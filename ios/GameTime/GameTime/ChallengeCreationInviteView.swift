import SwiftUI
import Observation

/// A continuation of the saved friend lobby. Invitations never imply roster
/// selection, agreement consent, message delivery, or a scheduled challenge.
struct ChallengeCreationInviteView: View {
    @Bindable var store: ChallengeV1Store
    let challengeID: UUID
    let progressLabels: [String]
    var onGoHome: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ChallengeCreationInvitationDraft
    @State private var showingConfirmation = false
    @State private var loading = false
    @State private var inviting = false
    @State private var showingLinks = false
    @Environment(FriendsStore.self) private var friends: FriendsStore?
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var headingSize: CGFloat = 30
    @AccessibilityFocusState private var headingFocused: Bool

    init(store: ChallengeV1Store, challengeID: UUID, progressLabels: [String] = ["Goal", "Challenge", "Friends"], onGoHome: @escaping () -> Void = {}) {
        self.store = store
        self.challengeID = challengeID
        self.progressLabels = progressLabels
        self.onGoHome = onGoHome
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
        Group {
            if showingConfirmation {
                ChallengeCreationSuccess(store: store, challengeID: challengeID, onGoHome: onGoHome)
            } else {
                invitations
            }
        }
        .tint(SignalCreationTheme.accent)
        .task(id: challengeID) { await refresh() }
        .onChange(of: store.actor) {
            draft.reset(); showingConfirmation = false
            dismiss()
        }
        .onDisappear { draft.reset() }
    }

    private var invitations: some View {
        ScrollView { content }
        .background(SignalCreationTheme.canvas)
        .foregroundStyle(SignalCreationTheme.textPrimary)
        .modifier(ChallengeScrollLegibility())
        .scrollDismissesKeyboard(.interactively)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .top, spacing: 0) {
            SignalCreationChrome(title: "Create challenge", showsBack: false, back: {}, close: { dismiss() })
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if currentRow != nil { footer }
        }
        .refreshable { await refresh() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let row = currentRow {
                invitation(row)
            } else {
                ContentUnavailableView("Refresh your challenge", systemImage: "arrow.clockwise",
                    description: Text("We couldn’t load the latest details. Refresh to continue inviting friends."))
                Button("Refresh") { Task { await refresh() } }
                    .buttonStyle(LiveSecondaryButtonStyle()).disabled(loading || store.busy)
                    .accessibilityIdentifier("beta.invite.refresh")
            }
            recovery
            if loading { ProgressView("Loading your challenge…") }
            if store.busy { ProgressView("Saving…") }
        }
        .padding(.horizontal, SignalCreationTheme.contentInset)
        .padding(.top, 2)
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
                Text(row.format.hasTarget
                     ? "Choose up to 5. They’ll each review the rules and choose their own goal."
                     : "Choose up to 5. They’ll each review the rules.")
                    .font(.system(.subheadline, design: .default)).foregroundStyle(SignalCreationTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if row.status == "lobby_open" {
                picker(row)
                InviteAddFriendRow()
                if store.linksAvailable { links(row) }
                if draft.invitationSaved {
                    Label("Invitations saved. Each friend still needs to review and agree.", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(SignalCreationTheme.textSecondary)
                        .accessibilityIdentifier("beta.invite.saved")
                }
            } else {
                Text("Inviting is closed. Open your challenge to review the current rules and status.")
                    .font(.subheadline).foregroundStyle(SignalCreationTheme.textSecondary)
            }
            Text("You pick the final roster from the friends who accept. Everyone on it agrees before the start.")
                .font(.caption).foregroundStyle(SignalCreationTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Accepted friends as checkable rows. People already in the lobby stay
    /// listed with their status and can't be picked twice.
    @ViewBuilder private func picker(_ row: ChallengeV1) -> some View {
        let members = draft.others(row, actor: store.actor)
        let memberIDs = Set(members.map(\.actorId))
        let candidates = (friends?.friends ?? []).filter { !memberIDs.contains($0.id) }
        let remaining = draft.remaining(row, actor: store.actor)
        if members.isEmpty && candidates.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "person.2").font(.system(size: 24, weight: .regular))
                    .frame(width: 52, height: 52).background(SignalCreationTheme.soft, in: Circle())
                    .accessibilityHidden(true)
                Text(friends?.state == .loading ? "Loading your friends…" : "No friends yet")
                    .liveFont(17, weight: .semibold)
                if friends?.state != .loading {
                    Text("Send a request by username. Once they accept, they’ll show up here and you can invite them. Your challenge is saved while you wait.")
                        .font(.subheadline).foregroundStyle(SignalCreationTheme.textSecondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity).padding(20)
            .background(SignalCreationTheme.soft.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("beta.invite.empty")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Your friends").font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("beta.invite.members")
                    Spacer(minLength: 12)
                    Text("\(members.count + draft.chosen.count) of \(ChallengeCreationInvitationDraft.othersLimit) chosen")
                        .font(.subheadline.monospacedDigit()).foregroundStyle(SignalCreationTheme.textSecondary)
                        .accessibilityIdentifier("beta.invite.count")
                }
                LiveListCard {
                    ForEach(members) { person in
                        FriendRow(person: FriendPerson(id: person.actorId, username: person.username,
                                                       displayName: friends?.friends.first { $0.id == person.actorId }?.displayName ?? person.username),
                                  detail: person.consented ? "Agreed" : person.selected ? "On your roster" : "Invited") {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 22))
                                .foregroundStyle(SignalCreationTheme.textSecondary).accessibilityHidden(true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    ForEach(candidates) { person in
                        let on = draft.chosen.contains(person.id)
                        let full = !on && draft.chosen.count >= remaining
                        Button { draft.toggle(person.id, row: row, actor: store.actor) } label: {
                            FriendRow(person: person) {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 22))
                                    .foregroundStyle(on ? SignalCreationTheme.accent : SignalCreationTheme.divider)
                                    .accessibilityHidden(true)
                            }
                            .opacity(full ? 0.45 : 1)
                        }
                        .buttonStyle(.plain)
                        .disabled(full || !canInvite)
                        .accessibilityAddTraits(on ? [.isSelected] : [])
                        .accessibilityHint(full ? "You’ve chosen 5 people." : "")
                        .accessibilityIdentifier("beta.invite.friend." + person.username)
                    }
                }
            }
        }
    }

    /// Only when the server has links open. The TestFlight build keeps them closed.
    private func links(_ row: ChallengeV1) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(SignalCreationTheme.divider)
            DisclosureGroup(isExpanded: $showingLinks) {
                ChallengeLinkIssuer(store: store, row: row)
                    .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 12)
            } label: {
                Label("Invitation link", systemImage: "link").font(.subheadline.weight(.medium))
                    .foregroundStyle(SignalCreationTheme.textPrimary).frame(minHeight: 48)
            }
            .accessibilityIdentifier("beta.invite.links")
        }
    }

    private var footerTitle: String {
        if !draft.chosen.isEmpty { return "Invite \(draft.chosen.count) \(draft.chosen.count == 1 ? "friend" : "friends")" }
        if let row = currentRow, !draft.others(row, actor: store.actor).isEmpty { return "Done inviting" }
        return "Skip for now"
    }

    private var footer: some View {
        Button { Task { await finish() } } label: {
            HStack(spacing: 12) {
                Text(footerTitle)
                Image(systemName: "arrow.right").accessibilityHidden(true)
            }
        }
        .buttonStyle(LivePrimaryButtonStyle()).disabled(store.busy || store.pending != nil || inviting)
        .accessibilityIdentifier("beta.invite.done")
        .padding(.horizontal, SignalCreationTheme.contentInset)
        .padding(.top, 12).padding(.bottom, 6)
        .background(SignalCreationTheme.canvas)
    }

    private func finish() async {
        guard !draft.chosen.isEmpty else { showingConfirmation = true; return }
        inviting = true
        defer { inviting = false }
        if await draft.inviteChosen(store: store, friends: friends?.friends ?? []) {
            SignalAccessibility.announce("Invitations saved.")
            showingConfirmation = true
        }
    }

    @ViewBuilder private var recovery: some View {
        if let error = store.error {
            Text(error).font(.subheadline).foregroundStyle(SignalCreationTheme.danger)
        }
        if store.pending != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text(ChallengePendingCopy.title).font(.subheadline.weight(.semibold))
                Text(ChallengePendingCopy.message).font(.subheadline)
                Button(ChallengePendingCopy.retry) { Task { await retry() } }
                    .buttonStyle(LivePrimaryButtonStyle()).accessibilityIdentifier("beta.invite.retry")
                Button(ChallengePendingCopy.cancel) { Task { await store.abandon() } }
                    .buttonStyle(LiveSecondaryButtonStyle()).accessibilityIdentifier("beta.invite.abandon")
            }.disabled(store.busy)
        }
    }

    private func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        await store.loadDetail(challengeID)
        // The picker lists only friends the server confirms right now.
        await friends?.refresh()
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
        chosen = []
    }

    /// A lobby holds six people: you and up to five others.
    static let othersLimit = 5
    /// Accepted friends picked on this screen, in the order they were picked.
    private(set) var chosen: [UUID] = []

    func others(_ row: ChallengeV1, actor: UUID?) -> [ChallengeV1.Member] {
        row.members.filter { $0.actorId != actor && !$0.exited }
    }
    func remaining(_ row: ChallengeV1, actor: UUID?) -> Int {
        max(0, Self.othersLimit - others(row, actor: actor).count)
    }
    func toggle(_ id: UUID, row: ChallengeV1, actor: UUID?) {
        if let index = chosen.firstIndex(of: id) { chosen.remove(at: index); return }
        guard chosen.count < remaining(row, actor: actor),
              !others(row, actor: actor).contains(where: { $0.actorId == id }) else { return }
        chosen.append(id)
    }

    /// Invites each chosen friend with its own saved request, in order. It
    /// stops at the first refusal so nothing is reported as sent that wasn't.
    @discardableResult
    func inviteChosen(store: ChallengeV1Store, friends: [FriendPerson]) async -> Bool {
        let ticket = generation
        invitationSaved = false
        for id in chosen {
            guard ticket == generation, let actor = store.actor, canInvite(store: store),
                  let row = currentRow(store: store) else { return false }
            if others(row, actor: actor).contains(where: { $0.actorId == id }) { continue }
            guard let friend = friends.first(where: { $0.id == id }) else { return false }
            let receipt = await store.submit(op: "invite", challenge: row, fields: ["username": .string(friend.username)])
            guard actor == store.actor, ticket == generation, accepts(receipt) else { return false }
            chosen.removeAll { $0 == id }
        }
        invitationSaved = true
        return true
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
