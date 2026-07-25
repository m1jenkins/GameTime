import DeviceCheck
import Foundation

@MainActor
protocol AppAttestProviding {
    var isSupported: Bool { get }

    func generateKey() async throws -> String
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data
}

@MainActor
final class DeviceAppAttestProvider: AppAttestProviding {
    private let service: DCAppAttestService

    init(service: DCAppAttestService = .shared) {
        self.service = service
    }

    var isSupported: Bool {
        service.isSupported
    }

    func generateKey() async throws -> String {
        try await service.generateKey()
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await service.attestKey(keyID, clientDataHash: clientDataHash)
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await service.generateAssertion(keyID, clientDataHash: clientDataHash)
    }
}

@MainActor
protocol KeyIDStoring: AnyObject {
    func loadKeyID() -> String?
    func saveKeyID(_ keyID: String) throws
}

@MainActor
final class UserDefaultsKeyIDStore: KeyIDStoring {
    static let storageKey = "GameTimeConformance.appAttestKeyID.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadKeyID() -> String? {
        guard let keyID = defaults.string(forKey: Self.storageKey), !keyID.isEmpty else {
            return nil
        }
        return keyID
    }

    func saveKeyID(_ keyID: String) throws {
        guard !keyID.isEmpty else {
            throw ConformanceFailure.invalidKeyID
        }

        if let existing = loadKeyID(), existing != keyID {
            throw ConformanceFailure.configuration(
                "This install already owns a different App Attest key. Delete and reinstall "
                    + "the conformance app before provisioning another key."
            )
        }

        defaults.set(keyID, forKey: Self.storageKey)
    }
}
