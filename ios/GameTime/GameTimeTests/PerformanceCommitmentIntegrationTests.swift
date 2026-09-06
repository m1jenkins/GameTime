import XCTest
@testable import GameTime

@MainActor
final class PerformanceCommitmentIntegrationTests: XCTestCase {
    func testRuntimeRequiresSeparateOptInAndExplicitLocalEndpoint() {
        func configuration(_ url: String, requested: Bool = true, environment: AppEnvironment = .debug) -> AppConfiguration {
            AppConfiguration(environment: environment, supabaseURL: URL(string: url)!,
                supabasePublishableKey: "sb_publishable_fixture_only", contestMutationsEnabled: true,
                performanceCommitmentRequested: requested)
        }
        XCTAssertFalse(AppConfiguration.personalFixture.performanceCommitmentRuntimeEnabled)
        XCTAssertFalse(AppConfiguration.duelFixture.performanceCommitmentRuntimeEnabled)
        XCTAssertTrue(AppConfiguration.performanceCommitmentFixture.performanceCommitmentRuntimeEnabled)
        XCTAssertFalse(configuration("http://127.0.0.1:57321", requested: false).performanceCommitmentRuntimeEnabled)
        XCTAssertFalse(configuration("http://127.0.0.1:57321", environment: .release).performanceCommitmentRuntimeEnabled)
        for url in ["https://hosted.example", "http://127.0.0.1", "http://127.0.0.1:0",
                    "http://127.0.0.1:57321/path", "http://user@127.0.0.1:57321",
                    "http://127.0.0.1:57321?forward=hosted.example"] {
            XCTAssertFalse(configuration(url).performanceCommitmentRuntimeEnabled, url)
        }
        for url in ["http://127.0.0.1:57321", "http://localhost:57321/", "http://[::1]:57321"] {
            XCTAssertTrue(configuration(url).performanceCommitmentRuntimeEnabled, url)
        }
    }

    func testEveryPresentationFixtureMatchesStrictModels() async throws {
        let actor = UUID()
        for scenario in ["correction", "final", "settlement", "closed"] {
            let client = FixturePerformanceCommitmentClient(currentActor: { actor }, arguments: ["--fixture-commitment-" + scenario])
            let rows = try await client.list(actorID: actor, before: nil)
            XCTAssertEqual(rows.count, 1)
            let row = try XCTUnwrap(rows.first)
            try row.validate(for: actor)
            let lifecycle = try await client.lifecycle(id: row.id, actorID: actor)
            try lifecycle.validate(agreement: row, actorID: actor)
            if scenario == "final" {
                XCTAssertEqual(row.status, .open)
                XCTAssertNotNil(lifecycle.finalResult)
                XCTAssertNil(lifecycle.simulation)
            }
            if scenario == "settlement" { XCTAssertEqual(lifecycle.simulation?.returnedCents, 2000) }
        }
    }

    func testNewStoreDoesNotFetchOrSubmitUnlessOptedIn() async {
        let services = FixtureServicesFactory.make()
        let model = AppModel(configuration: .personalFixture, services: services)
        await model.start()
        XCTAssertNil(model.performanceCommitments.actorID)
        await model.performanceCommitments.refresh()
        XCTAssertTrue(model.performanceCommitments.agreements.isEmpty)
        XCTAssertFalse(model.performanceCommitments.canStartRequest)
    }
}
