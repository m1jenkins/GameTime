import Foundation

/// The server-owned geometry and validation thresholds for one contest venue.
///
/// No threshold is hidden in the evaluator. The app receives the versioned
/// configuration that the server will use, evaluates it locally for immediate
/// feedback, and still submits every raw observation because the server is the
/// authority.
public struct ContestGeofenceConfiguration: Sendable, Hashable {
    public let contestId: UUID
    public let geofenceId: UUID
    public let validationVersion: String
    public let latitude: Double
    public let longitude: Double
    public let radiusMeters: Double
    public let maximumHorizontalAccuracyMeters: Double
    public let minimumDwellDuration: TimeInterval
    public let maximumSampleGap: TimeInterval
    public let minimumWorkoutOverlapDuration: TimeInterval

    public init(
        contestId: UUID,
        geofenceId: UUID,
        validationVersion: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Double,
        maximumHorizontalAccuracyMeters: Double,
        minimumDwellDuration: TimeInterval,
        maximumSampleGap: TimeInterval,
        minimumWorkoutOverlapDuration: TimeInterval
    ) throws {
        guard latitude.isFinite,
              longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude)
        else {
            throw CheckInAssessmentError.invalidGeofenceCoordinate
        }
        guard radiusMeters.isFinite, radiusMeters > 0, radiusMeters <= 100_000 else {
            throw CheckInAssessmentError.invalidRadius
        }
        guard maximumHorizontalAccuracyMeters.isFinite,
              maximumHorizontalAccuracyMeters > 0,
              maximumHorizontalAccuracyMeters <= 100_000
        else {
            throw CheckInAssessmentError.invalidMaximumHorizontalAccuracy
        }
        guard minimumDwellDuration.isFinite,
              (1...28_800).contains(minimumDwellDuration)
        else {
            throw CheckInAssessmentError.invalidMinimumDwellDuration
        }
        guard maximumSampleGap.isFinite,
              (1...3_600).contains(maximumSampleGap)
        else {
            throw CheckInAssessmentError.invalidMaximumSampleGap
        }
        guard minimumWorkoutOverlapDuration.isFinite,
              (1...28_800).contains(minimumWorkoutOverlapDuration)
        else {
            throw CheckInAssessmentError.invalidMinimumWorkoutOverlapDuration
        }

        self.contestId = contestId
        self.geofenceId = geofenceId
        self.validationVersion = validationVersion
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.maximumHorizontalAccuracyMeters = maximumHorizontalAccuracyMeters
        self.minimumDwellDuration = minimumDwellDuration
        self.maximumSampleGap = maximumSampleGap
        self.minimumWorkoutOverlapDuration = minimumWorkoutOverlapDuration
    }
}

/// One CoreLocation reading, expressed without importing CoreLocation.
///
/// The app target maps `CLLocation` and `CLLocationSourceInformation` into this
/// value. Keeping the raw source flags is deliberate: simulated readings are
/// evidence of a failed validation, not observations the client should hide.
public struct CheckInLocationSample: Sendable, Hashable {
    public let observedAt: Date
    public let latitude: Double
    public let longitude: Double
    public let horizontalAccuracyMeters: Double
    public let isSimulatedBySoftware: Bool
    public let isProducedByAccessory: Bool

    public init(
        observedAt: Date,
        latitude: Double,
        longitude: Double,
        horizontalAccuracyMeters: Double,
        isSimulatedBySoftware: Bool = false,
        isProducedByAccessory: Bool = false
    ) {
        self.observedAt = observedAt
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.isSimulatedBySoftware = isSimulatedBySoftware
        self.isProducedByAccessory = isProducedByAccessory
    }
}

/// One HealthKit workout interval, expressed without importing HealthKit.
///
/// Dates are absolute instants. No timezone participates in overlap: both the
/// client and server use half-open ranges `[startedAt, endedAt)`.
public struct WorkoutInterval: Sendable, Hashable {
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date
    public let activityType: String
    public let provenance: MetricProvenance
    public let sourceBundleId: String?

    public init(
        id: UUID,
        startedAt: Date,
        endedAt: Date,
        activityType: String,
        provenance: MetricProvenance,
        sourceBundleId: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activityType = activityType
        self.provenance = provenance
        self.sourceBundleId = sourceBundleId
    }
}

/// The server-mirroring classification of one raw location reading.
public enum LocationValidationOutcome: String, Sendable, Hashable, Codable {
    case inside
    case outside
    case simulated
    case lowAccuracy = "low_accuracy"
    case invalidLocation = "invalid_location"
}

/// One classified sample plus the server-reproducible geometry behind it.
public struct LocationSampleValidation: Sendable, Hashable {
    public let sample: CheckInLocationSample
    public let outcome: LocationValidationOutcome
    /// Great-circle distance from the configured center, absent for bad input.
    public let distanceFromCenterMeters: Double?

    public init(
        sample: CheckInLocationSample,
        outcome: LocationValidationOutcome,
        distanceFromCenterMeters: Double?
    ) {
        self.sample = sample
        self.outcome = outcome
        self.distanceFromCenterMeters = distanceFromCenterMeters
    }
}

/// A contiguous span credited as dwell, with half-open range semantics.
public struct CreditedDwellSegment: Sendable, Hashable {
    public let startedAt: Date
    public let endedAt: Date

    public init(startedAt: Date, endedAt: Date) {
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    public var duration: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }
}

/// The workout's intersection with the union of credited dwell segments.
public struct WorkoutOverlapAssessment: Sendable, Hashable {
    public let overlapDuration: TimeInterval
    public let workoutDuration: TimeInterval
    public let overlapFraction: Double
    public let meetsMinimumOverlap: Bool

    public init(
        overlapDuration: TimeInterval,
        workoutDuration: TimeInterval,
        overlapFraction: Double,
        meetsMinimumOverlap: Bool
    ) {
        self.overlapDuration = overlapDuration
        self.workoutDuration = workoutDuration
        self.overlapFraction = overlapFraction
        self.meetsMinimumOverlap = meetsMinimumOverlap
    }
}

/// A local preview of the server's geofence and workout validation.
///
/// This value is advisory. The signed request carries raw locations and the
/// workout interval, not these conclusions; the server sorts and evaluates the
/// evidence again and persists its own auditable outcomes.
public struct CheckInAssessment: Sendable, Hashable {
    public let locationValidations: [LocationSampleValidation]
    public let dwellSegments: [CreditedDwellSegment]
    public let creditedDwellDuration: TimeInterval
    public let meetsMinimumDwell: Bool
    public let workoutOverlap: WorkoutOverlapAssessment
    /// Mirrors the server's invariant: manual and unknown workouts cannot
    /// validate presence even when their timestamps overlap.
    public let workoutIsTrusted: Bool

    public init(
        locationValidations: [LocationSampleValidation],
        dwellSegments: [CreditedDwellSegment],
        creditedDwellDuration: TimeInterval,
        meetsMinimumDwell: Bool,
        workoutOverlap: WorkoutOverlapAssessment,
        workoutIsTrusted: Bool
    ) {
        self.locationValidations = locationValidations
        self.dwellSegments = dwellSegments
        self.creditedDwellDuration = creditedDwellDuration
        self.meetsMinimumDwell = meetsMinimumDwell
        self.workoutOverlap = workoutOverlap
        self.workoutIsTrusted = workoutIsTrusted
    }

    public var isLocallyValid: Bool {
        let hasServerRejectedLocation = locationValidations.contains {
            $0.outcome == .simulated || $0.outcome == .invalidLocation
        }
        return !hasServerRejectedLocation
            && workoutIsTrusted
            && meetsMinimumDwell
            && workoutOverlap.meetsMinimumOverlap
    }
}

public enum CheckInAssessmentError: Error, Sendable, Equatable {
    case invalidGeofenceCoordinate
    case invalidRadius
    case invalidMaximumHorizontalAccuracy
    case invalidMinimumDwellDuration
    case invalidMaximumSampleGap
    case invalidMinimumWorkoutOverlapDuration
    case invalidWorkoutInterval
}

/// Pure, portable geofence and workout-overlap evaluation.
public enum GeofenceCheckInEvaluator {
    /// IUGG mean Earth radius, also used by the server integrity sidecar.
    private static let earthRadiusMeters = 6_371_008.8

    /// Evaluates raw observations using absolute instants only.
    ///
    /// A dwell segment exists only between adjacent, inside samples whose gap
    /// is positive and no larger than `maximumSampleGap`. A larger gap credits
    /// no unseen time. Touching segments are merged before workout overlap is
    /// computed, so the same second is never counted twice.
    public static func assess(
        configuration: ContestGeofenceConfiguration,
        locations: [CheckInLocationSample],
        workout: WorkoutInterval
    ) throws -> CheckInAssessment {
        try validate(configuration)
        guard workout.startedAt.timeIntervalSince1970.isFinite,
              workout.endedAt.timeIntervalSince1970.isFinite,
              workout.endedAt > workout.startedAt,
              workout.endedAt.timeIntervalSince(workout.startedAt) <= 86_400
        else {
            throw CheckInAssessmentError.invalidWorkoutInterval
        }

        let ordered = deterministicallyOrdered(locations)
        let validations = ordered.map {
            classify($0, configuration: configuration)
        }

        var segments: [CreditedDwellSegment] = []
        if validations.count > 1 {
            for index in 1..<validations.count {
                let previous = validations[index - 1]
                let current = validations[index]
                guard previous.outcome == .inside, current.outcome == .inside else {
                    continue
                }

                let gap = current.sample.observedAt.timeIntervalSince(
                    previous.sample.observedAt
                )
                guard gap > 0, gap <= configuration.maximumSampleGap else {
                    continue
                }

                let candidate = CreditedDwellSegment(
                    startedAt: previous.sample.observedAt,
                    endedAt: current.sample.observedAt
                )
                if let last = segments.last, candidate.startedAt <= last.endedAt {
                    segments[segments.count - 1] = CreditedDwellSegment(
                        startedAt: last.startedAt,
                        endedAt: max(last.endedAt, candidate.endedAt)
                    )
                } else {
                    segments.append(candidate)
                }
            }
        }

        let creditedDwell = segments.reduce(0) { $0 + $1.duration }
        let workoutDuration = workout.endedAt.timeIntervalSince(workout.startedAt)
        let overlap = segments.reduce(0) { total, segment in
            let startsAt = max(segment.startedAt, workout.startedAt)
            let endsAt = min(segment.endedAt, workout.endedAt)
            return total + max(0, endsAt.timeIntervalSince(startsAt))
        }

        return CheckInAssessment(
            locationValidations: validations,
            dwellSegments: segments,
            creditedDwellDuration: creditedDwell,
            meetsMinimumDwell: creditedDwell >= configuration.minimumDwellDuration,
            workoutOverlap: WorkoutOverlapAssessment(
                overlapDuration: overlap,
                workoutDuration: workoutDuration,
                overlapFraction: overlap / workoutDuration,
                meetsMinimumOverlap:
                    overlap >= configuration.minimumWorkoutOverlapDuration
            ),
            workoutIsTrusted: workout.provenance.isAdmissible
        )
    }

    /// Great-circle distance using the haversine formula.
    ///
    /// Public so fixture suites can pin the inclusive geofence boundary without
    /// copying the geometry implementation into their setup.
    public static func distanceMeters(
        fromLatitude: Double,
        longitude fromLongitude: Double,
        toLatitude: Double,
        longitude toLongitude: Double
    ) -> Double {
        let fromLatitudeRadians = radians(fromLatitude)
        let toLatitudeRadians = radians(toLatitude)
        let latitudeDelta = toLatitudeRadians - fromLatitudeRadians
        let longitudeDelta = radians(toLongitude - fromLongitude)
        let haversine = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(fromLatitudeRadians) * cos(toLatitudeRadians)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return 2 * earthRadiusMeters * asin(min(1, sqrt(max(0, haversine))))
    }

    private static func validate(_ configuration: ContestGeofenceConfiguration) throws {
        guard configuration.latitude.isFinite,
              configuration.longitude.isFinite,
              (-90...90).contains(configuration.latitude),
              (-180...180).contains(configuration.longitude)
        else {
            throw CheckInAssessmentError.invalidGeofenceCoordinate
        }
        guard configuration.radiusMeters.isFinite,
              configuration.radiusMeters > 0,
              configuration.radiusMeters <= 100_000
        else {
            throw CheckInAssessmentError.invalidRadius
        }
        guard configuration.maximumHorizontalAccuracyMeters.isFinite,
              configuration.maximumHorizontalAccuracyMeters > 0,
              configuration.maximumHorizontalAccuracyMeters <= 100_000
        else {
            throw CheckInAssessmentError.invalidMaximumHorizontalAccuracy
        }
        guard configuration.minimumDwellDuration.isFinite,
              (1...28_800).contains(configuration.minimumDwellDuration)
        else {
            throw CheckInAssessmentError.invalidMinimumDwellDuration
        }
        guard configuration.maximumSampleGap.isFinite,
              (1...3_600).contains(configuration.maximumSampleGap)
        else {
            throw CheckInAssessmentError.invalidMaximumSampleGap
        }
        guard configuration.minimumWorkoutOverlapDuration.isFinite,
              (1...28_800).contains(
                  configuration.minimumWorkoutOverlapDuration
              )
        else {
            throw CheckInAssessmentError.invalidMinimumWorkoutOverlapDuration
        }
    }

    private static func classify(
        _ sample: CheckInLocationSample,
        configuration: ContestGeofenceConfiguration
    ) -> LocationSampleValidation {
        guard sample.observedAt.timeIntervalSince1970.isFinite,
              sample.latitude.isFinite,
              sample.longitude.isFinite,
              sample.horizontalAccuracyMeters.isFinite,
              (-90...90).contains(sample.latitude),
              (-180...180).contains(sample.longitude),
              sample.horizontalAccuracyMeters > 0,
              sample.horizontalAccuracyMeters <= 100_000
        else {
            return LocationSampleValidation(
                sample: sample,
                outcome: .invalidLocation,
                distanceFromCenterMeters: nil
            )
        }

        let distance = distanceMeters(
            fromLatitude: configuration.latitude,
            longitude: configuration.longitude,
            toLatitude: sample.latitude,
            longitude: sample.longitude
        )
        let outcome: LocationValidationOutcome
        if sample.isSimulatedBySoftware {
            outcome = .simulated
        } else if
            sample.horizontalAccuracyMeters
                > configuration.maximumHorizontalAccuracyMeters
        {
            outcome = .lowAccuracy
        } else if distance <= configuration.radiusMeters {
            outcome = .inside
        } else {
            outcome = .outside
        }

        return LocationSampleValidation(
            sample: sample,
            outcome: outcome,
            distanceFromCenterMeters: distance
        )
    }

    private static func deterministicallyOrdered(
        _ samples: [CheckInLocationSample]
    ) -> [CheckInLocationSample] {
        samples.enumerated()
            .sorted { left, right in
                let leftTime = left.element.observedAt.timeIntervalSince1970
                let rightTime = right.element.observedAt.timeIntervalSince1970
                if leftTime.isFinite != rightTime.isFinite {
                    return leftTime.isFinite
                }
                if leftTime != rightTime {
                    return leftTime < rightTime
                }
                if left.element.latitude != right.element.latitude {
                    return left.element.latitude < right.element.latitude
                }
                if left.element.longitude != right.element.longitude {
                    return left.element.longitude < right.element.longitude
                }
                if
                    left.element.horizontalAccuracyMeters
                        != right.element.horizontalAccuracyMeters
                {
                    return left.element.horizontalAccuracyMeters
                        < right.element.horizontalAccuracyMeters
                }
                if
                    left.element.isSimulatedBySoftware
                        != right.element.isSimulatedBySoftware
                {
                    return !left.element.isSimulatedBySoftware
                }
                if
                    left.element.isProducedByAccessory
                        != right.element.isProducedByAccessory
                {
                    return !left.element.isProducedByAccessory
                }
                return left.offset < right.offset
            }
            .map(\.element)
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * Double.pi / 180
    }
}

/// The semantic body for `POST /ingest-checkin`.
///
/// It intentionally contains raw observations and no caller-supplied outcome,
/// dwell duration, distance, or overlap. Those are all recomputed by the server.
public struct AttestedCheckInPayload: Sendable, Hashable {
    public let contestId: UUID
    public let geofenceId: UUID
    public let clientCheckInId: UUID
    public let locations: [CheckInLocationSample]
    public let workout: WorkoutInterval

    public init(
        contestId: UUID,
        geofenceId: UUID,
        clientCheckInId: UUID,
        locations: [CheckInLocationSample],
        workout: WorkoutInterval
    ) {
        self.contestId = contestId
        self.geofenceId = geofenceId
        self.clientCheckInId = clientCheckInId
        self.locations = locations
        self.workout = workout
    }
}

public enum CheckInPayloadEncodingError: Error, Sendable, Equatable {
    case invalidLocationCount
    case invalidLocationSpan
    case duplicateLocationTimestamp
    case invalidLocation(index: Int)
    case invalidWorkoutInterval
    case invalidWorkoutMetadata
    case timestampCannotBeEncoded
}

/// One already-encoded request whose exact bytes are ready for App Attest.
///
/// App Attest signs the SHA-256 digest of `body`. Callers must hash and transmit
/// this stored value rather than encode `payload` again.
public struct EncodedCheckInRequest: Sendable, Hashable {
    public let clientCheckInId: UUID
    public let body: Data

    public init(payload: AttestedCheckInPayload) throws {
        guard (2...256).contains(payload.locations.count) else {
            throw CheckInPayloadEncodingError.invalidLocationCount
        }
        var timestamps: Set<String> = []
        for (index, location) in payload.locations.enumerated() {
            guard location.observedAt.timeIntervalSince1970.isFinite,
                  location.latitude.isFinite,
                  location.longitude.isFinite,
                  (-90...90).contains(location.latitude),
                  (-180...180).contains(location.longitude),
                  location.horizontalAccuracyMeters.isFinite,
                  location.horizontalAccuracyMeters > 0,
                  location.horizontalAccuracyMeters <= 100_000
            else {
                throw CheckInPayloadEncodingError.invalidLocation(index: index)
            }
            let timestamp = try CheckInPayloadEncoder.timestamp(location.observedAt)
            guard timestamps.insert(timestamp).inserted else {
                throw CheckInPayloadEncodingError.duplicateLocationTimestamp
            }
        }
        let orderedDates = payload.locations.map(\.observedAt).sorted()
        if let first = orderedDates.first, let last = orderedDates.last,
           last.timeIntervalSince(first) > 28_800
        {
            throw CheckInPayloadEncodingError.invalidLocationSpan
        }
        guard payload.workout.startedAt.timeIntervalSince1970.isFinite,
              payload.workout.endedAt.timeIntervalSince1970.isFinite,
              payload.workout.endedAt > payload.workout.startedAt,
              payload.workout.endedAt.timeIntervalSince(payload.workout.startedAt)
                  <= 86_400
        else {
            throw CheckInPayloadEncodingError.invalidWorkoutInterval
        }
        let workoutStartedAt = try CheckInPayloadEncoder.timestamp(
            payload.workout.startedAt
        )
        let workoutEndedAt = try CheckInPayloadEncoder.timestamp(
            payload.workout.endedAt
        )
        guard workoutEndedAt > workoutStartedAt else {
            throw CheckInPayloadEncodingError.invalidWorkoutInterval
        }
        guard !payload.workout.activityType.isEmpty,
              payload.workout.activityType.utf16.count <= 100,
              payload.workout.sourceBundleId.map({
                  !$0.isEmpty && $0.utf16.count <= 200
              }) ?? true
        else {
            throw CheckInPayloadEncodingError.invalidWorkoutMetadata
        }

        self.clientCheckInId = payload.clientCheckInId
        self.body = try CheckInPayloadEncoder.encode(payload)
    }
}

private enum CheckInPayloadEncoder {
    private struct WireLocation: Encodable {
        let observedAt: String
        let latitude: Double
        let longitude: Double
        let horizontalAccuracyMeters: Double
        let isSimulatedBySoftware: Bool
        let isProducedByAccessory: Bool
    }

    private struct WireWorkout: Encodable {
        let id: String
        let startedAt: String
        let endedAt: String
        let activityType: String
        let provenance: String
        let sourceBundleId: String?
    }

    private struct WirePayload: Encodable {
        let contestId: String
        let geofenceId: String
        let clientCheckInId: String
        let locations: [WireLocation]
        let workout: WireWorkout
    }

    static func encode(_ payload: AttestedCheckInPayload) throws -> Data {
        let locations = try deterministicallyOrdered(payload.locations).map {
            WireLocation(
                observedAt: try timestamp($0.observedAt),
                latitude: $0.latitude,
                longitude: $0.longitude,
                horizontalAccuracyMeters: $0.horizontalAccuracyMeters,
                isSimulatedBySoftware: $0.isSimulatedBySoftware,
                isProducedByAccessory: $0.isProducedByAccessory
            )
        }
        let workout = WireWorkout(
            id: payload.workout.id.uuidString.lowercased(),
            startedAt: try timestamp(payload.workout.startedAt),
            endedAt: try timestamp(payload.workout.endedAt),
            activityType: payload.workout.activityType,
            provenance: payload.workout.provenance.rawValue,
            sourceBundleId: payload.workout.sourceBundleId
        )
        let wire = WirePayload(
            contestId: payload.contestId.uuidString.lowercased(),
            geofenceId: payload.geofenceId.uuidString.lowercased(),
            clientCheckInId: payload.clientCheckInId.uuidString.lowercased(),
            locations: locations,
            workout: workout
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(wire)
    }

    fileprivate static func timestamp(_ date: Date) throws -> String {
        guard date.timeIntervalSince1970.isFinite else {
            throw CheckInPayloadEncodingError.timestampCannotBeEncoded
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func deterministicallyOrdered(
        _ samples: [CheckInLocationSample]
    ) -> [CheckInLocationSample] {
        samples.enumerated()
            .sorted { left, right in
                if left.element.observedAt != right.element.observedAt {
                    return left.element.observedAt < right.element.observedAt
                }
                if left.element.latitude != right.element.latitude {
                    return left.element.latitude < right.element.latitude
                }
                if left.element.longitude != right.element.longitude {
                    return left.element.longitude < right.element.longitude
                }
                if
                    left.element.horizontalAccuracyMeters
                        != right.element.horizontalAccuracyMeters
                {
                    return left.element.horizontalAccuracyMeters
                        < right.element.horizontalAccuracyMeters
                }
                if
                    left.element.isSimulatedBySoftware
                        != right.element.isSimulatedBySoftware
                {
                    return !left.element.isSimulatedBySoftware
                }
                if
                    left.element.isProducedByAccessory
                        != right.element.isProducedByAccessory
                {
                    return !left.element.isProducedByAccessory
                }
                return left.offset < right.offset
            }
            .map(\.element)
    }
}
