## 2026-08-13T20:37:34Z

You are teamwork_preview_worker_m2_1 (M2 Implementation Worker).
Working Directory: /Users/user/Documents/GitHub/GameTime/.agents/teamwork_preview_worker_m2_1

Task: Refactor `ios/GameTime/GameTime/TodayView.swift` and `ios/GameTime/GameTime/PersonalPaceComponents.swift` to transform the UI/UX from Daybreak warm-paper aesthetic to Strava-dominant athletic performance design language.

Authoritative Context & Exploration Reports:
- Original Request: /Users/user/Documents/GitHub/GameTime/.agents/ORIGINAL_REQUEST.md
- Project Scope: /Users/user/Documents/GitHub/GameTime/.agents/teamwork_preview_orchestrator_1/PROJECT.md
- Copy Guidelines: /Users/user/Documents/GitHub/GameTime/docs/COPY.md
- TodayView Exploration Strategy: /Users/user/Documents/GitHub/GameTime/.agents/teamwork_preview_explorer_m2_1/handoff.md
- PersonalPaceComponents Exploration Strategy: /Users/user/Documents/GitHub/GameTime/.agents/teamwork_preview_explorer_m2_2/handoff.md
- Spec & Copy Compliance Report: /Users/user/Documents/GitHub/GameTime/.agents/teamwork_preview_spec_miner_m2_1/handoff.md

Exclusive Write Ownership:
- `ios/GameTime/GameTime/TodayView.swift`
- `ios/GameTime/GameTime/PersonalPaceComponents.swift`

Requirements for M2:
1. Re-architect `TodayView.swift`:
   - Delete legacy greeting date header ("Thursday, August 13").
   - Remove `DaybreakCard` bento boxes, drop shadows, and soft background fills. Replace with flat dark graphite HUD containers (`#121212`) separated by 1px hairline dividers (`CompetitiveTrustTheme.hairlineDivider` / `#2C2C2E`).
   - Implement Hero Performance Block: Total steps vs 7-day target (`CompetitiveTrustTheme.tabularFont(size: 40, weight: .bold)` with monospaced digits), pacing delta badge (+/- steps ahead/behind in Athletic Green `#00D084` or Signal Orange `#FC5200`), and `PersonalProgressBar` (`personal.progress`, `personal.progress.steps`, `personal.progress.remaining`).
   - Implement Stakes & Health Sync Status HUD: High-density financial stake status ($10–$50 locked/at risk), HealthKit sync status indicator (`personal.health.status`), ambient environment disclosure banner (`personal.environment-disclosure`), and "See details" button (`personal.today.open`).
   - Implement 7-Day Athletic Splits Breakdown (D1 to D7 split bars with actual verified steps, required daily split pace, pacing delta +/- steps) and Dynamic Pace Recalibration.
   - Refactor empty state button ("Start a challenge", `personal.create`) and recovery card (`personal.cancellation.pending`, `personal.cancellation.retry`, `personal.cancellation.refresh`, `personal.cancellation.support`).

2. Refactor `PersonalPaceComponents.swift`:
   - Preserve `PersonalPaceSummary` domain model and calculation functions intact so that all unit tests in `PersonalPaceSummaryTests` pass.
   - Replace `DaybreakCard` in `PersonalPaceCard`, `PersonalPaceTiles`, and `PersonalChallengeDetailsCard` with flat dark containers (`CompetitiveTrustTheme.card`) bounded by hairline dividers (`CompetitiveTrustTheme.hairlineDivider`).
   - Render D1-D7 split bars with `CompetitiveTrustTheme.tabularFont`, high-contrast bar fills (`athleticGreen`, `signalOrange`, `#2C2C2E`), guide lines, and selected day overlay panel (`personal.pace.selected-day`).
   - Refactor `PersonalPaceTiles` to 3-column ledger layout with hairline dividers, combining accessibility elements for tile IDs (`personal.pace.finish`, `personal.pace.average`, `personal.pace.left`, `personal.pace.week-total`, `personal.pace.goal-days`).
   - Refactor `PersonalChallengeDetailsCard` header button (`personal.details`) with flat 1px hairline row dividers.

3. Strict Constraints & Integrity:
   - ZERO AI-slop anti-patterns (no gradient text, no floating bento cards, no generic progress rings, no greeting headers, no pastel pills).
   - Strict compliance with `docs/COPY.md` vocabulary rules (0 forbidden terms).
   - Strictly preserve all accessibility identifiers (`personal.progress`, `personal.progress.steps`, `personal.progress.remaining`, `personal.health.status`, `personal.today.open`, `personal.create`, `personal.environment-disclosure`, `personal.pace.day.0` to `6`, `personal.pace.selected-day`, `personal.pace.finish`, `personal.pace.average`, `personal.pace.left`, `personal.pace.week-total`, `personal.pace.goal-days`, `personal.details`).
   - Strictly preserve `@Environment(PersonalAccountabilityStore.self)` and `@Environment(AppRouter.self)` store bindings.
