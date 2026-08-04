import CryptoKit
import Foundation
import GameTimeCore

@MainActor
final class ConformanceRunner {
    typealias UpdateHandler = @MainActor (ConformanceStepUpdate) -> Void

    private let appAttest: AppAttestProviding
    private let keyStore: KeyIDStoring
    private let httpClient: ConformanceHTTPClient
    private let now: () -> Date

    init(
        appAttest: AppAttestProviding,
        keyStore: KeyIDStoring,
        httpClient: ConformanceHTTPClient,
        now: @escaping () -> Date = Date.init
    ) {
        self.appAttest = appAttest
        self.keyStore = keyStore
        self.httpClient = httpClient
        self.now = now
    }

    func run(
        input: ConformanceInput,
        onUpdate: UpdateHandler
    ) async throws -> ConformanceRunSummary {
        let configuration = try await perform(
            .configuration,
            onUpdate: onUpdate
        ) {
            let configuration = try input.validated()
            return (
                configuration,
                "Using \(configuration.stagingURL.absoluteString) with participant time zone "
                    + configuration.participantTimeZone.identifier + "."
            )
        }

        try await perform(.appAttestAvailability, onUpdate: onUpdate) {
            guard self.appAttest.isSupported else {
                throw ConformanceFailure.appAttestUnsupported
            }
            return ((), "DCAppAttestService reports support on this device.")
        }

        let keyID = try await perform(.key, onUpdate: onUpdate) {
            if let existing = self.keyStore.loadKeyID() {
                return (
                    existing,
                    "Loaded the one persisted key ID unchanged (\(existing.count) characters)."
                )
            }

            let generated = try await self.appAttest.generateKey()
            guard !generated.isEmpty else {
                throw ConformanceFailure.invalidKeyID
            }
            try self.keyStore.saveKeyID(generated)
            return (
                generated,
                "Generated and persisted one key ID unchanged (\(generated.count) characters)."
            )
        }

        let challenge = try await perform(.challenge, onUpdate: onUpdate) {
            let request = try ConformanceRequestFactory.makeRequest(
                endpoint: .challenge,
                configuration: configuration
            )
            let response = try await self.httpClient.send(request)
            try Self.requireSuccess(response, endpoint: .challenge)

            let decoded: AttestChallengeResponse = try Self.decode(
                AttestChallengeResponse.self,
                response: response,
                endpoint: .challenge
            )
            guard let bytes = Data(base64Encoded: decoded.challenge), bytes.count == 32 else {
                throw ConformanceFailure.invalidChallenge
            }
            return (
                bytes,
                "Received \(bytes.count) challenge bytes; expires in "
                    + "\(decoded.expiresInSeconds) seconds."
            )
        }

        try await perform(.registration, onUpdate: onUpdate) {
            let challengeHash = challenge.sha256Digest
            let attestation = try await self.appAttest.attestKey(
                keyID,
                clientDataHash: challengeHash
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let body = try encoder.encode(
                RegistrationRequest(
                    keyId: keyID,
                    attestation: attestation.base64EncodedString()
                )
            )
            let request = try ConformanceRequestFactory.makeRequest(
                endpoint: .registerDevice,
                configuration: configuration,
                body: body
            )
            let response = try await self.httpClient.send(request)
            try Self.requireSuccess(response, endpoint: .registerDevice)
            let decoded: RegistrationResponse = try Self.decode(
                RegistrationResponse.self,
                response: response,
                endpoint: .registerDevice
            )
            guard decoded.registered else {
                throw ConformanceFailure.invalidResponse(
                    "attest-device returned registered=false"
                )
            }
            guard decoded.environment == "development" else {
                throw ConformanceFailure.invalidResponse(
                    "attest-device returned environment=\(decoded.environment), expected development"
                )
            }
            let validationCategory = decoded.validationCategory.map { String($0) }
                ?? "not supplied by attestation"
            let bundleVersion = decoded.bundleVersion ?? "not supplied by attestation"
            return (
                (),
                "SHA-256(challenge)=\(challengeHash.hexString); server accepted a "
                    + "\(decoded.environment) attestation (validation category "
                    + "\(validationCategory), bundle version "
                    + "\(bundleVersion)). The generated key ID was sent verbatim."
            )
        }

        let runDate = now()
        let encodedMetric = try await perform(.metricEncoding, onUpdate: onUpdate) {
            let bucketStart = try Self.previousCompletedHour(
                before: runDate,
                in: configuration.participantTimeZone
            )
            let payload = AttestedMetricPayload(
                contestId: configuration.contestID,
                clientBatchId: UUID(),
                observedAt: runDate,
                observations: [
                    HourlyBucket(
                        metric: .steps,
                        bucketStart: bucketStart,
                        provenance: .device,
                        value: 1,
                        sampleCount: 1,
                        sourceBundleIdentifier: "com.apple.health",
                        deviceModel: "M6.5 Conformance"
                    ),
                ]
            )
            let encoded = try EncodedMetricRequest(payload: payload)
            return (
                encoded,
                "\(encoded.body.count) exact GameTimeCore bytes; "
                    + "SHA-256=\(encoded.body.sha256Digest.hexString)."
            )
        }

        let signedMetric = try await perform(.metricAssertion, onUpdate: onUpdate) {
            let material = try await self.sign(body: encodedMetric.body, keyID: keyID)
            guard material.counter > 0 else {
                throw ConformanceFailure.assertionCounter(
                    "the first metric assertion counter must be greater than zero"
                )
            }
            return (
                material,
                "Local assertion counter \(material.counter); assertion "
                    + "SHA-256=\(material.assertion.sha256Digest.hexString)."
            )
        }

        let metricSubmission = try await perform(.metricSubmission, onUpdate: onUpdate) {
            let request = try signedMetric.makeRequest(
                endpoint: .ingestMetrics,
                configuration: configuration
            )
            let expectedAssertionHeader = signedMetric.assertion.base64EncodedString()
            guard request.httpBody == encodedMetric.body,
                  request.value(forHTTPHeaderField: "x-gametime-key-id") == keyID,
                  request.value(forHTTPHeaderField: "x-gametime-assertion")
                    == expectedAssertionHeader
            else {
                throw ConformanceFailure.replayMismatch(
                    "the metric request did not retain its exact body, key ID, and assertion"
                )
            }
            let response = try await self.httpClient.send(request)
            try Self.requireSuccess(response, endpoint: .ingestMetrics)
            let decoded: MetricIngestResponse = try Self.decode(
                MetricIngestResponse.self,
                response: response,
                endpoint: .ingestMetrics
            )
            guard response.statusCode == 201 else {
                throw ConformanceFailure.invalidResponse(
                    "first ingest-metrics response was HTTP \(response.statusCode), expected 201"
                )
            }
            guard !decoded.replayed else {
                throw ConformanceFailure.invalidResponse(
                    "first ingest-metrics response returned replayed=true"
                )
            }
            guard decoded.observationCount == 1 else {
                throw ConformanceFailure.invalidResponse(
                    "first ingest-metrics response recorded \(decoded.observationCount) "
                        + "observations, expected 1"
                )
            }
            return (
                (decoded, request),
                "HTTP \(response.statusCode); batch \(decoded.batchId.uuidString.lowercased()), "
                    + "\(decoded.observationCount) observation, replayed=\(decoded.replayed)."
            )
        }

        try await perform(.metricReplay, onUpdate: onUpdate) {
            let firstMetric = metricSubmission.0
            let metricRequest = metricSubmission.1
            let expectedAssertionHeader = signedMetric.assertion.base64EncodedString()

            // Send the same URLRequest value before generating another
            // assertion. No body encoding or signing occurs between attempts.
            guard metricRequest.httpBody == signedMetric.body,
                  metricRequest.value(forHTTPHeaderField: "x-gametime-key-id") == keyID,
                  metricRequest.value(forHTTPHeaderField: "x-gametime-assertion")
                    == expectedAssertionHeader
            else {
                throw ConformanceFailure.replayMismatch(
                    "metric body, key ID, or assertion changed before the second transmission"
                )
            }

            let response = try await self.httpClient.send(metricRequest)
            guard response.statusCode == 200 else {
                throw ConformanceFailure.replayMismatch(
                    "identical metric request returned HTTP \(response.statusCode), expected 200"
                )
            }
            let decoded: MetricIngestResponse = try Self.decode(
                MetricIngestResponse.self,
                response: response,
                endpoint: .ingestMetrics
            )
            guard decoded.replayed else {
                throw ConformanceFailure.replayMismatch(
                    "server returned replayed=false for the identical metric request"
                )
            }
            guard decoded.batchId == firstMetric.batchId else {
                throw ConformanceFailure.replayMismatch(
                    "server returned a different batch ID for the identical metric request"
                )
            }
            return (
                (),
                "HTTP 200; replayed=true for batch "
                    + "\(decoded.batchId.uuidString.lowercased()) using the same body bytes, "
                    + "assertion bytes, and counter \(signedMetric.counter)."
            )
        }

        let encodedCheckIn = try await perform(.checkInEncoding, onUpdate: onUpdate) {
            let locations = [-181.0, -121.0, -61.0, -1.0].map { offset in
                CheckInLocationSample(
                    observedAt: runDate.addingTimeInterval(offset),
                    latitude: configuration.latitude,
                    longitude: configuration.longitude,
                    horizontalAccuracyMeters: 5
                )
            }
            let workout = WorkoutInterval(
                id: UUID(),
                startedAt: runDate.addingTimeInterval(-211),
                endedAt: runDate.addingTimeInterval(-1),
                activityType: "walking",
                provenance: .device,
                sourceBundleId: "com.apple.Health"
            )
            let payload = AttestedCheckInPayload(
                contestId: configuration.contestID,
                geofenceId: configuration.geofenceID,
                clientCheckInId: UUID(),
                locations: locations,
                workout: workout
            )
            let encoded = try EncodedCheckInRequest(payload: payload)
            return (
                encoded,
                "\(encoded.body.count) exact GameTimeCore bytes; "
                    + "SHA-256=\(encoded.body.sha256Digest.hexString)."
            )
        }

        let signedCheckIn = try await perform(.checkInAssertion, onUpdate: onUpdate) {
            let material = try await self.sign(body: encodedCheckIn.body, keyID: keyID)
            guard material.counter > signedMetric.counter else {
                throw ConformanceFailure.assertionCounter(
                    "check-in counter \(material.counter) must be strictly greater than "
                        + "metric counter \(signedMetric.counter)"
                )
            }
            return (
                material,
                "Local assertion counter \(material.counter), advanced from metric counter "
                    + "\(signedMetric.counter); assertion "
                    + "SHA-256=\(material.assertion.sha256Digest.hexString)."
            )
        }

        let checkInRequest = try signedCheckIn.makeRequest(
            endpoint: .ingestCheckIn,
            configuration: configuration
        )
        guard checkInRequest.httpBody == encodedCheckIn.body else {
            throw ConformanceFailure.replayMismatch(
                "the check-in request did not retain EncodedCheckInRequest.body"
            )
        }
        let expectedAssertionHeader = signedCheckIn.assertion.base64EncodedString()
        guard checkInRequest.value(forHTTPHeaderField: "x-gametime-key-id") == keyID,
              checkInRequest.value(forHTTPHeaderField: "x-gametime-assertion")
                == expectedAssertionHeader
        else {
            throw ConformanceFailure.replayMismatch(
                "the check-in request headers did not retain the key ID and assertion"
            )
        }

        let firstCheckIn = try await perform(.checkInSubmission, onUpdate: onUpdate) {
            let response = try await self.httpClient.send(checkInRequest)
            try Self.requireSuccess(response, endpoint: .ingestCheckIn)
            let decoded: CheckInIngestResponse = try Self.decode(
                CheckInIngestResponse.self,
                response: response,
                endpoint: .ingestCheckIn
            )
            guard response.statusCode == 201 else {
                throw ConformanceFailure.invalidResponse(
                    "first ingest-checkin response was HTTP \(response.statusCode), expected 201"
                )
            }
            guard !decoded.replayed else {
                throw ConformanceFailure.invalidResponse(
                    "first ingest-checkin response returned replayed=true"
                )
            }
            guard decoded.outcome == "accepted" else {
                throw ConformanceFailure.invalidResponse(
                    "fixture check-in outcome was \(decoded.outcome), expected accepted"
                )
            }
            return (
                decoded,
                "HTTP \(response.statusCode); check-in "
                    + "\(decoded.checkInId.uuidString.lowercased()), outcome=\(decoded.outcome), "
                    + "dwell=\(decoded.dwellSeconds)s, overlap="
                    + "\(decoded.workoutOverlapSeconds)s, replayed=\(decoded.replayed)."
            )
        }

        try await perform(.checkInReplay, onUpdate: onUpdate) {
            // Send the same URLRequest value. No body encoding and no assertion
            // generation happens between the first attempt and this replay.
            guard checkInRequest.httpBody == signedCheckIn.body,
                  checkInRequest.value(forHTTPHeaderField: "x-gametime-key-id") == keyID,
                  checkInRequest.value(forHTTPHeaderField: "x-gametime-assertion")
                    == expectedAssertionHeader
            else {
                throw ConformanceFailure.replayMismatch(
                    "check-in body, key ID, or assertion changed before the second transmission"
                )
            }

            let response = try await self.httpClient.send(checkInRequest)
            guard response.statusCode == 200 else {
                throw ConformanceFailure.replayMismatch(
                    "identical check-in request returned HTTP \(response.statusCode), expected 200"
                )
            }
            let decoded: CheckInIngestResponse = try Self.decode(
                CheckInIngestResponse.self,
                response: response,
                endpoint: .ingestCheckIn
            )
            guard decoded.replayed else {
                throw ConformanceFailure.replayMismatch(
                    "server returned replayed=false for the identical request"
                )
            }
            guard decoded.checkInId == firstCheckIn.checkInId else {
                throw ConformanceFailure.replayMismatch(
                    "server returned a different check-in ID for the identical request"
                )
            }
            return (
                (),
                "HTTP 200; replayed=true for the same body bytes, "
                    + "same assertion bytes, and counter \(signedCheckIn.counter)."
            )
        }

        return ConformanceRunSummary(
            keyID: keyID,
            metricCounter: signedMetric.counter,
            checkInCounter: signedCheckIn.counter,
            metricBody: String(decoding: encodedMetric.body, as: UTF8.self),
            checkInBody: String(decoding: encodedCheckIn.body, as: UTF8.self),
            metricReplayConfirmed: true,
            checkInReplayConfirmed: true
        )
    }

    private func sign(body: Data, keyID: String) async throws -> SignedRequestMaterial {
        let assertion = try await appAttest.generateAssertion(
            keyID,
            clientDataHash: body.sha256Digest
        )
        let counter: UInt32
        do {
            counter = try AssertionCounterDecoder.decode(from: assertion)
        } catch {
            throw ConformanceFailure.assertionCounter(error.localizedDescription)
        }
        return SignedRequestMaterial(
            keyID: keyID,
            body: body,
            assertion: assertion,
            counter: counter
        )
    }

    private func perform<Value>(
        _ step: ConformanceStep,
        onUpdate: UpdateHandler,
        operation: () async throws -> (Value, String)
    ) async throws -> Value {
        onUpdate(
            ConformanceStepUpdate(step: step, state: .running, detail: "Running…")
        )
        do {
            let (value, detail) = try await operation()
            onUpdate(
                ConformanceStepUpdate(step: step, state: .succeeded, detail: detail)
            )
            return value
        } catch {
            onUpdate(
                ConformanceStepUpdate(
                    step: step,
                    state: .failed,
                    detail: error.localizedDescription
                )
            )
            throw error
        }
    }

    private static func previousCompletedHour(
        before date: Date,
        in timeZone: TimeZone
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let currentHour = calendar.dateInterval(of: .hour, for: date)?.start,
              let previousHour = calendar.date(
                byAdding: .hour,
                value: -1,
                to: currentHour
              )
        else {
            throw ConformanceFailure.configuration(
                "A completed participant-local hour could not be constructed."
            )
        }
        return previousHour
    }

    private static func requireSuccess(
        _ response: ConformanceHTTPResponse,
        endpoint: ConformanceEndpoint
    ) throws {
        guard (200..<300).contains(response.statusCode) else {
            throw ConformanceFailure.http(
                endpoint: endpoint.label,
                status: response.statusCode,
                body: String(response.bodyText.prefix(4_096))
            )
        }
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        response: ConformanceHTTPResponse,
        endpoint: ConformanceEndpoint
    ) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: response.body)
        } catch {
            throw ConformanceFailure.invalidResponse(
                "\(endpoint.label): \(error.localizedDescription); "
                    + String(response.bodyText.prefix(2_048))
            )
        }
    }
}

private struct RegistrationRequest: Encodable {
    let keyId: String
    let attestation: String
}

private extension Data {
    var sha256Digest: Data {
        Data(SHA256.hash(data: self))
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
