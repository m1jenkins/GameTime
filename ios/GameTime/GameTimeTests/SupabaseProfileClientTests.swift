import Foundation
import Supabase
import XCTest

@testable import GameTime

@MainActor
final class SupabaseProfileClientTests: XCTestCase {
    private let ownerID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    func testNormalCreationInsertsWithoutReturningThenReadsOwnProfile() async throws {
        let (client, script) = makeClient([.reply(201, ""), profileReply()])
        let profile = try await create(client)
        XCTAssertEqual(profile.id, ownerID)
        XCTAssertEqual(profile.handle, "runner_1")
        assertRequests(script, methods: ["POST", "GET"])
        let insert = try XCTUnwrap(script.requests.first)
        XCTAssertFalse(insert.value(forHTTPHeaderField: "Prefer")?.contains("return=representation") == true)
        XCTAssertFalse(insert.value(forHTTPHeaderField: "Prefer")?.contains("resolution=") == true)
    }

    func testLostInsertResponseRetryRecoversCommittedProfile() async throws {
        // The server committed the first POST, but its response was lost.
        let (client, script) = makeClient([
            .failure(URLError(.networkConnectionLost)), duplicate("profiles_pkey"), profileReply(),
        ])
        do {
            _ = try await create(client)
            XCTFail("The lost response must remain an error until the user retries")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost)
        }
        let recovered = try await create(client)
        XCTAssertEqual(recovered.id, ownerID)
        XCTAssertEqual(recovered.displayName, "Saved Runner")
        assertRequests(script, methods: ["POST", "POST", "GET"])
    }

    func testLostReadResponseRetryReturnsSavedValuesWithoutUpdatingThem() async throws {
        // The pinned SDK automatically retries failed GETs three times.
        let (client, script) = makeClient(
            [.reply(201, "")]
                + Array(repeating: .failure(URLError(.networkConnectionLost)), count: 4)
                + [duplicate("profiles_pkey"), profileReply()]
        )
        do { _ = try await create(client); XCTFail("Expected lost read") }
        catch { XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost) }
        let recovered = try await client.createProfile(
            userID: ownerID, handle: "edited_draft", displayName: "Edited Name", timezone: "UTC"
        )
        XCTAssertEqual(recovered.handle, "runner_1")
        XCTAssertEqual(recovered.displayName, "Saved Runner")
        assertRequests(script, methods: ["POST", "GET", "GET", "GET", "GET", "POST", "GET"])
    }

    func testGenuineUsernameConflictRemainsUnavailableWithoutRecoveryRead() async {
        let (client, script) = makeClient([duplicate("profiles_handle_key")])
        do { _ = try await create(client); XCTFail("Another actor's username is not success") }
        catch {
            XCTAssertEqual((error as? PostgrestError)?.code, "23505")
            XCTAssertEqual(AppMutationError.map(error), .handleUnavailable)
        }
        assertRequests(script, methods: ["POST"])
    }

    func testMissingOrWrongActorRecoveryRemainsAnError() async {
        for reply in [ProfileHTTPReply.reply(200, "[]"), profileReply(id: UUID())] {
            let (client, script) = makeClient([duplicate("profiles_pkey"), reply])
            do { _ = try await create(client); XCTFail("Must recover the requested actor") }
            catch {
                XCTAssertEqual((error as? PostgrestError)?.code, "23505")
                XCTAssertTrue(AppMutationError.map(error).isUnknownServerFailure)
            }
            assertRequests(script, methods: ["POST", "GET"])
        }
    }

    func testSuccessfulInsertStillRequiresReadableOwnProfile() async {
        for reply in [ProfileHTTPReply.reply(200, "[]"), profileReply(id: UUID())] {
            let (client, script) = makeClient([.reply(201, ""), reply])
            do { _ = try await create(client); XCTFail("Must read the requested actor") }
            catch { XCTAssertTrue(AppMutationError.map(error).isUnknownServerFailure) }
            assertRequests(script, methods: ["POST", "GET"])
        }
    }

    func testNetworkAndPermissionFailuresRemainErrorsOnInsertAndRecoveryRead() async {
        let failures: [ProfileHTTPReply] = [
            .failure(URLError(.notConnectedToInternet)),
            .reply(403, #"{"code":"42501","message":"permission denied","details":null,"hint":null}"#),
        ]
        for failure in failures {
            for recovering in [false, true] {
                let readAttempts: Int
                if case .failure = failure { readAttempts = 4 } else { readAttempts = 1 }
                let (client, script) = makeClient(
                    recovering
                        ? [duplicate("profiles_pkey")] + Array(repeating: failure, count: readAttempts)
                        : [failure]
                )
                do { _ = try await create(client); XCTFail("Failure must not become success") }
                catch {
                    switch failure {
                    case .failure:
                        XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
                    case .reply:
                        XCTAssertEqual((error as? PostgrestError)?.code, "42501")
                        XCTAssertEqual(AppMutationError.map(error), .permissionDenied)
                    }
                }
                assertRequests(script, methods: ["POST"] + (recovering ? Array(repeating: "GET", count: readAttempts) : []))
            }
        }
    }

    func testUnrelatedDuplicateAndNonUniquePrimaryKeyErrorsDoNotRecover() async {
        for reply in [
            duplicate("another_constraint"),
            duplicate("profiles_pkey", code: "42501"),
            .reply(409, #"{"code":"23505","message":"duplicate key","details":"profiles_pkey","hint":null}"#),
        ] {
            let (client, script) = makeClient([reply])
            do { _ = try await create(client); XCTFail("Only the profile primary key conflict can recover") }
            catch { XCTAssertNotNil(error as? PostgrestError) }
            assertRequests(script, methods: ["POST"])
        }
    }

    func testGenericDuplicateIsNotPresentedAsUsernameConflict() {
        for constraint in ["profiles_pkey", "another_constraint"] {
            let error = PostgrestError(
                code: "23505", message: "duplicate key value violates unique constraint \"\(constraint)\""
            )
            XCTAssertTrue(AppMutationError.map(error).isUnknownServerFailure)
        }
    }

    private func create(_ client: SupabaseProfileClient) async throws -> UserProfile {
        try await client.createProfile(
            userID: ownerID, handle: "runner_1", displayName: "Saved Runner", timezone: "UTC"
        )
    }

    private func profileReply(id: UUID? = nil) -> ProfileHTTPReply {
        .reply(200, """
        [{"id":"\((id ?? ownerID).uuidString)","handle":"runner_1","display_name":"Saved Runner","timezone":"UTC"}]
        """)
    }

    private func duplicate(_ constraint: String, code: String = "23505") -> ProfileHTTPReply {
        .reply(409, """
        {"code":"\(code)","message":"duplicate key value violates unique constraint \\"\(constraint)\\"","details":null,"hint":null}
        """)
    }

    private func makeClient(_ replies: [ProfileHTTPReply]) -> (SupabaseProfileClient, ProfileHTTPScript) {
        let host = "\(UUID().uuidString.lowercased()).invalid"
        let script = ProfileHTTPScript(replies)
        ProfileURLProtocol.register(script, host: host)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProfileURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let sdk = SupabaseClient(
            supabaseURL: URL(string: "https://\(host)")!, supabaseKey: "sb_publishable_fixture",
            options: .init(
                auth: .init(storage: ProfileEmptyAuthStorage(), autoRefreshToken: false, emitLocalSessionAsInitialSession: true),
                global: .init(session: session)
            )
        )
        addTeardownBlock {
            session.invalidateAndCancel()
            ProfileURLProtocol.unregister(host: host)
        }
        return (SupabaseProfileClient(client: sdk), script)
    }

    private func assertRequests(_ script: ProfileHTTPScript, methods: [String], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(script.requests.compactMap(\.httpMethod), methods, file: file, line: line)
        for request in script.requests {
            XCTAssertEqual(request.url?.path, "/rest/v1/profiles", file: file, line: line)
            if request.httpMethod == "GET" {
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
                XCTAssertEqual(query?.first { $0.name == "id" }?.value, "eq.\(ownerID.uuidString.lowercased())", file: file, line: line)
                XCTAssertEqual(query?.first { $0.name == "limit" }?.value, "1", file: file, line: line)
                XCTAssertNil(query?.first { $0.name == "handle" }, file: file, line: line)
            }
        }
    }
}

private enum ProfileHTTPReply: Sendable {
    case reply(Int, String)
    case failure(URLError)
}

// Each test owns a unique host and script; no shared response ordering.
private final class ProfileHTTPScript: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [ProfileHTTPReply]
    private var recorded: [URLRequest] = []
    init(_ replies: [ProfileHTTPReply]) { self.replies = replies }
    var requests: [URLRequest] { lock.withLock { recorded } }
    func next(_ request: URLRequest) -> ProfileHTTPReply {
        lock.withLock {
            recorded.append(request)
            return replies.isEmpty ? .failure(URLError(.badServerResponse)) : replies.removeFirst()
        }
    }
}

private final class ProfileURLProtocol: URLProtocol, @unchecked Sendable {
    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var scripts: [String: ProfileHTTPScript] = [:]
    }
    private static let registry = Registry()
    static func register(_ script: ProfileHTTPScript, host: String) {
        registry.lock.withLock { registry.scripts[host] = script }
    }
    static func unregister(host: String) {
        _ = registry.lock.withLock { registry.scripts.removeValue(forKey: host) }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let script = Self.registry.lock.withLock { Self.registry.scripts[request.url?.host ?? ""] }
        guard let script else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        switch script.next(request) {
        case .failure(let error): client?.urlProtocol(self, didFailWithError: error)
        case .reply(let status, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

private struct ProfileEmptyAuthStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws {}
    func retrieve(key: String) throws -> Data? { nil }
    func remove(key: String) throws {}
}
