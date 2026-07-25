import Foundation
import Testing

@testable import GameTimeCore

@Suite("Attested metric payload")
struct AttestedMetricPayloadTests {
    static let contestId = UUID(
        uuidString: "A000000A-0000-0000-0000-00000000000A"
    )!
    static let batchId = UUID(
        uuidString: "B000000B-0000-0000-0000-00000000000B"
    )!
    static let epoch = instant("2026-08-01T13:00:00.000Z")

    static func instant(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        return formatter.date(from: value)!
    }

    static func bucket(
        metric: ContestMetric = .steps,
        hour: Double = 0,
        provenance: MetricProvenance = .device,
        value: Double = 812,
        sampleCount: Int = 6,
        sourceBundleIdentifier: String? = "com.apple.health",
        deviceModel: String? = "Watch"
    ) -> HourlyBucket {
        HourlyBucket(
            metric: metric,
            bucketStart: epoch.addingTimeInterval(hour * 3_600),
            provenance: provenance,
            value: value,
            sampleCount: sampleCount,
            sourceBundleIdentifier: sourceBundleIdentifier,
            deviceModel: deviceModel
        )
    }

    static func payload(
        observedAt: Date = epoch.addingTimeInterval(7_323.123),
        observations: [HourlyBucket] = [bucket()]
    ) -> AttestedMetricPayload {
        AttestedMetricPayload(
            contestId: contestId,
            clientBatchId: batchId,
            observedAt: observedAt,
            observations: observations
        )
    }

    static func encodingError(
        for payload: AttestedMetricPayload
    ) -> MetricPayloadEncodingError? {
        do {
            _ = try EncodedMetricRequest(payload: payload)
            return nil
        } catch let error as MetricPayloadEncodingError {
            return error
        } catch {
            return .bodyCannotBeEncoded
        }
    }

    @Test("fixture body pins every production field to exact bytes")
    func exactFixtureBytes() throws {
        let payload = Self.payload(
            observations: [
                Self.bucket(hour: 1),
                Self.bucket(
                    metric: .activeEnergyKcal,
                    provenance: .thirdParty,
                    value: 1234.567,
                    sampleCount: 2,
                    sourceBundleIdentifier: nil,
                    deviceModel: nil
                ),
            ]
        )

        let encoded = try EncodedMetricRequest(payload: payload)
        let body = String(decoding: encoded.body, as: UTF8.self)
        let expected = """
        {"clientBatchId":"b000000b-0000-0000-0000-00000000000b","contestId":"a000000a-0000-0000-0000-00000000000a","observations":[{"bucketStart":"2026-08-01T13:00:00.000Z","metric":"active_energy_kcal","provenance":"third_party","sampleCount":2,"value":1234.57},{"bucketStart":"2026-08-01T14:00:00.000Z","deviceModel":"Watch","metric":"steps","provenance":"device","sampleCount":6,"sourceBundleId":"com.apple.health","value":812}],"observedAt":"2026-08-01T15:02:03.123Z"}
        """

        #expect(body == expected)
        #expect(encoded.clientBatchId == Self.batchId)
    }

    @Test("observation input order and Unicode normalization do not change bytes")
    func deterministicObservationOrder() throws {
        let composed = Self.bucket(
            sourceBundleIdentifier: "\u{00E9}",
            deviceModel: "iPhone"
        )
        let decomposed = Self.bucket(
            provenance: .thirdParty,
            sourceBundleIdentifier: "e\u{0301}",
            deviceModel: "iPhone"
        )

        let first = try EncodedMetricRequest(
            payload: Self.payload(observations: [composed, decomposed])
        )
        let second = try EncodedMetricRequest(
            payload: Self.payload(observations: [decomposed, composed])
        )

        #expect(first.body == second.body)
    }

    @Test("a queued batch maps without changing its retry identity")
    func pendingBatchBridge() throws {
        var queue = IngestQueue()
        let queued = queue.enqueue(
            contestId: Self.contestId,
            buckets: [Self.bucket()],
            observedAt: Self.epoch,
            clientBatchId: Self.batchId
        )
        let batch = try #require(queued)

        let encoded = try EncodedMetricRequest(
            payload: AttestedMetricPayload(batch: batch)
        )

        #expect(encoded.clientBatchId == batch.clientBatchId)
        #expect(String(decoding: encoded.body, as: UTF8.self).contains(
            #""clientBatchId":"b000000b-0000-0000-0000-00000000000b""#
        ))
    }

    @Test("the endpoint observation count bounds are exact")
    func observationCountBounds() throws {
        #expect(
            Self.encodingError(for: Self.payload(observations: []))
                == .invalidObservationCount
        )

        let maximum = (0..<EncodedMetricRequest.maximumObservationCount).map {
            Self.bucket(hour: Double($0))
        }
        _ = try EncodedMetricRequest(payload: Self.payload(observations: maximum))

        let tooMany = maximum + [
            Self.bucket(hour: Double(EncodedMetricRequest.maximumObservationCount)),
        ]
        #expect(
            Self.encodingError(for: Self.payload(observations: tooMany))
                == .invalidObservationCount
        )
    }

    @Test("non-finite dates fail before signing")
    func nonFiniteDatesAreRejected() {
        #expect(
            Self.encodingError(
                for: Self.payload(
                    observedAt: Date(timeIntervalSince1970: .infinity)
                )
            ) == .invalidObservedAt
        )

        let bucket = HourlyBucket(
            metric: .steps,
            bucketStart: Date(timeIntervalSince1970: .nan),
            provenance: .device,
            value: 1,
            sampleCount: 1
        )
        #expect(
            Self.encodingError(for: Self.payload(observations: [bucket]))
                == .invalidBucketStart(index: 0)
        )
    }

    @Test("numeric bounds mirror the endpoint")
    func invalidNumbersAreRejected() {
        for value in [-1, Double.nan, Double.infinity, 10_000_000_000] {
            #expect(
                Self.encodingError(
                    for: Self.payload(observations: [
                        Self.bucket(value: value),
                    ])
                ) == .invalidValue(index: 0)
            )
        }

        for count in [0, 100_001] {
            #expect(
                Self.encodingError(
                    for: Self.payload(observations: [
                        Self.bucket(sampleCount: count),
                    ])
                ) == .invalidSampleCount(index: 0)
            )
        }
    }

    @Test("metadata uses the server's nonempty UTF-16 limits")
    func metadataBoundsAreValidated() throws {
        let sourceAtLimit = String(repeating: "😀", count: 100)
        let deviceAtLimit = String(repeating: "😀", count: 50)
        _ = try EncodedMetricRequest(
            payload: Self.payload(observations: [
                Self.bucket(
                    sampleCount: 100_000,
                    sourceBundleIdentifier: sourceAtLimit,
                    deviceModel: deviceAtLimit
                ),
            ])
        )

        for source in ["", String(repeating: "😀", count: 101)] {
            #expect(
                Self.encodingError(
                    for: Self.payload(observations: [
                        Self.bucket(sourceBundleIdentifier: source),
                    ])
                ) == .invalidSourceBundleIdentifier(index: 0)
            )
        }
        for device in ["", String(repeating: "😀", count: 51)] {
            #expect(
                Self.encodingError(
                    for: Self.payload(observations: [
                        Self.bucket(deviceModel: device),
                    ])
                ) == .invalidDeviceModel(index: 0)
            )
        }
    }

    @Test("duplicate ledger identities are refused at encoded precision")
    func duplicateObservationsAreRejected() {
        let first = Self.bucket()
        let duplicate = HourlyBucket(
            metric: first.metric,
            bucketStart: first.bucketStart.addingTimeInterval(0.000_1),
            provenance: first.provenance,
            value: first.value + 1,
            sampleCount: first.sampleCount,
            sourceBundleIdentifier: "different.source",
            deviceModel: "different model"
        )

        #expect(
            Self.encodingError(
                for: Self.payload(observations: [first, duplicate])
            ) == .duplicateObservation(index: 1)
        )
    }

    @Test("the exact body byte ceiling is enforced")
    func bodySizeIsBounded() {
        let source = String(repeating: "😀", count: 100)
        let device = String(repeating: "😀", count: 50)
        let observations = (0..<EncodedMetricRequest.maximumObservationCount).map {
            Self.bucket(
                hour: Double($0),
                sourceBundleIdentifier: source,
                deviceModel: device
            )
        }

        #expect(
            Self.encodingError(for: Self.payload(observations: observations))
                == .bodyTooLarge
        )
    }
}
