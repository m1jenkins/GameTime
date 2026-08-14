# Original User Request

## 2026-08-13T20:14:57Z

Redesign the GameTime iOS app (SwiftUI) UI/UX from the current warm-paper "Daybreak" aesthetic to a high-utility, Strava-dominant athletic performance design language with high-contrast surfaces, split pacing, and strict anti-slop principles.

Working directory: /Users/user/Documents/GitHub/GameTime
Integrity mode: development

## Requirements

### R1. Athletic Design System & Theme Engine
Replace the Daybreak theme (`CompetitiveTrustTheme.swift`) with a Strava-inspired athletic design system:
- Adaptive theme foundation prioritizing pure dark/graphite (`#000000` / `#121212`) with high-contrast light mode support.
- Signature athletic high-visibility accents (Strava Signal Orange `#FC5200`, athletic green `#00D084` for target achievement, sharp neutral dividers `#2C2C2E`).
- Bold athletic typography hierarchy with tabular numbers (SF Pro Display / SF Mono for split metrics and step counters).
- Strict adherence to the Anti-AI-Slop guide: No pastel gradients, no glowing cards, no over-rounded bubble pills, no nested floating cards, no generic motivational fluff.

### R2. Today / Active Commitment Screen Transformation
Re-architect `TodayView.swift` and associated pace components to deliver a Strava-style segment split and athletic HUD:
- **Hero Performance Block**: Current total steps vs 7-day target with high-visibility daily split metrics.
- **7-Day Athletic Splits Breakdown**: Visual day-by-day split bars (D1 through D7) displaying actual verified steps, required daily split pace, and pacing delta (+/- steps ahead/behind).
- **Dynamic Pace Recalibration**: Clear calculation showing exact daily step volume required over remaining days to protect the commitment.
- **Stakes & Sync Status HUD**: Clean, high-density financial stake status ($10–$50 locked) and Apple Health sync status indicator without floating bento boxes.

### R3. Challenge History & Detail Ledger
Update `ChallengesView.swift` and `PersonalChallengeDetailView.swift` to present an athletic proof-of-work ledger:
- Tabular split breakdown of past challenges with verified Apple Health daily snapshots.
- Clean settlement status badges (Settled / Completed / At Risk) using flat 1px hairline row separators rather than cards on cards.
- Seamless integration with the existing `PersonalAccountabilityStore` and `docs/COPY.md` vocabulary rules.

### R4. Challenge Creation Flow Overhaul
Redesign `PersonalChallengeFlow.swift` / `CreatePersonalChallengeFlow`:
- High-efficiency athletic commitment builder: Target selection, 7-day cadence (daily vs cumulative), and test commitment stake selection ($10–$50) presented in a clean, tactile segmented layout without generic onboarding slides or fake loading animations.

## Acceptance Criteria

### Visual & Architectural Integrity
- [ ] Zero AI-slop anti-patterns (no gradient text, no floating bento cards, no generic progress rings, no greeting headers, no pastel pills).
- [ ] Strict compliance with `docs/COPY.md` vocabulary rules (no forbidden terms on screen).
- [ ] Both Dark Mode (primary) and Light Mode render with high-contrast legibility and accessible Dynamic Type support.
- [ ] Fully compiles with Swift 6 and iOS 18 targets without regression in existing business logic or Apple Health snapshot handling.

### Verification & Testing
- [ ] Xcode project builds cleanly (`xcodebuild -scheme GameTime -destination 'generic/platform=iOS' build`).
- [ ] Existing `GameTimeTests` unit test suite passes.
- [ ] UI test assertions (`GameTimeUITests`) updated to reflect the new Strava-dominant components and strings.
