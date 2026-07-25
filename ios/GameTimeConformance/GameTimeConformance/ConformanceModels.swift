import Foundation

enum ConformanceStep: String, CaseIterable, Identifiable {
    case configuration
    case appAttestAvailability
    case key
    case challenge
    case registration
    case metricEncoding
    case metricAssertion
    case metricSubmission
    case metricReplay
    case checkInEncoding
    case checkInAssertion
    case checkInSubmission
    case checkInReplay

    var id: Self { self }

    var title: String {
        switch self {
        case .configuration:
            "Validate runtime configuration"
        case .appAttestAvailability:
            "Confirm App Attest support"
        case .key:
            "Load or generate one key"
        case .challenge:
            "Fetch account-bound challenge"
        case .registration:
            "Attest and register key"
        case .metricEncoding:
            "Encode exact metric body"
        case .metricAssertion:
            "Sign exact metric body"
        case .metricSubmission:
            "Submit metric batch"
        case .metricReplay:
            "Replay identical metric request"
        case .checkInEncoding:
            "Encode exact check-in body"
        case .checkInAssertion:
            "Sign exact check-in body"
        case .checkInSubmission:
            "Submit check-in"
        case .checkInReplay:
            "Replay identical check-in request"
        }
    }
}

enum ConformanceStepState: Equatable {
    case pending
    case running
    case succeeded
    case failed
}

struct ConformanceStepResult: Identifiable, Equatable {
    let step: ConformanceStep
    var state: ConformanceStepState
    var detail: String

    var id: ConformanceStep { step }

    static func pending(_ step: ConformanceStep) -> Self {
        Self(step: step, state: .pending, detail: "")
    }
}

struct ConformanceStepUpdate {
    let step: ConformanceStep
    let state: ConformanceStepState
    let detail: String
}

struct ConformanceInput {
    var stagingURL = ""
    var apiKey = ""
    var accessJWT = ""
    var contestID = ""
    var geofenceID = ""
    var latitude = ""
    var longitude = ""
    var participantTimeZone = TimeZone.current.identifier

    func validated() throws -> ConformanceConfiguration {
        let stagingURLValue = stagingURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: stagingURLValue),
              url.scheme?.lowercased() == "https",
              let host = url.host,
              url.query == nil,
              url.fragment == nil
        else {
            throw ConformanceFailure.configuration(
                "Staging URL must be a Supabase HTTPS origin or its /functions/v1 URL."
            )
        }
        guard url.user == nil, url.password == nil, url.port == nil else {
            throw ConformanceFailure.configuration(
                "Staging URL must not contain user info or a port."
            )
        }
        guard Self.isSupabaseProjectHost(host) else {
            throw ConformanceFailure.configuration(
                "Staging host must match <20 lowercase alphanumeric characters>.supabase.co."
            )
        }
        guard url.path.isEmpty || url.path == "/functions/v1" else {
            throw ConformanceFailure.configuration(
                "Staging URL path must be empty or exactly /functions/v1."
            )
        }

        let apiKeyValue = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKeyValue.isEmpty else {
            throw ConformanceFailure.configuration(
                "A Supabase publishable or legacy anon key is required."
            )
        }

        let jwtValue = accessJWT.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !jwtValue.isEmpty else {
            throw ConformanceFailure.configuration("A signed-in user's access JWT is required.")
        }
        guard !jwtValue.lowercased().hasPrefix("bearer ") else {
            throw ConformanceFailure.configuration(
                "Paste only the access JWT; the app adds the Bearer prefix."
            )
        }

        guard let contestIDValue = UUID(
            uuidString: contestID.trimmingCharacters(in: .whitespacesAndNewlines)
        ) else {
            throw ConformanceFailure.configuration("Contest ID is not a UUID.")
        }
        guard let geofenceIDValue = UUID(
            uuidString: geofenceID.trimmingCharacters(in: .whitespacesAndNewlines)
        ) else {
            throw ConformanceFailure.configuration("Geofence ID is not a UUID.")
        }
        guard let latitudeValue = Double(
            latitude.trimmingCharacters(in: .whitespacesAndNewlines)
        ), (-90...90).contains(latitudeValue) else {
            throw ConformanceFailure.configuration("Latitude must be between -90 and 90.")
        }
        guard let longitudeValue = Double(
            longitude.trimmingCharacters(in: .whitespacesAndNewlines)
        ), (-180...180).contains(longitudeValue) else {
            throw ConformanceFailure.configuration("Longitude must be between -180 and 180.")
        }

        let timeZoneIdentifier = participantTimeZone
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            throw ConformanceFailure.configuration(
                "Participant time zone must be an IANA identifier such as America/Chicago."
            )
        }

        return ConformanceConfiguration(
            stagingURL: url,
            apiKey: apiKeyValue,
            accessJWT: jwtValue,
            contestID: contestIDValue,
            geofenceID: geofenceIDValue,
            latitude: latitudeValue,
            longitude: longitudeValue,
            participantTimeZone: timeZone
        )
    }

    private static func isSupabaseProjectHost(_ host: String) -> Bool {
        let suffix = ".supabase.co"
        guard host.hasSuffix(suffix) else { return false }

        let projectReference = host.dropLast(suffix.count)
        guard projectReference.utf8.count == 20 else { return false }
        return projectReference.utf8.allSatisfy { byte in
            (Character("a").asciiValue!...Character("z").asciiValue!).contains(byte)
                || (Character("0").asciiValue!...Character("9").asciiValue!).contains(byte)
        }
    }
}

struct ConformanceConfiguration {
    let stagingURL: URL
    let apiKey: String
    let accessJWT: String
    let contestID: UUID
    let geofenceID: UUID
    let latitude: Double
    let longitude: Double
    let participantTimeZone: TimeZone
}

struct ConformanceRunSummary {
    let keyID: String
    let metricCounter: UInt32
    let checkInCounter: UInt32
    let metricBody: String
    let checkInBody: String
    let metricReplayConfirmed: Bool
    let checkInReplayConfirmed: Bool
}

enum ConformanceFailure: LocalizedError {
    case configuration(String)
    case appAttestUnsupported
    case invalidKeyID
    case invalidChallenge
    case invalidResponse(String)
    case http(endpoint: String, status: Int, body: String)
    case assertionCounter(String)
    case replayMismatch(String)

    var errorDescription: String? {
        switch self {
        case .configuration(let message):
            message
        case .appAttestUnsupported:
            "App Attest is unavailable. Run on a supported physical iPhone, not Simulator."
        case .invalidKeyID:
            "App Attest returned an empty key identifier."
        case .invalidChallenge:
            "The challenge response must contain exactly 32 valid Base64 challenge bytes."
        case .invalidResponse(let message):
            "The server returned an unexpected response: \(message)"
        case .http(let endpoint, let status, let body):
            "\(endpoint) returned HTTP \(status): \(body)"
        case .assertionCounter(let message):
            "The App Attest assertion counter could not be decoded: \(message)"
        case .replayMismatch(let message):
            "Exact replay verification failed: \(message)"
        }
    }
}
