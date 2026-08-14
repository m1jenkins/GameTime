import Foundation

// MARK: - Empirical Verification Harness for M2 (TodayView & PersonalPaceComponents)

struct VerificationReport {
    var passedChecks = 0
    var failedChecks = 0
    var errors: [String] = []
    
    mutating func assert(_ condition: Bool, _ message: String) {
        if condition {
            passedChecks += 1
            print("  [PASS] \(message)")
        } else {
            failedChecks += 1
            errors.append(message)
            print("  [FAIL] \(message)")
        }
    }
}

var report = VerificationReport()

print("==================================================")
print("  EMPIRICAL CHALLENGER M2 VERIFICATION SUITE")
print("==================================================")

let todayViewPath = "/Users/user/Documents/GitHub/GameTime/ios/GameTime/GameTime/TodayView.swift"
let paceComponentsPath = "/Users/user/Documents/GitHub/GameTime/ios/GameTime/GameTime/PersonalPaceComponents.swift"

guard let todayContent = try? String(contentsOfFile: todayViewPath, encoding: .utf8) else {
    fatalError("Could not read TodayView.swift at \(todayViewPath)")
}

guard let paceContent = try? String(contentsOfFile: paceComponentsPath, encoding: .utf8) else {
    fatalError("Could not read PersonalPaceComponents.swift at \(paceComponentsPath)")
}

// --------------------------------------------------
// 1. Accessibility Identifiers Check
// --------------------------------------------------
print("\n--- 1. ACCESSIBILITY IDENTIFIERS VERIFICATION ---")

let expectedTodayIdentifiers = [
    "personal.today.open",
    "personal.create"
]

for identifier in expectedTodayIdentifiers {
    report.assert(
        todayContent.contains("\"\(identifier)\""),
        "TodayView.swift contains accessibilityIdentifier '\(identifier)'"
    )
}

let expectedPaceIdentifiers = [
    "personal.pace.day.\\(day.position)",
    "personal.pace.selected-day",
    "personal.pace.\\(tile.id)",
    "personal.details"
]

for identifier in expectedPaceIdentifiers {
    report.assert(
        paceContent.contains("\"\(identifier)\""),
        "PersonalPaceComponents.swift contains accessibilityIdentifier '\(identifier)'"
    )
}

// --------------------------------------------------
// 2. State & Environment Bindings Check
// --------------------------------------------------
print("\n--- 2. STATE & ENVIRONMENT BINDINGS VERIFICATION ---")

report.assert(
    todayContent.contains("@Environment(PersonalAccountabilityStore.self) private var store"),
    "TodayView properly declares @Environment(PersonalAccountabilityStore.self)"
)

report.assert(
    todayContent.contains("@Environment(AppRouter.self) private var router"),
    "TodayView properly declares @Environment(AppRouter.self)"
)

report.assert(
    todayContent.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"),
    "TodayView properly declares dynamicTypeSize environment variable"
)

report.assert(
    paceContent.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"),
    "PersonalPaceComponents properly declares dynamicTypeSize environment variable"
)

report.assert(
    !todayContent.contains("DaybreakCard"),
    "TodayView does NOT use legacy soft DaybreakCard containers"
)

report.assert(
    !paceContent.contains("DaybreakCard"),
    "PersonalPaceComponents does NOT use legacy soft DaybreakCard containers"
)

report.assert(
    todayContent.contains(".trustCard()"),
    "TodayView uses flat graphite .trustCard() containers"
)

report.assert(
    paceContent.contains(".trustCard()"),
    "PersonalPaceComponents uses flat graphite .trustCard() containers"
)

report.assert(
    todayContent.contains("CompetitiveTrustTheme.tabularFont"),
    "TodayView uses tabular fonts for monospaced metrics"
)

report.assert(
    paceContent.contains("CompetitiveTrustTheme.tabularFont"),
    "PersonalPaceComponents uses tabular fonts for monospaced metrics"
)

// --------------------------------------------------
// 3. docs/COPY.md Vocabulary & Anti-Slop Check
// --------------------------------------------------
print("\n--- 3. COPY COMPLIANCE & ANTI-SLOP VERIFICATION ---")

let forbiddenRegexes = [
    #"\b(friend|friends)\b"#,
    #"\b(invitation|invitations)\b"#,
    #"\b(roster|rosters)\b"#,
    #"\b(competitor|competitors)\b"#,
    #"\b(rank|ranks)\b"#,
    #"\b(standing|standings)\b"#,
    #"\b(winner|winners|winning)\b"#,
    #"\b(charity|charities)\b"#,
    #"\b(reaction|reactions)\b"#,
    #"\btie[- ]?break\b"#,
    "B//B",
    "Better Bet"
]

let fullCode = todayContent + "\n" + paceContent

for pattern in forbiddenRegexes {
    let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    let matches = regex.matches(in: fullCode, range: NSRange(fullCode.startIndex..., in: fullCode))
    report.assert(
        matches.isEmpty,
        "Zero matches for forbidden term pattern '\(pattern)'"
    )
}

// Check for AI-slop anti-patterns: gradient text, pastel pills, generic greetings
let slopRegexes = [
    "LinearGradient",
    "RadialGradient",
    "AngularGradient",
    "GreetingHeader",
    "Good morning",
    "Good afternoon",
    "Good evening"
]

for pattern in slopRegexes {
    report.assert(
        !fullCode.contains(pattern),
        "Zero matches for AI-slop pattern '\(pattern)'"
    )
}

// --------------------------------------------------
// SUMMARY & VERDICT
// --------------------------------------------------
print("\n==================================================")
print("  SUMMARY: \(report.passedChecks) Passed, \(report.failedChecks) Failed")
print("==================================================")

if report.failedChecks > 0 {
    print("\n[VERDICT: REJECT]")
    for err in report.errors {
        print(" - \(err)")
    }
    exit(1)
} else {
    print("\n[VERDICT: APPROVE]")
    exit(0)
}
