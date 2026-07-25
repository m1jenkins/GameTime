import Foundation
import Testing

@testable import GameTimeCore

@Suite("Geofence check-in evaluation")
struct GeofenceCheckInTests {
    static let contestId = UUID(
        uuidString: "a0000001-0000-0000-0000-000000000001"
    )!
    static let geofenceId = UUID(
        uuidString: "b0000001-0000-0000-0000-000000000001"
    )!
    static let checkInId = UUID(
        uuidString: "c0000001-0000-0000-0000-000000000001"
    )!
    static let workoutId = UUID(
        uuidString: "d0000001-0000-0000-0000-000000000001"
    )!
    static let epoch = instant("2026-08-01T15:05:00.000Z")

    static func instant(_ value: String) -> Date {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        if let date = withFractional.date(from: value) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)!
    }

    static func configuration(
        latitude: Double = 41,
        longitude: Double = -87,
        radiusMeters: Double = 100,
        maximumAccuracy: Double = 10,
        minimumDwell: TimeInterval = 120,
        maximumGap: TimeInterval = 60,
        minimumWorkoutOverlap: TimeInterval = 60
    ) throws -> ContestGeofenceConfiguration {
        try ContestGeofenceConfiguration(
            contestId: contestId,
            geofenceId: geofenceId,
            validationVersion: "m6-v1",
            latitude: latitude,
            longitude: longitude,
            radiusMeters: radiusMeters,
            maximumHorizontalAccuracyMeters: maximumAccuracy,
            minimumDwellDuration: minimumDwell,
            maximumSampleGap: maximumGap,
            minimumWorkoutOverlapDuration: minimumWorkoutOverlap
        )
    }

    static func location(
        second: TimeInterval,
        latitude: Double = 41,
        longitude: Double = -87,
        accuracy: Double = 5,
        simulated: Bool = false,
        accessory: Bool = false
    ) -> CheckInLocationSample {
        CheckInLocationSample(
            observedAt: epoch.addingTimeInterval(second),
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracyMeters: accuracy,
            isSimulatedBySoftware: simulated,
            isProducedByAccessory: accessory
        )
    }

    static func workout(
        startedAt: TimeInterval = 30,
        endedAt: TimeInterval = 90,
        activityType: String = "running",
        provenance: MetricProvenance = .device,
        sourceBundleId: String? = "com.apple.health"
    ) -> WorkoutInterval {
        WorkoutInterval(
            id: workoutId,
            startedAt: epoch.addingTimeInterval(startedAt),
            endedAt: epoch.addingTimeInterval(endedAt),
            activityType: activityType,
            provenance: provenance,
            sourceBundleId: sourceBundleId
        )
    }

    @Test("inside samples at exact dwell and overlap thresholds pass")
    func exactThresholdsPass() throws {
        let assessment = try GeofenceCheckInEvaluator.assess(
            configuration: Self.configuration(),
            locations: [
                Self.location(second: 0),
                Self.location(second: 60),
                Self.location(second: 120),
            ],
            workout: Self.workout()
        )

        #expect(assessment.locationValidations.map(\.outcome) == [
            .inside, .inside, .inside,
        ])
        #expect(assessment.dwellSegments == [
            CreditedDwellSegment(
                startedAt: Self.epoch,
                endedAt: Self.epoch.addingTimeInterval(120)
            ),
        ])
        #expect(assessment.creditedDwellDuration == 120)
        #expect(assessment.meetsMinimumDwell)
        #expect(assessment.workoutOverlap.overlapDuration == 60)
        #expect(assessment.workoutOverlap.overlapFraction == 1)
        #expect(assessment.workoutOverlap.meetsMinimumOverlap)
        #expect(assessment.isLocallyValid)
    }

    @Test("the geofence and accuracy boundaries are inclusive")
    func inclusiveLocationBoundaries() throws {
        let boundaryLongitude = 0.001
        let radius = GeofenceCheckInEvaluator.distanceMeters(
            fromLatitude: 0,
            longitude: 0,
            toLatitude: 0,
            longitude: boundaryLongitude
        )
        let configuration = try Self.configuration(
            latitude: 0,
            longitude: 0,
            radiusMeters: radius,
            maximumAccuracy: 10,
            minimumDwell: 60
        )
        let locations = [
            CheckInLocationSample(
                observedAt: Self.epoch,
                latitude: 0,
                longitude: boundaryLongitude,
                horizontalAccuracyMeters: 10
            ),
            CheckInLocationSample(
                observedAt: Self.epoch.addingTimeInterval(60),
                latitude: 0,
                longitude: boundaryLongitude,
                horizontalAccuracyMeters: 10
            ),
        ]

        let assessment = try GeofenceCheckInEvaluator.assess(
            configuration: configuration,
            locations: locations,
            workout: Self.workout(startedAt: 0, endedAt: 60)
        )

        #expect(assessment.locationValidations.allSatisfy {
            $0.outcome == .inside
        })
        #expect(assessment.meetsMinimumDwell)
        #expect(assessment.workoutOverlap.meetsMinimumOverlap)
    }

    @Test("outside, simulated, and low-accuracy samples remain distinct")
    func failedLocationOutcomesAreExplicit() throws {
        let assessment = try GeofenceCheckInEvaluator.assess(
            configuration: Self.configuration(minimumDwell: 1),
            locations: [
                Self.location(second: 0, longitude: -86.99),
                Self.location(second: 60, simulated: true),
                Self.location(second: 120, accuracy: 10.01),
                Self.location(second: 180, accessory: true),
            ],
            workout: Self.workout(startedAt: 0, endedAt: 240)
        )

        #expect(assessment.locationValidations.map(\.outcome) == [
            .outside,
            .simulated,
            .lowAccuracy,
            .inside,
        ])
        #expect(assessment.locationValidations.last?.sample.isProducedByAccessory == true)
        #expect(assessment.dwellSegments.isEmpty)
    }

    @Test("locally knowable server refusals cannot preview as valid")
    func simulatedAndUntrustedEvidenceAreNotLocallyValid() throws {
        let locations = [
            Self.location(second: -60, simulated: true),
            Self.location(second: 0),
            Self.location(second: 60),
            Self.location(second: 120),
        ]
        let simulated = try GeofenceCheckInEvaluator.assess(
            configuration: Self.configuration(),
            locations: locations,
            workout: Self.workout()
        )
        #expect(simulated.meetsMinimumDwell)
        #expect(simulated.workoutOverlap.meetsMinimumOverlap)
        #expect(!simulated.isLocallyValid)

        let manual = try GeofenceCheckInEvaluator.assess(
            configuration: Self.configuration(),
            locations: Array(locations.dropFirst()),
            workout: Self.workout(provenance: .manual)
        )
        #expect(!manual.workoutIsTrusted)
        #expect(!manual.isLocallyValid)
    }

    @Test("sample order does not change the assessment")
    func unsortedSamplesAreSortedByAbsoluteInstant() throws {
        let ordered = [
            Self.location(second: 0),
            Self.location(second: 60),
            Self.location(second: 120),
        ]
        let first = try GeofenceCheckInEvaluator.assess(
            configuration: Self.configuration(),
            locations: ordered,
            workout: Self.workout()
        )
        let second = try GeofenceCheckInEvaluator.assess(
            configuration: Self.configuration(),
            locations: ordered.reversed(),
            workout: Self.workout()
        )

        #expect(first == second)
        #expect(first.locationValidations.map(\.sample.observedAt) == ordered.map(\.observedAt))
    }

    @Test("gaps above the cap create disjoint credited segments")
    func cappedGapsAreNotCredited() throws {
        let assessment = try GeofenceCheckInEvaluator.assess(
            configuration: Self.configuration(),
            locations: [
                Self.location(second: 240),
                Self.location(second: 60),
                Self.location(second: 180),
                Self.location(second: 0),
            ],
            workout: Self.workout(startedAt: 30, endedAt: 210)
        )

        #expect(assessment.dwellSegments == [
            CreditedDwellSegment(
                startedAt: Self.epoch,
                endedAt: Self.epoch.addingTimeInterval(60)
            ),
            CreditedDwellSegment(
                startedAt: Self.epoch.addingTimeInterval(180),
                endedAt: Self.epoch.addingTimeInterval(240)
            ),
        ])
        #expect(assessment.creditedDwellDuration == 120)
        // 30 seconds in each disjoint segment; the unsampled two-minute gap
        // between them is not laundered into either dwell or workout overlap.
        #expect(assessment.workoutOverlap.overlapDuration == 60)
        #expect(assessment.workoutOverlap.overlapFraction == 1.0 / 3.0)
        #expect(assessment.isLocallyValid)
    }

    @Test("touching half-open endpoints have no workout overlap")
    func touchingWorkoutDoesNotOverlap() throws {
        let assessment = try GeofenceCheckInEvaluator.assess(
            configuration: Self.configuration(minimumWorkoutOverlap: 1),
            locations: [
                Self.location(second: 0),
                Self.location(second: 60),
                Self.location(second: 180),
                Self.location(second: 240),
            ],
            workout: Self.workout(startedAt: 60, endedAt: 180)
        )

        #expect(assessment.dwellSegments.count == 2)
        #expect(assessment.workoutOverlap.overlapDuration == 0)
        #expect(!assessment.workoutOverlap.meetsMinimumOverlap)
    }

    @Test("a workout enveloping dwell counts only the disjoint dwell union")
    func workoutOverlapIsClipped() throws {
        let assessment = try GeofenceCheckInEvaluator.assess(
            configuration: Self.configuration(minimumWorkoutOverlap: 120),
            locations: [
                Self.location(second: 0),
                Self.location(second: 60),
                Self.location(second: 180),
                Self.location(second: 240),
            ],
            workout: Self.workout(startedAt: -60, endedAt: 300)
        )

        #expect(assessment.workoutOverlap.overlapDuration == 120)
        #expect(assessment.workoutOverlap.workoutDuration == 360)
        #expect(assessment.workoutOverlap.overlapFraction == 1.0 / 3.0)
        #expect(assessment.workoutOverlap.meetsMinimumOverlap)
    }

    @Test("fall-back wall times are compared as distinct absolute instants")
    func timezoneDoesNotParticipateInOverlap() throws {
        let firstOneThirty = Self.instant("2026-11-01T01:30:00-04:00")
        let secondOneThirty = Self.instant("2026-11-01T01:30:00-05:00")
        #expect(secondOneThirty.timeIntervalSince(firstOneThirty) == 3600)

        let configuration = try Self.configuration(
            minimumDwell: 3600,
            maximumGap: 3600,
            minimumWorkoutOverlap: 1800
        )
        let locations = [
            CheckInLocationSample(
                observedAt: secondOneThirty,
                latitude: 41,
                longitude: -87,
                horizontalAccuracyMeters: 5
            ),
            CheckInLocationSample(
                observedAt: firstOneThirty,
                latitude: 41,
                longitude: -87,
                horizontalAccuracyMeters: 5
            ),
        ]
        let workout = WorkoutInterval(
            id: Self.workoutId,
            startedAt: Self.instant("2026-11-01T05:45:00Z"),
            endedAt: Self.instant("2026-11-01T06:15:00Z"),
            activityType: "running",
            provenance: .device
        )

        let assessment = try GeofenceCheckInEvaluator.assess(
            configuration: configuration,
            locations: locations,
            workout: workout
        )

        #expect(assessment.creditedDwellDuration == 3600)
        #expect(assessment.workoutOverlap.overlapDuration == 1800)
        #expect(assessment.isLocallyValid)
    }

    @Test("invalid threshold configurations fail at construction")
    func invalidConfigurationIsRejected() {
        #expect(throws: CheckInAssessmentError.self) {
            try Self.configuration(radiusMeters: 0)
        }
        #expect(throws: CheckInAssessmentError.self) {
            try Self.configuration(radiusMeters: 100_001)
        }
        #expect(throws: CheckInAssessmentError.self) {
            try Self.configuration(maximumAccuracy: 0)
        }
        #expect(throws: CheckInAssessmentError.self) {
            try Self.configuration(maximumAccuracy: 100_001)
        }
        #expect(throws: CheckInAssessmentError.self) {
            try Self.configuration(minimumDwell: 0)
        }
        #expect(throws: CheckInAssessmentError.self) {
            try Self.configuration(maximumGap: 3_601)
        }
        #expect(throws: CheckInAssessmentError.self) {
            try Self.configuration(minimumWorkoutOverlap: 0)
        }
        #expect(throws: CheckInAssessmentError.self) {
            try Self.configuration(minimumWorkoutOverlap: 28_801)
        }
    }

    @Test("invalid workout ranges are rejected rather than repaired")
    func invalidWorkoutIsRejected() throws {
        let invalid = Self.workout(startedAt: 90, endedAt: 90)
        #expect(throws: CheckInAssessmentError.self) {
            try GeofenceCheckInEvaluator.assess(
                configuration: Self.configuration(),
                locations: [
                    Self.location(second: 0),
                    Self.location(second: 60),
                ],
                workout: invalid
            )
        }

        let tooLong = Self.workout(startedAt: 0, endedAt: 86_401)
        #expect(throws: CheckInAssessmentError.self) {
            try GeofenceCheckInEvaluator.assess(
                configuration: Self.configuration(),
                locations: [
                    Self.location(second: 0),
                    Self.location(second: 60),
                ],
                workout: tooLong
            )
        }
    }
}

@Suite("Attested check-in payload")
struct AttestedCheckInPayloadTests {
    @Test("fixture body has the exact camel-case wire shape")
    func exactFixtureBytes() throws {
        let payload = AttestedCheckInPayload(
            contestId: GeofenceCheckInTests.contestId,
            geofenceId: GeofenceCheckInTests.geofenceId,
            clientCheckInId: GeofenceCheckInTests.checkInId,
            locations: [
                GeofenceCheckInTests.location(second: 60, accessory: true),
                GeofenceCheckInTests.location(second: 0),
            ],
            workout: GeofenceCheckInTests.workout()
        )

        let encoded = try EncodedCheckInRequest(payload: payload)
        let body = String(decoding: encoded.body, as: UTF8.self)
        let expected = """
        {"clientCheckInId":"c0000001-0000-0000-0000-000000000001","contestId":"a0000001-0000-0000-0000-000000000001","geofenceId":"b0000001-0000-0000-0000-000000000001","locations":[{"horizontalAccuracyMeters":5,"isProducedByAccessory":false,"isSimulatedBySoftware":false,"latitude":41,"longitude":-87,"observedAt":"2026-08-01T15:05:00.000Z"},{"horizontalAccuracyMeters":5,"isProducedByAccessory":true,"isSimulatedBySoftware":false,"latitude":41,"longitude":-87,"observedAt":"2026-08-01T15:06:00.000Z"}],"workout":{"activityType":"running","endedAt":"2026-08-01T15:06:30.000Z","id":"d0000001-0000-0000-0000-000000000001","provenance":"device","sourceBundleId":"com.apple.health","startedAt":"2026-08-01T15:05:30.000Z"}}
        """

        #expect(body == expected)
        #expect(encoded.clientCheckInId == GeofenceCheckInTests.checkInId)
    }

    @Test("location query order does not change signed bytes")
    func deterministicLocationOrder() throws {
        let locations = [
            GeofenceCheckInTests.location(second: 0),
            GeofenceCheckInTests.location(second: 60),
        ]
        let first = try EncodedCheckInRequest(
            payload: AttestedCheckInPayload(
                contestId: GeofenceCheckInTests.contestId,
                geofenceId: GeofenceCheckInTests.geofenceId,
                clientCheckInId: GeofenceCheckInTests.checkInId,
                locations: locations,
                workout: GeofenceCheckInTests.workout()
            )
        )
        let second = try EncodedCheckInRequest(
            payload: AttestedCheckInPayload(
                contestId: GeofenceCheckInTests.contestId,
                geofenceId: GeofenceCheckInTests.geofenceId,
                clientCheckInId: GeofenceCheckInTests.checkInId,
                locations: locations.reversed(),
                workout: GeofenceCheckInTests.workout()
            )
        )

        #expect(first.body == second.body)
    }

    @Test("the endpoint's location count bounds are mirrored")
    func locationCountIsValidated() {
        let oneLocation = AttestedCheckInPayload(
            contestId: GeofenceCheckInTests.contestId,
            geofenceId: GeofenceCheckInTests.geofenceId,
            clientCheckInId: GeofenceCheckInTests.checkInId,
            locations: [GeofenceCheckInTests.location(second: 0)],
            workout: GeofenceCheckInTests.workout()
        )
        #expect(throws: CheckInPayloadEncodingError.self) {
            try EncodedCheckInRequest(payload: oneLocation)
        }

        let tooMany = (0...256).map {
            GeofenceCheckInTests.location(second: TimeInterval($0))
        }
        #expect(throws: CheckInPayloadEncodingError.self) {
            try EncodedCheckInRequest(
                payload: AttestedCheckInPayload(
                    contestId: GeofenceCheckInTests.contestId,
                    geofenceId: GeofenceCheckInTests.geofenceId,
                    clientCheckInId: GeofenceCheckInTests.checkInId,
                    locations: tooMany,
                    workout: GeofenceCheckInTests.workout()
                )
            )
        }
    }

    @Test("duplicate millisecond instants are refused")
    func duplicateTimestampsAreRejected() {
        let payload = AttestedCheckInPayload(
            contestId: GeofenceCheckInTests.contestId,
            geofenceId: GeofenceCheckInTests.geofenceId,
            clientCheckInId: GeofenceCheckInTests.checkInId,
            locations: [
                GeofenceCheckInTests.location(second: 0),
                GeofenceCheckInTests.location(second: 0.000_1),
            ],
            workout: GeofenceCheckInTests.workout()
        )

        #expect(throws: CheckInPayloadEncodingError.self) {
            try EncodedCheckInRequest(payload: payload)
        }
    }

    @Test("invalid location and workout metadata fail before signing")
    func endpointFieldBoundsAreMirrored() {
        let zeroAccuracy = AttestedCheckInPayload(
            contestId: GeofenceCheckInTests.contestId,
            geofenceId: GeofenceCheckInTests.geofenceId,
            clientCheckInId: GeofenceCheckInTests.checkInId,
            locations: [
                GeofenceCheckInTests.location(second: 0, accuracy: 0),
                GeofenceCheckInTests.location(second: 60),
            ],
            workout: GeofenceCheckInTests.workout()
        )
        #expect(throws: CheckInPayloadEncodingError.self) {
            try EncodedCheckInRequest(payload: zeroAccuracy)
        }

        let excessiveAccuracy = AttestedCheckInPayload(
            contestId: GeofenceCheckInTests.contestId,
            geofenceId: GeofenceCheckInTests.geofenceId,
            clientCheckInId: GeofenceCheckInTests.checkInId,
            locations: [
                GeofenceCheckInTests.location(second: 0, accuracy: 100_000.01),
                GeofenceCheckInTests.location(second: 60),
            ],
            workout: GeofenceCheckInTests.workout()
        )
        #expect(throws: CheckInPayloadEncodingError.self) {
            try EncodedCheckInRequest(payload: excessiveAccuracy)
        }

        let excessiveLocationSpan = AttestedCheckInPayload(
            contestId: GeofenceCheckInTests.contestId,
            geofenceId: GeofenceCheckInTests.geofenceId,
            clientCheckInId: GeofenceCheckInTests.checkInId,
            locations: [
                GeofenceCheckInTests.location(second: 0),
                GeofenceCheckInTests.location(second: 28_801),
            ],
            workout: GeofenceCheckInTests.workout()
        )
        #expect(throws: CheckInPayloadEncodingError.self) {
            try EncodedCheckInRequest(payload: excessiveLocationSpan)
        }

        let excessiveWorkout = AttestedCheckInPayload(
            contestId: GeofenceCheckInTests.contestId,
            geofenceId: GeofenceCheckInTests.geofenceId,
            clientCheckInId: GeofenceCheckInTests.checkInId,
            locations: [
                GeofenceCheckInTests.location(second: 0),
                GeofenceCheckInTests.location(second: 60),
            ],
            workout: GeofenceCheckInTests.workout(startedAt: 0, endedAt: 86_401)
        )
        #expect(throws: CheckInPayloadEncodingError.self) {
            try EncodedCheckInRequest(payload: excessiveWorkout)
        }

        let emptyActivity = AttestedCheckInPayload(
            contestId: GeofenceCheckInTests.contestId,
            geofenceId: GeofenceCheckInTests.geofenceId,
            clientCheckInId: GeofenceCheckInTests.checkInId,
            locations: [
                GeofenceCheckInTests.location(second: 0),
                GeofenceCheckInTests.location(second: 60),
            ],
            workout: GeofenceCheckInTests.workout(activityType: "")
        )
        #expect(throws: CheckInPayloadEncodingError.self) {
            try EncodedCheckInRequest(payload: emptyActivity)
        }

        let emptyBundle = AttestedCheckInPayload(
            contestId: GeofenceCheckInTests.contestId,
            geofenceId: GeofenceCheckInTests.geofenceId,
            clientCheckInId: GeofenceCheckInTests.checkInId,
            locations: [
                GeofenceCheckInTests.location(second: 0),
                GeofenceCheckInTests.location(second: 60),
            ],
            workout: GeofenceCheckInTests.workout(sourceBundleId: "")
        )
        #expect(throws: CheckInPayloadEncodingError.self) {
            try EncodedCheckInRequest(payload: emptyBundle)
        }

        let longActivity = AttestedCheckInPayload(
            contestId: GeofenceCheckInTests.contestId,
            geofenceId: GeofenceCheckInTests.geofenceId,
            clientCheckInId: GeofenceCheckInTests.checkInId,
            locations: [
                GeofenceCheckInTests.location(second: 0),
                GeofenceCheckInTests.location(second: 60),
            ],
            workout: GeofenceCheckInTests.workout(
                activityType: String(repeating: "x", count: 101)
            )
        )
        #expect(throws: CheckInPayloadEncodingError.self) {
            try EncodedCheckInRequest(payload: longActivity)
        }
    }
}
