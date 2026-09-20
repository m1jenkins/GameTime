import Foundation
import GameTimeCore
import Observation

@MainActor
protocol ChallengeHealthPermissionService: AnyObject {
    var supported: Bool { get }
    func connect(_ metric: ChallengeHealthMetric) async throws
    func updates(for sources: Set<String>, active: Bool, perform: @escaping @MainActor @Sendable () -> Void)
}

extension ChallengeHealthPermissionService {
    func updates(for sources: Set<String>, active: Bool, perform: @escaping @MainActor @Sendable () -> Void) {}
}

@MainActor
struct ChallengeHealthFlowDependencies {
    let coordinator: ChallengeHealthTransportCoordinator
    let uploads: ChallengeHealthUploadClient
    let readiness: ChallengeHealthReadinessClient
    let cache: ChallengeHealthComparisonCache
    let permission: any ChallengeHealthPermissionService
    let reader: @MainActor (ChallengeHealthBinding, ChallengeHealthReadRequest.Purpose) -> any ChallengeHealthStore
    let adapter: @MainActor (ChallengeHealthBinding) -> any ChallengeHealthAdapter
    var now: @MainActor () -> Date = Date.init
    var updateClock: @MainActor () async throws -> Void = {}
    var actorSession: (@MainActor () -> WeeklyClientSession?)? = nil
}

/// Health ownership is separate from server challenge state. Contexts are never
/// shared between actors, bindings, read purposes or simultaneous challenges.
@MainActor @Observable
final class ChallengeHealthFlowStore {
    struct State: Equatable {
        var readiness: ChallengeHealthReadiness = .notConnected
        var localValue: Int64?
        var observedAt: Date?
        var pendingDelivery = false
        var lastServerUpdate: Date?
        var message: String?
    }
    private struct Acknowledged { let binding: ChallengeHealthBinding; let at: Date }
    private final class Context {
        let reader: any ChallengeHealthStore
        var previous: ChallengeHealthSnapshot?
        var task: Task<ChallengeHealthStoreOutcome, Never>?
        var generation = UUID()
        init(reader: any ChallengeHealthStore, previous: ChallengeHealthSnapshot?) { self.reader = reader; self.previous = previous }
    }
    private let dependencies: ChallengeHealthFlowDependencies
    private let challenges: ChallengeV1Store
    private let auth: any AuthClient
    private(set) var actor: UUID?
    private(set) var suspended = false
    private(set) var states: [UUID: State] = [:]
    private(set) var suggestions: [UUID: Int] = [:]
    private var connected: Set<String> = []
    private var operationVersions: [UUID: UUID] = [:]
    private var stateBindings: [UUID: ChallengeHealthBinding] = [:]
    private var acknowledged: [UUID: Acknowledged] = [:]
    private var contexts: [String: Context] = [:]
    private var contextIDs: [String: UUID] = [:]
    private var generation = UUID()
    private var actorSession: WeeklyClientSession?
    private var pending: Set<UUID> = []
    private var refreshTask: Task<Void, Never>?

    init(auth: any AuthClient, challenges: ChallengeV1Store, dependencies: ChallengeHealthFlowDependencies) {
        self.auth = auth; self.challenges = challenges; self.dependencies = dependencies
    }
    func setActor(_ actor: UUID?) {
        cancelAll(); self.actor = actor; suspended = false
        actorSession = dependencies.actorSession?()
        states = [:]; suggestions = [:]; acknowledged = [:]; connected = []; pending = []; operationVersions = [:]; stateBindings = [:]
        dependencies.permission.updates(for: [], active: false, perform: {})
        guard let actor else { return }
        do { connected = try dependencies.cache.connected(actor: actor); pending = try dependencies.cache.pending(actor: actor) }
        catch { /* A fresh retry after unlock must restore state before reading. */ }
        updateOpportunities()
    }
    func restrict(_ restricted: Bool) {
        guard suspended != restricted else { return }
        suspended = restricted
        if restricted { cancelAll(); states = [:]; suggestions = [:]; acknowledged = [:] }
        updateOpportunities()
    }
    func cancel(_ id: UUID) {
        operationVersions[id] = UUID()
        for key in contextIDs.keys where contextIDs[key] == id {
            contexts[key]?.generation = UUID(); contexts[key]?.task?.cancel()
        }
        acknowledged[id] = nil
    }
    func cancelAll() {
        generation = UUID(); refreshTask?.cancel(); refreshTask = nil
        for context in contexts.values { context.generation = UUID(); context.task?.cancel() }
        contexts = [:]; contextIDs = [:]
    }
    func state(for binding: ChallengeHealthBinding) -> State {
        if stateBindings[binding.challengeID] == binding, let state = states[binding.challengeID] { return state }
        if !dependencies.permission.supported || binding.realSourcePolicy == .appleWatchExerciseV1 { return State(readiness: .unsupported) }
        return State(readiness: connected.contains(binding.realSourcePolicy?.identifier ?? "") ? .noEligibleDataYet : .notConnected)
    }
    func canConsent(_ binding: ChallengeHealthBinding) -> Bool {
        guard !suspended, actor == binding.actorID, let receipt = acknowledged[binding.challengeID], receipt.binding == binding else { return false }
        let age = dependencies.now().timeIntervalSince(receipt.at)
        return age >= 0 && age <= 300 && states[binding.challengeID]?.readiness == .ready && states[binding.challengeID]?.pendingDelivery == false
    }
    func invalidateDraft(_ id: UUID) { cancel(id); states[id] = nil; suggestions[id] = nil }

    func authenticationRecovered(actor: UUID) async {
        guard self.actor == actor, let session = dependencies.actorSession,
              session() != actorSession else { return }
        dependencies.coordinator.invalidate()
        setActor(actor)
        await refresh()
    }

    /// Uses the injected source clock for local planning as well as reads. It
    /// requests no Health access and cannot create a readiness or activity fact.
    func planningDate() async -> Date? {
        guard let actor, !suspended else { return nil }
        let epoch = generation
        do {
            try await check(actor, epoch)
            try await dependencies.updateClock()
            try await check(actor, epoch)
            return dependencies.now()
        } catch { return nil }
    }

    func checkReadiness(_ binding: ChallengeHealthBinding, connect: Bool = false) async {
        let epoch = generation, id = binding.challengeID, operation = begin(binding)
        acknowledged[id] = nil
        do {
            try await check(binding.actorID, epoch)
            try validate(id, operation, epoch)
            try await dependencies.updateClock()
            try validate(id, operation, epoch)
            try await requireActive(binding.actorID, epoch)
            try validate(id, operation, epoch)
            guard dependencies.permission.supported, binding.realSourcePolicy != .appleWatchExerciseV1 else {
                states[id] = State(readiness: .unsupported); return
            }
            try restoreConnection(binding.actorID)
            if connect {
                try await dependencies.permission.connect(binding.metric)
                try await check(binding.actorID, epoch)
                try validate(id, operation, epoch)
                guard let policy = binding.realSourcePolicy else { throw ChallengeV1Error.unavailable }
                try dependencies.cache.connect(actor: binding.actorID, source: policy.identifier)
                connected.insert(policy.identifier)
                updateOpportunities()
            }
            guard connected.contains(binding.realSourcePolicy?.identifier ?? "") else { states[id] = State(readiness: .notConnected); return }
            states[id] = State(readiness: .checking)
            // Recover ALL writers before producing the next signed readiness request.
            try await dependencies.readiness.retry(actor: binding.actorID)
            try await check(binding.actorID, epoch)
            try validate(id, operation, epoch)
            let request = try historyRequest(binding, purpose: .readinessHistory)
            let (snapshot, evaluation) = try await read(request, epoch: epoch)
            try validate(id, operation, epoch)
            states[id] = State(readiness: evaluation.readiness, localValue: evaluation.activity?.integerValue, observedAt: snapshot.observedAt)
            guard evaluation.permitsRealConsent else { return }
            let wire = try ChallengeHealthReadinessRequest(binding: binding, snapshot: snapshot, evaluation: evaluation, requestID: UUID())
            states[id]?.pendingDelivery = true
            try await dependencies.readiness.submit(wire, validate: { [weak self] in
                guard let self else { throw CancellationError() }; try self.validate(id, operation, epoch)
            })
            try await check(binding.actorID, epoch)
            try validate(id, operation, epoch)
            states[id]?.pendingDelivery = false
            acknowledged[id] = Acknowledged(binding: binding, at: dependencies.now())
        } catch is CancellationError { return }
        catch {
            guard actor == binding.actorID, epoch == generation, operationVersions[id] == operation, !suspended else { return }
            states[id, default: State()].readiness = .temporarilyUnavailable
            states[id]?.message = "We couldn’t finish checking your activity. Unlock your phone and try Refresh."
        }
    }

    /// A local-only read purpose can never construct an activity or readiness request.
    func suggest(_ binding: ChallengeHealthBinding, policy: ChallengeV1Policy, days: Int) async {
        suggestions[binding.challengeID] = nil
        guard policy.hasTarget, policy.mode != .community else { return }
        let epoch = generation, operation = begin(binding)
        do {
            try await check(binding.actorID, epoch)
            try await requireActive(binding.actorID, epoch)
            try restoreConnection(binding.actorID)
            guard dependencies.permission.supported, let source = binding.realSourcePolicy, source != .appleWatchExerciseV1 else { return }
            if !connected.contains(source.identifier) {
                try await dependencies.permission.connect(binding.metric)
                try await check(binding.actorID, epoch); try validate(binding.challengeID, operation, epoch)
                try dependencies.cache.connect(actor: binding.actorID, source: source.identifier)
                connected.insert(source.identifier); updateOpportunities()
            }
            let (_, evaluation) = try await read(historyRequest(binding, purpose: .suggestionHistory), epoch: epoch)
            try validate(binding.challengeID, operation, epoch)
            guard evaluation.readiness == .ready, evaluation.acceptsRealSourceObservation,
                  let value = evaluation.activity?.integerValue, let total = Int(exactly: value) else { return }
            suggestions[binding.challengeID] = ChallengeV1Suggestion.value(policy: policy, days: days,
                eligible28DayTotal: policy.metric == .timed ? nil : total, best90DayElapsedSeconds: policy.metric == .timed ? total : nil)
        } catch { /* No usable history means no suggestion. */ }
    }

    /// Coalesces foreground, manual, observer, connectivity and unlock work.
    /// Observer callers schedule this and complete their callback immediately.
    func refresh(_ id: UUID? = nil) async {
        guard let actor, !suspended else { return }
        let ids = id.map { Set([$0]) } ?? Set(challenges.challenges.filter { $0.sourcePolicyVersion != nil && !$0.isClosed }.map(\.id))
        pending.formUnion(ids)
        var cacheAvailable = true
        do {
            try restoreConnection(actor)
            pending.formUnion(try dependencies.cache.pending(actor: actor))
            try dependencies.cache.enqueue(actor: actor, ids: pending)
        } catch {
            cacheAvailable = false
            for id in pending {
                states[id] = State(readiness: .temporarilyUnavailable, pendingDelivery: true,
                    message: "We couldn’t read your saved activity. Unlock your phone and try Refresh.")
            }
        }
        if let refreshTask { await refreshTask.value; return }
        let epoch = generation
        let canReadCache = cacheAvailable
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            // A saved request can outlive the list, local work cache, or new
            // ingestion gate. Every authenticated opportunity drains the actor's
            // endpoint journals under the shared lease before any new reads.
            do {
                try await self.check(actor, epoch)
                try await self.dependencies.uploads.retry(actor: actor)
                try await self.check(actor, epoch)
            } catch is CancellationError { return }
            catch {
                for id in self.pending {
                    self.states[id] = State(readiness: .temporarilyUnavailable, pendingDelivery: true,
                        message: "We couldn’t send your saved activity. Try Refresh when you’re connected.")
                }
                return
            }
            // One additional bounded pass includes work arriving during the
            // first pass without keeping an observer opportunity alive forever.
            for _ in 0..<2 {
                let batch = self.pending; self.pending.subtract(batch)
                for id in batch.sorted(by: { $0.uuidString < $1.uuidString }) {
                    guard !Task.isCancelled, self.generation == epoch else { break }
                    await self.refreshOne(id, actor: actor, epoch: epoch, cacheAvailable: canReadCache)
                }
                if self.pending.isEmpty { break }
            }
        }
        refreshTask = task
        await task.value
        guard generation == epoch else { return }
        refreshTask = nil
        // Work coalesced during this bounded pass is left persisted for the next
        // opportunity, avoiding unbounded background loops on failing networks.
    }

    private func refreshOne(_ id: UUID, actor: UUID, epoch: UUID, cacheAvailable: Bool) async {
        let operation = UUID(); operationVersions[id] = operation
        do {
            try await check(actor, epoch)
            try validate(id, operation, epoch)
            try await dependencies.updateClock()
            try await requireActive(actor, epoch)
            try await dependencies.uploads.retry(actor: actor)
            try await check(actor, epoch)
            try validate(id, operation, epoch)
            let row = try await challenges.client.detail(id, actor: actor)
            try await check(actor, epoch)
            try validate(id, operation, epoch)
            states[id, default: State()].lastServerUpdate = row.own(actor)?.fact?.recordedAt.date
            guard !row.isClosed, row.format.competition != .leaderboard, row.serverTime <= row.config.correctionsBy else {
                if cacheAvailable {
                    try dependencies.cache.acknowledge(actor: actor, id: id); try dependencies.cache.retire(actor: actor, id: id)
                }
                await challenges.loadDetail(id); return
            }
            let context = try ChallengeHealthBindingMapper.activity(row, actor: actor)
            let binding = context.binding
            stateBindings[id] = binding
            guard row.serverTime >= row.config.startsAt else { await challenges.loadDetail(id); return }
            guard !cacheAvailable || connected.contains(binding.realSourcePolicy?.identifier ?? "") else {
                states[id] = State(readiness: .notConnected); return
            }
            let readRequest = try ChallengeHealthReadRequest(binding: binding, deviceRequestID: UUID(), queryWindow: binding.challengeWindow, purpose: .challengeActivity)
            states[id, default: State()].readiness = .checking
            var replacement: ChallengeHealthReplacement = .unresolved(.temporarilyUnavailable)
            var observedAt = dependencies.now()
            do {
                guard cacheAvailable else { throw ChallengeHealthComparisonCache.Failure.unavailable }
                let (snapshot, evaluation) = try await read(readRequest, epoch: epoch)
                observedAt = snapshot.observedAt
                replacement = evaluation.realReplacementDecision.normalizedReplacement
                states[id] = State(readiness: evaluation.readiness, localValue: evaluation.activity?.integerValue,
                    observedAt: snapshot.observedAt, lastServerUpdate: row.own(actor)?.fact?.recordedAt.date)
            } catch is CancellationError { return }
            catch { states[id] = State(readiness: .temporarilyUnavailable, observedAt: observedAt) }
            try await check(actor, epoch)
            try validate(id, operation, epoch)
            // Refresh authoritative terms again after the native query. A reopen,
            // removal or suspension cannot be raced by a delayed Health callback.
            try await requireActive(actor, epoch)
            let latest = try await challenges.client.detail(id, actor: actor)
            try await check(actor, epoch)
            try validate(id, operation, epoch)
            guard try ChallengeHealthBindingMapper.activity(latest, actor: actor).binding == binding,
                  latest.serverTime <= latest.config.correctionsBy else { return }
            let previous = latest.own(actor)?.fact?.revision
            guard previous != nil || latest.serverTime <= latest.config.syncBy else { return }
            let through = min(binding.challengeWindow.endMicroseconds, Self.microseconds(observedAt))
            guard through >= binding.challengeWindow.startMicroseconds else { return }
            let request = try ChallengeHealthUploadRequest(binding: binding, requestID: UUID(), revision: (previous ?? 0) + 1,
                previousRevision: previous, replacement: replacement, observedAtMicroseconds: Self.microseconds(observedAt), queriedThroughMicroseconds: through)
            states[id]?.pendingDelivery = true
            try await dependencies.uploads.submit(request, confirmedServerRevision: previous, validate: { [weak self] in
                guard let self else { throw CancellationError() }; try self.validate(id, operation, epoch)
            })
            try await check(actor, epoch)
            try validate(id, operation, epoch)
            states[id]?.pendingDelivery = false
            if cacheAvailable { try dependencies.cache.acknowledge(actor: actor, id: id) }
            await challenges.loadDetail(id)
            try await check(actor, epoch)
            try validate(id, operation, epoch)
            states[id]?.lastServerUpdate = challenges.challenges.first { $0.id == id }?.own(actor)?.fact?.recordedAt.date
        } catch is CancellationError { return }
        catch {
            guard self.actor == actor, generation == epoch, operationVersions[id] == operation, !suspended else { return }
            states[id, default: State()].localValue = nil
            states[id]?.readiness = .temporarilyUnavailable
            states[id]?.message = "We couldn’t finish this update. Refresh to try again."
        }
    }

    private func begin(_ binding: ChallengeHealthBinding) -> UUID {
        let id = binding.challengeID
        if let previous = stateBindings[id], previous != binding {
            cancel(id); states[id] = nil; suggestions[id] = nil
        }
        stateBindings[id] = binding
        let operation = UUID(); operationVersions[id] = operation
        return operation
    }
    private func validate(_ id: UUID, _ operation: UUID, _ epoch: UUID) throws {
        try Task.checkCancellation()
        guard generation == epoch, operationVersions[id] == operation, !suspended else { throw CancellationError() }
    }
    private func read(_ request: ChallengeHealthReadRequest, epoch: UUID) async throws -> (ChallengeHealthSnapshot, ChallengeHealthEvaluation) {
        let key = try dependencies.cache.key(request)
        let context: Context
        if let existing = contexts[key] { context = existing }
        else {
            if contexts.count >= 32 {
                let idle = contexts.keys.filter { contexts[$0]?.task == nil }
                for key in idle { contexts[key] = nil; contextIDs[key] = nil }
            }
            guard contexts.count < 32 else { throw ChallengeHealthComparisonCache.Failure.capacity }
            context = Context(reader: dependencies.reader(request.binding, request.purpose),
                previous: request.purpose == .challengeActivity ? try dependencies.cache.load(request) : nil)
            contexts[key] = context; contextIDs[key] = request.binding.challengeID
        }
        context.task?.cancel(); context.generation = UUID(); let readGeneration = context.generation
        let task = Task { await context.reader.read(request) }; context.task = task
        let outcome = await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
        defer { if context.generation == readGeneration { context.task = nil } }
        try await check(request.binding.actorID, epoch)
        guard context.generation == readGeneration else { throw CancellationError() }
        guard case .snapshot(let snapshot) = outcome else {
            if outcome == .unavailable(.cancelled) { throw CancellationError() }
            throw ChallengeV1Error.unavailable
        }
        guard snapshot.request == request else { throw ChallengeV1Error.invalidResponse }
        let evaluation = dependencies.adapter(request.binding).evaluate(snapshot, replacing: context.previous)
        if evaluation.issues.isDisjoint(with: [.invalidSnapshot, .metricMismatch, .lostVisibility, .incompleteEvidence]) {
            if request.purpose == .challengeActivity { try dependencies.cache.save(snapshot) }
            context.previous = snapshot
        }
        return (snapshot, evaluation)
    }
    private func historyRequest(_ binding: ChallengeHealthBinding, purpose: ChallengeHealthReadRequest.Purpose) throws -> ChallengeHealthReadRequest {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: binding.challengeWindow.timeZoneIdentifier)!
        let end = min(dependencies.now(), binding.challengeWindow.interval.start)
        let days = binding.metric == .timedRunElapsedSeconds ? 90 : purpose == .suggestionHistory ? 28 : 30
        guard let start = calendar.date(byAdding: .day, value: -days, to: end) else { throw ChallengeV1Error.invalidResponse }
        return try ChallengeHealthReadRequest(binding: binding, deviceRequestID: UUID(), queryWindow: ChallengeHealthWindow(
            startMicroseconds: Self.microseconds(start), endMicroseconds: Self.microseconds(end),
            timeZoneIdentifier: binding.challengeWindow.timeZoneIdentifier, calendar: .gregorian), purpose: purpose)
    }
    private func updateOpportunities() {
        let active = !suspended && actor != nil
        dependencies.permission.updates(for: active ? connected : [], active: active) { [weak self] in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
    }
    private func restoreConnection(_ actor: UUID) throws {
        let saved = try dependencies.cache.connected(actor: actor)
        if connected != saved { connected = saved; updateOpportunities() }
    }
    private func requireActive(_ actor: UUID, _ epoch: UUID) async throws {
        let access = try await challenges.client.read("challenge_access_status_v1", fields: [:], actor: actor, as: ChallengeV1Access.self)
        try await check(actor, epoch)
        if access.suspended { restrict(true); throw ChallengeV1Error.unavailable }
    }
    private func check(_ actor: UUID, _ epoch: UUID) async throws {
        try Task.checkCancellation()
        let current = await auth.currentUserID()
        guard self.actor == actor, current == actor, generation == epoch, !suspended else { throw CancellationError() }
        if let session = dependencies.actorSession {
            guard let actorSession, actorSession.actorID == actor, session() == actorSession else {
                cancelAll(); states = [:]; suggestions = [:]; acknowledged = [:]; self.actorSession = nil
                throw CancellationError()
            }
        }
    }
    static func microseconds(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1_000_000).rounded(.down)) }
}
