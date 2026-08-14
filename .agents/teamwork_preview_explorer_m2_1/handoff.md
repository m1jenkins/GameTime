# Handoff Report: Milestone M2 — TodayView.swift & Hero Performance Block & HUD Refactoring Strategy

## 1. Observation

### 1.1 Source Code Inventory & Line Map
- **`ios/GameTime/GameTime/TodayView.swift`**:
  - Lines 3–7: Environment bindings (`@Environment(PersonalAccountabilityStore.self) private var store`, `@Environment(AppRouter.self) private var router`, `@Environment(\.dynamicTypeSize) private var dynamicTypeSize`).
  - Lines 9–27: Main `ScrollView` with `LazyVStack(spacing: 12)`, `.daybreakTabScrollClearance()`, `.daybreakScreenChrome()`, `.navigationTitle("Today")`, `.refreshable`.
  - Lines 37–60: Greeting date `header` displaying `Date.now.formatted(.dateTime.weekday(.wide))` and `Date.now.formatted(.dateTime.month(.wide).day())` using Bricolage display font and HankenGrotesk body font inside warm-paper section styling.
  - Lines 63–75: `loadState` view rendering `DaybreakCard` around `InlineLoadStateView`.
  - Lines 13–15: `PendingPersonalCancellationRecoveryCard` integration.
  - Lines 17–18 & 77–173: `currentChallenge` helper rendering `DaybreakSectionLabel(text: "Your week")`, `DaybreakCard(tone: .inverse)` hero card wrapping `PersonalStatusPill`, `commitmentText` ($10–$50 stake), `targetText` (step target), `PersonalProgressBar`, `PersonalHealthProgressStatus`, and Button("See details") (`personal.today.open`).
  - Lines 161–168: Split breakdown rendering `DaybreakSectionLabel(text: "Day by day")` and `DaybreakCard` wrapping `PersonalSevenDayTimeline`.
  - Lines 175–192: `createCard` view rendering `DaybreakCard` wrapping `EmptyTrustState` and Button("Start a challenge") (`personal.create`).
  - Line 194–200: `refreshWithAnnouncement` invoking `store.refresh()` and accessibility announcements.

- **`ios/GameTime/GameTime/PersonalAccountabilityComponents.swift`**:
  - Lines 170–224: `PersonalProgressBar` displaying progress track, `personal.progress`, `personal.progress.steps`, `personal.progress.remaining`.
  - Lines 228–279: `PersonalProgressPresentation` calculating step fraction, remaining steps, and daily/cumulative progress copy.
  - Lines 418–443: `PersonalHealthProgressStatus` displaying `personal.health.status`.
  - Lines 470–615: `PendingPersonalCancellationRecoveryCard` displaying `personal.cancellation.pending`, `personal.cancellation.retry`, `personal.cancellation.refresh`, `personal.cancellation.support`.
  - Lines 617–702: `PersonalSevenDayTimeline` displaying day-by-day vertical timeline list.

- **`ios/GameTime/GameTime/PersonalPaceComponents.swift`**:
  - Lines 11–462: `PersonalPaceSummary` calculating cumulative pacing delta (`+1,200` / `−3,400` ahead/behind pace), day goal status, and tile metrics.
  - Lines 499–780: `PersonalPaceCard` displaying chart height 132, bar scale 128, day buttons (`personal.pace.day.0` to `6`), and selected day panel (`personal.pace.selected-day`).
  - Lines 792–815: `PersonalPaceTiles` rendering stat tiles (`personal.pace.finish`, `personal.pace.average`, `personal.pace.left`, `personal.pace.week-total`, `personal.pace.goal-days`).

- **`ios/GameTime/GameTime/CompetitiveTrustTheme.swift`**:
  - Lines 6–16: Primary athletic dark theme tokens (`darkBackground = #000000`, `graphiteSurface = #121212`, `signalOrange = #FC5200`, `athleticGreen = #00D084`, `hairlineDivider = #2C2C2E`).
  - Lines 160–189: Monospaced digit typography helpers (`tabularFont(size:weight:)`, `monoFont(size:weight:)`).
  - Lines 624–662: `EnvironmentDisclosureBanner` displaying `personal.environment-disclosure`.

- **`ios/GameTime/GameTimeUITests/GameTimeUITests.swift`**:
  - Asserts accessibility identifiers: `tab.today`, `personal.progress`, `personal.progress.steps`, `personal.progress.remaining`, `personal.health.status`, `personal.today.open`, `personal.create`, `personal.environment-disclosure`, `personal.pace.day.0`–`6`, `personal.pace.selected-day`, `personal.cancellation.pending`.
  - Enforces strict zero-forbidden-language policy via `assertNoForbiddenLanguage`.

---

## 2. Logic Chain

1. **Observation**: `TodayView.swift` currently structures its active commitment UI inside nested `DaybreakCard` bento box containers with corner radius 24 and drop shadows, preceded by a soft greeting date header ("Thursday, August 13").
   **Reasoning**: Requirement R2 and anti-slop guidelines mandate replacing floating bento boxes, greeting headers, soft drop shadows, and pastel pills with a high-utility, Strava-dominant dark athletic HUD on pure `#000000`/`#121212` background structured with sharp `#2C2C2E` 1px hairline dividers.

2. **Observation**: The current hero section displays step numbers using standard display fonts without tabular digit formatting, making rapid pacing alignment hard to read.
   **Reasoning**: Requirement R1 & R2 mandate bold athletic typography using `SF Pro Display` / `SF Mono` with `.monospacedDigit()` for all split metrics and step totals (e.g. `42,850` total steps vs `70,000` 7-day target), with Strava Signal Orange (`#FC5200`) and Athletic Green (`#00D084`) accents.

3. **Observation**: Financial commitment information ($10–$50 stake) and Apple Health sync status are currently split between card headers and bottom labels inside `DaybreakCard(tone: .inverse)`.
   **Reasoning**: Requirement R2 requires a high-density **Stakes & Sync Status HUD** combining financial stake status ($10–$50 locked/at risk) and HealthKit sync status (`personal.health.status`) in a unified, non-floating high-density HUD block.

4. **Observation**: Daily breakdown in `TodayView` uses `PersonalSevenDayTimeline`, a simple vertical list of icons and text, missing explicit pacing delta (+/- steps ahead/behind pace) and dynamic daily pace recalibration.
   **Reasoning**: Requirement R2 mandates a **7-Day Athletic Splits Breakdown** displaying visual day-by-day split bars (D1–D7) with actual verified steps, required daily split pace, pacing delta (+/- steps), and **Dynamic Pace Recalibration** (exact step volume required over remaining days to protect the commitment).

5. **Observation**: `GameTimeUITests` checks specific accessibility identifiers (`personal.progress`, `personal.today.open`, `personal.create`, `personal.environment-disclosure`, `personal.health.status`) and store bindings (`PersonalAccountabilityStore`).
   **Reasoning**: Any visual redesign of `TodayView.swift` MUST strictly preserve 100% of accessibility identifiers and `PersonalAccountabilityStore` bindings to prevent UI test regressions.

---

## 3. Caveats

- **Scope Boundary**: This report details the architectural refactoring strategy for Milestone M2 (`TodayView.swift` and pace HUD components). Source code changes are not applied directly in this read-only phase.
- **Component Dependencies**: `TodayView.swift` relies on helper components in `PersonalPaceComponents.swift` and `PersonalAccountabilityComponents.swift`. Updates to `TodayView.swift` should leverage shared athletic HUD primitives from `PersonalPaceComponents.swift`.
- **Light/Dark Mode Support**: While primary focus is dark/graphite (`#000000`/`#121212`), high-contrast light mode styling must adapt cleanly using `CompetitiveTrustTheme` adaptive tokens.

---

## 4. Conclusion & Actionable Refactoring Strategy

### 4.1 Target Layout & Component Architecture for `TodayView.swift`

```
┌─────────────────────────────────────────────────────────┐
│ NAVIGATION BAR: "Today" (Inline Title, Hairline Border) │
├─────────────────────────────────────────────────────────┤
│ [EnvironmentDisclosureBanner]                           │
│ "Test commitment — no money will be charged."           │
│ (ID: personal.environment-disclosure)                   │
├─────────────────────────────────────────────────────────┤
│ HERO PERFORMANCE BLOCK                                  │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ TOTAL STEPS                7-DAY TARGET             │ │
│ │ 42,850             vs      70,000                   │ │
│ │ (SF Mono Monospaced)       (SF Mono Monospaced)     │ │
│ │                                                     │ │
│ │ TODAY: 6,450 steps   |   PACE DELTA: +1,200 steps   │ │
│ │                          (Athletic Green #00D084)   │ │
│ │                                                     │ │
│ │ [========PersonalProgressBar======================] │ │
│ │ (ID: personal.progress)                             │ │
│ └─────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────┤
│ STAKES & SYNC STATUS HUD                                │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ STAKE: $20.00 LOCKED  │ HEALTHKIT: Synced 2m ago  │ │
│ │ (ID: personal.health.status)                        │ │
│ │                                                     │ │
│ │ [SEE DETAILS BUTTON] (ID: personal.today.open)      │ │
│ └─────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────┤
│ 7-DAY ATHLETIC SPLITS BREAKDOWN & DYNAMIC RECALIBRATION │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ REQUIRED PACE: 6,788 steps/day over remaining 4 days│ │
│ │                                                     │ │
│ │ D1 Mon [████████████░░░] 8,420 steps  (+840 pace)   │ │
│ │ D2 Tue [███████████████] 10,250 steps (+2,250 pace) │ │
│ │ D3 Wed [█████████░░░░░░] 6,450 steps  (-1,550 pace) │ │
│ │ D4 Thu [░░░░░░░░░░░░░░░] Today in progress           │ │
│ │ D5-D7  Upcoming                                     │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### 4.2 Step-by-Step Refactoring Execution Plan

#### Step 1: `TodayView.swift` Cleaning & Layout Overhaul
1. **Remove Greeting Header**: Delete `private var header` (lines 37–60).
2. **Remove Bento Boxes**: Replace all `DaybreakCard` wrappers with flat graphite HUD sections (`#121212`) separated by 1px hairline dividers (`CompetitiveTrustTheme.hairlineDivider` `#2C2C2E`).
3. **Preserve Scroll Clearance & Screen Chrome**: Retain `.daybreakTabScrollClearance()` and `.daybreakScreenChrome()`.

#### Step 2: Hero Performance Block Implementation
1. Construct `HeroPerformanceBlock`:
   - Primary metric: Total steps (`summary.displayedProgress.totalSteps`) vs Target steps (`summary.terms.targetSteps`).
   - Font: `CompetitiveTrustTheme.tabularFont(size: 40, weight: .bold)` with SF Mono digits.
   - Pacing delta pill/badge: High-visibility delta string (`+1,200 steps ahead` or `−3,400 steps behind`) styled in `athleticGreen` or `signalOrange`.
   - Embed `PersonalProgressBar` with `accessibilityIdentifier("personal.progress")`, `personal.progress.steps`, and `personal.progress.remaining`.

#### Step 3: Stakes & Sync Status HUD Implementation
1. Construct `StakesAndSyncHUD`:
   - Financial stake indicator: Display `summary.terms.commitmentText` ($10–$50 locked) in high-contrast athletic badge formatting.
   - Sync status indicator: Embed `PersonalHealthProgressStatus` with `accessibilityIdentifier("personal.health.status")`.
   - Environment disclosure banner: Embed `EnvironmentDisclosureBanner` with `accessibilityIdentifier("personal.environment-disclosure")`.
   - Action button: Button("See details") with `accessibilityIdentifier("personal.today.open")` styled with `TrustPrimaryButtonStyle()`.

#### Step 4: 7-Day Athletic Splits Breakdown & Dynamic Pace Recalibration
1. Integrate `PersonalPaceSummary` and `PersonalPaceCard` logic directly into the active commitment view:
   - D1 through D7 split bars showing verified steps, target pace line, and +/- delta.
   - Clickable day split bars with accessibility identifiers `personal.pace.day.0` to `6` and selected day detail overlay `personal.pace.selected-day`.
   - Dynamic Pace Recalibration banner displaying required daily step volume over remaining days (`summary.tiles.first(where: { $0.id == "finish" })`).

#### Step 5: Empty & Recovery State Alignment
1. **Empty State (`createCard`)**: Refactor to flat dark surface callout without `DaybreakCard`, maintaining button text "Start a challenge" and `accessibilityIdentifier("personal.create")`.
2. **Cancellation Recovery (`PendingPersonalCancellationRecoveryCard`)**: Update to dark surface styling with hairline border, preserving `personal.cancellation.pending`, `personal.cancellation.retry`, `personal.cancellation.refresh`, `personal.cancellation.support`.

---

## 5. Accessibility Identifier & Binding Preservation Matrix

| Identifier / Binding | Location in Code | Status | Purpose / Test Coverage |
|---|---|---|---|
| `tab.today` | `AppShellView.swift` | Strictly Preserved | Tab navigation item for Today screen |
| `personal.progress` | `PersonalProgressBar` | Strictly Preserved | UI test check for progress bar indicator |
| `personal.progress.steps` | `PersonalProgressBar` | Strictly Preserved | UI test check for total step count text |
| `personal.progress.remaining` | `PersonalProgressBar` | Strictly Preserved | UI test check for remaining step count text |
| `personal.health.status` | `PersonalHealthProgressStatus` | Strictly Preserved | HealthKit sync status label |
| `personal.today.open` | `TodayView.swift` | Strictly Preserved | "See details" button to push detail view |
| `personal.create` | `TodayView.swift` | Strictly Preserved | "Start a challenge" button in empty state |
| `personal.environment-disclosure` | `EnvironmentDisclosureBanner` | Strictly Preserved | Environment test mode disclosure banner |
| `personal.pace.day.0`–`6` | `PersonalPaceCard` | Strictly Preserved | Day split bar buttons D1–D7 |
| `personal.pace.selected-day` | `PersonalPaceCard` | Strictly Preserved | Selected day detail overlay card |
| `PersonalAccountabilityStore` | `@Environment` binding | Strictly Preserved | Store bindings (`openChallenge`, `loadState`, `canCreate`) |

---

## 6. Verification Method

### 6.1 Xcode Build Verification
Execute in local terminal under `ios/GameTime`:
```bash
cd /Users/user/Documents/GitHub/GameTime/ios/GameTime
xcodebuild -scheme GameTime -destination 'generic/platform=iOS' build
```

### 6.2 UI & Unit Test Verification
```bash
cd /Users/user/Documents/GitHub/GameTime/ios/GameTime
xcodebuild test -scheme GameTime -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

### 6.3 Target Inspection Files
- `ios/GameTime/GameTime/TodayView.swift`
- `ios/GameTime/GameTime/PersonalPaceComponents.swift`
- `ios/GameTime/GameTime/PersonalAccountabilityComponents.swift`
- `ios/GameTime/GameTimeUITests/GameTimeUITests.swift`

### 6.4 Invalidation Conditions
- Any occurrence of `DaybreakCard`, greeting date headers, or pastel pill backgrounds in `TodayView.swift`.
- Any missing accessibility identifier (`personal.progress`, `personal.today.open`, `personal.create`, `personal.environment-disclosure`, `personal.health.status`).
- Any failure in `GameTimeUITests` (including `assertNoForbiddenLanguage` or navigation assertions).
