import Foundation

struct PersonalCommitmentProtectionPresentation: Equatable, Sendable {
    let text: String

    init(
        amountMinor: Int,
        settlementMode: PersonalSettlementMode
    ) {
        let amount = PersonalChallengeReceiptPresentation.amountText(
            amountMinor
        )
        text = switch settlementMode {
        case .testOnly:
            "\(amount) test commitment. No money will be charged. Missing or unclear step data never counts as a miss."
        case .stripeSandbox:
            "Your test charge is $0 when you meet your goal or step data is missing or unclear. Only a confirmed miss after review can create one \(amount) test charge."
        }
    }
}

/// A display-only receipt built from the choices already held by the creation
/// flow. It does not validate, persist, or reinterpret the challenge request.
struct PersonalChallengeReceiptPresentation: Equatable, Sendable {
    struct Group: Equatable, Identifiable, Sendable {
        enum Identifier: String, Hashable, Sendable {
            case challenge
            case start
            case payment
        }

        let id: Identifier
        let title: String
        let facts: [Fact]
    }

    struct Fact: Equatable, Identifiable, Sendable {
        enum Identifier: String, Hashable, Sendable {
            case howItCounts = "how-it-counts"
            case goal
            case amount
            case length
            case starts
            case dayOne = "day-one"
            case timeZone = "time-zone"
            case finalCheck = "final-check"
            case paymentMode = "payment-mode"
            case zeroOutcomes = "zero-outcomes"
            case confirmedMiss = "confirmed-miss"
            case review
            case missingData = "missing-data"
        }

        let id: Identifier
        let label: String
        let value: String
    }

    struct Detail: Equatable, Identifiable, Sendable {
        enum Identifier: String, Hashable, Sendable {
            case cadence
            case dayOne = "day-one"
            case cancellation
            case savedDraft = "saved-draft"
        }

        let id: Identifier
        let title: String
        let text: String
    }

    let groups: [Group]
    let details: [Detail]
    let dayOneExplanation: String

    init(
        draft: PersonalChallengeDraft,
        startsImmediately: Bool,
        settlementMode: PersonalSettlementMode,
        paymentMethodSaved: Bool,
        hasSavedDraft: Bool
    ) {
        let amount = Self.amountText(draft.commitmentAmountMinor)
        let firstDayHours = PersonalChallengeStart.firstDayHours(
            startsAt: draft.startsAt,
            timezone: draft.timezone
        )
        let startTime = Self.startTimeText(
            draft.startsAt,
            timezone: draft.timezone
        )

        dayOneExplanation = Self.dayOneExplanation(
            draft: draft,
            startsImmediately: startsImmediately,
            firstDayHours: firstDayHours,
            startTime: startTime
        )

        groups = [
            Group(
                id: .challenge,
                title: "Your challenge",
                facts: [
                    Fact(
                        id: .howItCounts,
                        label: "How it counts",
                        value: draft.cadence.title
                    ),
                    Fact(
                        id: .goal,
                        label: "Goal",
                        value: draft.cadence == .daily
                            ? "\(draft.targetSteps.formatted()) steps a day"
                            : "\(draft.targetSteps.formatted()) steps this week"
                    ),
                    Fact(id: .amount, label: "Amount", value: amount),
                    Fact(
                        id: .length,
                        label: "Length",
                        value: Self.lengthText(
                            startsImmediately: startsImmediately,
                            firstDayHours: firstDayHours,
                            startTime: startTime
                        )
                    ),
                ]
            ),
            Group(
                id: .start,
                title: "When it starts",
                facts: [
                    Fact(
                        id: .starts,
                        label: "Starts",
                        value: startsImmediately
                            ? "Now — today counts from midnight"
                            : PersonalTermsDateFormatter.dateTime(
                                draft.startsAt,
                                timezoneIdentifier: draft.timezone
                            )
                    ),
                    Fact(
                        id: .dayOne,
                        label: "Day one",
                        value: Self.dayOneText(
                            startsImmediately: startsImmediately,
                            firstDayHours: firstDayHours,
                            startTime: startTime
                        )
                    ),
                    Fact(
                        id: .timeZone,
                        label: "Time zone",
                        value: draft.timezone
                    ),
                    Fact(
                        id: .finalCheck,
                        label: "Final check",
                        value: "24 hours after your last day"
                    ),
                ]
            ),
            Group(
                id: .payment,
                title: "Payment protection",
                facts: Self.paymentFacts(
                    settlementMode: settlementMode,
                    amount: amount,
                    paymentMethodSaved: paymentMethodSaved
                )
            ),
        ]

        details = [
            Detail(
                id: .cadence,
                title: "How it counts",
                text: Self.cadenceExplanation(draft.cadence)
            ),
            Detail(
                id: .dayOne,
                title: "Day one",
                text: dayOneExplanation
            ),
            Detail(
                id: .cancellation,
                title: "Before it starts",
                text: settlementMode == .stripeSandbox
                    ? "Cancel before your challenge starts to close the payment terms before settlement."
                    : "Cancel before your challenge starts to close the test commitment."
            ),
            Detail(
                id: .savedDraft,
                title: "Saved draft",
                text: hasSavedDraft
                    ? "GameTime saved exactly what you picked on this phone so you can safely retry or delete it."
                    : "If starting is interrupted, GameTime saves exactly what you picked on this phone so you can safely retry or delete it."
            ),
        ]
    }

    static func amountText(_ amountMinor: Int) -> String {
        (Double(amountMinor) / 100).formatted(.currency(code: "USD"))
    }

    private static func paymentFacts(
        settlementMode: PersonalSettlementMode,
        amount: String,
        paymentMethodSaved: Bool
    ) -> [Fact] {
        switch settlementMode {
        case .testOnly:
            [
                Fact(
                    id: .paymentMode,
                    label: "Mode",
                    value: EnvironmentDisclosureCopy.testOnly
                ),
                Fact(
                    id: .zeroOutcomes,
                    label: "Outcomes",
                    value: "No money will be charged"
                ),
                Fact(
                    id: .missingData,
                    label: "Missing or unclear data",
                    value: "Never counts as a miss"
                ),
            ]
        case .stripeSandbox:
            [
                Fact(
                    id: .paymentMode,
                    label: "Payment",
                    value: paymentMethodSaved
                        ? "Test method saved — no real money moves."
                        : EnvironmentDisclosureCopy.stripeSandbox
                ),
                Fact(
                    id: .zeroOutcomes,
                    label: "$0 outcomes",
                    value: "Goal met, or step data missing or unclear"
                ),
                Fact(
                    id: .confirmedMiss,
                    label: "Confirmed miss",
                    value: "One \(amount) test charge, only after review"
                ),
                Fact(
                    id: .review,
                    label: "Review",
                    value: "Seven days — settlement paused"
                ),
            ]
        }
    }

    private static func cadenceExplanation(
        _ cadence: PersonalChallengeCadence
    ) -> String {
        switch cadence {
        case .daily:
            "Hit your goal on all seven days. Missing or unclear step data never counts against you."
        case .cumulative:
            "Reach your total by the end of the week. Missing or unclear step data never counts against you."
        }
    }

    private static func startTimeText(
        _ date: Date,
        timezone: String
    ) -> String {
        date.formatted(
            Date.FormatStyle(
                date: .omitted,
                time: .shortened,
                timeZone: TimeZone(identifier: timezone)
                    ?? TimeZone(secondsFromGMT: 0)!
            )
        )
    }

    private static func lengthText(
        startsImmediately: Bool,
        firstDayHours: Int,
        startTime: String
    ) -> String {
        if startsImmediately {
            return "Seven days, counting from midnight today"
        }
        return firstDayHours == 24
            ? "Seven full days"
            : "Seven days, starting at \(startTime) on day one"
    }

    private static func dayOneText(
        startsImmediately: Bool,
        firstDayHours: Int,
        startTime: String
    ) -> String {
        if startsImmediately {
            return "Eligible steps since midnight today count"
        }
        return firstDayHours == 24
            ? "Midnight to midnight"
            : "\(firstDayHours) \(firstDayHours == 1 ? "hour" : "hours"), \(startTime) to midnight"
    }

    private static func dayOneExplanation(
        draft: PersonalChallengeDraft,
        startsImmediately: Bool,
        firstDayHours: Int,
        startTime: String
    ) -> String {
        if startsImmediately {
            let shared =
                "Day one counts eligible steps from midnight today and runs until midnight. Days two to seven are full."
            return draft.cadence == .daily
                ? shared
                    + " Steps you took before starting count toward today’s \(draft.targetSteps.formatted())-step goal."
                : shared
                    + " Steps you took before starting count toward your week total."
        }
        if firstDayHours == 24 {
            return "Seven full days. Day one runs midnight to midnight."
        }
        let shared =
            "Day one is short — \(firstDayHours) \(firstDayHours == 1 ? "hour" : "hours"), from \(startTime) until midnight. Days two to seven are full."
        guard draft.cadence == .daily else {
            return shared
                + " You’re going for one total, so this just leaves you less time."
        }
        return shared
            + " You’ll still need \(draft.targetSteps.formatted()) steps in it."
    }
}
