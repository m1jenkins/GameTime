import SwiftUI

enum LiveGoalRuleSection: CaseIterable, Hashable {
    case goals, activity, dates, result, stake, review, leave, sharing
}

/// The saved agreement, organized for reading without changing its policy.
struct LiveGoalRules: View {
    let row: ChallengeV1
    let actor: UUID?
    var expandedSections: Set<LiveGoalRuleSection> = [.goals]
    /// The server reports that this account's activity carries no device check.
    var accountMode = false

    private var minimum: Int {
        row.agreement?.terms?["minimum"]?.integer ?? (row.format.mode == .personal ? 1 : 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(LiveChallengePresentation.title(row)) · \(ChallengePresentation.dates(row))")
                .liveFont(14).foregroundStyle(SignalTheme.textSecondary)
                .padding(.bottom, 6)
            LiveRuleModule(symbol: "flag", title: row.format.hasTarget ? "Everyone’s goal" : "How results count",
                           subtitle: row.format.hasTarget ? ownGoal : row.format.metric.title, expanded: expandedSections.contains(.goals)) {
                if row.format.hasTarget {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(row.members.filter { $0.selected && !$0.exited }) { person in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(person.actorId == actor ? "You" : person.username)
                                    .liveFont(12, weight: .medium).foregroundStyle(SignalTheme.textSecondary)
                                Text(person.target.map { row.format.metric.display($0) } ?? "Not chosen")
                                    .liveFont(22, weight: .bold).tracking(-0.7)
                                    .minimumScaleFactor(0.7).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .background(SignalTheme.soft, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                rule(row.format.scoring)
            }
            LiveRuleModule(symbol: "applewatch", title: "Activity that counts", subtitle: LiveGoalCopy.sourceTitle(row), expanded: expandedSections.contains(.activity)) {
                if let source = row.sourcePolicyVersion {
                    rule(ChallengeHealthCopy.source(source, leaderboard: row.format.usesReceivedScores))
                    if accountMode { rule(ChallengeHealthCopy.accountMode) }
                    if row.format.usesReceivedScores {
                        rule("We rank what GameTime saves, without checking that your entire Apple Health history is available. Refresh to send activity and check your saved score. An update counts only after GameTime confirms it.")
                        rule("If we can’t save an update, use Refresh to recover it. If your result is still wrong, ask us to review it before the review deadline.")
                    } else {
                        rule("An observed result can confirm that you met your goal. Missing or incomplete activity cannot confirm a missed goal or a ranking.")
                    }
                    if let distance = row.config.distanceMm {
                        rule("Whole outdoor run: \(ChallengeTimedDistanceCopy.range(distance)), including both distances. The whole run must fit inside these dates. Time from start to finish includes pauses.")
                    }
                } else {
                    rule("Source: fictional activity for this local preview. No Apple Health activity is scored.")
                    if let distance = row.config.distanceMm {
                        rule("Whole run distance: \(ChallengeV1Policy.Metric.distance.display(distance)). Only fictional matching runs are available until the distance rules pass physical testing.")
                    }
                }
            }
            LiveRuleModule(symbol: "calendar", title: "Dates and times", subtitle: SignalTimeZone.name(row.config.timezone), expanded: expandedSections.contains(.dates)) {
                LiveGoalFact(label: "Starts", value: row.config.startsAt.text(zone: row.config.timezone))
                LiveGoalFact(label: "Ends, not included", value: row.config.endsAt.text(zone: row.config.timezone))
                if row.format.usesReceivedScores {
                    LiveGoalFact(label: "Save activity by", value: row.config.correctionsBy.text(zone: row.config.timezone))
                    rule("First updates and corrections count through this deadline, including the exact deadline.")
                } else {
                    LiveGoalFact(label: "First updates close", value: row.config.syncBy.text(zone: row.config.timezone))
                    LiveGoalFact(label: "Corrections close", value: row.config.correctionsBy.text(zone: row.config.timezone))
                }
                rule("Results can settle after corrections close, your result notice and any review.")
            }
            LiveRuleModule(symbol: "checkmark.shield", title: "Your result", subtitle: row.format.hasTarget ? "Only a confirmed miss counts" : "Saved results decide", expanded: expandedSections.contains(.result)) {
                rule(row.format.missing)
            }
            LiveRuleModule(symbol: "dollarsign", title: "Your stake", subtitle: LiveGoalCopy.stake(row), expanded: expandedSections.contains(.stake)) {
                rule("\(challengeMoney(row.config.amountCents)) simulated per person. Nothing can be paid out or redeemed. No real money moves.")
                rule(row.format.allocation)
            }
            LiveRuleModule(symbol: "checkmark.shield", title: "Ask for review", subtitle: "48 hours from your result notice", expanded: expandedSections.contains(.review)) {
                rule("You have 48 hours after the actual result notice to ask for a review. Reviewers have 72 hours after your request. A processing delay never shortens those windows.")
                rule("An assigned reviewer can inspect the normalized challenge facts needed for your review. Raw Apple Health records are not shared.")
            }
            LiveRuleModule(symbol: "arrow.turn.up.left", title: "Leave the challenge", subtitle: "Before your result is final", expanded: expandedSections.contains(.leave)) {
                rule("You may leave before the result is final. Your simulated entry returns. The challenge continues only if at least \(minimum) eligible \(minimum == 1 ? "person remains" : "people remain").")
            }
            LiveRuleModule(symbol: "lock", title: "Sharing and changes", subtitle: row.format.mode == .friend ? "Only your agreed group" : "Your activity stays private", expanded: expandedSections.contains(.sharing)) {
                if row.format.mode == .friend {
                    rule("Everyone agrees to the displayed roster and goals, when this format has goals. Reopening the lobby requires everyone to agree again. Incomplete agreement at the start cancels the challenge.")
                    rule("The selected friends can see your username, agreed goal when there is one, current challenge activity and results. Your activity history outside this challenge stays private.")
                } else {
                    rule("Other participants cannot see your activity or results. Community challenges show anonymous participant counts.")
                }
                rule("Up to three unfinished challenges at once. Friend challenges for the same activity cannot overlap. One community challenge may overlap your friend steps challenge.")
            }
        }
    }

    private var ownGoal: String {
        guard let target = row.own(actor)?.target else { return "Choose your own goal" }
        return "Your goal: \(row.format.metric.display(target))"
    }

    private func rule(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(SignalTheme.textSecondary).frame(width: 3, height: 3).padding(.top, 8)
            Text(text).liveFont(14).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct LiveRuleModule<Content: View>: View {
    let symbol: String
    let title: String
    let subtitle: String
    @State private var expanded: Bool
    @ViewBuilder let content: () -> Content

    init(symbol: String, title: String, subtitle: String, expanded: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.symbol = symbol; self.title = title; self.subtitle = subtitle
        _expanded = State(initialValue: expanded); self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: symbol).font(.system(size: 20, weight: .regular))
                        .foregroundStyle(SignalTheme.accent).frame(width: 24)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).liveFont(15, weight: .semibold).foregroundStyle(SignalTheme.textPrimary)
                        Text(subtitle).liveFont(12).foregroundStyle(SignalTheme.textSecondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(SignalTheme.textSecondary)
                }.padding(16).frame(minHeight: 72)
            }.buttonStyle(.plain).accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded {
                VStack(alignment: .leading, spacing: 12, content: content)
                    .padding(.horizontal, 16).padding(.bottom, 16)
            }
        }.modifier(LiveCardModifier(radius: 18, material: true))
    }
}

struct LiveGoalFact: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).liveFont(12).foregroundStyle(SignalTheme.textSecondary)
            Text(value).liveFont(14, weight: .medium).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum LiveGoalCopy {
    static func stake(_ row: ChallengeV1) -> String { "\(LiveChallengePresentation.money(row.config.amountCents)) simulated · fee $0" }
    static func sourceTitle(_ row: ChallengeV1) -> String {
        guard let source = row.sourcePolicyVersion else { return "Fictional activity" }
        return switch source {
        case "apple_watch_steps_v1": "Apple Watch steps"
        case "apple_watch_exercise_credit_v2": "Apple Watch Activity minutes"
        case "apple_watch_exercise_v1": "Activity source unavailable"
        case "apple_workout_outdoor_distance_v1", "apple_workout_outdoor_timed_v1": "Apple Watch outdoor runs"
        default: "Check activity source"
        }
    }
    static func date(_ instant: ChallengeInstant, row: ChallengeV1, template: String = "MMM d", end: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: row.config.timezone)
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: end ? instant.date.addingTimeInterval(-1) : instant.date)
    }
}
