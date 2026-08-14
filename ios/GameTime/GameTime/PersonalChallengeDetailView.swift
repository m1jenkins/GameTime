import SwiftUI

struct PersonalChallengeDetailView: View {
    let challengeID: UUID

    @Environment(PersonalAccountabilityStore.self) private var store
    @Environment(PersonalStepProgressStore.self) private var stepProgress
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingCancelConfirmation = false
    @State private var isSyncNowRequested = false
    @State private var isCancellationRequested = false
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
                    if challenge.status.isOpen {
                        cancellation(challenge)
                        pace(challenge)
                    } else {
                        result(challenge)
                        review(challenge)
                        pace(challenge)
                    }
                    PersonalChallengeDetailsCard(terms: challenge.terms)
                } else {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity)
                        .trustCard()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
        }
        .daybreakTabScrollClearance()
        .daybreakScreenChrome()
        .navigationTitle("Your challenge")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: challengeID) {
            await store.loadDetail(challengeID: challengeID)
        }
        .task(id: reviewDeadline) {
            await refreshReviewClock(deadline: reviewDeadline)
        }
        .alert(
            "Cancel this challenge?",
            isPresented: $showingCancelConfirmation
        ) {
            Button("Yes, cancel it", role: .destructive) {
                isCancellationRequested = true
                Task {
                    let succeeded = await store.cancel(
                        challengeID: challengeID
                    )
                    PersonalAccessibilityAnnouncements.post(
                        succeeded
                            ? "Cancellation confirmed."
                            : "Cancellation is saved, but it is not confirmed yet."
                    )
                    if succeeded {
                        dismiss()
                    } else {
                        isCancellationRequested = false
                    }
                }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(cancellationMessage)
        }
    }

    private func hero(_ challenge: PersonalChallengeDetail) -> some View {
        let now = Date()
        let progress = store.displayedProgress(for: challenge, now: now)
        let status = challenge.presentationStatus(at: now)
        let healthPresentation = PersonalHealthProgressPresentation(
            progress: progress,
            terms: challenge.terms,
            status: status,
            outcome: challenge.outcome,
            uploadDelayed: challenge.id == stepProgress.challengeID
                && stepProgress.lastUploadError != nil,
            now: now
        )

        return VStack(alignment: .leading, spacing: 15) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    PersonalStatusPill(
                        status: status,
                        outcome: challenge.outcome?.kind
                    )
                    Text(challenge.terms.commitmentText)
                        .font(
                            CompetitiveTrustTheme.monoFont(
                                size: 20,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(CompetitiveTrustTheme.primaryText)
                }
            } else {
                HStack {
                    PersonalStatusPill(
                        status: status,
                        outcome: challenge.outcome?.kind
                    )
                    Spacer(minLength: 8)
                    Text(challenge.terms.commitmentText)
                        .font(
                            CompetitiveTrustTheme.monoFont(
                                size: 20,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(CompetitiveTrustTheme.primaryText)
                }
            }
            Text(challenge.terms.targetText)
                .font(
                    CompetitiveTrustTheme.displayFont(
                        size: dynamicTypeSize.isAccessibilitySize
                            ? 22
                            : 28,
                        relativeTo: dynamicTypeSize.isAccessibilitySize
                            ? .headline
                            : .title
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.primaryText)
                .tracking(-0.8)
            if let progress {
                PersonalProgressBar(
                    progress: progress,
                    terms: challenge.terms
                )
            }
            PersonalHealthProgressStatus(
                presentation: healthPresentation,
                policy: challenge.stepDataPolicy
            )
            if healthPresentation.needsNoDataRecovery,
                challenge.stepDataPolicy.usesAutomaticHealthProgress
            {
                activeNoDataRecovery(
                    canRetry: canSyncNow(challenge, now: now)
                )
            } else if canSyncNow(challenge, now: now) {
                healthRefreshButton(
                    title: "Sync now",
                    pendingTitle: "Syncing…"
                )
            }
        }
        .trustCard()
    }

    private func canSyncNow(
        _ challenge: PersonalChallengeDetail,
        now: Date = Date()
    ) -> Bool {
        challenge.id == stepProgress.challengeID
            && stepProgress.canRefresh
            && challenge.permitsActivitySync(at: now)
    }

    private func activeNoDataRecovery(canRetry: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                "Apple Health access may be limited, or this phone may not have recent device-recorded steps."
            )
            .font(.subheadline)
            .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

            healthRefreshButton(
                title: "Try Again",
                pendingTitle: "Checking Apple Health…",
                canRetry: canRetry
            )

            if let destination = URL(
                string: "https://support.apple.com/en-us/HT204351"
            ) {
                Link("Apple Health help", destination: destination)
                    .buttonStyle(TrustSecondaryButtonStyle())
                    .accessibilityIdentifier(
                        "personal.challenge.health-help"
                    )
            }

            Button("Account & support") {
                router.openAccountSupport()
            }
            .buttonStyle(TrustSecondaryButtonStyle())
            .accessibilityIdentifier("personal.challenge.account-support")
        }
    }

    private func healthRefreshButton(
        title: String,
        pendingTitle: String,
        canRetry: Bool = true
    ) -> some View {
        Button(action: requestHealthRefresh) {
            HStack(spacing: 8) {
                if isSyncNowRequested || stepProgress.isRefreshing {
                    ProgressView()
                        .tint(CompetitiveTrustTheme.coralInk)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .accessibilityHidden(true)
                }
                Text(
                    isSyncNowRequested || stepProgress.isRefreshing
                        ? pendingTitle
                        : title
                )
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(TrustSecondaryButtonStyle())
        .disabled(
            !canRetry || isSyncNowRequested || stepProgress.isRefreshing
        )
        .accessibilityIdentifier("personal.challenge.sync-now")
    }

    private func requestHealthRefresh() {
        guard !isSyncNowRequested, !stepProgress.isRefreshing else { return }
        isSyncNowRequested = true
        Task { @MainActor in
            await stepProgress.refresh()
            isSyncNowRequested = false
            if stepProgress.lastHealthError != nil {
                PersonalAccessibilityAnnouncements.post(
                    "Apple Health is temporarily unavailable. Your last update is still here."
                )
            } else if stepProgress.lastUploadError != nil {
                PersonalAccessibilityAnnouncements.post(
                    "Steps updated on this phone. Sending is delayed."
                )
            } else {
                PersonalAccessibilityAnnouncements.post("Steps updated.")
            }
        }
    }

    @ViewBuilder
    private func pace(_ challenge: PersonalChallengeDetail) -> some View {
        let progress = store.displayedProgress(for: challenge)
        AthleticSectionHeader(text: "Your pace")
        if progress?.days.isEmpty != false {
            Text(emptyPaceMessage(for: challenge))
                .font(.subheadline)
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .trustCard()
        } else if let progress {
            let summary = PersonalPaceSummary(
                detail: challenge,
                progress: progress
            )
            PersonalPaceCard(summary: summary)
            PersonalPaceTiles(tiles: summary.tiles)
        }
    }

    private func emptyPaceMessage(
        for challenge: PersonalChallengeDetail
    ) -> String {
        if challenge.outcome?.kind == .inconclusive,
            challenge.outcome?.reasonCode == "missing_health_data"
        {
            return "No Apple Health step data was available for this challenge."
        }
        switch challenge.presentationStatus(at: Date()) {
        case .scheduled:
            return "Your daily steps will show up here once you start."
        case .cancelled:
            return "This challenge was cancelled before step history was available."
        case .resultPending, .awaitingEvidence:
            return "Your final step history will appear when the result is ready."
        case .active:
            return "No step history is available yet. Try again above for recovery options."
        case .completed:
            return "No step history is available for this challenge."
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
            AthleticSectionHeader(text: "How it went")
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
            .trustCard()
            .accessibilityIdentifier("personal.result")
        }
    }

    @ViewBuilder
    private func review(_ challenge: PersonalChallengeDetail) -> some View {
        if challenge.terms.settlementMode == .stripeSandbox,
            let outcome = challenge.outcome,
            outcome.kind == .missedGoal
        {
            AthleticSectionHeader(text: "Review")
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
                .trustCard()
                .accessibilityIdentifier("personal.review.submitted")
            } else if reviewNow >= deadline {
                Text("The review request window ended.")
                    .font(.subheadline)
                    .foregroundStyle(
                        CompetitiveTrustTheme.secondaryText
                    )
                    .trustCard()
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
                    .accessibilityIdentifier(
                        "personal.review.available"
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
                                        ? CompetitiveTrustTheme.actionCoral
                                        : CompetitiveTrustTheme.guide
                                )
                                Text(reason.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer(minLength: 8)
                            }
                            .daybreakTappableRow()
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
                        Task { @MainActor in
                            let succeeded = await store.requestReview(
                                challengeID: challenge.id,
                                reason: selectedReviewReason
                            )
                            PersonalAccessibilityAnnouncements.post(
                                succeeded
                                    ? "Review requested. Settlement is paused."
                                    : "Review request failed. Try again."
                            )
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if store.isRequestingReview {
                                ProgressView().tint(.white)
                            }
                            Text(
                                store.isRequestingReview
                                    ? "Requesting review…"
                                    : "Request a review"
                            )
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TrustPrimaryButtonStyle())
                    .disabled(store.isRequestingReview)
                    .accessibilityIdentifier(
                        "personal.review.request"
                    )
                }
                .trustCard()
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
        let isSandboxCancellation =
            store.configuration.allowsActiveSandboxChallengeCancellation
            && challenge.terms.settlementMode
                == store.configuration.personalSettlementMode
            && (challenge.status == .scheduled || challenge.status == .active)
        let hasRelevantPendingCancellation =
            store.pendingCancellation?.challengeID == challenge.id
            || (store.pendingCancellation == nil
                && store.hasPendingCancellationRecoveryIssue)

        PendingPersonalCancellationRecoveryCard(
            challengeID: challenge.id,
            contactSupport: { router.openAccountSupport() }
        )

        if !hasRelevantPendingCancellation,
            isOrdinaryPreStartCancellation || isSandboxCancellation
        {
            Button(
                isCancellationRequested || store.isMutating
                    ? "Cancelling…"
                    : "Cancel this challenge",
                role: .destructive
            ) {
                showingCancelConfirmation = true
            }
            .buttonStyle(TrustSecondaryButtonStyle())
            .disabled(isCancellationRequested || store.isMutating)
            .accessibilityIdentifier("personal.cancel")
        }
    }

    private var cancellationMessage: String {
        if challenge?.terms.settlementMode == .stripeSandbox {
            return "This ends the challenge immediately. It will stay in your history, and your saved test payment method will not be charged."
        }
        if store.configuration.allowsActiveSandboxChallengeCancellation {
            return "This ends the test challenge immediately. It will stay in your history, and no money will be charged."
        }
        return "You can only cancel before your challenge starts. Cancelling before it starts closes the test commitment."
    }
}
