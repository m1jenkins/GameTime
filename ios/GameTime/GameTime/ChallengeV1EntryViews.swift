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
                Text(ChallengeHealthCopy.source(sourcePolicy, leaderboard: policy.usesReceivedScores))
                if policy.usesReceivedScores {
                    Text("We rank what GameTime saves, without checking that your entire Apple Health history is available. Refresh to send activity and check your saved score. An update counts only after GameTime confirms it.")
                    Text("If we can’t save an update, use Refresh to recover it. If your result is still wrong, ask us to review it before the review deadline.")
                } else {
                    Text("An observed result can confirm that you met your goal. Missing or incomplete activity cannot confirm a missed goal or a ranking.")
                }
                if let distance = window.distanceMm {
                    Text("Whole outdoor run: \(ChallengeTimedDistanceCopy.range(distance)), including both distances. The whole run must fit inside these dates. Time from start to finish includes pauses.")
                }
            } else {
                Text("Source: fictional activity for this local preview. No Apple Health activity is scored.")
                if let distance = window.distanceMm { Text("Whole run distance: \(ChallengeV1Policy.Metric.distance.display(distance)). Only fictional matching runs are available until the distance rules pass physical testing.") }
            }
            SignalDateSpan(window: window)
            if policy.usesReceivedScores {
                Text("Save activity by \(window.correctionsBy.text(zone: window.timezone)). First updates and corrections count through this deadline, including the exact deadline.")
            } else {
                Text("Initial updates through \(window.syncBy.text(zone: window.timezone)). Corrections through \(window.correctionsBy.text(zone: window.timezone)).")
            }
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


struct ChallengeDecisionSummary: View {
    let policy: ChallengeV1Policy
    let window: ChallengeV1.Window
    let minimum: Int
    let sourcePolicy: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            summary("Activity", text: sourcePolicy.map { ChallengeHealthCopy.source($0, leaderboard: policy.usesReceivedScores) }
                ?? "Fictional activity for this local preview. No Apple Health activity is scored.")
            if sourcePolicy != nil, let distance = window.distanceMm {
                summary("Whole run distance", text: "\(ChallengeTimedDistanceCopy.range(distance)), including both distances. The whole run must fit inside these dates.")
            }
            summary("How it ends", text: policy.scoring + " " + policy.missing + " " + policy.allocation)
            summary("Leaving and review", text: "You may leave before the result is final and recover your simulated entry. The challenge continues only if at least \(minimum) eligible \(minimum == 1 ? "person remains" : "people remain"). You have 48 hours after the result notice to ask for a review.")
            if policy.usesReceivedScores {
                SignalFactRow(label: "Save activity by", value: window.correctionsBy.text(zone: window.timezone))
            }
        }
    }

    private func summary(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(text).font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
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
        VStack(alignment: .leading, spacing: 16) {
            if store.access?.ageConfirmed != true {
                Toggle("I confirm I am 21 or older", isOn: $age).accessibilityIdentifier("beta.age.toggle")
                Button("Save age confirmation") { Task { await store.submit(op: "confirm_age", fields: ["confirmed": .bool(true)]) } }
                    .disabled(!age || store.busy || store.pending != nil).accessibilityIdentifier("beta.age.submit")
            }
            TextField("Invitation link", text: $invitation.link)
                .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                .textContentType(.URL).keyboardType(.URL)
                .frame(minHeight: 44)
            Button("Use invitation") { Task { await useInvitation() } }
                .buttonStyle(SignalPrimaryButtonStyle())
                .disabled(invitation.links.token(from: invitation.link) == nil || store.actor == nil || store.access?.ageConfirmed != true || store.busy || store.pending != nil)
            Text("Request a place, then choose whether to agree.")
                .font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
            DisclosureGroup("How invitations work") {
                Text("An invitation grants beta access and requests a place in the lobby. The creator still chooses the roster. You agree separately. It does not add a friend.")
                    .font(.subheadline).padding(.top, 8)
            }
            if let error = store.entryError { Text(error).font(.subheadline).foregroundStyle(SignalTheme.danger) }
            ForEach(store.communities) { row in
                NavigationLink { ChallengeCommunityJoin(store: store, community: row) } label: {
                    Label("Community steps", systemImage: "person.3")
                }
            }
        }.fixedSize(horizontal: false, vertical: true)
            .onChange(of: store.actor) { age = false }
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
    private var savedChallenge: ChallengeV1? { store.challenges.first { $0.id == community.id } }
    private var binding: ChallengeHealthBinding? {
        guard let actor = store.actor, let window = decodeWindow(community.terms["config"]),
              let source = community.terms["source_policy_version"]?.string else { return nil }
        return try? ChallengeHealthBindingMapper.binding(actor: actor, id: community.id, version: 1, digest: community.digest,
            policy: ChallengeV1Policy(rawValue: "community_steps_goal_v1")!, window: window, source: source)
    }
    var body: some View {
        ChallengeForm {
            if let target = community.terms["common_target"]?.integer {
                SignalTargetBand(value: target, metric: .steps)
            }
            if let window = decodeWindow(community.terms["config"]) {
                SignalDateSpan(window: window)
                SignalFactRow(label: "Simulated entry", value: challengeMoney(window.amountCents))
                Text("Nothing can be paid out or redeemed. No real money moves.")
                    .font(.caption).foregroundStyle(SignalTheme.textSecondary)
                ChallengeFormSection(savedChallenge == nil ? "Before you join" : "Your agreement") {
                    ChallengeDecisionSummary(policy: ChallengeV1Policy(rawValue: "community_steps_goal_v1")!,
                        window: window, minimum: community.terms["minimum"]?.integer ?? 2,
                        sourcePolicy: community.terms["source_policy_version"]?.string)
                    DisclosureGroup("Complete challenge rules") {
                        ChallengeAgreementText(policy: ChallengeV1Policy(rawValue: "community_steps_goal_v1")!, window: window,
                            minimum: community.terms["minimum"]?.integer ?? 2, sourcePolicy: community.terms["source_policy_version"]?.string)
                            .padding(.top, 12)
                    }
                }
            }
            ChallengeFormSection("Just your progress") {
                Text("Only your progress and result appear here.")
                Text((community.counts ?? .init(joined: nil)).text(at: community.serverTime))
                    .foregroundStyle(SignalTheme.textSecondary)
            }
            if let savedChallenge {
                Label(savedChallenge.own(store.actor)?.exited == true ? "You left this challenge." : "You have joined. Find your own progress in Home.", systemImage: "checkmark.circle")
                NavigationLink { ChallengeV1Detail(store: store, id: community.id) } label: {
                    Text(savedChallenge.own(store.actor)?.exited == true ? "View saved challenge" : "View my progress")
                }.buttonStyle(SignalPrimaryButtonStyle())
            } else if decodeWindow(community.terms["config"]) != nil {
                if let health, let binding { ChallengeHealthStatusView(flow: health, binding: binding, readiness: true) }
                Toggle("I have read the complete rules and agree", isOn: $consent)
                Button("Join community challenge") { Task {
                    await store.submit(op: "join_community", fields: ["id": .string(community.id.uuidString.lowercased()), "digest": .string(community.digest), "consent": .bool(true)])
                    consent = false
                }}.buttonStyle(SignalPrimaryButtonStyle())
                    .disabled(!consent || (community.terms["source_policy_version"] != nil && binding.map { health?.canConsent($0) == true } != true) || !store.entryFresh || store.access?.ageConfirmed != true || store.busy || store.pending != nil)
            } else {
                Text("We couldn’t load the complete agreement. Go back and refresh before joining.")
                    .font(.subheadline).foregroundStyle(SignalTheme.danger)
            }
            if let error = store.error { Text(error).foregroundStyle(SignalTheme.danger) }

        }.navigationTitle("Community steps").navigationBarTitleDisplayMode(.inline)
            .onChange(of: store.actor) { consent = false }
            .onChange(of: community.digest) { consent = false }
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
                ShareLink("Share invitation", item: url)
                    .buttonStyle(SignalSecondaryButtonStyle()).privacySensitive()
            }
            Text("Expires \(issued.expiresAt.text(zone: row.config.timezone))")
                .font(.caption).foregroundStyle(SignalTheme.textSecondary)
            Text("Up to 20 different accounts may request a place while the lobby is open.")
                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Button("Turn off this link", role: .destructive) { Task {
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
        }.buttonStyle(.plain).font(.subheadline)
            .foregroundStyle(SignalTheme.textSecondary).frame(minHeight: 44)
            .accessibilityLabel(person.exited || person.username.isEmpty ? "Report or block former participant" : "Report or block " + person.username)
            .disabled(store.busy || store.pending != nil)
            .confirmationDialog("Block this account?", isPresented: $block, titleVisibility: .visible) {
                Button("Block account", role: .destructive) { Task { await store.submit(op: "block", fields: ["subject": .string(person.actorId.uuidString.lowercased())]) } }
            } message: { Text("Shared details are hidden and affected participation ends safely. Previous final results remain in your own history.") }
    }
    private func report(_ reason: String) { Task { await store.submit(op: "report", fields: ["subject": .string(person.actorId.uuidString.lowercased()), "reason": .string(reason)]) } }
}
