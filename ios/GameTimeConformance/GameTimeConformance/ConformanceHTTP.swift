import Foundation

struct ConformanceHTTPResponse {
    let statusCode: Int
    let body: Data

    var bodyText: String {
        guard !body.isEmpty else { return "<empty body>" }
        return String(data: body, encoding: .utf8) ?? "<\(body.count) non-UTF-8 bytes>"
    }
}

@MainActor
protocol ConformanceHTTPClient {
    func send(_ request: URLRequest) async throws -> ConformanceHTTPResponse
}

@MainActor
final class URLSessionConformanceHTTPClient: ConformanceHTTPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> ConformanceHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConformanceFailure.invalidResponse("the transport response was not HTTP")
        }
        return ConformanceHTTPResponse(statusCode: httpResponse.statusCode, body: data)
    }
}

enum ConformanceEndpoint {
    case challenge
    case registerDevice
    case ingestMetrics
    case ingestCheckIn

    var label: String {
        switch self {
        case .challenge:
            "attest-device/challenge"
        case .registerDevice:
            "attest-device"
        case .ingestMetrics:
            "ingest-metrics"
        case .ingestCheckIn:
            "ingest-checkin"
        }
    }

    fileprivate var pathComponents: [String] {
        switch self {
        case .challenge:
            ["attest-device", "challenge"]
        case .registerDevice:
            ["attest-device"]
        case .ingestMetrics:
            ["ingest-metrics"]
        case .ingestCheckIn:
            ["ingest-checkin"]
        }
    }
}

enum ConformanceEndpointBuilder {
    static func url(
        for endpoint: ConformanceEndpoint,
        stagingURL: URL
    ) throws -> URL {
        guard var components = URLComponents(url: stagingURL, resolvingAgainstBaseURL: false) else {
            throw ConformanceFailure.configuration("Staging URL could not be resolved.")
        }

        let normalizedPath = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let functionsSuffix = ["functions", "v1"]

        var pathComponents = normalizedPath
        if Array(pathComponents.suffix(functionsSuffix.count)) != functionsSuffix {
            pathComponents.append(contentsOf: functionsSuffix)
        }
        pathComponents.append(contentsOf: endpoint.pathComponents)

        components.path = "/" + pathComponents.joined(separator: "/")
        components.query = nil
        components.fragment = nil
        guard let url = components.url else {
            throw ConformanceFailure.configuration("An endpoint URL could not be formed.")
        }
        return url
    }
}

struct SignedRequestMaterial {
    let keyID: String
    let body: Data
    let assertion: Data
    let counter: UInt32

    func makeRequest(
        endpoint: ConformanceEndpoint,
        configuration: ConformanceConfiguration
    ) throws -> URLRequest {
        var request = try ConformanceRequestFactory.makeRequest(
            endpoint: endpoint,
            configuration: configuration,
            body: body
        )
        // keyID is deliberately used as returned by generateKey(). It is
        // already Apple's Base64 key identifier; do not decode and re-encode it.
        request.setValue(keyID, forHTTPHeaderField: "x-gametime-key-id")
        request.setValue(
            assertion.base64EncodedString(),
            forHTTPHeaderField: "x-gametime-assertion"
        )
        return request
    }
}

enum ConformanceRequestFactory {
    static func makeRequest(
        endpoint: ConformanceEndpoint,
        configuration: ConformanceConfiguration,
        body: Data? = nil
    ) throws -> URLRequest {
        let url = try ConformanceEndpointBuilder.url(
            for: endpoint,
            stagingURL: configuration.stagingURL
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(configuration.apiKey, forHTTPHeaderField: "apikey")
        request.setValue(
            "Bearer \(configuration.accessJWT)",
            forHTTPHeaderField: "Authorization"
        )
        return request
    }
}

struct AttestChallengeResponse: Decodable {
    let challenge: String
    let expiresInSeconds: Int
}

struct RegistrationResponse: Decodable {
    let registered: Bool
    let environment: String
    let validationCategory: Int?
    let bundleVersion: String?
}

struct MetricIngestResponse: Decodable {
    let batchId: UUID
    let observationCount: Int
    let replayed: Bool
}

struct CheckInIngestResponse: Decodable {
    let checkInId: UUID
    let outcome: String
    let dwellSeconds: Double
    let workoutOverlapSeconds: Double
    let replayed: Bool
}
