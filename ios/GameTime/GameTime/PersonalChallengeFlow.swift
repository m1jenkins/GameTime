import SwiftUI

struct CreatePersonalChallengeFlow: View {
    @Environment(PersonalAccountabilityStore.self) private var store
    @Environment(AppModel.self) private var appModel
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var draft = PersonalChallengeDraft()
    @State private var requestID = UUID()
    @State private var step = Step.metric
    @State private var showingDiscardConfirmation = false

    private enum Step: Int, CaseIterable {
        case metric
        case cadence
        case target
        case commitment
        case diagnostic
        case review

        var title: String {
            switch self {
            case .metric: "Steps goal"
            case .cadence: "Choose cadence"
            case .target: "Set your target"
            case .commitment: "Test commitment"
            case .diagnostic: "Health diagnostic"
            case .review: "Review frozen terms"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    progressHeader
                    TestCommitmentDisclosure()
                    DaybreakCard {
                        stepContent
                    }
                    controls
                }
                .padding(18)
            }
            .daybreakScreenChrome()
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                if let pending = store.pendingCreation {
                    requestID = pending.request.requestID
                    draft = PersonalChallengeDraft(
                        cadence: pending.request.cadence,
                        targetSteps: pending.request.targetSteps,
                        commitmentAmountMinor:
                            pending.request.commitmentAmountMinor,
                        timezone: pending.request.timezone
                    )
                    step = .review
                } else {
                    draft = .initial(
                        profileTimezone: appModel.profile?.timezone
                    )
                }
            }
            .confirmationDialog(
                "Discard the local retry record?",
                isPresented: $showingDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard local retry", role: .destructive) {
                    Task {
                        if await store.discardPendingCreation() {
                            requestID = UUID()
                            draft = .initial(
                                profileTimezone: appModel.profile?.timezone
                            )
                            step = .metric
                        }
                    }
                }
                Button("Keep saved request", role: .cancel) {}
            }
        }
    }

    private var progressHeader: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.rawValue) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue
                        ? CompetitiveTrustTheme.coral
                        : CompetitiveTrustTheme.rail)
                    .frame(height: 6)
            }
        }
        .accessibilityLabel("Step \(step.rawValue + 1) of 6")
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .metric:
            choice(
                icon: "figure.walk",
                title: "Steps",
                detail:
                    "Personal Accountability V1 supports trusted Apple Health steps only.",
                selected: true
            )
            .accessibilityIdentifier("personal.metric.steps")
            .accessibilityValue("Selected")
        case .cadence:
            VStack(spacing: 12) {
                ForEach(PersonalChallengeCadence.allCases) { cadence in
                    Button {
                        draft.selectCadence(cadence)
                    } label: {
                        choice(
                            icon: cadence == .daily
                                ? "calendar.day.timeline.left"
                                : "sum",
                            title: cadence.title,
                            detail: cadence == .daily
                                ? "Meet the target on all seven local days."
                                : "Reach one total across all seven local days.",
                            selected: draft.cadence == cadence
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("personal.cadence.\(cadence.rawValue)")
                    .accessibilityValue(
                        draft.cadence == cadence
                            ? "Selected"
                            : "Not selected"
                    )
                }
            }
        case .target:
            VStack(alignment: .leading, spacing: 15) {
                Text(draft.cadence == .daily
                    ? "Steps required each day"
                    : "Steps required across seven days")
                    .font(.subheadline)
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                TextField(
                    "Step target",
                    value: $draft.targetSteps,
                    format: .number
                )
                .keyboardType(.numberPad)
                .font(
                    CompetitiveTrustTheme.displayFont(
                        size: 36,
                        relativeTo: .largeTitle
                    )
                )
                .padding(14)
                .background(
                    CompetitiveTrustTheme.paperSunk,
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .accessibilityIdentifier("personal.target")
                Text("Use a positive whole number from 1 to 1,000,000.")
                    .font(.caption)
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            }
        case .commitment:
            VStack(alignment: .leading, spacing: 14) {
                Text("Choose the amount you are testing")
                    .font(.subheadline)
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 76))],
                    spacing: 10
                ) {
                    ForEach(
                        PersonalChallengeDraft.allowedCommitmentAmountsMinor,
                        id: \.self
                    ) { amount in
                        Button {
                            draft.commitmentAmountMinor = amount
                        } label: {
                            Text(
                                (Double(amount) / 100)
                                    .formatted(.currency(code: "USD"))
                            )
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(
                                draft.commitmentAmountMinor == amount
                                    ? CompetitiveTrustTheme.coral
                                    : CompetitiveTrustTheme.paperSunk,
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                            .foregroundStyle(
                                draft.commitmentAmountMinor == amount
                                    ? Color.white
                                    : CompetitiveTrustTheme.primaryText
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("personal.commitment.\(amount)")
                        .accessibilityValue(
                            draft.commitmentAmountMinor == amount
                                ? "Selected"
                                : "Not selected"
                        )
                    }
                }
            }
        case .diagnostic:
            diagnosticContent
        case .review:
            reviewContent
        }
    }

    @ViewBuilder
    private var diagnosticContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                healthAccessTitle,
                systemImage: store.healthReadiness.isAttested
                    ? "checkmark.shield.fill"
                    : store.healthReadiness.permitsCreation
                        ? "checkmark.circle.fill"
                        : "heart.text.square.fill"
            )
            .font(
                CompetitiveTrustTheme.displayFont(
                    size: 21,
                    relativeTo: .headline
                )
            )
            Text(
                "GameTime checks a recent completed-hour window for at least one positive, first-party Apple-device step sample."
            )
            .font(.subheadline)
            .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            if store.eligibilityHoldActive {
                PersonalEligibilityHoldCard(hold: store.eligibilityHold)
            }
            if case .localStepsObserved(let probe) = store.healthReadiness {
                Text(
                    probe.sawTrustedDeviceSteps
                        ? "Read \(probe.positiveTrustedSampleCount) device step samples across \(probe.trustedHourCount) completed hours."
                        : "No first-party device step samples in the last 24 completed hours. Walk a little with your phone, then check again."
                )
                .font(.caption)
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                .accessibilityIdentifier("personal.health.probe-result")
            }
            Button(
                store.isVerifyingHealthAccess
                    ? "Checking Health…"
                    : "Verify Health access"
            ) {
                Task {
                    _ = await store.verifyHealthAccess(
                        timezone: draft.timezone
                    )
                }
            }
            .buttonStyle(TrustSecondaryButtonStyle())
            .disabled(
                store.isVerifyingHealthAccess
                    || !store.configuration.activitySyncEnabled
            )
            .accessibilityIdentifier("personal.health.verify")

            if store.configuration.attestedUploadEnabled {
                if let diagnostic = store.latestDiagnostic {
                    Text(
                        "Attested: \(diagnostic.status == .trusted ? "trusted" : "not ready") · \(diagnostic.performedAt.formatted(.relative(presentation: .named)))"
                    )
                    .font(.caption)
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                }
                Button(
                    store.isRunningDiagnostic
                        ? "Running diagnostic…"
                        : "Run trusted diagnostic"
                ) {
                    Task {
                        _ = await store.runDiagnostic(timezone: draft.timezone)
                    }
                }
                .buttonStyle(TrustSecondaryButtonStyle())
                .disabled(store.isRunningDiagnostic)
                .accessibilityIdentifier("personal.diagnostic.run")
            }

            if !store.configuration.activitySyncEnabled {
                Text(
                    "HealthKit reads are available in Debug and Staging builds on a physical iPhone."
                )
                .font(.caption)
                .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
            } else if !store.configuration.attestedUploadEnabled {
                Text(
                    "Steps are read locally in this build. App Attest-signed upload runs in Staging on a provisioned device."
                )
                .font(.caption)
                .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
            }
        }
    }

    private var healthAccessTitle: String {
        if store.healthReadiness.isAttested { return "Trusted diagnostic ready" }
        if store.healthReadiness.permitsCreation { return "Health access verified" }
        return "Verify Health access"
    }

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Terms freeze on confirmation", systemImage: "lock.fill")
                .font(
                    CompetitiveTrustTheme.displayFont(
                        size: 21,
                        relativeTo: .headline
                    )
                )
            reviewRow("Metric", "Steps")
            reviewRow("Cadence", draft.cadence.title)
            reviewRow(
                "Goal",
                draft.cadence == .daily
                    ? "\(draft.targetSteps.formatted()) per day"
                    : "\(draft.targetSteps.formatted()) total"
            )
            reviewRow(
                "Commitment",
                (Double(draft.commitmentAmountMinor) / 100)
                    .formatted(.currency(code: "USD"))
            )
            reviewRow("Length", "Seven complete local days")
            reviewRow("Timezone", draft.timezone)
            reviewRow("Starts", startDescription)
            reviewRow("Final sync", "24 hours after day seven")
            Divider().overlay(CompetitiveTrustTheme.border)
            Text(
                "Daily succeeds only with complete trusted evidence and the target met on all seven days. Cumulative succeeds when complete trusted evidence reaches the seven-day total. Any unresolved evidence is inconclusive and waived."
            )
            .font(.caption)
            .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            if let pending = store.pendingCreation {
                Text("Saved request ID: \(pending.request.requestID.uuidString.lowercased())")
                    .font(.caption2.monospaced())
                    .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
                    .accessibilityIdentifier("personal.request-id")
                Button("Discard saved retry", role: .destructive) {
                    showingDiscardConfirmation = true
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("personal.pending.discard-review")
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if step == .review {
                Button {
                    submit()
                } label: {
                    if store.isMutating {
                        ProgressView().tint(.white)
                    } else {
                        Text("Confirm test commitment")
                    }
                }
                .buttonStyle(TrustPrimaryButtonStyle())
                .disabled(
                    store.isMutating
                        || !store.healthReadiness.permitsCreation
                        || store.eligibilityHoldActive
                        || !isDraftValid
                )
                .accessibilityIdentifier("personal.submit")
            } else {
                Button("Continue") {
                    advance()
                }
                .buttonStyle(TrustPrimaryButtonStyle())
                .disabled(!canAdvance)
                .accessibilityIdentifier("personal.continue")
            }

            if step != .metric {
                Button("Back") {
                    step = Step(rawValue: step.rawValue - 1) ?? .metric
                }
                .buttonStyle(TrustSecondaryButtonStyle())
            }
        }
    }

    private func choice(
        icon: String,
        title: String,
        detail: String,
        selected: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(
                    selected
                        ? CompetitiveTrustTheme.coral
                        : CompetitiveTrustTheme.guide
                )
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            }
            Spacer(minLength: 8)
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(CompetitiveTrustTheme.coral)
            }
        }
        .padding(4)
    }

    private func reviewRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                .multilineTextAlignment(.trailing)
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .target: PersonalChallengeDraft.targetRange.contains(draft.targetSteps)
        case .diagnostic: store.healthReadiness.permitsCreation
        default: true
        }
    }

    private var isDraftValid: Bool {
        (try? draft.validated(requestID: requestID)) != nil
    }

    private var startDescription: String {
        guard let zone = TimeZone(identifier: draft.timezone) else {
            return "Next local midnight"
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let start = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: Date())
        ) else {
            return "Next local midnight"
        }
        return PersonalTermsDateFormatter.dateTime(
            start,
            timezoneIdentifier: draft.timezone
        )
    }

    private func advance() {
        if step == .target,
            !PersonalChallengeDraft.targetRange.contains(draft.targetSteps)
        {
            store.presentedError = PersonalChallengeValidationError.invalidTarget
                .localizedDescription
            return
        }
        step = Step(rawValue: step.rawValue + 1) ?? .review
    }

    private func submit() {
        do {
            let request = try draft.validated(requestID: requestID)
            Task {
                if let id = await store.create(request) {
                    dismiss()
                    router.openPersonalChallenge(id)
                }
            }
        } catch {
            store.presentedError = error.localizedDescription
        }
    }
}
