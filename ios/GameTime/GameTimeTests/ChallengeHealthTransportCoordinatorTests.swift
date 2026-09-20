import Foundation
import GameTimeCore
import Testing
@testable import GameTime

@MainActor private var p9TestCounter: UInt32 = 0
@MainActor func nextP9TestAssertion() -> Data {
    p9TestCounter += 1
    return p9TestAssertion(counter: p9TestCounter)
}
func p9TestAssertion(counter: UInt32) -> Data {
    let key = Array("authenticatorData".utf8)
    var data = Data([0xa1, 0x71] + key + [0x58, 37] + Array(repeating: UInt8(0), count: 33))
    data.append(contentsOf: [UInt8((counter >> 24) & 255), UInt8((counter >> 16) & 255),
                             UInt8((counter >> 8) & 255), UInt8(counter & 255)])
    return data
}

@Suite("Every signed writer shares counter-ordered recovery") @MainActor
struct ChallengeHealthTransportCoordinatorTests {
    func coordinator(directory: URL, binding: (@MainActor () -> WeeklyClientSession?)? = nil) -> ChallengeHealthTransportCoordinator {
        ChallengeHealthTransportCoordinator(uploadStore: .init(directory: directory.appendingPathComponent("uploads")),
            readinessStore: .init(directory: directory.appendingPathComponent("readiness")), binding: binding)
    }

    @Test func shuffledWritersRecoverBeforeNewSignature() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let coordinator = coordinator(directory: folder), actor = UUID()
        var delivered: [UInt32] = []
        let counters: [ChallengeHealthTransportCoordinator.Kind: [UInt32]] = [
            .upload: [21, 3], .readiness: [7], .metrics: [14, 2], .coverage: [10], .diagnostic: [5]]
        for kind in ChallengeHealthTransportCoordinator.Kind.allCases {
            coordinator.register(kind) { _ in
                (counters[kind] ?? []).map { counter in
                    .init(kind: kind, id: UUID(), keyID: "shared-key", assertion: p9TestAssertion(counter: counter), body: Data([UInt8(counter)])) {
                        delivered.append(counter)
                    }
                }
            }
        }
        try await coordinator.begin(actor: actor)
        defer { coordinator.release(actor: actor) }
        try await coordinator.recover(actor: actor)
        #expect(delivered == [2, 3, 5, 7, 10, 14, 21])
        #expect(throws: ChallengeHealthTransportCoordinator.Failure.counterConflict) {
            try coordinator.validateNewSignature(keyID: "shared-key", assertion: p9TestAssertion(counter: 21))
        }
        try coordinator.validateNewSignature(keyID: "shared-key", assertion: p9TestAssertion(counter: 25))
    }

    @Test func malformedOrConflictingCountersDeliverNothing() async throws {
        for malformed in [true, false] {
            let coordinator = coordinator(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            var calls = 0
            coordinator.register(.metrics) { _ in
                [1, 2].map { i in
                    .init(kind: .metrics, id: UUID(), keyID: "key", assertion: malformed && i == 2 ? Data([1]) : p9TestAssertion(counter: 4), body: Data([UInt8(i)])) { calls += 1 }
                }
            }
            let actor = UUID()
            try await coordinator.begin(actor: actor)
            await #expect(throws: malformed ? ChallengeHealthTransportCoordinator.Failure.malformedAssertion : .counterConflict) {
                try await coordinator.recover(actor: actor)
            }
            coordinator.release(actor: actor)
            #expect(calls == 0)
        }
    }

    @Test func failureStopsLaterCountersAndActorChangeStopsAcknowledgement() async throws {
        let actor = UUID()
        var session: WeeklyClientSession? = .init(actorID: actor, identity: "first")
        let coordinator = coordinator(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), binding: { session })
        var delivered: [Int] = []
        coordinator.register(.diagnostic) { _ in
            [2, 1].map { counter in
                .init(kind: .diagnostic, id: UUID(), keyID: "key", assertion: p9TestAssertion(counter: UInt32(counter)), body: Data()) {
                    delivered.append(counter)
                    throw ChallengeHealthTransportCoordinator.Failure.pendingDelivery
                }
            }
        }
        try await coordinator.begin(actor: actor)
        #expect(coordinator.acquire(actor: UUID()) == false)
        await #expect(throws: ChallengeHealthTransportCoordinator.Failure.pendingDelivery) { try await coordinator.recover(actor: actor) }
        #expect(delivered == [1])
        session = .init(actorID: UUID(), identity: "second")
        #expect(throws: ChallengeHealthTransportCoordinator.Failure.accountChanged) { try coordinator.check(actor: actor) }
        coordinator.release(actor: actor)
        #expect(coordinator.acquire(actor: actor))
        coordinator.invalidate()
        #expect(throws: ChallengeHealthTransportCoordinator.Failure.accountChanged) { try coordinator.check(actor: actor) }
        coordinator.release(actor: actor)
    }
}
