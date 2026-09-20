import SwiftUI
import GameTimeCore

extension EnvironmentValues {
    @Entry var challengeInvitationLinks = ChallengeInvitation()
    @Entry var challengeHealthFlow: ChallengeHealthFlowStore? = nil
}

struct ChallengeForm<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) { content }
                .padding(SignalTheme.contentInset).frame(maxWidth: .infinity, alignment: .leading)
                .modifier(SignalGlassGroup())
        }.modifier(ChallengeScrollLegibility()).background(SignalTheme.canvas)
            .textFieldStyle(.roundedBorder)
            .buttonStyle(ChallengeActionStyle())
            .scrollDismissesKeyboard(.interactively)
    }
}
struct ChallengeFormSection<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.bold()).foregroundStyle(SignalTheme.textPrimary).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 18) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 24)
                .overlay(alignment: .bottom) { Rectangle().fill(SignalTheme.divider).frame(height: 1) }
        }
    }
}

struct ChallengeIntegerControl: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let id: String
    let title: String
    let display: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(display).font(.body).fixedSize(horizontal: false, vertical: true)
            Stepper(title, value: $value, in: range).labelsHidden().accessibilityValue("\(value)").accessibilityIdentifier("beta.stepper." + id)
        }
    }
}

struct ChallengeAgreementText: View {
    let policy: ChallengeV1Policy; let window: ChallengeV1.Window; let minimum: Int
    var sourcePolicy: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(policy.scoring)
            if let sourcePolicy {
                Text(ChallengeHealthCopy.source(sourcePolicy))
                Text("An observed result can confirm that you met your goal. Missing or incomplete activity cannot confirm a missed goal or a ranking.")
                if let distance = window.distanceMm {
                    Text("Whole outdoor run: \(ChallengeV1Policy.Metric.distance.display(distance)) to \(ChallengeV1Policy.Metric.distance.display(distance * 102 / 100)), including both distances. The whole run must fit inside these dates. Time from start to finish includes pauses.")
                }
            } else {
                Text("Source: fictional activity for this local preview. No Apple Health activity is scored.")
                if let distance = window.distanceMm { Text("Whole run distance: \(ChallengeV1Policy.Metric.distance.display(distance)). Only fictional matching runs are available until the distance rules pass physical testing.") }
            }
            SignalDateSpan(window: window)
            Text("Initial updates through \(window.syncBy.text(zone: window.timezone)). Corrections through \(window.correctionsBy.text(zone: window.timezone)).")
            Text("\(challengeMoney(window.amountCents)) simulated per person. Nothing can be paid out or redeemed. No real money moves.")
            Text(policy.missing)
            Text(policy.allocation)
            Text("You may leave before the result is final. Your simulated entry returns. The challenge continues only if at least \(minimum) eligible \(minimum == 1 ? "person remains" : "people remain").")
            Text("You have 48 hours after the actual result notice to ask for a review. Reviewers have 72 hours after your request. A processing delay never shortens those windows.")
            if policy.mode == .friend {
                Text("Everyone agrees to the displayed roster and goals, when this format has goals. Reopening the lobby requires everyone to agree again. Incomplete agreement at the start cancels the challenge.")
            }
            if policy.mode == .friend {
                Text("The selected friends can see your username, agreed goal when there is one, current challenge activity and results. Your activity history outside this challenge stays private.")
            } else {
                Text("Other participants cannot see your activity or results. Community challenges show anonymous participant counts.")
            }
            Text("An assigned reviewer can inspect the normalized challenge facts needed for your review. Raw Apple Health records are not shared.")
            Text("Up to three unfinished challenges at once. Friend challenges for the same activity cannot overlap. One community challenge may overlap your friend steps challenge.")
        }.font(.subheadline).fixedSize(horizontal: false, vertical: true)
    }
}

struct ChallengeV1Create: View {
    @Bindable var store: ChallengeV1Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.challengeHealthFlow) private var health
    @State private var draftID = UUID()
    @State private var mode = ChallengeV1Policy.Mode.friend
    @State private var metric = ChallengeV1Policy.Metric.steps
    @State private var competition = ChallengeV1Policy.Competition.goal
    @State private var start = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
    @State private var days = 7
    @State private var dollars = 20
    @State private var zone = TimeZone.current.identifier
    @State private var distance = ""
    @State private var target = ""
    @State private var preview: ChallengeV1.Agreement?
    @State private var consent = false
    @State private var previewError: String?
    @State private var reading = false
    private let personalStepsOnly: Bool
    init(store: ChallengeV1Store, initialPolicy: ChallengeV1Policy? = nil, personalStepsOnly: Bool = false) {
        self.store = store
        self.personalStepsOnly = personalStepsOnly
        if personalStepsOnly {
            _mode = State(initialValue: .personal)
            _metric = State(initialValue: .steps)
            _competition = State(initialValue: .goal)
        } else if let initialPolicy {
            _mode = State(initialValue: initialPolicy.mode)
            _metric = State(initialValue: initialPolicy.metric)
            _competition = State(initialValue: initialPolicy.competition)
        }
    }
    private var policy: ChallengeV1Policy { ChallengeV1Policy(rawValue: "\(mode.rawValue)_\(metric.rawValue)_\(mode == .personal ? "goal" : competition.rawValue)_v1")! }
    private var config: ChallengeJSON {
        let fmt = DateFormatter(); fmt.timeZone = TimeZone(identifier: zone); fmt.dateFormat = "yyyy-MM-dd"
        var fields: [String: ChallengeJSON] = ["start_date": .string(fmt.string(from: start)), "days": .integer(days), "timezone": .string(zone), "amount_cents": .integer(dollars * 100)]
        if metric == .timed, let value = ChallengeV1Policy.Metric.distance.parse(distance) { fields["distance_mm"] = .integer(value) }
        return .object(fields)
    }
    private var draft: String { "\(policy.id)|\(start)|\(days)|\(dollars)|\(zone)|\(distance)|\(target)" }
    private var selectedSource: ChallengeHealthRealSourcePolicy? { ChallengeHealthBindingMapper.selectedSource(metric) }
    private var unavailable: Bool { health != nil && (!policy.hasTarget || selectedSource == nil) }
    private var sourceFields: [String: ChallengeJSON] { health != nil ? selectedSource.map { ["source_policy_version": .string($0.identifier)] } ?? [:] : [:] }
    private var planningBinding: ChallengeHealthBinding? {
        guard let actor = store.actor, let selectedSource else { return nil }
        return try? ChallengeHealthBindingMapper.planningDraft(actor: actor, id: draftID, policy: policy,
            config: config, source: selectedSource.identifier, draft: draft)
    }
    private var healthBinding: ChallengeHealthBinding? {
        guard let actor = store.actor, let preview, let window = decodeWindow(preview.terms?["config"]),
              let source = selectedSource else { return nil }
        return try? ChallengeHealthBindingMapper.binding(actor: actor, id: draftID, version: 1, digest: preview.digest,
            policy: policy, window: window, source: source.identifier)
    }
    private var readinessAcknowledged: Bool { health == nil || healthBinding.map { health?.canConsent($0) == true } == true }
    private var canSubmit: Bool { !unavailable && !store.busy && store.pending == nil && !reading && store.access?.ageConfirmed == true && (metric != .timed || ChallengeV1Policy.Metric.distance.parse(distance) != nil) }
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ChallengeForm {
                if !personalStepsOnly {
                ChallengeFormSection("Choose your challenge") {
                    Picker("Who", selection: $mode) {
                        Text("With friends").tag(ChallengeV1Policy.Mode.friend)
                        Text("Personal goal").tag(ChallengeV1Policy.Mode.personal)
                    }.accessibilityIdentifier("beta.create.mode")
                    Picker("Activity", selection: $metric) {
                        ForEach(ChallengeV1Policy.Metric.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("beta.create.metric")
                    if mode == .friend {
                        Picker("Format", selection: $competition) {
                            ForEach(ChallengeV1Policy.Competition.allCases, id: \.self) { Text($0 == .goal ? "Goal" : "Leaderboard").tag($0) }
                        }.accessibilityIdentifier("beta.create.competition")
                        Text(policy.hasTarget ? "Each friend chooses a goal before you lock in the roster and ask everyone to agree." : health != nil ? "We can’t confirm a complete activity history for a fair ranking. You can choose a goal instead." : "Choose the roster, then everyone agrees. The best result wins; equal best results share the win.")
                    } else { Text("Choose your own goal and review the agreement. Only you can see your activity and result.") }
                }
                }
                if unavailable {
                    ContentUnavailableView(policy.hasTarget ? "Activity not available yet" : "Leaderboard — Not available yet",
                        systemImage: "clock", description: Text(policy.hasTarget ? "We can’t use this activity for a new goal yet. Choose another activity." : "We can’t confirm everyone’s complete activity history for a fair ranking. Choose a goal to continue."))
                } else {
                ChallengeFormSection("Dates and amount") {
                    DatePicker(selection: $start, displayedComponents: .date) { Text("Starts").font(.body) }
                    ChallengeIntegerControl(value: $days, range: 1...30, id: "days", title: "Duration", display: "\(days) days")
                    LabeledContent("Time zone") {
                        TextField("Area/City", text: $zone, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityLabel("Time zone")
                    }
                    ChallengeIntegerControl(value: $dollars, range: 1...500, id: "amount", title: "Simulated dollars", display: "\(challengeMoney(dollars * 100)) simulated each")
                    Text("Starts in 2–30 calendar days. Each day runs midnight to midnight in the selected time zone. Simulated stakes — no real money moves.").font(.body).fixedSize(horizontal: false, vertical: true)
                    if metric == .timed {
                        Text("Whole run kilometres").font(.headline)
                        TextField("Whole run kilometres", text: $distance).keyboardType(.decimalPad).accessibilityIdentifier("beta.create.distance")
                        if !distance.isEmpty && ChallengeV1Policy.Metric.distance.parse(distance) == nil { Text(ChallengeV1Policy.Metric.distance.inputHelp).font(.subheadline) }
                    }
                }
                if mode == .personal {
                    ChallengeFormSection("Your goal") {
                        Text(metric.targetPrompt).font(.headline)
                        TextField(metric.targetPrompt, text: $target).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("beta.create.target")
                        if !target.isEmpty && metric.parse(target) == nil { Text(metric.inputHelp).font(.subheadline) }
                        if let health, let planningBinding {
                            ChallengeHealthSuggestionView(flow: health, binding: planningBinding, policy: policy, days: days) {
                                target = metric.inputValue($0)
                            }
                        }
                        Text("Choose your own goal. A suggestion will appear only when eligible activity is available on this phone.").font(.body).fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Review my agreement") { Task {
                        if await readPreview() {
                            await Task.yield()
                            withAnimation { proxy.scrollTo("beta.personal.agreement", anchor: .top) }
                        }
                    } }.disabled(reading).accessibilityIdentifier("beta.personal.preview")
                    if reading { ProgressView("Loading your agreement…") }
                    if let previewError {
                        Text(previewError).foregroundStyle(SignalTheme.textSecondary).accessibilityIdentifier("beta.personal.preview.error")
                    }
                    if let preview, let window = decodeWindow(preview.terms?["config"]) {
                        ChallengeFormSection("Your complete agreement") {
                            if let goal = metric.parse(target) { SignalTargetBand(value: goal, metric: metric) }
                            ChallengeAgreementText(policy: policy, window: window, minimum: 1, sourcePolicy: health != nil ? selectedSource?.identifier : nil)
                            if let health, let binding = healthBinding {
                                ChallengeHealthStatusView(flow: health, binding: binding, readiness: true)
                            }
                            Toggle("I have read the complete rules and agree", isOn: $consent).accessibilityIdentifier("beta.personal.consent")
                            Button("Start my personal goal") { Task {
                                guard let value = metric.parse(target) else { return }
                                await store.submit(op: "personal_commit", fields: sourceFields.merging(["policy": .string(policy.id), "config": config, "target": .integer(value), "digest": .string(preview.digest), "consent": .bool(true)], uniquingKeysWith: { _, value in value }))
                                if store.pending == nil && store.lastReceipt?.status == "scheduled" { dismiss() }
                            }}.disabled(!canSubmit || !consent || !readinessAcknowledged).accessibilityIdentifier("beta.personal.commit")
                        }.id("beta.personal.agreement")
                    }
                } else {
                    Button("Create lobby") { Task {
                        await store.submit(op: "create", fields: sourceFields.merging(["policy": .string(policy.id), "config": config], uniquingKeysWith: { _, value in value }))
                        if store.pending == nil && store.lastReceipt?.status == "lobby_open" { dismiss() }
                    }}.disabled(!canSubmit).accessibilityIdentifier("beta.create.submit")
                }
                }
                if store.access?.ageConfirmed != true { Text("Confirm that you are 21 or older in Challenges before continuing.") }
                if store.busy { ProgressView("Saving your action…") }
                if let error = store.error { Text(error) }
            }.safeAreaInset(edge: .top, spacing: 0) { SignalSimulationBanner() }
                .navigationTitle(mode == .personal ? "Personal goal" : "Friend challenge")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) }
                .task {
                    let now = await health?.planningDate() ?? store.access?.serverTime?.date
                    if let now { start = Calendar.current.date(byAdding: .day, value: 2, to: now)! }
                }
                .onChange(of: draft) { preview = nil; consent = false; previewError = nil; health?.invalidateDraft(draftID) }
                .onDisappear { health?.cancel(draftID) }
                .onChange(of: store.actor) { dismiss() }
            }
        }
    }
    private func readPreview() async -> Bool {
        guard let actor = store.actor else {
            previewError = "Sign in again before reviewing your agreement."
            return false
        }
        guard let value = metric.parse(target) else {
            previewError = target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Enter your goal before reviewing your agreement."
                : metric.inputHelp
            return false
        }
        let before = draft; reading = true; previewError = nil
        defer { reading = false }
        do {
            var fields: [String: ChallengeJSON] = ["p_policy": .string(policy.id), "p_config": config, "p_target": .integer(value)]
            if health != nil, let selectedSource { fields["p_source_policy_version"] = .string(selectedSource.identifier) }
            let result = try await store.client.read("challenge_personal_preview_v1", fields: fields, actor: actor, as: ChallengeV1.Agreement.self)
            guard actor == store.actor && draft == before else { return false }
            guard decodeWindow(result.terms?["config"]) != nil else {
                previewError = "We couldn’t show your agreement. Try again."
                return false
            }
            preview = result; consent = false
            return true
        } catch {
            previewError = (error as? ChallengeV1Error ?? .unavailable).localizedDescription
            return false
        }
    }
}

func decodeWindow(_ value: ChallengeJSON?) -> ChallengeV1.Window? {
    guard let value, let data = try? ChallengeJSON.data(value) else { return nil }
    let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try? decoder.decode(ChallengeV1.Window.self, from: data)
}

struct ChallengeEntryPanel: View {
    @Bindable var store: ChallengeV1Store
    @Bindable var invitation: ChallengeInvitationIntent
    @State private var age = false
    var body: some View {
        if store.access?.ageConfirmed != true {
            Toggle("I confirm I am 21 or older", isOn: $age).accessibilityIdentifier("beta.age.toggle")
            Button("Save age confirmation") { Task { await store.submit(op: "confirm_age", fields: ["confirmed": .bool(true)]) } }
                .disabled(!age || store.busy || store.pending != nil).accessibilityIdentifier("beta.age.submit")
        }
        TextField("Invitation link", text: $invitation.link).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
        Button("Use invitation") { Task { await useInvitation() } }
            .disabled(invitation.links.token(from: invitation.link) == nil || store.actor == nil || store.access?.ageConfirmed != true || store.busy || store.pending != nil)
        Text("An invitation grants beta access and requests a place in the lobby. The creator still chooses the roster. You agree separately. It does not add a friend.").font(.body).fixedSize(horizontal: false, vertical: true)
        if let error = store.entryError { Text(error).font(.body).fixedSize(horizontal: false, vertical: true) }
        ForEach(store.communities) { row in
            NavigationLink("Community steps") { ChallengeCommunityJoin(store: store, community: row) }
        }
    }
    func useInvitation() async {
        let submittedLink = invitation.link
        guard let token = invitation.links.token(from: submittedLink), let actor = store.actor,
              store.access?.ageConfirmed == true, !store.busy, store.pending == nil else { return }
        let receipt = await store.submit(op: "redeem_link", fields: ["token": .string(token)])
        guard store.actor == actor, receipt?.id != nil, receipt?.status == "pending_request" else { return }
        invitation.clear(ifMatching: submittedLink)
    }
}

struct ChallengeCommunityJoin: View {
    @Bindable var store: ChallengeV1Store
    @Environment(\.challengeHealthFlow) private var health
    let community: ChallengeV1Community
    @State private var consent = false
    private var binding: ChallengeHealthBinding? {
        guard let actor = store.actor, let window = decodeWindow(community.terms["config"]),
              let source = community.terms["source_policy_version"]?.string else { return nil }
        return try? ChallengeHealthBindingMapper.binding(actor: actor, id: community.id, version: 1, digest: community.digest,
            policy: ChallengeV1Policy(rawValue: "community_steps_goal_v1")!, window: window, source: source)
    }
    var body: some View {
        ChallengeForm {
            Text("Only your progress and result appear here.")
            Text((community.counts ?? .init(joined: nil)).text(at: community.serverTime))
            if let target = community.terms["common_target"]?.integer { Text("Everyone’s goal: \(target.formatted()) steps").font(.headline) }
            if let window = decodeWindow(community.terms["config"]) {
                ChallengeAgreementText(policy: ChallengeV1Policy(rawValue: "community_steps_goal_v1")!, window: window, minimum: community.terms["minimum"]?.integer ?? 2, sourcePolicy: community.terms["source_policy_version"]?.string)
            }
            Toggle("I have read the complete rules and agree", isOn: $consent)
            if let health, let binding { ChallengeHealthStatusView(flow: health, binding: binding, readiness: true) }
            Button("Join community challenge") { Task {
                await store.submit(op: "join_community", fields: ["id": .string(community.id.uuidString.lowercased()), "digest": .string(community.digest), "consent": .bool(true)])
                consent = false
            }}.disabled(!consent || (community.terms["source_policy_version"] != nil && binding.map { health?.canConsent($0) == true } != true) || !store.entryFresh || store.access?.ageConfirmed != true || store.busy || store.pending != nil)
            if let error = store.error { Text(error) }
            if store.challenges.contains(where: { $0.id == community.id }) { Text("You have joined. Find your own progress in Home.") }
        }.navigationTitle("Community steps")
            .onChange(of: store.actor) { consent = false }
    }
}

struct ChallengeLinkIssuer: View {
    @Bindable var store: ChallengeV1Store
    let row: ChallengeV1
    @Environment(\.challengeInvitationLinks) private var links
    var body: some View {
        Button("Create invitation link") { Task {
            await store.submit(op: "issue_link", fields: ["id": .string(row.id.uuidString.lowercased())])
        }}.disabled(!links.canFormat || !store.fresh || store.busy || store.pending != nil)
        if !links.canFormat {
            Text("Invitation links aren’t available yet. Try again later.")
        }
        ForEach(store.issuedLinks.filter { $0.actorId == store.actor && $0.challengeId == row.id && row.creatorId == store.actor }) { issued in
            if let url = links.url(for: issued.token) {
                Text(url.absoluteString).textSelection(.enabled).privacySensitive()
            }
            Text("Up to 20 different accounts, for at most 30 days while the lobby is open.").font(.body).fixedSize(horizontal: false, vertical: true)
            Button("Revoke invitation link") { Task {
                await store.submit(op: "revoke_link", fields: ["id": .string(issued.id.uuidString.lowercased())])
            }}.disabled(store.busy || store.pending != nil)
        }
    }
}

struct ChallengePersonSafety: View {
    @Bindable var store: ChallengeV1Store
    let person: ChallengeV1.Member
    @State private var block = false
    var body: some View {
        Menu("Report or block") {
            Button("Report username") { report("username") }
            Button("Report unwanted contact") { report("unwanted_contact") }
            Button("Report unsafe behavior") { report("unsafe_behavior") }
            Button("Block this account", role: .destructive) { block = true }
        }.disabled(store.busy || store.pending != nil)
            .confirmationDialog("Block this account?", isPresented: $block, titleVisibility: .visible) {
                Button("Block account", role: .destructive) { Task { await store.submit(op: "block", fields: ["subject": .string(person.actorId.uuidString.lowercased())]) } }
            } message: { Text("Shared details are hidden and affected participation ends safely. Previous final results remain in your own history.") }
    }
    private func report(_ reason: String) { Task { await store.submit(op: "report", fields: ["subject": .string(person.actorId.uuidString.lowercased()), "reason": .string(reason)]) } }
}
