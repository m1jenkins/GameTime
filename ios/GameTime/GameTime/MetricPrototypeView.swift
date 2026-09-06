#if DEBUG || STAGING
import SwiftUI

/// Explicit local fixture entry only. It cannot query Health or share progress.
struct MetricPrototypeView: View {
    @Bindable var store: MetricPrototypeStore
    @State private var format = MetricPrototypeFormat.cumulativeDistance
    @State private var distance = ""
    @State private var unit = MetricPrototypeDistanceUnit.meters
    @State private var elapsedSeconds = ""
    @State private var comparator = MetricPrototypeComparator.strictlyUnder
    @State private var startsAt = Date().addingTimeInterval(60)
    @State private var endsAt = Date().addingTimeInterval(86_400)
    @State private var consent = false
    @State private var consentingActorID: UUID?
    @State private var requestID = UUID()
    @State private var message: String?

    private var draft: MetricPrototypeDraft? {
        guard let target = try? MetricPrototypeUnits.millimeters(distance, unit: unit) else { return nil }
        let elapsed = format == .timedDistance ? try? MetricPrototypeUnits.microseconds(elapsedSeconds) : nil
        let value = MetricPrototypeDraft(format: format, target: target,
            startsAt: DuelInstant(date: startsAt), endsAt: DuelInstant(date: endsAt),
            timezone: TimeZone.current.identifier, elapsedTargetMicroseconds: elapsed,
            comparator: format == .timedDistance ? comparator : nil)
        return (try? value.validate()) != nil ? value : nil
    }

    var body: some View {
        Form {
            Section {
                Text("Private practice only") .font(.headline)
                Text("These fictional records stay on this phone. Apple Health is not connected. No money moves. Nobody else can follow your progress.")
                Text("Observations remain unresolved and are not evaluated. This tool cannot publish a result or prove a real goal was met.")
                Text("Exercise-minute choices remain unavailable while source validation is incomplete.")
                    .foregroundStyle(.secondary)
            }
            if store.actorID == nil {
                Text("Sign in to keep your practice records separate from other accounts.")
            } else if store.enabled {
                Section("Choose a fictional distance goal") {
                    Picker("Format", selection: $format) {
                        Text("Total running distance").tag(MetricPrototypeFormat.cumulativeDistance)
                        Text("One timed run").tag(MetricPrototypeFormat.timedDistance)
                    }
                    TextField("Your chosen distance", text: $distance).keyboardType(.decimalPad)
                        .accessibilityIdentifier("metric-distance")
                    Picker("Distance unit", selection: $unit) {
                        ForEach(MetricPrototypeDistanceUnit.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Text("Enter decimals with a period. One mile is exactly 1,609.344 meters; 1,600 meters is a different distance.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if format == .timedDistance {
                        TextField("Elapsed time limit in seconds", text: $elapsedSeconds).keyboardType(.decimalPad)
                        Picker("Time comparison", selection: $comparator) {
                            Text("Strictly under the limit (<)").tag(MetricPrototypeComparator.strictlyUnder)
                            Text("At or under the limit (≤)").tag(MetricPrototypeComparator.atMost)
                        }
                    }
                    DatePicker("Starts", selection: $startsAt)
                    DatePicker("Ends", selection: $endsAt)
                }
                if let draft {
                    Section("Review before agreeing") {
                        MetricPrototypeRules(draft: draft)
                        Toggle("I agree to save these frozen rules as a private fictional practice record.", isOn: $consent)
                            .accessibilityIdentifier("metric-consent")
                            .onChange(of: consent) { _, accepted in consentingActorID = accepted ? store.actorID : nil }
                        Button("Save agreed practice record") {
                            perform {
                                guard store.actorID != nil, store.actorID == consentingActorID else { throw MetricPrototypeError.accountChanged }
                                _ = try store.create(draft: draft, consent: consent, requestID: requestID)
                                consent = false; requestID = UUID()
                                message = "Your agreed practice record is saved on this phone. Its outcome is unresolved."
                            }
                        }.disabled(!consent).accessibilityIdentifier("metric-create")
                    }
                }
            }
            if let message { Section { Text(message).accessibilityIdentifier("metric-message") } }
            if let error = store.errorMessage { Section { Text(error) } }
            Section("Your private records") {
                if store.agreements.isEmpty { Text("No practice records saved.") }
                ForEach(store.agreements.reversed()) { agreement in
                    NavigationLink {
                        MetricPrototypeDetail(store: store, agreementID: agreement.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(agreement.terms.draft.format.title)
                            Text(agreement.exitedAt == nil ? "Unresolved · not evaluated" : "Left · not evaluated")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Distance practice")
        .onChange(of: draft) { _, _ in consent = false; requestID = UUID(); message = nil }
        .onChange(of: store.actorID) { _, _ in consent = false; consentingActorID = nil; requestID = UUID(); message = nil }
    }
    private func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { message = error.localizedDescription }
    }
}

private struct MetricPrototypeRules: View {
    let draft: MetricPrototypeDraft
    var body: some View {
        Text(draft.format.title).font(.headline)
        Text("Chosen target: \(MetricPrototypeDisplay.value(draft.target, format: draft.format)).")
        Text("Starts \(draft.startsAt.text(zone: draft.timezone)); ends \(draft.endsAt.text(zone: draft.timezone)).")
        if draft.format == .timedDistance {
            Text("One complete run at exactly the chosen distance; fictional short and long tolerances are both zero. No faster segment can be taken from a longer run.")
            Text("Time limit: \(MetricPrototypeDisplay.seconds(draft.elapsedTargetMicroseconds ?? 0)) seconds, \(draft.comparator == .strictlyUnder ? "strictly under (<)" : "at or under (≤)"). Full start-to-finish elapsed time includes every pause. Moving time and cumulative totals cannot prove this goal.")
            Text("A run may start at the opening instant and must finish strictly before the closing instant.")
        } else {
            Text("Replacement observations describe the total for this window. They are not added to previous revisions, and no timed performance is inferred.")
        }
        Text("You may replace an observation, including lowering it or marking data missing, until strictly before 48 hours after this window ends. Missing data never means failure. There is no final result or review process in this practice tool.")
        Text("You can leave at any time. Your saved rules and prior observations stay private until local account cleanup removes them.")
    }
}

private struct MetricPrototypeDetail: View {
    @Bindable var store: MetricPrototypeStore
    let agreementID: UUID
    @State private var proofState = MetricPrototypeProofDraft.State.missing
    @State private var distance = ""
    @State private var startsAt = Date()
    @State private var endsAt = Date()
    @State private var requestID = UUID()
    @State private var exitRequestID = UUID()
    @State private var confirmExit = false
    @State private var message: String?
    private var agreement: MetricPrototypeAgreement? { store.agreements.first { $0.id == agreementID } }
    private var proof: MetricPrototypeProofDraft? {
        if proofState != .observed { return .init(state: proofState, value: nil, startsAt: nil, endsAt: nil) }
        guard let value = try? MetricPrototypeUnits.millimeters(distance, unit: .meters, allowZero: true) else { return nil }
        return .init(state: .observed, value: value, startsAt: DuelInstant(date: startsAt), endsAt: DuelInstant(date: endsAt))
    }
    var body: some View {
        Form {
            if let agreement {
                Section("Frozen practice rules") { MetricPrototypeRules(draft: agreement.terms.draft) }
                Section("Private observation history") {
                    Text("Unresolved · not evaluated").font(.headline)
                    Text("There is no Health connection, shared progress, payout or final result.")
                    Text("Corrections close \(agreement.terms.correctionsCloseAt.text(zone: agreement.terms.draft.timezone)).")
                    ForEach(agreement.proofs.reversed()) { proof in
                        Text("Revision \(proof.revision): \(proof.draft.state.rawValue)\(proof.draft.value.map { " · \(MetricPrototypeDisplay.value($0, format: agreement.terms.draft.format))" } ?? ""). Replaces the prior observation.")
                    }
                    if agreement.proofs.isEmpty { Text("No observation saved. Missing data does not mean failure.") }
                }
                if agreement.exitedAt == nil, store.enabled, agreement.terms.draft.format != .exerciseMinutes {
                    Section("Save a replacement fictional observation") {
                        Picker("Data state", selection: $proofState) {
                            Text("Missing").tag(MetricPrototypeProofDraft.State.missing)
                            Text("Unavailable").tag(MetricPrototypeProofDraft.State.unavailable)
                            Text("Fictional observation").tag(MetricPrototypeProofDraft.State.observed)
                        }
                        if proofState == .observed {
                            TextField("Fictional distance in meters", text: $distance).keyboardType(.decimalPad)
                            DatePicker("Observation starts", selection: $startsAt)
                            DatePicker("Observation ends", selection: $endsAt)
                            Text("For a timed run, these timestamps include every pause. This report has no authority to qualify a goal.")
                        }
                        Button("Save private observation") {
                            guard let proof else { return }
                            do {
                                try store.appendProof(agreementID: agreementID, draft: proof, requestID: requestID)
                                requestID = UUID(); message = "Your fictional observation is saved. The outcome remains unresolved."
                            } catch { message = error.localizedDescription }
                        }.disabled(proof == nil)
                    }
                }
                Section {
                    if agreement.exitedAt != nil { Text("You left this practice record. No further observations can be added.") }
                    else { Button("Leave this practice record", role: .destructive) { confirmExit = true } }
                }
            } else { Text("This record is unavailable for the current account.") }
            if let message { Section { Text(message) } }
        }
        .navigationTitle("Private practice")
        .onChange(of: proof) { _, _ in requestID = UUID(); message = nil }
        .confirmationDialog("Leave this private practice record?", isPresented: $confirmExit) {
            Button("Leave practice record", role: .destructive) {
                do {
                    try store.exit(agreementID: agreementID, requestID: exitRequestID)
                    message = "You left this practice record. Your private history is saved."
                } catch { message = error.localizedDescription }
            }
        } message: { Text("Leaving stops new observations. It does not create a win, loss or final result.") }
    }
}

enum MetricPrototypeDisplay {
    static func value(_ value: Int, format: MetricPrototypeFormat) -> String {
        let number = NSDecimalNumber(decimal: Decimal(value) / 1_000).stringValue
        return number + (format == .exerciseMinutes ? " Exercise minutes" : " meters")
    }
    static func seconds(_ microseconds: Int) -> String {
        NSDecimalNumber(decimal: Decimal(microseconds) / 1_000_000).stringValue
    }
}
#endif
