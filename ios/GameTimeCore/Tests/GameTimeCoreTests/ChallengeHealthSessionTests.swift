import Foundation
import Testing
@testable import GameTimeCore

@Suite("Challenge Health async session fences")
struct ChallengeHealthSessionTests {
    typealias F = ChallengeHealthFixtures

    @Test("all seven states; permission completion alone is never ready")
    func readinessLifecycle() async throws {
        #expect(Set(ChallengeHealthReadiness.allCases.map(\.rawValue)) == [
            "unsupported", "notConnected", "checking", "ready", "noEligibleDataYet",
            "temporarilyUnavailable", "staleOrIncomplete"
        ])
        let session = ChallengeHealthReadSession(), store = FakeChallengeHealthStore()
        let request = try F.request()
        let adapter = ChallengeHealthStepsAdapter(fixture: F.policy([10: .contribution(100)]))
        #expect(await session.readiness == .notConnected)
        try await session.configure(request: request, supported: false, sourceRequestCompleted: true)
        #expect(try await session.refresh(store: store, adapter: adapter) == .notStarted(.unsupported))
        try await session.configure(request: request, supported: true, sourceRequestCompleted: false)
        #expect(try await session.refresh(store: store, adapter: adapter) == .notStarted(.notConnected))
        try await session.configure(request: request, supported: true, sourceRequestCompleted: true)
        #expect(await session.readiness == .noEligibleDataYet)
        let task = Task { try await session.refresh(store: store, adapter: adapter) }
        #expect(await store.request(at: 0) == request)
        #expect(await session.readiness == .checking)
        await store.resolve(0, with: .snapshot(try F.snapshot([F.record()], request: request)))
        guard case .applied(let result) = try await task.value else { Issue.record("Expected applied fixture"); return }
        #expect(result.readiness == .ready && result.syntheticOnly && !result.permitsRealConsent)
        #expect(await session.readiness == .ready)
    }

    @Test("lock, offline, query failure and cancellation never become empty or zero")
    func transportFailures() async throws {
        let session = ChallengeHealthReadSession(), store = FakeChallengeHealthStore()
        try await session.configure(request: F.request(), supported: true, sourceRequestCompleted: true)
        for (index, failure) in [ChallengeHealthStoreFailure.protectedDataUnavailable, .offline, .queryFailed, .cancelled].enumerated() {
            let task = Task { try await session.refresh(store: store, adapter: ChallengeHealthStepsAdapter()) }
            _ = await store.request(at: index)
            await store.resolve(index, with: .unavailable(failure))
            #expect(try await task.value == .unavailable(failure))
            #expect(await session.readiness == .temporarilyUnavailable)
        }
    }

    @Test("permission loss after positive history remains stale across repeated empty reads")
    func lostPermissionOrVisibility() async throws {
        let session = ChallengeHealthReadSession(), store = FakeChallengeHealthStore()
        let request = try F.request()
        try await session.configure(request: request, supported: true, sourceRequestCompleted: true)
        let adapter = ChallengeHealthStepsAdapter(fixture: F.policy([10: .contribution(100)], freshThrough: 1_200))
        for index in 0..<3 {
            let task = Task { try await session.refresh(store: store, adapter: adapter) }
            _ = await store.request(at: index)
            await store.resolve(index, with: .snapshot(try F.snapshot(index == 0 ? [F.record()] : [],
                request: request, observed: 1_000 + Double(index), freshness: 900)))
            guard case .applied(let result) = try await task.value else { Issue.record("Expected snapshot"); return }
            #expect(result.readiness == (index == 0 ? .ready : .staleOrIncomplete))
            if index > 0 { #expect(result.activity == nil && result.issues.contains(.lostVisibility)) }
        }
    }

    @Test("account, agreement terms and switch-away/back invalidate in-flight results")
    func accountAndTermsFences() async throws {
        let a = try F.request()
        for replacement in [try F.request(actor: 9), try F.request(version: 2), a] {
            let session = ChallengeHealthReadSession(), store = FakeChallengeHealthStore()
            try await session.configure(request: a, supported: true, sourceRequestCompleted: true)
            let task = Task { try await session.refresh(store: store, adapter: ChallengeHealthStepsAdapter()) }
            _ = await store.request(at: 0)
            try await session.configure(request: nil, supported: true, sourceRequestCompleted: false)
            try await session.configure(request: replacement, supported: true, sourceRequestCompleted: true)
            await store.resolve(0, with: .snapshot(try F.snapshot([F.record()], request: a)))
            #expect(try await task.value == .discarded)
            #expect(await session.readiness == .noEligibleDataYet)
        }
    }

    @Test("latest read wins even if an earlier read returns after it with a larger value")
    func outOfOrderCompletions() async throws {
        let session = ChallengeHealthReadSession(), store = FakeChallengeHealthStore()
        let request = try F.request()
        try await session.configure(request: request, supported: true, sourceRequestCompleted: true)
        let first = Task { try await session.refresh(store: store,
            adapter: ChallengeHealthStepsAdapter(fixture: F.policy([10: .contribution(999)]))) }
        _ = await store.request(at: 0)
        let second = Task { try await session.refresh(store: store,
            adapter: ChallengeHealthStepsAdapter(fixture: F.policy([10: .contribution(50)]))) }
        _ = await store.request(at: 1)
        await store.resolve(1, with: .snapshot(try F.snapshot([F.record(value: 50)], request: request)))
        guard case .applied(let result) = try await second.value else { Issue.record("Latest read missing"); return }
        #expect(result.activity?.integerValue == 50)
        await store.resolve(0, with: .snapshot(try F.snapshot([F.record(value: 999)], request: request)))
        #expect(try await first.value == .discarded)
        #expect(await session.readiness == .ready)
    }

    @Test("a transport returning another request or cancelled task cannot apply data")
    func wrongResponseAndCancellation() async throws {
        let session = ChallengeHealthReadSession(), store = FakeChallengeHealthStore()
        try await session.configure(request: F.request(), supported: true, sourceRequestCompleted: true)
        let wrong = Task { try await session.refresh(store: store, adapter: ChallengeHealthStepsAdapter()) }
        _ = await store.request(at: 0)
        await store.resolve(0, with: .snapshot(try F.snapshot([F.record()], request: F.request(requestID: 4))))
        #expect(try await wrong.value == .discarded)
        #expect(await session.readiness == .staleOrIncomplete)
        let cancelled = Task { try await session.refresh(store: store, adapter: ChallengeHealthStepsAdapter()) }
        _ = await store.request(at: 1)
        cancelled.cancel()
        await store.resolve(1, with: .snapshot(try F.snapshot([F.record()])))
        #expect(try await cancelled.value == .discarded)
        #expect(await session.readiness == .temporarilyUnavailable)
    }
}
