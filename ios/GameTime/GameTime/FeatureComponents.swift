import SwiftUI

struct FriendshipCardRow: View {
    let card: FriendshipCard
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            InitialsAvatar(
                initials: card.profileCard.initials,
                color: SignalTheme.avatarColor(
                    for: card.otherUserID
                )
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(card.displayName)
                    .font(
                        SignalTheme.uiFont(
                            size: 15,
                            relativeTo: .headline,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(SignalTheme.textPrimary)
                Text("@\(card.handle)")
                    .font(
                        SignalTheme.uiFont(
                            size: 13,
                            relativeTo: .subheadline
                        )
                    )
                    .foregroundStyle(SignalTheme.textSecondary)
            }

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SignalCompactButtonStyle())
                    .accessibilityLabel(
                        "\(actionTitle) \(card.displayName)"
                    )
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

struct ContestCardRow: View {
    let contest: ContestCard
    var currentUserID: UUID? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Text(contest.title)
                        .font(
                            SignalTheme.displayFont(
                                size: 18,
                                relativeTo: .headline
                            )
                        )
                        .foregroundStyle(SignalTheme.textPrimary)
                        .tracking(-0.5)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(1)
                    Spacer()
                    statusPill
                }

                if !participantColors.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(
                            Array(participantColors.enumerated()),
                            id: \.offset
                        ) { _, color in
                            Capsule()
                                .fill(color)
                                .frame(height: 5)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Text("\(contest.metric.title) · \(contest.cadence.title.lowercased())")
                    Circle()
                        .fill(SignalTheme.textSecondary)
                        .frame(width: 3, height: 3)
                        .accessibilityHidden(true)
                    Text(
                        contest.cadence == .daily
                            ? "\(contest.daybreakTargetText)/day"
                            : contest.daybreakTargetText
                    )
                    Spacer()
                    SignalStatusTag(
                        text: "\(contest.stakeText) each",
                        kind: .pledge
                    )
                }
                .font(
                    SignalTheme.uiFont(
                        size: 12.5,
                        relativeTo: .caption
                    )
                )
                .foregroundStyle(SignalTheme.textSecondary)

                Text(contextText)
                    .font(
                        SignalTheme.uiFont(
                            size: 11.5,
                            relativeTo: .caption
                        )
                    )
                    .foregroundStyle(SignalTheme.textSecondary)
            }
            .signalSection()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var statusPill: some View {
        if contest.myStatus == .invited {
            SignalStatusTag(text: "Needs you", kind: .action)
        } else if contest.status == .active {
            SignalStatusTag(text: "Live", kind: .live)
        } else if contest.status == .finalized {
            SignalStatusTag(text: "Final", kind: .positive)
        } else {
            SignalStatusTag(text: "Upcoming", kind: .neutral)
        }
    }

    private var participantColors: [Color] {
        let participantIDs = contest.resolvedParticipants.map(\.userID)
        return participantIDs.map {
            SignalTheme.participantColor(
                for: $0,
                participantIDs: participantIDs,
                currentUserID: currentUserID
            )
        }
    }

    private var contextText: String {
        switch contest.status {
        case .pending:
            return "Starts \(contest.startsAt.formatted(.dateTime.month(.abbreviated).day()))"
        case .active:
            return "Ends \(contest.endsAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
        case .finalized:
            return "Ended \(contest.endsAt.formatted(.dateTime.month(.abbreviated).day()))"
        case .cancelled:
            return "Challenge cancelled"
        }
    }

    private var accessibilitySummary: String {
        let state = contest.myStatus == .invited
            ? "Invitation, action needed"
            : contest.status.rawValue
        return "\(contest.title), \(state), \(contest.daybreakTargetText), \(contest.stakeText) each, \(contextText)"
    }
}

struct InlineLoadStateView: View {
    let state: ScreenLoadState
    let retry: () -> Void

    var body: some View {
        switch state {
        case .idle, .loaded, .empty:
            EmptyView()
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                    .tint(SignalTheme.accent)
                Text("Updating…")
                    .font(
                        SignalTheme.uiFont(
                            size: 14,
                            relativeTo: .subheadline,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(SignalTheme.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("state.loading")
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Label("Couldn’t refresh", systemImage: "wifi.slash")
                    .font(
                        SignalTheme.displayFont(
                            size: 18,
                            relativeTo: .headline
                        )
                    )
                Text(message)
                    .font(
                        SignalTheme.uiFont(
                            size: 13,
                            relativeTo: .subheadline
                        )
                    )
                    .foregroundStyle(SignalTheme.textSecondary)
                Button("Try again", action: retry)
                    .buttonStyle(
                        SignalCompactButtonStyle(tone: .quiet)
                    )
            }
            .accessibilityIdentifier("state.offline")
        }
    }
}

struct EmptyTrustState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(SignalTheme.accent)
                .frame(width: 52, height: 52)
                .background(
                    SignalTheme.selection,
                    in: Circle()
                )
                .accessibilityHidden(true)
            Text(title)
                .font(
                    SignalTheme.displayFont(
                        size: 21,
                        relativeTo: .title3
                    )
                )
                .tracking(-0.55)
            Text(message)
                .font(
                    SignalTheme.uiFont(
                        size: 13.5,
                        relativeTo: .subheadline
                    )
                )
                .foregroundStyle(SignalTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("state.empty")
    }
}

struct TermRow: View {
    let label: String
    let value: String
    var emphasis: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(SignalTheme.textSecondary)
            Spacer(minLength: 16)
            Text(value)
                .foregroundStyle(emphasis)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
        .font(
            SignalTheme.uiFont(
                size: 14,
                relativeTo: .subheadline
            )
        )
        .accessibilityElement(children: .combine)
    }
}
