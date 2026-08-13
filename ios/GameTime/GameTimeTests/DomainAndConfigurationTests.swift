import SwiftUI
import UIKit
import XCTest

@testable import GameTime

final class DomainAndConfigurationTests: XCTestCase {
    func testEveryProductConfigurationForcesLightAppearance() throws {
        let configurationDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Configuration", isDirectory: true)

        for filename in ["AppInfo.plist", "StagingAppInfo.plist"] {
            let data = try Data(
                contentsOf: configurationDirectory.appendingPathComponent(
                    filename
                )
            )
            let plist = try XCTUnwrap(
                PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                ) as? [String: Any]
            )

            XCTAssertEqual(
                plist["UIUserInterfaceStyle"] as? String,
                "Light",
                "\(filename) must keep GameTime in its fixed light appearance."
            )
        }
    }

    func testDaybreakTextRolesMeetNormalTextContrast() {
        let paper = UIColor(CompetitiveTrustTheme.paper)
        let lightSurfaces: [(name: String, color: UIColor)] = [
            ("paper", paper),
            ("white", UIColor(CompetitiveTrustTheme.card)),
            ("sunk", UIColor(CompetitiveTrustTheme.paperSunk)),
            ("coral tint", UIColor(CompetitiveTrustTheme.coralTint)),
            ("sun tint", UIColor(CompetitiveTrustTheme.sunTint)),
        ]
        let primaryText = UIColor(CompetitiveTrustTheme.primaryText)
        let action = UIColor(CompetitiveTrustTheme.actionCoral)
        var pairs: [(name: String, foreground: UIColor, background: UIColor)] = [
            ("Primary text on paper", primaryText, paper),
            (
                "Secondary text on paper",
                UIColor(CompetitiveTrustTheme.secondaryText),
                paper
            ),
            ("Primary button label", .white, action),
            (
                "Inverse secondary text",
                UIColor(CompetitiveTrustTheme.inverseSecondaryText),
                primaryText
            ),
            (
                "Caution text on paper",
                UIColor(CompetitiveTrustTheme.sunInk),
                paper
            ),
        ]
        let normalTextRoles: [(name: String, color: UIColor)] = [
            ("Tertiary text", UIColor(CompetitiveTrustTheme.tertiaryText)),
            ("Action text", action),
            ("Success text", UIColor(CompetitiveTrustTheme.mintInk)),
        ]
        for role in normalTextRoles {
            for surface in lightSurfaces {
                pairs.append(
                    (
                        "\(role.name) on \(surface.name)",
                        role.color,
                        surface.color
                    )
                )
            }
        }

        for pair in pairs {
            XCTAssertGreaterThanOrEqual(
                contrastRatio(pair.foreground, pair.background),
                4.5,
                "\(pair.name) must remain readable at normal text sizes."
            )
        }
    }

    func testInstalledProductUsesTheGameTimePublicIdentity() {
        XCTAssertEqual(GameTimePublicIdentity.name, "GameTime")
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName")
                as? String,
            "GameTime"
        )
        let healthDescription = Bundle.main.object(
            forInfoDictionaryKey: "NSHealthShareUsageDescription"
        ) as? String
        XCTAssertTrue(healthDescription?.hasPrefix("GameTime ") == true)
    }

    private func contrastRatio(
        _ first: UIColor,
        _ second: UIColor
    ) -> CGFloat {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        return (max(firstLuminance, secondLuminance) + 0.05)
            / (min(firstLuminance, secondLuminance) + 0.05)
    }

    private func relativeLuminance(_ color: UIColor) -> CGFloat {
        let lightColor = color.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .light)
        )
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard lightColor.getRed(
            &red,
            green: &green,
            blue: &blue,
            alpha: &alpha
        ) else {
            XCTFail("Expected an RGB-compatible Daybreak color.")
            return 0
        }

        func linearized(_ component: CGFloat) -> CGFloat {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linearized(red)
            + 0.7152 * linearized(green)
            + 0.0722 * linearized(blue)
    }

    func testInstalledProductContainsValidClientConfiguration() throws {
        let configuration = try AppConfiguration.load()

        XCTAssertNotNil(configuration.supabaseURL.host)
        XCTAssertTrue(
            configuration.supabasePublishableKey.hasPrefix("sb_publishable_")
        )
        XCTAssertGreaterThan(
            configuration.supabasePublishableKey.count,
            "sb_publishable_".count
        )
        XCTAssertEqual(
            Bundle.main.bundleIdentifier,
            "com.mjenkins.gametime.staging"
        )
    }

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

    func testOptionalHelpDestinationsRemainSafeFallbacks() throws {
        let configuration = try AppConfiguration.validated(
            environmentValue: "Debug",
            urlValue: "http://127.0.0.1:54321",
            keyValue: "sb_publishable_unit_test",
            mutationValue: "YES",
            privacyPolicyURLValue: nil,
            betaTermsURLValue: "not-a-published-url",
            supportEmailValue: "not an inbox"
        )

        XCTAssertNil(configuration.privacyPolicyURL)
        XCTAssertNil(configuration.betaTermsURL)
        XCTAssertNil(configuration.supportEmail)
        XCTAssertNil(configuration.supportMailtoURL)
    }

    func testReleaseKeepsLegacyContestMutationLockedByDefault() throws {
        let configuration = try AppConfiguration.validated(
            environmentValue: "Release",
            urlValue: "https://example.supabase.co",
            keyValue: "sb_publishable_unit_test",
            mutationValue: "YES"
        )
        XCTAssertEqual(configuration.environment, .release)
        XCTAssertFalse(configuration.contestMutationsEnabled)
        XCTAssertTrue(configuration.activitySyncEnabled)
        XCTAssertTrue(configuration.attestedUploadEnabled)
        XCTAssertEqual(
            configuration.expectedAppAttestEnvironment,
            .production
        )
        XCTAssertEqual(configuration.personalSettlementMode, .testOnly)
        XCTAssertFalse(configuration.personalChallengeMutationsEnabled)
        XCTAssertFalse(
            configuration.allowsActiveSandboxChallengeCancellation
        )
        XCTAssertNil(configuration.stripeReturnURL)
    }

    func testStripeSandboxRequiresSupportedReturnURLAndEnablesReleaseBeta()
        throws
    {
        XCTAssertThrowsError(
            try AppConfiguration.validated(
                environmentValue: "Staging",
                urlValue: "https://example.supabase.co",
                keyValue: "sb_publishable_unit_test",
                mutationValue: "YES",
                settlementModeValue: "stripe_sandbox",
                stripeReturnURLValue: nil
            )
        ) { error in
            XCTAssertEqual(
                error as? AppConfigurationError,
                .invalidStripeReturnURL
            )
        }

        let staging = try AppConfiguration.validated(
            environmentValue: "Staging",
            urlValue: "https://example.supabase.co",
            keyValue: "sb_publishable_unit_test",
            mutationValue: "YES",
            settlementModeValue: "stripe_sandbox",
            stripeReturnURLValue: "gametime-staging://stripe-redirect"
        )
        XCTAssertEqual(staging.personalSettlementMode, .stripeSandbox)
        XCTAssertTrue(staging.allowsActiveSandboxChallengeCancellation)
        XCTAssertEqual(
            staging.stripeReturnURL?.absoluteString,
            "gametime-staging://stripe-redirect"
        )

        let release = try AppConfiguration.validated(
            environmentValue: "Release",
            urlValue: "https://example.supabase.co",
            keyValue: "sb_publishable_unit_test",
            mutationValue: "YES",
            settlementModeValue: "stripe_sandbox",
            stripeReturnURLValue: "gametime-beta://stripe-redirect"
        )
        XCTAssertTrue(release.personalChallengeMutationsEnabled)
        XCTAssertEqual(release.personalSettlementMode, .stripeSandbox)
        XCTAssertTrue(release.allowsActiveSandboxChallengeCancellation)
        XCTAssertEqual(
            release.stripeReturnURL?.absoluteString,
            "gametime-beta://stripe-redirect"
        )

        XCTAssertThrowsError(
            try AppConfiguration.validated(
                environmentValue: "Release",
                urlValue: "https://example.supabase.co",
                keyValue: "sb_publishable_unit_test",
                mutationValue: "YES",
                settlementModeValue: "stripe_sandbox",
                stripeReturnURLValue:
                    "gametime-staging://stripe-redirect"
            )
        ) { error in
            XCTAssertEqual(
                error as? AppConfigurationError,
                .invalidStripeReturnURL
            )
        }
    }

    /// Reading Health and attesting that read are separate capabilities.
    /// Debug reads locally, Staging uses Apple's sandbox, and the distribution
    /// build requires production App Attest.
    func testHealthReadsAndAttestedUploadAreGatedIndependently() throws {
        let staging = try AppConfiguration.validated(
            environmentValue: "Staging",
            urlValue: "https://example.supabase.co",
            keyValue: "sb_publishable_unit_test",
            mutationValue: "YES"
        )
        let debug = try AppConfiguration.validated(
            environmentValue: "Debug",
            urlValue: "http://127.0.0.1:54321",
            keyValue: "sb_publishable_unit_test",
            mutationValue: "YES"
        )
        let release = try AppConfiguration.validated(
            environmentValue: "Release",
            urlValue: "https://example.supabase.co",
            keyValue: "sb_publishable_unit_test",
            mutationValue: "YES"
        )

        XCTAssertTrue(staging.activitySyncEnabled)
        XCTAssertTrue(debug.activitySyncEnabled)
        XCTAssertTrue(release.activitySyncEnabled)
        XCTAssertTrue(staging.allowsActiveSandboxChallengeCancellation)
        XCTAssertTrue(debug.allowsActiveSandboxChallengeCancellation)
        XCTAssertFalse(release.allowsActiveSandboxChallengeCancellation)

        XCTAssertTrue(staging.attestedUploadEnabled)
        XCTAssertFalse(debug.attestedUploadEnabled)
        XCTAssertTrue(release.attestedUploadEnabled)
        XCTAssertEqual(
            staging.expectedAppAttestEnvironment,
            .development
        )
        XCTAssertNil(debug.expectedAppAttestEnvironment)
        XCTAssertEqual(
            release.expectedAppAttestEnvironment,
            .production
        )
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

    func testProvisionalStandingsDecodeWithRivalIntegrityRedacted() throws {
        let data = Data(
            """
            {
              "contest_id":"cccccccc-cccc-cccc-cccc-cccccccccccc",
              "snapshot_id":"15151515-1515-1515-1515-151515151515",
              "phase":"provisional",
              "reason":"live",
              "as_of":"2026-07-28T12:00:00Z",
              "scoring_version":"m7-scoring-v1",
              "integrity_configuration_version":"m7-integrity-v1",
              "standings":[
                {
                  "participant_id":"44444444-4444-4444-4444-444444444444",
                  "display_name":"Marcus Green",
                  "handle":"marcusmoves",
                  "display_order":1,
                  "rank":1,
                  "qualified":false,
                  "total":7600,
                  "qualifying_days":2,
                  "scoreable_days":3,
                  "day_rate":0.6667
                },
                {
                  "participant_id":"11111111-1111-1111-1111-111111111111",
                  "display_name":"Austin",
                  "handle":"austinmoves",
                  "display_order":2,
                  "rank":2,
                  "qualified":false,
                  "total":6400,
                  "qualifying_days":2,
                  "scoreable_days":3,
                  "day_rate":0.6667,
                  "integrity_score":94.5,
                  "integrity_flags":[],
                  "rationale":[
                    {
                      "code":"trusted_source",
                      "summary":"Health data passed integrity review.",
                      "points":0
                    }
                  ]
                }
              ]
            }
            """.utf8
        )
        let standings = try standingsDecoder().decode(
            ChallengeStandings.self,
            from: data
        )

        XCTAssertEqual(standings.phase, .provisional)
        XCTAssertNil(standings.result)
        XCTAssertNil(standings.standings[0].integrityScore)
        XCTAssertNil(standings.standings[0].integrityFlags)
        XCTAssertNil(standings.standings[0].rationale)
        XCTAssertEqual(standings.standings[1].integrityScore, 94.5)
    }

    func testFinalStandingsDecodeResultAndPerLoserObligation() throws {
        let data = Data(
            """
            {
              "contest_id":"cccccccc-cccc-cccc-cccc-cccccccccccc",
              "snapshot_id":"13131313-1313-1313-1313-131313131313",
              "phase":"final",
              "reason":"final",
              "as_of":"2026-07-28T12:00:00Z",
              "scoring_version":"m7-scoring-v1",
              "integrity_configuration_version":"m7-integrity-v1",
              "result":{
                "id":"12121212-1212-1212-1212-121212121212",
                "kind":"winner",
                "reason":"earliest_to_target",
                "winner_participant_id":"44444444-4444-4444-4444-444444444444",
                "evidence_cutoff":"2026-07-28T10:00:00Z",
                "finalized_at":"2026-07-28T11:00:00Z"
              },
              "standings":[
                {
                  "participant_id":"11111111-1111-1111-1111-111111111111",
                  "display_name":"Austin",
                  "handle":"austinmoves",
                  "display_order":2,
                  "rank":2,
                  "qualified":true,
                  "total":10100,
                  "qualifying_days":3,
                  "scoreable_days":3,
                  "day_rate":1,
                  "reached_target_at":"2026-07-28T02:00:00Z",
                  "integrity_score":95,
                  "integrity_flags":[],
                  "rationale":[],
                  "obligation":{
                    "id":"14141414-1414-1414-1414-141414141414",
                    "kind":"loser_to_winner_charity",
                    "amount_cents":1000,
                    "charity_id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
                    "charity_name":"Fixture Community Fund",
                    "charity_slug":"fixture-community-fund",
                    "destination_owner_id":"44444444-4444-4444-4444-444444444444",
                    "result_dispute_closes_at":"2026-08-04T11:00:00Z"
                  }
                }
              ]
            }
            """.utf8
        )
        let standings = try standingsDecoder().decode(
            ChallengeStandings.self,
            from: data
        )
        let obligation = try XCTUnwrap(standings.standings.first?.obligation)

        XCTAssertEqual(standings.phase, .final)
        XCTAssertEqual(standings.result?.kind, .winner)
        XCTAssertEqual(standings.result?.reason, .earliestToTarget)
        XCTAssertEqual(obligation.kind, .loserToWinnerCharity)
        XCTAssertEqual(obligation.amountCents, 1_000)
        XCTAssertEqual(obligation.charityName, "Fixture Community Fund")
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

    private func standingsDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
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
