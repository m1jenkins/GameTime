# Project: GameTime Strava UI/UX Redesign

## Architecture
- **App**: iOS SwiftUI app (Swift 6 / iOS 18 targets).
- **Theme System**: `CompetitiveTrustTheme.swift` — Strava-inspired dark/graphite primary (`#000000` / `#121212`), Signal Orange (`#FC5200`), Athletic Green (`#00D084`), neutral dividers (`#2C2C2E`), SF Pro Display / SF Mono tabular numbers, high-contrast light mode support.
- **Views**:
  - `TodayView.swift`: Hero Performance Block, 7-Day Athletic Splits Breakdown, Dynamic Pace Recalibration, Stakes & Health Sync HUD.
  - `PersonalPaceComponents.swift`: Split pacing visualization, daily D1-D7 split bars, pacing delta, stat tiles.
  - `ChallengesView.swift` & `PersonalChallengeDetailView.swift`: Proof-of-work ledger, tabular split breakdown, flat 1px hairline row separators, settlement status badges.
  - `PersonalChallengeFlow.swift`: High-efficiency commitment builder, 7-day cadence selector, test stake selector ($10–$50).
- **Store & Domain**: `PersonalAccountabilityStore`, `PersonalStepProgressStore`, HealthKit activity sync, Stripe sandbox payment rules.
- **Verification**: `xcodebuild` build, `GameTimeTests` unit tests, `GameTimeUITests` UI tests (including `assertNoForbiddenLanguage` and `docs/COPY.md` rules).

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Adaptive Dark/Graphite Theme Foundation | Pure dark/graphite (`#000000`/`#121212`), Signal Orange (`#FC5200`), Athletic Green (`#00D084`), neutral dividers (`#2C2C2E`), tabular fonts, zero AI-slop | M1 | R1, survey |
| 2 | Plist & Contrast Test Alignment | Update `AppInfo.plist` & `DomainAndConfigurationTests.swift` for dark/adaptive theme support and color contrast tests | M1 | R1, survey |
| 3 | Hero Performance Block & Today Screen Transformation | Re-architect `TodayView.swift` with total steps vs target and high-visibility daily split metrics | M2 | R2, survey |
| 4 | 7-Day Athletic Splits & Dynamic Pace Recalibration | D1-D7 split bars with actual verified steps, required daily split pace, pacing delta (+/-), required daily volume | M2 | R2, survey |
| 5 | Stakes & Sync Status HUD | High-density financial stake status ($10–$50) and Apple Health sync status indicator without bento boxes | M2 | R2, survey |
| 6 | Challenge History & Detail Ledger | `ChallengesView.swift` and `PersonalChallengeDetailView.swift` proof-of-work ledger with tabular split breakdown and flat 1px hairline separators | M3 | R3, survey |
| 7 | Settlement Badges & Store Integration | Settled / Completed / At Risk status badges, `PersonalAccountabilityStore` integration, `docs/COPY.md` vocabulary rules | M3 | R3, survey |
| 8 | Challenge Creation Flow Overhaul | Redesign `PersonalChallengeFlow.swift` with high-efficiency commitment builder, 7-day cadence, test stakes ($10–$50) in tactile segmented layout | M4 | R4, survey |
| 9 | Test Suite & Forbidden Copy Hardening | Pass `xcodebuild build`, update unit tests (`GameTimeTests`) & UI test assertions (`GameTimeUITests`) with zero forbidden terms | M5 | AC, survey |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Athletic Design System & Theme Engine | `CompetitiveTrustTheme.swift`, `AppInfo.plist`, `DomainAndConfigurationTests.swift` | none | DONE |
| M2 | Today / Active Commitment Screen Transformation | `TodayView.swift`, `PersonalPaceComponents.swift` | M1 | DONE |
| M3 | Challenge History & Detail Ledger | `ChallengesView.swift`, `PersonalChallengeDetailView.swift`, `PersonalAccountabilityComponents.swift` | M1 | DONE |
| M4 | Challenge Creation Flow Overhaul | `PersonalChallengeFlow.swift` | M1 | PLANNED |
| M5 | Test Suite Verification & Hardening | `GameTimeTests`, `GameTimeUITests` | M1, M2, M3, M4 | PLANNED |


## Interface Contracts
### Theme Engine ↔ Views
- `CompetitiveTrustTheme.darkBackground`: `#000000` / `#121212`
- `CompetitiveTrustTheme.cardBackground`: `#121212` (dark) / `#FFFFFF` (light)
- `CompetitiveTrustTheme.signalOrange`: `#FC5200`
- `CompetitiveTrustTheme.athleticGreen`: `#00D084`
- `CompetitiveTrustTheme.hairlineDivider`: `#2C2C2E` (dark) / `#E5E5EA` (light)
- `CompetitiveTrustTheme.tabularFont(size:weight:)`: SF Pro Display / SF Mono monospaced digit typography.

### Store ↔ Views
- `PersonalAccountabilityStore` properties (`activeChallenge`, `pastChallenges`, `stepProgress`) bound cleanly to views without changing domain models.
- Accessibility identifiers (`personal.create`, `personal.details`, `personal.pace.day.0-6`, `personal.environment-disclosure`, etc.) MUST be strictly preserved.

## Code Layout
- `ios/GameTime/GameTime/CompetitiveTrustTheme.swift`
- `ios/GameTime/GameTime/TodayView.swift`
- `ios/GameTime/GameTime/PersonalPaceComponents.swift`
- `ios/GameTime/GameTime/ChallengesView.swift`
- `ios/GameTime/GameTime/PersonalChallengeDetailView.swift`
- `ios/GameTime/GameTime/PersonalChallengeFlow.swift`
- `ios/GameTime/GameTime/PersonalAccountabilityComponents.swift`
- `ios/GameTime/GameTimeTests/DomainAndConfigurationTests.swift`
- `ios/GameTime/GameTimeUITests/GameTimeUITests.swift`
