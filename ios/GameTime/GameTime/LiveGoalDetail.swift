import SwiftUI

/// The live agreement screen. The compact visual summary is backed by the same
/// saved agreement, activity, consent and review operations as the challenge.
struct LiveGoalDetail: View {
    @Bindable var store: ChallengeV1Store
    let id: UUID
    var section: Section? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.challengeHealthFlow) private var health
    @State private var sheet: Section?
    @State private var target = ""
    @State private var username = ""
    @State private var consent = false
    @State private var exitAction: String?
    @State private var reviewReason = "wrong_total"
    @State private var communityReportSaved = false
    @State private var refreshing = false
    @ScaledMetric(relativeTo: .title2) private var headingSize = 25.0

    enum Section: String, Identifiable {
        case rules, agreement, activity, people, lobby, result, community
        var id: String { rawValue }
        var title: String {
            switch self {
            case .rules: "Full rules"
            case .agreement: "Review and agree"
            case .activity: "Your activity"
            case .people: "With you"
            case .lobby: "Set up your challenge"
            case .result: "Your result"
            case .community: "Community"
            }
        }
    }

    private var row: ChallengeV1? { store.challenges.first { $0.id == id } }
    private var canAct: Bool { row.map { store.isFresh($0) } == true && !store.busy && store.pending == nil }

    var body: some View {
        ScrollView {
            if let row {
                VStack(alignment: .leading, spacing: 18) {
                    if let section {
                        Text(section.title).font(.system(size: 26, weight: .bold)).tracking(-0.8)
                        sheetContent(section, row: row)
                    } else {
                        header(row)
                        hero(row)
                        agreementCards(row)
                        timeline(row)
                        stateActions(row)
                        actions(row)
                    }
                    recovery
                }.padding(.horizontal, 24).padding(.top, 11).padding(.bottom, 28)
            } else {
                VStack(spacing: 20) {
                    HStack { LiveRoundButton(symbol: "chevron.left", label: "Back") { dismiss() }; Spacer() }
                    ContentUnavailableView("Refresh this challenge", systemImage: "arrow.clockwise",
                        description: Text("Sign in to the same account and refresh to see its latest details."))
                    Button("Refresh activity") { Task { await refreshActivity() } }
                        .buttonStyle(LivePrimaryButtonStyle())
                }.padding(24)
            }
        }
        .background(SignalTheme.canvas)
        .foregroundStyle(SignalTheme.textPrimary)
        .toolbar(.hidden, for: .navigationBar)
        // The page draws one back control. Leaving the system button visible stacks a second one.
        .navigationBarBackButtonHidden(section == nil)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await refreshActivity() }
        .task(id: id) {
            await refreshActivity()
            #if DEBUG
            if LiveDesignFixtures.enabled, ProcessInfo.processInfo.arguments.contains("--live-screen=rules"),
               id == LiveDesignFixtures.activeID { sheet = .rules }
            #endif
        }
        .onDisappear { health?.cancel(id) }
        .onChange(of: row?.revision) { consent = false }
        .onChange(of: store.actor) {
            consent = false; target = ""; username = ""; exitAction = nil
            reviewReason = "wrong_total"; communityReportSaved = false; sheet = nil
        }
        .sheet(item: $sheet) { page in
            LiveGoalSheet(title: page.title) {
                if let row {
                    sheetContent(page, row: row)
                    recovery
                } else {
                    Text("Sign in to the same account and refresh to see this challenge.")
                }
            }
        }
        .confirmationDialog("Leave safely?", isPresented: Binding(
            get: { exitAction != nil }, set: { if !$0 { exitAction = nil } }), titleVisibility: .visible) {
                Button(exitAction == "cancel" ? "Cancel challenge" : "Leave challenge", role: .destructive) {
                    if let row, let action = exitAction { Task { await store.submit(op: action, challenge: row) } }
                    exitAction = nil
                }
            } message: {
                Text("Your simulated entry is returned. A shared challenge continues only if its agreed minimum remains. No real money moves.")
            }
    }

    private func header(_ row: ChallengeV1) -> some View {
        HStack(spacing: 10) {
            LiveRoundButton(symbol: "chevron.left", label: "Back to Home") { dismiss() }
            VStack(alignment: .leading, spacing: 4) {
                Text(LiveChallengePresentation.title(row))
                    .font(.system(size: headingSize, weight: .bold)).tracking(-1.1)
                    .lineLimit(2).minimumScaleFactor(0.8)
                Text(headerSummary(row))
                    .font(.system(size: 12.5, weight: .medium)).foregroundStyle(SignalTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func hero(_ row: ChallengeV1) -> some View {
        let member = row.own(store.actor)
        let saved = member.flatMap { row.savedScore($0) }
        let progress = LiveChallengePresentation.progress(row, actor: store.actor)
        let state = LiveChallengePresentation.state(row, actor: store.actor)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 6) {
                LiveMetric(value: LiveChallengePresentation.value(saved, metric: row.format.metric),
                           unit: LiveChallengePresentation.unit(row.format.metric), size: 104)
                    // Keep the font's natural line box. The compact 100pt layout
                    // slot should not make Text scale down a 104pt athletic metric.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: typeSize.isAccessibilitySize ? nil : 100).layoutPriority(1)
                VStack(alignment: .trailing, spacing: 12) {
                    Text(row.format.hasTarget ? "\(goalValue(row)) goal" : "Saved result")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(SignalTheme.textSecondary)
                        .multilineTextAlignment(.trailing)
                    LiveStateChip(text: state, warning: state == "Behind" || state == "Missed",
                                  neutral: saved == nil || !["active", "final"].contains(row.status))
                }.fixedSize(horizontal: true, vertical: true).layoutPriority(2)
            }.frame(minHeight: 100)
            if row.format.hasTarget && row.format.metric != .timed {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(SignalTheme.progressTrack)
                        Capsule().fill(SignalTheme.accent).frame(width: proxy.size.width * (progress ?? 0))
                    }
                }.frame(height: 18)
                    .accessibilityLabel("\(LiveChallengePresentation.value(saved, metric: row.format.metric)) of \(goalValue(row)) saved")
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(LiveChallengePresentation.remaining(row, actor: store.actor))
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 2)
                Text(endLabel(row)).font(.system(size: 12, weight: .medium)).foregroundStyle(SignalTheme.textSecondary)
            }.fixedSize(horizontal: false, vertical: true)
        }.padding(18).modifier(LiveCardModifier())
            .accessibilityElement(children: .contain).accessibilityIdentifier("live.goal.hero")
    }

    private func agreementCards(_ row: ChallengeV1) -> some View {
        VStack(spacing: 8) {
            Button { sheet = .activity } label: {
                verdict(symbol: "applewatch", label: "What counts", value: LiveGoalCopy.sourceTitle(row))
            }.buttonStyle(.plain)
            Button { sheet = .rules } label: {
                verdict(symbol: "checkmark.shield", label: row.format.hasTarget ? "If you miss" : "Your result",
                        value: row.format.hasTarget ? "Only a confirmed miss counts" : "Saved results decide")
            }.buttonStyle(.plain)
            Button { sheet = .rules } label: {
                verdict(symbol: "dollarsign", label: "Your stake", value: LiveGoalCopy.stake(row))
            }.buttonStyle(.plain)
        }
    }

    private func verdict(symbol: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 20, weight: .regular))
                .foregroundStyle(SignalTheme.accent).frame(width: 34, height: 34)
                .background(SignalTheme.accent.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(SignalTheme.textSecondary)
                Text(value).font(.system(size: 14, weight: .semibold)).tracking(-0.25)
                    .foregroundStyle(SignalTheme.textPrimary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.horizontal, 14).padding(.vertical, 11)
            .frame(minHeight: 60).modifier(LiveCardModifier(radius: 18, material: true))
            .accessibilityElement(children: .combine)
    }

    private func timeline(_ row: ChallengeV1) -> some View {
        let current = row.serverTime < row.config.startsAt ? 0 : row.serverTime < row.config.endsAt ? 1 : row.isClosed ? 3 : 2
        let labels = [row.agreement == nil ? "Your goal" : "Locked in",
                      row.config.days == 7 ? "Week starts" : "Starts",
                      row.config.days == 7 ? "Week ends" : "Ends", "Results settle"]
        let dates = [lockedLabel(row),
                     LiveGoalCopy.date(row.config.startsAt, row: row),
                     LiveGoalCopy.date(row.config.endsAt, row: row, end: true),
                     "From \(LiveGoalCopy.date(row.config.correctionsBy, row: row))"]
        return VStack(spacing: 10) {
            GeometryReader { proxy in
                let step = proxy.size.width / 4
                Path { path in
                    path.move(to: CGPoint(x: step / 2, y: 7))
                    path.addLine(to: CGPoint(x: proxy.size.width - step / 2, y: 7))
                }.stroke(SignalTheme.progressTrack, lineWidth: 2)
                if current < 3 {
                    Path { path in
                        path.move(to: CGPoint(x: step * (CGFloat(current) + 0.5), y: 7))
                        path.addLine(to: CGPoint(x: step * (CGFloat(current) + 1.5), y: 7))
                    }.stroke(SignalTheme.accent, lineWidth: 2)
                }
                HStack(spacing: 0) {
                    ForEach(0..<4) { index in
                        Circle().fill(index == current ? SignalTheme.accent : SignalTheme.textSecondary.opacity(0.3))
                            .frame(width: 6, height: 6).padding(4)
                            .background(SignalTheme.canvas, in: Circle())
                            .overlay(Circle().stroke(index == current ? SignalTheme.accent.opacity(0.2) : SignalTheme.divider, lineWidth: 1))
                            .frame(maxWidth: .infinity)
                    }
                }
            }.frame(height: 14).accessibilityHidden(true)
            HStack(alignment: .top, spacing: 0) {
                ForEach(0..<4) { index in
                    VStack(spacing: 5) {
                        Text(labels[index]).font(.system(size: 10, weight: .semibold))
                        Text(dates[index]).font(.system(size: 10.5))
                    }.foregroundStyle(index == current ? SignalTheme.accent : SignalTheme.textSecondary)
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                }
            }
        }.padding(.top, 3).padding(.bottom, 4).accessibilityLabel("Challenge timeline")
    }

    @ViewBuilder private func stateActions(_ row: ChallengeV1) -> some View {
        if needsConsent(row) {
            stateButton("Review and agree", subtitle: "Your agreement needs a final choice", symbol: "checkmark.shield") { sheet = .agreement }
        } else if row.status == "lobby_open" {
            stateButton("Choose your goal", subtitle: row.creatorId == store.actor ? "Goals, friends and invitation" : "Set the goal you’ll agree to", symbol: "flag") { sheet = .lobby }
        } else if row.notice != nil || row.final != nil || !row.reviews.isEmpty {
            stateButton(row.final == nil ? "Review your result" : "Result confirmed", subtitle: resultSubtitle(row), symbol: "checkmark.circle") { sheet = .result }
        } else if row.status == "consent_pending" {
            stateButton("Waiting for the group", subtitle: "Your agreement is saved", symbol: "person.2") { sheet = .people }
        }
        if row.socialHidden && row.format.mode == .friend {
            Text("Shared details are hidden. Your own records and safe actions remain available.")
                .font(.system(size: 13)).foregroundStyle(SignalTheme.textSecondary)
        }
    }

    private func stateButton(_ title: String, subtitle: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(SignalTheme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(SignalTheme.textSecondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
            }.foregroundStyle(SignalTheme.textPrimary).padding(14)
        }.buttonStyle(.plain).modifier(LiveCardModifier(radius: 16, material: true))
    }

    private func actions(_ row: ChallengeV1) -> some View {
        VStack(spacing: 8) {
            Button { sheet = .rules } label: {
                HStack { Text("Full rules"); Spacer(); Image(systemName: "chevron.right").font(.system(size: 15, weight: .medium)) }
            }.buttonStyle(LivePrimaryButtonStyle(height: 48)).accessibilityIdentifier("live.goal.rules")
            HStack(spacing: 8) {
                if !row.isClosed, row.own(store.actor)?.exited == false {
                    Button("Leave challenge") { exitAction = "leave" }
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(SignalTheme.danger)
                        .frame(maxWidth: .infinity, minHeight: 44).disabled(!canAct)
                        .accessibilityIdentifier("beta.leave")
                } else {
                    Button("With you") { sheet = .people }
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(SignalTheme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                Button { Task { await refreshActivity() } } label: {
                    Label(refreshing ? "Refreshing…" : "Refresh activity", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(SignalTheme.soft, in: RoundedRectangle(cornerRadius: 14))
                }.foregroundStyle(SignalTheme.accent).disabled(refreshing)
                    .accessibilityIdentifier("live.goal.refresh")
            }.buttonStyle(.plain)
        }
    }

    @ViewBuilder private var recovery: some View {
        if let error = store.error {
            Text(error).font(.system(size: 13)).foregroundStyle(SignalTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
        if store.pending != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("An action is waiting to finish").font(.system(size: 15, weight: .semibold))
                Button("Retry saved action") { Task { await store.retry() } }.buttonStyle(LivePrimaryButtonStyle())
                Button("Stop waiting for this action") { Task { await store.abandon() } }
                    .frame(minHeight: 44).font(.system(size: 14))
            }.padding(16).modifier(LiveCardModifier(radius: 18)).disabled(store.busy)
        }
    }

    @ViewBuilder private func sheetContent(_ page: Section, row: ChallengeV1) -> some View {
        switch page {
        case .rules:
            LiveGoalRules(row: row, actor: store.actor, accountMode: store.availability?.accountMode == true)
            if row.format.mode == .friend { stateButton("With you", subtitle: "People and activity", symbol: "person.2") { sheet = .people } }
            if row.format.mode == .community { stateButton("Community", subtitle: "People and reporting", symbol: "person.3") { sheet = .community } }
            management(row)
        case .agreement:
            LiveGoalRules(row: row, actor: store.actor, accountMode: store.availability?.accountMode == true)
            healthContent(row)
            Toggle("I have read the complete rules and agree", isOn: $consent)
                .font(.system(size: 15, weight: .medium)).tint(SignalTheme.accent)
                .accessibilityIdentifier("beta.consent.toggle")
            Button("Agree to this challenge") { Task {
                await store.submit(op: "consent", challenge: row,
                    fields: ["digest": .string(row.agreement?.digest ?? ""), "consent": .bool(true)])
                consent = false
                if store.pending == nil && store.error == nil { sheet = nil }
            }}.buttonStyle(LivePrimaryButtonStyle()).disabled(!needsConsent(row) || !consent || !canAct || !healthReady(row))
                .accessibilityIdentifier("beta.consent")
        case .activity: activityContent(row)
        case .people: peopleContent(row)
        case .lobby: lobbyContent(row)
        case .result: resultContent(row)
        case .community: communityContent(row)
        }
    }

    @ViewBuilder private func healthContent(_ row: ChallengeV1) -> some View {
        if let health, let actor = store.actor,
           let binding = try? ChallengeHealthBindingMapper.agreement(row, actor: actor),
           !row.isClosed, row.own(actor)?.exited == false {
            ChallengeHealthStatusView(flow: health, binding: binding,
                readiness: row.status == "consent_pending", receivedScores: row.format.usesReceivedScores)
                .padding(16).modifier(LiveCardModifier(radius: 18, material: true))
        }
    }

    @ViewBuilder private func activityContent(_ row: ChallengeV1) -> some View {
        LiveRuleModule(symbol: "applewatch", title: "What counts", subtitle: LiveGoalCopy.sourceTitle(row), expanded: true) {
            Text(row.sourcePolicyVersion.map { ChallengeHealthCopy.source($0, leaderboard: row.format.usesReceivedScores) }
                 ?? "Source: fictional activity for this local preview. No Apple Health activity is scored.")
                .font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
            if row.sourcePolicyVersion != nil, store.availability?.accountMode == true {
                Text(ChallengeHealthCopy.accountMode).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("live.goal.account-mode")
            }
        }
        if row.sourcePolicyVersion != nil, !row.format.hasTarget, !row.format.usesReceivedScores {
            LiveGoalFact(label: "Leaderboard — Not available yet", value: "We can’t confirm a complete activity history for a fair ranking. You can still review your records or leave this challenge safely.")
        }
        if row.format.usesReceivedScores {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your saved score").font(.headline)
                let saved = row.own(store.actor).flatMap { row.savedScore($0) }
                LiveMetric(value: LiveChallengePresentation.value(saved, metric: row.format.metric),
                           unit: LiveChallengePresentation.unit(row.format.metric), size: 60)
                    .accessibilityIdentifier("beta.leaderboard.saved-score")
                if saved == nil { Text("Unranked — no valid saved score").font(.system(size: 14)) }
                Text("Save activity by \(row.config.correctionsBy.text(zone: row.config.timezone)). Missing or late activity doesn’t count.")
                    .font(.system(size: 13)).foregroundStyle(SignalTheme.textSecondary)
            }.padding(16).modifier(LiveCardModifier(radius: 18))
        }
        if let fact = row.own(store.actor)?.fact {
            LiveGoalFact(label: fact.state == "value" || fact.state == "complete" ? "Saved activity" : "Activity not confirmed",
                         value: "Last saved update \(fact.recordedAt.text(zone: row.config.timezone))")
        }
        healthContent(row)
        Button("Refresh activity") { Task { await refreshActivity() } }.buttonStyle(LivePrimaryButtonStyle())
            .disabled(refreshing).accessibilityIdentifier("beta.leaderboard.refresh")
    }

    @ViewBuilder func peopleContent(_ row: ChallengeV1) -> some View {
        ForEach(row.rankedMembers) { person in
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    if row.showsRanking {
                        Text(ChallengePresentation.rank(person, in: row, actor: store.actor).map(String.init) ?? "—")
                            .font(.system(size: 18, weight: .bold)).monospacedDigit().frame(minWidth: 22)
                            .accessibilityLabel(ChallengePresentation.rank(person, in: row, actor: store.actor).map { "Rank \($0)" } ?? "Not ranked")
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(person.actorId == store.actor ? "You" : person.exited ? "Former participant" : person.username)
                            .font(.system(size: 16, weight: .semibold))
                        Text(person.exited ? "Left challenge" : person.consented ? "Agreed" : person.selected ? "Reviewing the rules" : "Requested to join")
                            .font(.system(size: 12)).foregroundStyle(SignalTheme.textSecondary)
                    }
                    Spacer()
                    if person.actorId != store.actor { ChallengePersonSafety(store: store, person: person) }
                }
                if !person.exited || person.actorId == store.actor {
                    LiveMetric(value: LiveChallengePresentation.value(row.savedScore(person), metric: row.format.metric),
                               unit: LiveChallengePresentation.unit(row.format.metric), size: 42)
                    if row.savedScore(person) == nil {
                        Text(person.fact == nil ? "No update yet" : "Activity unavailable")
                            .font(.system(size: 13)).foregroundStyle(SignalTheme.textSecondary)
                    }
                    if let target = person.target { Text("Goal: \(row.format.metric.display(target))").font(.system(size: 13)).foregroundStyle(SignalTheme.textSecondary) }
                    if let fact = person.fact {
                        Text("Updated \(fact.recordedAt.text(zone: row.config.timezone))")
                            .font(.system(size: 12)).foregroundStyle(SignalTheme.textSecondary)
                    }
                } else {
                    Text("Activity hidden").font(.system(size: 12)).foregroundStyle(SignalTheme.textSecondary)
                }
                if let outcome = row.final?.result.participants?[person.actorId.uuidString.lowercased()]?.status {
                    LiveStateChip(text: resultText(outcome), warning: outcome == "missed", neutral: !["met", "winner", "missed"].contains(outcome))
                }
                if row.status == "lobby_open", row.creatorId == store.actor, person.actorId != store.actor, !person.exited {
                    Button(person.selected ? "Remove from roster" : "Select for roster") { Task {
                        await store.submit(op: "select", challenge: row,
                            fields: ["actor_id": .string(person.actorId.uuidString.lowercased()), "selected": .bool(!person.selected)])
                    }}.buttonStyle(LivePrimaryButtonStyle()).disabled(!canAct)
                        .accessibilityIdentifier("beta.select.\(person.username)")
                    if !person.selected {
                        Button("Decline request") { Task {
                            await store.submit(op: "reject", challenge: row, fields: ["actor_id": .string(person.actorId.uuidString.lowercased())])
                        }}.frame(minHeight: 44).disabled(!canAct)
                    }
                }
            }.padding(16).modifier(LiveCardModifier(radius: 18, material: true))
        }
        if row.socialHidden { Text("Shared details are hidden. Your own record stays available.").font(.system(size: 13)).foregroundStyle(SignalTheme.textSecondary) }
    }

    @ViewBuilder private func lobbyContent(_ row: ChallengeV1) -> some View {
        if row.format.hasTarget, row.own(store.actor)?.exited == false {
            VStack(alignment: .leading, spacing: 14) {
                Text("Choose your own goal").font(.system(size: 20, weight: .bold)).tracking(-0.5)
                Text("\(SignalDateSpan.duration(row.config.days)) · \(SignalTimeZone.name(row.config.timezone))")
                    .font(.system(size: 13)).foregroundStyle(SignalTheme.textSecondary)
                TextField(row.format.metric.targetPrompt, text: $target)
                    .keyboardType(.numbersAndPunctuation).font(.system(size: 30, weight: .bold))
                    .padding(14).background(SignalTheme.soft, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel(row.format.metric.targetPrompt).accessibilityIdentifier("beta.target.input")
                if !target.isEmpty, row.format.metric.parse(target) == nil {
                    Text(row.format.metric.inputHelp).font(.system(size: 13)).foregroundStyle(SignalTheme.danger)
                }
                if let health, let actor = store.actor, let source = row.sourcePolicyVersion,
                   let planning = try? ChallengeHealthBindingMapper.planning(actor: actor, id: row.id, policy: row.format,
                        window: row.config, source: source, draft: target + "|" + String(row.revision)) {
                    ChallengeHealthSuggestionView(flow: health, binding: planning, policy: row.format, days: row.config.days) {
                        target = row.format.metric.inputValue($0)
                    }
                }
                Button("Propose my goal") { Task {
                    if let value = row.format.metric.parse(target) {
                        await store.submit(op: "target", challenge: row, fields: ["target": .integer(value)])
                    }
                }}.buttonStyle(LivePrimaryButtonStyle()).disabled(!canAct || row.format.metric.parse(target) == nil)
                    .accessibilityIdentifier("beta.target.submit")
            }
        }
        if row.creatorId == store.actor {
            NavigationLink {
                ChallengeCreationInviteView(store: store, challengeID: row.id)
            } label: {
                Label("Invite friends", systemImage: "person.2").frame(maxWidth: .infinity, minHeight: 48)
            }.buttonStyle(LivePrimaryButtonStyle()).accessibilityIdentifier("beta.invite.open")
            LiveRuleModule(symbol: "person.badge.plus", title: "Invite by username", subtitle: "Send to one friend") {
                TextField("Exact friend username", text: $username).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().padding(12).background(SignalTheme.soft, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("beta.invite.input")
                Button("Invite friend") { Task {
                    await store.submit(op: "invite", challenge: row, fields: ["username": .string(username)])
                    if store.pending == nil { username = "" }
                }}.buttonStyle(LivePrimaryButtonStyle()).disabled(!canAct || username.isEmpty)
                    .accessibilityIdentifier("beta.invite.submit")
            }
            // Links stay closed unless the server opens them.
            if store.linksAvailable {
                LiveRuleModule(symbol: "link", title: "Invite with a link", subtitle: "Choose when to share") {
                    ChallengeLinkIssuer(store: store, row: row)
                }
            }
            peopleContent(row)
            Button(row.format.hasTarget ? "Lock in roster and goals" : "Lock in roster") { Task {
                await store.submit(op: "freeze", challenge: row)
                if store.pending == nil && store.error == nil { sheet = nil }
            }}.buttonStyle(LivePrimaryButtonStyle()).disabled(!canAct).accessibilityIdentifier("beta.freeze")
        } else { peopleContent(row) }
    }

    @ViewBuilder private func management(_ row: ChallengeV1) -> some View {
        if row.format.mode == .friend, row.creatorId == store.actor,
           ["consent_pending", "scheduled"].contains(row.status) {
            LiveRuleModule(symbol: "person.2", title: "Change the group or goals", subtitle: "Everyone agrees again") {
                Button("Reopen lobby and ask everyone again") { Task {
                    await store.submit(op: "reopen", challenge: row)
                    if store.pending == nil && store.error == nil { sheet = .lobby }
                }}.buttonStyle(LivePrimaryButtonStyle()).disabled(!canAct)
            }
        }
        if !row.isClosed, row.own(store.actor)?.exited == false,
           row.creatorId == store.actor, row.serverTime < row.config.startsAt {
            Button("Cancel challenge", role: .destructive) { exitAction = "cancel" }
                .font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 44).disabled(!canAct)
        }
    }

    @ViewBuilder func resultContent(_ row: ChallengeV1) -> some View {
        if let final = row.final {
            allocation(final.result, row: row, confirmed: true)
            LiveGoalFact(label: "Result confirmed", value: final.recordedAt.text(zone: row.config.timezone))
        }
        if let notice = row.notice {
            LiveRuleModule(symbol: "checkmark.circle", title: row.final == nil ? "Latest result update" : "Earlier result update",
                           subtitle: notice.recordedAt.text(zone: row.config.timezone), expanded: row.final == nil) {
                if let result = notice.result { allocation(result, row: row, confirmed: false) }
                LiveGoalFact(label: "Review by", value: notice.reviewBy.text(zone: row.config.timezone))
                if row.status == "review", row.serverTime < notice.reviewBy,
                   !row.reviews.contains(where: { $0.noticeRevision == notice.revision }) {
                    Picker("Reason", selection: $reviewReason) {
                        Text("My total looks wrong").tag("wrong_total")
                        Text("Activity is missing").tag("missing_activity")
                        Text("My result looks wrong").tag("wrong_result")
                    }.pickerStyle(.menu).disabled(!canAct)
                    Button("Ask us to review") { Task {
                        await store.submit(op: "review", challenge: row,
                            fields: ["notice_revision": .integer(notice.revision), "reason": .string(reviewReason)])
                    }}.buttonStyle(LivePrimaryButtonStyle()).disabled(!canAct).accessibilityIdentifier("beta.review")
                }
            }
        }
        ForEach(row.reviews) { review in
            VStack(alignment: .leading, spacing: 10) {
                Text("Your review").font(.system(size: 16, weight: .semibold))
                if row.final == nil {
                    Text(review.decision != nil ? "Review complete. Refresh for the latest result." :
                         row.serverTime >= review.resolveBy ? "Review time has ended. Refresh to see your updated result and simulated return." :
                         "Your review request is saved. We’re checking your result.").font(.system(size: 14))
                }
                Text("Requested \(review.filedAt.text(zone: row.config.timezone))")
                    .font(.system(size: 12)).foregroundStyle(SignalTheme.textSecondary)
            }.padding(16).modifier(LiveCardModifier(radius: 18, material: true))
        }
        Button("Refresh result") { Task { await refreshActivity() } }.buttonStyle(LivePrimaryButtonStyle()).disabled(refreshing)
    }

    private func allocation(_ result: ChallengeV1.Allocation, row: ChallengeV1, confirmed: Bool) -> some View {
        let own = store.actor.flatMap { result.participants?[$0.uuidString.lowercased()] } ?? result.own
        return VStack(alignment: .leading, spacing: 14) {
            if let own {
                LiveStateChip(text: resultText(own.status), warning: own.status == "missed", neutral: !["met", "winner", "missed"].contains(own.status))
                LiveGoalFact(label: confirmed ? "Recorded simulated return" : "Proposed simulated return", value: challengeMoney(own.returnedCents))
                    .accessibilityIdentifier(confirmed ? "beta.result.return" : "beta.result.proposed-return")
            }
            if let cents = result.unallocatedCents { LiveGoalFact(label: "Unallocated simulation", value: challengeMoney(cents)) }
            Text("Nothing can be paid out or redeemed. No real money moved.")
                .font(.system(size: 12)).foregroundStyle(SignalTheme.textSecondary)
        }.padding(16).modifier(LiveCardModifier(radius: 18))
    }

    func communityContent(_ row: ChallengeV1) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text((row.counts ?? .init(joined: nil)).text(at: row.serverTime)).font(.system(size: 14))
            Text("Reports about this community go to its assigned moderator.")
                .font(.system(size: 13)).foregroundStyle(SignalTheme.textSecondary)
            Button("Report unsafe behavior in this community") { Task {
                let actor = store.actor
                guard !store.busy, store.pending == nil else { return }
                await store.submit(op: "report_scoped", fields: ["id": .string(row.id.uuidString.lowercased()), "subject": .null, "reason": .string("unsafe_behavior")])
                if store.actor == actor, store.pending == nil, store.error == nil, store.lastReceipt?.saved == true { communityReportSaved = true }
            }}.buttonStyle(LivePrimaryButtonStyle()).disabled(store.busy || store.pending != nil)
            if communityReportSaved { Text("Your community report is saved.").font(.system(size: 14)) }
        }
    }

    private func refreshActivity() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        await store.loadDetail(id)
        if row?.sourcePolicyVersion != nil { await health?.refresh(id) }
    }
    private func needsConsent(_ row: ChallengeV1) -> Bool {
        row.status == "consent_pending" && row.own(store.actor).map { $0.selected && !$0.exited && !$0.consented } == true
    }
    private func goalValue(_ row: ChallengeV1) -> String {
        guard let target = row.own(store.actor)?.target else { return row.format.metric.title }
        return row.format.metric.display(target)
    }
    private func headerSummary(_ row: ChallengeV1) -> String {
        let days = "\(row.config.days) \(row.config.days == 1 ? "day" : "days")"
        if let distance = row.config.distanceMm {
            let time = row.format.hasTarget ? "Under \(goalValue(row))" : "Fastest run"
            return "\(ChallengeV1Policy.Metric.distance.display(distance)) · \(time) · \(days) · \(ChallengePresentation.dates(row))"
        }
        return "\(goalValue(row)) over \(days) · \(ChallengePresentation.dates(row))"
    }
    private func healthReady(_ row: ChallengeV1) -> Bool {
        guard row.sourcePolicyVersion != nil else { return true }
        guard let actor = store.actor, let binding = try? ChallengeHealthBindingMapper.agreement(row, actor: actor) else { return false }
        return health?.canConsent(binding) == true
    }
    private func endLabel(_ row: ChallengeV1) -> String {
        if row.serverTime < row.config.startsAt { return "Starts \(LiveGoalCopy.date(row.config.startsAt, row: row))" }
        return "\(row.isClosed ? "Ended" : "Ends") \(LiveGoalCopy.date(row.config.endsAt, row: row, template: "EEEE", end: true))"
    }
    private func lockedLabel(_ row: ChallengeV1) -> String {
        #if DEBUG
        if LiveDesignFixtures.enabled, let locked = LiveDesignFixtures.lockedDate(for: row.id) {
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(identifier: row.config.timezone)
            formatter.setLocalizedDateFormatFromTemplate("MMM d")
            return formatter.string(from: locked)
        }
        #endif
        return row.agreement == nil ? "Choose" : "Agreed"
    }
    private func resultSubtitle(_ row: ChallengeV1) -> String {
        if let final = row.final { return "Recorded \(LiveGoalCopy.date(final.recordedAt, row: row))" }
        if let notice = row.notice { return "Review by \(LiveGoalCopy.date(notice.reviewBy, row: row))" }
        return "Your review request is saved"
    }
    private func resultText(_ status: String) -> String {
        switch status {
        case "met": "Goal met"
        case "missed": "Goal missed"
        case "winner": "Winning result"
        case "placed": "Result recorded"
        case "unranked": "Unranked — your simulated entry returns"
        default: "Your entry returns"
        }
    }
}

private struct LiveGoalSheet<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text(title).font(.system(size: 26, weight: .bold)).tracking(-0.8)
                        Spacer()
                        LiveRoundButton(symbol: "xmark", label: "Close") { dismiss() }
                    }.padding(.bottom, 2)
                    content()
                }.padding(24)
            }.background(SignalTheme.canvas).foregroundStyle(SignalTheme.textPrimary)
                .toolbar(.hidden, for: .navigationBar)
                .scrollDismissesKeyboard(.interactively)
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
            .presentationCornerRadius(28).tint(SignalTheme.accent)
    }
}
