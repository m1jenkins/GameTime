import Combine
import Foundation

@MainActor
final class ConformanceViewModel: ObservableObject {
    @Published var stagingURL = ""
    @Published var apiKey = ""
    @Published var accessJWT = ""
    @Published var contestID = ""
    @Published var geofenceID = ""
    @Published var latitude = ""
    @Published var longitude = ""
    @Published var participantTimeZone = TimeZone.current.identifier

    @Published private(set) var results = ConformanceStep.allCases.map {
        ConformanceStepResult.pending($0)
    }
    @Published private(set) var isRunning = false
    @Published private(set) var summary: ConformanceRunSummary?
    @Published private(set) var failureMessage: String?
    @Published private(set) var savedKeyID: String?

    let appAttestSupported: Bool

    private let runner: ConformanceRunner
    private let keyStore: KeyIDStoring

    init(
        appAttest: AppAttestProviding? = nil,
        keyStore: KeyIDStoring? = nil,
        httpClient: ConformanceHTTPClient? = nil
    ) {
        let appAttest = appAttest ?? DeviceAppAttestProvider()
        let keyStore = keyStore ?? UserDefaultsKeyIDStore()
        let httpClient = httpClient ?? URLSessionConformanceHTTPClient()

        self.keyStore = keyStore
        self.runner = ConformanceRunner(
            appAttest: appAttest,
            keyStore: keyStore,
            httpClient: httpClient
        )
        self.appAttestSupported = appAttest.isSupported
        self.savedKeyID = keyStore.loadKeyID()
    }

    func run() {
        guard !isRunning else { return }

        let input = ConformanceInput(
            stagingURL: stagingURL,
            apiKey: apiKey,
            accessJWT: accessJWT,
            contestID: contestID,
            geofenceID: geofenceID,
            latitude: latitude,
            longitude: longitude,
            participantTimeZone: participantTimeZone
        )

        results = ConformanceStep.allCases.map(ConformanceStepResult.pending)
        summary = nil
        failureMessage = nil
        isRunning = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isRunning = false
                self.savedKeyID = self.keyStore.loadKeyID()
            }

            do {
                self.summary = try await self.runner.run(input: input) { update in
                    self.apply(update)
                }
            } catch {
                self.failureMessage = error.localizedDescription
            }
        }
    }

    private func apply(_ update: ConformanceStepUpdate) {
        guard let index = results.firstIndex(where: { $0.step == update.step }) else {
            return
        }
        results[index].state = update.state
        results[index].detail = update.detail
    }
}
