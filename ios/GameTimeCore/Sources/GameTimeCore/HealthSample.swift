import Foundation

/// The measurable quantities, mirroring `public.contest_metric`.
///
/// The raw values are the database's, not HealthKit's. Apple's identifiers stop
/// at the app target's HealthKit adapter, which is the one place that knows
/// `HKQuantityTypeIdentifier.stepCount` means `steps` — so a change to that
/// mapping is one file, and nothing in the schema or in this package has to
/// learn Apple's vocabulary.
public enum ContestMetric: String, Sendable, CaseIterable, Hashable {
    case steps
    case distanceMeters = "distance_meters"
    case activeEnergyKcal = "active_energy_kcal"
    case exerciseMinutes = "exercise_minutes"
}

/// Where a measurement came from, mirroring `public.metric_provenance`.
///
/// Ordered from most to least trustworthy, which is what `Comparable` below is
/// for.
public enum MetricProvenance: String, Sendable, CaseIterable, Hashable {
    /// First-party Apple hardware reported it and the user did not type it.
    case device
    /// Another app wrote it to HealthKit. Could be a running app; could be a
    /// step spoofer. Telling those apart is a heuristic and it is the server's.
    case thirdParty = "third_party"
    /// The user typed it into the Health app. Never admissible.
    case manual
    /// The sample carried no usable provenance metadata at all.
    case unknown

    /// Whether the server will count this toward a target.
    ///
    /// Duplicated from the generated column on `metric_snapshots` on purpose:
    /// the client uses it to show a participant which of their data counts,
    /// before they find out by losing. The server does not consult this — it
    /// recomputes it from the provenance it was sent — so a client that got it
    /// wrong misleads its own user and changes nothing about the outcome.
    public var isAdmissible: Bool {
        switch self {
        case .device, .thirdParty: true
        case .manual, .unknown: false
        }
    }
}

extension MetricProvenance: Comparable {
    private var trustRank: Int {
        switch self {
        case .device: 0
        case .thirdParty: 1
        case .manual: 2
        case .unknown: 3
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.trustRank < rhs.trustRank
    }
}

/// One HealthKit sample, as much of it as this package needs.
///
/// A protocol rather than a struct so that the app target can conform its
/// `HKQuantitySample` wrapper to it without this package importing HealthKit —
/// which is what lets bucketing and provenance be tested on Linux CI at all
/// (D10). The suites conform a plain struct to it.
///
/// `start` and `end` are the sample's own interval. HealthKit's cumulative
/// quantities cover a span rather than an instant, and that span is what makes
/// hour attribution a real problem rather than a lookup.
public protocol HealthSampleDescriptor: Sendable {
    var metric: ContestMetric { get }
    var start: Date { get }
    var end: Date { get }
    /// Already converted to the metric's unit: steps, metres, kilocalories, minutes.
    var value: Double { get }
    /// `HKMetadataKeyWasUserEntered`.
    var wasUserEntered: Bool { get }
    /// `HKSource.bundleIdentifier`, or nil where HealthKit gave none.
    var sourceBundleIdentifier: String? { get }
    /// `HKDevice.manufacturer`.
    var deviceManufacturer: String? { get }
    /// `HKDevice.model`.
    var deviceModel: String? { get }
}

/// Classifies a sample's provenance.
///
/// ---------------------------------------------------------------------------
/// What this is and is not
/// ---------------------------------------------------------------------------
/// It is a *report*, not an authorisation. The client is the party with a motive
/// to lie about where its data came from, so nothing downstream treats this
/// classification as proof: `manual` and `unknown` are refused outright,
/// `third_party` is admissible but carries less weight in M5's integrity
/// scoring, and the reason any of it is worth reading is App Attest — an
/// assertion establishes that the binary doing the classifying is the one that
/// shipped.
///
/// So the job here is to be *faithful* rather than generous. Where the metadata
/// is ambiguous the answer is the less trusted one, because the cost of
/// misreporting a third-party sample as first-party is that a spoofing app looks
/// like an iPhone, and the cost of the reverse is that somebody's genuine run
/// scores slightly lower.
public enum ProvenanceClassifier {
    /// Bundle identifiers HealthKit uses for data the operating system itself
    /// recorded. The Health app writes step and distance data under
    /// `com.apple.health` with a per-device suffix, and the Fitness app uses
    /// `com.apple.Fitness`.
    static let firstPartyPrefixes = ["com.apple.health", "com.apple.Health", "com.apple.Fitness"]

    /// `HKDevice.manufacturer` for Apple hardware.
    static let appleManufacturer = "Apple Inc."

    public static func classify(_ sample: some HealthSampleDescriptor) -> MetricProvenance {
        // Checked first and unconditionally. A hand-typed figure is hand-typed
        // whatever else the sample says about itself, and this is the one flag
        // HealthKit sets that no writing app controls.
        if sample.wasUserEntered {
            return .manual
        }

        guard let bundleIdentifier = sample.sourceBundleIdentifier,
              !bundleIdentifier.isEmpty
        else {
            // No origin at all. Absent evidence of origin is not evidence, so
            // this is deliberately not folded into `thirdParty`.
            return .unknown
        }

        let isFirstPartySource = firstPartyPrefixes.contains { bundleIdentifier.hasPrefix($0) }

        // Both halves are required. A first-party bundle identifier with no
        // Apple device behind it is what a sample synthesised by something else
        // and attributed to Health looks like, and an Apple device reported by a
        // third-party app is that app's claim about its own data.
        if isFirstPartySource, sample.deviceManufacturer == appleManufacturer {
            return .device
        }

        return .thirdParty
    }
}
