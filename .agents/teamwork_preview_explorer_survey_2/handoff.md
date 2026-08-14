# Handoff Report: GameTime UI Views, Pace Components, Challenge Screens & Test Suite Audit

## 1. Observation

### 1.1 Key File Paths & Structure
- **Theme & Components**:
  - `ios/GameTime/GameTime/CompetitiveTrustTheme.swift` (lines 4-109: Daybreak theme colors/fonts; lines 218-227: light mode forced navigation bar; lines 240-402: button styles).
  - `ios/GameTime/GameTime/ChallengeVisualComponents.swift` (lines 33-96: `DaybreakCard` implementation; lines 462-522: `ChallengeStatTile`).
  - `ios/GameTime/GameTime/FeatureComponents.swift` (lines 174-223: `InlineLoadStateView`; lines 225-265: `EmptyTrustState`).
  - `ios/GameTime/GameTime/PersonalAccountabilityComponents.swift` (lines 4-125: `PersonalChallengeCard`; lines 170-224: `PersonalProgressBar`; lines 228-279: `PersonalProgressPresentation`; lines 283-416: `PersonalHealthProgressPresentation`; lines 617-702: `PersonalSevenDayTimeline`).
- **Main Views**:
  - `ios/GameTime/GameTime/TodayView.swift` (lines 37-60: header; lines 77-173: `currentChallenge`; lines 175-192: `createCard`).
  - `ios/GameTime/GameTime/PersonalPaceComponents.swift` (lines 11-462: `PersonalPaceSummary`; lines 499-780: `PersonalPaceCard`; lines 792-815: `PersonalPaceTiles`; lines 819-964: `PersonalChallengeDetailsCard`).
  - `ios/GameTime/GameTime/ChallengesView.swift` (lines 8-83: ScrollView & card list; lines 102-151: `pendingRecovery`).
  - `ios/GameTime/GameTime/PersonalChallengeDetailView.swift` (lines 98-182: `hero`; lines 276-293: `pace`; lines 318-350: `result`; lines 353-469: `review`; lines 488-522: `cancellation`).
- **Creation Flow**:
  - `ios/GameTime/GameTime/PersonalChallengeFlow.swift` (lines 42-64: `Step` enum; lines 194-223: `visibleSteps`; lines 225-338: step content switch; lines 294-328: stake selection `$10` to `$50`; lines 578-628: payment step; lines 643-683: review step; lines 823-921: controls).
- **Test Suites & Guidelines**:
  - `ios/GameTime/GameTimeUITests/GameTimeUITests.swift` (lines 29-2103: full UI test suite with exact string assertions, environment disclosures, receipt checks, and forbidden language regex).
  - `docs/COPY.md` (lines 8-15: vocabulary rules; lines 68-87: forward Stripe sandbox copy contract; lines 141-173: domain term mapping table).

### 1.2 Verbatim Observations from Source Code
1. **Daybreak Aesthetic Anti-Patterns**:
   - `CompetitiveTrustTheme.swift`:
     - Line 8: `static let paper = Color(red: 1.00, green: 0.969, blue: 0.941)` (#FFFFF5 warm paper background).
     - Lines 90, 102: Uses `"BricolageGrotesque-96ptExtraBold"` display font and `"HankenGrotesk-Regular"` body font.
     - Line 219: `background(CompetitiveTrustTheme.paper.ignoresSafeArea())`.
     - Line 220: `.preferredColorScheme(.light)` (forces Light mode).
   - `ChallengeVisualComponents.swift`:
     - Line 94: `RoundedRectangle(cornerRadius: 24, style: .continuous)` for `DaybreakCard`.
     - Line 67: `.shadow(color: CompetitiveTrustTheme.primaryText.opacity(tone == .standard ? 0.05 : 0), radius: 7, y: 3)` (soft drop shadows).

2. **TodayView & Pace Components**:
   - `TodayView.swift`:
     - Uses `DaybreakCard(tone: .inverse)` for current challenge hero card, wrapping `PersonalProgressBar` and `PersonalHealthProgressStatus`.
     - Uses `PersonalSevenDayTimeline` inside a second `DaybreakCard` for daily splits.
   - `PersonalPaceComponents.swift`:
     - `PersonalPaceSummary` calculates pacing metrics:
       - Cumulative delta: `+1,200` (`steps ahead of where you need to be`) vs `−3,400` (`steps behind where you need to be`).
       - Daily goal status: `3 of 7` (`days you hit your goal`) or `2,650` (`steps to go today`).
     - `PersonalPaceCard`:
       - Renders vertical bar chart overlaying `PaceGuideLine` dashed stroke.
       - Height: `chartHeight = 132`, `barScale = 128`.
       - Renders clickable day bars (`personal.pace.day.0` to `personal.pace.day.6`).
       - Shows detail card when bar tapped (`personal.pace.selected-day`).
     - `PersonalPaceTiles`:
       - Renders 3 stat tiles (`ChallengeStatTile`): "To finish" (required per-day step volume remaining), "Average" (average steps/day so far), "Left" (days remaining).
       - Accessibility IDs: `personal.pace.finish`, `personal.pace.average`, `personal.pace.left`, `personal.pace.week-total`, `personal.pace.goal-days`.

3. **ChallengesView & PersonalChallengeDetailView**:
   - `ChallengesView.swift`:
     - Uses `PersonalChallengeCard` (`personal.challenge.<uuid>`) for active and finished challenges.
     - Shows `pendingRecovery` card for unfinished setup.
   - `PersonalChallengeDetailView.swift`:
     - Hero block (`hero`): Status pill, commitment text ($10–$50), target text, `PersonalProgressBar`, `PersonalHealthProgressStatus`, Sync now button (`personal.challenge.sync-now`).
     - Pace block (`pace`): `PersonalPaceCard` + `PersonalPaceTiles`.
     - Result block (`result`): `PersonalResultPresentation` card.
     - Review block (`review`): Shown for Stripe sandbox missed goal:
       - Reason buttons: `personal.review.reason.user_disputes_step_data`, `personal.review.reason.user_disputes_result`.
       - Button: `personal.review.request` ("Request a review").
       - Status string: `personal.review.submitted` ("Under review — settlement paused.").
       - Expired string: `personal.review.expired` ("The review request window ended.").
     - Details block: `PersonalChallengeDetailsCard` (`personal.details`).

4. **Creation Flow (`PersonalChallengeFlow.swift`)**:
   - `visibleSteps`: `.cadence` -> `.target` -> `.commitment` -> `.healthAccess` -> `.payment` (sandbox only) -> `.review`.
   - `.cadence`: `personal.cadence.daily` ("Every day"), `personal.cadence.cumulative` ("Week total").
   - `.target`: `personal.target` (number pad text field, range 1 to 1,000,000).
   - `.commitment`: `personal.commitment.1000`, `personal.commitment.2000`, `personal.commitment.3000`, `personal.commitment.4000`, `personal.commitment.5000` ($10 to $50).
   - `.healthAccess`: `personal.health.verify` ("Connect Apple Health").
   - `.payment`: `personal.payment.consent` (toggle), `personal.payment.setup` ("Set up test payment").
   - `.review`: `personal.start.now` (toggle), `personal.submit` ("Start my challenge").

5. **Existing UI Test Assertions (`GameTimeUITests.swift`)**:
   - Navigation titles asserted: `"Today"`, `"Challenges"`, `"You"`, `"How it counts"`, `"Your goal"`, `"Your amount"`, `"Apple Health"`, `"Test payment"`, `"Check and confirm"`, `"Your challenge"`.
   - Environment disclosures asserted:
     - `personal.environment-disclosure`: `"Test commitment — no money will be charged."` (testOnly), `"Payment test mode — no real money moves."` (stripeSandbox), `"Demo mode — no money will be charged. Nothing here leaves your phone."` (demo).
   - Required copy strings:
     - Goal met: `"Goal met — $0 test charge."`
     - Goal missed review open: `"Goal missed — review open. Settlement is paused."`
     - Didn't count: `"This one didn’t count — $0 test charge."`
     - Guarantee: `"Missing or unclear step data never counts as a miss."`
     - Consent sentence: `"By starting, you agree that GameTime may create one $10.00 test charge only if this challenge is confirmed missed after the review window. Missing or unclear step data never counts as a miss."`
   - Strict forbidden language regex in `assertNoForbiddenLanguage`:
     `#"(?i)\b(?:friend|friends|invitation|invitations|roster|rosters|competitor|competitors|rank|ranks|standing|standings|winner|winners|winning|charity|charities|reaction|reactions|tie[- ]?break)\b"#`

---

## 2. Logic Chain

1. **Observation**: `TodayView.swift` and `PersonalChallengeDetailView.swift` currently construct UI using `DaybreakCard` with light-mode warm paper background (`#FFFFF5`), Bricolage display typography, and rounded bento containers.
   **Reasoning**: Transitioning to the Strava-inspired athletic design system (R1/R2) requires replacing `CompetitiveTrustTheme` color palette with pure dark/graphite (`#000000`/`#121212`), Strava Signal Orange (`#FC5200`), athletic green (`#00D084`), sharp hairline dividers (`#2C2C2E`), tabular numbers (`SF Pro Display` / `SF Mono`), and flat non-bento layouts.

2. **Observation**: `TodayView.swift` displays `PersonalProgressBar` (standard SwiftUI `ProgressView`) and `PersonalSevenDayTimeline` (vertical list of days with icons).
   **Reasoning**: Requirement R2 specifies a Hero Performance Block with high-visibility daily split metrics, a 7-Day Athletic Splits Breakdown (D1 to D7 split bars showing verified steps, required daily split pace, and pacing delta +/- steps), Dynamic Pace Recalibration (exact daily step volume required over remaining days), and a Stakes & Sync Status HUD without floating bento boxes.

3. **Observation**: `ChallengesView.swift` and `PersonalChallengeDetailView.swift` use nested cards, soft pills, and modal review cards.
   **Reasoning**: Requirement R3 specifies an athletic proof-of-work ledger, tabular split breakdowns with verified Apple Health daily snapshots, clean settlement status badges (Settled / Completed / At Risk) using flat 1px hairline row separators, while strictly preserving `PersonalAccountabilityStore` state binding and `docs/COPY.md` vocabulary contracts.

4. **Observation**: `CreatePersonalChallengeFlow` in `PersonalChallengeFlow.swift` transitions through 6 steps wrapped in `DaybreakCard` with `LazyVGrid` stake buttons and `ProgressView` loading indicators.
   **Reasoning**: Requirement R4 specifies a high-efficiency athletic commitment builder: clean, tactile segmented selector for 7-day cadence (daily vs cumulative) and test commitment stake ($10–$50) without generic onboarding slides or fake loading animations, while retaining all existing test hooks (`personal.cadence.daily`, `personal.target`, `personal.commitment.1000`, `personal.payment.consent`, `personal.submit`).

5. **Observation**: `GameTimeUITests.swift` contains over 2,100 lines of UI assertions verifying specific accessibility identifiers, exact step navigation titles, environment disclosure labels, and running `assertNoForbiddenLanguage` regex.
   **Reasoning**: Any visual redesign MUST retain every accessibility identifier (`personal.environment-disclosure`, `personal.create`, `personal.target`, `personal.commitment.1000`–`5000`, `personal.health.verify`, `personal.payment.consent`, `personal.payment.setup`, `personal.start.now`, `personal.submit`, `personal.progress`, `personal.pace.day.0`–`6`, `personal.review.available`, `personal.cancel`, etc.) and exact string text, while avoiding forbidden terms.

---

## 3. Caveats

- **Scope & Write Access**: This report represents a read-only architectural investigation. Source files in `ios/GameTime/GameTime` and `ios/GameTime/GameTimeUITests` have not been altered.
- **Unsandboxed Execution**: Xcode build command (`xcodebuild`) timed out waiting for unsandboxed execution permission in subagent execution. Verification commands are fully documented for execution in local shell.
- **Backend & Store Contracts**: The underlying `PersonalAccountabilityStore`, `PersonalStepProgressStore`, HealthKit activity sync, and Stripe sandbox integration remain unchanged and fully compatible with the proposed UI redesign.

---

## 4. Conclusion

The GameTime UI components, views, creation flow, and test assertions have been fully audited.

### Key Architectural Action Items for Implementation:
1. **Athletic Design System Foundation (`CompetitiveTrustTheme.swift` & Visuals)**:
   - Primary dark theme: Background `#000000` / `#121212`, Signal Orange `#FC5200`, Athletic Green `#00D084`, Hairline Divider `#2C2C2E`.
   - Replace rounded bento `DaybreakCard` containers with flat 1px hairline row separators.
   - Replace Bricolage fonts with bold athletic typography hierarchy using tabular SF Pro Display / SF Mono for split metrics.
2. **Today Screen (`TodayView.swift` & `PersonalPaceComponents.swift`)**:
   - Hero Performance Block: Total steps vs 7-day target with high-visibility split metrics.
   - 7-Day Athletic Splits Breakdown (D1 to D7 split bars with actual verified steps, required daily split pace, and pacing delta +/- steps).
   - Dynamic Pace Recalibration: Daily step volume required over remaining days.
   - Stakes & Sync Status HUD: High-density financial stake status ($10–$50 locked) and HealthKit sync status without floating bento boxes.
3. **Challenges & Detail Ledger (`ChallengesView.swift` & `PersonalChallengeDetailView.swift`)**:
   - Proof-of-work tabular ledger with flat 1px hairline separators.
   - Settlement badges: Settled / Completed / At Risk.
   - Retain full integration with `PersonalAccountabilityStore` and exact Stripe sandbox copy rules from `docs/COPY.md`.
4. **Creation Flow (`PersonalChallengeFlow.swift`)**:
   - Tactile segmented commitment builder for target, 7-day cadence, and test stakes ($10–$50).
   - Retain all test identifiers (`personal.cadence.*`, `personal.target`, `personal.commitment.*`, `personal.payment.*`, `personal.submit`).
5. **UI Test Suite (`GameTimeUITests.swift`)**:
   - Retain all accessibility identifiers and exact contract copy strings.
   - Ensure zero forbidden words are present to keep `assertNoForbiddenLanguage` passing.

---

## 5. Verification Method

### 5.1 Xcode Build Command
Execute inside `ios/GameTime`:
```bash
cd /Users/user/Documents/GitHub/GameTime/ios/GameTime
xcodebuild -scheme GameTime -destination 'generic/platform=iOS' build
```

### 5.2 Unit & UI Test Commands
```bash
cd /Users/user/Documents/GitHub/GameTime/ios/GameTime
xcodebuild test -scheme GameTime -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

### 5.3 Files to Inspect
- `ios/GameTime/GameTime/TodayView.swift`
- `ios/GameTime/GameTime/PersonalPaceComponents.swift`
- `ios/GameTime/GameTime/ChallengesView.swift`
- `ios/GameTime/GameTime/PersonalChallengeDetailView.swift`
- `ios/GameTime/GameTime/PersonalChallengeFlow.swift`
- `ios/GameTime/GameTime/CompetitiveTrustTheme.swift`
- `ios/GameTime/GameTimeUITests/GameTimeUITests.swift`

### 5.4 Invalidation Conditions
- Any build failure or Swift 6 compiler warnings in `ios/GameTime`.
- Any assertion failure in `GameTimeUITests.swift` (specifically `assertNoForbiddenLanguage`, accessibility identifier presence, or environment disclosure copy).
