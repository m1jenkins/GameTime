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
            case .metric: "Steps goal"
            case .cadence: "Choose cadence"
            case .target: "Set your target"
            case .commitment: "Test commitment"
            case .start: "Choose your start"
            case .healthAccess: "Apple Health"
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
        .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .metric:
            choice(
                icon: "figure.walk",
                title: "Steps",
                detail: "This challenge uses steps from Apple Health.",
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
                "Pick the day and hour your seven days open, in \(draft.timezone)."
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
                Button("Tomorrow, midnight") {
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
            return "Seven full local days. Day one runs midnight to midnight."
        }
        let shared =
            "Day one is short: \(firstDayHours) completed \(firstDayHours == 1 ? "hour" : "hours"), from \(hourLabel(PersonalChallengeStart.hour(of: draft.startsAt, timezone: draft.timezone))) to midnight. Days two through seven are full."
        guard draft.cadence == .daily else {
            return shared
                + " Cumulative counts one total across all seven, so this only shortens the time available."
        }
        return shared
            + " On a daily cadence you still need \(draft.targetSteps.formatted()) steps within it."
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
            Text(healthAccessMessage)
            .font(.subheadline)
            .foregroundStyle(CompetitiveTrustTheme.secondaryText)

            if store.eligibilityHoldActive {
                VStack(alignment: .leading, spacing: 6) {
                    Text("New challenge paused")
                        .font(.subheadline.weight(.semibold))
                    Text(
                        "Close this screen, open You, and choose Restore trusted access before starting another challenge."
                    )
                    .font(.caption)
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                }
                .accessibilityIdentifier("personal.eligibility-hold")
            }

            if !store.healthReadiness.permitsCreation {
                Button(
                    store.isVerifyingHealthAccess
                        ? "Checking Apple Health…"
                        : "Check Apple Health"
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
                Text("Apple Health is unavailable right now.")
                    .font(.caption)
                    .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
            }
        }
    }

    private var healthAccessTitle: String {
        store.healthReadiness.permitsCreation
            ? "Apple Health connected"
            : "Connect Apple Health"
    }

    private var healthAccessMessage: String {
        if store.healthReadiness.permitsCreation {
            return "GameTime found recent Apple Health steps."
        }
        if store.isVerifyingHealthAccess {
            return "GameTime is checking for recent Apple Health steps."
        }
        if store.healthReadiness == .unknown {
            return "Check Apple Health so GameTime can confirm it can read your recent steps."
        }
        return "GameTime couldn't find recent Apple Health steps. Check your Health permission, walk briefly with your iPhone or Apple Watch, and try again."
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
            reviewRow(
                "Length",
                firstDayHours == 24
                    ? "Seven complete local days"
                    : "Seven local days, day one from \(hourLabel(PersonalChallengeStart.hour(of: draft.startsAt, timezone: draft.timezone)))"
            )
            reviewRow("Timezone", draft.timezone)
            reviewRow("Starts", startDescription)
            reviewRow("Final sync", "24 hours after day seven")
            if firstDayHours != 24 {
                Text(startConsequence)
                    .font(.caption)
                    .foregroundStyle(CompetitiveTrustTheme.primaryText)
                    .accessibilityIdentifier("personal.review.short-first-day")
            }
            if !startIsStillValid {
                Text(
                    "This saved start has passed. Go back and choose a new one, or discard the saved retry."
                )
                .font(.caption)
                .foregroundStyle(CompetitiveTrustTheme.coral)
                .accessibilityIdentifier("personal.review.stale-start")
            }
            Divider().overlay(CompetitiveTrustTheme.border)
            Text(
                "Daily succeeds only with complete step data and the target met on all seven days. Cumulative succeeds when complete step data reaches the seven-day total. If GameTime cannot confirm the step data, the test commitment is waived."
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
