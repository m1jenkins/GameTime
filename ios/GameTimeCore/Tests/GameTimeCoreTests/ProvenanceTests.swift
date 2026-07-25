import Foundation
import Testing

@testable import GameTimeCore

/// A stand-in for the app target's `HKQuantitySample` wrapper.
///
/// This is why `HealthSampleDescriptor` is a protocol: the real conformance
/// imports HealthKit and only compiles on a device, and this one compiles
/// anywhere, so provenance and bucketing are tested on Linux CI rather than only
/// when somebody opens Xcode (DECISIONS.md D10).
struct StubSample: HealthSampleDescriptor {
    var metric: ContestMetric = .steps
    var start: Date
    var end: Date
    var value: Double
    var wasUserEntered: Bool = false
    var sourceBundleIdentifier: String? = "com.apple.health.1234"
    var deviceManufacturer: String? = "Apple Inc."
    var deviceModel: String? = "Watch"

    init(
        metric: ContestMetric = .steps,
        start: Date,
        duration: TimeInterval = 60,
        value: Double,
        wasUserEntered: Bool = false,
        sourceBundleIdentifier: String? = "com.apple.health.1234",
        deviceManufacturer: String? = "Apple Inc.",
        deviceModel: String? = "Watch"
    ) {
        self.metric = metric
        self.start = start
        self.end = start.addingTimeInterval(duration)
        self.value = value
        self.wasUserEntered = wasUserEntered
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.deviceManufacturer = deviceManufacturer
        self.deviceModel = deviceModel
    }
}

@Suite("Provenance")
struct ProvenanceTests {
    let anHour = Date(timeIntervalSince1970: 1_767_225_600)  // 2026-01-01T00:00:00Z

    @Test("first-party hardware with no manual flag is device data")
    func firstPartyIsDevice() {
        let sample = StubSample(start: anHour, value: 800)
        #expect(ProvenanceClassifier.classify(sample) == .device)
    }

    @Test("the Fitness app also counts as first party")
    func fitnessIsDevice() {
        let sample = StubSample(
            start: anHour, value: 30, sourceBundleIdentifier: "com.apple.Fitness"
        )
        #expect(ProvenanceClassifier.classify(sample) == .device)
    }

    // The one flag no writing app controls, so it is checked first and it wins.
    // Everything else about a hand-typed sample can look impeccable.
    @Test("a hand-typed sample is manual whatever else it claims")
    func userEnteredWinsOutright() {
        let sample = StubSample(
            start: anHour,
            value: 20000,
            wasUserEntered: true,
            sourceBundleIdentifier: "com.apple.health.1234",
            deviceManufacturer: "Apple Inc.",
            deviceModel: "iPhone"
        )
        #expect(ProvenanceClassifier.classify(sample) == .manual)
        #expect(ProvenanceClassifier.classify(sample).isAdmissible == false)
    }

    @Test("another app's data is third party")
    func otherAppIsThirdParty() {
        let sample = StubSample(
            start: anHour,
            value: 5000,
            sourceBundleIdentifier: "com.example.stepcounter",
            deviceManufacturer: nil,
            deviceModel: nil
        )
        #expect(ProvenanceClassifier.classify(sample) == .thirdParty)
    }

    // The interesting half of the rule. A sample claiming to be Health data with
    // no Apple device behind it is what something else synthesising data and
    // attributing it to Health looks like, so the ambiguity resolves downward.
    @Test("a first-party bundle id with no Apple device is only third party")
    func firstPartyBundleWithoutAppleDeviceIsThirdParty() {
        let sample = StubSample(
            start: anHour,
            value: 5000,
            sourceBundleIdentifier: "com.apple.health.1234",
            deviceManufacturer: "Definitely Not Apple",
            deviceModel: "Treadmill"
        )
        #expect(ProvenanceClassifier.classify(sample) == .thirdParty)
    }

    // And the mirror image: an app can put whatever it likes in HKDevice, so an
    // Apple device reported by a third-party bundle is that app's own claim.
    @Test("an Apple device reported by another app is still third party")
    func appleDeviceFromThirdPartyBundleIsThirdParty() {
        let sample = StubSample(
            start: anHour,
            value: 5000,
            sourceBundleIdentifier: "com.example.spoofer",
            deviceManufacturer: "Apple Inc.",
            deviceModel: "iPhone"
        )
        #expect(ProvenanceClassifier.classify(sample) == .thirdParty)
    }

    @Test("no source at all is unknown, not third party")
    func missingSourceIsUnknown() {
        for identifier in [nil, ""] as [String?] {
            let sample = StubSample(
                start: anHour,
                value: 100,
                sourceBundleIdentifier: identifier,
                deviceManufacturer: nil,
                deviceModel: nil
            )
            // Absent evidence of origin is not evidence, so it is kept apart from
            // "some app wrote this" rather than folded into it.
            #expect(ProvenanceClassifier.classify(sample) == .unknown)
            #expect(ProvenanceClassifier.classify(sample).isAdmissible == false)
        }
    }

    @Test("admissibility matches the ledger's generated column")
    func admissibilityMatchesTheSchema() {
        #expect(MetricProvenance.device.isAdmissible)
        #expect(MetricProvenance.thirdParty.isAdmissible)
        #expect(!MetricProvenance.manual.isAdmissible)
        #expect(!MetricProvenance.unknown.isAdmissible)
    }

    @Test("raw values are the database's spelling, not Swift's")
    func rawValuesMatchTheSchema() {
        // These strings cross the wire into a Postgres enum, so a rename here
        // that looks harmless in Swift is an ingest failure.
        #expect(MetricProvenance.thirdParty.rawValue == "third_party")
        #expect(ContestMetric.distanceMeters.rawValue == "distance_meters")
        #expect(ContestMetric.activeEnergyKcal.rawValue == "active_energy_kcal")
        #expect(ContestMetric.exerciseMinutes.rawValue == "exercise_minutes")
        #expect(ContestMetric.steps.rawValue == "steps")
    }

    @Test("provenance orders from most to least trustworthy")
    func trustOrdering() {
        #expect(MetricProvenance.device < .thirdParty)
        #expect(MetricProvenance.thirdParty < .manual)
        #expect(MetricProvenance.manual < .unknown)
        #expect([MetricProvenance.unknown, .device, .manual].min() == .device)
    }
}
