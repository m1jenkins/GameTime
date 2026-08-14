# Specification Handoff Report — Milestone M3 Specification Mining

## 1. Observation
- **Forbidden Vocabulary Audit**: Executed case-insensitive regex search (`friends?|invitations?|rosters?|competitors?|ranks?|standings?|winners?|winning|charity|charities|reactions?|tie-?break|B//B|Better Bet`) against the 3 target files:
  - `ios/GameTime/GameTime/ChallengesView.swift`: 0 occurrences found.
  - `ios/GameTime/GameTime/PersonalChallengeDetailView.swift`: 0 occurrences found.
  - `ios/GameTime/GameTime/PersonalAccountabilityComponents.swift`: 0 occurrences found.
  - Verification in `ios/GameTime/GameTimeUITests/GameTimeUITests.swift`: Line 2078 enforces regex check `(?i)\b(?:friend|friends|invitation|invitations|roster|rosters|competitor|competitors|rank|ranks|standing|standings|winner|winners|winning|charity|charities|reaction|reactions|tie[- ]?break)\b` and `B//B|Better Bet` across all reachable UI elements via `assertNoForbiddenLanguage`.
- **Exact Copy Contracts**:
  - Section Labels: `"Your challenge"` (`ChallengesView.swift:18`), `"Finished"` (`ChallengesView.swift:27`), `"Unfinished setup"` (`ChallengesView.swift:103`), `"Your pace"` (`PersonalChallengeDetailView.swift:278`), `"How it went"` (`PersonalChallengeDetailView.swift:325`), `"Review"` (`PersonalChallengeDetailView.swift:358`).
  - Status Badges & Outcomes:
    - `.metGoal` outcome: `"Goal met"` badge, `"Goal met — $0 test charge."` (Sandbox title in `COPY.md:76`).
    - `.missedGoal` outcome: `"Goal missed"` badge, `"Goal missed — review open. Settlement is paused. Ask us to review this result by \(reviewDeadline)."` (`COPY.md:78`), `"Under review — settlement paused."` (`PersonalChallengeDetailView.swift:365`), `"Processing one \(amount) test charge."` (`COPY.md:81`), `"Test charge complete — sandbox transaction recorded."` (`COPY.md:82`).
    - `.inconclusive` outcome: `"Didn’t count"` badge, `"This one didn't count — $0 test charge."` (`COPY.md:77`).
    - Presentation Statuses without final outcome: `"Scheduled"` (`PersonalAccountabilityComponents.swift:144`), `"In progress"` (`:145`), `"Waiting on steps"` (`:146`), `"Almost done"` (`:147`), `"Cancelled"` (`:148`), `"Done"` (`:149`).
  - Terms Accordion (`PersonalPaceComponents.swift:883-946`):
    - Button Label: `"Challenge details"` (`personal.details`)
    - Key Rows: `"How it counts"`, `"Goal"`, `"Amount"`, `"Time zone"`, `"Starts"`, `"Ends"`, `"Updates through"`.
  - Environmental Disclosures: `"Payment test mode — no real money moves."` (`COPY.md:70`), `"Test commitment — no money will be charged."` (`COPY.md:62`), `"Demo mode — no money will be charged. Nothing here leaves your phone."` (`COPY.md:102`).
  - Cancellation Dialogs (`PersonalChallengeDetailView.swift:524-532`):
    - Sandbox: `"This ends the challenge immediately. It will stay in your history, and your saved test payment method will not be charged."`
    - Test-only: `"This ends the test challenge immediately. It will stay in your history, and no money will be charged."`
    - Default pre-start: `"You can only cancel before your challenge starts. Cancelling before it starts closes the test commitment."`
- **Unit Test Requirements (`ios/GameTime/GameTimeTests/PersonalAccountabilityTests.swift`)**:
  - `testRefreshReplacesCachedActiveDetailWithTerminalFrozenSummary` (Line 512): Validates active detail updates to terminal frozen summary on refresh; progress source transitions to `.frozenResult` and `isFrozen == true`.
  - `testRefreshReplacesCachedOpenDetailWithCancellationTruth` (Line 564): Validates active detail updates to cancelled status and moves from `openChallenge` to `history`.
  - `testTerminalDetailPromotesOpenListAndFreezesEverySurface` (Line 603): Validates terminal detail synchronization clears active step progress store and invalidates step snapshot cache.
  - `testCancelledDetailPromotesOpenListAndRetiresMutableProgress` (Line 677): Validates cancelled detail clears step progress and invalidates cache.
  - `testStaleOpenListCannotUndoTerminalDetailPromotion` (Line 748): Validates monotonic state machine—stale open list response cannot override terminal detail state.
  - `testMissingHealthDataReasonUsesPlainV2Language` (Line 35): Asserts `PersonalReasonText.sentence(for: "missing_health_data")` returns `"Apple Health didn’t have step data available for this challenge."`.
  - `testOpenChallengeBecomesResultPendingAtEvidenceCutoff` (Line 251): Asserts active challenge becomes `.resultPending` at `evidenceCutoff` and `permitsActivitySync` becomes `false`.
- **UI Test Accessibility Identifiers (`ios/GameTime/GameTimeUITests/GameTimeUITests.swift`)**:
  - `personal.create`: "Start a challenge" button (`ChallengesView.swift:56`).
  - `personal.pending.resume`: "Continue setup" button (`ChallengesView.swift:131`).
  - `personal.challenge.<id>`: Card container for challenge item (`PersonalAccountabilityComponents.swift:103`).
  - `personal.challenge.sync-now`: "Sync now" / "Try Again" button (`PersonalChallengeDetailView.swift:214`).
  - `personal.challenge.health-help`: "Apple Health help" link (`PersonalChallengeDetailView.swift:252`).
  - `personal.challenge.account-support`: "Account & support" button (`PersonalChallengeDetailView.swift:222`).
  - `personal.details`: "Challenge details" terms accordion button (`PersonalPaceComponents.swift:903`).
  - `personal.progress`: Progress bar container (`PersonalAccountabilityComponents.swift:188`).
  - `personal.progress.steps`: Steps progress label (`PersonalAccountabilityComponents.swift:217`).
  - `personal.progress.remaining`: Remaining steps label (`PersonalAccountabilityComponents.swift:221`).
  - `personal.health.status`: Apple Health progress status text (`PersonalAccountabilityComponents.swift:440`).
  - `personal.result`: "How it went" result card container (`PersonalChallengeDetailView.swift:348`).
  - `personal.review.available`: Review request container card when review window is active (`PersonalChallengeDetailView.swift:397`).
  - `personal.review.submitted`: Under review container card (`PersonalChallengeDetailView.swift:380`).
  - `personal.review.expired`: Review expired notice (`PersonalChallengeDetailView.swift:387`).
  - `personal.review.reason.<rawValue>`: Review reason selection item (e.g. `personal.review.reason.userDisputesStepData`, `:426`).
  - `personal.review.request`: "Request a review" button (`PersonalChallengeDetailView.swift:462`).
  - `personal.cancel`: "Cancel this challenge" destructive button (`PersonalChallengeDetailView.swift:521`).
  - `personal.cancellation.pending`: Pending cancellation recovery header (`PersonalAccountabilityComponents.swift:501`).
  - `personal.cancellation.retry`: "Retry Cancellation" button (`PersonalAccountabilityComponents.swift:518`).
  - `personal.cancellation.refresh`: "Refresh" button (`PersonalAccountabilityComponents.swift:527`).
  - `personal.cancellation.support`: "Contact Support" button (`PersonalAccountabilityComponents.swift:535`).
  - `personal.legacy-hold`: Legacy readiness notice card (`PersonalAccountabilityComponents.swift:740`).
  - `personal.environment-disclosure`: Ambient environment disclosure banner (`PersonalPaceComponents.swift`, `COPY.md:105`).

## 2. Logic Chain
1. **Audit Logic**: To verify zero AI-slop / competitive language violations, case-insensitive regex pattern matching was performed against all 12 terms (`friend(s)`, `invitation(s)`, `roster(s)`, `competitor(s)`, `rank(s)`, `standing(s)`, `winner(s)/winning`, `charity/charities`, `reaction(s)`, `tie-break`, `B//B`, `Better Bet`). All 3 target view files returned 0 matches, confirming strict compliance. `GameTimeUITests.swift` includes an automated check (`assertNoForbiddenLanguage`) asserting this on runtime XCUIElements.
2. **Copy Contract Logic**: User-facing copy was verified against `docs/COPY.md` and Swift literal declarations in `ChallengesView.swift`, `PersonalChallengeDetailView.swift`, `PersonalAccountabilityComponents.swift`, and `PersonalPaceComponents.swift`. Plain language guidelines (no technical jargon like `snapshot`, `RPC`, or `AppAttest` exposed to users) govern all error and status copy.
3. **Settlement Logic**: Settlement state transitions follow `PersonalChallengePresentationStatus` and `PersonalOutcomeKind`. A challenge transitions monotonically from `.scheduled` → `.active` → `.awaitingEvidence` / `.resultPending` → `.completed` / `.cancelled`. If an outcome is `.missedGoal` under Stripe sandbox, a 7-day review window opens, showing `"Under review — settlement paused."` when a dispute is submitted.
4. **Test Assertion Logic**: Unit tests in `PersonalAccountabilityTests.swift` ensure that terminal state promotions freeze progress and purge local step caches, and that stale network responses cannot regress state. UI tests in `GameTimeUITests.swift` rely on precise accessibility identifiers (`personal.*`) to assert element existence, tap interactions, and absence of legacy or forbidden UI surfaces.

## 3. Caveats
- No caveats. All target source files, copy guidelines, unit test suites, and UI test suites were fully inspected and documented.

## 4. Conclusion
Milestone M3 (`ChallengesView.swift` & `PersonalChallengeDetailView.swift`) fully adheres to the anti-slop copy rules in `docs/COPY.md` with zero forbidden terms. Settlement status badges, daily split snapshots, accordion terms disclosures, and 7-day review flows are tightly defined and covered by existing unit tests in `PersonalAccountabilityTests.swift` and UI test identifiers in `GameTimeUITests.swift`.

## 5. Verification Method
1. **Forbidden Terms Verification**:
   Run grep across target files:
   `grep -iE "friend|invitation|roster|competitor|rank|standing|winner|winning|charity|reaction|tie-?break|B//B|Better Bet" ios/GameTime/GameTime/ChallengesView.swift ios/GameTime/GameTime/PersonalChallengeDetailView.swift ios/GameTime/GameTime/PersonalAccountabilityComponents.swift`
   Expected result: 0 matching lines.
2. **Unit Tests Verification**:
   Run `xcodebuild -scheme GameTime -destination 'generic/platform=iOS' test` (or test runner) and verify `PersonalAccountabilityTests` passes.
3. **UI Tests Verification**:
   Inspect accessibility identifiers in `GameTimeUITests.swift` against `ChallengesView.swift` and `PersonalChallengeDetailView.swift` to ensure test assertions match button/card identifiers.

---

## Features Discovered
| # | Category | Feature | Description | Inputs | Outputs | Error Behavior | Discovered Via |
|---|----------|---------|-------------|--------|---------|----------------|----------------|
| 1 | Navigation & History | Challenge History List | Displays active challenge (`Your challenge`) and past challenges (`Finished`) using flat hairline separators without nested floating cards | `store.openChallenge`, `store.history` | List of `PersonalChallengeCard` elements | Shows `loadState` retry view on failure or `EmptyTrustState` when empty | `ChallengesView.swift:18-35` |
| 2 | Challenge Detail | Athletic Detail Ledger | Shows hero commitment block, step progress, health status, cancellation/review options, pace breakdown, and terms disclosure | `challengeID: UUID` | `PersonalChallengeDetailView` hierarchy | Displays loading card when detail is unavailable | `PersonalChallengeDetailView.swift:37-56` |
| 3 | Pacing Ledger | Daily Split Pace Summary | Tabular 7-day breakdown with day-by-day verdict icons, step counts, and delta pacing | `PersonalPaceSummary(detail, progress)` | Pacing summary card and `PersonalPaceTiles` | Displays status-appropriate empty pace message when no steps exist | `PersonalPaceComponents.swift:11-200`, `PersonalChallengeDetailView.swift:276-293` |
| 4 | Settlement | Status Badges & Result Card | Clean settlement pills (`Goal met`, `Goal missed`, `Didn't count`, `In progress`, `Scheduled`, `Waiting on steps`, `Almost done`, `Cancelled`, `Done`) | `status`, `outcome` | `PersonalStatusPill`, `personal.result` card | Discloses pause on settlement during dispute window | `PersonalAccountabilityComponents.swift:127-168`, `PersonalChallengeDetailView.swift:318-350` |
| 5 | Dispute Resolution | 7-Day Review Window | Allows requesting review for missed sandbox goals within 7 days of publication | `selectedReviewReason` (`PersonalReviewReason`) | Updates UI to `Under review — settlement paused.` | Displays expired notice if past 7-day window | `PersonalChallengeDetailView.swift:353-469` |
| 6 | Terms Disclosure | Foldable Terms Accordion | Expands frozen terms (`How it counts`, `Goal`, `Amount`, `Time zone`, `Starts`, `Ends`, `Updates through`) | User tap on accordion header | `PersonalChallengeDetailsCard` expanded view | Keeps terms folded by default; accessible toggle state | `PersonalPaceComponents.swift:883-946` |
| 7 | Resilience & Recovery | Pending Cancellation Recovery | Retries or refreshes unconfirmed challenge cancellation requests stored locally | Retry / Refresh / Support button taps | `PendingPersonalCancellationRecoveryCard` | Displays recovery message if saved cancellation cannot be read safely | `PersonalAccountabilityComponents.swift:470-615` |
| 8 | Resilience & Recovery | Unfinished Draft Setup Recovery | Offers resume setup or delete draft for uncommitted challenge creations | Resume setup / Delete draft taps | Resume setup sheet or discard confirmation dialog | Shows triangle alert card if draft cannot be safely restored | `ChallengesView.swift:101-151` |

## Edge Cases
| # | Feature | Input | Observed Behavior |
|---|---------|-------|-------------------|
| 1 | Detail Synchronization | Server returns terminal status (`completed`) while client list still holds open challenge | Detail load immediately updates history, removes `openChallenge`, clears `stepProgress.challengeID`, and purges local step cache (`testTerminalDetailPromotesOpenListAndFreezesEverySurface`). |
| 2 | Cancellation Sync | Client cancels active challenge offline or during network drop | Cancellation request saved locally on phone; `PendingPersonalCancellationRecoveryCard` presented on detail and list views until confirmed. |
| 3 | Review Expiration | Review deadline passes (7 days post publication) | Review request button is hidden and replaced by `The review request window ended.` (`personal.review.expired`). |
| 4 | Missing Step Data | Challenge completes with `missing_health_data` reason code | Pace section displays `No Apple Health step data was available for this challenge.` and outcome shows `This one didn't count — $0 test charge.` without penalizing user. |
| 5 | Stale List Overwrite | Stale refresh response arrives after terminal detail promotion | Monotonic transition enforcement prevents stale list response from overriding terminal detail state (`testStaleOpenListCannotUndoTerminalDetailPromotion`). |
| 6 | Cutoff Transition | Local time reaches `evidenceCutoff` while challenge status is active | Presentation status automatically transitions to `.resultPending` (`Almost done`) and disables sync action (`permitsActivitySync == false`). |
