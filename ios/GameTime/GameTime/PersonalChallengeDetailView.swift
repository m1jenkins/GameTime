import SwiftUI

struct PersonalChallengeDetailView: View {
    let challengeID: UUID

    @Environment(PersonalAccountabilityStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingCancelConfirmation = false
    @State private var selectedReviewReason:
        PersonalReviewReason = .userDisputesStepData

    private var challenge: PersonalChallengeDetail? {
        store.detail(for: challengeID)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                TestCommitmentDisclosure(
                    settlementMode: challenge?.terms.settlementMode
                        ?? store.configuration.personalSettlementMode
                )
                if let challenge {
                    hero(challenge)
                    frozenTerms(challenge.terms)
                    progress(challenge)
                    result(challenge)
                    review(challenge)
                    sync(challenge)
                    cancellation(challenge)
                } else {
                    DaybreakCard {
                        ProgressView("Loading…")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .daybreakScreenChrome()
        .navigationTitle("Your challenge")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: challengeID) {
            await store.loadDetail(challengeID: challengeID)
        }
        .confirmationDialog(
            "Cancel this challenge?",
            isPresented: $showingCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Yes, cancel it", role: .destructive) {
                Task {
                    if await store.cancel(challengeID: challengeID) {
                        dismiss()
                    }
                }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(cancellationMessage)
        }
    }

    private func hero(_ challenge: PersonalChallengeDetail) -> some View {
        DaybreakCard(tone: .inverse) {
            VStack(alignment: .leading, spacing: 15) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        PersonalStatusPill(
                            status: challenge.presentationStatus(at: Date()),
                            outcome: challenge.outcome?.kind
                        )
                        Text(challenge.terms.commitmentText)
                            .font(
                                CompetitiveTrustTheme.displayFont(
                                    size: 24,
                                    relativeTo: .title2
                                )
                            )
                    }
                } else {
                    HStack {
                        PersonalStatusPill(
                            status: challenge.presentationStatus(at: Date()),
                            outcome: challenge.outcome?.kind
                        )
                        Spacer(minLength: 8)
                        Text(challenge.terms.commitmentText)
                            .font(
                                CompetitiveTrustTheme.displayFont(
                                    size: 24,
                                    relativeTo: .title2
                                )
                            )
                    }
                }
                Text(challenge.terms.targetText)
                    .font(
                        CompetitiveTrustTheme.displayFont(
                            size: 30,
                            relativeTo: .title
                        )
                    )
                    .tracking(-0.8)
                PersonalProgressBar(
                    progress: challenge.progress,
                    terms: challenge.terms
                )
                .colorScheme(.dark)
            }
        }
    }

    private func frozenTerms(_ terms: FrozenPersonalTerms) -> some View {
        Group {
            DaybreakSectionLabel(text: "What you signed up for")
            DaybreakCard {
                VStack(spacing: 0) {
                    termRow("How it counts", terms.cadence.title)
                    divider
                    termRow("Goal", terms.targetText)
                    divider
                    termRow("Amount", terms.commitmentText)
                    divider
                    termRow("Time zone", terms.timezone)
                    divider
                    termRow(
                        "Starts",
                        PersonalTermsDateFormatter.dateTime(
                            terms.startsAt,
                            timezoneIdentifier: terms.timezone
                        )
                    )
                    divider
                    termRow(
                        "Ends",
                        PersonalTermsDateFormatter.dateTime(
                            terms.endsAt,
                            timezoneIdentifier: terms.timezone
                        )
                    )
                    divider
                    termRow(
                        "Last chance to sync",
                        PersonalTermsDateFormatter.dateTime(
                            terms.evidenceCutoff,
                            timezoneIdentifier: terms.timezone
                        )
                    )
                }
            }
        }
    }

    private func progress(_ challenge: PersonalChallengeDetail) -> some View {
        Group {
            DaybreakSectionLabel(text: "Day by day")
            DaybreakCard {
                if challenge.progress.days.isEmpty {
                    Text("Your daily steps will show up here once you start.")
                        .font(.subheadline)
                        .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                } else {
                    PersonalSevenDayTimeline(days: challenge.progress.days)
                }
            }
            DaybreakCard {
                VStack(alignment: .leading, spacing: 9) {
                    Label("Steps received", systemImage: "checkmark.shield")
                        .font(
                            CompetitiveTrustTheme.displayFont(
                                size: 18,
                                relativeTo: .headline
                            )
                        )
                    Text(
                        "We have your steps for \(challenge.progress.coveredBucketCount.formatted()) of \(challenge.progress.expectedBucketCount.formatted()) hours so far."
                    )
                    .font(.subheadline)
                    Text(evidenceExplanation(challenge.progress.evidenceState))
                        .font(.caption)
                        .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private func result(_ challenge: PersonalChallengeDetail) -> some View {
        if let outcome = challenge.outcome {
            DaybreakSectionLabel(text: "How it went")
            DaybreakCard(tone: outcome.kind == .metGoal ? .standard : .pledge) {
                VStack(alignment: .leading, spacing: 9) {
                    PersonalStatusPill(
                        status: challenge.presentationStatus(at: Date()),
                        outcome: outcome.kind
                    )
                    Text(resultTitle(outcome.kind))
                        .font(
                            CompetitiveTrustTheme.displayFont(
                                size: 23,
                                relativeTo: .title2
                            )
                        )
                    Text(resultExplanation(outcome))
                        .font(.subheadline)
                        .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                }
            }
        }
    }

    private func sync(_ challenge: PersonalChallengeDetail) -> some View {
        Group {
            DaybreakSectionLabel(text: "Step syncing")
            DaybreakCard {
                VStack(alignment: .leading, spacing: 11) {
                    if let date = challenge.progress.lastTrustedSyncAt {
                        Label(
                            "Last synced \(date.formatted(.relative(presentation: .named)))",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(CompetitiveTrustTheme.mintInk)
                    } else {
                        Label(
                            "We haven’t received your steps yet",
                            systemImage: "exclamationmark.circle.fill"
                        )
                        .foregroundStyle(CompetitiveTrustTheme.sunInk)
                    }
                    if let message = store.syncState(for: challenge.id).message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                    }
                    Button("Sync my steps") {
                        Task { await store.sync(challengeID: challenge.id) }
                    }
                    .buttonStyle(TrustSecondaryButtonStyle())
                    .disabled(
                        !store.canSyncActivity(
                            challengeID: challenge.id,
                            permitsFreshSync: challenge
                                .permitsActivitySync(
                                    at: Date()
                                )
                        )
                    )
                    .accessibilityIdentifier("personal.sync")
                    Text(
                        "Steps can still arrive up to 24 hours after your last day ends. If some never turn up, the challenge simply doesn’t count — and it doesn’t count against you."
                    )
                    .font(.caption)
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private func review(_ challenge: PersonalChallengeDetail) -> some View {
        if challenge.terms.settlementMode == .stripeSandbox,
            let outcome = challenge.outcome,
            outcome.kind == .missedGoal
        {
            DaybreakSectionLabel(text: "Review")
            DaybreakCard {
                if let request = store.reviewRequest(for: challenge.id) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(
                            "Review requested",
                            systemImage: "checkmark.shield.fill"
                        )
                        .font(
                            CompetitiveTrustTheme.displayFont(
                                size: 20,
                                relativeTo: .headline
                            )
                        )
                        Text("Settlement stays paused while this result is reviewed.")
                            .font(.subheadline.weight(.semibold))
                        Text(
                            "Review ends by \(PersonalTermsDateFormatter.dateTime(request.reviewDeadline, timezoneIdentifier: challenge.terms.timezone))."
                        )
                        .font(.caption)
                        .foregroundStyle(
                            CompetitiveTrustTheme.secondaryText
                        )
                    }
                    .accessibilityIdentifier("personal.review.requested")
                } else if Date()
                    < outcome.publishedAt.addingTimeInterval(7 * 86_400)
                {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Something doesn’t look right?")
                            .font(
                                CompetitiveTrustTheme.displayFont(
                                    size: 20,
                                    relativeTo: .headline
                                )
                            )
                        Text(
                            "Tell us why before the 7-day review window ends. Settlement stays paused while a review is open."
                        )
                        .font(.subheadline)
                        .foregroundStyle(
                            CompetitiveTrustTheme.secondaryText
                        )

                        ForEach(PersonalReviewReason.allCases) { reason in
                            Button {
                                selectedReviewReason = reason
                            } label: {
                                HStack(spacing: 10) {
                                    Image(
                                        systemName:
                                            selectedReviewReason == reason
                                            ? "checkmark.circle.fill"
                                            : "circle"
                                    )
                                    .foregroundStyle(
                                        selectedReviewReason == reason
                                            ? CompetitiveTrustTheme.coral
                                            : CompetitiveTrustTheme.guide
                                    )
                                    Text(reason.title)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer(minLength: 8)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(
                                "personal.review.reason.\(reason.rawValue)"
                            )
                            .accessibilityValue(
                                selectedReviewReason == reason
                                    ? "Selected"
                                    : "Not selected"
                            )
                        }

                        Button {
                            Task {
                                _ = await store.requestReview(
                                    challengeID: challenge.id,
                                    reason: selectedReviewReason
                                )
                            }
                        } label: {
                            if store.isRequestingReview {
                                ProgressView().tint(.white)
                            } else {
                                Text("Request a review")
                            }
                        }
                        .buttonStyle(TrustPrimaryButtonStyle())
                        .disabled(store.isRequestingReview)
                        .accessibilityIdentifier(
                            "personal.review.request"
                        )

                        Text(
                            "Review window ends \(PersonalTermsDateFormatter.dateTime(outcome.publishedAt.addingTimeInterval(7 * 86_400), timezoneIdentifier: challenge.terms.timezone))."
                        )
                        .font(.caption)
                        .foregroundStyle(
                            CompetitiveTrustTheme.tertiaryText
                        )
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Review window ended")
                            .font(.headline)
                        Text(
                            "The 7-day window for requesting a review has closed."
                        )
                        .font(.subheadline)
                        .foregroundStyle(
                            CompetitiveTrustTheme.secondaryText
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cancellation(_ challenge: PersonalChallengeDetail) -> some View {
        if challenge.status == .scheduled {
            Button("Cancel this challenge", role: .destructive) {
                showingCancelConfirmation = true
            }
            .buttonStyle(TrustSecondaryButtonStyle())
            .disabled(store.isMutating || Date() >= challenge.terms.startsAt)
            .accessibilityIdentifier("personal.cancel")
        }
    }

    private func termRow(_ label: String, _ value: String) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 5) {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Divider().overlay(CompetitiveTrustTheme.border)
    }

    private func evidenceExplanation(_ state: PersonalEvidenceState) -> String {
        switch state {
        case .complete:
            "We have everything we need so far."
        case .future:
            "Nothing to count until your challenge starts."
        case .inProgress, .pending:
            "Still counting. Nothing is final until your challenge ends."
        case .outageWaived:
            "This was a problem on our end, so it doesn’t count against you."
        case .incomplete, .missing, .quarantined, .conflicting, .unresolved:
            "We can’t confirm your steps, so this one won’t count either way. You may need to run a Health check."
        }
    }

    private func resultTitle(_ kind: PersonalOutcomeKind) -> String {
        switch kind {
        case .metGoal: "You hit your goal"
        case .missedGoal: "You came up short"
        case .inconclusive: "This one didn’t count"
        }
    }

    private func resultExplanation(_ outcome: PersonalOutcome) -> String {
        switch outcome.kind {
        case .metGoal:
            return "Your steps added up and you got there. Nice work."
        case .missedGoal:
            if challenge?.terms.settlementMode == .stripeSandbox {
                return "Your steps added up, but they didn’t reach your goal. This result is provisional through the 7-day review window; only a confirmed miss can create one simulated test charge."
            }
            return "Your steps added up, but they didn’t reach your goal. This result closes without settlement."
        case .inconclusive:
            let opening =
                "We couldn’t confirm your steps, so this one doesn’t count — for you or against you."
            guard let reason = PersonalReasonText.sentence(
                for: outcome.reasonCode
            ) else {
                return opening
            }
            return "\(opening) \(reason)"
        }
    }

    private var cancellationMessage: String {
        if challenge?.terms.settlementMode == .stripeSandbox {
            return "You can only cancel before your challenge starts. Cancelling before it starts closes the payment terms before settlement."
        }
        return "You can only cancel before your challenge starts. Cancelling before it starts closes the test commitment."
    }
}
