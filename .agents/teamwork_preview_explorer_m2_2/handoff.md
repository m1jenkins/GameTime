# Handoff Report: Refactoring Strategy for `PersonalPaceComponents.swift` (M2)

## 1. Observation

### 1.1 Source Code Architecture & Component Inventory
An investigation of `ios/GameTime/GameTime/PersonalPaceComponents.swift` and related files reveals the following structure:

1. **`PersonalPaceSummary` (Lines 11–462)**:
   - Domain calculation model for 7-day pacing metrics, daily split verdicts (`.metGoal`, `.underGoal`, `.today`, `.waived`, `.waiting`, `.problem`, `.future`), headlines, and tile values.
   - Key computed properties:
     - `days`: `[Day]` (D1 through D7, indexed 0 to 6 with `id`, `position`, `shortLabel`, `longLabel`, `steps`, `verdict`, `evidenceState`).
     - `dayGoal`: `Int` (daily target or cumulative daily rate).
     - `barCeiling`: `Double` (chart scaling ceiling).
     - `goalLineText`: `String` (e.g. `"10,000 a day"`).
     - `headline`: `String` (e.g. `"+860"`, `"−1,560"`, `"2,650"`, `"6 of 7"`, `"10,000"`, `"Goal met"`).
     - `headlineTone`: `Tone` (`.positive` vs `.action`).
     - `headlineCaption`: `String` (e.g. `"steps ahead of where you need to be"`).
     - `dayCountText`: `String` (e.g. `"Day 5 of 7"` or `"7 days"`).
     - `tiles`: `[Tile]` (3-item array of `Tile` structs with `id`, `label`, `value`, `caption`).
       - Cumulative cadence tiles: `finish` ("To finish"), `average` ("Average"), `left` ("Left").
       - Daily cadence tiles: `goal-days` ("Goal days") or `week-total` ("Week total"), `average` ("Average"), `left` ("Left").
     - `detailText(for day:)`: Returns `(value: String, caption: String)` for selected day breakdown.

2. **`PersonalPaceCard` (Lines 499–780)**:
   - View wrapper rendering the headline HUD, interactive vertical bar chart (`PaceGuideLine` dashed stroke), day label row, and selected day detail panel.
   - Currently wrapped in `DaybreakCard` (rounded bento card with `cornerRadius: 24`, soft drop shadow, `#FFFFF5` paper background).
   - Accessibility Identifiers:
     - `personal.pace.day.\(day.position)` attached to each day bar button (line 648).
     - `personal.pace.selected-day` attached to the detail panel (line 733).

3. **`PersonalPaceTiles` (Lines 792–815)**:
   - View wrapper rendering stat tiles.
   - Currently calls `ChallengeStatTile` (from `ChallengeVisualComponents.swift`, which uses `DaybreakCard` bento containers).
   - Accessibility Identifiers:
     - `personal.pace.\(tile.id)` attached to each tile (line 812), supporting `personal.pace.finish`, `personal.pace.average`, `personal.pace.left`, `personal.pace.week-total`, `personal.pace.goal-days`.

4. **`PersonalChallengeDetailsCard` (Lines 819–964)**:
   - Expandable card listing frozen challenge terms.
   - Wrapped in `DaybreakCard`.
   - Accessibility Identifier: `personal.details` (line 840).

5. **`CompetitiveTrustTheme.swift` Tokens Available**:
   - `darkBackground`: `#000000`
   - `graphiteSurface`: `#121212`
   - `signalOrange`: `#FC5200`
   - `athleticGreen`: `#00D084`
   - `hairlineDivider`: `#2C2C2E` (dark) / `#E5E5EA` (light)
   - `tabularFont(size:weight:)`: SF Pro Display / SF Mono monospaced digit typography.

6. **Test Suite Dependencies**:
   - `PersonalAccountabilityTests.swift` (lines 4074–4274): 8 unit tests in `PersonalPaceSummaryTests` that verify exact calculation strings (`headline`, `headlineCaption`, `goalLineText`, `dayCountText`, tile values, and `detailText`).
   - `GameTimeUITests.swift` (lines 427–437): Verifies `app.buttons["personal.pace.day.0"]` and `app.descendants(matching: .any)["personal.pace.week-total"]` with label check.

---

## 2. Logic Chain

1. **Observation**: `PersonalPaceSummaryTests` in `PersonalAccountabilityTests.swift` directly tests the output of `PersonalPaceSummary` properties (`headline`, `headlineTone`, `headlineCaption`, `tiles`, `dayGoal`, `goalLineText`, `detailText`).
   **Reasoning**: `PersonalPaceSummary` domain calculation logic MUST be preserved without altering its return strings or struct fields. The refactoring strategy focuses exclusively on replacing the visual SwiftUI presentation layer (`PersonalPaceCard`, `PersonalPaceTiles`, `PersonalChallengeDetailsCard`) and removing legacy Daybreak bento wrappers.

2. **Observation**: R2 and the Strava-inspired design mandate require replacing bento stat containers (`DaybreakCard`, `ChallengeStatTile`, rounded bubble cards, drop shadows) with high-contrast surfaces and flat 1px hairline row separators (`#2C2C2E` / `#E5E5EA`).
   **Reasoning**: In `PersonalPaceCard`, `PersonalPaceTiles`, and `PersonalChallengeDetailsCard`, replace `DaybreakCard` with flat containers (`CompetitiveTrustTheme.cardBackground` - `#121212` in dark mode) bounded by `CompetitiveTrustTheme.hairlineDivider` (`#2C2C2E` / `#E5E5EA`), with zero drop shadows (`.shadow(color: .clear)`).

3. **Observation**: Requirement R2 specifies 7-Day Athletic Splits Breakdown (D1 to D7 split bars with actual verified steps, required daily split pace, and pacing delta +/-) and Dynamic Pace Recalibration.
   **Reasoning**: `PersonalPaceCard` should render:
   - High-visibility hero metric with tabular monospaced digits (`CompetitiveTrustTheme.tabularFont`) using Strava Signal Orange (`#FC5200`) for action/behind status and Athletic Green (`#00D084`) for target met.
   - Visual day-by-day split bars (D1–D7) displaying actual verified steps, required daily split pace guide line (`summary.goalLineText`), and pacing delta (+/- steps ahead/behind) on selection.
   - Dynamic Pace Recalibration HUD showing exact daily step volume required over remaining days (`summary.tiles` finish tile or `detailText`).

4. **Observation**: `GameTimeUITests` inspects `app.buttons["personal.pace.day.0"]`, `personal.pace.selected-day`, `personal.details`, and `app.descendants(matching: .any)["personal.pace.<tile.id>"]`.
   **Reasoning**: Every accessibility identifier (`personal.pace.day.0` through `personal.pace.day.6`, `personal.pace.selected-day`, `personal.pace.finish`, `personal.pace.average`, `personal.pace.left`, `personal.pace.week-total`, `personal.pace.goal-days`, `personal.details`) MUST be strictly attached to the newly rendered flat hairline views. `PersonalPaceTiles` must combine child accessibility elements so that `weekTotal.label` contains both `"Week total"` and `"17,832"`.

---

## 3. Caveats

- **Read-Only Scope**: This report is an architectural investigation and strategy plan. No code changes have been committed to `ios/GameTime/GameTime/PersonalPaceComponents.swift`.
- **Accessibility Traversal in UI Tests**: UI tests use `app.descendants(matching: .any)["personal.pace.<tile.id>"]`. The replacement layout for `PersonalPaceTiles` must use `.accessibilityElement(children: .combine)` on each stat element to ensure `label` concatenates subview text cleanly.
- **Dark/Light Mode Hairline Contrast**: Color tokens must use `CompetitiveTrustTheme.hairlineDivider` so that `#2C2C2E` renders in dark mode and `#E5E5EA` renders in light mode automatically.

---

## 4. Conclusion

### Refactoring Strategy for `PersonalPaceComponents.swift` (Milestone M2)

#### 4.1 Data Model Layer (`PersonalPaceSummary`)
- Retain `PersonalPaceSummary` domain model, enums (`Verdict`, `Tone`), and inner structs (`Day`, `Tile`) exactly as written.
- Retain all calculation functions (`weekHeadline`, `dayHeadline`, `makeTiles`, `detailText`) so that unit tests in `PersonalPaceSummaryTests` continue to pass 100%.

#### 4.2 Split Pacing View (`PersonalPaceCard`)
- Replace `DaybreakCard` wrapper with a flat, dark container (`CompetitiveTrustTheme.card` background) bounded by 1px hairline dividers (`CompetitiveTrustTheme.hairlineDivider`).
- **Hero Performance & Pace Recalibration Header**:
  - Render `summary.headline` (+860, −1,560, 2,650, etc.) in `CompetitiveTrustTheme.tabularFont(size: 38, weight: .bold)`.
  - Headline color: `summary.headlineTone == .positive ? CompetitiveTrustTheme.athleticGreen : CompetitiveTrustTheme.signalOrange`.
  - Flat day-count status chip with subtle border (`CompetitiveTrustTheme.hairlineDivider`) replacing capsule background (`CompetitiveTrustTheme.paperSunk`).
- **7-Day Visual Split Bars (D1 to D7)**:
  - Render interactive bar buttons with accessibility IDs `personal.pace.day.0` through `personal.pace.day.6`.
  - Visual styling:
    - `.metGoal` / `.waived`: Athletic Green (`#00D084`)
    - `.today`: Signal Orange (`#FC5200`)
    - `.underGoal`: Signal Orange / Coral Tint Strong
    - `.future` / `.waiting`: Dark neutral rail (`#2C2C2E` / `CompetitiveTrustTheme.rail`)
    - `.problem`: Caution tone (`CompetitiveTrustTheme.sun`)
  - Dash guide line: 1px dashed line (`CompetitiveTrustTheme.hairlineDivider`) with `summary.goalLineText` in tabular font.
  - Selection ring: High-contrast 1.5px white stroke around selected day bar.
- **Selected Day Recalibration & Delta Breakdown**:
  - Container with `accessibilityIdentifier("personal.pace.selected-day")` separated by `Divider().overlay(CompetitiveTrustTheme.hairlineDivider)`.
  - Date label: Upper-cased monospaced day title (e.g. `MONDAY, AUG 3`).
  - Actual steps: `text.value` (e.g. `11,240 steps`) in bold tabular numbers.
  - Delta calculation: `text.caption` (e.g. `1,240 over a 10,000-step day` or `Still counting. 2,800 to go...`).

#### 4.3 Pacing Ledger Tiles (`PersonalPaceTiles`)
- Replace `ChallengeStatTile` bento cards with a flat hairline ledger structure (`HStack` or `VStack`).
- 3-column layout separated by flat 1px vertical/horizontal hairline dividers (`CompetitiveTrustTheme.hairlineDivider`).
- Each tile element:
  - Accessibility identifier: `.accessibilityIdentifier("personal.pace.\(tile.id)")`.
  - Element traits: `.accessibilityElement(children: .combine)`.
  - Top label: Uppercase caption (e.g. `TO FINISH`, `AVERAGE`, `LEFT`, `WEEK TOTAL`, `GOAL DAYS`) in `CompetitiveTrustTheme.secondaryText`.
  - Value: `CompetitiveTrustTheme.tabularFont(size: 20, weight: .bold)` in `CompetitiveTrustTheme.primaryText`.
  - Caption: `CompetitiveTrustTheme.tertiaryText` in 11pt tabular/ui font.

#### 4.4 Challenge Details Card (`PersonalChallengeDetailsCard`)
- Replace `DaybreakCard` with flat hairline card container (`CompetitiveTrustTheme.card`).
- Header button with `.accessibilityIdentifier("personal.details")`.
- Expandable terms list with flat 1px hairline row dividers (`Divider().overlay(CompetitiveTrustTheme.hairlineDivider)`).

---

## 5. Verification Method

### 5.1 Compilation Verification
Execute inside `ios/GameTime`:
```bash
cd /Users/user/Documents/GitHub/GameTime/ios/GameTime
xcodebuild -scheme GameTime -destination 'generic/platform=iOS' build
```

### 5.2 Unit Test Suite Verification
```bash
cd /Users/user/Documents/GitHub/GameTime/ios/GameTime
xcodebuild test -scheme GameTime -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:GameTimeTests/PersonalPaceSummaryTests
```

### 5.3 UI Test Suite Verification
```bash
cd /Users/user/Documents/GitHub/GameTime/ios/GameTime
xcodebuild test -scheme GameTime -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:GameTimeUITests/GameTimeUITests/testPersonalProgressReplacementFixturesStayConsistentAcrossSurfaces
```

### 5.4 Files to Inspect
- `ios/GameTime/GameTime/PersonalPaceComponents.swift`
- `ios/GameTime/GameTime/CompetitiveTrustTheme.swift`
- `ios/GameTime/GameTimeTests/PersonalAccountabilityTests.swift`
- `ios/GameTime/GameTimeUITests/GameTimeUITests.swift`

### 5.5 Invalidation Conditions
- Any failure in `PersonalPaceSummaryTests` unit tests.
- Missing accessibility identifiers (`personal.pace.day.0` to `6`, `personal.pace.finish`, `personal.pace.average`, `personal.pace.left`, `personal.pace.week-total`, `personal.pace.goal-days`, `personal.details`).
- Presence of rounded bento cards (`cornerRadius: 24`), soft drop shadows, pastel pills, or generic AI-slop elements.
- Any forbidden language regex match in `assertNoForbiddenLanguage`.
