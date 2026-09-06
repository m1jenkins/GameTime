import Foundation
import Observation

@MainActor
@Observable
final class PerformanceCommitmentStore {
    private(set) var actorID: UUID?
    private(set) var agreements: [PerformanceCommitmentAgreement] = []
    private(set) var lifecycles: [UUID: PerformanceCommitmentLifecycle] = [:]
    private(set) var lifecycleErrors: [UUID: String] = [:]
    private(set) var lifecycleReceivedAt: [UUID: Date] = [:]
    private(set) var freshIDs: Set<UUID> = []
    private(set) var pending: PendingPerformanceCommitmentRequest?
    private(set) var previewedTerms: PerformanceCommitmentPreview?
    private(set) var previewedDraft: PerformanceCommitmentDraft?
    private(set) var storageBlocked = true
    private(set) var isLoading = false
    private(set) var isSending = false
    private(set) var isPreviewing = false
    private(set) var hasMore = false
    private(set) var errorMessage: String?
    private(set) var lastConfirmedID: UUID?
    private(set) var lastConfirmedOperation: PerformanceCommitmentMutation?

    private let enabled: Bool
    private let auth: any AuthClient
    private let client: any PerformanceCommitmentClient
    private let pendingStore: any PendingPerformanceCommitmentRequestStore
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var readToken = UUID()
    @ObservationIgnored private var previewToken = UUID()

    init(enabled: Bool, auth: any AuthClient, client: any PerformanceCommitmentClient,
         pendingStore: any PendingPerformanceCommitmentRequestStore) {
        self.enabled = enabled
        self.auth = auth
        self.client = client
        self.pendingStore = pendingStore
    }

    func setActor(_ actorID: UUID?) {
        generation = UUID()
        self.actorID = enabled ? actorID : nil
        clearVisibleContent()
        pending = nil
        storageBlocked = true
        isSending = false
        errorMessage = nil
    }

    /// Called on account changes and when the feature leaves the foreground.
    /// The durable request remains available for explicit recovery.
    func clearVisibleContent() {
        readToken = UUID()
        invalidatePreview()
        clearOwnerContent()
        isLoading = false
        lastConfirmedID = nil
        lastConfirmedOperation = nil
    }

    func invalidatePreview() {
        previewToken = UUID()
        previewedTerms = nil
        previewedDraft = nil
        isPreviewing = false
    }

    var canStartRequest: Bool {
        actorID != nil && !isSending && !isLoading && !isPreviewing && !storageBlocked && pending == nil
    }

    func preview(_ draft: PerformanceCommitmentDraft) async {
        guard canStartRequest, let actor = actorID else { return }
        invalidatePreview()
        let operationToken = previewToken
        let accountToken = generation
        isPreviewing = true
        errorMessage = nil
        defer { if generation == accountToken && previewToken == operationToken { isPreviewing = false } }
        do {
            try draft.validate()
            let preview = try await client.preview(draft, actorID: actor)
            guard await current(actor, accountToken), previewToken == operationToken else { return }
            try preview.validate(for: actor)
            guard draft.matches(preview.terms) else { throw PerformanceCommitmentClientError.invalidResponse }
            previewedTerms = preview
            previewedDraft = draft
        } catch {
            guard await current(actor, accountToken), previewToken == operationToken else { return }
            clearVisibleContent()
            errorMessage = mapped(error).localizedDescription
        }
    }

    func refresh(loadMore: Bool = false) async {
        guard let actor = actorID, !isSending else { return }
        let accountToken = generation
        let token = UUID()
        let previous = loadMore ? agreements : []
        let cursor = loadMore ? agreements.last : nil
        readToken = token
        invalidatePreview()
        clearOwnerContent()
        isLoading = true
        errorMessage = nil
        defer { if generation == accountToken && readToken == token { isLoading = false } }
        do {
            let saved = try await pendingStore.load(for: actor)
            guard await current(actor, accountToken), readToken == token else { return }
            if let saved { try saved.validate(for: actor) }
            pending = saved
            storageBlocked = false
        } catch {
            guard await current(actor, accountToken), readToken == token else { return }
            storageBlocked = true
            pending = nil
            errorMessage = PerformanceCommitmentClientError.storage.localizedDescription
        }
        do {
            let page = try await client.list(actorID: actor, before: cursor)
            guard await current(actor, accountToken), readToken == token else { return }
            for row in page { try row.validate(for: actor) }
            let existingIDs = Set(previous.map(\.id))
            let rows = previous + page.filter { !existingIDs.contains($0.id) }
            var results: [UUID: PerformanceCommitmentLifecycle] = [:]
            var received: [UUID: Date] = [:]
            for row in rows {
                let lifecycle = try await client.lifecycle(id: row.id, actorID: actor)
                guard await current(actor, accountToken), readToken == token else { return }
                try lifecycle.validate(agreement: row, actorID: actor)
                results[row.id] = lifecycle
                received[row.id] = Date()
            }
            agreements = rows
            lifecycles = results
            lifecycleReceivedAt = received
            freshIDs = Set(rows.map(\.id))
            hasMore = page.count == 50
        } catch {
            guard await current(actor, accountToken), readToken == token else { return }
            clearVisibleContent()
            errorMessage = mapped(error).localizedDescription
        }
    }

    func refreshDetail(_ id: UUID) async {
        guard let actor = actorID, !isSending else { return }
        let accountToken = generation
        let token = UUID()
        readToken = token
        invalidatePreview()
        // A detail failure cannot retain goal facts or an older result.
        agreements.removeAll { $0.id == id }
        lifecycles[id] = nil
        lifecycleReceivedAt[id] = nil
        lifecycleErrors[id] = nil
        freshIDs.remove(id)
        isLoading = true
        errorMessage = nil
        defer { if generation == accountToken && readToken == token { isLoading = false } }
        do {
            let row = try await client.detail(id: id, actorID: actor)
            guard await current(actor, accountToken), readToken == token else { return }
            try row.validate(for: actor)
            guard row.id == id else { throw PerformanceCommitmentClientError.invalidResponse }
            let lifecycle = try await client.lifecycle(id: id, actorID: actor)
            guard await current(actor, accountToken), readToken == token else { return }
            try lifecycle.validate(agreement: row, actorID: actor)
            upsert(row, lifecycle)
        } catch {
            guard await current(actor, accountToken), readToken == token else { return }
            clearVisibleContent()
            lifecycleErrors[id] = "We couldn’t load your goal and result updates. Refresh this goal to try again."
            errorMessage = mapped(error).localizedDescription
        }
    }

    func submit(_ operation: PerformanceCommitmentMutation) async {
        guard canStartRequest, let actor = actorID else { return }
        switch operation {
        case let .create(draft, digest, consent):
            guard consent, previewedDraft == draft, previewedTerms?.termsDigest == digest,
                  previewedTerms.map({ draft.matches($0.terms) }) == true else { return }
        case let .close(id, reason): guard canClose(id, reason: reason) else { return }
        case let .fileReview(id, revision, _): guard canFileReview(id, revision: revision) else { return }
        }
        let accountToken = generation
        let visibilityToken = readToken
        isSending = true
        errorMessage = nil
        lastConfirmedID = nil
        lastConfirmedOperation = nil
        defer { if generation == accountToken { isSending = false } }
        do {
            guard await current(actor, accountToken), readToken == visibilityToken else { return }
            let request = try PendingPerformanceCommitmentRequest(actorID: actor, operation: operation)
            try await pendingStore.save(request)
            guard await current(actor, accountToken), readToken == visibilityToken else { return }
            pending = request
            await send(request, accountToken: accountToken, visibilityToken: visibilityToken)
        } catch {
            guard await current(actor, accountToken), readToken == visibilityToken else { return }
            storageBlocked = true
            errorMessage = PerformanceCommitmentClientError.storage.localizedDescription
        }
    }

    /// Refresh, account restoration and foregrounding never call this method.
    func retry() async {
        guard let pending, !isSending, !isLoading, !isPreviewing, !storageBlocked else { return }
        let accountToken = generation
        let visibilityToken = readToken
        isSending = true
        errorMessage = nil
        defer { if generation == accountToken { isSending = false } }
        await send(pending, accountToken: accountToken, visibilityToken: visibilityToken)
    }

    private func send(_ saved: PendingPerformanceCommitmentRequest, accountToken: UUID, visibilityToken initialVisibilityToken: UUID) async {
        let actor = saved.actorID
        guard await current(actor, accountToken), readToken == initialVisibilityToken else { return }
        var visibilityToken = initialVisibilityToken
        var request = saved
        request.mayHaveCommitted = true
        var receivedCommit = false
        var sent = false
        do {
            // This second durable save closes the termination-before-response
            // gap. Failure here must prevent the HTTP request altogether.
            try await pendingStore.save(request)
            guard await current(actor, accountToken), readToken == visibilityToken else { return }
            pending = request
            clearVisibleContent()
            visibilityToken = readToken
            sent = true
            let receipt = try await client.submit(request)
            receivedCommit = true
            guard await current(actor, accountToken), readToken == visibilityToken else { return }
            let id: UUID
            switch (request.operation, receipt) {
            case (.create, .commitment(let value)): id = value
            case (.close(let value, _), .commitment(let returned)) where value == returned: id = value
            case (.fileReview(let value, _, _), .review): id = value
            default: throw PerformanceCommitmentClientError.invalidResponse
            }
            let row = try await client.detail(id: id, actorID: actor)
            guard await current(actor, accountToken), readToken == visibilityToken else { return }
            try row.validate(for: actor)
            guard row.id == id else { throw PerformanceCommitmentClientError.invalidResponse }
            let lifecycle = try await client.lifecycle(id: id, actorID: actor)
            guard await current(actor, accountToken), readToken == visibilityToken else { return }
            try lifecycle.validate(agreement: row, actorID: actor)
            switch (request.operation, receipt) {
            case let (.create(draft, digest, _), .commitment):
                guard draft.matches(row.terms), row.termsDigest == digest else { throw PerformanceCommitmentClientError.invalidResponse }
            case let (.close(_, reason), .commitment):
                guard row.closeReason == reason, lifecycle.closure?.reason == reason else { throw PerformanceCommitmentClientError.invalidResponse }
            case let (.fileReview(_, revision, reason), .review(review)):
                guard lifecycle.reviews.contains(where: {
                    $0.caseID == review.caseID && $0.proofRevision == revision && $0.reason == reason
                        && $0.filedAt == review.recordedAt
                }) else { throw PerformanceCommitmentClientError.invalidResponse }
            default: throw PerformanceCommitmentClientError.invalidResponse
            }
            try await pendingStore.remove(for: actor, matching: request.requestID)
            guard await current(actor, accountToken), readToken == visibilityToken else { return }
            pending = nil
            upsert(row, lifecycle)
            lastConfirmedID = id
            lastConfirmedOperation = request.operation
        } catch {
            // A reply received after backgrounding cannot publish content or
            // erase the saved request, including a definitive rejection.
            guard await current(actor, accountToken), readToken == visibilityToken else { return }
            clearVisibleContent()
            let failure = mapped(error)
            if !sent { storageBlocked = true }
            if sent && failure.isDefinitiveRejection && !saved.mayHaveCommitted && !receivedCommit {
                do {
                    try await pendingStore.remove(for: actor, matching: saved.requestID)
                    guard await current(actor, accountToken) else { return }
                    pending = nil
                } catch { storageBlocked = true }
            }
            errorMessage = (!sent ? PerformanceCommitmentClientError.storage : failure).localizedDescription
        }
    }

    func estimatedNow(for id: UUID, at now: Date = Date()) -> PerformanceCommitmentInstant? {
        guard let lifecycle = lifecycles[id], let received = lifecycleReceivedAt[id] else { return nil }
        let elapsed = max(0, now.timeIntervalSince(received))
        // Keep the incoming server microseconds as integers. Converting that
        // timestamp through Date can round a deadline backward. Round elapsed
        // fractions forward so this UI hint cannot extend a filing window.
        let elapsedMicros = (elapsed * 1_000_000).rounded(.up)
        guard elapsedMicros.isFinite, elapsedMicros < Double(Int64.max) else { return nil }
        let (micros, overflow) = lifecycle.serverNow.microseconds.addingReportingOverflow(Int64(elapsedMicros))
        guard !overflow, micros >= 0 else { return nil }
        let whole = Date(timeIntervalSince1970: Double(micros / 1_000_000)).formatted(.iso8601)
        let wire = whole.replacingOccurrences(of: "Z", with: String(format: ".%06lldZ", micros % 1_000_000))
        return try? PerformanceCommitmentInstant(wire)
    }
    func canFileReview(_ id: UUID, revision: Int, at now: Date = Date()) -> Bool {
        guard canStartRequest, freshIDs.contains(id), let lifecycle = lifecycles[id], lifecycle.finalResult == nil,
              lifecycle.closure == nil, let notice = lifecycle.notices.first(where: { $0.proofRevision == revision }),
              notice.canFileReview, let clock = estimatedNow(for: id, at: now),
              let row = agreements.first(where: { $0.id == id }), row.status == .open else { return false }
        return clock < notice.disputeClosesAt && clock < row.terms.finalityDueAt
    }
    func canClose(_ id: UUID, reason: PerformanceCommitmentCloseReason, at now: Date = Date()) -> Bool {
        guard canStartRequest, freshIDs.contains(id), let lifecycle = lifecycles[id], lifecycle.finalResult == nil,
              lifecycle.closure == nil, let row = agreements.first(where: { $0.id == id }), row.status == .open,
              let clock = estimatedNow(for: id, at: now) else { return false }
        switch reason {
        case .cancel: return clock < row.startsAt
        case .withdrawal: return clock >= row.startsAt
        case .injury: return true
        case .accountDeleted: return false
        }
    }
    private func current(_ actor: UUID, _ token: UUID) async -> Bool {
        let live = await auth.currentUserID()
        guard generation == token, actorID == actor else { return false }
        guard live == actor else {
            setActor(nil)
            return false
        }
        return true
    }
    private func clearOwnerContent() {
        agreements = []
        lifecycles = [:]
        lifecycleReceivedAt = [:]
        lifecycleErrors = [:]
        freshIDs = []
        hasMore = false
    }
    private func upsert(_ row: PerformanceCommitmentAgreement, _ lifecycle: PerformanceCommitmentLifecycle) {
        if let index = agreements.firstIndex(where: { $0.id == row.id }) { agreements[index] = row }
        else { agreements.insert(row, at: 0) }
        lifecycles[row.id] = lifecycle
        lifecycleReceivedAt[row.id] = Date()
        freshIDs.insert(row.id)
        lifecycleErrors[row.id] = nil
    }
    private func mapped(_ error: Error) -> PerformanceCommitmentClientError {
        if let failure = error as? PerformanceCommitmentClientError { return failure }
        if error is PerformanceCommitmentModelError { return .invalidResponse }
        return .unavailable
    }
}
