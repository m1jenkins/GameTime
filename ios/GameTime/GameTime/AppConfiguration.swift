import Foundation
import GameTimeCore

enum AppEnvironment: String, Equatable, Sendable {
    case debug
    case staging
    case release

    var showsTestEnvironmentBanner: Bool {
        self == .staging || self == .release
    }
}

typealias AppAttestEnvironment = MetricUploadAttestationEnvironment

struct AppConfiguration: Equatable, Sendable {
    let environment: AppEnvironment
    let supabaseURL: URL
    let supabasePublishableKey: String
    let contestMutationsEnabled: Bool
    let personalSettlementMode: PersonalSettlementMode
    let stripeReturnURL: URL?
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
        legacySocialRuntimeEnabled: Bool = false
    ) {
        self.environment = environment
        self.supabaseURL = supabaseURL
        self.supabasePublishableKey = supabasePublishableKey
        self.contestMutationsEnabled = contestMutationsEnabled
        self.personalSettlementMode = personalSettlementMode
        self.stripeReturnURL = stripeReturnURL
        self.legacySocialRuntimeEnabled = legacySocialRuntimeEnabled
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

        return try validated(
            environmentValue: environmentValue,
            urlValue: urlValue,
            keyValue: keyValue,
            mutationValue: mutationValue,
            settlementModeValue: settlementModeValue,
            stripeReturnURLValue: stripeReturnURLValue
        )
    }

    static func validated(
        environmentValue: String?,
        urlValue: String?,
        keyValue: String?,
        mutationValue: String?,
        settlementModeValue: String? = nil,
        stripeReturnURLValue: String? = nil
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
            stripeReturnURL: stripeReturnURL
        )
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
        contestMutationsEnabled: true
    )

    static let activityFixture = AppConfiguration(
        environment: .staging,
        supabaseURL: URL(string: "https://fixture.invalid")!,
        supabasePublishableKey: "sb_publishable_fixture_only",
        contestMutationsEnabled: true
    )

    static let stripeSandboxFixture = AppConfiguration(
        environment: .staging,
        supabaseURL: URL(string: "https://fixture.invalid")!,
        supabasePublishableKey: "sb_publishable_fixture_only",
        contestMutationsEnabled: true,
        personalSettlementMode: .stripeSandbox,
        stripeReturnURL: URL(
            string: "gametime-staging://stripe-redirect"
        )!
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
