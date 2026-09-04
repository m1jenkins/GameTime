import SwiftUI

/// The seven frozen local dates of an open challenge, in challenge order.
///
/// This is not a Sunday-start calendar widget. Day 0 is the challenge start
/// date. Shape carries met / today / remaining so status is not color alone.
struct PersonalChallengeWeekRow: Equatable {
    enum Mark: Equatable {
        case upcoming
        case today
        case met
        case underGoal
        case didNotCount
        case waiting
    }

    struct Day: Identifiable, Equatable {
        let id: String
        let position: Int
        let localDate: String
        let weekdayLabel: String
        let mark: Mark
        let accessibilityLabel: String
        let accessibilityValue: String
    }

    let days: [Day]

    init(pace: PersonalPaceSummary) {
        days = pace.days.map { day in
            let text = pace.detailText(for: day)
            return Day(
                id: day.id,
                position: day.position,
                localDate: day.id,
                weekdayLabel: Self.narrowWeekday(for: day.id),
                mark: Mark(verdict: day.verdict),
                accessibilityLabel: "\(day.longLabel), \(text.value)",
                accessibilityValue: text.caption
            )
        }
    }

    private static func narrowWeekday(for localDate: String) -> String {
        let parts = localDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return "" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        guard let date = calendar.date(from: components) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return formatter.string(from: date)
    }
}

extension PersonalChallengeWeekRow.Mark {
    init(verdict: PersonalPaceSummary.Verdict) {
        switch verdict {
        case .future:
            self = .upcoming
        case .today:
            self = .today
        case .metGoal:
            self = .met
        case .underGoal:
            self = .underGoal
        case .waived, .problem:
            self = .didNotCount
        case .waiting:
            self = .waiting
        }
    }

    var spokenStatus: String {
        switch self {
        case .upcoming: "Not yet"
        case .today: "Today"
        case .met: "Met"
        case .underGoal: "Under"
        case .didNotCount: "Didn’t count"
        case .waiting: "Waiting"
        }
    }
}

struct PersonalTodayHeroPresentation: Equatable {
    let displayedSteps: Int
    let stepsText: String
    let remainingText: String
    let receiptText: String
    let openActionTitle: String
    let accessibilityLabel: String
    let accessibilityValue: String
    let fraction: Double
    let week: PersonalChallengeWeekRow

    init(
        terms: FrozenPersonalTerms,
        progress: PersonalDisplayedProgress,
        pace: PersonalPaceSummary
    ) {
        let presentation = PersonalProgressPresentation(
            progress: progress,
            terms: terms
        )
        displayedSteps = presentation.displayedSteps
        stepsText = presentation.stepsText
        remainingText = presentation.remainingText
        accessibilityLabel = presentation.accessibilityLabel
        accessibilityValue = presentation.accessibilityValue
        fraction = presentation.fraction
        receiptText = [
            terms.commitmentText,
            terms.cadence.title,
            pace.dayCountText,
        ].joined(separator: " · ")
        openActionTitle = "See this week"
        week = PersonalChallengeWeekRow(pace: pace)
    }
}

struct PersonalWeekRow: View {
    let row: PersonalChallengeWeekRow
    var action: ((PersonalChallengeWeekRow.Day) -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(row.days) { day in
                        dayButton(day, compact: false)
                    }
                }
            } else {
                HStack(spacing: 4) {
                    ForEach(row.days) { day in
                        dayButton(day, compact: true)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .accessibilityIdentifier("personal.today.week")
    }

    private func dayButton(
        _ day: PersonalChallengeWeekRow.Day,
        compact: Bool
    ) -> some View {
        Button {
            action?(day)
        } label: {
            if compact {
                VStack(spacing: 6) {
                    PersonalWeekDayMark(mark: day.mark)
                    Text(day.weekdayLabel)
                        .font(
                            CompetitiveTrustTheme.tabularFont(
                                size: 11,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(labelColor(for: day.mark))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(minHeight: 44)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            } else {
                HStack(spacing: 12) {
                    PersonalWeekDayMark(mark: day.mark)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.weekdayLabel)
                            .font(
                                CompetitiveTrustTheme.uiFont(
                                    size: 17,
                                    relativeTo: .headline,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(CompetitiveTrustTheme.primaryText)
                        Text(day.mark.spokenStatus)
                            .font(
                                CompetitiveTrustTheme.uiFont(
                                    size: 15,
                                    relativeTo: .subheadline
                                )
                            )
                            .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.accessibilityLabel)
        .accessibilityValue(day.accessibilityValue)
        .accessibilityIdentifier("personal.pace.day.\(day.position)")
    }

    private func labelColor(for mark: PersonalChallengeWeekRow.Mark) -> Color {
        switch mark {
        case .today, .met:
            CompetitiveTrustTheme.primaryText
        case .didNotCount:
            CompetitiveTrustTheme.didNotCount
        default:
            CompetitiveTrustTheme.tertiaryText
        }
    }
}

private struct PersonalWeekDayMark: View {
    let mark: PersonalChallengeWeekRow.Mark

    private let size: CGFloat = 28

    var body: some View {
        ZStack {
            switch mark {
            case .upcoming:
                Circle()
                    .stroke(CompetitiveTrustTheme.hairlineDivider, lineWidth: 1.5)
            case .today:
                Circle()
                    .stroke(CompetitiveTrustTheme.pine, lineWidth: 1.5)
                Circle()
                    .fill(CompetitiveTrustTheme.pine)
                    .padding(7)
            case .met:
                Circle()
                    .fill(CompetitiveTrustTheme.pine)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CompetitiveTrustTheme.onPine)
            case .underGoal:
                Circle()
                    .stroke(CompetitiveTrustTheme.secondaryText, lineWidth: 1.5)
                Capsule()
                    .fill(CompetitiveTrustTheme.secondaryText)
                    .frame(width: 10, height: 2)
            case .didNotCount:
                Circle()
                    .stroke(CompetitiveTrustTheme.didNotCount, lineWidth: 1.5)
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CompetitiveTrustTheme.didNotCount)
            case .waiting:
                Circle()
                    .stroke(
                        CompetitiveTrustTheme.tertiaryText,
                        style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])
                    )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
