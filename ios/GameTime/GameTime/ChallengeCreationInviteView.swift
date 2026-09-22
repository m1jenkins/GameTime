import SwiftUI
import Observation

/// A continuation of the saved friend lobby. Invitations never imply roster
/// selection, agreement consent, message delivery, or a scheduled challenge.
struct ChallengeCreationInviteView: View {
    @Bindable var store: ChallengeV1Store
    let challengeID: UUID
    let progressLabels: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ChallengeCreationInvitationDraft
    @State private var showingConfirmation = false
    @State private var loading = false
    @State private var showingLinks = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var headingSize: CGFloat = 30
    @AccessibilityFocusState private var headingFocused: Bool

    init(store: ChallengeV1Store, challengeID: UUID, progressLabels: [String] = ["Goal", "Challenge", "Friends"]) {
        self.store = store
        self.challengeID = challengeID
        self.progressLabels = progressLabels
        _draft = State(initialValue: ChallengeCreationInvitationDraft(challengeID: challengeID))
    }

    #if DEBUG
    init(store: ChallengeV1Store, challengeID: UUID, showingConfirmation: Bool,
         progressLabels: [String] = ["Goal", "Challenge", "Friends"]) {
        self.store = store
        self.challengeID = challengeID
        self.progressLabels = progressLabels
        _draft = State(initialValue: ChallengeCreationInvitationDraft(challengeID: challengeID))
        _showingConfirmation = State(initialValue: showingConfirmation)
    }

    init(store: ChallengeV1Store, draft: ChallengeCreationInvitationDraft,
         showingConfirmation: Bool = false,
         progressLabels: [String] = ["Goal", "Challenge", "Friends"]) {
        self.store = store
        challengeID = draft.challengeID
        self.progressLabels = progressLabels
        _draft = State(initialValue: draft)
        _showingConfirmation = State(initialValue: showingConfirmation)
    }
    #endif

    private var currentRow: ChallengeV1? { draft.currentRow(store: store) }
    private var canInvite: Bool { draft.canInvite(store: store) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView { content }
            .onChange(of: showingConfirmation) {
                proxy.scrollTo("invite-top", anchor: .top)
                headingFocused = true
            }
        }
        .background(SignalCreationTheme.canvas)
        .foregroundStyle(SignalCreationTheme.textPrimary)
        .tint(SignalCreationTheme.accent)
        .modifier(ChallengeScrollLegibility())
        .scrollDismissesKeyboard(.interactively)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            SignalCreationChrome(title: "Create challenge", showsBack: showingConfirmation,
                                 back: { showingConfirmation = false }, close: { dismiss() })
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if currentRow != nil { footer }
        }
        .task(id: challengeID) { await refresh() }
        .refreshable { await refresh() }
        .onChange(of: store.actor) {
            draft.reset(); showingConfirmation = false
            dismiss()
        }
        .onDisappear { draft.reset() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let row = currentRow {
                if showingConfirmation { confirmation(row) }
                else { invitation(row) }
            } else {
                ContentUnavailableView("Refresh your challenge", systemImage: "arrow.clockwise",
                    description: Text("We couldn’t load the latest details. Refresh to continue inviting friends."))
                Button("Refresh") { Task { await refresh() } }
                    .buttonStyle(SignalSecondaryButtonStyle()).disabled(loading || store.busy)
                    .accessibilityIdentifier("beta.invite.refresh")
            }
            recovery
            if loading { ProgressView("Loading your challenge…") }
            if store.busy { ProgressView("Saving your action…") }
        }
        .padding(.horizontal, SignalCreationTheme.contentInset)
        .padding(.top, showingConfirmation ? 6 : 2)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .id("invite-top")
    }

    private func invitation(_ row: ChallengeV1) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            SignalCreationProgress(labels: progressLabels, current: progressLabels.count - 1)
                .accessibilityIdentifier("beta.create.progress")
                .padding(.bottom, 1)
            VStack(alignment: .leading, spacing: 10) {
                Text("Invite friends.").font(.system(size: headingSize, weight: .bold)).tracking(-1.1)
                    .accessibilityAddTraits(.isHeader).accessibilityFocused($headingFocused)
                    .accessibilityIdentifier("beta.invite.heading")
                Text("Choose up to 5 friends for the final roster.")
                    .font(.system(.subheadline, design: .default)).foregroundStyle(SignalCreationTheme.textSecondary)
            }
            members(row)
            if row.status == "lobby_open" {
                VStack(alignment: .leading, spacing: 8) {
                    let layout = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                        : AnyLayout(HStackLayout(spacing: 6))
                    layout {
                        HStack(spacing: 9) {
                            Image(systemName: "magnifyingglass").font(.body.weight(.regular))
                                .foregroundStyle(SignalCreationTheme.textSecondary).accessibilityHidden(true)
                            TextField("Exact friend username", text: $draft.username)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .textContentType(.username).submitLabel(.send)
                                .font(.subheadline)
                                .accessibilityIdentifier("beta.invite.input")
                                .onSubmit { Task { await invite() } }
                        }.frame(minHeight: 44)
                        Button { Task { await invite() } } label: {
                            Text("Invite").font(.subheadline.weight(.semibold))
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain).foregroundStyle(SignalCreationTheme.accent)
                        .disabled(!canInvite || ExactHandleSubmission.normalized(draft.username) == nil)
                        .accessibilityLabel("Invite friend")
                        .accessibilityIdentifier("beta.invite.submit")
                    }
                    .padding(.horizontal, 13)
                    .background(SignalCreationTheme.soft, in: RoundedRectangle(cornerRadius: 14))
                    .disabled(!canInvite)
                    Text("Use the exact username of an accepted friend.")
                        .font(.caption).foregroundStyle(SignalCreationTheme.textSecondary)
                    if draft.invitationSaved {
                        Label("Invitation saved. Your friend still needs to review and agree.", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(SignalCreationTheme.textSecondary)
                            .accessibilityIdentifier("beta.invite.saved")
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Divider().overlay(SignalCreationTheme.divider)
                    DisclosureGroup(isExpanded: $showingLinks) {
                        VStack(alignment: .leading, spacing: 10) {
                            ChallengeLinkIssuer(store: store, row: row)
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 12)
                    } label: {
                        Label("Invitation link", systemImage: "link")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(SignalCreationTheme.textPrimary)
                            .frame(minHeight: 48)
                    }
                    .accessibilityIdentifier("beta.invite.links")
                }
            } else {
                Text("Inviting is closed. Open your lobby to review the current rules and status.")
                    .font(.subheadline).foregroundStyle(SignalCreationTheme.textSecondary)
            }
            Text(row.format.hasTarget
                 ? "Each friend chooses their own goal. You choose the roster, then everyone reviews the rules and agrees."
                 : "You choose the roster, then everyone reviews the rules and agrees.")
                .font(.caption).foregroundStyle(SignalCreationTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func members(_ row: ChallengeV1) -> some View {
        let people = row.members.filter { $0.actorId != store.actor && !$0.exited }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Friends in your lobby").font(.subheadline.weight(.semibold))
                Spacer(minLength: 12)
                Text(people.count.formatted()).font(.subheadline.monospacedDigit())
                    .foregroundStyle(SignalCreationTheme.textSecondary)
            }
            if people.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "person.2").font(.system(size: 21, weight: .regular))
                        .frame(width: 44, height: 44)
                        .background(SignalCreationTheme.soft, in: Circle()).accessibilityHidden(true)
                    Text("Invite a friend to do this with.")
                        .font(.subheadline).foregroundStyle(SignalCreationTheme.textSecondary)
                }.frame(minHeight: 62)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(people) { person in
                            VStack(spacing: 7) {
                                Text(String(person.username.prefix(2)).uppercased())
                                    .font(.body.weight(.semibold))
                                    .frame(width: 48, height: 48)
                                    .background(SignalCreationTheme.soft, in: Circle())
                                    .padding(4)
                                    .overlay { Circle().stroke(person.selected ? SignalCreationTheme.accent : SignalCreationTheme.divider, lineWidth: person.selected ? 2 : 1) }
                                    .accessibilityHidden(true)
                                Text(person.username).font(.caption.weight(.semibold))
                                    .lineLimit(2).multilineTextAlignment(.center)
                                Text(person.consented ? "Agreed" : person.selected ? "On your roster" : "Waiting for roster selection")
                                    .font(.caption2).foregroundStyle(SignalCreationTheme.textSecondary)
                                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(width: typeSize.isAccessibilitySize ? 150 : 88)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.vertical, 2)
                }.scrollIndicators(.hidden)
            }
        }.accessibilityIdentifier("beta.invite.members")
    }

    private func confirmation(_ row: ChallengeV1) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 25, weight: .regular))
                    .foregroundStyle(SignalCreationTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(SignalCreationTheme.selection, in: Circle()).accessibilityHidden(true)
                Text("Your challenge is saved.").font(.system(size: headingSize, weight: .bold)).tracking(-1.1)
                    .accessibilityAddTraits(.isHeader).accessibilityFocused($headingFocused)
                    .accessibilityIdentifier("beta.create.saved")
                Text(row.status == "lobby_open"
                     ? "Choose your roster in the lobby. Everyone still needs to review and agree."
                     : row.statusText)
                    .font(.subheadline).foregroundStyle(SignalCreationTheme.textSecondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(row.title).font(.title2.weight(.bold)).tracking(-0.6)
                    Text(dateRange(row.config)).font(.subheadline)
                        .foregroundStyle(SignalCreationTheme.textSecondary)
                    Text(SignalTimeZone.name(row.config.timezone)).font(.caption)
                        .foregroundStyle(SignalCreationTheme.textSecondary)
                }
                if row.format.hasTarget, let target = row.own(store.actor)?.target {
                    VStack(alignment: .leading, spacing: 6) {
                        SignalCreationMetricReadout(value: target, metric: row.format.metric)
                        Text("Your goal").font(.caption).foregroundStyle(SignalCreationTheme.textSecondary)
                    }
                }
                Divider().overlay(SignalCreationTheme.divider)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(challengeMoney(row.config.amountCents)) simulated each · Fee $0")
                        .font(.caption)
                    Text("No real money moves. Nothing can be paid out or redeemed.")
                        .font(.caption)
                }.foregroundStyle(SignalCreationTheme.textSecondary)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [SignalCreationTheme.surface, SignalCreationTheme.soft], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 24))
            .overlay { RoundedRectangle(cornerRadius: 24).stroke(SignalCreationTheme.divider.opacity(0.45), lineWidth: 0.75) }
            members(row)
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            if showingConfirmation {
                NavigationLink {
                    ChallengeV1Detail(store: store, id: challengeID)
                        .toolbar(.visible, for: .navigationBar)
                } label: {
                    HStack(spacing: 12) {
                        Text("View lobby")
                        Image(systemName: "arrow.right").accessibilityHidden(true)
                    }
                }
                .buttonStyle(SignalCreationPrimaryStyle()).accessibilityIdentifier("beta.create.detail")
                Button("Back to invitations") { showingConfirmation = false }
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    .foregroundStyle(SignalCreationTheme.textSecondary)
                    .accessibilityIdentifier("beta.invite.back")
            } else {
                Button { showingConfirmation = true } label: {
                    HStack(spacing: 12) {
                        Text("Done inviting")
                        Image(systemName: "arrow.right").accessibilityHidden(true)
                    }
                }
                .buttonStyle(SignalCreationPrimaryStyle()).disabled(store.busy || store.pending != nil)
                .accessibilityIdentifier("beta.invite.done")
            }
        }
        .padding(.horizontal, SignalCreationTheme.contentInset)
        .padding(.top, 12).padding(.bottom, 6)
        .background(SignalCreationTheme.canvas)
    }

    private func dateRange(_ window: ChallengeV1.Window) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: window.timezone)
        formatter.setLocalizedDateFormatFromTemplate("MMM d yyyy")
        // The server's end is exclusive; the final included second is always
        // on the last goal day, including across daylight-saving changes.
        let lastDay = window.endsAt.date.addingTimeInterval(-1)
        let start = formatter.string(from: window.startsAt.date)
        let end = formatter.string(from: lastDay)
        let range = window.days == 1 ? start : "\(start)–\(end)"
        return "\(range) · \(window.days) \(window.days == 1 ? "day" : "days")"
    }

    @ViewBuilder private var recovery: some View {
        if let error = store.error {
            Text(error).font(.subheadline).foregroundStyle(SignalCreationTheme.danger)
        }
        if store.pending != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your last action is saved on this phone. Retry it to check whether it went through.")
                    .font(.subheadline)
                Button("Retry saved action") { Task { await retry() } }
                    .buttonStyle(SignalCreationPrimaryStyle()).accessibilityIdentifier("beta.invite.retry")
                Button("Stop waiting for this action") { Task { await store.abandon() } }
                    .buttonStyle(SignalSecondaryButtonStyle()).accessibilityIdentifier("beta.invite.abandon")
            }.disabled(store.busy)
        }
    }

    private func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        await store.loadDetail(challengeID)
    }

    private func invite() async {
        if await draft.invite(store: store) { SignalAccessibility.announce("Invitation saved.") }
    }

    private func retry() async {
        if await draft.retry(store: store) { SignalAccessibility.announce("Invitation saved.") }
    }
}

/// Owns the local invitation form and its acknowledgment, while the shared store
/// remains the only owner of persisted requests and exact retries.
@MainActor @Observable final class ChallengeCreationInvitationDraft {
    let challengeID: UUID
    var username = "" { didSet { if !username.isEmpty { invitationSaved = false } } }
    private(set) var invitationSaved = false
    @ObservationIgnored private var generation = UUID()

    init(challengeID: UUID) { self.challengeID = challengeID }

    func currentRow(store: ChallengeV1Store) -> ChallengeV1? {
        guard let row = store.challenges.first(where: { $0.id == challengeID }),
              store.isFresh(row), row.creatorId == store.actor,
              row.format.mode == .friend, !row.socialHidden,
              row.own(store.actor)?.exited == false else { return nil }
        return row
    }

    func canInvite(store: ChallengeV1Store) -> Bool {
        currentRow(store: store)?.status == "lobby_open" && !store.busy && store.pending == nil
    }

    func reset() {
        generation = UUID()
        username = ""
        invitationSaved = false
    }

    @discardableResult
    func invite(store: ChallengeV1Store) async -> Bool {
        guard canInvite(store: store), let row = currentRow(store: store), let actor = store.actor,
              let submitted = ExactHandleSubmission.normalized(username) else { return false }
        let ticket = generation
        invitationSaved = false
        let receipt = await store.submit(op: "invite", challenge: row, fields: ["username": .string(submitted)])
        guard actor == store.actor, ticket == generation, accepts(receipt) else { return false }
        if ExactHandleSubmission.normalized(username) == submitted { username = "" }
        invitationSaved = true
        return true
    }

    @discardableResult
    func retry(store: ChallengeV1Store) async -> Bool {
        guard let pending = store.pending, let actor = store.actor, pending.actorId == actor else { return false }
        let ticket = generation
        invitationSaved = false
        await store.retry()
        guard store.actor == actor, ticket == generation, store.pending == nil,
              pending.payload["op"]?.string == "invite",
              pending.payload["id"]?.string.flatMap(UUID.init(uuidString:)) == challengeID,
              accepts(store.lastReceipt) else { return false }
        if ExactHandleSubmission.normalized(username) == pending.payload["username"]?.string { username = "" }
        invitationSaved = true
        return true
    }

    private func accepts(_ receipt: ChallengeV1Receipt?) -> Bool {
        receipt?.id == challengeID && receipt?.status == "lobby_open" && (receipt?.revision ?? 0) > 0
    }
}
