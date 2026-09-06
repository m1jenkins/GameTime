import Foundation
import Observation

@MainActor @Observable final class WeeklyStore {
    private(set) var actorID: UUID?
    private(set) var challenges: [WeeklyChallenge] = []
    private(set) var cohorts: [WeeklyCohort] = []
    private(set) var friends: [FriendshipCard] = []
    private(set) var sharing: [UUID: [WeeklySharing]] = [:]
    private(set) var followRequests: [WeeklyFollowRequest] = []
    private(set) var sharedProgress: [WeeklySharedProgress] = []
    private(set) var studyUnavailable = false
    private(set) var preferences: WeeklyPreferences?
    private(set) var previewed: WeeklyPreview?
    private(set) var pending: PendingWeeklyRequest?
    private(set) var isLoading = false
    private(set) var isSending = false
    private(set) var storageBlocked = true
    private(set) var errorMessage: String?
    private(set) var lastConfirmedID: UUID?
    private(set) var lastConfirmedOperation: WeeklyMutation?
    private(set) var freshIDs: Set<UUID> = []
    @ObservationIgnored private var socialRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var socialExpiryTask: Task<Void, Never>?
    @ObservationIgnored private var socialReceivedAt: Double?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var refreshToken = UUID()
    @ObservationIgnored private var receivedAt: [UUID: Double] = [:]
    @ObservationIgnored private var recordedStudyEvents: Set<String> = []
    private let waitForSocialExpiry: @MainActor (Double) async throws -> Void
    private let monotonicNow: () -> Double
    private let enabled: Bool
    private let auth: any AuthClient
    private let client: any WeeklyClient
    private let friendships: any FriendshipsClient
    private let pendingStore: any PendingWeeklyRequestStore

    init(enabled: Bool, auth: any AuthClient, client: any WeeklyClient, friendships: any FriendshipsClient,
         pendingStore: any PendingWeeklyRequestStore, monotonicNow: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         waitForSocialExpiry: @escaping @MainActor (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.monotonicNow = monotonicNow
        self.waitForSocialExpiry = waitForSocialExpiry
        self.enabled = enabled; self.auth = auth; self.client = client; self.friendships = friendships; self.pendingStore = pendingStore
    }
    func setActor(_ id: UUID?) {
        cancelSocialRefresh()
        generation = UUID(); refreshToken = UUID(); actorID = enabled ? id : nil
        clearContent(); pending = nil; storageBlocked = true; isLoading = false; isSending = false
        errorMessage = nil; lastConfirmedID = nil; lastConfirmedOperation = nil
        studyUnavailable = false; recordedStudyEvents = []
    }
    private func clearContent() {
        challenges = []; cohorts = []; friends = []; preferences = nil; previewed = nil; freshIDs = []; receivedAt = [:]
        clearSocial()
    }
    var canStartRequest: Bool { actorID != nil && !isLoading && !isSending && !storageBlocked && pending == nil }
    var canEnter: Bool { canStartRequest && preferences?.paused == false }
    func invalidatePreview() { refreshToken = UUID(); previewed = nil; isLoading = false }
    func beginCreation() {
        invalidatePreview(); lastConfirmedID = nil; lastConfirmedOperation = nil
    }

    func refresh() async {
        guard let actor = actorID, !isSending else { return }
        cancelSocialRefresh()
        let generation = generation, token = UUID()
        refreshToken = token; clearContent(); isLoading = true; errorMessage = nil
        defer { if self.generation == generation && refreshToken == token { isLoading = false } }
        do {
            let saved = try await pendingStore.load(for: actor)
            guard await current(actor, generation), refreshToken == token else { return }
            pending = saved; storageBlocked = false
        } catch {
            guard await current(actor, generation), refreshToken == token else { return }
            storageBlocked = true; errorMessage = WeeklyClientError.storage.localizedDescription
        }
        do {
            let rows = try await client.list(actorID: actor)
            guard await current(actor, generation), refreshToken == token else { return }
            for row in rows { try row.validate(for: actor) }
            challenges = rows; freshIDs = Set(rows.map(\.id))
            receivedAt = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, monotonicNow()) })
            let preferences = try await client.preferences(actorID: actor)
            guard await current(actor, generation), refreshToken == token else { return }
            self.preferences = preferences
            let cohorts = try await client.cohorts(actorID: actor)
            guard await current(actor, generation), refreshToken == token else { return }
            self.cohorts = cohorts
            isLoading = false
            beginSocialRefresh(rows: rows, actor: actor, generation: generation, token: token)
            await socialRefreshTask?.value
        } catch {
            guard await current(actor, generation), refreshToken == token else { return }
            clearContent(); errorMessage = mapped(error).localizedDescription
        }
    }

    func preview(_ draft: WeeklyDraft) async {
        guard canEnter, let actor = actorID else { return }
        let generation = generation, token = UUID()
        refreshToken = token; isLoading = true; previewed = nil; errorMessage = nil
        defer { if self.generation == generation && refreshToken == token { isLoading = false } }
        do {
            guard draft.participants.filter({ $0.actorID != actor }).allSatisfy({ p in friends.contains { $0.otherUserID == p.actorID } }) else { throw WeeklyClientError.accessDenied }
            let result = try await client.preview(draft, actorID: actor)
            guard await current(actor, generation), refreshToken == token else { return }
            try result.validate(actorID: actor, draft: draft)
            previewed = result
            queueStudy(event: "rule_preview", challengeID: nil, phase: "exposure", actor: actor, generation: generation)
        } catch {
            guard await current(actor, generation), refreshToken == token else { return }
            errorMessage = mapped(error).localizedDescription
        }
    }

    func submit(_ operation: WeeklyMutation) async {
        guard canStartRequest, let actor = actorID else { return }
        switch operation {
        case .create(let preview): guard canEnter, previewed == preview else { return }
        case .join(let id, let digest): guard canEnter, cohorts.contains(where: { $0.id == id && $0.termsDigest == digest && $0.participantCount < $0.capacity }) else { return }
        case .accept(let id, let digest): guard canEnter, canAccept(id), challenges.contains(where: { $0.id == id && $0.termsDigest == digest }) else { return }
        case .review(let id, let revision, _): guard canReview(id, revision: revision) else { return }
        case .exit(let id, _): guard canExit(id) else { return }
        case .support(let id, _), .progress(let id, _, _): guard freshIDs.contains(id) else { return }
        case .share(let id, _, _): guard freshIDs.contains(id) else { return }
        case .follow(let id, let owner, let offer, let decision):
            guard decision == .unfollow ? sharedProgress.contains(where: { $0.challengeID == id && $0.ownerID == owner }) : followRequests.contains(where: { $0.offerID == offer && $0.challengeID == id && $0.ownerID == owner }) else { return }
        case .pause, .pilotConsent: guard preferences != nil else { return }
        }
        cancelSocialRefresh(); clearSocial()
        let generation = generation
        isSending = true; errorMessage = nil; lastConfirmedID = nil; lastConfirmedOperation = nil
        defer { if self.generation == generation { isSending = false } }
        do {
            let request = try PendingWeeklyRequest(actorID: actor, operation: operation)
            try await pendingStore.save(request)
            guard await current(actor, generation) else { return }
            pending = request
            await send(request, generation)
        } catch {
            guard await current(actor, generation) else { return }
            storageBlocked = true; errorMessage = WeeklyClientError.storage.localizedDescription
        }
    }
    /// Only a deliberate retry sends a previously uncertain operation.
    func retry() async {
        guard let request = pending, !isLoading, !isSending, !storageBlocked else { return }
        cancelSocialRefresh(); clearSocial()
        let generation = generation
        isSending = true; errorMessage = nil
        defer { if self.generation == generation { isSending = false } }
        await send(request, generation)
    }
    /// Server-side retirement fences a delayed original before any local removal.
    func resolveSavedRequest() async {
        guard let request = pending, !isLoading, !isSending, !storageBlocked else { return }
        cancelSocialRefresh(); clearSocial()
        let generation = generation
        isSending = true; errorMessage = nil
        do {
            let resolution = try await client.resolveRequest(request)
            guard await current(request.actorID, generation) else { return }
            if resolution.state == "committed" {
                await send(request, generation)
            } else if resolution.state == "cancelled" && resolution.receiptID == nil {
                try await pendingStore.remove(for: request.actorID, matching: request.requestID)
                guard await current(request.actorID, generation) else { return }
                pending = nil
            } else { throw WeeklyClientError.invalidResponse
            }
        } catch {
            guard await current(request.actorID, generation) else { return }
            errorMessage = mapped(error).localizedDescription
        }
        guard await current(request.actorID, generation) else { return }
        isSending = false
        if pending == nil { await refresh() }
    }
    private func send(_ saved: PendingWeeklyRequest, _ generation: UUID) async {
        let actor = saved.actorID
        var request = saved
        var receivedCommit = false
        do {
            guard await current(actor, generation) else { return }
            request.mayHaveCommitted = true
            try await pendingStore.save(request)
            guard await current(actor, generation) else { return }
            pending = request; refreshToken = UUID(); previewed = nil; freshIDs = []; receivedAt = [:]
            clearSocial()
            let receipt = try await client.submit(request)
            receivedCommit = true
            guard await current(actor, generation) else { return }
            if case .pause(let paused) = request.operation {
                guard receipt == request.requestID else { throw WeeklyClientError.invalidResponse }
                let preferences = try await client.preferences(actorID: actor)
                guard await current(actor, generation) else { return }
                guard preferences.paused == paused else { throw WeeklyClientError.invalidResponse }
                self.preferences = preferences
            } else if case .pilotConsent(let enabled) = request.operation {
                guard receipt == request.requestID else { throw WeeklyClientError.invalidResponse }
                let preferences = try await client.preferences(actorID: actor)
                guard await current(actor, generation) else { return }
                guard preferences.pilotConsent == enabled else { throw WeeklyClientError.invalidResponse }
                self.preferences = preferences
            } else if case .follow = request.operation {
                guard receipt == request.requestID else { throw WeeklyClientError.invalidResponse }
                // The recipient need not be enrolled in the owner's challenge.
                let socialReadAt = monotonicNow()
                let shared = try await client.sharedProgress(actorID: actor)
                let offers = try await client.followRequests(actorID: actor)
                guard await current(actor, generation) else { return }
                let socialAge = monotonicNow() - socialReadAt
                if socialAge.isFinite && socialAge >= 0 && socialAge < 60 {
                    sharedProgress = shared; followRequests = offers
                    armSocialExpiry(receivedAt: socialReadAt)
                }
            } else {
                let id = request.operation.challengeID ?? receipt
                let row = try await client.detail(id: id, actorID: actor)
                guard await current(actor, generation) else { return }
                try row.validate(for: actor)
                switch request.operation {
                case .create(let preview): guard receipt == row.id, row.terms == preview.terms, row.termsDigest == preview.termsDigest, row.own.acceptedAt != nil else { throw WeeklyClientError.invalidResponse }
                case .accept(_, let digest), .join(_, let digest): guard receipt == row.id, row.termsDigest == digest, row.own.acceptedAt != nil else { throw WeeklyClientError.invalidResponse }
                case .exit(_, let kind): guard receipt == row.id, row.exits.contains(where: { $0.id == request.requestID && $0.kind == kind.rawValue }) else { throw WeeklyClientError.invalidResponse }
                case .review(_, let revision, let reason): guard row.cases.contains(where: { $0.id == receipt && $0.noticeRevision == revision && $0.reason == reason }) else { throw WeeklyClientError.invalidResponse }
                case .support(_, let reason): guard row.support.contains(where: { $0.id == receipt && $0.reason == reason }) else { throw WeeklyClientError.invalidResponse }
                case .progress: guard receipt == request.requestID else { throw WeeklyClientError.invalidResponse }
                case .share(_, let friend, let enabled):
                    guard receipt == request.requestID else { throw WeeklyClientError.invalidResponse }
                    let socialReadAt = monotonicNow()
                    let grants = try await client.sharing(id: id, actorID: actor)
                    guard await current(actor, generation) else { return }
                    guard grants.contains(where: { $0.friendID == friend && $0.enabled == enabled }) || (!enabled && !grants.contains(where: { $0.friendID == friend })) else { throw WeeklyClientError.invalidResponse }
                    let socialAge = monotonicNow() - socialReadAt
                    if socialAge.isFinite && socialAge >= 0 && socialAge < 60 {
                        sharing[id] = grants
                        armSocialExpiry(receivedAt: socialReadAt)
                    }
                case .pause, .pilotConsent, .follow: break
                }
                challenges.removeAll { $0.id == id }; challenges.insert(row, at: 0)
                freshIDs.insert(id); receivedAt[id] = monotonicNow(); lastConfirmedID = id
            }
            try await pendingStore.remove(for: actor, matching: request.requestID)
            guard await current(actor, generation) else { return }
            pending = nil; lastConfirmedOperation = request.operation
            let event: String?
            switch request.operation {
            case .create, .accept: event = "consent"
            case .join: event = "cohort_join"
            case .review: event = "review"
            case .exit: event = "withdrawal"
            case .progress: event = "progress_refresh"
            case .share, .follow: event = "sharing"
            case .support, .pause, .pilotConsent: event = nil
            }
            if let event { queueStudy(event: event, challengeID: lastConfirmedID, phase: "outcome", actor: actor, generation: generation) }
        } catch {
            guard await current(actor, generation) else { return }
            let failure = mapped(error)
            if failure.definitive && !saved.mayHaveCommitted && !receivedCommit {
                do { try await pendingStore.remove(for: actor, matching: request.requestID)
                    guard await current(actor, generation) else { return }; pending = nil
                } catch { storageBlocked = true }
            }
            clearContent(); errorMessage = failure.localizedDescription
        }
    }

    private func queueStudy(event: String, challengeID: UUID?, phase: String, actor: UUID, generation: UUID) {
        Task { [weak self] in
            guard let self, await self.current(actor, generation) else { return }
            await self.recordStudy(event: event, challengeID: challengeID, phase: phase)
        }
    }

    private func beginSocialRefresh(rows: [WeeklyChallenge], actor: UUID, generation: UUID, token: UUID) {
        let acceptedIDs = rows.compactMap { $0.own.acceptedAt == nil ? nil : $0.id }
        socialRefreshTask = Task { [weak self] in
            await self?.refreshSocial(acceptedIDs: acceptedIDs, actor: actor, generation: generation, token: token)
        }
    }

    private func refreshSocial(acceptedIDs: [UUID], actor: UUID, generation: UUID, token: UUID) async {
        let socialReadAt = monotonicNow()
        do {
            guard await socialRefreshIsCurrent(actor, generation, token) else { return }
            let shared = try await client.sharedProgress(actorID: actor)
            guard await socialRefreshIsCurrent(actor, generation, token) else { return }
            let offers = try await client.followRequests(actorID: actor)
            guard await socialRefreshIsCurrent(actor, generation, token) else { return }
            let grants = try await sharingSnapshot(ids: acceptedIDs, actor: actor, generation: generation, token: token)
            guard await socialRefreshIsCurrent(actor, generation, token) else { return }
            let cards = try await friendships.listCards()
            guard await socialRefreshIsCurrent(actor, generation, token) else { return }
            let socialAge = monotonicNow() - socialReadAt
            guard socialAge.isFinite, socialAge >= 0, socialAge < 60 else {
                clearSocial()
                return
            }
            sharedProgress = shared; followRequests = offers; sharing = grants
            friends = cards.filter { $0.status == .accepted && $0.otherUserID != actor }
            armSocialExpiry(receivedAt: socialReadAt)
            socialRefreshTask = nil
        } catch {
            guard await socialRefreshIsCurrent(actor, generation, token) else { return }
            clearSocial(); socialRefreshTask = nil
        }
    }

    private func sharingSnapshot(ids: [UUID], actor: UUID, generation: UUID, token: UUID) async throws -> [UUID: [WeeklySharing]] {
        var partitions = [[UUID]](repeating: [], count: 4)
        for (index, id) in ids.enumerated() { partitions[index % 4].append(id) }
        let firstIDs = partitions[0], secondIDs = partitions[1]
        let thirdIDs = partitions[2], fourthIDs = partitions[3]
        async let first = sharingPartition(ids: firstIDs, actor: actor, generation: generation, token: token)
        async let second = sharingPartition(ids: secondIDs, actor: actor, generation: generation, token: token)
        async let third = sharingPartition(ids: thirdIDs, actor: actor, generation: generation, token: token)
        async let fourth = sharingPartition(ids: fourthIDs, actor: actor, generation: generation, token: token)
        let snapshots = try await [first, second, third, fourth]
        return snapshots.reduce(into: [:]) { result, snapshot in
            result.merge(snapshot) { _, latest in latest }
        }
    }

    private func sharingPartition(ids: [UUID], actor: UUID, generation: UUID, token: UUID) async throws -> [UUID: [WeeklySharing]] {
        var result: [UUID: [WeeklySharing]] = [:]
        for id in ids {
            guard await socialRefreshIsCurrent(actor, generation, token) else { throw CancellationError() }
            let grants = try await client.sharing(id: id, actorID: actor)
            guard await socialRefreshIsCurrent(actor, generation, token) else { throw CancellationError() }
            result[id] = grants
        }
        return result
    }

    private func socialRefreshIsCurrent(_ actor: UUID, _ generation: UUID, _ token: UUID) async -> Bool {
        guard await current(actor, generation) else { return false }
        return !Task.isCancelled && refreshToken == token
    }

    private func cancelSocialRefresh() {
        socialRefreshTask?.cancel(); socialRefreshTask = nil
    }

    /// Optional, coarse first-party study delivery never owns the safety-request queue.
    func recordStudy(event: String, challengeID: UUID?, phase: String) async {
        guard preferences?.pilotConsent == true, let actor = actorID else { return }
        let generation = generation, key = "\(event)/\(phase)/\(challengeID?.uuidString ?? "none")"
        guard !recordedStudyEvents.contains(key) else { return }
        recordedStudyEvents.insert(key)
        do {
            try await client.recordPilotEvent(actorID: actor, challengeID: challengeID, event: event, phase: phase, requestID: UUID())
            guard await current(actor, generation) else { return }
            studyUnavailable = false
        } catch {
            guard await current(actor, generation) else { return }
            studyUnavailable = true
        }
    }

    private func clearSocial() {
        socialExpiryTask?.cancel(); socialExpiryTask = nil; socialReceivedAt = nil
        sharing = [:]; sharedProgress = []; followRequests = []; friends = []
    }
    private func armSocialExpiry(receivedAt: Double? = nil) {
        socialExpiryTask?.cancel()
        socialReceivedAt = receivedAt ?? monotonicNow()
        expireSocialIfNeeded()
        guard let received = socialReceivedAt else { return }
        let remaining = max(0, 60 - (monotonicNow() - received))
        let generation = generation, wait = waitForSocialExpiry
        socialExpiryTask = Task { [weak self] in
            do { try await wait(remaining) } catch { return }
            guard let self, self.generation == generation else { return }
            self.expireSocialIfNeeded()
        }
    }
    /// Removes private labels/totals even if an idle foreground screen never refreshes.
    func expireSocialIfNeeded() {
        guard let received = socialReceivedAt else { return }
        let elapsed = monotonicNow() - received
        if !elapsed.isFinite || elapsed < 0 || elapsed >= 60 {
            sharing = [:]; sharedProgress = []; followRequests = []; friends = []
            socialReceivedAt = nil
        }
    }
    func estimatedNow(_ row: WeeklyChallenge) -> WeeklyInstant? {
        guard freshIDs.contains(row.id), let received = receivedAt[row.id] else { return nil }
        let elapsed = monotonicNow() - received
        guard elapsed.isFinite, elapsed >= 0, elapsed <= 60 else { return nil }
        return WeeklyInstant(date: row.serverNow.date.addingTimeInterval(elapsed))
    }
    func canAccept(_ id: UUID) -> Bool {
        guard canStartRequest, let row = challenges.first(where: { $0.id == id }), let now = estimatedNow(row),
              !row.contactSuppressed, ["invited", "scheduled"].contains(row.status), row.own.acceptedAt == nil, row.own.exitedAt == nil else { return false }
        return now.microseconds < row.terms.fields.startsAt.microseconds - 3_600_000_000
    }
    func canDecline(_ id: UUID) -> Bool {
        guard canStartRequest, let row = challenges.first(where: { $0.id == id }), let now = estimatedNow(row),
              row.own.acceptedAt == nil, row.own.exitedAt == nil, row.result == nil else { return false }
        return now.microseconds < row.terms.fields.startsAt.microseconds - 3_600_000_000
    }
    func canExit(_ id: UUID) -> Bool {
        guard canStartRequest, let row = challenges.first(where: { $0.id == id }), estimatedNow(row) != nil else { return false }
        return row.status != "final" && row.result == nil && row.own.exitedAt == nil
    }
    func canReview(_ id: UUID, revision: Int) -> Bool {
        guard canStartRequest, let row = challenges.first(where: { $0.id == id }), let now = estimatedNow(row),
              row.result == nil, let notice = row.notices.first(where: { $0.revision == revision }),
              !row.cases.contains(where: { $0.noticeRevision == revision }) else { return false }
        return now < notice.fileBy && now < row.terms.fields.lifecycle.finalityBy
    }
    private func current(_ actor: UUID, _ generation: UUID) async -> Bool {
        let live = await auth.currentUserID()
        return self.generation == generation && actorID == actor && live == actor
    }
    private func mapped(_ error: Error) -> WeeklyClientError { (error as? WeeklyClientError) ?? .unavailable }
}
