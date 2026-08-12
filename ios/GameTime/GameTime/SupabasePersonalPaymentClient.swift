import Foundation
import Supabase

/// Native Edge Function adapter for the Stripe sandbox.
///
/// Keep the endpoint names and JSON documents private to this file so a
/// backend contract adjustment cannot leak Stripe concepts into the domain or
/// challenge store.
@MainActor
final class SupabasePersonalPaymentClient: PersonalPaymentClient {
    private static let maximumResponseBytes = 32 * 1024
    private static let setupEndpoint = "personal-payment-setup"
    private static let commitEndpoint = "personal-challenge-commit"
    private static let reviewEndpoint = "personal-stripe-sandbox-review"

    private let client: SupabaseClient
    private let configuration: AppConfiguration
    private let session: URLSession

    init(
        client: SupabaseClient,
        configuration: AppConfiguration,
        session: URLSession = .shared
    ) {
        self.client = client
        self.configuration = configuration
        self.session = session
    }

    func prepare(
        _ request: PersonalChallengeCreationRequest,
        expectedUserID: UUID
    ) async throws -> PersonalPaymentSetup {
        let document = try await send(
            TermsDocument(request: request),
            to: Self.setupEndpoint,
            expectedUserID: expectedUserID
        )
        let response: SetupResponse = try decode(document.data)
        guard
            UUID(uuidString: response.setupID) != nil,
            response.publishableKey.hasPrefix("pk_test_"),
            response.setupIntentClientSecret.hasPrefix("seti_"),
            response.setupIntentClientSecret.contains("_secret_")
        else {
            throw PersonalPaymentClientError.invalidResponse
        }

        let presentation: PersonalPaymentSetupPresentation =
            response.status == .succeeded
                ? .alreadyConfirmed
                : .paymentSheet(
                    publishableKey: response.publishableKey,
                    setupIntentClientSecret:
                        response.setupIntentClientSecret
                )
        return PersonalPaymentSetup(
            setupID: response.setupID.lowercased(),
            presentation: presentation
        )
    }

    func commit(
        _ request: PersonalChallengeCreationRequest,
        setupID: String,
        expectedUserID: UUID
    ) async throws -> UUID {
        guard UUID(uuidString: setupID) != nil else {
            throw PersonalPaymentClientError.invalidResponse
        }
        let document = try await send(
            CommitDocument(request: request, setupID: setupID),
            to: Self.commitEndpoint,
            expectedUserID: expectedUserID
        )
        let response: CommitResponse = try decode(document.data)
        guard response.paymentState == "method_saved" else {
            throw PersonalPaymentClientError.invalidResponse
        }
        return response.challengeID
    }

    func requestReview(
        challengeID: UUID,
        reason: PersonalReviewReason,
        expectedUserID: UUID
    ) async throws -> PersonalReviewRequestResult {
        let document = try await send(
            ReviewDocument(challengeID: challengeID, reasonCode: reason),
            to: Self.reviewEndpoint,
            expectedUserID: expectedUserID
        )
        let response: ReviewResponse = try decode(document.data)
        guard
            response.reviewState == .underReview,
            let deadline = Self.reviewDate(from: response.reviewDeadline)
        else {
            throw PersonalPaymentClientError.invalidResponse
        }
        return PersonalReviewRequestResult(
            state: response.reviewState,
            reviewDeadline: deadline,
            replayed: response.replayed
        )
    }

    private func send<Body: Encodable>(
        _ body: Body,
        to endpoint: String,
        expectedUserID: UUID
    ) async throws -> (data: Data, statusCode: Int) {
        guard configuration.personalSettlementMode == .stripeSandbox else {
            throw PersonalPaymentClientError.disabled
        }
        guard let liveSession = try await client.validSession() else {
            throw PersonalPaymentClientError.authenticationRequired
        }
        guard liveSession.user.id == expectedUserID else {
            throw PersonalPaymentClientError.accountChanged
        }

        var request = URLRequest(url: try endpointURL(named: endpoint))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            configuration.supabasePublishableKey,
            forHTTPHeaderField: "apikey"
        )
        request.setValue(
            "Bearer \(liveSession.accessToken)",
            forHTTPHeaderField: "Authorization"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PersonalPaymentClientError.unavailable
        }
        guard client.auth.currentSession?.user.id == expectedUserID else {
            throw PersonalPaymentClientError.accountChanged
        }
        guard
            let http = response as? HTTPURLResponse,
            data.count <= Self.maximumResponseBytes
        else {
            throw PersonalPaymentClientError.invalidResponse
        }
        guard (200...201).contains(http.statusCode) else {
            throw mapRefusal(statusCode: http.statusCode, data: data)
        }
        return (data, http.statusCode)
    }

    private func endpointURL(named endpoint: String) throws -> URL {
        guard
            var components = URLComponents(
                url: configuration.supabaseURL,
                resolvingAgainstBaseURL: false
            )
        else {
            throw PersonalPaymentClientError.invalidResponse
        }
        var parts = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        if Array(parts.suffix(2)) != ["functions", "v1"] {
            parts.append(contentsOf: ["functions", "v1"])
        }
        parts.append(endpoint)
        components.path = "/" + parts.joined(separator: "/")
        components.query = nil
        components.fragment = nil
        guard let url = components.url else {
            throw PersonalPaymentClientError.invalidResponse
        }
        return url
    }

    private func decode<Value: Decodable>(_ data: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw PersonalPaymentClientError.invalidResponse
        }
    }

    private func mapRefusal(statusCode: Int, data: Data) -> Error {
        let failure = try? JSONDecoder().decode(
            FailureDocument.self,
            from: data
        )
        if statusCode == 401 || statusCode == 403 {
            return PersonalPaymentClientError.authenticationRequired
        }
        if statusCode == 422 {
            if failure?.message.lowercased().contains("review") == true {
                return PersonalPaymentClientError.reviewWindowClosed
            }
            return failure?.message.lowercased().contains("terms") == true
                ? PersonalPaymentClientError.termsChanged
                : PersonalPaymentClientError.setupNotConfirmed
        }
        if statusCode >= 500 {
            return PersonalPaymentClientError.unavailable
        }
        return PersonalPaymentClientError.invalidResponse
    }

    private static func reviewDate(from value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        if let date = fractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }
}

struct PersonalPaymentTermsDocument: Encodable {
    static let agreementVersion = "personal-stripe-sandbox-v1"
    static let consentVersion = "personal-stripe-sandbox-consent-v1"
    static let stepDataPolicy = "healthkit_nonmanual_daily_v1"

    let requestID: UUID
    let cadence: PersonalChallengeCadence
    let targetSteps: Int
    let commitmentAmountMinor: Int
    let currency = "USD"
    let timezone: String
    let requestedStartsAt: String?
    let agreementVersion = Self.agreementVersion
    let consentVersion = Self.consentVersion
    let consentAccepted = true
    let stepDataPolicy = Self.stepDataPolicy

    init(request: PersonalChallengeCreationRequest) {
        requestID = request.requestID
        cadence = request.cadence
        targetSteps = request.targetSteps
        commitmentAmountMinor = request.commitmentAmountMinor
        timezone = request.timezone
        requestedStartsAt = request.startsAt?.formatted(.iso8601)
    }

    enum CodingKeys: String, CodingKey {
        case requestID = "requestId"
        case cadence
        case targetSteps
        case commitmentAmountMinor
        case currency
        case timezone
        case requestedStartsAt
        case agreementVersion
        case consentVersion
        case consentAccepted
        case stepDataPolicy
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(cadence, forKey: .cadence)
        try container.encode(targetSteps, forKey: .targetSteps)
        try container.encode(
            commitmentAmountMinor,
            forKey: .commitmentAmountMinor
        )
        try container.encode(currency, forKey: .currency)
        try container.encode(timezone, forKey: .timezone)
        try container.encode(agreementVersion, forKey: .agreementVersion)
        try container.encode(consentVersion, forKey: .consentVersion)
        try container.encode(consentAccepted, forKey: .consentAccepted)
        try container.encode(stepDataPolicy, forKey: .stepDataPolicy)
        try container.encodeIfPresent(
            requestedStartsAt,
            forKey: .requestedStartsAt
        )
    }
}

private struct TermsDocument: Encodable {
    private let terms: PersonalPaymentTermsDocument

    init(request: PersonalChallengeCreationRequest) {
        terms = PersonalPaymentTermsDocument(request: request)
    }

    func encode(to encoder: any Encoder) throws {
        try terms.encode(to: encoder)
    }
}

private struct CommitDocument: Encodable {
    private let terms: PersonalPaymentTermsDocument
    let setupID: String

    init(request: PersonalChallengeCreationRequest, setupID: String) {
        terms = PersonalPaymentTermsDocument(request: request)
        self.setupID = setupID
    }

    enum CodingKeys: String, CodingKey {
        case setupID = "setupId"
    }

    func encode(to encoder: any Encoder) throws {
        try terms.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(setupID, forKey: .setupID)
    }
}

private struct SetupResponse: Decodable {
    enum Status: String, Decodable {
        case pendingProvider = "pending_provider"
        case requiresAction = "requires_action"
        case processing
        case succeeded
        case failed
        case cancelled
    }

    let setupID: String
    let publishableKey: String
    let setupIntentClientSecret: String
    let status: Status

    enum CodingKeys: String, CodingKey {
        case setupID = "setupId"
        case publishableKey
        case setupIntentClientSecret
        case status
    }
}

private struct CommitResponse: Decodable {
    let challengeID: UUID
    let paymentState: String

    enum CodingKeys: String, CodingKey {
        case challengeID = "challengeId"
        case paymentState
    }
}

private struct ReviewDocument: Encodable {
    let challengeID: UUID
    let reasonCode: PersonalReviewReason

    enum CodingKeys: String, CodingKey {
        case challengeID = "challengeId"
        case reasonCode
    }
}

private struct ReviewResponse: Decodable {
    let reviewState: PersonalReviewState
    let reviewDeadline: String
    let replayed: Bool
}

private struct FailureDocument: Decodable {
    let message: String
}
