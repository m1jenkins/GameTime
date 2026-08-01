import SwiftUI

struct FriendshipCardRow: View {
    let card: FriendshipCard
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            InitialsAvatar(initials: card.profileCard.initials)

            VStack(alignment: .leading, spacing: 3) {
                Text(card.displayName)
                    .font(.headline)
                Text("@\(card.handle)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(CompetitiveTrustTheme.teal)
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
                            CompetitiveTrustTheme.displayFont(
                                size: 18,
                                relativeTo: .headline
                            )
                        )
                        .foregroundStyle(CompetitiveTrustTheme.primaryText)
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
                        .fill(CompetitiveTrustTheme.disabledText)
                        .frame(width: 3, height: 3)
                        .accessibilityHidden(true)
                    Text(
                        contest.cadence == .daily
                            ? "\(contest.daybreakTargetText)/day"
                            : contest.daybreakTargetText
                    )
                    Spacer()
                    TrustStatusPill(
                        text: "\(contest.stakeText) each",
                        kind: .pledge
                    )
                }
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 12.5,
                        relativeTo: .caption
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)

                Text(contextText)
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 11.5,
                            relativeTo: .caption
                        )
                    )
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            }
            .trustCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var statusPill: some View {
        if contest.myStatus == .invited {
            TrustStatusPill(text: "Action needed", kind: .action)
        } else if contest.status == .active {
            TrustStatusPill(text: "Live", kind: .live)
        } else if contest.status == .finalized {
            TrustStatusPill(text: "Final", kind: .positive)
        } else {
            TrustStatusPill(text: "Upcoming", kind: .neutral)
        }
    }

    private var participantColors: [Color] {
        let participantIDs = contest.resolvedParticipants.map(\.userID)
        return participantIDs.map {
            CompetitiveTrustTheme.participantColor(
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
                Text("Refreshing live state…")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("state.loading")
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Label("Couldn’t refresh", systemImage: "wifi.slash")
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Try again", action: retry)
                    .font(.subheadline.weight(.semibold))
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
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
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
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .foregroundStyle(emphasis)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}
