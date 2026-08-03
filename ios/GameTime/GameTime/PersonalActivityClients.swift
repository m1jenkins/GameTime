import Foundation
import GameTimeCore
import Supabase

@MainActor
final class SupabaseTrustedActivityDiagnosticClient:
    TrustedActivityDiagnosticClient
{
    private static let maximumResponseBytes = 64 * 1024

    private let client: SupabaseClient
    private let configuration: AppConfiguration
    private let activity: any ActivityClient
    private let signer: any AppAttestedBodySigning
    private let session: URLSession
    private let now: () -> Date

    init(
        client: SupabaseClient,
        configuration: AppConfiguration,
        activity: any ActivityClient,
        signer: any AppAttestedBodySigning,
        session: URLSession = .shared,
        now: @escaping () -> Date = Date.init
    ) throws {
        guard configuration.environment == .staging else {
            throw PersonalAccountabilityClientError.diagnosticUnavailable
        }
        self.client = client
        self.configuration = configuration
        self.activity = activity
        self.signer = signer
        self.session = session
        self.now = now
    }

    func requestAuthorization() async throws -> ActivityAuthorizationOutcome {
        try await activity.requestStepReadAuthorization()
    }

    func runTrustedDiagnostic(
        ownerID: UUID,
        timezone: String
    ) async throws -> TrustedActivityDiagnostic {
        guard client.auth.currentSession?.user.id == ownerID else {
            throw PersonalAccountabilityClientError.accountChanged
        }
        guard let zone = TimeZone(identifier: timezone) else {
            throw PersonalChallengeValidationError.invalidTimezone
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let queryAsOf = now()
        guard
            let readEnd = calendar.dateInterval(
                of: .hour,
                for: queryAsOf
            )?.start,
            let windowStart = calendar.date(
                byAdding: .hour,
                value: -24,
                to: readEnd
            ),
            windowStart < readEnd
        else {
            throw PersonalAccountabilityClientError.diagnosticUnavailable
        }

        let readStartedAt = now()
        let buckets = try await activity.stepBuckets(
            overlapping: DateInterval(start: windowStart, end: readEnd),
            timeZoneSchedule: ContestTimeZoneSchedule(initialTimeZone: zone),
            asOf: queryAsOf
        )
        let readEndedAt = max(
            now(),
            readStartedAt.addingTimeInterval(0.001)
        )
        let observedAt = max(now(), readEndedAt)
        let trustedBuckets = buckets.filter {
            $0.provenance == .device && $0.value > 0
        }
        let trustedSampleCount = trustedBuckets.reduce(0) {
            $0 + $1.sampleCount
        }
        let clientDiagnosticID = UUID()

        guard trustedSampleCount > 0 else {
            return TrustedActivityDiagnostic(
                id: clientDiagnosticID,
                status: .noPositiveTrustedSample,
                performedAt: readEndedAt,
                trustedQueriedHourCount: trustedBuckets.count,
                positiveTrustedSampleCount: 0,
                clearsEligibilityHold: false
            )
        }

        let body = try DiagnosticRequestBody.encode(
            clientDiagnosticID: clientDiagnosticID,
            observedAt: observedAt,
            healthKitReadStartedAt: readStartedAt,
            healthKitReadEndedAt: readEndedAt,
            trustedDeviceSampleCount: trustedSampleCount
        )
        let signed = try await signer.sign(ownerID: ownerID, body: body)
        guard
            let liveSession = client.auth.currentSession,
            liveSession.user.id == ownerID
        else {
            throw PersonalAccountabilityClientError.accountChanged
        }

        var request = URLRequest(url: try endpointURL())
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            configuration.supabasePublishableKey,
            forHTTPHeaderField: "apikey"
        )
        request.setValue(
            "Bearer \(liveSession.accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            signed.keyID,
            forHTTPHeaderField: "x-gametime-key-id"
        )
        request.setValue(
            signed.assertion.base64EncodedString(),
            forHTTPHeaderField: "x-gametime-assertion"
        )

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PersonalAccountabilityClientError.unavailable
        }
        guard
            client.auth.currentSession?.user.id == ownerID,
            let http = response as? HTTPURLResponse
        else {
            throw PersonalAccountabilityClientError.accountChanged
        }
        guard (200...201).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw MetricUploadClientError.uploadVerificationFailed
            }
            throw PersonalAccountabilityClientError.unavailable
        }
        guard data.count <= Self.maximumResponseBytes else {
            throw PersonalAccountabilityClientError.invalidResponse
        }
        let responseBody = try DiagnosticResponse.decode(
            data,
            statusCode: http.statusCode
        )
        return TrustedActivityDiagnostic(
            id: responseBody.diagnosticID,
            status: .trusted,
            performedAt: responseBody.performedAt,
            trustedQueriedHourCount: trustedBuckets.count,
            positiveTrustedSampleCount: trustedSampleCount,
            clearsEligibilityHold: responseBody.clearedHold
        )
    }

    private func endpointURL() throws -> URL {
        guard
            var components = URLComponents(
                url: configuration.supabaseURL,
                resolvingAgainstBaseURL: false
            )
        else {
            throw PersonalAccountabilityClientError.diagnosticUnavailable
        }
        var parts = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        if Array(parts.suffix(2)) != ["functions", "v1"] {
            parts.append(contentsOf: ["functions", "v1"])
        }
        parts.append("activity-diagnostic")
        components.path = "/" + parts.joined(separator: "/")
        components.query = nil
        components.fragment = nil
        guard let url = components.url else {
            throw PersonalAccountabilityClientError.diagnosticUnavailable
        }
        return url
    }
}

private struct DiagnosticRequestBody: Encodable {
    let clientDiagnosticID: UUID
    let observedAt: String
    let healthKitReadStartedAt: String
    let healthKitReadEndedAt: String
    let trustedDeviceSampleCount: Int

    enum CodingKeys: String, CodingKey {
        case clientDiagnosticID = "clientDiagnosticId"
        case observedAt
        case healthKitReadStartedAt
        case healthKitReadEndedAt
        case trustedDeviceSampleCount
    }

    static func encode(
        clientDiagnosticID: UUID,
        observedAt: Date,
        healthKitReadStartedAt: Date,
        healthKitReadEndedAt: Date,
        trustedDeviceSampleCount: Int
    ) throws -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(
            DiagnosticRequestBody(
                clientDiagnosticID: clientDiagnosticID,
                observedAt: formatter.string(from: observedAt),
                healthKitReadStartedAt: formatter.string(
                    from: healthKitReadStartedAt
                ),
                healthKitReadEndedAt: formatter.string(
                    from: healthKitReadEndedAt
                ),
                trustedDeviceSampleCount: trustedDeviceSampleCount
            )
        )
    }
}

struct DiagnosticResponse: Decodable {
    let diagnosticID: UUID
    let performedAt: Date
    let replayed: Bool
    let clearedHold: Bool

    enum CodingKeys: String, CodingKey {
        case diagnosticID = "diagnosticId"
        case performedAt
        case replayed
        case clearedHold
    }

    static func decode(
        _ data: Data,
        statusCode: Int
    ) throws -> DiagnosticResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [
                .withInternetDateTime,
                .withFractionalSeconds,
            ]
            if let date = fractional.date(from: value) {
                return date
            }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid diagnostic timestamp."
            )
        }
        do {
            let response = try decoder.decode(
                DiagnosticResponse.self,
                from: data
            )
            guard
                (statusCode == 200 && response.replayed)
                    || (statusCode == 201 && !response.replayed)
            else {
                throw PersonalAccountabilityClientError.invalidResponse
            }
            return response
        } catch {
            throw PersonalAccountabilityClientError.invalidResponse
        }
    }
}
