import SwiftUI

@MainActor
enum GameTimeStyle {
    static let accent = Color(red: 0.10, green: 0.45, blue: 0.34)
    static let accentDark = Color(red: 0.05, green: 0.22, blue: 0.19)
    static let highlight = Color(red: 0.98, green: 0.67, blue: 0.25)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let muted = Color(uiColor: .secondaryLabel)
    static let avatarColors = [
        Color(red: 0.22, green: 0.48, blue: 0.88),
        Color(red: 0.94, green: 0.48, blue: 0.25),
        Color(red: 0.53, green: 0.36, blue: 0.82),
        Color(red: 0.10, green: 0.58, blue: 0.55),
    ]
}

struct PreviewModeBanner: View {
    var body: some View {
        Label("Simulator preview · sample data", systemImage: "sparkles")
            .font(.caption.weight(.semibold))
            .foregroundStyle(GameTimeStyle.accentDark)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(GameTimeStyle.accent.opacity(0.12), in: Capsule())
            .accessibilityLabel("Simulator preview using sample data")
    }
}

struct PreviewSectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.bold())
            Spacer()
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PreviewAvatar: View {
    let initials: String
    let name: String
    var accentIndex = 0
    var size: CGFloat = 48

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                GameTimeStyle.avatarColors[
                    accentIndex % GameTimeStyle.avatarColors.count
                ],
                in: Circle()
            )
            .accessibilityLabel(name)
    }
}

struct PreviewProgressRing: View {
    let progress: Double
    let value: String
    let label: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.22), lineWidth: 10)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    .white,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(value)
                    .font(.title2.bold())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .foregroundStyle(.white)
        }
        .frame(width: 108, height: 108)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(progress * 100)) percent, \(value)")
    }
}

struct PreviewStatusPill: View {
    let text: String
    let systemImage: String
    var tint = GameTimeStyle.accent

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.11), in: Capsule())
    }
}

struct PreviewContestCard: View {
    let contest: PreviewContest

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: contest.metricIcon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(GameTimeStyle.accent)
                    .frame(width: 42, height: 42)
                    .background(
                        GameTimeStyle.accent.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(contest.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(contest.periodLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 5)
            }

            HStack(spacing: 14) {
                PreviewMiniProgress(
                    name: contest.currentParticipant,
                    value: contest.currentValue,
                    target: contest.targetValue,
                    tint: GameTimeStyle.accent
                )
                PreviewMiniProgress(
                    name: contest.opponent,
                    value: contest.opponentValue,
                    target: contest.targetValue,
                    tint: GameTimeStyle.highlight
                )
            }

            HStack {
                Label(contest.evidenceSummary, systemImage: "checkmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(contest.stakeLabel)
                    .font(.caption.bold())
                    .foregroundStyle(GameTimeStyle.accentDark)
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.04), radius: 12, y: 5)
    }
}

struct PreviewMiniProgress: View {
    let name: String
    let value: Int
    let target: Int
    let tint: Color

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(Double(value) / Double(target), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(value)/\(target)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .tint(tint)
        }
        .frame(maxWidth: .infinity)
    }
}

struct PreviewEvidenceRow: View {
    let title: String
    let detail: String
    let systemImage: String
    var tint = GameTimeStyle.accent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.11), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(GameTimeStyle.accent)
                .accessibilityLabel("Verified")
        }
    }
}

struct PreviewValueTile: View {
    let value: String
    let label: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: systemImage)
                .foregroundStyle(GameTimeStyle.accent)
            Text(value)
                .font(.title3.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}
