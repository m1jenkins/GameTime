import XCTest
@testable import GameTime

/// Round 12: every sign-in failure, including the server's, is Sign in's one
/// quiet sentence rather than the GameTime alert. Cancelling shows nothing.
@MainActor
final class SignInFailureTests: XCTestCase {
    private let identity = AppleIdentity(idToken: "token", rawNonce: "nonce", firstSignInDisplayName: nil)

    func testServerFailureShowsTheSignInCardNotTheAlert() async {
        let auth = SignInTestAuth(outcome: .failure(URLError(.badServerResponse)))
        let model = AppModel(configuration: .personalFixture,
                             services: FixtureServicesFactory.make(arguments: ["--fixture-mode"], authClient: auth))
        await model.signInWithApple(identity)
        XCTAssertNotNil(model.signInFailure)
        XCTAssertNil(model.presentedError, "Sign-in failures never reach the GameTime alert")
        XCTAssertFalse(model.isMutating)

        model.beginAppleSignIn()
        XCTAssertNil(model.signInFailure, "Opening Apple's sheet again clears the last failure")
    }

    func testCancellationShowsNothing() async {
        let auth = SignInTestAuth(outcome: .failure(CancellationError()))
        let model = AppModel(configuration: .personalFixture,
                             services: FixtureServicesFactory.make(arguments: ["--fixture-mode"], authClient: auth))
        await model.signInWithApple(identity)
        XCTAssertNil(model.signInFailure)
        XCTAssertNil(model.presentedError)
    }

    func testANewAttemptClearsTheLastFailure() async {
        let auth = SignInTestAuth(outcome: .failure(URLError(.notConnectedToInternet)))
        let model = AppModel(configuration: .personalFixture,
                             services: FixtureServicesFactory.make(arguments: ["--fixture-mode"], authClient: auth))
        await model.signInWithApple(identity)
        XCTAssertNotNil(model.signInFailure)
        auth.outcome = .success(UUID())
        await model.signInWithApple(identity)
        XCTAssertNil(model.signInFailure)
    }
}

@MainActor private final class SignInTestAuth: AuthClient {
    var outcome: Result<UUID, Error>
    init(outcome: Result<UUID, Error>) { self.outcome = outcome }
    func currentUserID() async -> UUID? { nil }
    func authStateChanges() async -> AsyncStream<AuthSnapshot> { AsyncStream { $0.finish() } }
    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID { try outcome.get() }
    func signOut() async throws {}
}
