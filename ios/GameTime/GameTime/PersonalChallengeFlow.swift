import StripePaymentSheet
import SwiftUI

struct CreatePersonalChallengeFlow: View {
    @Environment(PersonalAccountabilityStore.self) private var store
    @Environment(AppModel.self) private var appModel
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.demoMode) private var demoMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var draft = PersonalChallengeDraft()
    @State private var requestID = UUID()
    @State private var step = Step.cadence
    @State private var showingDiscardConfirmation = false
    @State private var paymentConsentAccepted = false
    @State private var paymentSheet: PaymentSheet?
    @State private var paymentSheetSetupID: String?
    @State private var showingPaymentSheet = false
    @State private var showingReceiptDetails = false
    @State private var initialDraft: PersonalChallengeDraft?
    @State private var initialStartsImmediately = false
    @State private var initialPaymentConsentAccepted = false
    @State private var hasLoadedInitialState = false
    @State private var hasMadeProgress = false
    @State private var showingSetupDiscardConfirmation = false
    @State private var isSettingUpPayment = false
    @State private var isConfirmingPaymentSetup = false
    @State private var isSubmittingChallenge = false
    @State private var isDeletingPendingDraft = false
    @FocusState private var focusedField: FocusedField?
    /// Resampled whenever the start step is entered, so the hours it offers
    /// are the hours still open. Submission re-checks against a live clock.
    @State private var now = Date()
    @State private var startsImmediately = false

    private enum FocusedField {
        case target
    }

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
                    EnvironmentDisclosureBanner(
                        settlementMode:
                            store.configuration.personalSettlementMode,
                        isDemo: demoMode.isActive
                    )
                    AthleticCard {
                        stepContent
                    }
                    controls
                }
                .padding(18)
            }
            .scrollDismissesKeyboard(.interactively)
            .athleticScreenChrome()
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { attemptClose() }
                        .disabled(isCreationBusy)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                    .accessibilityIdentifier("personal.target.done")
                }
            }
            .task {
                now = Date()
                if let pending = store.pendingCreation {
                    requestID = pending.request.requestID
                    startsImmediately = pendingUsesStartNow(pending)
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
                captureInitialState()
            }
            .confirmationDialog(
                "Delete this draft?",
                isPresented: $showingDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete draft", role: .destructive) {
                    Task {
                        isDeletingPendingDraft = true
                        DaybreakAccessibility.announce("Deleting draft…")
                        defer { isDeletingPendingDraft = false }
                        if await store.discardPendingCreation() {
                            requestID = UUID()
                            paymentConsentAccepted = false
                            paymentSheet = nil
                            paymentSheetSetupID = nil
                            showingPaymentSheet = false
                            showingReceiptDetails = false
                            startsImmediately = false
                            draft = .initial(
                                profileTimezone: appModel.profile?.timezone,
                                now: Date()
                            )
                            step = .cadence
                            captureInitialState()
                            DaybreakAccessibility.announce("Draft deleted.")
                        } else if let message = store.presentedError {
                            DaybreakAccessibility.announce(message)
                        }
                    }
                }
                Button("Keep it", role: .cancel) {}
            }
            .alert(
                "Discard this setup?",
                isPresented: $showingSetupDiscardConfirmation
            ) {
                Button("Discard changes", role: .destructive) {
                    dismiss()
                }
                Button("Keep editing", role: .cancel) {}
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
            .interactiveDismissDisabled(
                isCreationBusy || hasUnsavedSetupChanges
            )
        }
    }

    private var progressHeader: some View {
        HStack(spacing: 4) {
            ForEach(visibleSteps, id: \.rawValue) { item in
                Rectangle()
                    .fill(
                        (visibleSteps.firstIndex(of: item) ?? 0)
                            <= (visibleSteps.firstIndex(of: step) ?? 0)
                        ? CompetitiveTrustTheme.signalOrange
                        : CompetitiveTrustTheme.hairlineDivider
                    )
                    .frame(height: 4)
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
                        athleticCadenceChoice(cadence)
                    }
                    .buttonStyle(.plain)
                    .daybreakTappableRow()
                    .accessibilityIdentifier("personal.cadence.\(cadence.rawValue)")
                    .accessibilityValue(
                        draft.cadence == cadence
                            ? "Selected"
                            : "Not selected"
                    )
                }
            }
        case .target:
            targetContent
        case .commitment:
            commitmentContent
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

    private func athleticCadenceChoice(_ cadence: PersonalChallengeCadence) -> some View {
        let selected = draft.cadence == cadence
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: cadence == .daily ? "calendar.day.timeline.left" : "sum")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(
                    selected
                        ? CompetitiveTrustTheme.signalOrange
                        : CompetitiveTrustTheme.secondaryText
                )
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(cadence.title)
                    .font(CompetitiveTrustTheme.uiFont(size: 16, relativeTo: .headline, weight: .bold))
                    .foregroundStyle(CompetitiveTrustTheme.primaryText)
                Text(
                    cadence == .daily
                        ? "Hit your goal every single day."
                        : "Hit one total by the end of the week."
                )
                .font(CompetitiveTrustTheme.uiFont(size: 13, relativeTo: .subheadline, weight: .regular))
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            }
            Spacer(minLength: 8)
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(CompetitiveTrustTheme.signalOrange)
            }
        }
        .padding(14)
        .background(CompetitiveTrustTheme.graphiteSurface)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(
                    selected
                        ? CompetitiveTrustTheme.signalOrange
                        : CompetitiveTrustTheme.hairlineDivider,
                    lineWidth: selected ? 1.5 : 1
                )
        )
    }

    private var targetContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.cadence == .daily
                ? "Steps you’ll walk each day"
                : "Steps you’ll walk over the week")
                .font(CompetitiveTrustTheme.monoFont(size: 12, weight: .bold))
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                .tracking(0.5)

            HStack {
                TextField(
                    "Step goal",
                    value: $draft.targetSteps,
                    format: .number
                )
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .target)
                .font(CompetitiveTrustTheme.tabularFont(size: 36, weight: .bold))
                .foregroundStyle(CompetitiveTrustTheme.primaryText)
                .multilineTextAlignment(.leading)
                .accessibilityIdentifier("personal.target")

                Text("steps")
                    .font(CompetitiveTrustTheme.monoFont(size: 14, weight: .bold))
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            }
            .padding(14)
            .background(CompetitiveTrustTheme.graphiteSurface)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(CompetitiveTrustTheme.hairlineDivider, lineWidth: 1)
            )

            HStack(spacing: 8) {
                let presets = draft.cadence == .daily
                    ? [7000, 10000, 12500, 15000]
                    : [50000, 70000, 100000]
                ForEach(presets, id: \.self) { preset in
                    Button {
                        draft.targetSteps = preset
                    } label: {
                        Text(preset.formatted(.number))
                            .font(CompetitiveTrustTheme.tabularFont(size: 13, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                draft.targetSteps == preset
                                    ? CompetitiveTrustTheme.signalOrange.opacity(0.15)
                                    : CompetitiveTrustTheme.graphiteSurface
                            )
                            .foregroundStyle(
                                draft.targetSteps == preset
                                    ? CompetitiveTrustTheme.signalOrange
                                    : CompetitiveTrustTheme.secondaryText
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(
                                        draft.targetSteps == preset
                                            ? CompetitiveTrustTheme.signalOrange
                                            : CompetitiveTrustTheme.hairlineDivider,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Pick any whole number from 1 to 1,000,000.")
                .font(CompetitiveTrustTheme.uiFont(size: 12, relativeTo: .caption, weight: .regular))
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
        }
    }

    private var commitmentContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SELECT COMMITMENT STAKE")
                .font(CompetitiveTrustTheme.monoFont(size: 12, weight: .bold))
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                .tracking(0.5)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    ForEach(
                        PersonalChallengeDraft.allowedCommitmentAmountsMinor,
                        id: \.self
                    ) { amount in
                        commitmentSegmentButton(amount)
                        if amount != PersonalChallengeDraft.allowedCommitmentAmountsMinor.last {
                            Divider().overlay(CompetitiveTrustTheme.hairlineDivider)
                        }
                    }
                }
                .background(CompetitiveTrustTheme.graphiteSurface)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(CompetitiveTrustTheme.hairlineDivider, lineWidth: 1)
                )
            } else {
                HStack(spacing: 0) {
                    ForEach(
                        PersonalChallengeDraft.allowedCommitmentAmountsMinor,
                        id: \.self
                    ) { amount in
                        commitmentSegmentButton(amount)
                        if amount != PersonalChallengeDraft.allowedCommitmentAmountsMinor.last {
                            Rectangle()
                                .fill(CompetitiveTrustTheme.hairlineDivider)
                                .frame(width: 1)
                        }
                    }
                }
                .background(CompetitiveTrustTheme.graphiteSurface)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(CompetitiveTrustTheme.hairlineDivider, lineWidth: 1)
                )
            }

            Label(
                commitmentProtection.text,
                systemImage: "checkmark.shield"
            )
            .font(CompetitiveTrustTheme.uiFont(size: 13, relativeTo: .caption, weight: .medium))
            .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("personal.commitment.protection")
        }
    }

    private func commitmentSegmentButton(_ amount: Int) -> some View {
        let isSelected = draft.commitmentAmountMinor == amount
        return Button {
            draft.commitmentAmountMinor = amount
        } label: {
            Text(
                (Double(amount) / 100)
                    .formatted(.currency(code: "USD"))
            )
            .font(CompetitiveTrustTheme.tabularFont(size: 15, weight: .bold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                isSelected
                    ? CompetitiveTrustTheme.signalOrange
                    : CompetitiveTrustTheme.graphiteSurface
            )
            .foregroundStyle(
                isSelected
                    ? Color.black
                    : CompetitiveTrustTheme.primaryText
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("personal.commitment.\(amount)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    @ViewBuilder
    private var startContent: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(
                "Pick the day and time your week starts (\(draft.timezone))."
            )
            .font(CompetitiveTrustTheme.uiFont(size: 14, relativeTo: .subheadline, weight: .medium))
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

            Divider().overlay(CompetitiveTrustTheme.hairlineDivider)

            Text(startConsequence)
                .font(CompetitiveTrustTheme.uiFont(size: 12, relativeTo: .caption, weight: .regular))
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

    /// A start-now request is frozen at the current minute immediately before
    /// its pending record is saved. A scheduled start is in the future when
    /// saved, even if that hour has passed by the time recovery opens.
    private func pendingUsesStartNow(
        _ pending: PendingPersonalChallengeSubmission
    ) -> Bool {
        guard let startsAt = pending.request.startsAt else { return false }
        let savedAfterStart = pending.createdAt.timeIntervalSince(startsAt)
        return (0..<120).contains(savedAfterStart)
    }

    private var firstDayHours: Int {
        PersonalChallengeStart.firstDayHours(
            startsAt: draft.startsAt,
            timezone: draft.timezone
        )
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

    /// The seventh local date always closes at local midnight, so a later
    /// start shortens day one instead of moving the end. Said plainly here
    /// rather than discovered on day one.
    private var startConsequence: String {
        receiptPresentation.dayOneExplanation
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
            .font(CompetitiveTrustTheme.uiFont(size: 14, relativeTo: .subheadline, weight: .regular))
            .foregroundStyle(CompetitiveTrustTheme.secondaryText)

            if !store.healthReadiness.permitsCreation {
                Button(
                    store.isVerifyingHealthAccess
                        ? "Connecting…"
                        : "Connect Apple Health"
                ) {
                    verifyHealthAccess()
                }
                .buttonStyle(TrustSecondaryButtonStyle())
                .disabled(
                    isCreationBusy
                        || !store.configuration.activitySyncEnabled
                )
                .accessibilityIdentifier("personal.health.verify")
            }

            if !store.configuration.activitySyncEnabled {
                Text(
                    "Health connection checks aren’t available yet."
                )
                .font(CompetitiveTrustTheme.uiFont(size: 12, relativeTo: .caption, weight: .regular))
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
                .font(CompetitiveTrustTheme.uiFont(size: 14, relativeTo: .subheadline, weight: .semibold))

            if store.pendingCreation == nil {
                startNowChoice
            }

            VStack(alignment: .leading, spacing: 8) {
                paymentRule(
                    "Saving this test payment method creates no charge."
                )
                paymentRule(
                    "Your test charge is $0 when you meet your goal or step data is missing or unclear."
                )
                paymentRule(
                    "GameTime makes one final Apple Health check 24 hours after your last day."
                )
                paymentRule(
                    "A seven-day review follows a missed goal. Settlement stays paused during review."
                )
            }

            Divider().overlay(CompetitiveTrustTheme.hairlineDivider)

            Toggle(isOn: $paymentConsentAccepted) {
                Text(paymentConsentText)
                    .font(CompetitiveTrustTheme.uiFont(size: 12, relativeTo: .caption, weight: .regular))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.switch)
            .disabled(store.pendingPaymentIsConfirmed)
            .accessibilityIdentifier("personal.payment.consent")
        }
    }

    private func paymentRule(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.shield")
            .font(CompetitiveTrustTheme.uiFont(size: 12, relativeTo: .caption, weight: .regular))
            .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var paymentConsentText: String {
        let amount = (Double(draft.commitmentAmountMinor) / 100)
            .formatted(.currency(code: "USD"))
        return "By starting, you agree that GameTime may create one \(amount) test charge only if this challenge is confirmed missed after the review window. Missing or unclear step data never counts as a miss."
    }

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("This locks in when you start", systemImage: "lock.fill")
                .font(
                    CompetitiveTrustTheme.displayFont(
                        size: 21,
                        relativeTo: .headline
                    )
                )
                .accessibilityIdentifier("personal.receipt")
                .padding(.bottom, 12)

            Divider().overlay(CompetitiveTrustTheme.hairlineDivider)

            ForEach(receiptPresentation.groups) { group in
                receiptGroup(group)

                if group.id == .start, store.pendingCreation == nil {
                    startNowChoice
                        .padding(.bottom, 12)
                }

                if group.id != .payment {
                    Divider().overlay(CompetitiveTrustTheme.hairlineDivider)
                }
            }

            if !startIsStillValid {
                Text(
                    "That start time has already passed. Go back and pick a new one, or delete this draft."
                )
                .font(CompetitiveTrustTheme.uiFont(size: 12, relativeTo: .caption, weight: .semibold))
                .foregroundStyle(CompetitiveTrustTheme.signalOrange)
                .accessibilityIdentifier("personal.review.stale-start")
                .padding(.vertical, 12)
            }

            Divider().overlay(CompetitiveTrustTheme.hairlineDivider)
            receiptDetailsDisclosure
        }
    }

    private func receiptGroup(
        _ group: PersonalChallengeReceiptPresentation.Group
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.title)
                .font(
                    CompetitiveTrustTheme.displayFont(
                        size: 18,
                        relativeTo: .headline
                    )
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 14)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(
                    "personal.receipt.group.\(group.id.rawValue)"
                )

            ForEach(group.facts) { fact in
                receiptFactRow(fact)
                if fact.id != group.facts.last?.id {
                    Divider().overlay(CompetitiveTrustTheme.hairlineDivider)
                }
            }
        }
    }

    private func receiptFactRow(
        _ fact: PersonalChallengeReceiptPresentation.Fact
    ) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 5) {
                    Text(fact.label)
                        .font(CompetitiveTrustTheme.uiFont(size: 14, relativeTo: .subheadline, weight: .semibold))
                    Text(fact.value)
                        .font(CompetitiveTrustTheme.tabularFont(size: 14, weight: .regular))
                        .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(fact.label)
                        .font(CompetitiveTrustTheme.uiFont(size: 14, relativeTo: .subheadline, weight: .semibold))
                    Spacer(minLength: 8)
                    Text(fact.value)
                        .font(CompetitiveTrustTheme.tabularFont(size: 14, weight: .regular))
                        .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("personal.receipt.fact.\(fact.id.rawValue)")
    }

    private var receiptDetailsDisclosure: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    showingReceiptDetails.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
                        .accessibilityHidden(true)
                    Text("More details")
                        .font(CompetitiveTrustTheme.uiFont(size: 14, relativeTo: .subheadline, weight: .semibold))
                    Spacer(minLength: 8)
                    Text(showingReceiptDetails ? "Hide" : "Show")
                        .font(CompetitiveTrustTheme.monoFont(size: 12, weight: .bold))
                        .foregroundStyle(CompetitiveTrustTheme.signalOrange)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .daybreakTappableRow()
            .accessibilityIdentifier("personal.receipt.more-details")
            .accessibilityLabel("More details")
            .accessibilityValue(
                showingReceiptDetails ? "Showing" : "Hidden"
            )
            .accessibilityHint(
                "Shows timing, cancellation, and saved draft details"
            )

            if showingReceiptDetails {
                VStack(alignment: .leading, spacing: 0) {
                    Divider().overlay(CompetitiveTrustTheme.hairlineDivider)
                    ForEach(receiptPresentation.details) { detail in
                        receiptDetail(detail)
                        if detail.id != receiptPresentation.details.last?.id {
                            Divider().overlay(CompetitiveTrustTheme.hairlineDivider)
                        }
                    }
                }
            }
        }
    }

    private func receiptDetail(
        _ detail: PersonalChallengeReceiptPresentation.Detail
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(detail.title)
                .font(CompetitiveTrustTheme.uiFont(size: 12, relativeTo: .caption, weight: .bold))
            Text(detail.text)
                .font(CompetitiveTrustTheme.uiFont(size: 12, relativeTo: .caption, weight: .regular))
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(
            "personal.receipt.detail.\(detail.id.rawValue)"
        )
    }

    private var startNowChoice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(
                "Start right now (count today)",
                isOn: startNowBinding
            )
            .tint(CompetitiveTrustTheme.signalOrange)
            .accessibilityIdentifier("personal.start.now")
            Text("The challenge activates on the current minute, and all eligible steps since midnight today count.")
                .font(CompetitiveTrustTheme.uiFont(size: 12, relativeTo: .caption, weight: .regular))
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if step == .review {
                Button {
                    submit()
                } label: {
                    HStack(spacing: 9) {
                        if isSubmittingChallenge {
                            ProgressView().tint(.white)
                        }
                        Text(
                            isSubmittingChallenge
                                ? "Starting challenge…"
                                : "Start my challenge"
                        )
                    }
                }
                .buttonStyle(TrustPrimaryButtonStyle())
                .disabled(
                    isCreationBusy
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
                    .disabled(isCreationBusy)
                    .accessibilityIdentifier("personal.continue")
                } else {
                    Button {
                        preparePaymentSheet()
                    } label: {
                        HStack(spacing: 9) {
                            if isSettingUpPayment
                                || isConfirmingPaymentSetup
                            {
                                ProgressView().tint(.white)
                            }
                            Text(
                                isSettingUpPayment
                                    || isConfirmingPaymentSetup
                                    ? "Setting up test payment…"
                                    : "Set up test payment"
                            )
                        }
                    }
                    .buttonStyle(TrustPrimaryButtonStyle())
                    .disabled(
                        !store.hasVerifiedCreationState
                            || !paymentConsentAccepted
                            || isCreationBusy
                    )
                    .accessibilityIdentifier("personal.payment.setup")
                }
            } else {
                Button("Continue") {
                    advance()
                }
                .buttonStyle(TrustPrimaryButtonStyle())
                .disabled(!canAdvance || isCreationBusy)
                .accessibilityIdentifier("personal.continue")
            }

            if step != visibleSteps.first {
                HStack(spacing: 10) {
                    Button("Back") {
                        goBack()
                    }
                    .buttonStyle(TrustCompactButtonStyle(tone: .quiet))
                    .disabled(isCreationBusy)
                    .accessibilityIdentifier("personal.back")

                    Spacer(minLength: 8)

                    if step == .review, store.pendingCreation != nil {
                        Button(
                            isDeletingPendingDraft
                                ? "Deleting draft…"
                                : "Delete draft",
                            role: .destructive
                        ) {
                            showingDiscardConfirmation = true
                        }
                        .buttonStyle(TrustCompactButtonStyle(tone: .quiet))
                        .disabled(isCreationBusy)
                        .accessibilityIdentifier(
                            "personal.pending.discard-review"
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var isCreationBusy: Bool {
        store.isVerifyingHealthAccess
            || store.isPreparingPayment
            || store.isMutating
            || isSettingUpPayment
            || isConfirmingPaymentSetup
            || isSubmittingChallenge
            || isDeletingPendingDraft
            || showingPaymentSheet
    }

    private var hasUnsavedSetupChanges: Bool {
        guard
            hasLoadedInitialState,
            store.pendingCreation == nil,
            let initialDraft
        else {
            return false
        }
        return hasMadeProgress
            || draft != initialDraft
            || startsImmediately != initialStartsImmediately
            || paymentConsentAccepted != initialPaymentConsentAccepted
    }

    private func captureInitialState() {
        initialDraft = draft
        initialStartsImmediately = startsImmediately
        initialPaymentConsentAccepted = paymentConsentAccepted
        hasMadeProgress = false
        hasLoadedInitialState = true
    }

    private func attemptClose() {
        focusedField = nil
        guard !isCreationBusy else { return }
        if hasUnsavedSetupChanges {
            showingSetupDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func verifyHealthAccess() {
        focusedField = nil
        DaybreakAccessibility.announce("Connecting…")
        Task {
            let connected = await store.verifyHealthAccess(
                timezone: draft.timezone
            )
            if connected {
                DaybreakAccessibility.announce("Apple Health connected.")
            } else if let message = store.presentedError {
                DaybreakAccessibility.announce(message)
            }
        }
    }

    private func goBack() {
        focusedField = nil
        guard
            let index = visibleSteps.firstIndex(of: step),
            index > visibleSteps.startIndex
        else {
            return
        }
        let previous = visibleSteps[index - 1]
        step = previous
        if previous == .target {
            Task { @MainActor in
                await Task.yield()
                focusedField = .target
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
                        ? CompetitiveTrustTheme.signalOrange
                        : CompetitiveTrustTheme.secondaryText
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
                    .foregroundStyle(CompetitiveTrustTheme.signalOrange)
            }
        }
        .padding(4)
    }

    private var commitmentProtection:
        PersonalCommitmentProtectionPresentation
    {
        PersonalCommitmentProtectionPresentation(
            amountMinor: draft.commitmentAmountMinor,
            settlementMode: store.configuration.personalSettlementMode
        )
    }

    private var receiptPresentation:
        PersonalChallengeReceiptPresentation
    {
        PersonalChallengeReceiptPresentation(
            draft: draft,
            startsImmediately: startsImmediately,
            settlementMode: store.configuration.personalSettlementMode,
            paymentMethodSaved: store.pendingPaymentIsConfirmed,
            hasSavedDraft: store.pendingCreation != nil
        )
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
        if startsImmediately { return true }
        let requested: Date?
        if let pending = store.pendingCreation {
            requested = pending.request.startsAt
        } else {
            requested = draft.requestedStart(now: now)
        }
        guard let requested else { return true }
        return PersonalChallengeStart.isSelectable(
            requested,
            now: Date(),
            timezone: draft.timezone
        )
    }

    private var startNowBinding: Binding<Bool> {
        Binding(
            get: { startsImmediately },
            set: { shouldStartImmediately in
                startsImmediately = shouldStartImmediately
                now = Date()
                draft.startsAt = shouldStartImmediately
                    ? PersonalChallengeStart.currentMinute(now: now)
                    : PersonalChallengeStart.nextLocalMidnight(
                        now: now,
                        timezone: draft.timezone
                    )
            }
        )
    }

    private func advance() {
        focusedField = nil
        if step == .target,
            !PersonalChallengeDraft.targetRange.contains(draft.targetSteps)
        {
            store.presentedError = PersonalChallengeValidationError.invalidTarget
                .localizedDescription
            return
        }
        hasMadeProgress = true
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
        if next == .target {
            Task { @MainActor in
                await Task.yield()
                focusedField = .target
            }
        }
    }

    /// Keep the chosen start mode fresh while preserving an exact saved retry.
    /// A default start is resolved by the server at the next local midnight;
    /// start-now sends the current minute as an explicit intent marker.
    private func refreshBetaStart(at date: Date = Date()) {
        guard store.pendingCreation == nil else { return }
        now = date
        draft.startsAt = startsImmediately
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
        requestDraft.startsAt = startsImmediately
            ? PersonalChallengeStart.currentMinute(now: date)
            : PersonalChallengeStart.nextLocalMidnight(
                now: date,
                timezone: requestDraft.timezone
            )
        return try requestDraft.validated(
            requestID: requestID,
            now: date,
            allowsCurrentMinuteStart: startsImmediately
        )
    }

    private func preparePaymentSheet() {
        focusedField = nil
        do {
            let requestDate = Date()
            refreshBetaStart(at: requestDate)
            let request = try betaRequest(at: requestDate)
            isSettingUpPayment = true
            DaybreakAccessibility.announce("Setting up test payment…")
            Task {
                defer { isSettingUpPayment = false }
                guard let setup = await store.preparePayment(request) else {
                    if let message = store.presentedError {
                        DaybreakAccessibility.announce(message)
                    }
                    return
                }
                switch setup.presentation {
                case .alreadyConfirmed:
                    paymentConsentAccepted = true
                    refreshBetaStart()
                    step = .review
                    DaybreakAccessibility.announce(
                        "Test payment method saved."
                    )
                case .paymentSheet(
                    let publishableKey,
                    let setupIntentClientSecret
                ):
                    var configuration = PaymentSheet.Configuration()
                    configuration.apiClient = STPAPIClient(
                        publishableKey: publishableKey
                    )
                    configuration.merchantDisplayName =
                        GameTimePublicIdentity.name
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
            DaybreakAccessibility.announce(error.localizedDescription)
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
                isConfirmingPaymentSetup = true
                Task {
                    defer { isConfirmingPaymentSetup = false }
                    if await store.confirmPaymentSetup(
                        request: request,
                        setupID: setupID
                    ) {
                        paymentConsentAccepted = true
                        refreshBetaStart()
                        step = .review
                        DaybreakAccessibility.announce(
                            "Test payment method saved."
                        )
                    } else if let message = store.presentedError {
                        DaybreakAccessibility.announce(message)
                    }
                }
            } catch {
                now = Date()
                store.presentedError = error.localizedDescription
                DaybreakAccessibility.announce(error.localizedDescription)
            }
        case .canceled:
            break
        case .failed:
            let message =
                "Stripe couldn’t save that test payment method. Try again when you’re ready."
            store.presentedError = message
            DaybreakAccessibility.announce(message)
        }
    }

    private func submit() {
        focusedField = nil
        do {
            let requestDate = Date()
            refreshBetaStart(at: requestDate)
            let request = try betaRequest(at: requestDate)
            isSubmittingChallenge = true
            DaybreakAccessibility.announce("Starting challenge…")
            Task {
                defer { isSubmittingChallenge = false }
                if let id = await store.create(request) {
                    DaybreakAccessibility.announce("Challenge started.")
                    dismiss()
                    router.openPersonalChallenge(id)
                } else if let message = store.presentedError {
                    DaybreakAccessibility.announce(message)
                }
            }
        } catch {
            now = Date()
            store.presentedError = error.localizedDescription
            DaybreakAccessibility.announce(error.localizedDescription)
        }
    }
}

private struct AthleticCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(CompetitiveTrustTheme.primaryText)
            .background(CompetitiveTrustTheme.graphiteSurface)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(CompetitiveTrustTheme.hairlineDivider, lineWidth: 1)
            )
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

