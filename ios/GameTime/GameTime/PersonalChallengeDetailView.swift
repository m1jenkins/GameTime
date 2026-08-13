import SwiftUI

struct PersonalChallengeDetailView: View {
    let challengeID: UUID

    @Environment(PersonalAccountabilityStore.self) private var store
    @Environment(PersonalStepProgressStore.self) private var stepProgress
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingCancelConfirmation = false
    @State private var isSyncNowRequested = false
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
                    cancellation(challenge)
                    pace(challenge)
                    result(challenge)
                    review(challenge)
                    PersonalChallengeDetailsCard(terms: challenge.terms)
                } else {
                    DaybreakCard {
                        ProgressView("Loading challenge…")
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("personal.detail.loading")
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
                    GameTimeAccessibility.announce(
                        "Cancelling your challenge."
                    )
                    if await store.cancel(challengeID: challengeID) {
                        dismiss()
                        await Task.yield()
                        GameTimeAccessibility.announce(
                            "Challenge cancelled."
                        )
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
                if let progress = store.displayedProgress(for: challenge) {
                    PersonalProgressBar(
                        progress: progress,
                        terms: challenge.terms
                    )
                    .colorScheme(.dark)
                }
                PersonalHealthProgressStatus(
                    progress: store.displayedProgress(for: challenge),
                    terms: challenge.terms,
                    status: challenge.presentationStatus(at: Date()),
                    policy: challenge.stepDataPolicy,
                    outcome: challenge.outcome
                )
                .colorScheme(.dark)
                if canSyncNow(challenge) {
                    Button {
                        isSyncNowRequested = true
                        Task {
                            await stepProgress.refresh()
                            isSyncNowRequested = false
                            GameTimeAccessibility.announce(
                                PersonalAccessibilityCopy.syncResult(
                                    progress: store.displayedProgress(
                                        for: challenge
                                    ),
                                    terms: challenge.terms,
                                    healthError: stepProgress.lastHealthError
                                )
                            )
                        }
                    } label: {
                        if isSyncNowRequested || stepProgress.isRefreshing {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .tint(CompetitiveTrustTheme.coralInk)
                                    .accessibilityHidden(true)
                                Text("Syncing…")
                            }
                        } else {
                            Label("Sync now", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(TrustSecondaryButtonStyle())
                    .disabled(
                        isSyncNowRequested || stepProgress.isRefreshing
                    )
                    .accessibilityIdentifier(
                        "personal.challenge.sync-now"
                    )
                    .accessibilityLabel("Sync now")
                    .accessibilityValue(
                        isSyncNowRequested || stepProgress.isRefreshing
                            ? "Syncing"
                            : ""
                    )
                }
            }
        }
    }

    private func canSyncNow(_ challenge: PersonalChallengeDetail) -> Bool {
        challenge.id == stepProgress.challengeID
            && stepProgress.canRefresh
    }

    @ViewBuilder
    private func pace(_ challenge: PersonalChallengeDetail) -> some View {
        let progress = store.displayedProgress(for: challenge)
        DaybreakSectionLabel(text: "Your pace")
        if progress?.days.isEmpty != false {
            DaybreakCard {
                Text(
                    challenge.outcome?.kind == .inconclusive
                        && challenge.outcome?.reasonCode == "missing_health_data"
                        ? "No Apple Health step data was available for this challenge."
                        : "Your daily steps will show up here once you start."
                )
                    .font(.subheadline)
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            }
        } else if let progress {
            let summary = PersonalPaceSummary(
                detail: challenge,
                progress: progress
            )
            PersonalPaceCard(summary: summary)
            PersonalPaceTiles(tiles: summary.tiles)
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
                        .accessibilityAddTraits(.isHeader)
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
                            .accessibilityAddTraits(.isHeader)
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
                                            : CompetitiveTrustTheme.tertiaryText
                                    )
                                    .accessibilityHidden(true)
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
                            .accessibilityAddTraits(
                                selectedReviewReason == reason
                                    ? [.isSelected]
                                    : []
                            )
                            .minimumInteractiveSize()
                        }

                        Button {
                            Task {
                                if await store.requestReview(
                                    challengeID: challenge.id,
                                    reason: selectedReviewReason
                                ) {
                                    GameTimeAccessibility.announce(
                                        PersonalAccessibilityCopy.reviewRequested
                                    )
                                }
                            }
                        } label: {
                            if store.isRequestingReview {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .tint(.white)
                                        .accessibilityHidden(true)
                                    Text("Submitting…")
                                }
                            } else {
                                Text("Request a review")
                            }
                        }
                        .buttonStyle(TrustPrimaryButtonStyle())
                        .disabled(store.isRequestingReview)
                        .accessibilityIdentifier(
                            "personal.review.request"
                        )
                        .accessibilityLabel("Request a review")
                        .accessibilityValue(
                            store.isRequestingReview ? "Submitting" : ""
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
                            .accessibilityAddTraits(.isHeader)
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
        let isOrdinaryPreStartCancellation =
            challenge.status == .scheduled
            && Date() < challenge.terms.startsAt
        let isTestCleanup =
            store.configuration.allowsActiveTestChallengeCancellation
            && challenge.terms.settlementMode == .testOnly
            && (challenge.status == .scheduled || challenge.status == .active)

        if isOrdinaryPreStartCancellation || isTestCleanup {
            Button("Cancel this challenge", role: .destructive) {
                showingCancelConfirmation = true
            }
            .buttonStyle(TrustSecondaryButtonStyle())
            .disabled(store.isMutating)
            .accessibilityIdentifier("personal.cancel")
            .accessibilityValue(store.isMutating ? "Cancelling" : "")
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
        if store.configuration.allowsActiveTestChallengeCancellation,
            challenge?.status == .active,
            challenge?.terms.settlementMode == .testOnly
        {
            return "This ends the test challenge now so you can start another. No money will be charged."
        }
        if challenge?.terms.settlementMode == .stripeSandbox {
            return "You can only cancel before your challenge starts. Cancelling before it starts closes the payment terms before settlement."
        }
        return "You can only cancel before your challenge starts. Cancelling before it starts closes the test commitment."
    }
}
