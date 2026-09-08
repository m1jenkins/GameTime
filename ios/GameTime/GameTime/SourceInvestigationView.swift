#if DEBUG
import GameTimeCore
import SwiftUI

/// A separate launch mode never constructs the product's services, auth, upload,
/// observer or Watch connectivity. The identity is an ephemeral local session.
enum SourceInvestigationLaunch {
    static var enabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--health-source-investigation")
    }
}

@MainActor @Observable
final class SourceInvestigationStore {
    private(set) var capture: WeeklySourceCapture?
    private(set) var assessment: WeeklySourceAssessment?
    private(set) var busy = false
    private(set) var message = "Nothing has been read."
    private(set) var optedIn = false
    private var generation = UUID()
    private var account = UUID()
    private let read: @MainActor (UUID, WeeklySourceMetric, DateInterval, Date) async throws -> WeeklySourceCapture
    private let authorize: @MainActor (WeeklySourceMetric) async throws -> Void

    init(probe: WeeklyHealthSourceProbe = WeeklyHealthSourceProbe(localInvestigationEnabled: true)) {
        read = { try await probe.capture(accountID: $0, metric: $1, window: $2, observedAt: $3) }
        authorize = { try await probe.requestReadAuthorization(for: $0) }
    }

    init(read: @escaping @MainActor (UUID, WeeklySourceMetric, DateInterval, Date) async throws -> WeeklySourceCapture,
         authorize: @escaping @MainActor (WeeklySourceMetric) async throws -> Void = { _ in }) {
        self.read = read
        self.authorize = authorize
    }

    func optIn() { optedIn = true }

    func clear() {
        generation = UUID()
        account = UUID()
        capture = nil
        assessment = nil
        busy = false
        optedIn = false
        message = "Cleared from memory. Choose to begin again when you’re ready."
    }

    func connect(metric: WeeklySourceMetric) async {
        guard optedIn, !busy else { return }
        let ticket = generation
        busy = true
        defer { if ticket == generation { busy = false } }
        do {
            try await authorize(metric)
            guard ticket == generation else { return }
            message = "The permission request finished. Read a window to see what is available."
        } catch {
            guard ticket == generation else { return }
            message = "We couldn’t open Apple Health. Check access in Settings, then try again."
        }
    }

    func refresh(metric: WeeklySourceMetric, window: DateInterval, now: Date = Date()) async {
        guard optedIn, !busy else { return }
        let ticket = generation
        let owner = account
        let previous = capture.flatMap { $0.metric == metric && $0.window == window ? $0 : nil }
        busy = true
        defer { if ticket == generation { busy = false } }
        do {
            let next = try await read(owner, metric, window, now)
            guard ticket == generation, owner == account else { return }
            guard next.accountID == owner, next.metric == metric, next.window == window else {
                clear()
                return
            }
            let result = try WeeklySourceFeasibility.assess(next, replacing: previous)
            capture = next
            assessment = result
            switch next.state {
            case .successfulQuery: message = "Read finished. Missing activity and complete history cannot be confirmed from this read."
            case .truncated: message = "This window contains too many records. Choose a shorter window and read again."
            case .disabled, .unavailable, .failed: message = "We couldn’t read this window. Check Apple Health access and try again."
            }
        } catch {
            guard ticket == generation else { return }
            capture = nil
            assessment = nil
            message = "We couldn’t compare these reads. Clear this session and try again."
        }
    }
}

struct SourceInvestigationView: View {
    @Environment(\.scenePhase) private var phase
    @State private var store = SourceInvestigationStore()
    @State private var metric = WeeklySourceMetric.steps
    @State private var start = Calendar.current.startOfDay(for: Date())
    @State private var end = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Private activity investigation") {
                    Text("This separate local session does not sign in, score challenges or send activity anywhere. Records remain in memory on this phone.")
                    Text("Do not take screenshots, record the screen, or copy activity records. Leaving this screen or locking the phone clears the session.")
                    Text("No source is approved. A successful read does not prove that activity is complete or that a goal was missed.")
                    if !store.optedIn {
                        Button("Begin private session") { store.optIn() }
                            .accessibilityIdentifier("source-investigation.begin")
                    }
                }
                Section("What to inspect") {
                    Picker("Activity", selection: $metric) {
                        Text("Steps").tag(WeeklySourceMetric.steps)
                        Text("Apple Exercise Time").tag(WeeklySourceMetric.appleExerciseMinutes)
                        Text("Running distance and time").tag(WeeklySourceMetric.runningDistanceMillimeters)
                    }
                    DatePicker("From", selection: $start)
                    DatePicker("Until", selection: $end)
                    Text("The same window stays selected between reads so you can inspect late arrivals and records no longer visible. Travel does not move these instants.")
                    Button("Connect Apple Health") { Task { await store.connect(metric: metric) } }
                        .disabled(!store.optedIn || store.busy)
                    Button("Read this window") {
                        Task { await store.refresh(metric: metric, window: DateInterval(start: start, end: end)) }
                    }.disabled(!store.optedIn || store.busy || start >= end)
                        .accessibilityIdentifier("source-investigation.read")
                }
                Section("Read status") {
                    Text(store.message).accessibilityIdentifier("source-investigation.status")
                    if store.busy { ProgressView("Reading Apple Health…") }
                    if let assessment = store.assessment {
                        LabeledContent("Distinct records", value: assessment.distinctRecordCount.formatted())
                        LabeledContent("Marked as entered by hand", value: assessment.explicitlyManualCount.formatted())
                        ForEach(assessment.concerns.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { concern in
                            Text(explanation(concern))
                        }
                    }
                }
                if let capture = store.capture {
                    Section("Records · only on this phone") {
                        ForEach(capture.records, id: \.id) { record in
                            DisclosureGroup(record.start.formatted(date: .abbreviated, time: .shortened)) {
                                LabeledContent("Value", value: record.value.formatted())
                                LabeledContent("Unit", value: metric == .steps ? "steps" : metric == .appleExerciseMinutes ? "minutes as read" : "millimetres")
                                LabeledContent("Ends", value: record.end.formatted())
                                LabeledContent("Source", value: record.sourceBundleIdentifier ?? "Not supplied")
                                LabeledContent("Device", value: record.deviceModel ?? "Not supplied")
                                LabeledContent("Entered by hand", value: record.wasUserEntered.map { $0 ? "Yes" : "No" } ?? "Not supplied")
                                if let duration = record.reportedWorkoutDurationSeconds {
                                    LabeledContent("Reported workout seconds", value: duration.formatted())
                                    LabeledContent("Start-to-finish seconds, including pauses", value: ceil(record.end.timeIntervalSince(record.start)).formatted())
                                }
                            }
                        }
                    }.privacySensitive()
                }
                Section {
                    Button("Clear session", role: .destructive) { store.clear() }
                        .accessibilityIdentifier("source-investigation.clear")
                }
            }
            .navigationTitle("Activity investigation")
            .onChange(of: metric) { store.clear() }
            .onChange(of: start) { store.clear() }
            .onChange(of: end) { store.clear() }
            .onChange(of: phase) { _, value in if value != .active { store.clear() } }
            .onDisappear { store.clear() }
        }
    }

    private func explanation(_ concern: WeeklySourceConcern) -> String {
        switch concern {
        case .sourceNotValidated: "This source has not been approved for challenge results."
        case .readAccessAndCompletenessUnknown: "Read access and complete activity history cannot be confirmed."
        case .manualEntry: "Some records are marked as entered by hand."
        case .manualMarkerAbsent: "Some records do not say whether they were entered by hand."
        case .sourceMetadataAbsent: "Some records lack source or device details."
        case .overlappingRecords: "Some records overlap. Adding them could count activity twice."
        case .possibleReimport: "Some records may have been imported more than once."
        case .queryTruncated: "The record limit was reached. Try a shorter window."
        case .queryFailedOrUnavailable: "This read was unavailable. Check access and try again."
        case .recordsNoLongerVisible: "Some earlier records are no longer visible. This alone does not prove deletion."
        case .lateArrivals: "Earlier activity appeared after the previous read."
        case .exerciseLineageUnverified: "Apple Exercise Time origins still need physical testing."
        case .runningAccuracyUnverified: "Running distance and pause behavior still need physical testing."
        case .intervalCrossesWindow: "Some records cross the selected window. They are not split or scored."
        }
    }
}
#endif
