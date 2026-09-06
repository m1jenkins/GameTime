#if DEBUG || STAGING
import SwiftUI

struct DuelHomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var creation: DuelCreationSheet?
    private var store: DuelStore { model.duels }

    var body: some View {
        Group {
            if model.configuration.duelRuntimeEnabled {
                List {
                    DuelDisclosure()
                    if creation == nil { DuelRecoverySection(store: store) }
                    Section {
                        Button("Challenge a friend") { creation = DuelCreationSheet() }
                            .accessibilityIdentifier("duel.create")
                            .disabled(!store.canStartRequest)
                    }
                    Section("Your duels") {
                        if store.isLoading { ProgressView("Loading your duels…") }
                        if store.agreements.isEmpty && !store.isLoading {
                            Text("No duels yet. Choose a friend and agree to the same 5K rules.")
                        }
                        ForEach(store.agreements) { duel in
                            NavigationLink {
                                DuelDetailView(challengeID: duel.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(duel.terms.event.eventName).font(.headline)
                                    Text(store.lifecycles[duel.id].map { $0.progressText.isEmpty ? duel.statusText : $0.progressText } ?? (duel.status == .scheduled ? "Refresh for result status" : duel.statusText))
                                    Text(DuelCodec.dateText(duel.startsAt, zone: duel.terms.event.displayTimezone))
                                        .font(.caption)
                                }
                                .padding(.vertical, 4)
                            }
                            .accessibilityIdentifier("duel.row.\(duel.id)")
                        }
                        if store.hasMore {
                            Button("Load more") { Task { await store.refresh(loadMore: true) } }
                                .disabled(store.isLoading || store.isSending)
                        }
                    }
                }
                .refreshable { await store.refresh() }
                .task(id: model.userID) { await store.refresh() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await store.refresh() } }
                }
                .sheet(item: $creation) { _ in
                    DuelCreateView(store: store)
                        .id(model.userID)
                }
                .onChange(of: model.userID) { _, _ in creation = nil }
            } else {
                ContentUnavailableView("Duels aren’t open yet", systemImage: "figure.run")
            }
        }
        .navigationTitle("Friend duels")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("duel.home")
    }
}

private struct DuelCreationSheet: Identifiable { let id = UUID() }

struct DuelDisclosure: View {
    var body: some View {
        Text("Simulated stakes — no real money moves.")
            .font(.subheadline.weight(.semibold))
            .accessibilityIdentifier("duel.simulation")
    }
}

private struct DuelRecoverySection: View {
    let store: DuelStore
    var body: some View {
        if let error = store.errorMessage {
            Section {
                Text(error).foregroundStyle(.secondary)
                    .accessibilityIdentifier("duel.error")
                Button("Refresh duels") { Task { await store.refresh() } }
                    .disabled(store.isSending || store.isLoading)
            }
        }
        if store.pending != nil {
            Section("Saved request") {
                Text("Your last request may already be complete. Retry it to confirm what happened before making another change.")
                Button("Retry saved request") { Task { await store.retry() } }
                    .accessibilityIdentifier("duel.retry")
                    .disabled(store.isSending || store.isLoading || store.storageBlocked)
            }
        }
        if store.isSending { ProgressView("Confirming your request…") }
    }
}

private struct DuelReviewChoice: Identifiable {
    let id = UUID()
    let friend: FriendshipCard
    let event: DuelEvent
    let policy: DuelPolicy
    var previousID: UUID? = nil
}

private struct DuelCreateView: View {
    let store: DuelStore
    var previous: DuelAgreement? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var friendID: UUID?
    @State private var eventID: UUID?
    @State private var review: DuelReviewChoice?

    private var events: [DuelEvent] {
        store.catalog.events.filter { event in
            if let previous, event.id == previous.eventID || event.startsAt <= previous.terms.event.endsAt { return false }
            return event.isAvailable(at: Date()) && store.catalog.policies.contains {
                $0.version == event.policyVersion && $0.isSupported
            }
        }
    }

    private var availableFriends: [FriendshipCard] {
        guard let previous else { return store.friends }
        let other = previous.creatorID == store.actorID ? previous.inviteeID : previous.creatorID
        return store.friends.filter { $0.otherUserID == other }
    }

    var body: some View {
        NavigationStack {
            Form {
                DuelDisclosure()
                if review == nil { DuelRecoverySection(store: store) }
                Section("Choose a friend") {
                    if availableFriends.isEmpty {
                        Text("No accepted friends are available. Refresh your duels after a friend has accepted your friendship.")
                    }
                    ForEach(availableFriends) { friend in
                        Button {
                            friendID = friend.otherUserID
                        } label: {
                            selection(friend.displayName, selected: friendID == friend.otherUserID)
                        }
                        .accessibilityIdentifier("duel.friend.\(friend.otherUserID)")
                        .accessibilityAddTraits(friendID == friend.otherUserID ? .isSelected : [])
                    }
                }
                Section("Choose a race") {
                    if events.isEmpty {
                        Text("No races are open for invitations. Refresh later to check again.")
                    }
                    ForEach(events) { event in
                        Button { eventID = event.id } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                selection(event.eventName, selected: eventID == event.id)
                                Text(DuelCodec.dateText(event.startsAt, zone: event.displayTimezone))
                                    .font(.caption)
                            }
                        }
                        .accessibilityIdentifier("duel.event")
                        .accessibilityAddTraits(eventID == event.id ? .isSelected : [])
                    }
                }
                Button("Review rules") {
                    if let friend = availableFriends.first(where: { $0.otherUserID == friendID }),
                        let event = events.first(where: { $0.id == eventID }),
                        let policy = store.catalog.policies.first(where: { $0.version == event.policyVersion }) {
                        review = DuelReviewChoice(friend: friend, event: event, policy: policy, previousID: previous?.id)
                    }
                }
                .accessibilityIdentifier("duel.review")
                .disabled(friendID == nil || eventID == nil || !store.canStartRequest)
            }
            .navigationTitle(previous == nil ? "Challenge a friend" : "Challenge again")
            .onAppear { if previous != nil { friendID = availableFriends.first?.otherUserID } }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(item: $review) { choice in
                DuelCreatorReviewView(store: store, choice: choice)
            }
        }
    }

    private func selection(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title).multilineTextAlignment(.leading)
            Spacer(minLength: 12)
            if selected { Image(systemName: "checkmark.circle.fill").accessibilityHidden(true) }
        }
        .frame(minHeight: 44)
    }
}

private struct DuelCreatorReviewView: View {
    let store: DuelStore
    let choice: DuelReviewChoice
    @State private var consent = false
    @State private var receiptID: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let receiptID {
                    Section("Invitation confirmed") {
                        Text("Your invitation is saved. Your friend still needs to agree.")
                        NavigationLink("View what you agreed to") {
                            DuelDetailView(challengeID: receiptID)
                        }
                        .accessibilityIdentifier("duel.receipt")
                    }
                } else if store.pending != nil {
                    DuelDisclosure()
                    Section("Invitation to \(choice.friend.displayName)") {
                        Text(choice.event.eventName)
                        Text("We saved the rules you agreed to. Confirm your request to see the current invitation.")
                    }
                    DuelRecoverySection(store: store)
                } else {
                    DuelDisclosure()
                    Section("You and \(choice.friend.displayName)") {
                        Text("You both agree to these rules.")
                    }
                    if choice.previousID != nil {
                        Section {
                            Text("This is a new duel for a new race. You both need to agree again. Your previous result stays in history.")
                        }
                    }
                    DuelRulesSections(event: choice.event, terms: nil)
                    DuelRecoverySection(store: store)
                    Section {
                        Toggle("I agree to these simulated 5K rules.", isOn: $consent)
                            .accessibilityIdentifier("duel.consent")
                        Button("Agree and send invitation") {
                            Task {
                                let operation: DuelMutation = if let previous = choice.previousID {
                                    .rematch(previousID: previous, eventID: choice.event.id,
                                        policyVersion: choice.policy.version, consent: consent)
                                } else {
                                    .create(inviteeID: choice.friend.otherUserID, eventID: choice.event.id,
                                        policyVersion: choice.policy.version, consent: consent)
                                }
                                await store.submit(operation)
                                receiptID = store.lastConfirmedID
                            }
                        }
                        .accessibilityIdentifier("duel.send")
                        .disabled(!consent || !store.canStartRequest || !choice.event.isAvailable(at: Date()))
                    }
                }
            }
            .interactiveDismissDisabled(store.isSending || store.pending != nil)
            .navigationTitle(receiptID == nil ? "Review rules" : "Invitation sent")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onChange(of: store.lastConfirmedID) { _, id in
                if let id { receiptID = id }
            }
        }
    }
}

struct DuelDetailView: View {
    let challengeID: UUID
    @Environment(AppModel.self) private var model
    @State private var consent = false
    @State private var exitAction: DuelExitAction?
    @State private var reviewNotice: DuelParticipantReviewChoice?
    @State private var safeExit: DuelSafeExitKind?
    @State private var rematch: DuelAgreement?
    @Environment(\.scenePhase) private var scenePhase
    private var store: DuelStore { model.duels }

    var body: some View {
        Form {
            DuelDisclosure()
            DuelRecoverySection(store: store)
            if let duel = store.agreements.first(where: { $0.id == challengeID }),
                let actor = store.actorID {
                Section("Your duel") {
                    Text(store.lifecycles[duel.id].map { $0.progressText.isEmpty ? duel.statusText : $0.progressText } ?? (duel.status == .scheduled ? "Refresh for result status" : duel.statusText)).font(.headline).accessibilityIdentifier("duel.status")
                    Text(actor == duel.creatorID ? "You sent this invitation." : "Your friend invited you.")
                    Text("You both agree to these rules.")
                    ForEach(duel.participants, id: \.actorID) { participant in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(participant.actorID == actor ? "You" :
                                (store.lifecycles[duel.id]?.contactSuppressed == false
                                    ? (store.friends.first(where: { $0.otherUserID == participant.actorID })?.displayName ?? "Your friend")
                                    : "Other participant"))
                            if let accepted = participant.acceptedAt {
                                Text("Agreed \(DuelCodec.dateText(accepted, zone: duel.terms.event.displayTimezone))")
                            } else {
                                Text(participant.declinedAt == nil ? "Hasn’t agreed" : "Declined")
                            }
                        }
                    }
                }
                DuelLifecycleSections(store: store, agreement: duel, actorID: actor,
                    onReview: { reviewNotice = DuelParticipantReviewChoice(agreement: duel, notice: $0) }, onExit: { safeExit = $0 })
                    .id(actor)
                if store.canRematch(duel.id) {
                    Section {
                        Button("Challenge again") {
                            Task {
                                await store.refresh()
                                if store.canRematch(duel.id) { rematch = duel }
                            }
                        }
                        .accessibilityIdentifier("duel.rematch")
                    }
                }
                if actor == duel.creatorID, duel.status == .invited,
                   store.freshIDs.contains(duel.id), store.lifecycles[duel.id]?.contactSuppressed == false {
                    Section("Invitation link") {
                        Text("Only the friend you invited can open this link. They still need to agree to the rules.")
                        if let link = store.invitationLinks[duel.id] {
                            ShareLink(item: link.url) { Label("Share invitation", systemImage: "square.and.arrow.up") }
                                .accessibilityIdentifier("duel.share")
                                .disabled(store.isLoading || store.isSending || (store.estimatedNow(for: duel.id).map { $0 >= link.expiresAt } ?? true))
                            Text("Link expires \(DuelCodec.dateText(link.expiresAt.date, zone: duel.terms.event.displayTimezone))")
                            Button("Turn off this link", role: .destructive) {
                                Task { await store.submit(.revokeLink(challengeID: duel.id, token: link.token)) }
                            }
                            .accessibilityIdentifier("duel.revoke-link")
                            .disabled(!store.canStartRequest)
                        } else {
                            Button("Create invitation link") { Task { await store.submit(.issueLink(challengeID: duel.id)) } }
                                .accessibilityIdentifier("duel.issue-link")
                                .disabled(!store.canStartRequest || duel.expiryDue)
                        }
                        Text("Turning off a link does not cancel the invitation. You can cancel the duel below.")
                    }
                }
                DuelRulesSections(event: duel.terms.event, terms: duel.terms)
                Section {
                    if duel.canAccept(actorID: actor, now: Date()) && store.lifecycles[duel.id]?.contactSuppressed == false {
                        Toggle("I agree to these simulated 5K rules.", isOn: $consent)
                            .accessibilityIdentifier("duel.consent")
                        Button("Agree to this duel") {
                            Task { await store.submit(.accept(challengeID: duel.id,
                                policyVersion: duel.policyVersion, termsDigest: duel.termsDigest)) }
                        }
                        .accessibilityIdentifier("duel.accept")
                        .disabled(!consent || !store.canStartRequest || !store.freshIDs.contains(duel.id))
                    }
                    if duel.status == .invited && actor == duel.inviteeID {
                        Button("Decline invitation", role: .destructive) { exitAction = .decline }
                            .accessibilityIdentifier("duel.decline")
                            .disabled(!store.canStartRequest || !store.freshIDs.contains(duel.id))
                    }
                    if duel.canCancel(actorID: actor, now: Date()),
                       let lifecycle = store.lifecycles[duel.id], lifecycle.finalResult == nil, lifecycle.closure == nil {
                        Button("Cancel duel", role: .destructive) { exitAction = .cancel }
                            .accessibilityIdentifier("duel.cancel")
                            .disabled(!store.canStartRequest || !store.freshIDs.contains(duel.id))
                    }
                    Button("Refresh duel") { Task { await store.refreshDetail(challengeID) } }
                        .disabled(store.isSending)
                }
            } else {
                Text("We couldn’t load this duel. Refresh your duels to try again.")
            }
        }
        .navigationTitle("Duel rules")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.userID) { await store.refreshDetail(challengeID) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshDetail(challengeID) } }
        }
        .onChange(of: model.userID) { _, _ in
            consent = false; exitAction = nil; reviewNotice = nil; safeExit = nil; rematch = nil
        }
        .sheet(item: $rematch) { previous in
            DuelCreateView(store: store, previous: previous).id(model.userID)
        }
        .sheet(item: $reviewNotice) { choice in
            DuelParticipantReviewView(store: store, agreement: choice.agreement, notice: choice.notice)
        }
        .confirmationDialog(safeExit?.title ?? "Leave this duel?",
            isPresented: Binding(get: { safeExit != nil }, set: { if !$0 { safeExit = nil } }),
            titleVisibility: .visible) {
                if let kind = safeExit {
                    Button(kind.title, role: .destructive) {
                        Task { await store.submit(.exit(challengeID: challengeID, kind: kind)) }
                    }
                    .accessibilityIdentifier("duel.confirm-safe-exit")
                }
            } message: {
                Text("This ends your participation. Neither runner loses a simulated stake. Your agreed rules and updates stay in history.")
            }
        .confirmationDialog(exitAction == .decline ? "Decline this invitation?" : "Cancel this duel?",
            isPresented: Binding(get: { exitAction != nil }, set: { if !$0 { exitAction = nil } }),
            titleVisibility: .visible) {
                if let exitAction {
                    Button(exitAction == .decline ? "Decline invitation" : "Cancel duel", role: .destructive) {
                        Task { await store.submit(exitAction == .decline
                            ? .decline(challengeID: challengeID) : .cancel(challengeID: challengeID)) }
                    }
                    .accessibilityIdentifier("duel.confirm-exit")
                }
            } message: {
                Text("This ends the invitation or duel. It stays in your history, and neither of you loses a simulated stake.")
            }
    }
}

private struct DuelParticipantReviewChoice: Identifiable {
    var id: Int { notice.id }
    let agreement: DuelAgreement
    let notice: DuelNotice
}

private enum DuelExitAction { case decline, cancel }

/// Copy applies only after the typed policy exactly matches the supported v1
/// specification. The returned server dates, never a client-created digest,
/// become the authoritative receipt and invitee consent facts.
private struct DuelRulesSections: View {
    let event: DuelEvent
    let terms: DuelTerms?

    var body: some View {
        Section("Your duel at a glance") {
            Text(event.eventName).font(.headline)
            Text("Run the same fictional outdoor 5K course in the same starting wave. One attempt each, no handicap. The faster qualifying finisher wins, using whole-second organizer chip times. Phone or watch times do not count.")
            fact("Starts", event.startsAt)
            fact("Ends", event.endsAt)
            if let terms {
                fact("Agree before", terms.acceptBy)
            } else {
                Text("Your friend must agree within 72 hours of sending, and more than one hour before the race starts, whichever comes first. The exact deadline appears when your invitation is saved.")
            }
            Text("$20 simulated each · $40 combined · $0 fee each. No real money moves; nothing can be redeemed.")
                .accessibilityIdentifier("duel.summary-amount")
            Text("A qualifying finisher wins the combined simulated amount if the other runner has a confirmed nonfinish. A tie, neither runner finishing, or unresolved results returns both amounts after review.")
            Text("You can decline, cancel before the start, withdraw after it starts, or report an injury. Neither runner loses a simulated stake for these exits or a cancelled race.")
            Text("You have seven full days after each saved result notice to ask for review. Any simulated outcome waits for review; missing results alone never mean a loss.")
        }
        Section {
            DisclosureGroup("Full duel rules") {
                VStack(alignment: .leading, spacing: 20) {
                    fullRules
                }
                .padding(.vertical, 8)
            }
            .accessibilityIdentifier("duel.full-rules")
        }
    }

    @ViewBuilder
    private var fullRules: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The race").font(.headline).accessibilityAddTraits(.isHeader)
            Text(event.eventName)
            Text("Course: Fictional 5K course. Starting wave: shared start.")
            Text("5,000 meters outdoors. You run the same course in the same starting wave. One attempt each; no handicap.")
            fact("Starts", event.startsAt)
            fact("Ends", event.endsAt)
            Text("Race time zone: \(event.displayTimezone)")
            Text("Times come from the race organizer: crossing the start to crossing the finish, rounded to whole seconds. Phone or watch times do not count.")
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("Simulated stakes").font(.headline).accessibilityAddTraits(.isHeader)
            Text("$20 USD each · $40 USD combined · $0 fee each.")
            Text("The faster qualifying finisher receives the combined simulated stake. Nothing can be paid out or redeemed.")
            Text("Same time: both simulated stakes returned. A confirmed nonfinish lets the qualifying finisher win after review. If neither finishes, neither loses a simulated stake.")
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("When to agree").font(.headline).accessibilityAddTraits(.isHeader)
            if let terms {
                fact("Agree before", terms.acceptBy)
                fact("Invitation created", terms.createdAt)
            } else {
                Text("Your friend must agree within 72 hours of sending, and more than one hour before the race starts, whichever comes first. The exact deadline appears when your invitation is saved.")
                fact("Latest possible acceptance", event.startsAt.addingTimeInterval(-3600))
            }
            Text("The deadline itself is too late. Opening an invitation does not mean you agreed.")
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("Cancelling and missing results").font(.headline).accessibilityAddTraits(.isHeader)
            Text("Before the race starts, you can cancel an invitation you sent. Once you both agree, either runner can cancel before the start. An invited friend can decline. Neither loses a simulated stake.")
            Text("The rules also return both simulated stakes for withdrawal after the start, injury or a cancelled race.")
            Text("Missing, late or unclear results go to review; they do not automatically mean a loss. If we cannot confirm a result, neither of you loses a simulated stake.")
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("Results and review rules").font(.headline).accessibilityAddTraits(.isHeader)
            fact("Race results due", terms?.resultsDueAt ?? event.endsAt.addingTimeInterval(72 * 3600))
            Text("You have 168 hours to ask for review after a saved result notice. Review lasts up to 168 hours after your request. If review runs out of time, neither loses a simulated stake.")
            fact("Result must be final by", terms?.finalityDueAt ?? event.endsAt.addingTimeInterval(720 * 3600))
            Text("Any simulated outcome waits until the review request deadline has passed and review is complete. Corrections stay in the history and never automatically create a new consequence.")
            Text("Saved result notices and your review requests appear in this duel. Each correction has a new notice and review deadline; earlier updates stay in your history.")
        }
    }

    private func fact(_ title: String, _ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(DuelCodec.dateText(date, zone: event.displayTimezone))
        }
    }
}
#endif
