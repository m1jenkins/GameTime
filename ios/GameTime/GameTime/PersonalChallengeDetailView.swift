import SwiftUI

struct PersonalChallengeDetailView: View {
    let challengeID: UUID

    @Environment(PersonalAccountabilityStore.self) private var store
    @Environment(PersonalStepProgressStore.self) private var stepProgress
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingCancelConfirmation = false
    @State private var isSyncNowRequested = false
    @State private var reviewNow = Date()
    @State private var selectedReviewReason:
        PersonalReviewReason = .userDisputesStepData

    private var challenge: PersonalChallengeDetail? {
        store.detail(for: challengeID)
    }

    private var reviewDeadline: Date? {
        guard
            let challenge,
            challenge.terms.settlementMode == .stripeSandbox,
            let outcome = challenge.outcome,
            outcome.kind == .missedGoal
        else {
            return nil
        }
        return outcome.publishedAt.addingTimeInterval(
            PersonalResultPresentation.reviewWindow
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if let challenge {
                    hero(challenge)
                    cancellation(challenge)
                    pace(challenge)
                    result(challenge)
                    review(challenge)
                    PersonalChallengeDetailsCard(terms: challenge.terms)
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
        .task(id: reviewDeadline) {
            await refreshReviewClock(deadline: reviewDeadline)
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
                        }
                    } label: {
                        if isSyncNowRequested || stepProgress.isRefreshing {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .tint(CompetitiveTrustTheme.coralInk)
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
            let presentation = PersonalResultPresentation(
                terms: challenge.terms,
                outcome: outcome,
                now: reviewNow
            )
            DaybreakSectionLabel(text: "How it went")
            DaybreakCard(tone: outcome.kind == .metGoal ? .standard : .pledge) {
                VStack(alignment: .leading, spacing: 9) {
                    PersonalStatusPill(
                        status: challenge.presentationStatus(at: Date()),
                        outcome: outcome.kind
                    )
                    Text(presentation.title)
                        .font(
                            CompetitiveTrustTheme.displayFont(
                                size: 23,
                                relativeTo: .title2
                            )
                        )
                    ForEach(presentation.details, id: \.self) { detail in
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(
                                CompetitiveTrustTheme.secondaryText
                            )
                    }
                }
            }
            .accessibilityIdentifier("personal.result")
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
                let deadline = outcome.publishedAt.addingTimeInterval(
                    PersonalResultPresentation.reviewWindow
                )
                if let request = store.reviewRequest(for: challenge.id) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Under review — settlement paused.")
                            .font(
                                CompetitiveTrustTheme.displayFont(
                                    size: 20,
                                    relativeTo: .headline
                                )
                            )
                        Text(
                            "Review ends by \(PersonalTermsDateFormatter.dateTime(request.reviewDeadline, timezoneIdentifier: challenge.terms.timezone))."
                        )
                        .font(.caption)
                        .foregroundStyle(
                            CompetitiveTrustTheme.secondaryText
                        )
                    }
                    .accessibilityIdentifier("personal.review.submitted")
                } else if reviewNow >= deadline {
                    Text("The review request window ended.")
                        .font(.subheadline)
                        .foregroundStyle(
                            CompetitiveTrustTheme.secondaryText
                        )
                        .accessibilityIdentifier("personal.review.expired")
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(
                            "Request a review by \(PersonalTermsDateFormatter.dateTime(deadline, timezoneIdentifier: challenge.terms.timezone)); settlement is paused during this seven-day window."
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

                    }
                    .accessibilityIdentifier("personal.review.available")
                }
            }
        }
    }

    private func refreshReviewClock(deadline: Date?) async {
        reviewNow = Date()
        guard let deadline else { return }
        let remaining = deadline.timeIntervalSince(reviewNow)
        guard remaining > 0 else { return }
        do {
            try await Task.sleep(
                nanoseconds: UInt64(remaining * 1_000_000_000)
            )
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        reviewNow = Date()
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
