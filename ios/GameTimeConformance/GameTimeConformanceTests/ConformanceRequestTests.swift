import Foundation
import XCTest
@testable import GameTimeConformance

final class ConformanceRequestTests: XCTestCase {
    func testBuildsFunctionEndpointsFromOriginOrFunctionsBase() throws {
        let origin = try XCTUnwrap(
            URL(string: "https://abcdefghijklmnopqrst.supabase.co/")
        )
        let functions = try XCTUnwrap(
            URL(string: "https://abcdefghijklmnopqrst.supabase.co/functions/v1/")
        )

        let fromOrigin = try ConformanceEndpointBuilder.url(
            for: .challenge,
            stagingURL: origin
        )
        let fromFunctions = try ConformanceEndpointBuilder.url(
            for: .challenge,
            stagingURL: functions
        )

        XCTAssertEqual(
            fromOrigin.absoluteString,
            "https://abcdefghijklmnopqrst.supabase.co/functions/v1/attest-device/challenge"
        )
        XCTAssertEqual(fromFunctions, fromOrigin)
    }

    func testValidatedInputRestrictsTheCredentialDestination() throws {
        XCTAssertNoThrow(
            try input(
                stagingURL: "https://abcdefghijklmnopqrst.supabase.co"
            ).validated()
        )
        XCTAssertNoThrow(
            try input(
                stagingURL: "https://abcdefghijklmnopqrst.supabase.co/functions/v1"
            ).validated()
        )

        let unsafeDestinations = [
            "https://evil.example",
            "https://short.supabase.co",
            "https://abcdefghijklmnopqrst.supabase.co.evil.example",
            "https://user:password@abcdefghijklmnopqrst.supabase.co",
            "https://abcdefghijklmnopqrst.supabase.co:443",
            "https://abcdefghijklmnopqrst.supabase.co/",
            "https://abcdefghijklmnopqrst.supabase.co/rest/v1",
            "https://abcdefghijklmnopqrst.supabase.co/functions/v1/attest-device",
        ]
        for destination in unsafeDestinations {
            XCTAssertThrowsError(
                try input(stagingURL: destination).validated(),
                "accepted unsafe credential destination \(destination)"
            )
        }
    }

    func testSignedRequestRetainsExactBodyAssertionAndKeyString() throws {
        let body = Data(#"{"b":2,"a":1}"#.utf8)
        let assertion = Data([0x00, 0xff, 0x01])
        let keyID = "AppleKey+/=="
        let material = SignedRequestMaterial(
            keyID: keyID,
            body: body,
            assertion: assertion,
            counter: 7
        )

        let request = try material.makeRequest(
            endpoint: .ingestCheckIn,
            configuration: configuration()
        )

        XCTAssertEqual(request.httpBody, body)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-gametime-key-id"), keyID)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "x-gametime-assertion"),
            assertion.base64EncodedString()
        )
    }

    func testRegistrationResponseAllowsOmittedOrNullOptionalExtensionFields() throws {
        let responses = [
            #"{"registered":true,"environment":"development"}"#,
            #"{"registered":true,"environment":"development","validationCategory":null,"bundleVersion":null}"#,
        ]

        for json in responses {
            let decoded = try JSONDecoder().decode(
                RegistrationResponse.self,
                from: Data(json.utf8)
            )
            XCTAssertTrue(decoded.registered)
            XCTAssertEqual(decoded.environment, "development")
            XCTAssertNil(decoded.validationCategory)
            XCTAssertNil(decoded.bundleVersion)
        }
    }

    private func configuration() -> ConformanceConfiguration {
        ConformanceConfiguration(
            stagingURL: URL(string: "https://abcdefghijklmnopqrst.supabase.co")!,
            apiKey: "publishable-key",
            accessJWT: "header.payload.signature",
            contestID: UUID(),
            geofenceID: UUID(),
            latitude: 41.88,
            longitude: -87.63,
            participantTimeZone: TimeZone(identifier: "America/Chicago")!
        )
    }

    private func input(stagingURL: String) -> ConformanceInput {
        ConformanceInput(
            stagingURL: stagingURL,
            apiKey: "publishable-key",
            accessJWT: "header.payload.signature",
            contestID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            geofenceID: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            latitude: "41.881",
            longitude: "-87.629",
            participantTimeZone: "America/Chicago"
        )
    }
}
