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
    /// Resampled whenever the start step is entered, so the hours it offers
    /// are the hours still open. Submission re-checks against a live clock.
    @State private var now = Date()

    private enum Step: Int, CaseIterable {
        case metric
        case cadence
        case target
        case commitment
        case start
        case healthAccess
        case review

        var title: String {
            switch self {
            case .metric: "What you’ll track"
            case .cadence: "How it counts"
            case .target: "Your goal"
            case .commitment: "Your amount"
            case .start: "When you start"
            case .healthAccess: "Health check"
            case .review: "Check and confirm"
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
                now = Date()
                if let pending = store.pendingCreation {
                    requestID = pending.request.requestID
                    draft = PersonalChallengeDraft(
                        cadence: pending.request.cadence,
                        targetSteps: pending.request.targetSteps,
                        commitmentAmountMinor:
                            pending.request.commitmentAmountMinor,
                        timezone: pending.request.timezone,
                        // An absent start in a saved retry always meant the
                        // next local midnight, and still does.
                        startsAt: pending.request.startsAt
                            ?? PersonalChallengeStart.nextLocalMidnight(
                                now: now,
                                timezone: pending.request.timezone
                            )
                    )
                    step = .review
                } else {
                    draft = .initial(
                        profileTimezone: appModel.profile?.timezone,
                        now: now
                    )
                }
            }
            .confirmationDialog(
                "Delete this draft?",
                isPresented: $showingDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete draft", role: .destructive) {
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
                Button("Keep it", role: .cancel) {}
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
        .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .metric:
            choice(
                icon: "figure.walk",
                title: "Steps",
                detail:
                    "Right now, steps from Apple Health are the only thing you can track.",
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
                                ? "Hit your goal every single day."
                                : "Hit one total by the end of the week.",
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
                    ? "Steps you’ll walk each day"
                    : "Steps you’ll walk over the week")
                    .font(.subheadline)
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                TextField(
                    "Step goal",
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
                Text("Pick any whole number from 1 to 1,000,000.")
                    .font(.caption)
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            }
        case .commitment:
            VStack(alignment: .leading, spacing: 14) {
                Text("How much are you putting on it?")
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
        case .start:
            startContent
        case .healthAccess:
            healthAccessContent
        case .review:
            reviewContent
        }
    }

    @ViewBuilder
    private var startContent: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(
                "Pick the day and time your week starts (\(draft.timezone))."
            )
            .font(.subheadline)
            .foregroundStyle(CompetitiveTrustTheme.secondaryText)

            DatePicker(
                "Start day",
                selection: startDayBinding,
                in: PersonalChallengeStart.selectableDayRange(
                    now: now,
                    timezone: draft.timezone
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .accessibilityIdentifier("personal.start.day")

            Picker("Start time", selection: startHourBinding) {
                ForEach(selectableHours, id: \.self) { hour in
                    Text(hourLabel(hour)).tag(hour)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("personal.start.hour")

            HStack(spacing: 10) {
                Button("Tonight at midnight") {
                    draft.startsAt = PersonalChallengeStart.nextLocalMidnight(
                        now: now,
                        timezone: draft.timezone
                    )
                }
                .buttonStyle(TrustSecondaryButtonStyle())
                .accessibilityIdentifier("personal.start.tomorrow")

                Button("Next hour") {
                    if let earliest = PersonalChallengeStart
                        .earliestSelectableInstant(
                            now: now,
                            timezone: draft.timezone
                        )
                    {
                        draft.startsAt = earliest
                    }
                }
                .buttonStyle(TrustSecondaryButtonStyle())
                .accessibilityIdentifier("personal.start.next-hour")
            }

            Divider().overlay(CompetitiveTrustTheme.border)

            Text(startConsequence)
                .font(.caption)
                .foregroundStyle(
                    firstDayHours == 24
                        ? CompetitiveTrustTheme.secondaryText
                        : CompetitiveTrustTheme.primaryText
                )
                .accessibilityIdentifier("personal.start.consequence")
        }
    }

    private var selectableHours: [Int] {
        let hours = PersonalChallengeStart.selectableHours(
            onLocalDay: PersonalChallengeStart.localDay(
                of: draft.startsAt,
                timezone: draft.timezone
            ),
            now: now,
            timezone: draft.timezone
        )
        // Keep the current selection addressable even if the hour it sits on
        // has just passed; submission validates against a live clock anyway.
        let selected = PersonalChallengeStart.hour(
            of: draft.startsAt,
            timezone: draft.timezone
        )
        return hours.contains(selected) ? hours : ([selected] + hours).sorted()
    }

    private var startDayBinding: Binding<Date> {
        Binding(
            get: {
                PersonalChallengeStart.localDay(
                    of: draft.startsAt,
                    timezone: draft.timezone
                )
            },
            set: { draft.selectStartDay($0, now: now) }
        )
    }

    private var startHourBinding: Binding<Int> {
        Binding(
            get: {
                PersonalChallengeStart.hour(
                    of: draft.startsAt,
                    timezone: draft.timezone
                )
            },
            set: { draft.selectStartHour($0, now: now) }
        )
    }

    private func hourLabel(_ hour: Int) -> String {
        guard let instant = PersonalChallengeStart.instant(
            localDay: PersonalChallengeStart.localDay(
                of: draft.startsAt,
                timezone: draft.timezone
            ),
            hour: hour,
            timezone: draft.timezone
        ) else { return "\(hour):00" }
        return instant.formatted(
            Date.FormatStyle(
                date: .omitted,
                time: .shortened,
                timeZone: TimeZone(identifier: draft.timezone)
                    ?? TimeZone(secondsFromGMT: 0)!
            )
        )
    }

    private var firstDayHours: Int {
        PersonalChallengeStart.firstDayHours(
            startsAt: draft.startsAt,
            timezone: draft.timezone
        )
    }

    /// The seventh local date always closes at local midnight, so a later
    /// start shortens day one instead of moving the end. Said plainly here
    /// rather than discovered on day one.
    private var startConsequence: String {
        if firstDayHours == 24 {
            return "Seven full days. Day one runs midnight to midnight."
        }
        let shared =
            "Day one is short — \(firstDayHours) \(firstDayHours == 1 ? "hour" : "hours"), from \(hourLabel(PersonalChallengeStart.hour(of: draft.startsAt, timezone: draft.timezone))) until midnight. Days two to seven are full."
        guard draft.cadence == .daily else {
            return shared
                + " You’re going for one total, so this just leaves you less time."
        }
        return shared
            + " You’ll still need \(draft.targetSteps.formatted()) steps in it."
    }

    @ViewBuilder
    private var healthAccessContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                healthAccessTitle,
                systemImage: store.healthReadiness.permitsCreation
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
                "We look at the last day of steps to check that your iPhone or Apple Watch is recording them."
            )
            .font(.subheadline)
            .foregroundStyle(CompetitiveTrustTheme.secondaryText)

            if store.eligibilityHoldActive {
                PersonalEligibilityHoldCard(hold: store.eligibilityHold)
                Text(
                    "Open You and choose Reconnect Health before starting another challenge."
                )
                .font(.caption)
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            }

            if case .localStepsObserved(let probe) = store.healthReadiness {
                Text(
                    probe.sawTrustedDeviceSteps
                        ? "Found \(probe.positiveTrustedSampleCount) step readings from your devices in the last \(probe.trustedHourCount) hours."
                        : "No steps from your devices in the last 24 hours. Walk around with your phone for a bit, then check again."
                )
                .font(.caption)
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                .accessibilityIdentifier("personal.health.probe-result")
            }

            if !store.healthReadiness.permitsCreation {
                Button(
                    store.isVerifyingHealthAccess
                        ? "Checking…"
                        : "Check Health connection"
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
            }

            if !store.configuration.activitySyncEnabled {
                Text(
                    "Health connection checks aren’t available yet."
                )
                .font(.caption)
                .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
            } else if !store.configuration.attestedUploadEnabled {
                Text(
                    "Your steps stay on your phone and aren’t sent to GameTime."
                )
                .font(.caption)
                .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
            }
        }
    }

    private var healthAccessTitle: String {
        store.healthReadiness.permitsCreation
            ? "Health connected"
            : "Check your Health connection"
    }

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("This locks in when you start", systemImage: "lock.fill")
                .font(
                    CompetitiveTrustTheme.displayFont(
                        size: 21,
                        relativeTo: .headline
                    )
                )
            reviewRow("How it counts", draft.cadence.title)
            reviewRow(
                "Goal",
                draft.cadence == .daily
                    ? "\(draft.targetSteps.formatted()) steps a day"
                    : "\(draft.targetSteps.formatted()) steps this week"
            )
            reviewRow(
                "Amount",
                (Double(draft.commitmentAmountMinor) / 100)
                    .formatted(.currency(code: "USD"))
            )
            reviewRow(
                "How long",
                firstDayHours == 24
                    ? "Seven full days"
                    : "Seven days, starting at \(hourLabel(PersonalChallengeStart.hour(of: draft.startsAt, timezone: draft.timezone))) on day one"
            )
            reviewRow("Time zone", draft.timezone)
            reviewRow("Starts", startDescription)
            reviewRow("Last chance to sync", "24 hours after your last day")
            if firstDayHours != 24 {
                Text(startConsequence)
                    .font(.caption)
                    .foregroundStyle(CompetitiveTrustTheme.primaryText)
                    .accessibilityIdentifier("personal.review.short-first-day")
            }
            if !startIsStillValid {
                Text(
                    "That start time has already passed. Go back and pick a new one, or delete this draft."
                )
                .font(.caption)
                .foregroundStyle(CompetitiveTrustTheme.coral)
                .accessibilityIdentifier("personal.review.stale-start")
            }
            Divider().overlay(CompetitiveTrustTheme.border)
            Text(
                "On a daily challenge you have to hit your goal all seven days. On a weekly one you just have to reach the total by the end. If your steps go missing or don’t add up, the week doesn’t count — and it doesn’t count against you."
            )
            .font(.caption)
            .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            if let pending = store.pendingCreation {
                Text("Draft reference: \(pending.request.requestID.uuidString.lowercased())")
                    .font(.caption2.monospaced())
                    .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
                    .accessibilityIdentifier("personal.request-id")
                Button("Delete draft", role: .destructive) {
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
                        Text("Start my challenge")
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
        case .start: startIsStillValid
        case .healthAccess: store.healthReadiness.permitsCreation
        default: true
        }
    }

    private var isDraftValid: Bool {
        (try? draft.validated(requestID: requestID, now: Date())) != nil
    }

    /// A selection sitting in a draft — or restored from a saved retry — can
    /// simply age out of validity while the flow is open.
    private var startIsStillValid: Bool {
        guard let requested = draft.requestedStart(now: now) else { return true }
        return PersonalChallengeStart.isSelectable(
            requested,
            now: now,
            timezone: draft.timezone
        )
    }

    private var startDescription: String {
        PersonalTermsDateFormatter.dateTime(
            draft.startsAt,
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
        let next = Step(rawValue: step.rawValue + 1) ?? .review
        if next == .start {
            // Offer the hours that are open now, not the ones that were open
            // when the flow was first presented.
            now = Date()
            if !startIsStillValid {
                draft.startsAt = PersonalChallengeStart.nextLocalMidnight(
                    now: now,
                    timezone: draft.timezone
                )
            }
        }
        step = next
    }

    private func submit() {
        do {
            let request = try draft.validated(
                requestID: requestID,
                now: Date()
            )
            Task {
                if let id = await store.create(request) {
                    dismiss()
                    router.openPersonalChallenge(id)
                }
            }
        } catch {
            now = Date()
            store.presentedError = error.localizedDescription
        }
    }
}
