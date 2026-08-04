import Foundation
import XCTest
@testable import GameTimeConformance

@MainActor
final class ConformanceRunnerTests: XCTestCase {
    func testSequentialRunReplaysTheSameMetricAndCheckInRequests() async throws {
        let appAttest = FakeAppAttest()
        let keyStore = InMemoryKeyStore()
        let httpClient = RecordingHTTPClient()
        let runner = ConformanceRunner(
            appAttest: appAttest,
            keyStore: keyStore,
            httpClient: httpClient,
            now: { Date(timeIntervalSince1970: 1_782_921_600) }
        )
        var updates: [ConformanceStepUpdate] = []

        let summary = try await runner.run(
            input: ConformanceInput(
                stagingURL: "https://abcdefghijklmnopqrst.supabase.co",
                apiKey: "publishable-key",
                accessJWT: "header.payload.signature",
                contestID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                geofenceID: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
                latitude: "41.881",
                longitude: "-87.629",
                participantTimeZone: "America/Chicago"
            )
        ) { updates.append($0) }

        XCTAssertEqual(summary.metricCounter, 1)
        XCTAssertEqual(summary.checkInCounter, 2)
        XCTAssertTrue(summary.metricReplayConfirmed)
        XCTAssertTrue(summary.checkInReplayConfirmed)
        XCTAssertEqual(keyStore.loadKeyID(), FakeAppAttest.keyID)
        XCTAssertEqual(appAttest.generatedKeyCount, 1)
        XCTAssertEqual(appAttest.attestationHashes.count, 1)
        XCTAssertEqual(appAttest.assertionHashes.count, 2)
        XCTAssertTrue(appAttest.attestationHashes.allSatisfy { $0.count == 32 })
        XCTAssertTrue(appAttest.assertionHashes.allSatisfy { $0.count == 32 })

        XCTAssertEqual(httpClient.requests.count, 6)
        let firstMetric = httpClient.requests[2]
        let replayedMetric = httpClient.requests[3]
        XCTAssertEqual(firstMetric.httpBody, replayedMetric.httpBody)
        XCTAssertEqual(
            firstMetric.value(forHTTPHeaderField: "x-gametime-assertion"),
            replayedMetric.value(forHTTPHeaderField: "x-gametime-assertion")
        )
        XCTAssertEqual(
            firstMetric.value(forHTTPHeaderField: "x-gametime-key-id"),
            FakeAppAttest.keyID
        )

        let firstCheckIn = httpClient.requests[4]
        let replayedCheckIn = httpClient.requests[5]
        XCTAssertEqual(firstCheckIn.httpBody, replayedCheckIn.httpBody)
        XCTAssertEqual(
            firstCheckIn.value(forHTTPHeaderField: "x-gametime-assertion"),
            replayedCheckIn.value(forHTTPHeaderField: "x-gametime-assertion")
        )
        XCTAssertEqual(
            firstCheckIn.value(forHTTPHeaderField: "x-gametime-key-id"),
            FakeAppAttest.keyID
        )
        XCTAssertEqual(
            updates.filter { $0.state == .succeeded }.map(\.step),
            ConformanceStep.allCases
        )
        let registrationDetail = updates.first {
            $0.step == .registration && $0.state == .succeeded
        }?.detail
        XCTAssertTrue(
            registrationDetail?.contains(
                "validation category not supplied by attestation, "
                    + "bundle version not supplied by attestation"
            ) == true
        )
    }

    func testRejectsEveryServerProofInvariantMismatch() async {
        for mismatch in ServerProofMismatch.allCases {
            await assertRunFails(
                appAttest: FakeAppAttest(),
                httpClient: RecordingHTTPClient(mismatch: mismatch),
                label: String(describing: mismatch)
            )
        }
    }

    func testRejectsZeroOrNonAdvancingAssertionCounters() async {
        await assertRunFails(
            appAttest: FakeAppAttest(assertionCounters: [0, 1]),
            httpClient: RecordingHTTPClient(),
            label: "zero metric counter"
        )
        await assertRunFails(
            appAttest: FakeAppAttest(assertionCounters: [1, 1]),
            httpClient: RecordingHTTPClient(),
            label: "non-advancing check-in counter"
        )
    }

    private func assertRunFails(
        appAttest: FakeAppAttest,
        httpClient: RecordingHTTPClient,
        label: String
    ) async {
        let runner = ConformanceRunner(
            appAttest: appAttest,
            keyStore: InMemoryKeyStore(),
            httpClient: httpClient,
            now: { Date(timeIntervalSince1970: 1_782_921_600) }
        )

        do {
            _ = try await runner.run(input: validInput()) { _ in }
            XCTFail("Runner accepted proof mismatch: \(label)")
        } catch {
            // Expected: each fixture violates one explicit live-proof gate.
        }
    }

    private func validInput() -> ConformanceInput {
        ConformanceInput(
            stagingURL: "https://abcdefghijklmnopqrst.supabase.co",
            apiKey: "publishable-key",
            accessJWT: "header.payload.signature",
            contestID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            geofenceID: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            latitude: "41.881",
            longitude: "-87.629",
            participantTimeZone: "America/Chicago"
        )
    }
}

@MainActor
private final class FakeAppAttest: AppAttestProviding {
    static let keyID = "returned-key-id+/=="

    private let assertionCounters: [UInt32]
    var generatedKeyCount = 0
    var attestationHashes: [Data] = []
    var assertionHashes: [Data] = []

    init(assertionCounters: [UInt32] = [1, 2]) {
        self.assertionCounters = assertionCounters
    }

    var isSupported: Bool { true }

    func generateKey() async throws -> String {
        generatedKeyCount += 1
        return Self.keyID
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        XCTAssertEqual(keyID, Self.keyID)
        attestationHashes.append(clientDataHash)
        return Data([0xa1, 0x01])
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        XCTAssertEqual(keyID, Self.keyID)
        assertionHashes.append(clientDataHash)
        let index = assertionHashes.count - 1
        return makeAssertion(counter: assertionCounters[index])
    }
}

@MainActor
private final class InMemoryKeyStore: KeyIDStoring {
    private var value: String?

    func loadKeyID() -> String? {
        value
    }

    func saveKeyID(_ keyID: String) throws {
        value = keyID
    }
}

@MainActor
private final class RecordingHTTPClient: ConformanceHTTPClient {
    private let mismatch: ServerProofMismatch?
    private(set) var requests: [URLRequest] = []
    private var metricCount = 0
    private var checkInCount = 0

    init(mismatch: ServerProofMismatch? = nil) {
        self.mismatch = mismatch
    }

    func send(_ request: URLRequest) async throws -> ConformanceHTTPResponse {
        requests.append(request)
        let path = try XCTUnwrap(request.url?.path)

        switch path {
        case let value where value.hasSuffix("/attest-device/challenge"):
            let challengeCount = mismatch == .shortChallenge ? 31 : 32
            let challenge = Data(
                repeating: 0xa5,
                count: challengeCount
            ).base64EncodedString()
            return response(
                #"{"challenge":"\#(challenge)","expiresInSeconds":600}"#
            )
        case let value where value.hasSuffix("/attest-device"):
            let registered = mismatch == .registrationFalse ? "false" : "true"
            let environment = mismatch == .productionRegistration
                ? "production"
                : "development"
            return response(
                #"{"registered":\#(registered),"environment":"\#(environment)","validationCategory":null,"bundleVersion":null}"#
            )
        case let value where value.hasSuffix("/ingest-metrics"):
            metricCount += 1
            let isReplay = metricCount == 2
            let status: Int
            if isReplay {
                status = mismatch == .metricReplayStatus ? 201 : 200
            } else {
                status = mismatch == .metricFirstStatus ? 200 : 201
            }
            let replayed: String
            if isReplay {
                replayed = mismatch == .metricReplayFalse ? "false" : "true"
            } else {
                replayed = mismatch == .metricFirstReplayed ? "true" : "false"
            }
            let batchID = isReplay && mismatch == .metricReplayDifferentID
                ? "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
                : "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
            let observationCount = !isReplay && mismatch == .metricObservationCount ? 2 : 1
            return response(
                #"{"batchId":"\#(batchID)","observationCount":\#(observationCount),"replayed":\#(replayed)}"#,
                status: status
            )
        case let value where value.hasSuffix("/ingest-checkin"):
            checkInCount += 1
            let isReplay = checkInCount == 2
            let status: Int
            if isReplay {
                status = mismatch == .checkInReplayStatus ? 201 : 200
            } else {
                status = mismatch == .checkInFirstStatus ? 200 : 201
            }
            let replayed: String
            if isReplay {
                replayed = mismatch == .checkInReplayFalse ? "false" : "true"
            } else {
                replayed = mismatch == .checkInFirstReplayed ? "true" : "false"
            }
            let checkInID = isReplay && mismatch == .checkInReplayDifferentID
                ? "ffffffff-ffff-4fff-8fff-ffffffffffff"
                : "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
            let outcome = !isReplay && mismatch == .checkInOutcome
                ? "outside_geofence"
                : "accepted"
            return response(
                #"{"checkInId":"\#(checkInID)","outcome":"\#(outcome)","dwellSeconds":180,"workoutOverlapSeconds":180,"replayed":\#(replayed)}"#,
                status: status
            )
        default:
            XCTFail("Unexpected endpoint \(path)")
            return response(#"{"error":"unexpected"}"#, status: 500)
        }
    }

    private func response(
        _ json: String,
        status: Int = 200
    ) -> ConformanceHTTPResponse {
        ConformanceHTTPResponse(statusCode: status, body: Data(json.utf8))
    }
}

private enum ServerProofMismatch: CaseIterable {
    case shortChallenge
    case registrationFalse
    case productionRegistration
    case metricFirstStatus
    case metricFirstReplayed
    case metricObservationCount
    case metricReplayStatus
    case metricReplayFalse
    case metricReplayDifferentID
    case checkInFirstStatus
    case checkInFirstReplayed
    case checkInOutcome
    case checkInReplayStatus
    case checkInReplayFalse
    case checkInReplayDifferentID
}
