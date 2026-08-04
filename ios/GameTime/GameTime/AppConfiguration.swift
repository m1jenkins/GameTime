import Foundation

enum AppEnvironment: String, Equatable, Sendable {
    case debug
    case staging
    case release

    var showsTestEnvironmentBanner: Bool { self == .staging }
}

struct AppConfiguration: Equatable, Sendable {
    let environment: AppEnvironment
    let supabaseURL: URL
    let supabasePublishableKey: String
    let contestMutationsEnabled: Bool
    /// Kept only for explicit V2/regression fixtures. Personal V1 runtime must
    /// not fetch or mutate dormant social inventories.
    let legacySocialRuntimeEnabled: Bool

    init(
        environment: AppEnvironment,
        supabaseURL: URL,
        supabasePublishableKey: String,
        contestMutationsEnabled: Bool,
        legacySocialRuntimeEnabled: Bool = false
    ) {
        self.environment = environment
        self.supabaseURL = supabaseURL
        self.supabasePublishableKey = supabasePublishableKey
        self.contestMutationsEnabled = contestMutationsEnabled
        self.legacySocialRuntimeEnabled = legacySocialRuntimeEnabled
    }

    /// Personal accountability is Stage A only. The existing build flag may
    /// unlock local/Staging mutations, but Release always remains read-only.
    var personalChallengeMutationsEnabled: Bool {
        environment != .release && contestMutationsEnabled
    }

    /// There is deliberately no live-fee configuration in the V1 client.
    var personalSettlementMode: PersonalSettlementMode { .testOnly }

    /// Debug and Staging read HealthKit. Release stays off until the shipping
    /// configuration is separately authorized; it also refuses every personal
    /// mutation, so a step read there would have nothing to attach to.
    var activitySyncEnabled: Bool {
        environment == .debug || environment == .staging
    }

    /// Whether a step read can be App Attest-signed and delivered to the
    /// server. Attestation requires a provisioned physical device and the
    /// deployed attested endpoints; Debug against a local stack has neither.
    ///
    /// This is deliberately separate from `activitySyncEnabled`. Reading Health
    /// data and proving that reading to a server are different capabilities,
    /// and fusing them is what previously made the product unreachable until
    /// the entire stack was live.
    var attestedUploadEnabled: Bool { environment == .staging }

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

        return try validated(
            environmentValue: environmentValue,
            urlValue: urlValue,
            keyValue: keyValue,
            mutationValue: mutationValue
        )
    }

    static func validated(
        environmentValue: String?,
        urlValue: String?,
        keyValue: String?,
        mutationValue: String?
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

        return AppConfiguration(
            environment: environment,
            supabaseURL: url,
            supabasePublishableKey: key,
            contestMutationsEnabled: environment == .release
                ? false
                : requestedMutations
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
        }
    }
}
