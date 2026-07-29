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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(contest.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    statusPill
                }

                HStack(spacing: 14) {
                    Label(contest.metric.title, systemImage: "waveform.path.ecg")
                    Label(contest.targetText, systemImage: "target")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {
                    Text(contest.stakeText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CompetitiveTrustTheme.amber)
                    Text("test pledge")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(
                        contest.startsAt,
                        format: .dateTime.month(.abbreviated).day()
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
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
            TrustStatusPill(text: "Active", kind: .verified)
        } else if contest.status == .finalized {
            TrustStatusPill(text: "Final", kind: .verified)
        } else {
            TrustStatusPill(text: "Upcoming", kind: .neutral)
        }
    }

    private var accessibilitySummary: String {
        let state = contest.myStatus == .invited
            ? "Invitation, action needed"
            : contest.status.rawValue
        return "\(contest.title), \(state), \(contest.targetText), \(contest.stakeText) test pledge"
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
