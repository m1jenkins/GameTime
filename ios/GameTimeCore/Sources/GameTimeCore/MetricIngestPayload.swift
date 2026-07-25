import Foundation

/// The semantic body for `POST /ingest-metrics`.
///
/// The app target deals in `HourlyBucket` values and never needs to know the
/// endpoint's camel-case field names. Encoding is deliberately a separate,
/// throwing step: an App Attest assertion must cover the exact bytes that are
/// later transmitted, so callers retain `EncodedMetricRequest.body` rather
/// than re-encoding this value for a retry.
public struct AttestedMetricPayload: Sendable, Hashable {
    public let contestId: UUID
    public let clientBatchId: UUID
    public let observedAt: Date
    public let observations: [HourlyBucket]

    public init(
        contestId: UUID,
        clientBatchId: UUID,
        observedAt: Date,
        observations: [HourlyBucket]
    ) {
        self.contestId = contestId
        self.clientBatchId = clientBatchId
        self.observedAt = observedAt
        self.observations = observations
    }

    /// Bridges the existing offline queue to the exact-byte request boundary.
    public init(batch: PendingBatch) {
        self.init(
            contestId: batch.contestId,
            clientBatchId: batch.clientBatchId,
            observedAt: batch.observedAt,
            observations: batch.buckets
        )
    }
}

/// A locally knowable reason a metric body cannot be sent.
///
/// These bounds mirror the effective server contract: the Edge Function checks
/// count, numeric, and UTF-16 string ceilings, while the ledger additionally
/// refuses empty metadata and duplicate metric/hour/provenance rows.
public enum MetricPayloadEncodingError: Error, Sendable, Equatable {
    case invalidObservationCount
    case invalidObservedAt
    case invalidBucketStart(index: Int)
    case invalidValue(index: Int)
    case invalidSampleCount(index: Int)
    case invalidSourceBundleIdentifier(index: Int)
    case invalidDeviceModel(index: Int)
    case duplicateObservation(index: Int)
    case bodyCannotBeEncoded
    case bodyTooLarge
}

/// One already-encoded request whose exact bytes are ready for App Attest.
///
/// App Attest signs the SHA-256 digest of `body`. Hash and transmit this stored
/// value; do not encode the semantic payload again after generating an
/// assertion. `clientBatchId` remains available for durable retry bookkeeping.
public struct EncodedMetricRequest: Sendable, Hashable {
    /// The same ceiling enforced by `ingest-metrics` and
    /// `record_metric_batch()`.
    public static let maximumObservationCount = 2_000

    /// The same byte ceiling enforced before the endpoint parses the body.
    public static let maximumBodyBytes = 1_024 * 1_024

    public let clientBatchId: UUID
    public let body: Data

    public init(payload: AttestedMetricPayload) throws {
        self.clientBatchId = payload.clientBatchId
        self.body = try MetricPayloadEncoder.encode(payload)
    }
}

private enum MetricPayloadEncoder {
    private struct WireObservation: Encodable {
        let metric: String
        let bucketStart: String
        let value: Double
        let provenance: String
        let sampleCount: Int
        let sourceBundleId: String?
        let deviceModel: String?
    }

    private struct WirePayload: Encodable {
        let contestId: String
        let clientBatchId: String
        let observedAt: String
        let observations: [WireObservation]
    }

    private struct ObservationIdentity: Hashable {
        let metric: ContestMetric
        let bucketStart: String
        let provenance: MetricProvenance
    }

    static func encode(_ payload: AttestedMetricPayload) throws -> Data {
        guard
            (1...EncodedMetricRequest.maximumObservationCount)
                .contains(payload.observations.count)
        else {
            throw MetricPayloadEncodingError.invalidObservationCount
        }
        guard let observedAt = timestamp(payload.observedAt) else {
            throw MetricPayloadEncodingError.invalidObservedAt
        }

        var identities: Set<ObservationIdentity> = []
        var observations: [WireObservation] = []
        observations.reserveCapacity(payload.observations.count)

        for (index, bucket) in payload.observations.enumerated() {
            guard let bucketStart = timestamp(bucket.bucketStart) else {
                throw MetricPayloadEncodingError.invalidBucketStart(index: index)
            }

            guard bucket.value.isFinite, bucket.value >= 0 else {
                throw MetricPayloadEncodingError.invalidValue(index: index)
            }
            // HealthKit aggregation already rounds to hundredths. Repeating the
            // endpoint's rule here also protects callers that construct an
            // HourlyBucket directly.
            let roundedValue = (bucket.value * 100).rounded() / 100
            guard roundedValue.isFinite, roundedValue < 1e10 else {
                throw MetricPayloadEncodingError.invalidValue(index: index)
            }

            guard (1...100_000).contains(bucket.sampleCount) else {
                throw MetricPayloadEncodingError.invalidSampleCount(index: index)
            }
            if let sourceBundleIdentifier = bucket.sourceBundleIdentifier {
                guard !sourceBundleIdentifier.isEmpty,
                      sourceBundleIdentifier.utf16.count <= 200
                else {
                    throw MetricPayloadEncodingError
                        .invalidSourceBundleIdentifier(index: index)
                }
            }
            if let deviceModel = bucket.deviceModel {
                guard !deviceModel.isEmpty, deviceModel.utf16.count <= 100 else {
                    throw MetricPayloadEncodingError.invalidDeviceModel(index: index)
                }
            }

            let identity = ObservationIdentity(
                metric: bucket.metric,
                bucketStart: bucketStart,
                provenance: bucket.provenance
            )
            guard identities.insert(identity).inserted else {
                throw MetricPayloadEncodingError.duplicateObservation(index: index)
            }

            observations.append(
                WireObservation(
                    metric: bucket.metric.rawValue,
                    bucketStart: bucketStart,
                    value: roundedValue == 0 ? 0 : roundedValue,
                    provenance: bucket.provenance.rawValue,
                    sampleCount: bucket.sampleCount,
                    sourceBundleId: bucket.sourceBundleIdentifier,
                    deviceModel: bucket.deviceModel
                )
            )
        }

        // Array order has no semantic meaning to the endpoint. Canonicalising
        // it prevents HealthKit query order or dictionary iteration order from
        // changing the digest. Every encoded field participates so this remains
        // a total order even for canonically equivalent Unicode strings.
        observations.sort(by: precedes)

        let wire = WirePayload(
            contestId: payload.contestId.uuidString.lowercased(),
            clientBatchId: payload.clientBatchId.uuidString.lowercased(),
            observedAt: observedAt,
            observations: observations
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        let body: Data
        do {
            body = try encoder.encode(wire)
        } catch {
            throw MetricPayloadEncodingError.bodyCannotBeEncoded
        }
        guard body.count <= EncodedMetricRequest.maximumBodyBytes else {
            throw MetricPayloadEncodingError.bodyTooLarge
        }
        return body
    }

    /// Produces one deliberately narrow RFC 3339 spelling: UTC with exactly
    /// three fractional digits. The shape check makes an SDK formatting change
    /// fail visibly rather than silently changing bytes that App Attest signs.
    private static func timestamp(_ date: Date) -> String? {
        guard date.timeIntervalSince1970.isFinite else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let value = formatter.string(from: date)
        let bytes = Array(value.utf8)

        guard bytes.count == 24,
              bytes[4] == Character("-").asciiValue,
              bytes[7] == Character("-").asciiValue,
              bytes[10] == Character("T").asciiValue,
              bytes[13] == Character(":").asciiValue,
              bytes[16] == Character(":").asciiValue,
              bytes[19] == Character(".").asciiValue,
              bytes[23] == Character("Z").asciiValue
        else {
            return nil
        }

        let separators: Set<Int> = [4, 7, 10, 13, 16, 19, 23]
        for index in bytes.indices where !separators.contains(index) {
            guard (Character("0").asciiValue!...Character("9").asciiValue!)
                .contains(bytes[index])
            else {
                return nil
            }
        }
        return value
    }

    private static func precedes(
        _ left: WireObservation,
        _ right: WireObservation
    ) -> Bool {
        for comparison in [
            utf8Comparison(left.bucketStart, right.bucketStart),
            utf8Comparison(left.metric, right.metric),
            utf8Comparison(left.provenance, right.provenance),
            utf8Comparison(left.sourceBundleId, right.sourceBundleId),
            utf8Comparison(left.deviceModel, right.deviceModel),
        ] where comparison != 0 {
            return comparison < 0
        }
        if left.value != right.value {
            return left.value < right.value
        }
        return left.sampleCount < right.sampleCount
    }

    /// String's normal comparison is canonically equivalent, while JSON
    /// preserves the original scalar spelling. Comparing UTF-8 gives distinct
    /// wire strings a distinct and platform-independent order.
    private static func utf8Comparison(_ left: String, _ right: String) -> Int {
        let leftBytes = Array(left.utf8)
        let rightBytes = Array(right.utf8)
        if leftBytes == rightBytes { return 0 }
        return leftBytes.lexicographicallyPrecedes(rightBytes) ? -1 : 1
    }

    private static func utf8Comparison(_ left: String?, _ right: String?) -> Int {
        switch (left, right) {
        case (nil, nil):
            return 0
        case (nil, .some):
            return -1
        case (.some, nil):
            return 1
        case let (.some(left), .some(right)):
            return utf8Comparison(left, right)
        }
    }
}
