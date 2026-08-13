import Foundation
import GameTimeCore

enum AppEnvironment: String, Equatable, Sendable {
    case debug
    case staging
    case release
}

typealias AppAttestEnvironment = MetricUploadAttestationEnvironment

struct AppConfiguration: Equatable, Sendable {
    let environment: AppEnvironment
    let supabaseURL: URL
    let supabasePublishableKey: String
    let contestMutationsEnabled: Bool
    let personalSettlementMode: PersonalSettlementMode
    let stripeReturnURL: URL?
    /// Where the published privacy policy lives, and the inbox a person can
    /// write to. Both are optional at runtime on purpose: a missing help link
    /// is a shipping mistake, not a reason to refuse to open. Making one
    /// required is exactly how `invalidStripeReturnURL` turned a Release build
    /// into a failure screen. `check-beta-candidate.sh` blocks the candidate
    /// instead, before anyone can install it.
    let privacyPolicyURL: URL?
    let betaTermsURL: URL?
    let supportEmail: String?
    /// Kept only for explicit V2/regression fixtures. Personal V1 runtime must
    /// not fetch or mutate dormant social inventories.
    let legacySocialRuntimeEnabled: Bool

    init(
        environment: AppEnvironment,
        supabaseURL: URL,
        supabasePublishableKey: String,
        contestMutationsEnabled: Bool,
        personalSettlementMode: PersonalSettlementMode = .testOnly,
        stripeReturnURL: URL? = nil,
        privacyPolicyURL: URL? = nil,
        betaTermsURL: URL? = nil,
        supportEmail: String? = nil,
        legacySocialRuntimeEnabled: Bool = false
    ) {
        self.environment = environment
        self.supabaseURL = supabaseURL
        self.supabasePublishableKey = supabasePublishableKey
        self.contestMutationsEnabled = contestMutationsEnabled
        self.personalSettlementMode = personalSettlementMode
        self.stripeReturnURL = stripeReturnURL
        self.privacyPolicyURL = privacyPolicyURL
        self.betaTermsURL = betaTermsURL
        self.supportEmail = supportEmail
        self.legacySocialRuntimeEnabled = legacySocialRuntimeEnabled
    }

    /// The `mailto:` a Contact button opens, or nil when no inbox is set.
    var supportMailtoURL: URL? {
        guard let supportEmail else { return nil }
        return URL(string: "mailto:\(supportEmail)")
    }

    /// Legacy social mutations remain separately locked in Release. The beta
    /// Release build may create Personal challenges only through the explicit
    /// Stripe sandbox settlement mode.
    var personalChallengeMutationsEnabled: Bool {
        if environment == .release {
            return personalSettlementMode == .stripeSandbox
        }
        return contestMutationsEnabled
    }

    /// Active cancellation is a sandbox-only capability. Internal Stage A may
    /// clear test-only challenges, and the invite-only Release beta may end a
    /// Stripe test-mode challenge. A locked Release test-only configuration
    /// cannot use the exception.
    var allowsActiveSandboxChallengeCancellation: Bool {
        guard personalChallengeMutationsEnabled else { return false }
        switch personalSettlementMode {
        case .testOnly:
            environment != .release
        case .stripeSandbox:
            true
        }
    }

    /// Health reads are useful in every product configuration. Whether those
    /// reads can leave the phone remains a separate App Attest capability.
    var activitySyncEnabled: Bool {
        switch environment {
        case .debug, .staging, .release:
            true
        }
    }

    /// Whether a step read can be App Attest-signed and delivered to the
    /// server. Attestation requires a provisioned physical device and the
    /// deployed attested endpoints; Debug against a local stack has neither.
    ///
    /// This is deliberately separate from `activitySyncEnabled`. Reading Health
    /// data and proving that reading to a server are different capabilities,
    /// and fusing them is what previously made the product unreachable until
    /// the entire stack was live.
    var attestedUploadEnabled: Bool {
        expectedAppAttestEnvironment != nil
    }

    /// The environment the server must report for a newly registered App
    /// Attest key. TestFlight and App Store builds always use production, while
    /// the internal Staging build deliberately exercises Apple's sandbox.
    var expectedAppAttestEnvironment: AppAttestEnvironment? {
        switch environment {
        case .debug:
            nil
        case .staging:
            .development
        case .release:
            .production
        }
    }

    static func load(bundle: Bundle = .main) throws -> AppConfiguration {
        let environmentValue = bundle.object(
            forInfoDictionaryKey: "GAMETIME_ENV"
        ) as? String
        let urlValue = bundle.object(
            forInfoDictionaryKey: "SUPABASE_URL"
        ) as? String
        let keyValue = bundle.object(
            forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY"
        ) as? String
        let mutationValue = bundle.object(
            forInfoDictionaryKey: "GAMETIME_CONTEST_MUTATIONS_ENABLED"
        ) as? String
        let settlementModeValue = bundle.object(
            forInfoDictionaryKey: "GAMETIME_PERSONAL_SETTLEMENT_MODE"
        ) as? String
        let stripeReturnURLValue = bundle.object(
            forInfoDictionaryKey: "GAMETIME_STRIPE_RETURN_URL"
        ) as? String
        let privacyPolicyURLValue = bundle.object(
            forInfoDictionaryKey: "GAMETIME_PRIVACY_POLICY_URL"
        ) as? String
        let betaTermsURLValue = bundle.object(
            forInfoDictionaryKey: "GAMETIME_BETA_TERMS_URL"
        ) as? String
        let supportEmailValue = bundle.object(
            forInfoDictionaryKey: "GAMETIME_SUPPORT_EMAIL"
        ) as? String

        return try validated(
            environmentValue: environmentValue,
            urlValue: urlValue,
            keyValue: keyValue,
            mutationValue: mutationValue,
            settlementModeValue: settlementModeValue,
            stripeReturnURLValue: stripeReturnURLValue,
            privacyPolicyURLValue: privacyPolicyURLValue,
            betaTermsURLValue: betaTermsURLValue,
            supportEmailValue: supportEmailValue
        )
    }

    static func validated(
        environmentValue: String?,
        urlValue: String?,
        keyValue: String?,
        mutationValue: String?,
        settlementModeValue: String? = nil,
        stripeReturnURLValue: String? = nil,
        privacyPolicyURLValue: String? = nil,
        betaTermsURLValue: String? = nil,
        supportEmailValue: String? = nil
    ) throws -> AppConfiguration {
        guard let environment = AppEnvironment(
            rawValue: environmentValue?.lowercased() ?? ""
        ) else {
            throw AppConfigurationError.invalidEnvironment
        }

        guard
            let rawURL = normalized(urlValue),
            let url = URL(string: rawURL),
            let scheme = url.scheme?.lowercased(),
            url.host != nil,
            scheme == "https" || (environment == .debug && scheme == "http")
        else {
            throw AppConfigurationError.invalidSupabaseURL
        }

        guard let key = normalized(keyValue) else {
            throw AppConfigurationError.missingPublishableKey
        }
        guard key.hasPrefix("sb_publishable_") else {
            if key.hasPrefix("sb_secret_") || jwtRole(in: key) == "service_role" {
                throw AppConfigurationError.serviceRoleKeyRejected
            }
            throw AppConfigurationError.invalidPublishableKey
        }

        let requestedMutations = mutationValue?.lowercased() == "yes"
            || mutationValue?.lowercased() == "true"
            || mutationValue == "1"
        let requestedSettlementMode: PersonalSettlementMode
        if let normalizedMode = normalized(settlementModeValue) {
            guard
                let settlementMode = PersonalSettlementMode(
                    rawValue: normalizedMode.lowercased()
                )
            else {
                throw AppConfigurationError.invalidPersonalSettlementMode
            }
            requestedSettlementMode = settlementMode
        } else {
            // An older or local Debug configuration stays on the legacy
            // no-provider fixture path. Stripe must be explicitly selected.
            requestedSettlementMode = .testOnly
        }

        let stripeReturnURL: URL?
        if requestedSettlementMode == .stripeSandbox {
            guard environment == .staging || environment == .release else {
                throw AppConfigurationError.invalidPersonalSettlementMode
            }

            guard
                let rawReturnURL = normalized(stripeReturnURLValue),
                let returnURL = URL(string: rawReturnURL),
                let returnScheme = returnURL.scheme?.lowercased(),
                returnURL.host?.lowercased() == "stripe-redirect",
                returnURL.user == nil,
                returnURL.password == nil,
                returnURL.port == nil,
                returnURL.query == nil,
                returnURL.fragment == nil
            else {
                throw AppConfigurationError.invalidStripeReturnURL
            }

            let isAllowedReturnScheme: Bool
            switch environment {
            case .staging:
                isAllowedReturnScheme = returnScheme == "gametime-staging"
            case .release:
                let forbiddenReleaseMarkers = [
                    "staging",
                    "debug",
                    "test",
                    "example",
                ]
                isAllowedReturnScheme =
                    returnScheme.hasPrefix("gametime")
                    && forbiddenReleaseMarkers.allSatisfy {
                        !returnScheme.contains($0)
                    }
            case .debug:
                isAllowedReturnScheme = false
            }

            guard isAllowedReturnScheme else {
                throw AppConfigurationError.invalidStripeReturnURL
            }
            stripeReturnURL = returnURL
        } else {
            stripeReturnURL = nil
        }

        return AppConfiguration(
            environment: environment,
            supabaseURL: url,
            supabasePublishableKey: key,
            contestMutationsEnabled: environment == .release
                ? false
                : requestedMutations,
            personalSettlementMode: requestedSettlementMode,
            stripeReturnURL: stripeReturnURL,
            privacyPolicyURL: publishedPolicyURL(privacyPolicyURLValue),
            betaTermsURL: publishedPolicyURL(betaTermsURLValue),
            supportEmail: supportInbox(supportEmailValue)
        )
    }

    /// A published policy has to be reachable from a phone with no session, so
    /// it is HTTPS and nothing else. Anything malformed reads as unset rather
    /// than throwing; see the `privacyPolicyURL` note above.
    static func publishedPolicyURL(_ value: String?) -> URL? {
        guard
            let raw = normalized(value),
            let url = URL(string: raw),
            url.scheme?.lowercased() == "https",
            let host = url.host,
            !host.isEmpty,
            host.contains("."),
            url.user == nil,
            url.password == nil
        else {
            return nil
        }
        return url
    }

    /// Deliberately narrow. This is a single monitored inbox we control, not a
    /// general address parser, so anything with spaces, a missing domain, or a
    /// second `@` reads as unset.
    static func supportInbox(_ value: String?) -> String? {
        guard let raw = normalized(value) else { return nil }
        guard
            raw.unicodeScalars.allSatisfy({
                !CharacterSet.whitespacesAndNewlines.contains($0)
                    && !CharacterSet.controlCharacters.contains($0)
            })
        else {
            return nil
        }
        let parts = raw.split(separator: "@", omittingEmptySubsequences: false)
        guard
            parts.count == 2,
            !parts[0].isEmpty,
            parts[1].contains("."),
            !parts[1].hasPrefix("."),
            !parts[1].hasSuffix(".")
        else {
            return nil
        }
        return raw
    }

    #if DEBUG || STAGING
    /// Explicit opt-in for dormant V2 and historical regression tests.
    static let fixture = AppConfiguration(
        environment: .debug,
        supabaseURL: URL(string: "http://127.0.0.1:54321")!,
        supabasePublishableKey: "sb_publishable_fixture_only",
        contestMutationsEnabled: true,
        legacySocialRuntimeEnabled: true
    )

    static let personalFixture = AppConfiguration(
        environment: .debug,
        supabaseURL: URL(string: "http://127.0.0.1:54321")!,
        supabasePublishableKey: "sb_publishable_fixture_only",
        contestMutationsEnabled: true,
        privacyPolicyURL: URL(string: "https://fixture.invalid/privacy"),
        betaTermsURL: URL(string: "https://fixture.invalid/terms"),
        supportEmail: "support@fixture.invalid"
    )

    static let activityFixture = AppConfiguration(
        environment: .staging,
        supabaseURL: URL(string: "https://fixture.invalid")!,
        supabasePublishableKey: "sb_publishable_fixture_only",
        contestMutationsEnabled: true,
        privacyPolicyURL: URL(string: "https://fixture.invalid/privacy"),
        betaTermsURL: URL(string: "https://fixture.invalid/terms"),
        supportEmail: "support@fixture.invalid"
    )

    static let stripeSandboxFixture = AppConfiguration(
        environment: .staging,
        supabaseURL: URL(string: "https://fixture.invalid")!,
        supabasePublishableKey: "sb_publishable_fixture_only",
        contestMutationsEnabled: true,
        personalSettlementMode: .stripeSandbox,
        stripeReturnURL: URL(
            string: "gametime-staging://stripe-redirect"
        )!,
        privacyPolicyURL: URL(string: "https://fixture.invalid/privacy"),
        betaTermsURL: URL(string: "https://fixture.invalid/terms"),
        supportEmail: "support@fixture.invalid"
    )
    #endif

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmed.isEmpty,
            trimmed != "UNCONFIGURED",
            !trimmed.contains("$(")
        else {
            return nil
        }
        return trimmed
    }

    private static func jwtRole(in key: String) -> String? {
        let parts = key.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var value = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while value.count.isMultiple(of: 4) == false {
            value.append("=")
        }
        guard
            let data = Data(base64Encoded: value),
            let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else {
            return nil
        }
        return object["role"] as? String
    }
}

enum AppConfigurationError: LocalizedError, Equatable, Sendable {
    case invalidEnvironment
    case invalidSupabaseURL
    case missingPublishableKey
    case invalidPublishableKey
    case serviceRoleKeyRejected
    case invalidPersonalSettlementMode
    case invalidStripeReturnURL

    var errorDescription: String? {
        switch self {
        case .invalidEnvironment:
            "This copy of GameTime isn’t set up correctly."
        case .invalidSupabaseURL:
            "GameTime can’t connect because it isn’t set up correctly."
        case .missingPublishableKey:
            "GameTime can’t connect because it isn’t set up correctly."
        case .invalidPublishableKey:
            "GameTime can’t connect because it isn’t set up correctly."
        case .serviceRoleKeyRejected:
            "GameTime can’t connect because it isn’t set up correctly."
        case .invalidPersonalSettlementMode:
            "GameTime payments aren’t set up correctly."
        case .invalidStripeReturnURL:
            "GameTime payments can’t return to the app because this build isn’t set up correctly."
        }
    }
}
