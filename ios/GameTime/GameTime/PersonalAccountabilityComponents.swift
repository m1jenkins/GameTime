import SwiftUI

struct TestCommitmentDisclosure: View {
    var body: some View {
        Label(
            "Test commitment — no money will be charged.",
            systemImage: "checkmark.shield.fill"
        )
        .font(
            CompetitiveTrustTheme.uiFont(
                size: 13,
                relativeTo: .subheadline,
                weight: .bold
            )
        )
        .foregroundStyle(CompetitiveTrustTheme.sunInk)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CompetitiveTrustTheme.sunTint,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .accessibilityIdentifier("personal.test-only-disclosure")
    }
}

struct PersonalChallengeCard: View {
    let challenge: PersonalChallengeSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DaybreakCard {
                VStack(alignment: .leading, spacing: 14) {
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

                    Text(challenge.terms.targetText)
                        .font(
                            CompetitiveTrustTheme.displayFont(
                                size: 24,
                                relativeTo: .title2
                            )
                        )
                        .tracking(-0.5)

                    if let progress = challenge.progress,
                        challenge.status.isOpen
                    {
                        PersonalProgressBar(
                            progress: progress,
                            terms: challenge.terms
                        )
                    }

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
            "Final sync window ends \(PersonalTermsDateFormatter.dateTime(challenge.terms.evidenceCutoff, timezoneIdentifier: challenge.terms.timezone))"
        case .resultPending:
            "Evidence closed — result pending"
        case .cancelled:
            "Cancelled before start"
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
            case .inconclusive: return "Inconclusive — waived"
            }
        }
        switch status {
        case .scheduled: return "Scheduled"
        case .active: return "Day in progress"
        case .awaitingEvidence: return "Final sync window"
        case .resultPending: return "Result pending"
        case .cancelled: return "Cancelled"
        case .completed: return "Complete"
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
    let progress: PersonalProgress
    let terms: FrozenPersonalTerms

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ProgressView(value: fraction)
                .tint(CompetitiveTrustTheme.coral)
                .accessibilityIdentifier("personal.progress")
            HStack(alignment: .firstTextBaseline) {
                Text("\(progress.trustedSteps.formatted()) trusted steps")
                Spacer(minLength: 8)
                Text("\(progress.remainingSteps.formatted()) remaining")
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

    private var fraction: Double {
        guard terms.targetSteps > 0 else { return 0 }
        if terms.cadence == .daily {
            let current = progress.days.last(where: {
                $0.evidenceState == .inProgress
            })?.trustedSteps ?? progress.days.last?.trustedSteps ?? 0
            return min(1, current / Double(terms.targetSteps))
        }
        return min(1, Double(progress.trustedSteps) / Double(terms.targetSteps))
    }
}

struct PersonalSevenDayTimeline: View {
    let days: [PersonalDayProgress]

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
                    Text(day.displayedTrustedSteps.formatted())
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

    private func icon(for day: PersonalDayProgress) -> String {
        if day.metTarget == true { return "checkmark.circle.fill" }
        switch day.evidenceState {
        case .future: return "circle.dashed"
        case .inProgress: return "figure.walk.circle.fill"
        case .complete: return "xmark.circle.fill"
        case .outageWaived: return "checkmark.shield.fill"
        case .pending: return "clock.fill"
        case .incomplete, .missing, .quarantined, .conflicting, .unresolved:
            return "exclamationmark.triangle.fill"
        }
    }

    private func color(for day: PersonalDayProgress) -> Color {
        if day.metTarget == true { return CompetitiveTrustTheme.mintInk }
        switch day.evidenceState {
        case .future, .pending: return CompetitiveTrustTheme.guide
        case .inProgress: return CompetitiveTrustTheme.coral
        case .outageWaived: return CompetitiveTrustTheme.mintInk
        case .complete, .incomplete, .missing, .quarantined, .conflicting,
            .unresolved:
            return CompetitiveTrustTheme.sunInk
        }
    }

    private func evidenceLabel(for day: PersonalDayProgress) -> String {
        switch day.evidenceState {
        case .future: "Upcoming"
        case .inProgress: "Today so far"
        case .pending: "Awaiting trusted sync"
        case .complete where day.metTarget == true: "Target met"
        case .complete: "Complete evidence · target not met"
        case .incomplete: "Evidence incomplete"
        case .missing: "Evidence missing"
        case .quarantined: "Evidence quarantined"
        case .conflicting: "Evidence conflicting"
        case .unresolved: "Evidence unresolved"
        case .outageWaived: "GameTime outage · waived"
        }
    }
}

struct PersonalEligibilityHoldCard: View {
    let hold: PersonalEligibilityHold?

    var body: some View {
        DaybreakCard(tone: .pledge) {
            VStack(alignment: .leading, spacing: 9) {
                Label(
                    "New challenge paused",
                    systemImage: "exclamationmark.shield.fill"
                )
                .font(
                    CompetitiveTrustTheme.displayFont(
                        size: 19,
                        relativeTo: .headline
                    )
                )
                Text(
                    "A user or device sync issue needs a fresh trusted Health diagnostic before another challenge can begin. Your test commitment is waived while evidence is unresolved."
                )
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 13,
                        relativeTo: .subheadline
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                if let hold {
                    Text("Reason: \(hold.reasonCode.replacingOccurrences(of: "_", with: " "))")
                        .font(.caption)
                        .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
                }
            }
        }
        .accessibilityIdentifier("personal.eligibility-hold")
    }
}
