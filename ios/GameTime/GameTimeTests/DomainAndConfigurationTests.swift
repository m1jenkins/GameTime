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
              "title":"Distance challenge",
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

    func testChallengeValidationRequiresFutureCoherentTerms() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var draft = ChallengeDraft()
        draft.title = "Step challenge"
        let firstFriendID = UUID(
            uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
        )!
        let secondFriendID = UUID(
            uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        )!
        draft.inviteeIDs = [firstFriendID, secondFriendID]
        draft.charityID = UUID()
        draft.startsAt = now.addingTimeInterval(3_600.987_654)
        draft.endsAt = now.addingTimeInterval((2 * 86_400) + 0.765_432)

        let terms = try draft.validated(now: now)
        XCTAssertEqual(terms.title, "Step challenge")
        XCTAssertEqual(terms.inviteeIDs, [secondFriendID, firstFriendID])
        XCTAssertEqual(terms.maxParticipants, 3)
        XCTAssertEqual(terms.metric, .steps)
        XCTAssertNotEqual(terms.requestID, UUID())
        XCTAssertEqual(
            terms.startsAt,
            Date(
                timeIntervalSince1970: (draft.startsAt.timeIntervalSince1970 * 1_000)
                    .rounded(.down) / 1_000
            )
        )
        XCTAssertEqual(
            terms.endsAt,
            Date(
                timeIntervalSince1970: (draft.endsAt.timeIntervalSince1970 * 1_000)
                    .rounded(.down) / 1_000
            )
        )

        draft.cadence = .daily
        draft.endsAt = draft.startsAt.addingTimeInterval(3_600)
        XCTAssertThrowsError(try draft.validated(now: now)) { error in
            XCTAssertEqual(
                error as? ChallengeValidationError,
                .dailyNeedsFullDay
            )
        }
    }

    func testChallengeValidationRequiresOneToNineteenUniqueFriends() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var draft = ChallengeDraft()
        draft.title = "Roster bounds"
        draft.charityID = UUID()
        draft.startsAt = now.addingTimeInterval(3_600)
        draft.endsAt = now.addingTimeInterval(86_400)

        XCTAssertThrowsError(try draft.validated(now: now)) { error in
            XCTAssertEqual(
                error as? ChallengeValidationError,
                .missingFriends
            )
        }

        let friendIDs = (1...20).map { index in
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-\(String(format: "%012d", index))"
            )!
        }
        draft.inviteeIDs = Set(friendIDs.prefix(19))
        let maximumRoster = try draft.validated(now: now)
        XCTAssertEqual(maximumRoster.inviteeIDs.count, 19)
        XCTAssertEqual(maximumRoster.maxParticipants, 20)

        draft.inviteeIDs.insert(friendIDs[19])
        XCTAssertThrowsError(try draft.validated(now: now)) { error in
            XCTAssertEqual(
                error as? ChallengeValidationError,
                .tooManyFriends
            )
        }
    }

    func testAtomicChallengeParametersContainTheCompleteCanonicalRoster()
        throws
    {
        let laterID = UUID(
            uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
        )!
        let earlierID = UUID(
            uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        )!
        let startsAt = Date(timeIntervalSince1970: 2_000_086_400)
        let terms = ChallengeTerms(
            requestID: UUID(),
            title: "One atomic roster",
            inviteeIDs: [laterID, earlierID],
            metric: .steps,
            cadence: .cumulative,
            targetValue: 10_000,
            stakeAmountCents: 500,
            startsAt: startsAt,
            endsAt: startsAt.addingTimeInterval(86_400),
            timezone: "America/Chicago",
            charityID: UUID(),
            tieBreak: .integrityScore
        )

        let encoded = try JSONEncoder().encode(
            CreateContestWithInvitesParameters(terms: terms)
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded)
                as? [String: Any]
        )
        let encodedInvitees = try XCTUnwrap(
            object["p_invitee_ids"] as? [String]
        )

        XCTAssertEqual(
            encodedInvitees.map { $0.lowercased() },
            terms.inviteeIDs.map { $0.uuidString.lowercased() }
        )
        XCTAssertEqual(object["p_max_participants"] as? Int, 3)
        XCTAssertEqual(object["p_request_id"] as? String, terms.requestID.uuidString)
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
