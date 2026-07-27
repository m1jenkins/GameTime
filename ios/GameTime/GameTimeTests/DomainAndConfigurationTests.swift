import XCTest
@testable import GameTime

final class DomainAndConfigurationTests: XCTestCase {
    func testConfigurationRejectsMissingAndSecretKeys() {
        XCTAssertThrowsError(
            try AppConfiguration.validated(
                environmentValue: "Staging",
                urlValue: "https://example.supabase.co",
                keyValue: nil,
                mutationValue: "YES"
            )
        ) { error in
            XCTAssertEqual(
                error as? AppConfigurationError,
                .missingPublishableKey
            )
        }

        XCTAssertThrowsError(
            try AppConfiguration.validated(
                environmentValue: "Staging",
                urlValue: "https://example.supabase.co",
                keyValue: "sb_secret_never_embed_this",
                mutationValue: "YES"
            )
        ) { error in
            XCTAssertEqual(
                error as? AppConfigurationError,
                .serviceRoleKeyRejected
            )
        }
    }

    func testReleaseAlwaysLocksContestMutation() throws {
        let configuration = try AppConfiguration.validated(
            environmentValue: "Release",
            urlValue: "https://example.supabase.co",
            keyValue: "sb_publishable_unit_test",
            mutationValue: "YES"
        )
        XCTAssertEqual(configuration.environment, .release)
        XCTAssertFalse(configuration.contestMutationsEnabled)
    }

    func testExactHandleSubmissionDoesNotBecomeFuzzySearch() {
        XCTAssertEqual(
            ExactHandleSubmission.normalized("  @Marcus_Moves  "),
            "Marcus_Moves"
        )
        XCTAssertNil(ExactHandleSubmission.normalized("ma"))
        XCTAssertNil(ExactHandleSubmission.normalized("mar*"))
        XCTAssertNil(ExactHandleSubmission.normalized("contains spaces"))
    }

    func testFriendshipCardDTOAndDirectionDecode() throws {
        let data = Data(
            """
            {
              "other_user_id":"22222222-2222-2222-2222-222222222222",
              "handle":"marcusmoves",
              "display_name":"Marcus Green",
              "status":"pending",
              "requested_by":"22222222-2222-2222-2222-222222222222",
              "created_at":"2026-07-26T12:00:00Z",
              "updated_at":"2026-07-26T12:00:00Z",
              "accepted_at":null
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let card = try decoder.decode(FriendshipCard.self, from: data)
        let caller = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!

        XCTAssertEqual(card.handle, "marcusmoves")
        XCTAssertEqual(card.direction(for: caller), .incoming)
    }

    func testContestCardDTOUsesBackendEnumNames() throws {
        let data = Data(
            """
            {
              "id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
              "title":"Distance duel",
              "created_by":"11111111-1111-1111-1111-111111111111",
              "metric":"distance_meters",
              "cadence":"cumulative",
              "target_value":5000,
              "stake_amount_cents":500,
              "tie_break":"earliest_to_target",
              "starts_at":"2026-08-01T12:00:00Z",
              "ends_at":"2026-08-03T12:00:00Z",
              "status":"pending",
              "my_status":"invited"
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let card = try decoder.decode(ContestCard.self, from: data)

        XCTAssertEqual(card.metric, .distanceMeters)
        XCTAssertEqual(card.tieBreak, .earliestToTarget)
        XCTAssertEqual(card.myStatus, .invited)
    }

    func testDuelValidationRequiresFutureCoherentTerms() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var draft = DuelDraft()
        draft.title = "Step duel"
        draft.inviteeID = UUID()
        draft.charityID = UUID()
        draft.startsAt = now.addingTimeInterval(3_600)
        draft.endsAt = now.addingTimeInterval(2 * 86_400)

        let terms = try draft.validated(now: now)
        XCTAssertEqual(terms.title, "Step duel")
        XCTAssertEqual(terms.metric, .steps)
        XCTAssertNotEqual(terms.requestID, UUID())

        draft.cadence = .daily
        draft.endsAt = draft.startsAt.addingTimeInterval(3_600)
        XCTAssertThrowsError(try draft.validated(now: now)) { error in
            XCTAssertEqual(
                error as? DuelValidationError,
                .dailyNeedsFullDay
            )
        }
    }

    func testMutationErrorMapping() {
        struct TestError: LocalizedError {
            let errorDescription: String?
        }

        XCTAssertEqual(
            AppMutationError.map(
                TestError(
                    errorDescription:
                        "request UUID already used with different contest terms"
                )
            ),
            .duplicateRequestChanged
        )
        XCTAssertEqual(
            AppMutationError.map(
                TestError(errorDescription: "Network connection was lost")
            ),
            .offline
        )
        XCTAssertEqual(
            AppMutationError.map(
                TestError(errorDescription: "permission denied 42501")
            ),
            .permissionDenied
        )
    }
}
