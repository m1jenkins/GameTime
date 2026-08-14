import Supabase
import XCTest

@testable import GameTime

@MainActor
final class SupabasePersonalPaymentClientTests: XCTestCase {
    private let ownerID = UUID(
        uuidString: "11111111-1111-1111-1111-111111111111"
    )!
    private let otherOwnerID = UUID(
        uuidString: "22222222-2222-2222-2222-222222222222"
    )!
    private let challengeID = UUID(
        uuidString: "33333333-3333-3333-3333-333333333333"
    )!

    func testPaymentStatusDecodesEveryKnownState() async throws {
        for state in PersonalPaymentState.allCases {
            let deadline = state == .reviewOpen
                ? "2026-08-20T19:30:00Z"
                : nil
            let rpc = PaymentStatusRPCStub(
                responseData: try statusData(
                    state: state.rawValue,
                    reviewDeadline: deadline,
                    providerFields: [
                        "setup_id": "not-a-provider-id-the-domain-can-expose",
                        "charge_status": "succeeded",
                    ]
                )
            )
            let client = makeClient(rpc: rpc)

            let status = try await client.paymentStatus(
                challengeID: challengeID,
                expectedUserID: ownerID
            )

            XCTAssertEqual(status.challengeID, challengeID)
            XCTAssertEqual(status.state, state)
            XCTAssertEqual(status.reviewDeadline != nil, state == .reviewOpen)
        }
    }

    func testPaymentStatusAcceptsSupportedISODatesAndOptionalDeadline()
        async throws
    {
        let standardRPC = PaymentStatusRPCStub(
            responseData: try statusData(
                state: PersonalPaymentState.reviewOpen.rawValue,
                reviewDeadline: "2026-08-20T19:30:00Z"
            )
        )
        let standard = try await makeClient(rpc: standardRPC).paymentStatus(
            challengeID: challengeID,
            expectedUserID: ownerID
        )
        XCTAssertEqual(
            standard.reviewDeadline,
            ISO8601DateFormatter().date(from: "2026-08-20T19:30:00Z")
        )

        let fractionalRPC = PaymentStatusRPCStub(
            responseData: try statusData(
                state: PersonalPaymentState.underReview.rawValue,
                reviewDeadline: "2026-08-20T19:30:00.125Z"
            )
        )
        let fractional = try await makeClient(rpc: fractionalRPC)
            .paymentStatus(
                challengeID: challengeID,
                expectedUserID: ownerID
            )
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        XCTAssertEqual(
            fractional.reviewDeadline,
            fractionalFormatter.date(from: "2026-08-20T19:30:00.125Z")
        )

        let absentRPC = PaymentStatusRPCStub(
            responseData: try statusData(
                state: PersonalPaymentState.charged.rawValue,
                providerFields: ["review_deadline": NSNull()]
            )
        )
        let absent = try await makeClient(rpc: absentRPC).paymentStatus(
            challengeID: challengeID,
            expectedUserID: ownerID
        )
        XCTAssertNil(absent.reviewDeadline)
    }

    func testPaymentStatusRejectsUnknownState() async throws {
        let rpc = PaymentStatusRPCStub(
            responseData: try statusData(state: "future_provider_state")
        )
        let client = makeClient(rpc: rpc)

        await assertPaymentError(.invalidResponse) {
            _ = try await client.paymentStatus(
                challengeID: self.challengeID,
                expectedUserID: self.ownerID
            )
        }
    }

    func testPaymentStatusRejectsOversizeAndMalformedResponses() async throws {
        var oversized = try statusData(
            state: PersonalPaymentState.charged.rawValue
        )
        oversized.append(
            Data(
                repeating: 0x20,
                count: 32 * 1024
            )
        )

        for data in [oversized, Data("{".utf8), Data()] {
            let client = makeClient(
                rpc: PaymentStatusRPCStub(responseData: data)
            )
            await assertPaymentError(.invalidResponse) {
                _ = try await client.paymentStatus(
                    challengeID: self.challengeID,
                    expectedUserID: self.ownerID
                )
            }
        }
    }

    func testPaymentStatusRejectsChallengeAndEnvironmentMismatch()
        async throws
    {
        let mismatches = [
            try statusData(
                challengeID: UUID(
                    uuidString: "44444444-4444-4444-4444-444444444444"
                )!,
                state: PersonalPaymentState.methodSaved.rawValue
            ),
            try statusData(
                state: PersonalPaymentState.methodSaved.rawValue,
                environment: "production"
            ),
            try statusData(
                state: PersonalPaymentState.methodSaved.rawValue,
                environment: "SANDBOX"
            ),
        ]

        for data in mismatches {
            let client = makeClient(
                rpc: PaymentStatusRPCStub(responseData: data)
            )
            await assertPaymentError(.invalidResponse) {
                _ = try await client.paymentStatus(
                    challengeID: self.challengeID,
                    expectedUserID: self.ownerID
                )
            }
        }
    }

    func testPaymentStatusValidatesReviewDeadline() async throws {
        let invalidDocuments = [
            try statusData(state: PersonalPaymentState.reviewOpen.rawValue),
            try statusData(
                state: PersonalPaymentState.reviewOpen.rawValue,
                reviewDeadline: "not-an-iso-date"
            ),
            try statusData(
                state: PersonalPaymentState.reviewOpen.rawValue,
                providerFields: ["review_deadline": NSNull()]
            ),
            try statusData(
                state: PersonalPaymentState.underReview.rawValue,
                reviewDeadline: "not-an-iso-date"
            ),
        ]

        for data in invalidDocuments {
            let client = makeClient(
                rpc: PaymentStatusRPCStub(responseData: data)
            )
            await assertPaymentError(.invalidResponse) {
                _ = try await client.paymentStatus(
                    challengeID: self.challengeID,
                    expectedUserID: self.ownerID
                )
            }
        }
    }

    func testPaymentStatusUsesExpectedRPCAndParameterName() async throws {
        let rpc = PaymentStatusRPCStub(
            responseData: try statusData(
                state: PersonalPaymentState.methodSaved.rawValue
            )
        )
        let client = makeClient(rpc: rpc)

        _ = try await client.paymentStatus(
            challengeID: challengeID,
            expectedUserID: ownerID
        )

        let invocation = try XCTUnwrap(rpc.invocations.first)
        XCTAssertEqual(rpc.invocations.count, 1)
        XCTAssertEqual(
            invocation.name,
            "get_my_personal_stripe_sandbox_status_v1"
        )
        let encoded = try JSONEncoder().encode(invocation.parameters)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: String]
        )
        XCTAssertEqual(
            object,
            ["p_challenge_id": challengeID.uuidString]
        )
    }

    func testPaymentStatusValidatesAccountBeforeRequest() async throws {
        let rpc = PaymentStatusRPCStub(
            responseData: try statusData(
                state: PersonalPaymentState.methodSaved.rawValue
            )
        )
        let signedOut = makeClient(rpc: rpc, currentUserID: { nil })
        await assertPaymentError(.authenticationRequired) {
            _ = try await signedOut.paymentStatus(
                challengeID: self.challengeID,
                expectedUserID: self.ownerID
            )
        }

        let otherAccount = makeClient(
            rpc: rpc,
            currentUserID: { self.otherOwnerID }
        )
        await assertPaymentError(.accountChanged) {
            _ = try await otherAccount.paymentStatus(
                challengeID: self.challengeID,
                expectedUserID: self.ownerID
            )
        }
        XCTAssertTrue(rpc.invocations.isEmpty)
    }

    func testPaymentStatusRejectsAccountChangeAcrossAwait() async throws {
        let rpc = PaymentStatusRPCStub(
            responseData: try statusData(
                state: PersonalPaymentState.methodSaved.rawValue
            )
        )
        var accountChecks = 0
        let client = makeClient(
            rpc: rpc,
            currentUserID: {
                accountChecks += 1
                return accountChecks == 1 ? self.ownerID : self.otherOwnerID
            }
        )

        await assertPaymentError(.accountChanged) {
            _ = try await client.paymentStatus(
                challengeID: self.challengeID,
                expectedUserID: self.ownerID
            )
        }
        XCTAssertEqual(rpc.invocations.count, 1)
    }

    func testPaymentStatusMapsRPCFailureWithoutLeakingIt() async throws {
        let rpc = PaymentStatusRPCStub(
            responseData: Data(),
            responseError: URLError(.cannotConnectToHost)
        )
        let client = makeClient(rpc: rpc)

        await assertPaymentError(.unavailable) {
            _ = try await client.paymentStatus(
                challengeID: self.challengeID,
                expectedUserID: self.ownerID
            )
        }
    }

    func testPaymentStatusReadDoesNotDependOnMutationSwitch() async throws {
        let rpc = PaymentStatusRPCStub(
            responseData: try statusData(
                state: PersonalPaymentState.methodSaved.rawValue
            )
        )
        let client = makeClient(
            rpc: rpc,
            configuration: configuration(
                settlementMode: .stripeSandbox,
                contestMutationsEnabled: false
            )
        )

        let status = try await client.paymentStatus(
            challengeID: challengeID,
            expectedUserID: ownerID
        )

        XCTAssertEqual(status.state, .methodSaved)
        XCTAssertEqual(rpc.invocations.count, 1)
    }

    func testNonStripeAndDisabledClientsRefuseStatusRead() async throws {
        let rpc = PaymentStatusRPCStub(
            responseData: try statusData(
                state: PersonalPaymentState.methodSaved.rawValue
            )
        )
        let nonStripe = makeClient(
            rpc: rpc,
            configuration: configuration(settlementMode: .testOnly)
        )
        await assertPaymentError(.disabled) {
            _ = try await nonStripe.paymentStatus(
                challengeID: self.challengeID,
                expectedUserID: self.ownerID
            )
        }

        let disabled = DisabledPersonalPaymentClient()
        await assertPaymentError(.disabled) {
            _ = try await disabled.paymentStatus(
                challengeID: self.challengeID,
                expectedUserID: self.ownerID
            )
        }
        XCTAssertTrue(rpc.invocations.isEmpty)
    }

    private func makeClient(
        rpc: PaymentStatusRPCStub,
        configuration: AppConfiguration? = nil,
        currentUserID: (@MainActor () -> UUID?)? = nil
    ) -> SupabasePersonalPaymentClient {
        let configuration = configuration ?? self.configuration(
            settlementMode: .stripeSandbox
        )
        let supabase = SupabaseClient(
            supabaseURL: configuration.supabaseURL,
            supabaseKey: configuration.supabasePublishableKey
        )
        return SupabasePersonalPaymentClient(
            client: supabase,
            configuration: configuration,
            currentUserID: currentUserID ?? { self.ownerID },
            statusRPC: { name, parameters in
                try await rpc.call(name: name, parameters: parameters)
            }
        )
    }

    private func configuration(
        settlementMode: PersonalSettlementMode,
        contestMutationsEnabled: Bool = true
    ) -> AppConfiguration {
        AppConfiguration(
            environment: .staging,
            supabaseURL: URL(string: "https://fixture.invalid")!,
            supabasePublishableKey: "sb_publishable_fixture_only",
            contestMutationsEnabled: contestMutationsEnabled,
            personalSettlementMode: settlementMode,
            stripeReturnURL: settlementMode == .stripeSandbox
                ? URL(string: "gametime-staging://stripe-redirect")!
                : nil
        )
    }

    private func statusData(
        challengeID: UUID? = nil,
        state: String,
        reviewDeadline: String? = nil,
        environment: String = "sandbox",
        providerFields: [String: Any] = [:]
    ) throws -> Data {
        var object: [String: Any] = [
            "challenge_id": (challengeID ?? self.challengeID).uuidString,
            "environment": environment,
            "payment_state": state,
        ]
        if let reviewDeadline {
            object["review_deadline"] = reviewDeadline
        }
        object.merge(providerFields) { _, new in new }
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func assertPaymentError(
        _ expected: PersonalPaymentClientError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail(
                "Expected payment client error \(expected)",
                file: file,
                line: line
            )
        } catch {
            XCTAssertEqual(
                error as? PersonalPaymentClientError,
                expected,
                file: file,
                line: line
            )
        }
    }
}

@MainActor
private final class PaymentStatusRPCStub {
    struct Invocation {
        let name: String
        let parameters: PersonalPaymentStatusParameters
    }

    let responseData: Data
    let responseError: Error?
    private(set) var invocations: [Invocation] = []

    init(responseData: Data, responseError: Error? = nil) {
        self.responseData = responseData
        self.responseError = responseError
    }

    func call(
        name: String,
        parameters: PersonalPaymentStatusParameters
    ) async throws -> Data {
        invocations.append(Invocation(name: name, parameters: parameters))
        if let responseError {
            throw responseError
        }
        return responseData
    }
}
