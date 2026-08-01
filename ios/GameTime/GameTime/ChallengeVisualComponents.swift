import Foundation
import SwiftUI

struct DaybreakSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(
                CompetitiveTrustTheme.uiFont(
                    size: 11,
                    relativeTo: .caption,
                    weight: .bold
                )
            )
            .tracking(1.05)
            .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

enum DaybreakCardTone: Equatable {
    case standard
    case inverse
}

struct DaybreakCard<Content: View>: View {
    let tone: DaybreakCardTone
    let content: Content

    init(
        tone: DaybreakCardTone = .standard,
        @ViewBuilder content: () -> Content
    ) {
        self.tone = tone
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(
                tone == .inverse
                    ? Color.white
                    : CompetitiveTrustTheme.primaryText
            )
            .background(background, in: cardShape)
            .overlay {
                if tone == .standard {
                    cardShape
                        .stroke(CompetitiveTrustTheme.border, lineWidth: 1)
                }
            }
            .shadow(
                color: CompetitiveTrustTheme.primaryText.opacity(
                    tone == .standard ? 0.05 : 0
                ),
                radius: 7,
                y: 3
            )
    }

    private var background: Color {
        tone == .inverse
            ? CompetitiveTrustTheme.primaryText
            : CompetitiveTrustTheme.card
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }
}

struct ChallengeFieldParticipant: Identifiable {
    let id: UUID
    let name: String
    let initials: String
    let progress: Double
    let value: String
    let note: String?
    let color: Color
    let isCurrentUser: Bool
}

struct ChallengeField: View {
    let participants: [ChallengeFieldParticipant]
    let paceProgress: Double?
    let goalLabel: String
    var dense = false

    var body: some View {
        VStack(alignment: .leading, spacing: dense ? 10 : 14) {
            GeometryReader { geometry in
                let labelWidth: CGFloat = dense ? 52 : 61
                let railStart = labelWidth + 9
                let railWidth = max(0, geometry.size.width - railStart)

                Text("START")
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )

                if let paceProgress {
                    Text("PACE")
                        .position(
                            x: min(
                                max(
                                    railStart + railWidth * paceProgress,
                                    railStart + 18
                                ),
                                geometry.size.width - 62
                            ),
                            y: 6
                        )
                }

                Text(goalLabel.uppercased())
                    .foregroundStyle(CompetitiveTrustTheme.mintInk)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .trailing
                    )
            }
            .frame(height: 12)
            .font(
                CompetitiveTrustTheme.uiFont(
                    size: 9,
                    relativeTo: .caption2,
                    weight: .bold
                )
            )
            .tracking(0.85)
            .foregroundStyle(CompetitiveTrustTheme.tertiaryText)

            ForEach(participants) { participant in
                ChallengeFieldLane(
                    participant: participant,
                    paceProgress: paceProgress,
                    dense: dense
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Challenge field")
    }
}

private struct ChallengeFieldLane: View {
    let participant: ChallengeFieldParticipant
    let paceProgress: Double?
    let dense: Bool

    private var boundedProgress: Double {
        min(max(participant.progress, 0), 1)
    }

    private var isBehindPace: Bool {
        guard let paceProgress else { return false }
        return boundedProgress + 0.001 < paceProgress
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dense ? 4 : 7) {
            HStack(spacing: 9) {
                Text(participant.name)
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: dense ? 11.5 : 13,
                            relativeTo: .caption,
                            weight: participant.isCurrentUser ? .bold : .semibold
                        )
                    )
                    .foregroundStyle(
                        participant.isCurrentUser
                            ? CompetitiveTrustTheme.coralInk
                            : CompetitiveTrustTheme.primaryText
                    )
                    .lineLimit(1)
                    .frame(width: dense ? 52 : 61, alignment: .leading)

                GeometryReader { geometry in
                    let width = geometry.size.width
                    let markerSize: CGFloat = dense ? 20 : 28
                    let markerCenter = min(
                        max(markerSize / 2, width * boundedProgress),
                        width - markerSize / 2
                    )

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(CompetitiveTrustTheme.rail)

                        Capsule()
                            .fill(
                                participant.color.opacity(
                                    isBehindPace ? 0.30 : 0.82
                                )
                            )
                            .frame(
                                width: max(markerCenter, markerSize / 2)
                            )

                        if let paceProgress {
                            ChallengeVerticalGuide(
                                color: CompetitiveTrustTheme.guide,
                                dash: [3, 3]
                            )
                            .offset(
                                x: min(
                                    max(0, width * paceProgress),
                                    width - 1
                                )
                            )
                        }

                        ChallengeVerticalGuide(
                            color: CompetitiveTrustTheme.mint,
                            dash: [3, 3],
                            lineWidth: 2
                        )
                        .offset(x: max(0, width - 2))

                        Text(participant.initials)
                            .font(
                                CompetitiveTrustTheme.uiFont(
                                    size: dense ? 8 : 10,
                                    relativeTo: .caption2,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(
                                isBehindPace
                                    ? participant.color
                                    : Color.white
                            )
                            .frame(
                                width: markerSize,
                                height: markerSize
                            )
                            .background(
                                isBehindPace
                                    ? CompetitiveTrustTheme.card
                                    : participant.color,
                                in: Circle()
                            )
                            .overlay {
                                Circle()
                                    .stroke(
                                        participant.color,
                                        lineWidth: isBehindPace ? 2 : 0
                                    )
                            }
                            .shadow(
                                color: participant.color.opacity(0.16),
                                radius: 3,
                                y: 1
                            )
                            .offset(x: markerCenter - markerSize / 2)
                    }
                }
                .frame(height: dense ? 20 : 28)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Color.clear
                    .frame(width: dense ? 52 : 61, height: 1)

                if !dense, let note = participant.note {
                    Text(note)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(participant.value)
                    .fontWeight(.bold)
                    .monospacedDigit()
            }
            .font(
                CompetitiveTrustTheme.uiFont(
                    size: dense ? 10.5 : 11.5,
                    relativeTo: .caption
                )
            )
            .foregroundStyle(CompetitiveTrustTheme.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [
                participant.name,
                participant.value,
                participant.note,
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        )
    }
}

private struct ChallengeVerticalGuide: View {
    let color: Color
    let dash: [CGFloat]
    var lineWidth: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                path.move(to: .zero)
                path.addLine(
                    to: CGPoint(x: 0, y: geometry.size.height)
                )
            }
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    dash: dash
                )
            )
        }
        .frame(width: lineWidth)
        .accessibilityHidden(true)
    }
}

struct ChallengeCountdown: View {
    let startsAt: Date
    let timeZoneName: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 6) {
                Text(countdownText(now: context.date))
                    .font(
                        CompetitiveTrustTheme.displayFont(
                            size: 38,
                            relativeTo: .largeTitle
                        )
                    )
                    .tracking(-1.2)
                    .monospacedDigit()
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)

                Text(scheduleText)
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 12.5,
                            relativeTo: .caption
                        )
                    )
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Starts in \(countdownText(now: context.date))")
        }
    }

    private var scheduleText: String {
        var value = startsAt.formatted(
            .dateTime.weekday(.abbreviated)
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
        )
        if let timeZoneName, !timeZoneName.isEmpty {
            value += " · \(timeZoneName)"
        }
        return value
    }

    private func countdownText(now: Date) -> String {
        let interval = max(0, Int(startsAt.timeIntervalSince(now)))
        let hours = interval / 3_600
        let minutes = (interval % 3_600) / 60
        let seconds = interval % 60
        return String(
            format: "%02d:%02d:%02d",
            hours,
            minutes,
            seconds
        )
    }
}

struct ChallengeZeroField: View {
    let laneCount: Int
    let goalLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("START")
                Spacer()
                Text(goalLabel.uppercased())
                    .foregroundStyle(CompetitiveTrustTheme.mintInk)
            }
            .font(
                CompetitiveTrustTheme.uiFont(
                    size: 9,
                    relativeTo: .caption2,
                    weight: .bold
                )
            )
            .tracking(0.85)
            .foregroundStyle(CompetitiveTrustTheme.tertiaryText)

            ZStack(alignment: .trailing) {
                VStack(spacing: 9) {
                    ForEach(0..<max(2, min(laneCount, 6)), id: \.self) { _ in
                        Capsule()
                            .fill(CompetitiveTrustTheme.rail)
                            .frame(height: 8)
                    }
                }

                ChallengeVerticalGuide(
                    color: CompetitiveTrustTheme.mint,
                    dash: [3, 3],
                    lineWidth: 2
                )
                .frame(width: 2)
            }

            Text("Everyone starts on zero.")
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 11.5,
                        relativeTo: .caption
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ChallengeStatTile: View {
    let label: String
    let value: String
    let caption: String
    var pledge = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 9,
                        relativeTo: .caption2,
                        weight: .bold
                    )
                )
                .tracking(0.8)
                .foregroundStyle(
                    pledge
                        ? CompetitiveTrustTheme.sunInk
                        : CompetitiveTrustTheme.tertiaryText
                )
            Text(value)
                .font(
                    CompetitiveTrustTheme.displayFont(
                        size: 17,
                        relativeTo: .headline
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(caption)
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 10,
                        relativeTo: .caption2
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                .lineLimit(2)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(
            pledge
                ? CompetitiveTrustTheme.sunTint
                : CompetitiveTrustTheme.card,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    pledge
                        ? CompetitiveTrustTheme.sun.opacity(0.34)
                        : CompetitiveTrustTheme.border,
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .combine)
    }
}

struct ChallengeRosterChip: View {
    let initials: String
    let name: String
    let color: Color
    let isPending: Bool

    var body: some View {
        HStack(spacing: 7) {
            InitialsAvatar(
                initials: initials,
                size: 24,
                color: color,
                muted: isPending
            )
            Text(name)
                .lineLimit(1)
            if isPending {
                Circle()
                    .fill(CompetitiveTrustTheme.sun)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
        }
        .font(
            CompetitiveTrustTheme.uiFont(
                size: 12,
                relativeTo: .caption,
                weight: .semibold
            )
        )
        .foregroundStyle(
            isPending
                ? CompetitiveTrustTheme.secondaryText
                : CompetitiveTrustTheme.primaryText
        )
        .padding(.leading, 5)
        .padding(.trailing, 10)
        .frame(minHeight: 32)
        .background(
            isPending
                ? CompetitiveTrustTheme.paperSunk.opacity(0.72)
                : CompetitiveTrustTheme.paper,
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(CompetitiveTrustTheme.border, lineWidth: 1)
        }
        .accessibilityLabel(
            isPending ? "\(name), pending" : "\(name), accepted"
        )
    }
}

extension ContestMetric {
    func daybreakDisplayText(
        value: Double,
        compact: Bool = false
    ) -> String {
        switch self {
        case .distanceMeters:
            let miles = value / 1_609.344
            return "\(miles.formatted(.number.precision(.fractionLength(0...2)))) mi"
        case .steps:
            return compact
                ? "\(value.formatted(.number.notation(.compactName)))"
                : "\(value.formatted(.number.precision(.fractionLength(0)))) steps"
        case .activeEnergyKilocalories:
            return "\(value.formatted(.number.precision(.fractionLength(0...1)))) kcal"
        case .exerciseMinutes:
            return "\(value.formatted(.number.precision(.fractionLength(0...1)))) min"
        }
    }
}

extension ContestCard {
    var daybreakTargetText: String {
        metric.daybreakDisplayText(value: targetValue)
    }

    var daybreakGoalLabel: String {
        let target = metric.daybreakDisplayText(
            value: targetValue,
            compact: true
        )
        return cadence == .daily ? "Goal \(target)/day" : "Goal \(target)"
    }

    var daybreakWindowText: String {
        let dayCount = max(
            1,
            Calendar.current.dateComponents(
                [.day],
                from: startsAt,
                to: endsAt
            ).day ?? 1
        )
        return dayCount == 1 ? "1 day" : "\(dayCount) days"
    }
}
