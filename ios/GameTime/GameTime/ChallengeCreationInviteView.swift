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
        .navigationTitle(showingConfirmation ? "Challenge saved" : "Invite friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("Close").modifier(SignalNavigationAction())
                    .accessibilityIdentifier("beta.create.close")
            }
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
        VStack(alignment: .leading, spacing: 26) {
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
        .padding(SignalCreationTheme.contentInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .id("invite-top")
    }

    private func invitation(_ row: ChallengeV1) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            SignalCreationProgress(labels: progressLabels, current: progressLabels.count - 1)
            VStack(alignment: .leading, spacing: 10) {
                Text("Invite friends.").font(.largeTitle.weight(.bold))
                    .accessibilityAddTraits(.isHeader).accessibilityFocused($headingFocused)
                    .accessibilityIdentifier("beta.invite.heading")
                Text("Choose up to 5 friends for the final roster.")
                    .font(.subheadline).foregroundStyle(SignalCreationTheme.textSecondary)
            }
            members(row)
            if row.status == "lobby_open" {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Add by username", systemImage: "person.2").font(.headline)
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").foregroundStyle(SignalCreationTheme.textSecondary)
                            .accessibilityHidden(true)
                        TextField("Exact friend username", text: $draft.username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .textContentType(.username).submitLabel(.send)
                            .accessibilityIdentifier("beta.invite.input")
                            .onSubmit { Task { await invite() } }
                    }
                    .padding(.horizontal, 16).frame(minHeight: 52)
                    .background(SignalCreationTheme.soft, in: RoundedRectangle(cornerRadius: 16))
                    .disabled(!canInvite)
                    Text("Use the exact username of an accepted friend.")
                        .font(.caption).foregroundStyle(SignalCreationTheme.textSecondary)
                    Button { Task { await invite() } } label: {
                        Label("Invite friend", systemImage: "arrow.right")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(SignalCreationPrimaryStyle())
                    .disabled(!canInvite || ExactHandleSubmission.normalized(draft.username) == nil)
                    .accessibilityIdentifier("beta.invite.submit")
                    if draft.invitationSaved {
                        Label("Invitation saved. Your friend still needs to review and agree.", systemImage: "checkmark.circle.fill")
                            .font(.subheadline).foregroundStyle(SignalCreationTheme.textSecondary)
                            .accessibilityIdentifier("beta.invite.saved")
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    Label("Invitation link", systemImage: "link").font(.headline)
                    ChallengeLinkIssuer(store: store, row: row)
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(SignalCreationTheme.soft, in: RoundedRectangle(cornerRadius: 20))
            } else {
                Text("Inviting is closed. Open your lobby to review the current rules and status.")
                    .font(.subheadline).foregroundStyle(SignalCreationTheme.textSecondary)
            }
            Text(row.format.hasTarget
                 ? "Each friend chooses their own goal. You choose the roster, then everyone reviews the rules and agrees."
                 : "You choose the roster, then everyone reviews the rules and agrees.")
                .font(.subheadline).foregroundStyle(SignalCreationTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showingConfirmation = true
            } label: {
                HStack {
                    Text("Done inviting")
                    Image(systemName: "arrow.right").accessibilityHidden(true)
                }.frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(SignalCreationPrimaryStyle()).disabled(store.busy || store.pending != nil)
            .accessibilityIdentifier("beta.invite.done")
        }
    }

    private func members(_ row: ChallengeV1) -> some View {
        let people = row.members.filter { $0.actorId != store.actor && !$0.exited }
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Friends in your lobby").font(.headline)
                Spacer(minLength: 12)
                Text(people.count.formatted()).font(.subheadline.monospacedDigit())
                    .foregroundStyle(SignalCreationTheme.textSecondary)
            }
            if people.isEmpty {
                HStack(spacing: 16) {
                    Image(systemName: "person.2").font(.title2.weight(.regular))
                        .frame(width: 52, height: 52)
                        .background(SignalCreationTheme.soft, in: Circle()).accessibilityHidden(true)
                    Text("Invite a friend to do this with.")
                        .font(.subheadline).foregroundStyle(SignalCreationTheme.textSecondary)
                }.padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(people) { person in
                        HStack(spacing: 14) {
                            Text(String(person.username.prefix(2)).uppercased())
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 44, height: 44)
                                .background(SignalCreationTheme.soft, in: Circle()).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(person.username).font(.headline)
                                Text(person.selected ? "On your roster" : "Waiting for roster selection")
                                    .font(.caption).foregroundStyle(SignalCreationTheme.textSecondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if person.consented {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(SignalCreationTheme.textSecondary)
                                    .accessibilityLabel("Agreed")
                            }
                        }.padding(.vertical, 12)
                        .accessibilityElement(children: .combine)
                        Divider().overlay(SignalCreationTheme.divider)
                    }
                }
            }
        }.accessibilityIdentifier("beta.invite.members")
    }

    private func confirmation(_ row: ChallengeV1) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 36, weight: .regular))
                    .foregroundStyle(SignalCreationTheme.accent).accessibilityHidden(true)
                Text("Your challenge is saved.").font(.largeTitle.weight(.bold))
                    .accessibilityAddTraits(.isHeader).accessibilityFocused($headingFocused)
                    .accessibilityIdentifier("beta.create.saved")
                Text(row.status == "lobby_open"
                     ? "Choose your roster in the lobby. Everyone still needs to review and agree."
                     : row.statusText)
                    .font(.subheadline).foregroundStyle(SignalCreationTheme.textSecondary)
            }
            VStack(alignment: .leading, spacing: 16) {
                Text(row.title).font(.title2.weight(.semibold))
                SignalDateSpan(window: row.config)
                if row.format.hasTarget, let target = row.own(store.actor)?.target {
                    SignalCreationMetric(value: target, metric: row.format.metric)
                }
                Text("\(challengeMoney(row.config.amountCents)) simulated each · Fee $0")
                    .font(.subheadline)
                Text("No real money moves. Nothing can be paid out or redeemed.")
                    .font(.caption).foregroundStyle(SignalCreationTheme.textSecondary)
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(SignalCreationTheme.soft, in: RoundedRectangle(cornerRadius: 22))
            members(row)
            NavigationLink {
                ChallengeV1Detail(store: store, id: challengeID)
            } label: {
                HStack {
                    Text("View lobby")
                    Image(systemName: "arrow.right").accessibilityHidden(true)
                }.frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(SignalCreationPrimaryStyle()).accessibilityIdentifier("beta.create.detail")
            Button("Back to invitations") { showingConfirmation = false }
                .buttonStyle(SignalSecondaryButtonStyle()).accessibilityIdentifier("beta.invite.back")
        }
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
