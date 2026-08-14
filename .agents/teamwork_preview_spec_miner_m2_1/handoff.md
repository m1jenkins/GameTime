# Handoff Report: Milestone M2 Copy Compliance, Anti-Slop Audit & Test Assertion Plan

## 1. Observation

### Authoritative Specification Sources Examined
1. **`docs/COPY.md`**: Core copy guidelines, exact payment and health sync status contracts, domain glossary, and social V1 forbidden vocabulary rules.
2. **`ORIGINAL_REQUEST.md` (R2)**: Today screen transformation requirements, including Hero Performance Block, 7-Day Athletic Splits Breakdown (D1-D7), Dynamic Pace Recalibration, Stakes & Health Sync Status HUD, and zero AI-slop principles.
3. **`PROJECT.md`**: Milestone M2 scope (`TodayView.swift` & `PersonalPaceComponents.swift`), interface contracts (`CompetitiveTrustTheme`), and accessibility identifier requirements.
4. **Codebase Files**:
   - `ios/GameTime/GameTime/TodayView.swift`
   - `ios/GameTime/GameTime/PersonalPaceComponents.swift`
   - `ios/GameTime/GameTimeTests/PersonalAccountabilityTests.swift` (lines 4074–4280: `PersonalPaceSummaryTests`)
   - `ios/GameTime/GameTimeUITests/GameTimeUITests.swift` (lines 2069–2095: `assertNoForbiddenLanguage`)

### Forbidden Words Audit Results (M2 Scope)
Executed case-insensitive regex search against `TodayView.swift` and `PersonalPaceComponents.swift` for all 12 forbidden terms/phrases:
`friend(s)`, `invitation(s)`, `roster(s)`, `competitor(s)`, `rank(s)`, `standing(s)`, `winner(s)/winning`, `charity/charities`, `reaction(s)`, `tie-break`, `B//B`, `Better Bet`.

- **Result**: **0 forbidden words detected** in `TodayView.swift` and `PersonalPaceComponents.swift`.

### AI-Slop Anti-Pattern Audit Results (M2 Scope)
Audited `TodayView.swift` and `PersonalPaceComponents.swift` for AI-slop visual and copy patterns:
1. **Greeting Headers** ("Good morning", "Welcome back", "Hello"): **0 instances**. `TodayView.swift` uses factual date header (`Date.now.formatted(...)`).
2. **Motivational Fluff** ("You got this!", "Awesome work!"): **0 instances**. Copy is factual, concise, and user-centered.
3. **Pastel Pills & Soft Tint Fill**: **Found 2 legacy instances** in `PersonalPaceComponents.swift` (`Capsule()` with `paperSunk` background in `dayCountChip`, soft tints like `coralTintStrong`). Must be replaced in M2 with Strava-inspired high-contrast athletic badges (`Signal Orange #FC5200`, `Athletic Green #00D084`, `Neutral #2C2C2E`).
4. **Bento Card Containers & Daybreak Wrappers**: **Found 6 legacy instances** across `TodayView.swift` and `PersonalPaceComponents.swift` (`DaybreakCard`, `DaybreakCard(tone: .inverse)`, `DaybreakSectionLabel`, `.daybreakTabScrollClearance()`, `.daybreakScreenChrome()`). Must be replaced in M2 with high-contrast performance blocks and 1px hairline dividers (`#2C2C2E`).
5. **Generic Progress Rings**: `TodayView.swift` uses `PersonalProgressBar`. Must be replaced in M2 with the Athletic Hero Performance Block and 7-Day Athletic Splits breakdown.

---

## 2. Logic Chain

1. **Copy Compliance & Vocabulary Alignment**:
   - `docs/COPY.md` defines strict vocabulary mappings (e.g., "steps", "how it counts", "Every day / Week total", "Updated from Apple Health 3 min ago").
   - Automated testing in `GameTimeUITests.swift` (`assertNoForbiddenLanguage`) guarantees zero forbidden words across reachable views. Auditing `TodayView.swift` and `PersonalPaceComponents.swift` confirms clean compliance.

2. **Strava-Inspired Athletic Visual Architecture**:
   - AI-slop patterns (bento cards, paper backgrounds, pastel pills, generic rings) must be eliminated during the M2 component transformation.
   - Layout will transition to:
     - Pure Dark/Graphite background (`#000000`/`#121212`)
     - High-visibility tabular numbers (SF Pro Display / SF Mono)
     - 7-Day Athletic Split bars (D1–D7) with tabular +/- pacing deltas
     - Stakes & Apple Health Sync HUD without card-on-card nesting.

3. **Domain Engine & Unit Test Verification**:
   - `PersonalPaceSummary` calculates all split metrics, deltas, and stat tiles without recomputing in view bodies.
   - Existing unit tests (`PersonalPaceSummaryTests` in `PersonalAccountabilityTests.swift`) strictly validate exact copy strings, tenses (in-progress vs finished), and fail-closed problem day captions. All existing domain calculations must be preserved intact.

---

## Features Discovered

## Features Discovered
| # | Category | Feature | Description | Inputs | Outputs | Error Behavior | Discovered Via |
|---|----------|---------|-------------|--------|---------|----------------|----------------|
| 1 | Today HUD | Hero Performance Block | High-visibility step counter display (current total vs 7-day target) with tabular typography | Verified Health steps, target steps | Tabular step counts with high-contrast split ratio | Displays last retained steps with stale sync status banner if sync fails | `ORIGINAL_REQUEST.md` R2, `TodayView.swift` |
| 2 | Athletic Pacing | 7-Day Athletic Splits Breakdown | Visual D1–D7 day split bars with daily split pace guide line and tabular +/- pacing deltas | 7-day daily step progress records | D1–D7 split bar chart + selected day detail panel | Uncounted problem days stay out of pace comparison ("doesn't count against you") | `ORIGINAL_REQUEST.md` R2, `PersonalPaceComponents.swift` |
| 3 | Athletic Pacing | Dynamic Pace Recalibration | Calculates exact daily step volume required over remaining days to reach target | Remaining target steps, remaining days | "To finish" pace tile with required daily step count | Displays "Done / you reached your goal" when remaining steps = 0 | `ORIGINAL_REQUEST.md` R2, `PersonalPaceComponents.swift` |
| 4 | Today HUD | Stakes & Sync Status HUD | High-density indicator displaying active stake ($10–$50) and Apple Health sync status | Financial stake amount, last sync date | "Updated from Apple Health 3 min ago" & "$20 test stake" | "Apple Health is temporarily unavailable. Your last update is still here." | `docs/COPY.md`, `TodayView.swift` |
| 5 | Athletic Pacing | Day Split Detail Panel | Interactive panel displaying selected day's exact step count and plain-language explanation | Day bar selection tap | Selected day name, step count, and plain-language caption | Explains problem days ("We never received steps for this day, so it won't count either way.") | `docs/COPY.md`, `PersonalPaceComponents.swift` |

---

## Edge Cases

## Edge Cases
| # | Feature | Input | Observed Behavior |
|---|---------|-------|-------------------|
| 1 | Health Sync HUD | Apple Health data sync delayed / error | Renders status `"Last updated \(time) · Apple Health is temporarily unavailable"` with actionable retry action `"Try Again"`. |
| 2 | Pacing Delta | Equal target & actual steps (0 delta) | Renders headline `"10,000"` (or target) with caption `"steps a day keeps you on track"` (cumulative) or `"steps a day, every day"` (daily). |
| 3 | Pacing Delta | Negative pacing delta (behind target) | Renders headline with Unicode minus sign `"−1,560"` and caption `"steps behind where you need to be"` (in-progress) or `"steps short of what you needed"` (finished). |
| 4 | Pacing Delta | Positive pacing delta (ahead of target) | Renders headline `"+860"` with caption `"steps ahead of where you need to be"` (in-progress) or `"steps more than you needed"` (finished). |
| 5 | Athletic Splits | Uncounted / missing day step data | Excludes problem day from pacing comparison delta; shows caption `"We couldn’t use this day’s steps, so it won’t count either way."` |
| 6 | Athletic Splits | Outage / waived day | Excludes waived day from pace penalty; shows caption `"This was a problem on our end, so it doesn’t count against you."` |

---

## Exact Copy Strings Contract (Milestone M2)

### 1. HUD & Sync Status Copy
- **Ambient Environment Disclosure**:
  - Stage A: `"Test commitment — no money will be charged."`
  - Sandbox: `"Payment test mode — no real money moves."`
  - Demo: `"Demo mode — no money will be charged. Nothing here leaves your phone."`
- **Sync Status Timestamp**: `"Updated from Apple Health 3 min ago"` (or `X min ago` / `just now`).
- **Sync Status Outage / Stale**: `"Last updated \(time) · Apple Health is temporarily unavailable"`.
- **Sync Status Actionable Error**: `"We couldn’t update Apple Health right now. Your last update is still here."`.
- **Fail-Closed Protection Reassurance**: `"Missing or unclear step data never counts as a miss."`.

### 2. Tabular Pacing Deltas (+/- Steps)
- **Cumulative Pacing (Ahead)**:
  - Headline: `"+860"` (or `"+X"`)
  - Headline Caption (In-progress): `"steps ahead of where you need to be"`
  - Headline Caption (Finished): `"steps more than you needed"`
- **Cumulative Pacing (Behind)**:
  - Headline: `"−1,560"` (Unicode minus `U+2212`)
  - Headline Caption (In-progress): `"steps behind where you need to be"`
  - Headline Caption (Finished): `"steps short of what you needed"`
- **Cumulative Pacing (On Track / Scheduled)**:
  - Headline: `"10,000"` (Target count)
  - Headline Caption: `"steps a day keeps you on track"`
- **Daily Pacing (In-progress Today)**:
  - Headline: `"2,650"`
  - Headline Caption: `"steps to go today"`
- **Daily Pacing (Goal Met Today)**:
  - Headline: `"Goal met"`
  - Headline Caption: `"you’ve hit today’s goal"`
- **Daily Pacing (Finished Challenge)**:
  - Headline: `"6 of 7"`
  - Headline Caption: `"days you hit your goal"`

### 3. Dynamic Pace Recalibration & Stat Tiles
- **"To finish" Tile**:
  - In-progress: Value: `"9,570"`, Caption: `"a day, Sat and Sun"` (or day range)
  - Goal met: Value: `"Done"`, Caption: `"you reached your goal"`
  - Finished short: Value: `"14,000"`, Caption: `"steps short at the end"`
- **"Average" Tile**:
  - In-progress: Value: `"10,172"`, Caption: `"steps a day so far"`
  - Finished: Value: `"10,172"`, Caption: `"steps a day"`
- **"Left" Tile**:
  - In-progress: Value: `"2 days"`, Caption: `"through Sun"`
  - Finished: Value: `"0 days"`, Caption: `"your last day is done"`
- **"Week total" Tile** (Daily cadence):
  - In-progress: Value: `"17,832"`, Caption: `"steps so far"`
  - Finished: Value: `"73,100"`, Caption: `"steps across seven days"`
- **"Goal days" Tile** (Daily cadence):
  - In-progress: Value: `"1 of 2"`, Caption: `"days you hit so far"`

### 4. Day Breakdown Detail Captions
- Future day: Value: `"Not here yet"`, Caption: `"Day X of Y"`
- Current day (under goal): Value: `"7,200 steps"`, Caption: `"Still counting. 2,800 to go for a 10,000-step day."`
- Current day (passed goal): Value: `"11,240 steps"`, Caption: `"Still counting. You have already passed a 10,000-step day."`
- Met goal day: Value: `"11,240 steps"`, Caption: `"1,240 over a 10,000-step day"` (or `"Right on a 10,000-step day"`)
- Under goal day: Value: `"7,200 steps"`, Caption: `"2,800 under a 10,000-step day"`
- Waived day: Value: `"12,040 steps"`, Caption: `"This was a problem on our end, so it doesn’t count against you."`
- Waiting day: Value: `"0 steps"`, Caption: `"We’re still waiting for this day’s steps."`
- Missing day: Value: `"0 steps"`, Caption: `"We never received steps for this day, so it won’t count either way."`
- Quarantined day: Value: `"4,000 steps"`, Caption: `"We couldn’t use this day’s steps, so it won’t count either way."`

---

## Test Assertion Coverage Plan (Milestone M2)

### 1. Unit Test Assertions (`GameTimeTests/PersonalAccountabilityTests.swift`)
The following unit tests in `PersonalPaceSummaryTests` MUST pass without modification:
- `testWeekPaceComparesStepsWithTheDaysThatCount`: Asserts headline (`"+860"`), headlineTone (`.positive`), headlineCaption (`"steps ahead of where you need to be"`), tiles (`["To finish", "Average", "Left"]`).
- `testDaysWeCannotCountStayOutOfThePaceComparison`: Asserts negative headline (`"−1,560"`), headlineTone (`.action`), tiles.
- `testEachDayExplainsItselfInPlainWords`: Asserts exact day captions for complete, missing, quarantined, waived, inProgress, and future states.
- `testFinishedWeekSpeaksInThePastTense`: Asserts past tense captions (`"steps short of what you needed"`, `"steps short at the end"`).
- `testDailyChallengeLeadsWithTodayNotTheWeekTotal`: Asserts daily cadence strings (`"steps to go today"`, `"Goal days"`, `"Week total"`).
- `testFinishedDailyChallengeCountsTheDaysYouHit`: Asserts finished daily strings (`"6 of 7"`, `"days you hit your goal"`).
- `testScheduledChallengeStatesTheRateWithoutInventingProgress`: Asserts rate string (`"steps a day keeps you on track"`).
- `testBarCeilingKeepsTheGoalLineInsideTheChart`: Asserts bar height ceiling calculation accuracy.

### 2. UI Test Assertions & Accessibility Identifiers (`GameTimeUITests/GameTimeUITests.swift`)
The following accessibility identifiers MUST be preserved in the redesigned `TodayView.swift` and `PersonalPaceComponents.swift`:
- `personal.today.open`: Button to view challenge details from TodayView.
- `personal.create`: Button to create a new personal challenge.
- `personal.pace.day.0` through `personal.pace.day.6`: Segment split day buttons.
- `personal.pace.selected-day`: Selected day detail container.
- `personal.pace.to-finish`: "To finish" stat tile.
- `personal.pace.average`: "Average" stat tile.
- `personal.pace.left`: "Left" stat tile.
- `personal.pace.week-total`: "Week total" stat tile.
- `personal.pace.goal-days`: "Goal days" stat tile.
- `personal.environment-disclosure`: Ambient environment disclosure banner.

---

## 3. Caveats
- No code modifications were performed during this specification mining step (read-only mode).
- UI test assertions in `GameTimeUITests` check exact accessibility identifiers and strings. When replacing Daybreak components in M2, accessibility identifiers must be applied to the new Strava-style elements to avoid breaking UI test suites.

---

## 4. Conclusion
`TodayView.swift` and `PersonalPaceComponents.swift` currently comply with `docs/COPY.md` vocabulary rules (0 forbidden terms). However, they contain legacy AI-slop visual patterns (`DaybreakCard` bento containers, `DaybreakSectionLabel`, `PersonalProgressBar`, soft paper pill backgrounds). Milestone M2 should transform these views into Strava-inspired high-density performance blocks with 1px hairline dividers, tabular numbers, and D1–D7 split pacing while preserving all exact copy contracts and accessibility test identifiers.

---

## 5. Verification Method

To verify copy compliance and test assertion coverage:
1. **Audit Codebase for Forbidden Terms**:
   ```bash
   grep -Ei "\b(friend|friends|invitation|invitations|roster|rosters|competitor|competitors|rank|ranks|standing|standings|winner|winners|winning|charity|charities|reaction|reactions|tie[- ]?break|B//B|Better Bet)\b" ios/GameTime/GameTime/TodayView.swift ios/GameTime/GameTime/PersonalPaceComponents.swift
   ```
   *(Expected result: 0 matches)*

2. **Run Unit Test Suite for Pace Summary Logic**:
   ```bash
   xcodebuild -scheme GameTime -destination 'generic/platform=iOS' test -only-testing:GameTimeTests/PersonalPaceSummaryTests
   ```
   *(Expected result: All tests pass)*

3. **Run UI Test Suite for Copy & UI Accessibility Identifiers**:
   ```bash
   xcodebuild -scheme GameTime -destination 'generic/platform=iOS' test -only-testing:GameTimeUITests
   ```
   *(Expected result: `assertNoForbiddenLanguage` passes)*
