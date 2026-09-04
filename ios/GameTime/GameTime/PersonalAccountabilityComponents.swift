import Accessibility
import SwiftUI

/// Paper-ledger summary for Challenges history. The goal is the title;
/// money is a receipt, never the hero.
struct PersonalChallengeHistoryCardPresentation: Equatable {
    let statusText: String
    let targetText: String
    let dateSummary: String
    let receiptText: String
    let showsProgress: Bool
    let showsHealth: Bool
    let health: PersonalHealthProgressPresentation

    init(
        challenge: PersonalChallengeSummary,
        progress: PersonalDisplayedProgress?,
        uploadDelayed: Bool,
        now: Date
    ) {
        let status = challenge.presentationStatus(at: now)
        statusText = Self.statusText(
            status: status,
            outcome: challenge.outcome?.kind
        )
        targetText = challenge.terms.targetText
        dateSummary = Self.dateSummary(for: challenge, status: status)
        receiptText = [
            challenge.terms.commitmentText,
            challenge.terms.cadence.title,
        ].joined(separator: " · ")
        switch status {
        case .completed, .cancelled:
            showsProgress = false
        case .scheduled, .active, .awaitingEvidence, .resultPending:
            showsProgress = progress != nil
        }
        health = PersonalHealthProgressPresentation(
            progress: progress,
            terms: challenge.terms,
            status: status,
            outcome: challenge.outcome,
            uploadDelayed: uploadDelayed,
            now: now
        )
        if challenge.stepDataPolicy.usesAutomaticHealthProgress {
            switch health.state {
            case .frozen:
                showsHealth = false
            case .scheduled, .active, .stale, .uploadDelayed, .cutoff,
                .resultPending, .missingFinalData, .cancelled:
                showsHealth = true
            }
        } else {
            showsHealth = false
        }
    }

    static func statusText(
        status: PersonalChallengePresentationStatus,
        outcome: PersonalOutcomeKind?
    ) -> String {
        if let outcome {
            switch outcome {
            case .metGoal: return "Goal met"
            case .missedGoal: return "Goal missed"
            case .inconclusive: return "Didn’t count"
            }
        }
        switch status {
        case .scheduled: return "Scheduled"
        case .active: return "In progress"
        case .awaitingEvidence: return "Waiting on steps"
        case .resultPending: return "Almost done"
        case .cancelled: return "Cancelled"
        case .completed: return "Done"
        }
    }

    private static func dateSummary(
        for challenge: PersonalChallengeSummary,
        status: PersonalChallengePresentationStatus
    ) -> String {
        let timezone = challenge.terms.timezone
        switch status {
        case .scheduled:
            return "Starts \(PersonalTermsDateFormatter.day(challenge.terms.startsAt, timezoneIdentifier: timezone))"
        case .active:
            return "Ends \(PersonalTermsDateFormatter.day(challenge.terms.endsAt, timezoneIdentifier: timezone))"
        case .awaitingEvidence:
            return "Updates through \(PersonalTermsDateFormatter.dateTime(challenge.terms.evidenceCutoff, timezoneIdentifier: timezone))"
        case .resultPending:
            return "Working out how you did"
        case .cancelled:
            return "Cancelled"
        case .completed:
            return "Completed \(PersonalTermsDateFormatter.day(challenge.terms.closedAt ?? challenge.terms.evidenceCutoff, timezoneIdentifier: timezone))"
        }
    }
}

struct PersonalChallengeCard: View {
    let challenge: PersonalChallengeSummary
    let action: () -> Void
    @Environment(PersonalAccountabilityStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let now = Date()
        let progress = store.displayedProgress(for: challenge, now: now)
        let status = challenge.presentationStatus(at: now)
        let card = PersonalChallengeHistoryCardPresentation(
            challenge: challenge,
            progress: progress,
            uploadDelayed: challenge.id == store.stepProgress.challengeID
                && store.stepProgress.lastUploadError != nil,
            now: now
        )

        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            PersonalStatusPill(
                                status: status,
                                outcome: challenge.outcome?.kind
                            )
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
                                .accessibilityHidden(true)
                        }
                        Text(card.targetText)
                            .font(
                                CompetitiveTrustTheme.displayFont(
                                    size: 19,
                                    relativeTo: .headline
                                )
                            )
                            .foregroundStyle(CompetitiveTrustTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        PersonalStatusPill(
                            status: status,
                            outcome: challenge.outcome?.kind
                        )
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
                            .accessibilityHidden(true)
                    }
                    Text(card.targetText)
                        .font(
                            CompetitiveTrustTheme.displayFont(
                                size: 22,
                                relativeTo: .title2
                            )
                        )
                        .foregroundStyle(CompetitiveTrustTheme.primaryText)
                        .tracking(-0.5)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if card.showsProgress, let progress {
                    PersonalProgressBar(
                        progress: progress,
                        terms: challenge.terms
                    )
                }
                if card.showsHealth {
                    PersonalHealthProgressStatus(
                        presentation: card.health,
                        policy: challenge.stepDataPolicy
                    )
                }

                Text(card.dateSummary)
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 13,
                            relativeTo: .footnote,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(card.receiptText)
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 13,
                            relativeTo: .footnote,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(CompetitiveTrustTheme.money)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .trustCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            "personal.challenge.\(challenge.id.uuidString.lowercased())"
        )
    }
}

struct PersonalStatusPill: View {
    let status: PersonalChallengePresentationStatus
    let outcome: PersonalOutcomeKind?

    var body: some View {
        TrustStatusPill(text: text, kind: kind)
    }

    private var text: String {
        PersonalChallengeHistoryCardPresentation.statusText(
            status: status,
            outcome: outcome
        )
    }

    private var kind: TrustStatusPill.Kind {
        if let outcome {
            switch outcome {
            case .metGoal: return .positive
            case .missedGoal: return .action
            case .inconclusive: return .neutral
            }
        }
        switch status {
        case .scheduled, .completed, .cancelled: return .neutral
        case .active: return .live
        case .awaitingEvidence: return .action
        case .resultPending: return .action
        }
    }
}

struct PersonalProgressBar: View {
    let progress: PersonalDisplayedProgress
    let terms: FrozenPersonalTerms
    var showsFacts: Bool = true

    @Environment(\.daybreakSecondaryForeground)
    private var secondaryForeground
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var presentation: PersonalProgressPresentation {
        PersonalProgressPresentation(progress: progress, terms: terms)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ProgressView(value: presentation.fraction)
                .tint(CompetitiveTrustTheme.pine)
                .accessibilityLabel(Text(presentation.accessibilityLabel))
                .accessibilityValue(Text(presentation.accessibilityValue))
                .accessibilityIdentifier("personal.progress")
            if showsFacts {
                progressFacts
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 12,
                            relativeTo: .caption,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(secondaryForeground)
            }
        }
    }

    @ViewBuilder
    private var progressFacts: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                progressFactContents
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                progressFactContents
            }
        }
    }

    @ViewBuilder
    private var progressFactContents: some View {
        Text(presentation.stepsText)
            .accessibilityIdentifier("personal.progress.steps")
        if !dynamicTypeSize.isAccessibilitySize {
            Spacer(minLength: 8)
        }
        Text(presentation.remainingText)
            .accessibilityIdentifier("personal.progress.remaining")
    }
}

/// Keeps every primary progress value in one time scope. Daily challenges use
/// the current day's total; weekly challenges use the seven-day total.
struct PersonalProgressPresentation: Equatable {
    let displayedSteps: Int
    let stepsText: String
    let remainingText: String
    let accessibilityLabel: String
    let accessibilityValue: String
    let fraction: Double

    init(
        progress: PersonalDisplayedProgress,
        terms: FrozenPersonalTerms
    ) {
        let target = max(0, terms.targetSteps)
        let steps: Int
        let remaining: Int

        switch terms.cadence {
        case .daily:
            let current = progress.days.first(where: {
                $0.state == .current
            })
            let displayedDay = current
                ?? progress.days.last(where: { $0.state != .future })
            steps = max(0, displayedDay?.totalSteps ?? 0)
            remaining = max(0, target - steps)

            if current != nil {
                stepsText = "\(steps.formatted()) steps today"
                remainingText = "\(remaining.formatted()) to today’s goal"
                accessibilityLabel = "Today’s progress"
            } else if displayedDay != nil {
                stepsText = "\(steps.formatted()) steps on the last day"
                remainingText = "\(remaining.formatted()) to the daily goal"
                accessibilityLabel = "Last day’s progress"
            } else {
                stepsText = "No steps counted yet"
                remainingText = "\(target.formatted())-step daily goal"
                accessibilityLabel = "Daily progress"
            }
        case .cumulative:
            steps = max(0, progress.totalSteps)
            remaining = max(0, progress.remainingSteps)
            stepsText = "\(steps.formatted()) steps this week"
            remainingText = "\(remaining.formatted()) to this week’s goal"
            accessibilityLabel = "Week progress"
        }

        displayedSteps = steps
        accessibilityValue = "\(stepsText). \(remainingText)."
        fraction = target > 0
            ? min(1, Double(steps) / Double(target))
            : 0
    }
}

/// Pure UI state for Apple Health progress. Numeric progress is resolved before
/// this boundary; this type only chooses honest lifecycle copy and semantics.
struct PersonalHealthProgressPresentation: Equatable {
    enum State: Equatable {
        case scheduled
        case active
        case stale
        case uploadDelayed
        case cutoff
        case resultPending
        case frozen
        case missingFinalData
        case cancelled
    }

    let state: State
    let message: String
    let symbol: String
    let needsNoDataRecovery: Bool

    init(
        progress: PersonalDisplayedProgress?,
        terms: FrozenPersonalTerms,
        status: PersonalChallengePresentationStatus,
        outcome: PersonalOutcome?,
        uploadDelayed: Bool,
        now: Date
    ) {
        if status == .cancelled {
            state = .cancelled
            message =
                "Apple Health updates stopped when this challenge was cancelled."
            symbol = "xmark.circle"
            needsNoDataRecovery = false
            return
        }
        if status == .completed {
            if outcome?.kind == .inconclusive,
                outcome?.reasonCode == "missing_health_data",
                progress == nil
            {
                state = .missingFinalData
                message =
                    "No Apple Health step data was available for the final result."
                symbol = "exclamationmark.circle"
            } else {
                state = .frozen
                message = progress == nil
                    ? "Final result is locked."
                    : "Final result from Apple Health"
                symbol = "checkmark.circle.fill"
            }
            needsNoDataRecovery = false
            return
        }
        if status == .scheduled {
            state = .scheduled
            message = "Apple Health updates begin when this challenge starts."
            symbol = "calendar"
            needsNoDataRecovery = false
            return
        }
        if status == .awaitingEvidence {
            if now < terms.evidenceCutoff {
                state = .cutoff
                message =
                    "We’ll keep checking Apple Health through \(PersonalTermsDateFormatter.dateTime(terms.evidenceCutoff, timezoneIdentifier: terms.timezone))."
                symbol = "clock"
            } else {
                state = .resultPending
                message = "Final result is being prepared."
                symbol = "clock.badge.checkmark"
            }
            needsNoDataRecovery = false
            return
        }
        if status == .resultPending {
            state = .resultPending
            message = "Final result is being prepared."
            symbol = "clock.badge.checkmark"
            needsNoDataRecovery = false
            return
        }
        if progress?.isFrozen == true {
            state = .frozen
            message = "Final result from Apple Health"
            symbol = "checkmark.circle.fill"
            needsNoDataRecovery = false
            return
        }
        if progress?.isStale == true {
            state = .stale
            if let observedAt = progress?.observedAt {
                message =
                    "Last updated \(Self.relativeText(observedAt, now: now)) · Apple Health is temporarily unavailable."
            } else {
                message =
                    "Apple Health is temporarily unavailable. Your last update is still here."
            }
            symbol = "clock.badge.exclamationmark"
            needsNoDataRecovery = false
            return
        }
        if uploadDelayed {
            state = .uploadDelayed
            if let observedAt = progress?.observedAt {
                message =
                    "Updated from Apple Health \(Self.relativeText(observedAt, now: now)) · This update will be sent when connectivity returns."
            } else {
                message =
                    "Your latest Apple Health update is saved on this phone and will be sent when connectivity returns."
            }
            symbol = "wifi.slash"
            needsNoDataRecovery = false
            return
        }

        state = .active
        if let observedAt = progress?.observedAt {
            message =
                "Updated from Apple Health \(Self.relativeText(observedAt, now: now))"
            symbol = "heart.fill"
            needsNoDataRecovery = false
        } else {
            message = "No step data available yet."
            symbol = "exclamationmark.circle"
            needsNoDataRecovery = true
        }
    }

    private static func relativeText(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

struct PersonalHealthProgressStatus: View {
    let presentation: PersonalHealthProgressPresentation
    let policy: PersonalStepDataPolicy

    @Environment(\.daybreakSecondaryForeground)
    private var secondaryForeground

    @ViewBuilder
    var body: some View {
        if policy.usesAutomaticHealthProgress {
            Label(presentation.message, systemImage: presentation.symbol)
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 11.5,
                        relativeTo: .caption,
                        weight: .semibold
                    )
                )
                .foregroundStyle(secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(presentation.message)
                .accessibilityIdentifier("personal.health.status")
        }
    }
}

@MainActor
enum PersonalAccessibilityAnnouncements {
    static func post(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }

    static func postRefreshResult(
        loadState: ScreenLoadState,
        healthError: String?
    ) {
        switch loadState {
        case .failed:
            post("Refresh failed. Your last available information is still here.")
        case .idle, .loading, .loaded, .empty:
            if healthError != nil {
                post(
                    "Refresh finished. Apple Health is temporarily unavailable, and your last update is still here."
                )
            } else {
                post("Progress refreshed.")
            }
        }
    }
}

struct PendingPersonalCancellationRecoveryCard: View {
    let challengeID: UUID?
    let contactSupport: (() -> Void)?

    @Environment(PersonalAccountabilityStore.self) private var store
    @State private var runningAction: Action?

    init(
        challengeID: UUID? = nil,
        contactSupport: (() -> Void)? = nil
    ) {
        self.challengeID = challengeID
        self.contactSupport = contactSupport
    }

    var body: some View {
        if shouldShow {
            VStack(alignment: .leading, spacing: 11) {
                Label(
                    "Cancellation saved — still trying.",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(
                    CompetitiveTrustTheme.displayFont(
                        size: 19,
                        relativeTo: .headline
                        )
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "Cancellation saved — still trying."
                )
                .accessibilityIdentifier("personal.cancellation.pending")
                Text(recoveryMessage)
                    .font(.subheadline)
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: retryCancellation) {
                    mutationLabel(
                        idle: "Retry Cancellation",
                        pending: "Retrying cancellation…",
                        action: .retry
                    )
                }
                .buttonStyle(TrustPrimaryButtonStyle())
                .disabled(actionsAreDisabled)
                .accessibilityIdentifier("personal.cancellation.retry")

                Button(action: refreshTruth) {
                    mutationLabel(
                        idle: "Refresh",
                        pending: "Refreshing…",
                        action: .refresh
                    )
                }
                .buttonStyle(TrustSecondaryButtonStyle())
                .disabled(actionsAreDisabled)
                .accessibilityIdentifier("personal.cancellation.refresh")

                if let contactSupport {
                    Button("Contact Support", action: contactSupport)
                        .buttonStyle(TrustSecondaryButtonStyle())
                        .disabled(actionsAreDisabled)
                        .accessibilityIdentifier(
                            "personal.cancellation.support"
                        )
                }
            }
            .trustCard()
        }
    }

    private enum Action: Equatable {
        case retry
        case refresh
    }

    private var shouldShow: Bool {
        if let challengeID {
            return store.pendingCancellation?.challengeID == challengeID
        }
        return store.pendingCancellation != nil
            || store.hasPendingCancellationRecoveryIssue
    }

    private var recoveryMessage: String {
        if store.hasPendingCancellationRecoveryIssue,
            store.pendingCancellation == nil
        {
            return "GameTime can’t safely read the cancellation saved on this phone yet. Starting another challenge stays paused until we know what happened."
        }
        return "Your cancellation is saved on this phone. We’ll keep using the same request until it is confirmed."
    }

    private var actionsAreDisabled: Bool {
        runningAction != nil || store.isMutating || store.isRestoringSavedState
    }

    private func mutationLabel(
        idle: String,
        pending: String,
        action: Action
    ) -> some View {
        HStack(spacing: 8) {
            if runningAction == action {
                ProgressView()
            }
            Text(runningAction == action ? pending : idle)
        }
        .frame(maxWidth: .infinity)
    }

    private func retryCancellation() {
        guard !actionsAreDisabled else { return }
        runningAction = .retry
        Task { @MainActor in
            let succeeded: Bool
            if store.pendingCancellation != nil {
                succeeded = await store.retryPendingCancellation()
            } else {
                succeeded = await store.retryPendingCancellationRecovery()
            }
            runningAction = nil
            PersonalAccessibilityAnnouncements.post(
                succeeded
                    ? "Cancellation confirmed."
                    : "Cancellation is still saved. We’ll keep trying."
            )
        }
    }

    private func refreshTruth() {
        guard !actionsAreDisabled else { return }
        runningAction = .refresh
        Task { @MainActor in
            await store.refresh()
            runningAction = nil
            PersonalAccessibilityAnnouncements.postRefreshResult(
                loadState: store.loadState,
                healthError: store.stepProgress.lastHealthError
            )
        }
    }
}

struct PersonalSevenDayTimeline: View {
    let days: [PersonalDisplayedDay]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                HStack(spacing: 12) {
                    Image(systemName: icon(for: day))
                        .foregroundStyle(color(for: day))
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dayLabel(index: index, localDate: day.localDate))
                            .font(
                                CompetitiveTrustTheme.uiFont(
                                    size: 14,
                                    relativeTo: .subheadline,
                                    weight: .bold
                                )
                            )
                        Text(evidenceLabel(for: day))
                            .font(
                                CompetitiveTrustTheme.uiFont(
                                    size: 12,
                                    relativeTo: .caption
                                )
                            )
                            .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                    }
                    Spacer(minLength: 8)
                    Text(day.totalSteps.formatted())
                        .font(
                            CompetitiveTrustTheme.tabularFont(
                                size: 14,
                                weight: .bold
                            )
                        )
                }
                .padding(.vertical, 11)
                .accessibilityElement(children: .combine)

                if index < days.count - 1 {
                    Divider().overlay(CompetitiveTrustTheme.hairlineDivider)
                }
            }
        }
    }

    private func dayLabel(index: Int, localDate: String) -> String {
        "Day \(index + 1) · \(localDate)"
    }

    private func icon(for day: PersonalDisplayedDay) -> String {
        if day.metTarget == true { return "checkmark.circle.fill" }
        if day.state == .complete, day.metTarget == nil {
            return "circle.fill"
        }
        switch day.state {
        case .future: return "circle.dashed"
        case .current: return "figure.walk.circle.fill"
        case .complete: return "xmark.circle.fill"
        }
    }

    private func color(for day: PersonalDisplayedDay) -> Color {
        if day.metTarget == true { return CompetitiveTrustTheme.mintInk }
        if day.state == .complete, day.metTarget == nil {
            return CompetitiveTrustTheme.guide
        }
        switch day.state {
        case .future: return CompetitiveTrustTheme.guide
        case .current: return CompetitiveTrustTheme.coral
        case .complete: return CompetitiveTrustTheme.sunInk
        }
    }

    private func evidenceLabel(for day: PersonalDisplayedDay) -> String {
        switch day.state {
        case .future: "Coming up"
        case .current: "Today so far"
        case .complete where day.metTarget == true: "Goal met"
        case .complete: "Day complete"
        }
    }
}

struct LegacyPersonalReadinessNotice: View {
    let hold: PersonalEligibilityHold?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(
                "New challenges are paused",
                systemImage: "exclamationmark.shield.fill"
            )
            .font(
                CompetitiveTrustTheme.displayFont(
                    size: 19,
                    relativeTo: .headline
                )
            )
            Text(
                "Something is wrong with the steps coming from your phone. Run a Health check to start another challenge — and don’t worry, your last one doesn’t count against you."
            )
            .font(
                CompetitiveTrustTheme.uiFont(
                    size: 13,
                    relativeTo: .subheadline
                )
            )
            .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            if let hold, let reason = PersonalReasonText.sentence(
                for: hold.reasonCode
            ) {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
            }
        }
        .trustCard()
        .accessibilityIdentifier("personal.legacy-hold")
    }
}

/// Server reason codes are stable identifiers, not sentences. Say what each
/// known one means in plain words; show an unknown code as a support
/// reference rather than dressing it up as English.
enum PersonalReasonText {
    static func sentence(for reasonCode: String) -> String? {
        let code = reasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return nil }
        switch code {
        case "missing_health_data":
            return "Apple Health didn’t have step data available for this challenge."
        case "missing":
            return "We never received steps for part of your week."
        case "incomplete":
            return "Some hours of your week never arrived."
        case "quarantined":
            return "Some of your steps didn’t look like they came from your Apple devices."
        case "conflicting":
            return "The steps we received didn’t add up."
        case "unresolved":
            return "We’re still sorting out some of your steps."
        case "unresolved_device_update":
            return "Your phone stopped sending steps for a while."
        case "outage_waived":
            return "This was a problem on our end."
        default:
            return "Reference: \(code)"
        }
    }
}
