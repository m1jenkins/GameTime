import SwiftUI

struct ContentView: View {
    @ObservedObject var model: ConformanceViewModel

    var body: some View {
        NavigationStack {
            Form {
                configurationSection
                deviceSection
                runSection
                resultsSection
                if let summary = model.summary {
                    artifactsSection(summary)
                }
            }
            .navigationTitle("M6.5 Conformance")
        }
    }

    private var configurationSection: some View {
        Section {
            TextField(
                "https://abcdefghijklmnopqrst.supabase.co",
                text: $model.stagingURL
            )
            .textContentType(.URL)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            SecureField("Publishable / anon key", text: $model.apiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("User access JWT (without Bearer)", text: $model.accessJWT)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField("Contest UUID", text: $model.contestID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Geofence UUID", text: $model.geofenceID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            HStack {
                TextField("Latitude", text: $model.latitude)
                    .keyboardType(.numbersAndPunctuation)
                TextField("Longitude", text: $model.longitude)
                    .keyboardType(.numbersAndPunctuation)
            }

            TextField("Participant time zone", text: $model.participantTimeZone)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Staging runtime")
        } footer: {
            Text(
                "Secrets stay in memory and are never persisted by this target. "
                    + "The time zone constructs one fully completed local metric hour."
            )
        }
    }

    private var deviceSection: some View {
        Section("Device") {
            LabeledContent("App Attest") {
                Label(
                    model.appAttestSupported ? "Supported" : "Unavailable",
                    systemImage: model.appAttestSupported
                        ? "checkmark.shield.fill"
                        : "xmark.shield.fill"
                )
                .foregroundStyle(model.appAttestSupported ? .green : .red)
            }

            if let keyID = model.savedKeyID {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Persisted key ID")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(keyID)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            } else {
                Text("No key has been generated for this install.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var runSection: some View {
        Section {
            Button {
                model.run()
            } label: {
                HStack {
                    if model.isRunning {
                        ProgressView()
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(model.isRunning ? "Running sequentially…" : "Run conformance")
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(model.isRunning)

            if let failureMessage = model.failureMessage {
                Label(failureMessage, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if let summary = model.summary {
                Label(
                    "Complete. Counters \(summary.metricCounter) → "
                        + "\(summary.checkInCounter); both exact replays confirmed.",
                    systemImage: "checkmark.seal.fill"
                )
                .foregroundStyle(.green)
            }
        }
    }

    private var resultsSection: some View {
        Section("Sequential results") {
            ForEach(model.results) { result in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Image(systemName: icon(for: result.state))
                            .foregroundStyle(color(for: result.state))
                            .frame(width: 20)
                        Text(result.step.title)
                    }
                    if !result.detail.isEmpty {
                        Text(result.detail)
                            .font(.caption)
                            .foregroundStyle(
                                result.state == .failed ? Color.red : Color.secondary
                            )
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func artifactsSection(_ summary: ConformanceRunSummary) -> some View {
        Section {
            LabeledContent("Metric counter", value: String(summary.metricCounter))
            LabeledContent("Check-in counter", value: String(summary.checkInCounter))
            LabeledContent(
                "Metric exact replay",
                value: summary.metricReplayConfirmed ? "Confirmed" : "Not confirmed"
            )
            LabeledContent(
                "Check-in exact replay",
                value: summary.checkInReplayConfirmed ? "Confirmed" : "Not confirmed"
            )

            DisclosureGroup("Exact metric JSON") {
                Text(summary.metricBody)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            DisclosureGroup("Exact check-in JSON") {
                Text(summary.checkInBody)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        } header: {
            Text("Captured artifacts")
        } footer: {
            Text(
                "These are the same immutable GameTimeCore bytes hashed, asserted, "
                    + "and placed in URLRequest.httpBody."
            )
        }
    }

    private func icon(for state: ConformanceStepState) -> String {
        switch state {
        case .pending:
            "circle"
        case .running:
            "circle.dotted"
        case .succeeded:
            "checkmark.circle.fill"
        case .failed:
            "xmark.circle.fill"
        }
    }

    private func color(for state: ConformanceStepState) -> Color {
        switch state {
        case .pending:
            .secondary
        case .running:
            .blue
        case .succeeded:
            .green
        case .failed:
            .red
        }
    }
}
