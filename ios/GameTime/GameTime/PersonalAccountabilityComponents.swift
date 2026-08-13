import SwiftUI

struct PersonalChallengeCard: View {
    let challenge: PersonalChallengeSummary
    let action: () -> Void
    @Environment(PersonalAccountabilityStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            DaybreakCard {
                VStack(alignment: .leading, spacing: 14) {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            PersonalStatusPill(
                                status: challenge.presentationStatus(at: Date()),
                                outcome: challenge.outcome?.kind
                            )
                            Text(challenge.terms.commitmentText)
                                .font(
                                    CompetitiveTrustTheme.displayFont(
                                        size: 20,
                                        relativeTo: .headline
                                    )
                                )
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            PersonalStatusPill(
                                status: challenge.presentationStatus(at: Date()),
                                outcome: challenge.outcome?.kind
                            )
                            Spacer(minLength: 8)
                            Text(challenge.terms.commitmentText)
                                .font(
                                    CompetitiveTrustTheme.displayFont(
                                        size: 20,
                                        relativeTo: .headline
                                    )
                                )
                        }
                    }

                    Text(challenge.terms.targetText)
                        .font(
                            CompetitiveTrustTheme.displayFont(
                                size: 24,
                                relativeTo: .title2
                            )
                        )
                        .tracking(-0.5)

                    if let progress = store.displayedProgress(for: challenge) {
                        PersonalProgressBar(
                            progress: progress,
                            terms: challenge.terms
                        )
                    }
                    PersonalHealthProgressStatus(
                        progress: store.displayedProgress(for: challenge),
                        terms: challenge.terms,
                        status: challenge.presentationStatus(at: Date()),
                        policy: challenge.stepDataPolicy,
                        outcome: challenge.outcome
                    )

                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .accessibilityHidden(true)
                        Text(dateSummary)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .accessibilityHidden(true)
                    }
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 12,
                            relativeTo: .caption,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            "personal.challenge.\(challenge.id.uuidString.lowercased())"
        )
    }

    private var dateSummary: String {
        switch challenge.presentationStatus(at: Date()) {
        case .scheduled:
            "Starts \(PersonalTermsDateFormatter.day(challenge.terms.startsAt, timezoneIdentifier: challenge.terms.timezone))"
        case .active:
            "Ends \(PersonalTermsDateFormatter.day(challenge.terms.endsAt, timezoneIdentifier: challenge.terms.timezone))"
        case .awaitingEvidence:
            "Updates through \(PersonalTermsDateFormatter.dateTime(challenge.terms.evidenceCutoff, timezoneIdentifier: challenge.terms.timezone))"
        case .resultPending:
            "Working out how you did"
        case .cancelled:
            "Cancelled"
        case .completed:
            "Completed \(PersonalTermsDateFormatter.day(challenge.terms.closedAt ?? challenge.terms.evidenceCutoff, timezoneIdentifier: challenge.terms.timezone))"
        }
    }
}

struct PersonalStatusPill: View {
    let status: PersonalChallengePresentationStatus
    let outcome: PersonalOutcomeKind?

    var body: some View {
        TrustStatusPill(text: text, kind: kind)
    }

    private var text: String {
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

    private var presentation: PersonalProgressPresentation {
        PersonalProgressPresentation(progress: progress, terms: terms)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ProgressView(value: presentation.fraction)
                .tint(CompetitiveTrustTheme.coral)
                .accessibilityLabel(Text(presentation.accessibilityLabel))
                .accessibilityValue(Text(presentation.accessibilityValue))
                .accessibilityIdentifier("personal.progress")
            HStack(alignment: .firstTextBaseline) {
                Text(presentation.stepsText)
                    .accessibilityIdentifier("personal.progress.steps")
                Spacer(minLength: 8)
                Text(presentation.remainingText)
                    .accessibilityIdentifier("personal.progress.remaining")
            }
            .font(
                CompetitiveTrustTheme.uiFont(
                    size: 12,
                    relativeTo: .caption,
                    weight: .semibold
                )
            )
            .foregroundStyle(CompetitiveTrustTheme.secondaryText)
        }
    }
}

/// Keeps every primary progress value in one time scope. Daily challenges use
/// the current day's total; weekly challenges use the seven-day total.
struct PersonalProgressPresentation: Equatable {
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

        accessibilityValue = "\(stepsText). \(remainingText)."
        fraction = target > 0
            ? min(1, Double(steps) / Double(target))
            : 0
    }
}

struct PersonalHealthProgressStatus: View {
    let progress: PersonalDisplayedProgress?
    let terms: FrozenPersonalTerms
    let status: PersonalChallengePresentationStatus
    let policy: PersonalStepDataPolicy
    let outcome: PersonalOutcome?

    @ViewBuilder
    var body: some View {
        if policy.usesAutomaticHealthProgress {
            Label(message, systemImage: symbol)
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 11.5,
                        relativeTo: .caption,
                        weight: .semibold
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("personal.health.status")
        }
    }

    private var message: String {
        if isMissingFinalHealthData {
            return "No Apple Health step data was available for the final result."
        }
        if progress?.isFrozen == true {
            return "Final result from Apple Health"
        }
        if (status == .awaitingEvidence || status == .resultPending),
            Date() < terms.evidenceCutoff
        {
            return "We’ll keep checking Apple Health through \(PersonalTermsDateFormatter.dateTime(terms.evidenceCutoff, timezoneIdentifier: terms.timezone))."
        }
        if status == .resultPending {
            return "Final result is being prepared."
        }
        if let progress, let observedAt = progress.observedAt {
            let update = "Updated from Apple Health \(observedAt.formatted(.relative(presentation: .named)))"
            return progress.isStale ? "\(update) · Update delayed" : update
        }
        return "No step data available yet. Check Apple Health access in Settings."
    }

    private var symbol: String {
        if isMissingFinalHealthData { return "exclamationmark.circle" }
        if progress?.isFrozen == true { return "checkmark.circle.fill" }
        if progress == nil { return "exclamationmark.circle" }
        return progress?.isStale == true
            ? "clock.badge.exclamationmark"
            : "heart.fill"
    }

    private var isMissingFinalHealthData: Bool {
        status == .completed
            && outcome?.kind == .inconclusive
            && outcome?.reasonCode == "missing_health_data"
            && progress == nil
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
                            CompetitiveTrustTheme.uiFont(
                                size: 14,
                                relativeTo: .subheadline,
                                weight: .semibold
                            )
                        )
                }
                .padding(.vertical, 11)
                .accessibilityElement(children: .combine)

                if index < days.count - 1 {
                    Divider().overlay(CompetitiveTrustTheme.border)
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
        DaybreakCard(tone: .pledge) {
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
        }
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
