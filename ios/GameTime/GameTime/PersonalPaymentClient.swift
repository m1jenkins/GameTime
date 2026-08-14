import Foundation

/// Provider-neutral information the UI needs to present payment setup.
///
/// Stripe SDK values stop at the view boundary. The accountability store and
/// the persisted retry record only know an opaque GameTime setup identifier.
enum PersonalPaymentSetupPresentation: Equatable, Sendable {
    case paymentSheet(
        publishableKey: String,
        setupIntentClientSecret: String
    )
    case alreadyConfirmed
}

struct PersonalPaymentSetup: Equatable, Sendable {
    let setupID: String
    let presentation: PersonalPaymentSetupPresentation
}

enum PersonalPaymentState: String, Codable, CaseIterable, Equatable, Sendable {
    case methodSaved = "method_saved"
    case reviewOpen = "review_open"
    case underReview = "under_review"
    case waived
    case noCharge = "no_charge"
    case chargePending = "charge_pending"
    case charged
    case requiresAction = "requires_action"
    case collectionFailed = "collection_failed"
}

/// Provider-neutral, server-confirmed settlement state for one challenge.
///
/// No Stripe identifiers are represented here. Callers may retain this value
/// as the last confirmed status, but its freshness remains a UI/store concern.
struct PersonalPaymentStatus: Equatable, Sendable {
    let challengeID: UUID
    let state: PersonalPaymentState
    let reviewDeadline: Date?
}

enum PersonalReviewReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case userDisputesStepData = "user_disputes_step_data"
    case userDisputesResult = "user_disputes_result"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .userDisputesStepData:
            "My step data is wrong or incomplete"
        case .userDisputesResult:
            "I disagree with the result"
        }
    }
}

enum PersonalReviewState: String, Codable, Equatable, Sendable {
    case underReview = "under_review"
}

struct PersonalReviewRequestResult: Equatable, Sendable {
    let state: PersonalReviewState
    let reviewDeadline: Date
    let replayed: Bool
}

@MainActor
protocol PersonalPaymentClient: AnyObject {
    func prepare(
        _ request: PersonalChallengeCreationRequest,
        expectedUserID: UUID
    ) async throws -> PersonalPaymentSetup

    func commit(
        _ request: PersonalChallengeCreationRequest,
        setupID: String,
        expectedUserID: UUID
    ) async throws -> UUID

    func requestReview(
        challengeID: UUID,
        reason: PersonalReviewReason,
        expectedUserID: UUID
    ) async throws -> PersonalReviewRequestResult

    func paymentStatus(
        challengeID: UUID,
        expectedUserID: UUID
    ) async throws -> PersonalPaymentStatus
}

enum PersonalPaymentClientError: LocalizedError, Equatable, Sendable {
    case disabled
    case authenticationRequired
    case accountChanged
    case unavailable
    case invalidResponse
    case setupNotConfirmed
    case termsChanged
    case reviewWindowClosed

    var errorDescription: String? {
        switch self {
        case .disabled:
            "Test payments aren’t enabled in this copy of GameTime."
        case .authenticationRequired:
            "Sign in again before setting up your test payment."
        case .accountChanged:
            "You signed in with a different account. Try again."
        case .unavailable:
            "We couldn’t reach GameTime right now. Try again when you’re ready."
        case .invalidResponse:
            "GameTime couldn’t safely prepare that test payment. Try again."
        case .setupNotConfirmed:
            "Finish saving your test payment method before starting the challenge."
        case .termsChanged:
            "Your challenge details changed. Set up the test payment again."
        case .reviewWindowClosed:
            "The review window for this result has ended."
        }
    }
}

@MainActor
final class DisabledPersonalPaymentClient: PersonalPaymentClient {
    func prepare(
        _ request: PersonalChallengeCreationRequest,
        expectedUserID: UUID
    ) async throws -> PersonalPaymentSetup {
        _ = (request, expectedUserID)
        throw PersonalPaymentClientError.disabled
    }

    func commit(
        _ request: PersonalChallengeCreationRequest,
        setupID: String,
        expectedUserID: UUID
    ) async throws -> UUID {
        _ = (request, setupID, expectedUserID)
        throw PersonalPaymentClientError.disabled
    }

    func requestReview(
        challengeID: UUID,
        reason: PersonalReviewReason,
        expectedUserID: UUID
    ) async throws -> PersonalReviewRequestResult {
        _ = (challengeID, reason, expectedUserID)
        throw PersonalPaymentClientError.disabled
    }

    func paymentStatus(
        challengeID: UUID,
        expectedUserID: UUID
    ) async throws -> PersonalPaymentStatus {
        _ = (challengeID, expectedUserID)
        throw PersonalPaymentClientError.disabled
    }
}
