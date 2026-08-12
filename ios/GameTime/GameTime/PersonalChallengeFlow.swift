import StripePaymentSheet
import SwiftUI

struct CreatePersonalChallengeFlow: View {
    @Environment(PersonalAccountabilityStore.self) private var store
    @Environment(AppModel.self) private var appModel
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.demoMode) private var demoMode

    @State private var draft = PersonalChallengeDraft()
    @State private var requestID = UUID()
    @State private var step = Step.cadence
    @State private var showingDiscardConfirmation = false
    @State private var paymentConsentAccepted = false
    @State private var paymentSheet: PaymentSheet?
    @State private var paymentSheetSetupID: String?
    @State private var showingPaymentSheet = false
    /// Resampled whenever the start step is entered, so the hours it offers
    /// are the hours still open. Submission re-checks against a live clock.
    @State private var now = Date()
    @State private var startsImmediatelyInDemo = false

    private enum Step: Int, CaseIterable {
        case metric
        case cadence
        case target
        case commitment
        case start
        case healthAccess
        case payment
        case review

        var title: String {
            switch self {
            case .metric: "What you’ll track"
            case .cadence: "How it counts"
            case .target: "Your goal"
            case .commitment: "Your amount"
            case .start: "When you start"
            case .healthAccess: "Apple Health"
            case .payment: "Test payment"
            case .review: "Check and confirm"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    progressHeader
                    TestCommitmentDisclosure(
                        settlementMode:
                            store.configuration.personalSettlementMode
                    )
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
                    step =
                        if !store.healthReadiness.permitsCreation {
                            .healthAccess
                        } else if store.configuration.personalSettlementMode
                            == .stripeSandbox,
                            pending.paymentSetupCompletedAt == nil
                        {
                            .payment
                        } else {
                            .review
                        }
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
                            step = .cadence
                        }
                    }
                }
                Button("Keep it", role: .cancel) {}
            }
            .background {
                if let paymentSheet {
                    PersonalPaymentSheetPresenter(
                        paymentSheet: paymentSheet,
                        isPresented: $showingPaymentSheet,
                        completion: handlePaymentSheetResult
                    )
                }
            }
        }
    }

    private var progressHeader: some View {
        HStack(spacing: 6) {
            ForEach(visibleSteps, id: \.rawValue) { item in
                Capsule()
                    .fill(
                        (visibleSteps.firstIndex(of: item) ?? 0)
                            <= (visibleSteps.firstIndex(of: step) ?? 0)
                        ? CompetitiveTrustTheme.coral
                        : CompetitiveTrustTheme.rail
                    )
                    .frame(height: 6)
            }
        }
        .accessibilityLabel(
            "Step \((visibleSteps.firstIndex(of: step) ?? 0) + 1) of \(visibleSteps.count)"
        )
    }

    private var visibleSteps: [Step] {
        Step.allCases.filter { item in
            item != .metric
                && item != .start
                && (
                    item != .payment
                        || store.configuration.personalSettlementMode
                            == .stripeSandbox
                )
        }
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
        case .payment:
            paymentContent
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
        if startsImmediatelyInDemo && demoMode.isActive {
            let shared =
                "Day one starts at \(startTimeLabel) and runs until midnight. Days two to seven are full."
            return draft.cadence == .daily
                ? shared
                    + " You’ll still need \(draft.targetSteps.formatted()) steps today."
                : shared
                    + " You’re going for one total, so this just leaves you less time."
        }
        let shared =
            "Day one is short — \(firstDayHours) \(firstDayHours == 1 ? "hour" : "hours"), from \(startTimeLabel) until midnight. Days two to seven are full."
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
                "Connect Apple Health so GameTime can update this challenge automatically from your step history."
            )
            .font(.subheadline)
            .foregroundStyle(CompetitiveTrustTheme.secondaryText)

            if !store.healthReadiness.permitsCreation {
                Button(
                    store.isVerifyingHealthAccess
                        ? "Connecting…"
                        : "Connect Apple Health"
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
            }
        }
    }

    private var healthAccessTitle: String {
        store.healthReadiness.permitsCreation
            ? "Health connected"
            : "Connect Apple Health"
    }

    private var paymentContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                store.pendingPaymentIsConfirmed
                    ? "Test payment method saved"
                    : "Save a payment method in Stripe test mode",
                systemImage: store.pendingPaymentIsConfirmed
                    ? "checkmark.circle.fill"
                    : "creditcard.fill"
            )
            .font(
                CompetitiveTrustTheme.displayFont(
                    size: 21,
                    relativeTo: .headline
                )
            )

            Text("Add your test payment method before you start.")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                paymentRule(
                    "Meeting your goal, an inconclusive result, and cancelling before the challenge starts close without a settlement."
                )
                paymentRule(
                    "A complete miss is only provisional after the 24-hour update window."
                )
                paymentRule(
                    "Your review window ends 7 days after the result is published."
                )
                paymentRule(
                    "Only a miss confirmed after review can create one simulated off-session test charge."
                )
            }

            Divider().overlay(CompetitiveTrustTheme.border)

            Toggle(isOn: $paymentConsentAccepted) {
                Text(paymentConsentText)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.switch)
            .disabled(store.pendingPaymentIsConfirmed)
            .accessibilityIdentifier("personal.payment.consent")

            Text(
                "Stripe test mode accepts test card details only. No real money moves."
            )
            .font(.caption)
            .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
        }
    }

    private func paymentRule(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.shield")
            .font(.caption)
            .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var paymentConsentText: String {
        let amount = (Double(draft.commitmentAmountMinor) / 100)
            .formatted(.currency(code: "USD"))
        return "By starting, you agree that GameTime may create one \(amount) test charge only if this challenge is confirmed missed after the review window. Missing or unclear step data never counts as a miss."
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
                    : "Seven days, starting at \(startTimeLabel) on day one"
            )
            reviewRow("Time zone", draft.timezone)
            reviewRow("Starts", startDescription)
            if demoMode.isActive, store.pendingCreation == nil {
                Toggle(
                    "Start right now (count today)",
                    isOn: demoStartBinding
                )
                    .tint(CompetitiveTrustTheme.coral)
                    .accessibilityIdentifier("personal.start.demo-now")
                Text("The challenge activates on the current minute, and all eligible steps since midnight today count.")
                    .font(.caption)
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            }
            reviewRow("Updates through", "24 hours after your last day")
            if store.configuration.personalSettlementMode == .stripeSandbox {
                reviewRow("Payment", "Test method saved — ready for review")
                reviewRow(
                    "Review window",
                    "7 days after the result is published"
                )
            }
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
            Text(reviewOutcomeExplanation)
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
                        || !store.hasVerifiedCreationState
                        || !store.healthReadiness.permitsCreation
                        || !isDraftValid
                )
                .accessibilityIdentifier("personal.submit")
            } else if step == .payment {
                if store.pendingPaymentIsConfirmed {
                    Button("Continue") {
                        advance()
                    }
                    .buttonStyle(TrustPrimaryButtonStyle())
                    .accessibilityIdentifier("personal.continue")
                } else {
                    Button {
                        preparePaymentSheet()
                    } label: {
                        if store.isPreparingPayment {
                            ProgressView().tint(.white)
                        } else {
                            Text("Set up test payment")
                        }
                    }
                    .buttonStyle(TrustPrimaryButtonStyle())
                    .disabled(
                        !store.hasVerifiedCreationState
                            || !paymentConsentAccepted
                            || store.isPreparingPayment
                    )
                    .accessibilityIdentifier("personal.payment.setup")
                }
            } else {
                Button("Continue") {
                    advance()
                }
                .buttonStyle(TrustPrimaryButtonStyle())
                .disabled(!canAdvance)
                .accessibilityIdentifier("personal.continue")
            }

            if step != visibleSteps.first {
                Button("Back") {
                    guard
                        let index = visibleSteps.firstIndex(of: step),
                        index > visibleSteps.startIndex
                    else {
                        return
                    }
                    step = visibleSteps[index - 1]
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
        let validationDate = Date()
        return (
            try? betaRequest(
                at: validationDate
            )
        ) != nil
    }

    /// A selection sitting in a draft — or restored from a saved retry — can
    /// simply age out of validity while the flow is open.
    private var startIsStillValid: Bool {
        if startsImmediatelyInDemo && demoMode.isActive { return true }
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

    private var startTimeLabel: String {
        draft.startsAt.formatted(
            Date.FormatStyle(
                date: .omitted,
                time: .shortened,
                timeZone: TimeZone(identifier: draft.timezone)
                    ?? TimeZone(secondsFromGMT: 0)!
            )
        )
    }

    private var demoStartBinding: Binding<Bool> {
        Binding(
            get: { startsImmediatelyInDemo },
            set: { startsImmediately in
                startsImmediatelyInDemo = startsImmediately
                now = Date()
                draft.startsAt = startsImmediately
                    ? PersonalChallengeStart.currentMinute(now: now)
                    : PersonalChallengeStart.nextLocalMidnight(
                        now: now,
                        timezone: draft.timezone
                    )
            }
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
        guard let index = visibleSteps.firstIndex(of: step) else {
            step = .review
            return
        }
        let next = visibleSteps.index(after: index) < visibleSteps.endIndex
            ? visibleSteps[visibleSteps.index(after: index)]
            : .review
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
        } else if next == .review {
            refreshBetaStart()
        }
        step = next
    }

    /// The lean beta has one start rule: the server resolves the next local
    /// midnight when a fresh request commits. Keep restored retries exact, but
    /// refresh a new draft before review so leaving the sheet open overnight
    /// cannot turn the hidden default into a stale custom start.
    private func refreshBetaStart(at date: Date = Date()) {
        guard store.pendingCreation == nil else { return }
        now = date
        draft.startsAt = startsImmediatelyInDemo && demoMode.isActive
            ? PersonalChallengeStart.currentMinute(now: date)
            : PersonalChallengeStart.nextLocalMidnight(
                now: date,
                timezone: draft.timezone
            )
    }

    private func betaRequest(
        at date: Date
    ) throws -> PersonalChallengeCreationRequest {
        if let pending = store.pendingCreation {
            return pending.request
        }
        var requestDraft = draft
        requestDraft.startsAt = startsImmediatelyInDemo && demoMode.isActive
            ? PersonalChallengeStart.currentMinute(now: date)
            : PersonalChallengeStart.nextLocalMidnight(
                now: date,
                timezone: requestDraft.timezone
            )
        return try requestDraft.validated(
            requestID: requestID,
            now: date,
            allowsCurrentMinuteStart: startsImmediatelyInDemo
                && demoMode.isActive
        )
    }

    private var reviewOutcomeExplanation: String {
        let base =
            "On a daily challenge you have to hit your goal all seven days. On a weekly one you just have to reach the total by the end. If your steps go missing or don’t add up, the week doesn’t count — and it doesn’t count against you."
        guard store.configuration.personalSettlementMode == .stripeSandbox else {
            return base
        }
        return base
            + " A complete miss stays provisional through the review window. Only a confirmed miss can create one simulated test charge."
    }

    private func preparePaymentSheet() {
        do {
            let requestDate = Date()
            refreshBetaStart(at: requestDate)
            let request = try betaRequest(at: requestDate)
            Task {
                guard let setup = await store.preparePayment(request) else {
                    return
                }
                switch setup.presentation {
                case .alreadyConfirmed:
                    paymentConsentAccepted = true
                    refreshBetaStart()
                    step = .review
                case .paymentSheet(
                    let publishableKey,
                    let setupIntentClientSecret
                ):
                    var configuration = PaymentSheet.Configuration()
                    configuration.apiClient = STPAPIClient(
                        publishableKey: publishableKey
                    )
                    configuration.merchantDisplayName = "Better Bet"
                    configuration.returnURL =
                        store.configuration.stripeReturnURL?.absoluteString
                    configuration.primaryButtonLabel =
                        "Save test payment method"
                    configuration.allowsDelayedPaymentMethods = false
                    paymentSheet = PaymentSheet(
                        setupIntentClientSecret: setupIntentClientSecret,
                        configuration: configuration
                    )
                    paymentSheetSetupID = setup.setupID
                    await Task.yield()
                    showingPaymentSheet = true
                }
            }
        } catch {
            now = Date()
            store.presentedError = error.localizedDescription
        }
    }

    private func handlePaymentSheetResult(_ result: PaymentSheetResult) {
        switch result {
        case .completed:
            guard let setupID = paymentSheetSetupID else {
                store.presentedError =
                    PersonalPaymentClientError.invalidResponse
                    .localizedDescription
                return
            }
            do {
                let requestDate = Date()
                refreshBetaStart(at: requestDate)
                let request = try betaRequest(at: requestDate)
                Task {
                    if await store.confirmPaymentSetup(
                        request: request,
                        setupID: setupID
                    ) {
                        paymentConsentAccepted = true
                        refreshBetaStart()
                        step = .review
                    }
                }
            } catch {
                now = Date()
                store.presentedError = error.localizedDescription
            }
        case .canceled:
            break
        case .failed:
            store.presentedError =
                "Stripe couldn’t save that test payment method. Try again when you’re ready."
        }
    }

    private func submit() {
        do {
            let requestDate = Date()
            refreshBetaStart(at: requestDate)
            let request = try betaRequest(at: requestDate)
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

private struct PersonalPaymentSheetPresenter: View {
    let paymentSheet: PaymentSheet
    @Binding var isPresented: Bool
    let completion: @MainActor (PaymentSheetResult) -> Void

    var body: some View {
        Color.clear
            .paymentSheet(
                isPresented: $isPresented,
                paymentSheet: paymentSheet,
                onCompletion: completion
            )
    }
}
