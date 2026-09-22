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
    @State private var showingLinks = false
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
                    .buttonStyle(SignalSecondaryButtonStyle()).disabled(loading || store.busy)
                    .accessibilityIdentifier("beta.invite.refresh")
            }
            recovery
            if loading { ProgressView("Loading your challenge…") }
            if store.busy { ProgressView("Saving your action…") }
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

    private var footer: some View {
        Button { showingConfirmation = true } label: {
            HStack(spacing: 12) {
                Text("Done inviting")
                Image(systemName: "arrow.right").accessibilityHidden(true)
            }
        }
        .buttonStyle(SignalCreationPrimaryStyle()).disabled(store.busy || store.pending != nil)
        .accessibilityIdentifier("beta.invite.done")
        .padding(.horizontal, SignalCreationTheme.contentInset)
        .padding(.top, 12).padding(.bottom, 6)
        .background(SignalCreationTheme.canvas)
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
