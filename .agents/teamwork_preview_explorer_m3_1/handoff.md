# Handoff Report: Milestone M3 — Challenge History & Detail Ledger Overhaul

## 1. Observation

### Codebase Structure & File Paths Inspected
1. `ios/GameTime/GameTime/ChallengesView.swift` (161 lines):
   - Renders the main challenge history tab.
   - Contains sections for load state (`loadState`), pending cancellation recovery (`PendingPersonalCancellationRecoveryCard`), pending setup recovery (`pendingRecovery`), current active challenge (`store.openChallenge`), historical finished challenges (`store.history`), empty state (`store.loadState == .empty`), and creation CTA button (`Button("Start a challenge")` at line 51).
   - Currently relies on `DaybreakCard` (lines 38, 89, 104, 139) and `DaybreakSectionLabel` (lines 18, 27, 103) for layout, producing rounded paper cards with soft shadows.
2. `ios/GameTime/GameTime/PersonalChallengeDetailView.swift` (534 lines):
   - Renders the detailed single-challenge view.
   - Includes hero section (`hero` at line 98), cancellation section (`cancellation` at line 488), pace section (`pace` at line 275), result section (`result` at line 318), review section (`review` at line 352), and challenge details terms card (`PersonalChallengeDetailsCard` at line 49).
   - Currently uses `DaybreakCard` (lines 51, 112, 280, 326, 359) with rounded 24pt corner cards, soft shadows, and warm-paper tints.
3. `ios/GameTime/GameTime/PersonalAccountabilityComponents.swift` (772 lines):
   - Contains core helper components:
     - `PersonalChallengeCard` (lines 4-105): Renders individual challenge summary items in history/active lists using `DaybreakCard`.
     - `PersonalStatusPill` (lines 127-168): Maps outcome/status to `TrustStatusPill` text and style.
     - `PersonalProgressBar` (lines 170-224): Renders step progress bar and text facts (`personal.progress`, `personal.progress.steps`, `personal.progress.remaining`).
     - `PersonalHealthProgressStatus` (lines 418-443): Renders Apple Health status label (`personal.health.status`).
     - `PendingPersonalCancellationRecoveryCard` (lines 470-615): Renders pending cancellation retry/recovery UI inside `DaybreakCard(tone: .pledge)`.
     - `PersonalSevenDayTimeline` (lines 617-702): Renders 7-day split timeline list.
     - `LegacyPersonalReadinessNotice` (lines 704-741): Renders readiness notice for legacy holds.
     - `PersonalReasonText` (lines 746-771): Maps server error codes to user-friendly sentences.
4. `ios/GameTime/GameTime/PersonalPaceComponents.swift` (1027 lines):
   - Contains `PersonalPaceSummary`, `PersonalPaceCard` (7-day bar chart), `PersonalPaceTiles` (Average, Goal days, Left, To finish, Week total stat tiles), and `PersonalChallengeDetailsCard` (expandable terms table).
5. `ios/GameTime/GameTime/CompetitiveTrustTheme.swift` (716 lines):
   - Design tokens available: `darkBackground` (`#000000`), `graphiteSurface` (`#121212`), `signalOrange` (`#FC5200`), `athleticGreen` (`#00D084`), `hairlineDivider` (`#2C2C2E` / `#E5E5EA`), `tabularFont(size:weight:)` (SF Pro Display / SF Mono monospaced digit typography), `monoFont(size:weight:)`.

### Exact Accessibility Identifiers Identified
The following accessibility identifiers must be strictly preserved during refactoring:
- `personal.create`: "Start a challenge" button on `ChallengesView.swift:56`.
- `personal.pending.resume`: "Continue setup" button on `ChallengesView.swift:131`.
- `personal.challenge.\(challenge.id.uuidString.lowercased())`: Challenge history/active row button on `PersonalAccountabilityComponents.swift:102-103`.
- `personal.progress`: Progress bar on `PersonalAccountabilityComponents.swift:188`.
- `personal.progress.steps`: Steps text on `PersonalAccountabilityComponents.swift:217`.
- `personal.progress.remaining`: Remaining steps text on `PersonalAccountabilityComponents.swift:222`.
- `personal.health.status`: Health status label on `PersonalAccountabilityComponents.swift:440`.
- `personal.challenge.sync-now`: Sync button on `PersonalChallengeDetailView.swift:252`.
- `personal.challenge.health-help`: Health help link on `PersonalChallengeDetailView.swift:213-214`.
- `personal.challenge.account-support`: Support button on `PersonalChallengeDetailView.swift:222`.
- `personal.result`: Result block on `PersonalChallengeDetailView.swift:348`.
- `personal.review.available`: Review window notice on `PersonalChallengeDetailView.swift:397-398`.
- `personal.review.reason.\(reason.rawValue)`: Review reason radio buttons on `PersonalChallengeDetailView.swift:425-426`.
- `personal.review.request`: Request review CTA button on `PersonalChallengeDetailView.swift:462-463`.
- `personal.review.submitted`: Review submitted block on `PersonalChallengeDetailView.swift:380`.
- `personal.review.expired`: Review expired notice on `PersonalChallengeDetailView.swift:387`.
- `personal.cancel`: Cancel challenge button on `PersonalChallengeDetailView.swift:520`.
- `personal.cancellation.pending`: Pending cancellation card label on `PersonalAccountabilityComponents.swift:503`.
- `personal.cancellation.retry`: Retry cancellation button on `PersonalAccountabilityComponents.swift:518`.
- `personal.cancellation.refresh`: Refresh button on `PersonalAccountabilityComponents.swift:529`.
- `personal.cancellation.support`: Contact support button on `PersonalAccountabilityComponents.swift:535-536`.
- `personal.legacy-hold`: Legacy readiness hold card on `PersonalAccountabilityComponents.swift:739`.
- `personal.details`: Expandable challenge terms header on `PersonalPaceComponents.swift:903`.
- `personal.pace.day.\(0..6)`: Daily split bar buttons in `PersonalPaceCard` on `PersonalPaceComponents.swift:657`.
- `personal.pace.selected-day`: Selected day detail panel on `PersonalPaceComponents.swift:745`.
- `personal.pace.\(tile.id)`: Stat tile cells (`personal.pace.week-total`, `personal.pace.goal-days`, `personal.pace.left`, `personal.pace.finish`, `personal.pace.average`) on `PersonalPaceComponents.swift:877`.
- `personal.environment-disclosure`: Ambient environment banner on `CompetitiveTrustTheme.swift:660`.

### Exact Store Bindings & Domain Models
- `PersonalAccountabilityStore`:
  - `openChallenge`: Active or scheduled challenge summary (`PersonalChallengeSummary?`).
  - `history`: List of finished challenges (`[PersonalChallengeSummary]`).
  - `loadState`: Screen load state (`.idle`, `.loading`, `.loaded`, `.empty`, `.failed`).
  - `pendingCreation`: Setup draft state (`PersonalPendingCreation?`).
  - `hasVerifiedCreationState`: Boolean check if creation state is verified.
  - `canCreate`: Boolean check if user can start a challenge.
  - `pendingCancellation`: Pending cancellation state (`PersonalPendingCancellation?`).
  - `hasPendingCancellationRecoveryIssue`: Recovery issue state boolean.
  - `detail(for: challengeID)`: Method returning `PersonalChallengeDetail?`.
  - `loadDetail(challengeID:)`: Async method to load single challenge details.
  - `cancel(challengeID:)`: Async cancellation method.
  - `requestReview(challengeID:reason:)`: Async review request method.
  - `reviewRequest(for: challengeID)`: Returns `PersonalReviewRequest?`.
  - `displayedProgress(for:now:)`: Returns `PersonalDisplayedProgress?`.
- `PersonalStepProgressStore`:
  - `stepProgress.challengeID`: Current tracked challenge UUID.
  - `stepProgress.canRefresh`: Boolean flag for immediate HealthKit refresh availability.
  - `stepProgress.isRefreshing`: Boolean flag for active refresh status.
  - `stepProgress.lastHealthError`: String description of last HealthKit error.
  - `stepProgress.lastUploadError`: String description of last upload error.
  - `stepProgress.refresh()`: Async method to trigger HealthKit sync.

---

## 2. Logic Chain

1. **Observation**: `ChallengesView.swift` and `PersonalChallengeDetailView.swift` currently wrap views inside `DaybreakCard` (rounded 24pt corner paper cards with soft shadows) and `DaybreakSectionLabel` (warm paper section headers).
2. **Deduction**: This directly violates Requirement R1 (Anti-AI-Slop guide: no nested floating cards, no over-rounded bubble pills, pure dark/graphite `#000000`/`#121212` primary) and Requirement R3 (tabular proof-of-work ledger format with flat 1px hairline row separators `#2C2C2E` / `#E5E5EA`).
3. **Observation**: `PersonalChallengeCard` is currently rendered as a standalone rounded card with nested progress bars and status pills.
4. **Deduction**: History rows should be refactored into a unified, high-density **Tabular Proof-of-Work Ledger**. In `ChallengesView.swift`, active and past challenges should be grouped inside sleek dark ledger containers (`graphiteSurface` background, 1px `#2C2C2E` hairline border) with flat 1px hairline dividers between rows, eliminating card-in-card spacing.
5. **Observation**: Status pills currently use rounded bubble styling (`TrustStatusPill`).
6. **Deduction**: Status badges should be refactored into sharp, athletic settlement badges ("Settled", "Goal Met", "Goal Missed", "In Progress", "At Risk", "Didn't Count") featuring 4pt corner radii, 1px hairline borders, and high-visibility athletic accents (`#00D084` Athletic Green for goal met / settled, `#FC5200` Signal Orange for goal missed / at risk).
7. **Observation**: Step counts, dollar stakes ($10–$50), dates, and split metrics currently use default proportional system fonts in several helper labels.
8. **Deduction**: All numerical values (step totals, daily splits, pacing delta, stake amounts $10–$50) must strictly use tabular monospaced digits via `CompetitiveTrustTheme.tabularFont(size:weight:)` or `CompetitiveTrustTheme.monoFont(size:weight:)` to deliver the Strava performance UI aesthetic.
9. **Observation**: UI tests in `GameTimeUITests.swift` perform exact string, button, and hierarchy assertions on accessibility identifiers (e.g. `personal.create`, `personal.challenge.<id>`, `personal.details`, `personal.result`, `personal.review.request`, `personal.cancel`).
10. **Deduction**: All accessibility identifiers and store property bindings must remain 100% intact so that UI test assertions pass cleanly without breaking business logic or Apple Health snapshot handling.

---

## 3. Caveats

1. **Xcode Unsandboxed Execution**: `xcodebuild` commands require `BypassSandbox: true` to access DerivedData outside the sandbox folder; automated terminal commands within sandbox timed out. Build verification must be executed when running unsandboxed or via standard IDE workflows.
2. **Domain Models Read-Only**: Domain models (`PersonalChallengeSummary`, `PersonalChallengeDetail`, `FrozenPersonalTerms`, `PersonalDisplayedProgress`) and store methods must NOT be altered during UI refactoring.
3. **No Copy Vocabulary Violations**: All text on updated screens must strictly adhere to `docs/COPY.md`. No forbidden terms (*snapshot*, *observation*, *evidence*, *attestation*, *provenance*, *friend*, *winner*, *standings*, etc.) can appear on screen.

---

## 4. Conclusion

Milestone M3 requires refactoring `ChallengesView.swift`, `PersonalChallengeDetailView.swift`, and `PersonalAccountabilityComponents.swift` from the warm-paper Daybreak card design into a high-utility, Strava-inspired dark performance proof-of-work ledger.

### Actionable Refactoring Strategy:
1. **Replace Daybreak Card Containers**:
   - Replace `DaybreakCard` rounded containers (24pt radius) in `ChallengesView.swift` and `PersonalChallengeDetailView.swift` with flat `graphiteSurface` (`#121212`) containers bordered by flat 1px hairline dividers (`#2C2C2E` / `#E5E5EA`).
   - Remove card-in-card nesting and soft shadow drop shadows.
2. **Redesign `PersonalChallengeCard` into Tabular History Rows**:
   - Format each history row as a high-density tabular row featuring:
     - Left: Athletic settlement status badge ("Settled", "Goal Met", "Goal Missed", "In Progress").
     - Center: Target & Cadence string + Monospaced step counter (`68,420 / 70,000 steps`).
     - Right: Financial stake ($10–$50) in monospaced SF Mono + date summary + chevron.
   - Preserve `accessibilityIdentifier("personal.challenge.\(challenge.id.uuidString.lowercased())")`.
3. **Refactor Settlement Status Badges (`TrustStatusPill` / `PersonalStatusPill`)**:
   - Update pills into compact rectangular athletic badges with 4pt corner radius, 1px border, and high-contrast Signal Orange (`#FC5200`) and Athletic Green (`#00D084`) text/accents.
4. **Enhance Single Challenge Detail View (`PersonalChallengeDetailView.swift`)**:
   - **Hero Block**: High-visibility dark performance HUD with monospaced step counts, Signal Orange active progress bar, and tabular health sync status.
   - **Pace & Splits Section**: Tabular 7-day split timeline (`PersonalSevenDayTimeline`) and pace tiles (`PersonalPaceTiles`) with hairline borders and monospaced digits.
   - **Result & Review Section**: Clear settlement cards with high-contrast outcome badges ("Goal Met — $0 test charge", "Goal Missed — review open").
   - **Details Card (`PersonalChallengeDetailsCard`)**: Clean key-value tabular layout with hairline row dividers and preserved `personal.details` toggle.
5. **Preserve All 31 Accessibility Identifiers & Store Bindings**:
   - Ensure all 31 accessibility identifiers listed in Section 1 are explicitly bound to the refactored SwiftUI components.

---

## 5. Verification Method

### Independent Verification Steps:
1. **Codebase Inspection**:
   - Verify `ChallengesView.swift` no longer imports or calls `DaybreakCard` or `DaybreakSectionLabel`.
   - Verify `PersonalChallengeDetailView.swift` no longer imports or calls `DaybreakCard` or `DaybreakSectionLabel`.
   - Verify `PersonalAccountabilityComponents.swift` uses `CompetitiveTrustTheme.darkBackground`, `graphiteSurface`, `hairlineDivider`, `tabularFont`, and `monoFont`.
   - Confirm all 31 accessibility identifiers (`personal.create`, `personal.details`, `personal.challenge.<id>`, etc.) are present and properly attached to elements.
2. **Build Verification**:
   - Run: `xcodebuild -scheme GameTime -destination 'generic/platform=iOS' build` from `/Users/user/Documents/GitHub/GameTime/ios/GameTime`.
   - Ensure compilation succeeds with Swift 6 and iOS 18 targets without errors.
3. **Test Suite Verification**:
   - Run unit tests: `xcodebuild test -scheme GameTime -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:GameTimeTests`.
   - Run UI tests: `xcodebuild test -scheme GameTime -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:GameTimeUITests`.
   - Confirm `assertNoForbiddenLanguage` and UI test assertions pass cleanly.
