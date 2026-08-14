# Milestone M4 Specification Handoff Report — Personal Challenge Creation Flow

**Miner Name**: `spec_miner_m4_1` (M4 Specification Miner)  
**Date**: 2026-08-14  
**Target Milestone**: M4 (`PersonalChallengeFlow.swift`)  
**Working Directory**: `/Users/user/Documents/GitHub/GameTime/.agents/teamwork_preview_spec_miner_m4_1`

---

## 1. Observation

Direct code and documentation observations from authoritative codebase files:

### Codebase Files Audited & Inspected
- `ORIGINAL_REQUEST.md`: `/Users/user/Documents/GitHub/GameTime/.agents/ORIGINAL_REQUEST.md` (Requirement R4 & Acceptance Criteria)
- `COPY.md`: `/Users/user/Documents/GitHub/GameTime/docs/COPY.md` (Payment copy contracts & vocabulary glossary)
- `PersonalChallengeFlow.swift`: `ios/GameTime/GameTime/PersonalChallengeFlow.swift` (1315 lines)
- `PersonalAccountabilityModels.swift`: `ios/GameTime/GameTime/PersonalAccountabilityModels.swift`
- `PersonalAccountabilityComponents.swift`: `ios/GameTime/GameTime/PersonalAccountabilityComponents.swift`
- `PersonalChallengeReceiptPresentation.swift`: `ios/GameTime/GameTime/PersonalChallengeReceiptPresentation.swift`
- `PersonalAccountabilityTests.swift`: `ios/GameTime/GameTimeTests/PersonalAccountabilityTests.swift`
- `PersonalChallengeReceiptPresentationTests.swift`: `ios/GameTime/GameTimeTests/PersonalChallengeReceiptPresentationTests.swift`
- `GameTimeUITests.swift`: `ios/GameTime/GameTimeUITests/GameTimeUITests.swift`

### Objective 1: Forbidden Vocabulary Audit Results
Case-insensitive regular expression audit was executed against `PersonalChallengeFlow.swift` for all 12 forbidden terms:
`friend(s)`, `invitation(s)`, `roster(s)`, `competitor(s)`, `rank(s)`, `standing(s)`, `winner(s)/winning`, `charity/charities`, `reaction(s)`, `tie-break`, `B//B`, `Better Bet`.

- **Audit Command**:
  ```bash
  grep -iE "\b(friend|friends|invitation|invitations|roster|rosters|competitor|competitors|rank|ranks|standing|standings|winner|winners|winning|charity|charities|reaction|reactions|tie[- ]?break)\b|B//B|Better Bet" ios/GameTime/GameTime/PersonalChallengeFlow.swift
  ```
- **Audit Findings**: **0 forbidden term occurrences found** in `PersonalChallengeFlow.swift`.
- **UI Test Audit Reference**: `GameTimeUITests.swift` line 2078–2094 defines the authoritative runtime regex assertion `assertNoForbiddenLanguage(in:)`.

### Objective 2: Creation Parameters & Exact Copy Contracts
- **Stakes Range**: `$10, $20, $30, $40, $50` (Minor amounts: `1_000, 2_000, 3_000, 4_000, 5_000`). Default: `$10.00` (`1_000`).
- **Target Steps Range**: `1` to `1,000,000` steps. Default daily: `10,000`. Default cumulative: `70,000`.
- **7-Day Cadence Options**:
  - Daily: rawValue `"daily"`, UI Title `"Every day"`, step goal text `"Steps you’ll walk each day"`, detail `"Hit your goal every single day."`
  - Cumulative: rawValue `"cumulative"`, UI Title `"Week total"`, step goal text `"Steps you’ll walk over the week"`, detail `"Hit one total by the end of the week."`
- **Environment Disclosure Banners**:
  - `testOnly`: `"Test commitment — no money will be charged."`
  - `stripeSandbox`: `"Payment test mode — no real money moves."`
  - `demo`: `"Demo mode — no money will be charged. Nothing here leaves your phone."`
- **Commitment Protection Copy**:
  - `testOnly`: `"\(amount) test commitment. No money will be charged. Missing or unclear step data never counts as a miss."`
  - `stripeSandbox`: `"Your test charge is $0 when you meet your goal or step data is missing or unclear. Only a confirmed miss after review can create one \(amount) test charge."`
- **Payment Setup & Consent Copy (Stripe Sandbox)**:
  - Header: `"Save a payment method in Stripe test mode"` / `"Test payment method saved"`
  - Prompt: `"Add your test payment method before you start."`
  - Consent Switch: `"By starting, you agree that GameTime may create one \(amount) test charge only if this challenge is confirmed missed after the review window. Missing or unclear step data never counts as a miss."`
  - Confirmation status: `"Test payment method saved."` / `"Test method saved — no real money moves."`
- **Confirmation Receipt Structure ("This locks in when you start")**:
  - Group 1: `"Your challenge"` (`how-it-counts`, `goal`, `amount`, `length`)
  - Group 2: `"When it starts"` (`starts`, `day-one`, `time-zone`, `final-check`)
  - Group 3: `"Payment protection"` (`payment-mode`, `zero-outcomes`, `confirmed-miss`, `review`, `missing-data`)

---

## 2. Features Discovered

| # | Category | Feature | Description | Inputs | Outputs | Error Behavior | Discovered Via |
|---|----------|---------|-------------|--------|---------|----------------|----------------|
| 1 | Creation Flow | Step Cadence Selection | Choose between daily target (Every day) and weekly total (Week total). Automatically adjusts target step defaults. | User tap on `.cadence` button (`daily` vs `cumulative`) | Updated `draft.cadence` and `draft.targetSteps` (10,000 vs 70,000) | N/A | `PersonalChallengeFlow.swift:237` |
| 2 | Creation Flow | Target Step Input | Input step target for chosen cadence with keyboard pad. | Numerical step count integer input | Formatted step target | Throws `.invalidTarget` if not within `1...1_000_000` | `PersonalChallengeFlow.swift:264`, `PersonalAccountabilityModels.swift:504` |
| 3 | Creation Flow | Test Commitment Stake Selection | Tactile segmented selection of commitment amount from predefined $10–$50 options. | User tap on amount choice button ($10, $20, $30, $40, $50) | Updated `draft.commitmentAmountMinor` (1000–5000) | Throws `.invalidCommitment` if outside allowed array | `PersonalChallengeFlow.swift:294`, `PersonalAccountabilityModels.swift:319` |
| 4 | Creation Flow | Dynamic Commitment Protection Display | Displays exact legal/payment protection notice matching active settlement mode. | `draft.commitmentAmountMinor` and `store.configuration.personalSettlementMode` | Protection string displayed with shield icon | N/A | `PersonalChallengeFlow.swift:320`, `PersonalChallengeReceiptPresentation.swift:3` |
| 5 | Creation Flow | Start Time & Start-Now Selection | Select future local midnight/hour or toggle "Start right now (count today)". | DatePicker / Hour Picker / Toggle `startsImmediately` | Frozen `startsAt` instant (or `nil` for default next midnight) | Throws `.invalidStart` if past, non-hourly, or >90 days out | `PersonalChallengeFlow.swift:373`, `PersonalAccountabilityModels.swift:158` |
| 6 | Creation Flow | Health Access Verification | Prompts and verifies Apple Health step reading permissions before proceeding. | User tap "Connect Apple Health" | `store.healthReadiness.permitsCreation` state | Disables advance until permitted; shows error if check fails | `PersonalChallengeFlow.swift:526` |
| 7 | Creation Flow | Stripe Sandbox Payment Setup & Consent | Presents payment setup sheet and mandatory consent toggle for Stripe sandbox mode. | Consent toggle ON, tap "Set up test payment" | Confirmed Stripe setup intent ID & saved payment state | Displays warning if consent not toggled; fails closed if setup fails | `PersonalChallengeFlow.swift:578`, `GameTimeUITests.swift:178` |
| 8 | Creation Flow | Receipt & Confirmation Summary | Comprehensive summary sheet grouping parameters into 3 categories with expandable details. | Current draft, settlement mode, start mode | Grouped fact rows (`Your challenge`, `When it starts`, `Payment protection`) and details | Shows stale start error (`.stale-start`) if selected start time passed | `PersonalChallengeFlow.swift:643`, `PersonalChallengeReceiptPresentation.swift:24` |
| 9 | Creation Flow | Draft Autosave & Recovery | Persists active creation draft on phone so user can safely resume or discard. | Interrupted setup / saved retry record | Draft restored on launch with "Ready to finish" / "Continue setup" | Confirmation dialog on discard ("Delete this draft?") | `PersonalChallengeFlow.swift:102`, `GameTimeUITests.swift:1176` |
| 10 | Security / Copy | Environment Disclosure Banner | Compact header banner explicitly stating test/sandbox status above root/sheet. | Settlement mode (`testOnly`, `stripeSandbox`, `demo`) | Banner: "Test commitment — no money will be charged." / "Payment test mode — no real money moves." | Canonical single-banner rule; prevents duplicate cards | `PersonalChallengeFlow.swift:71`, `COPY.md:94` |

---

## 3. Edge Cases

| # | Feature | Input | Observed Behavior |
|---|---------|-------|-------------------|
| 1 | Target Step Validation | Input `0` or `1,000,001` steps | Validation fails with error: `"Enter a whole number of steps, from 1 to 1,000,000."` (`.invalidTarget`). |
| 2 | Stake Validation | Unallowed stake amount (e.g. `$15` / `1500`) | Validation fails with error: `"Pick $10, $20, $30, $40, or $50."` (`.invalidCommitment`). |
| 3 | Daylight Saving Time | Start time falls on spring-forward skipped hour (e.g., 02:00 in America/Chicago) | `PersonalChallengeStart.instant` returns `nil`; hour is excluded from `selectableHours`. |
| 4 | Stale Start Time | Draft left open in review screen until start hour passes | Flow displays warning: `"That start time has already passed. Go back and pick a new one, or delete this draft."` (`personal.review.stale-start`), disabling submission. |
| 5 | Unsaved Setup Discard | Tapping "Close" on dirty creation setup | Triggers alert `"Discard this setup?"` with options `"Discard changes"` (destructive) and `"Keep editing"` (cancel). |
| 6 | Saved Draft Discard | Discarding a saved pending creation retry | Triggers confirmation dialog `"Delete this draft?"` with options `"Delete draft"` and `"Keep it"`. |
| 7 | Current Minute Start | "Start right now" toggle activated | `startsAt` is set to `currentMinute(now:)`; first day counts all eligible steps from midnight today. |
| 8 | Accessibility Type Size | `UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge` (XXXL) | UI switches grid layout to vertical stack for stake choices (`commitmentAmountChoice`) and receipt fact rows. |
| 9 | Network Loss during Payment Setup | Payment sheet network failure | Displays error `"Stripe couldn’t save that test payment method. Try again when you’re ready."` without corrupting draft. |
| 10 | Profile Timezone Travel | Device changes timezone while profile timezone is set | Draft preserves `profileTimezone` ("America/Chicago") rather than dynamic device timezone ("Europe/Paris"). |

---

## 4. Logic Chain

1. **Observation 1.1**: Inspecting `ORIGINAL_REQUEST.md` (R4) specifies: "Target selection, 7-day cadence (daily vs cumulative), and test commitment stake selection ($10–$50) presented in a clean, tactile segmented layout without generic onboarding slides or fake loading animations."
2. **Observation 1.2**: Inspecting `docs/COPY.md` provides strict payment copy contracts, requiring exact wording for test commitments, Stripe sandbox mode, zero-charge promises, and forbidden terms.
3. **Observation 1.3**: Executing regex search against `PersonalChallengeFlow.swift` yields 0 matches for all 12 forbidden terms (`friend(s)`, `invitation(s)`, `roster(s)`, `competitor(s)`, `rank(s)`, `standing(s)`, `winner(s)/winning`, `charity/charities`, `reaction(s)`, `tie-break`, `B//B`, `Better Bet`).
4. **Observation 1.4**: Inspecting `PersonalChallengeFlow.swift`, `PersonalAccountabilityModels.swift`, and `PersonalChallengeReceiptPresentation.swift` verifies that commitment amounts are strictly limited to `$10, $20, $30, $40, $50` (`[1000, 2000, 3000, 4000, 5000]`), and cadences are strictly 7-day (`daily` with default 10k steps/day vs `cumulative` with default 70k steps/week).
5. **Observation 1.5**: Inspecting `GameTimeUITests.swift` and `PersonalAccountabilityTests.swift` reveals 25+ unit and UI test cases asserting on every creation step, accessibility identifier, error string, and payment consent contract.
6. **Conclusion**: `PersonalChallengeFlow.swift` fully complies with Requirement R4 and `COPY.md` rules. All creation specifications, parameters, anti-slop rules, copy strings, accessibility identifiers, and unit test assertions are fully documented and ready for implementation verification.

---

## 5. Caveats

- **No Caveats**: The codebase was completely accessible, fully readable, and all unit/UI test assertions and view specifications were extracted directly from authoritative source files without ambiguity.

---

## 6. Conclusion

Milestone M4 (`PersonalChallengeFlow.swift`) specification mining is complete. The component enforces strict 7-day cadence (daily vs cumulative), $10–$50 stake selection, exact Stripe sandbox and test-only payment copy contracts, complete zero-slop vocabulary compliance, and comprehensive accessibility test hooks.

---

## 7. Verification Method

To verify these mined specifications independently:

### 1. Build Verification
Run the iOS build command:
```bash
xcodebuild -scheme GameTime -destination 'generic/platform=iOS' build
```

### 2. Unit Test Suite Verification
Run the unit test suite covering `PersonalAccountabilityTests` and `PersonalChallengeReceiptPresentationTests`:
```bash
xcodebuild test -scheme GameTime -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:GameTimeTests/PersonalAccountabilityModelTests -only-testing:GameTimeTests/PersonalChallengeReceiptPresentationTests
```

### 3. UI Test & Anti-Slop Verification
Run UI tests including forbidden vocabulary assertions (`assertNoForbiddenLanguage`):
```bash
xcodebuild test -scheme GameTime -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:GameTimeUITests/GameTimeUITests/testCumulativeCreationOmitsFixedMetricAndStartSteps -only-testing:GameTimeUITests/GameTimeUITests/testStripeSandboxFlowUsesFixturePaymentAndExactConsent
```

### 4. Forbidden Vocabulary Re-Audit
Execute the exact regex audit on `PersonalChallengeFlow.swift`:
```bash
grep -iE "\b(friend|friends|invitation|invitations|roster|rosters|competitor|competitors|rank|ranks|standing|standings|winner|winners|winning|charity|charities|reaction|reactions|tie[- ]?break)\b|B//B|Better Bet" ios/GameTime/GameTime/PersonalChallengeFlow.swift
```
*Expected Result: Exit code 1 (no lines matched).*

---

### Appendix: UI Test Accessibility Identifiers Inventory

| Accessibility Identifier | Component / Screen | Purpose |
|--------------------------|-------------------|---------|
| `personal.create` | Challenges / Today View | Button to launch creation sheet |
| `personal.continue` | Flow Controls | Primary button to advance to next step |
| `personal.back` | Flow Controls | Secondary button to return to previous step |
| `personal.target.done` | Toolbar | Keyboard Done button for target input |
| `personal.cadence.daily` | Step 2 (Cadence) | Button for "Every day" cadence |
| `personal.cadence.cumulative` | Step 2 (Cadence) | Button for "Week total" cadence |
| `personal.target` | Step 3 (Target) | Step goal text field |
| `personal.commitment.1000` | Step 4 (Commitment) | $10 stake selection button |
| `personal.commitment.2000` | Step 4 (Commitment) | $20 stake selection button |
| `personal.commitment.3000` | Step 4 (Commitment) | $30 stake selection button |
| `personal.commitment.4000` | Step 4 (Commitment) | $40 stake selection button |
| `personal.commitment.5000` | Step 4 (Commitment) | $50 stake selection button |
| `personal.commitment.protection` | Step 4 (Commitment) | Protection disclosure text label |
| `personal.start.day` | Step 5 (Start) | Start day DatePicker |
| `personal.start.hour` | Step 5 (Start) | Start hour Picker |
| `personal.start.tomorrow` | Step 5 (Start) | "Tonight at midnight" button |
| `personal.start.next-hour` | Step 5 (Start) | "Next hour" button |
| `personal.start.consequence` | Step 5 (Start) | Day one consequence explanation text |
| `personal.start.now` | Step 5 / Step 7 / Step 8 | "Start right now (count today)" toggle |
| `personal.health.verify` | Step 6 (Health Access) | "Connect Apple Health" button |
| `personal.payment.consent` | Step 7 (Payment) | Payment consent switch toggle |
| `personal.payment.setup` | Step 7 (Payment) | "Set up test payment" primary button |
| `personal.receipt` | Step 8 (Review) | Receipt title header ("This locks in when you start") |
| `personal.review.stale-start` | Step 8 (Review) | Warning label when chosen start hour has passed |
| `personal.receipt.group.challenge` | Step 8 (Review) | "Your challenge" group header |
| `personal.receipt.group.start` | Step 8 (Review) | "When it starts" group header |
| `personal.receipt.group.payment` | Step 8 (Review) | "Payment protection" group header |
| `personal.receipt.fact.how-it-counts` | Step 8 (Review) | How it counts fact row |
| `personal.receipt.fact.goal` | Step 8 (Review) | Goal fact row |
| `personal.receipt.fact.amount` | Step 8 (Review) | Amount fact row |
| `personal.receipt.fact.length` | Step 8 (Review) | Length fact row |
| `personal.receipt.fact.starts` | Step 8 (Review) | Starts fact row |
| `personal.receipt.fact.day-one` | Step 8 (Review) | Day one fact row |
| `personal.receipt.fact.time-zone` | Step 8 (Review) | Time zone fact row |
| `personal.receipt.fact.final-check` | Step 8 (Review) | Final check fact row |
| `personal.receipt.fact.payment-mode` | Step 8 (Review) | Payment mode fact row |
| `personal.receipt.fact.zero-outcomes` | Step 8 (Review) | $0 outcomes fact row |
| `personal.receipt.fact.confirmed-miss` | Step 8 (Review) | Confirmed miss fact row |
| `personal.receipt.fact.review` | Step 8 (Review) | Review window fact row |
| `personal.receipt.fact.missing-data` | Step 8 (Review) | Missing data fact row |
| `personal.receipt.more-details` | Step 8 (Review) | "More details" disclosure button |
| `personal.receipt.detail.cadence` | Step 8 (Review) | Expanded cadence explanation detail |
| `personal.receipt.detail.day-one` | Step 8 (Review) | Expanded day one explanation detail |
| `personal.receipt.detail.cancellation` | Step 8 (Review) | Expanded cancellation detail |
| `personal.receipt.detail.saved-draft` | Step 8 (Review) | Expanded saved draft detail |
| `personal.submit` | Step 8 (Review) | "Start my challenge" submission button |
| `personal.pending.discard-review` | Step 8 (Review) | "Delete draft" button |
| `personal.pending.resume` | Challenges View | "Continue setup" button for saved draft |
| `personal.environment-disclosure` | Global Header | Ambient environment disclosure banner |
