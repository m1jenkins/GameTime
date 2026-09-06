import Foundation
import Observation

@MainActor
@Observable
final class DuelStore {
    private(set) var invitationLinks: [UUID: DuelInvitationLink] = [:]
    private(set) var pendingInvitationToken: UUID?
    private(set) var resolvedInvitationID: UUID?
    private(set) var invitationError: String?
    @ObservationIgnored private let invitationDefaults: UserDefaults
    private static let invitationKey = "duel_pending_invitation_v1"
    private(set) var lifecycles: [UUID: DuelLifecycle] = [:]
    private(set) var lifecycleErrors: [UUID: String] = [:]
    private(set) var lifecycleReceivedAt: [UUID: Date] = [:]
    private(set) var lastConfirmedOperation: DuelMutation?
    @ObservationIgnored private var detailTokens: [UUID: UUID] = [:]
    private(set) var actorID: UUID?
    private(set) var agreements: [DuelAgreement] = []
    private(set) var friends: [FriendshipCard] = []
    private(set) var catalog = DuelCatalog(events: [], policies: [])
    private(set) var pending: PendingDuelRequest?
    private(set) var storageBlocked = true
    private(set) var isLoading = false
    private(set) var isSending = false
    private(set) var hasMore = false
    private(set) var errorMessage: String?
    private(set) var lastConfirmedID: UUID?
    private(set) var freshIDs: Set<UUID> = []

    private let enabled: Bool
    private let auth: any AuthClient
    private let client: any DuelClient
    private let friendships: any FriendshipsClient
    private let pendingStore: any PendingDuelRequestStore
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var refreshID = UUID()

    init(enabled: Bool, auth: any AuthClient, client: any DuelClient,
         friendships: any FriendshipsClient, pendingStore: any PendingDuelRequestStore,
         invitationDefaults: UserDefaults = .standard) {
        self.invitationDefaults = invitationDefaults
        if enabled, let saved = invitationDefaults.string(forKey: Self.invitationKey) {
            pendingInvitationToken = UUID(uuidString: saved)
        }
        self.enabled = enabled
        self.auth = auth
        self.client = client
        self.friendships = friendships
        self.pendingStore = pendingStore
    }

    /// Synchronous clearing prevents a previous account's rows flashing while
    /// the new account's auth/profile lookup is suspended.
    func setActor(_ actorID: UUID?) {
        generation = UUID()
        refreshID = UUID()
        self.actorID = enabled ? actorID : nil
        agreements = []
        resolvedInvitationID = nil
        invitationError = nil
        lifecycles = [:]
        lifecycleErrors = [:]
        lifecycleReceivedAt = [:]
        detailTokens = [:]
        lastConfirmedOperation = nil
        friends = []
        catalog = DuelCatalog(events: [], policies: [])
        pending = nil
        storageBlocked = true
        freshIDs = []
        invitationLinks = [:]
        isLoading = false
        isSending = false
        hasMore = false
        errorMessage = nil
        lastConfirmedID = nil
    }

    var canStartRequest: Bool {
        actorID != nil && !isSending && !isLoading && !storageBlocked && pending == nil
    }

    func refresh(loadMore: Bool = false) async {
        guard let actor = actorID, !isSending else { return }
        let token = generation
        let refresh = UUID()
        refreshID = refresh
        isLoading = true
        errorMessage = nil
        freshIDs = []
        invitationLinks = [:]
        lifecycles = [:]
        lifecycleReceivedAt = [:]
        lifecycleErrors = [:]
        detailTokens = [:]
        defer { if generation == token && refreshID == refresh { isLoading = false } }
        do {
            let saved = try await pendingStore.load(for: actor)
            guard await current(actor, token), refreshID == refresh else { return }
            pending = saved
            storageBlocked = false
        } catch {
            guard await current(actor, token), refreshID == refresh else { return }
            storageBlocked = true
            errorMessage = DuelClientError.storage.localizedDescription
        }
        do {
            let rows = try await client.list(actorID: actor, before: loadMore ? agreements.last : nil)
            guard await current(actor, token), refreshID == refresh else { return }
            for row in rows { try row.validate(for: actor) }
            if loadMore {
                let ids = Set(agreements.map(\.id))
                agreements += rows.filter { !ids.contains($0.id) }
            } else { agreements = rows }
            freshIDs = Set(agreements.map(\.id))
            hasMore = rows.count == 50
            // Each participant projection is independently authorized. A failed
            // read removes result content; it cannot leave an opponent's cached
            // result visible after a block or session revocation.
            for row in agreements {
                await loadLifecycle(row, actor: actor, token: token, refresh: refresh)
                guard await current(actor, token), refreshID == refresh else { return }
            }
            let catalog = try await client.catalog(actorID: actor)
            guard await current(actor, token), refreshID == refresh else { return }
            self.catalog = catalog
            let friends = try await friendships.listCards()
            guard await current(actor, token), refreshID == refresh else { return }
            self.friends = friends.filter { $0.status == .accepted && $0.otherUserID != actor }
        } catch {
            guard await current(actor, token), refreshID == refresh else { return }
            errorMessage = mapped(error).localizedDescription
            // History can still be read, but stale friend/event choices cannot
            // become a new invitation after a failed catalog refresh.
            friends = []
            catalog = DuelCatalog(events: [], policies: [])
        }
    }

    func refreshDetail(_ id: UUID) async {
        guard let actor = actorID, !isSending else { return }
        let token = generation
        let contentToken = refreshID
        let detailToken = UUID()
        detailTokens[id] = detailToken
        lifecycles[id] = nil
        lifecycleReceivedAt[id] = nil
        lifecycleErrors[id] = nil
        freshIDs.remove(id)
        invitationLinks[id] = nil
        do {
            let row = try await client.detail(id: id, actorID: actor)
            guard await current(actor, token), refreshID == contentToken, detailTokens[id] == detailToken else { return }
            try row.validate(for: actor)
            upsert(row)
            freshIDs.insert(id)
            await loadLifecycle(row, actor: actor, token: token, refresh: contentToken, detailToken: detailToken)
        } catch {
            guard await current(actor, token), refreshID == contentToken, detailTokens[id] == detailToken else { return }
            if mapped(error) == .accessDenied { agreements.removeAll { $0.id == id } }
            lifecycleErrors[id] = "We couldn’t load your result updates. Refresh this duel to try again."
            errorMessage = mapped(error).localizedDescription
        }
    }

    func submit(_ operation: DuelMutation) async {
        guard canStartRequest, let actor = actorID else { return }
        if let id = operation.challengeID, !freshIDs.contains(id) { return }
        if case .rematch(let id, _, _, _) = operation, !canRematch(id) { return }
        if case .fileReview(let id, let revision, _) = operation,
           !canFileReview(id, revision: revision) { return }
        if case .exit(let id, _) = operation, !canExit(id) { return }
        if case .cancel(let id) = operation,
           let lifecycle = lifecycles[id], lifecycle.finalResult != nil || lifecycle.closure != nil { return }
        let token = generation
        isSending = true
        errorMessage = nil
        lastConfirmedID = nil
        lastConfirmedOperation = nil
        defer { if generation == token { isSending = false } }
        do {
            guard await current(actor, token) else { return }
            let request = try PendingDuelRequest(actorID: actor, operation: operation)
            try await pendingStore.save(request)
            guard await current(actor, token) else { return }
            pending = request
            await send(request, token: token)
        } catch {
            guard await current(actor, token) else { return }
            storageBlocked = true
            errorMessage = DuelClientError.storage.localizedDescription
        }
    }

    /// Never called by refresh, foregrounding or signing in. The actor must
    /// explicitly retry the durable, unchanged request.
    func retry() async {
        guard let pending, !isSending, !isLoading, !storageBlocked else { return }
        let token = generation
        isSending = true
        errorMessage = nil
        defer { if generation == token { isSending = false } }
        await send(pending, token: token)
    }

    private func send(_ saved: PendingDuelRequest, token: UUID) async {
        let actor = saved.actorID
        guard await current(actor, token) else { return }
        var request = saved
        request.mayHaveCommitted = true
        var receivedCommit = false
        do {
            // Mark before sending: termination between the send and response
            // handler must be recoverable too.
            try await pendingStore.save(request)
            guard await current(actor, token) else { return }
            pending = request
            refreshID = UUID()
            freshIDs = []
            invitationLinks = [:]
            lifecycles = [:]
            lifecycleReceivedAt = [:]
            let receiptID = try await client.submit(request)
            // Review RPCs return a case UUID. The immutable request always
            // owns the duel destination; never route using the case receipt.
            let id = request.operation.challengeID ?? receiptID
            if !request.operation.isLifecycle && request.operation.challengeID != nil && receiptID != id {
                throw DuelClientError.invalidResponse
            }
            if case .exit = request.operation, receiptID != id { throw DuelClientError.invalidResponse }
            receivedCommit = true
            guard await current(actor, token) else { return }
            let row = try await client.detail(id: id, actorID: actor)
            guard await current(actor, token) else { return }
            try row.validate(for: actor)
            let lifecycle = try await client.lifecycle(id: id, actorID: actor)
            guard await current(actor, token) else { return }
            try lifecycle.validate(agreement: row, actorID: actor)
            if case .fileReview(_, let revision, let reason) = request.operation {
                guard lifecycle.reviews.contains(where: {
                    $0.id == receiptID && $0.proofRevision == revision && $0.reason == reason
                }) else { throw DuelClientError.invalidResponse }
            }
            try await pendingStore.remove(for: actor, matching: request.requestID)
            guard await current(actor, token) else { return }
            pending = nil
            upsert(row)
            freshIDs.insert(id)
            lifecycles[id] = lifecycle
            lifecycleReceivedAt[id] = Date()
            lifecycleErrors[id] = nil
            lastConfirmedID = id
            lastConfirmedOperation = request.operation
            await loadInvitationLink(row, actor: actor, token: token, refresh: refreshID)
        } catch {
            guard await current(actor, token) else { return }
            let failure = mapped(error)
            // A first, definite rejection cannot have committed. After any
            // uncertainty retain the key, even through an admission denial.
            if failure.isDefinitiveRejection && !saved.mayHaveCommitted && !receivedCommit {
                do {
                    try await pendingStore.remove(for: actor, matching: saved.requestID)
                    guard await current(actor, token) else { return }
                    pending = nil
                } catch { storageBlocked = true }
            }
            if [.lifecycle, .reviewAlreadyFiled, .exitAlreadySaved].contains(failure),
               let id = saved.operation.challengeID {
                freshIDs.remove(id)
                invitationLinks[id] = nil
                if let row = try? await client.detail(id: id, actorID: actor),
                    await current(actor, token), (try? row.validate(for: actor)) != nil {
                    upsert(row)
                    freshIDs.insert(id)
                    await loadLifecycle(row, actor: actor, token: token, refresh: refreshID)
                }
            }
            guard await current(actor, token) else { return }
            errorMessage = failure.localizedDescription
        }
    }

    private func loadLifecycle(_ row: DuelAgreement, actor: UUID, token: UUID, refresh: UUID,
                               detailToken: UUID? = nil) async {
        let readToken = detailToken ?? UUID()
        detailTokens[row.id] = readToken
        do {
            let lifecycle = try await client.lifecycle(id: row.id, actorID: actor)
            guard await current(actor, token), refreshID == refresh,
                  detailTokens[row.id] == readToken else { return }
            try lifecycle.validate(agreement: row, actorID: actor)
            lifecycles[row.id] = lifecycle
            lifecycleReceivedAt[row.id] = Date()
            lifecycleErrors[row.id] = nil
            await loadInvitationLink(row, actor: actor, token: token, refresh: refresh)
        } catch {
            guard await current(actor, token), refreshID == refresh,
                  detailTokens[row.id] == readToken else { return }
            lifecycles[row.id] = nil
            lifecycleReceivedAt[row.id] = nil
            lifecycleErrors[row.id] = "We couldn’t load your result updates. Refresh this duel to try again."
        }
    }

    /// Server-clock estimate is a UI hint. Every write is rechecked under
    /// database locks; crossing a boundary can still reject a tap safely.
    func estimatedNow(for id: UUID, at now: Date = Date()) -> DuelInstant? {
        guard let row = lifecycles[id], let received = lifecycleReceivedAt[id] else { return nil }
        return DuelInstant(date: row.serverNow.date.addingTimeInterval(max(0, now.timeIntervalSince(received))))
    }

    func canFileReview(_ id: UUID, revision: Int, at now: Date = Date()) -> Bool {
        guard canStartRequest, freshIDs.contains(id), let row = lifecycles[id],
              let notice = row.notices.first(where: { $0.proofRevision == revision }),
              notice.canFileReview, let clock = estimatedNow(for: id, at: now),
              let agreement = agreements.first(where: { $0.id == id }) else { return false }
        return clock < notice.disputeClosesAt && clock.date < agreement.terms.finalityDueAt
    }

    func canExit(_ id: UUID, at now: Date = Date()) -> Bool {
        guard canStartRequest, freshIDs.contains(id), lifecycles[id]?.canExit == true,
              let clock = estimatedNow(for: id, at: now),
              let agreement = agreements.first(where: { $0.id == id }) else { return false }
        return clock.date < agreement.terms.finalityDueAt
    }

    func canRematch(_ id: UUID) -> Bool {
        guard canStartRequest, freshIDs.contains(id), let life = lifecycles[id],
              !life.contactSuppressed, life.finalResult != nil else { return false }
        return true
    }

    private func loadInvitationLink(_ row: DuelAgreement, actor: UUID, token: UUID, refresh: UUID) async {
        guard row.creatorID == actor, row.status == .invited,
              lifecycles[row.id]?.contactSuppressed == false else { return }
        let detailToken = detailTokens[row.id]
        let link = try? await client.invitationLink(id: row.id, actorID: actor)
        guard await current(actor, token), refreshID == refresh, detailTokens[row.id] == detailToken else { return }
        invitationLinks[row.id] = link
    }

    func receiveInvitation(_ url: URL) {
        guard enabled, let token = DuelInvitationLink.token(from: url) else { return }
        pendingInvitationToken = token
        resolvedInvitationID = nil
        invitationError = nil
        // Persist only an untrusted locator, never a result, actor or auth token.
        invitationDefaults.set(token.uuidString, forKey: Self.invitationKey)
    }

    func dismissInvitation() {
        pendingInvitationToken = nil
        resolvedInvitationID = nil
        invitationError = nil
        invitationDefaults.removeObject(forKey: Self.invitationKey)
    }

    func openPendingInvitation() async {
        guard let actor = actorID, let locator = pendingInvitationToken else { return }
        let token = generation
        invitationError = nil
        do {
            await refresh()
            guard await current(actor, token), pendingInvitationToken == locator else { return }
            let id = try await client.resolveInvitation(token: locator, actorID: actor)
            guard await current(actor, token), pendingInvitationToken == locator else { return }
            await refreshDetail(id)
            guard await current(actor, token), pendingInvitationToken == locator,
                  freshIDs.contains(id), lifecycles[id]?.contactSuppressed == false else { return }
            resolvedInvitationID = id
            pendingInvitationToken = nil
            invitationDefaults.removeObject(forKey: Self.invitationKey)
        } catch {
            guard await current(actor, token), pendingInvitationToken == locator else { return }
            invitationError = "We couldn’t open this invitation. Sign in as the friend it was sent to, or ask them for a new link."
        }
    }

    private func current(_ actor: UUID, _ token: UUID) async -> Bool {
        let live = await auth.currentUserID()
        return generation == token && actorID == actor && live == actor
    }

    private func upsert(_ row: DuelAgreement) {
        if let index = agreements.firstIndex(where: { $0.id == row.id }) { agreements[index] = row }
        else { agreements.insert(row, at: 0) }
    }

    private func mapped(_ error: Error) -> DuelClientError {
        (error as? DuelClientError) ?? .unavailable
    }
}
