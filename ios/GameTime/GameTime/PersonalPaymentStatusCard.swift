import SwiftUI

struct PersonalPaymentStatusCard: View {
    let challenge: PersonalChallengeDetail
    let contactSupport: () -> Void

    @Environment(PersonalAccountabilityStore.self) private var store
    @State private var selectedReviewReason:
        PersonalReviewReason = .userDisputesStepData

    var body: some View {
        let now = Date()
        let statusState = store.paymentStatusState(for: challenge.id)
        let presentation = PersonalPaymentStatusPresentation(
            challenge: challenge,
            statusState: statusState,
            now: now
        )
        let freshReviewDeadline = store.freshReviewDeadline(
            for: challenge.id,
            at: now
        )
        let retainedReviewDeadline = retainedReviewDeadline(
            for: statusState,
            at: now
        )

        AthleticSectionHeader(text: "Payment test status")
        VStack(alignment: .leading, spacing: 12) {
            statusRow(presentation)

            ForEach(presentation.details, id: \.self) { detail in
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let freshnessMessage = freshnessMessage(for: statusState) {
                freshnessRow(
                    freshnessMessage,
                    statusState: statusState
                )
            }

            if let reviewDeadline = freshReviewDeadline
                ?? retainedReviewDeadline
            {
                Divider().overlay(CompetitiveTrustTheme.hairlineDivider)
                reviewControls(
                    deadline: reviewDeadline,
                    isEnabled: freshReviewDeadline == reviewDeadline
                )
            }

            if showsRecoveryActions(for: statusState) {
                recoveryActions(statusState: statusState)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .trustCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("personal.payment.status.card")
    }

    private func statusRow(
        _ presentation: PersonalPaymentStatusPresentation
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if presentation.isChecking {
                ProgressView()
                    .tint(CompetitiveTrustTheme.coralInk)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: presentation.symbol)
                    .foregroundStyle(presentation.color)
                    .accessibilityHidden(true)
            }

            Text(presentation.title)
                .font(.headline.weight(.bold))
                .foregroundStyle(CompetitiveTrustTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.title)
        .accessibilityIdentifier("personal.payment.status.state")
    }

    private func freshnessRow(
        _ message: String,
        statusState: PersonalPaymentStatusViewState
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if statusState.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            } else {
                Image(
                    systemName: statusState.isStale
                        ? "exclamationmark.arrow.triangle.2.circlepath"
                        : "clock"
                )
                .accessibilityHidden(true)
            }

            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(
            statusState.isStale
                ? CompetitiveTrustTheme.sunInk
                : CompetitiveTrustTheme.secondaryText
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
    }

    private func reviewControls(
        deadline: Date,
        isEnabled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Why are you asking for a review?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CompetitiveTrustTheme.primaryText)

            ForEach(PersonalReviewReason.allCases) { reason in
                let isSelected = selectedReviewReason == reason
                Button {
                    selectedReviewReason = reason
                } label: {
                    HStack(spacing: 10) {
                        Image(
                            systemName: isSelected
                                ? "checkmark.circle.fill"
                                : "circle"
                        )
                        .foregroundStyle(
                            isSelected
                                ? CompetitiveTrustTheme.actionCoral
                                : CompetitiveTrustTheme.guide
                        )
                        .accessibilityHidden(true)

                        Text(reason.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(
                                CompetitiveTrustTheme.primaryText
                            )
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                    }
                    .daybreakTappableRow()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(
                    "personal.review.reason.\(reason.rawValue)"
                )
                .accessibilityLabel(reason.title)
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .disabled(!isEnabled || store.isRequestingReview)
            }

            Button(action: requestReview) {
                HStack(spacing: 8) {
                    if store.isRequestingReview {
                        ProgressView()
                            .tint(.black)
                            .accessibilityHidden(true)
                    }
                    Text(
                        store.isRequestingReview
                            ? "Requesting review…"
                            : "Request a review"
                    )
                    .font(.headline.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(TrustPrimaryButtonStyle())
            .disabled(
                !isEnabled
                    || store.isRequestingReview
                    || store.freshReviewDeadline(
                        for: challenge.id,
                        at: Date()
                    ) != deadline
            )
            .accessibilityIdentifier("personal.review.request")
        }
    }

    private func retainedReviewDeadline(
        for statusState: PersonalPaymentStatusViewState,
        at now: Date
    ) -> Date? {
        let confirmation: PersonalPaymentStatusConfirmation?
        switch statusState {
        case .loading(let lastConfirmed), .failed(let lastConfirmed):
            confirmation = lastConfirmed
        case .idle, .confirmed:
            confirmation = nil
        }
        guard
            confirmation?.status.state == .reviewOpen,
            let deadline = confirmation?.status.reviewDeadline,
            now < deadline
        else {
            return nil
        }
        return deadline
    }

    private func recoveryActions(
        statusState: PersonalPaymentStatusViewState
    ) -> some View {
        VStack(spacing: 10) {
            Button(action: requestRefresh) {
                HStack(spacing: 8) {
                    if statusState.isLoading {
                        ProgressView()
                            .tint(CompetitiveTrustTheme.coralInk)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .accessibilityHidden(true)
                    }
                    Text(statusState.isLoading ? "Refreshing…" : "Refresh")
                        .font(.headline.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(TrustSecondaryButtonStyle())
            .disabled(
                statusState.isLoading
                    || isWaitingForInitialLoad(statusState)
                    || store.isRequestingReview
            )
            .accessibilityIdentifier("personal.payment.status.refresh")

            Button(action: contactSupport) {
                Text("Contact Support")
                    .font(.headline.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TrustSecondaryButtonStyle())
            .accessibilityIdentifier("personal.payment.status.support")
        }
    }

    private func showsRecoveryActions(
        for statusState: PersonalPaymentStatusViewState
    ) -> Bool {
        if statusState.refreshFailed || statusState.lastConfirmed == nil {
            return true
        }

        switch statusState.lastConfirmed?.status.state {
        case .waived, .noCharge, .charged:
            return false
        case .methodSaved, .reviewOpen, .underReview, .chargePending,
            .requiresAction, .collectionFailed, .none:
            return true
        }
    }

    private func freshnessMessage(
        for statusState: PersonalPaymentStatusViewState
    ) -> String? {
        guard let confirmation = statusState.lastConfirmed else { return nil }
        let checkedAt = PersonalTermsDateFormatter.dateTime(
            confirmation.checkedAt,
            timezoneIdentifier: challenge.terms.timezone
        )

        if statusState.isStale {
            return "Last confirmed \(checkedAt). We couldn’t refresh it."
        }
        if statusState.isLoading {
            return "Last confirmed \(checkedAt). Refreshing…"
        }
        return "Checked \(checkedAt)."
    }

    private func isWaitingForInitialLoad(
        _ statusState: PersonalPaymentStatusViewState
    ) -> Bool {
        if case .idle = statusState { return true }
        return false
    }

    private func requestRefresh() {
        Task { @MainActor in
            await store.refreshPaymentStatus(challengeID: challenge.id)
            let updatedState = store.paymentStatusState(for: challenge.id)
            PersonalAccessibilityAnnouncements.post(
                refreshAnnouncement(for: updatedState)
            )
        }
    }

    private func requestReview() {
        Task { @MainActor in
            let succeeded = await store.requestReview(
                challengeID: challenge.id,
                reason: selectedReviewReason
            )
            PersonalAccessibilityAnnouncements.post(
                succeeded
                    ? "Review requested. Settlement is paused."
                    : "Review could not be requested. Refresh payment test status and try again."
            )
        }
    }

    private func refreshAnnouncement(
        for statusState: PersonalPaymentStatusViewState
    ) -> String {
        switch statusState {
        case .confirmed:
            let presentation = PersonalPaymentStatusPresentation(
                challenge: challenge,
                statusState: statusState,
                now: Date()
            )
            return "Payment test status refreshed. \(presentation.title)"
        case .failed(let lastConfirmed) where lastConfirmed != nil:
            return "Refresh failed. Your last confirmed payment test status is still here."
        case .idle, .loading, .failed:
            return "Payment test status could not be confirmed."
        }
    }
}

private struct PersonalPaymentStatusPresentation {
    enum Tone {
        case neutral
        case pending
        case positive
        case attention
    }

    let title: String
    let details: [String]
    let symbol: String
    let tone: Tone
    let isChecking: Bool

    init(
        challenge: PersonalChallengeDetail,
        statusState: PersonalPaymentStatusViewState,
        now: Date
    ) {
        guard let status = statusState.lastConfirmed?.status else {
            if statusState.refreshFailed {
                title = "Payment test status could not be confirmed."
                details = []
                symbol = "questionmark.circle.fill"
                tone = .attention
                isChecking = false
            } else {
                title = "Checking payment test status…"
                details = []
                symbol = "clock"
                tone = .neutral
                isChecking = true
            }
            return
        }

        isChecking = false
        switch status.state {
        case .methodSaved:
            title = "Test method saved."
            details = ["No test charge exists."]
            symbol = "creditcard.fill"
            tone = .neutral
        case .reviewOpen:
            guard let deadline = status.reviewDeadline else {
                title = "Payment test status could not be confirmed."
                details = []
                symbol = "questionmark.circle.fill"
                tone = .attention
                return
            }
            if deadline <= now {
                title = "Review window ended — settlement update pending."
                details = ["Refresh to check the latest payment test status."]
            } else {
                let deadlineText = PersonalTermsDateFormatter.dateTime(
                    deadline,
                    timezoneIdentifier: challenge.terms.timezone
                )
                let amount = challenge.terms.commitmentText
                title = "Goal missed — review open. Settlement is paused."
                details = [
                    "Ask us to review this result by \(deadlineText).",
                    "Only a confirmed miss after review can create one \(amount) test charge.",
                ]
            }
            symbol = "clock.fill"
            tone = .pending
        case .underReview:
            title = "Under review — settlement paused."
            details = []
            symbol = "pause.circle.fill"
            tone = .pending
        case .waived:
            title = "This one didn’t count — $0 test charge."
            details = []
            symbol = "checkmark.circle.fill"
            tone = .positive
        case .noCharge:
            switch challenge.outcome?.kind {
            case .metGoal:
                title = "Goal met — $0 test charge."
            case .missedGoal, .inconclusive:
                title = "This one didn’t count — $0 test charge."
            case nil:
                title = "Challenge closed — $0 test charge."
            }
            details = []
            symbol = "checkmark.circle.fill"
            tone = .positive
        case .chargePending:
            title =
                "Processing one \(challenge.terms.commitmentText) test charge."
            details = []
            symbol = "hourglass"
            tone = .pending
        case .charged:
            title = "Test charge complete — sandbox transaction recorded."
            details = []
            symbol = "checkmark.seal.fill"
            tone = .positive
        case .requiresAction, .collectionFailed:
            title =
                "Test payment needs your attention. We won’t try again automatically."
            details = []
            symbol = "exclamationmark.triangle.fill"
            tone = .attention
        }
    }

    var color: Color {
        switch tone {
        case .neutral:
            CompetitiveTrustTheme.secondaryText
        case .pending:
            CompetitiveTrustTheme.sunInk
        case .positive:
            CompetitiveTrustTheme.mintInk
        case .attention:
            CompetitiveTrustTheme.coralInk
        }
    }
}
