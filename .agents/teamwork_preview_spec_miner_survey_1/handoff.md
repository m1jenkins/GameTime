# Handoff Report: Specification Mining & Copy Rule Extraction

## 1. Observation

### Authoritative Specification Sources Examined
1. **`docs/COPY.md`**: Primary copy contract, domain vocabulary mapping, tone guidelines, payment copy contract (Stage A, Stripe Sandbox, Live), error messaging rules, environment disclosure placement rules, and forbidden Social V1 terms.
2. **`ORIGINAL_REQUEST.md`**: Functional and design requirements for redesigning GameTime from warm-paper "Daybreak" aesthetic to Strava-dominant athletic performance design system with high-contrast surfaces, split pacing, anti-AI-slop principles, proof-of-work ledger, and dynamic pace recalibration.
3. **Codebase UI Files & Test Suite**:
   - `ios/GameTime/GameTime/TodayView.swift`
   - `ios/GameTime/GameTime/ChallengesView.swift`
   - `ios/GameTime/GameTime/PersonalChallengeDetailView.swift`
   - `ios/GameTime/GameTime/PersonalChallengeFlow.swift`
   - `ios/GameTime/GameTime/PersonalAccountabilityComponents.swift`
   - `ios/GameTime/GameTime/PersonalPaceComponents.swift`
   - `ios/GameTime/GameTime/CompetitiveTrustTheme.swift`
   - `ios/GameTime/GameTime/ChallengeVisualComponents.swift`
   - `ios/GameTime/GameTime/FeatureComponents.swift`
   - `ios/GameTime/GameTime/YouView.swift`
   - `ios/GameTime/GameTime/LaunchingView.swift`
   - `ios/GameTime/GameTimeUITests/GameTimeUITests.swift`

### Extracted Core Rules & Constraints

#### A. Voice, Tone & Perspective Rules
1. **User Action / Observable State Focus**: Describe what the user sees or needs to do, not internal system computations (e.g., `"Updated from Apple Health 3 min ago"` rather than `"snapshot observed at 14:03 and queried through 14:02"`).
2. **Actionable Error Messages**: Every error must explain what happened and provide a clear next step (e.g., `"We couldn’t update Apple Health right now. Your last update is still here."`).
3. **Active Voice & Explicit Actors**: Use `"we"` for GameTime and `"you"` for the user. Eliminate passive constructions (*was observed*, *could not be verified*, *is required*).
4. **No Internal Identifiers as Prose**: Never format enum values or underscore-separated reason codes into title-case strings (`identity_mismatch` → "identity mismatch" is forbidden). Map known codes to sentences via `PersonalReasonText`; present unknown codes explicitly as `Reference: <code>`.
5. **No System / Infrastructure Leaks**: Hide build, API, RPC, App Attest, Staging, Debug, HealthKit, and Supabase internal terminology from user-facing screens.
6. **Generous Protection Reassurance**: Emphasize fail-closed safety (missing or unclear step data never counts as a miss and never counts against the user).
7. **Exact Payment Triggers**: State payment consequences as `"confirmed miss after review"`, never using vague or punitive words like `"failure"`, `"forfeit"`, or `"we may charge you"`.

#### B. Exact Payment Copy Contract (Stripe Sandbox & Stage A)
- **Ambient Environment Disclosures** (shown ONCE above app root, `personal.environment-disclosure`, and ONCE inside creation sheet):
  - Stage A internal test mode: `"Test commitment — no money will be charged."`
  - Stripe sandbox mode: `"Payment test mode — no real money moves."`
  - Interactive Demo mode: `"Demo mode — no money will be charged. Nothing here leaves your phone."`
- **Sandbox UI States**:
  - Payment Setup: `"Add your test payment method before you start."`
  - Consent Text: `"By starting, you agree that GameTime may create one \(amount) test charge only if this challenge is confirmed missed after the review window. Missing or unclear step data never counts as a miss."`
  - Met Goal Outcome: `"Goal met — $0 test charge."`
  - Inconclusive / Waived Outcome: `"This one didn’t count — $0 test charge."`
  - Provisional Miss: `"Goal missed — review open. Settlement is paused. Ask us to review this result by \(reviewDeadline)."`
  - Review Pending: `"Under review — settlement paused."`
  - Confirmed Miss: `"Processing one \(amount) test charge."`
  - Test Payment Complete: `"Test charge complete — sandbox transaction recorded."`
  - Payment Failed / Action Required: `"Test payment needs your attention. We won’t try again automatically."`
  - Sandbox Cancellation: `"This ends the challenge immediately. It will stay in your history, and your saved test payment method will not be charged."`
- **Payment Method Display**: Show brand and last 4 digits only (e.g. `"Visa ···· 4242"` / `"Test method saved"`). Never expose card numbers, Stripe IDs, `SetupIntent`, `PaymentIntent`, mandate, or idempotency language.

#### C. Domain Glossary Mapping Matrix

| System / Internal Term | Required On-Screen Term | Notes & Guidelines |
|---|---|---|
| snapshot steps, historical trusted steps | **steps** | Bare count of verified steps |
| snapshot observation / update time | **"Updated from Apple Health 3 min ago"** | User-centered timestamp |
| stale retained snapshot | **"Last updated … · Apple Health is temporarily unavailable"** | Explains issue & retains previous step value |
| frozen terms | **"what you signed up for"** / **"this locks in when you start"** | Replaces legalistic terms |
| cadence | **"how it counts"** | Creation step title |
| daily / cumulative | **"Every day" / "Week total"** | Cadence choices in UI |
| legacy Stage A commitment | **amount ("Test commitment — no money will be charged.")** | Environment disclosure |
| Stripe sandbox commitment | **amount ("Payment test mode — no real money moves.")** | Environment disclosure |
| settlement mode | *(Not shown on screen)* | Covered by environment disclosure banner |
| saved payment method, `SetupIntent` | **"payment method"** / **"Test method saved"** | High-level user description |
| off-session mandate | Exact one-time authorization sentence | In sandbox consent switch |
| provisional `missed_goal` | **"goal missed — review open"** | Settlement paused state |
| `review_deadline` | **"review by"** | Date deadline label |
| off-session `PaymentIntent` | **"one-time charge"** | Payment disclosure |
| failed payment, customer action required | **"payment needs your attention"** | Actionable status |
| metric | *(Not shown while steps are the only option)* | Omitted from UI |
| Health permission request | **"Connect Apple Health"** | Consistent action label |
| App Attest, attestation, provenance | *(Never shown on Personal screens)* | Developer/infrastructure term |
| historical evidence, coverage, diagnostic, eligibility hold | *(Never shown on Personal v2 screens)* | Legacy V1 term |
| inconclusive, waived | **"didn’t count"** / **"it doesn’t count against you"** | Reassuring outcome language |
| evidence cutoff, snapshot cutoff | **"We’ll keep checking Apple Health through …"** | Honest timing explanation |
| no successful snapshot | **"No step data available yet"** plus Apple Health settings help | Actionable empty state |
| local day | **day** | Simple temporal reference |
| pending creation, retry record | **draft** | User draft concept |
| protected storage | **saved on your phone** | Clear local storage description |
| handle | **username** | User profile label |
| surface, route, view | *(Never shown)* | Implementation jargon |
| Staging, Debug, HealthKit, Supabase | *(Never shown)* | Infrastructure names |

#### D. Forbidden Words & Social V1 Vocabulary (Strict Regex Compliance)
Enforced in UI testing (`GameTimeUITests.swift:assertNoForbiddenLanguage`):
- `friend`, `friends`
- `invitation`, `invitations`
- `roster`, `rosters`
- `competitor`, `competitors`
- `rank`, `ranks`
- `standing`, `standings`
- `winner`, `winners`, `winning`
- `charity`, `charities`
- `reaction`, `reactions`
- `tie-break`, `tie break`
- `B//B`, `Better Bet`

#### E. Anti-AI-Slop Visual & Copy Anti-Patterns
1. **Forbidden Copy**: Greeting headers ("Good morning", "Welcome back", "Hello"), generic motivational fluff ("You got this!", "Awesome work!", "Crushing it!").
2. **Forbidden Aesthetics**: Warm-paper background tint (`#FFF7F0`), paper-sunk backgrounds (`#F7EBE2`), soft pastel pills (`coralTint`, `sunTint`), floating bento cards (`DaybreakCard` / `trustCard()`), over-rounded bubble pills, pastel gradients, glowing card borders.
3. **Forbidden Theme Terminology in Codebase**: `CompetitiveTrustTheme`, `DaybreakCard`, `DaybreakSectionLabel`, `daybreakScreenChrome()`, `daybreakTabScrollClearance()`, `DaybreakSpinner`, `DaybreakAppearance`, `daybreakTargetText`, `daybreakGoalLabel`.

---

## 2. Logic Chain

1. **Mapping Requirements to Implementation Architecture**:
   - The user request requires a transition from the warm-paper Daybreak design language (`CompetitiveTrustTheme.swift`) to a high-contrast, Strava-dominant athletic performance design system.
   - To achieve compliance with `docs/COPY.md`, all UI components must be checked against vocabulary constraints, exact payment copy strings, and forbidden V1 terms.

2. **Screen-by-Screen Inventory & Copy Requirement Analysis**:

   - **`TodayView.swift` (Active Commitment & Segment Split)**:
     - *Current Implementation*: Displays date headers ("Thursday, August 13"), section labels (`Your week`, `Day by day`), nested `DaybreakCard` containers, and button `"See details"`.
     - *Required Transformation*:
       - Hero Performance Block: Tabular step display (current total vs 7-day target) using SF Pro Display / SF Mono.
       - 7-Day Athletic Splits Breakdown: D1 to D7 visual split bars showing actual steps, required daily split pace, and pacing delta (+/- steps ahead/behind).
       - Dynamic Pace Recalibration: Daily step volume needed over remaining days.
       - Stakes & Sync Status HUD: High-density financial stake status ($10–$50 locked) + Apple Health sync status ("Updated from Apple Health 3 min ago") without floating bento boxes.

   - **`ChallengesView.swift` (Proof-of-Work Ledger)**:
     - *Current Implementation*: Uses `DaybreakSectionLabel` (`Your challenge`, `Finished`, `Unfinished setup`) and floating cards (`PersonalChallengeCard`).
     - *Required Transformation*:
       - Athletic proof-of-work ledger with 1px hairline row separators (`#2C2C2E`) instead of cards on cards.
       - Settlement Badges: Flat status badges (`Settled`, `Completed`, `At Risk`, `Goal met`, `Goal missed`, `Didn't count`, `Under review`).
       - Tabular split breakdown of historical challenges.

   - **`PersonalChallengeDetailView.swift` (Challenge Detail & Review Ledger)**:
     - *Current Implementation*: Section headers (`Your pace`, `How it went`, `Review`, `Challenge details`), sync buttons (`"Sync now"`, `"Try Again"`), review flow.
     - *Required Transformation*:
       - High-visibility hero metrics (tabular step metrics and split pacing).
       - Verified Apple Health snapshot breakdown.
       - Clean settlement badges and 1px hairline row separators.
       - Strict preservation of review and cancellation copy contracts.

   - **`PersonalChallengeFlow.swift` (Creation Builder)**:
     - *Current Implementation*: Step wizard with titles ("How it counts", "Your goal", "Your amount", "Apple Health", "Test payment", "Check and confirm").
     - *Required Transformation*:
       - High-efficiency athletic commitment builder: Target selection, 7-day cadence (daily vs cumulative: "Every day" / "Week total"), test commitment stake selection ($10–$50) in a tactile segmented layout.
       - No onboarding slides, no fake loading spinners, no bento containers.

   - **`PersonalAccountabilityComponents.swift` & `PersonalPaceComponents.swift`**:
     - *Current Implementation*: Defines `TrustStatusPill`, `PersonalProgressBar`, `PersonalHealthProgressStatus`, `PersonalSevenDayTimeline`, `PersonalPaceCard`, `PersonalPaceTiles`.
     - *Required Transformation*:
       - Replace soft pastel pills with high-contrast athletic badges (Strava Signal Orange `#FC5200`, Athletic Green `#00D084`, Sharp Neutral `#2C2C2E`).
       - Re-architect timeline into 7-Day Athletic Splits with tabular +/- pacing deltas.

---

## 3. Features Discovered

## Features Discovered
| # | Category | Feature | Description | Inputs | Outputs | Error Behavior | Discovered Via |
|---|----------|---------|-------------|--------|---------|----------------|----------------|
| 1 | Today Screen | Hero Performance Block | Displays total steps vs 7-day target with high-visibility daily split metrics | Target step count, verified Health steps | High-contrast split metrics with tabular typography | Shows retained step count with stale status if sync fails | `ORIGINAL_REQUEST.md` R2, `TodayView.swift` |
| 2 | Today Screen | 7-Day Athletic Splits Breakdown | Day-by-day split bars (D1–D7) showing actual verified steps, daily split pace, and +/- pacing delta | Verified daily step snapshots, target cadence | Visual split bars with tabular +/- deltas | Shows "Didn't count" or problem caption if step data incomplete | `ORIGINAL_REQUEST.md` R2, `PersonalPaceComponents.swift` |
| 3 | Today Screen | Dynamic Pace Recalibration | Calculates exact daily step volume required over remaining days to protect commitment | Remaining target steps, remaining days | Required daily pace count | Displays "0 steps to go" if goal reached | `ORIGINAL_REQUEST.md` R2, `PersonalPaceComponents.swift` |
| 4 | Today & Detail | Stakes & Sync Status HUD | High-density indicator for financial stake ($10–$50 locked) and Apple Health sync status | Active challenge terms, sync timestamp | Status string: "Updated from Apple Health 3 min ago" | "Apple Health is temporarily unavailable. Your last update is still here." | `docs/COPY.md`, `TodayView.swift`, `PersonalAccountabilityComponents.swift` |
| 5 | Challenge History | Proof-of-Work Ledger | Tabular list of past and current challenges using flat 1px hairline row separators | Historical challenge array from `PersonalAccountabilityStore` | Flat list with verified Apple Health snapshots | Displays empty state "No challenges yet" when list is empty | `ORIGINAL_REQUEST.md` R3, `ChallengesView.swift` |
| 6 | Challenge History | Settlement Status Badges | Flat status badges indicating challenge settlement outcome | Challenge outcome kind (`metGoal`, `missedGoal`, `inconclusive`) | Status badge: "Settled", "Completed", "At Risk", "Goal met", "Goal missed", "Didn't count" | Highlights provisional miss with "Goal missed — review open. Settlement is paused." | `docs/COPY.md`, `ChallengesView.swift`, `PersonalAccountabilityComponents.swift` |
| 7 | Creation Flow | Athletic Commitment Builder | High-efficiency step-by-step target selection, cadence, and test stake ($10–$50) selection | User inputs (step count, cadence, stake amount) | Validated `PersonalChallengeDraft` | Displays inline target error ("Pick any whole number from 1 to 1,000,000") | `ORIGINAL_REQUEST.md` R4, `PersonalChallengeFlow.swift` |
| 8 | Creation Flow | Stripe Sandbox Consent & Payment Setup | Collects payment method authorization under Stripe sandbox terms | Payment sheet selection, consent toggle | Authorized payment setup ID & saved draft | "Test payment needs your attention. We won't try again automatically." | `docs/COPY.md`, `PersonalChallengeFlow.swift` |
| 9 | Challenge Detail | Dispute Review Flow | Enables requesting a review for a missed goal within a 7-day window | Review reason selection (`userDisputesStepData`, `userDisputesResult`) | Review request record | "The review request window ended." if past deadline | `docs/COPY.md`, `PersonalChallengeDetailView.swift` |
| 10 | Challenge Detail | Active Sandbox Cancellation | Allows immediate cancellation of a test challenge before or during active run | User tap on cancel button | Cancelled challenge state | Preserves historical record; saved test payment method not charged | `docs/COPY.md`, `PersonalChallengeDetailView.swift` |

---

## 4. Edge Cases

## Edge Cases
| # | Feature | Input | Observed Behavior |
|---|---------|-------|-------------------|
| 1 | Health Sync HUD | Apple Health data unavailable / permission revoked | Displays `"Apple Health is temporarily unavailable. Your last update is still here."` with retry button `"Try Again"`. |
| 2 | Step Snapshot | Incomplete or corrupted day step data | Displays `"No step data available yet."` and does not penalize user (`"Missing or unclear step data never counts as a miss."`). |
| 3 | Creation Flow | User attempts to start challenge with past start hour | Shows stale start warning `"That start time has already passed. Go back and pick a new one, or delete this draft."` |
| 4 | Dispute Review | Review window (7 days) expired | Replaces review buttons with static text `"The review request window ended."` |
| 5 | Pending Draft Recovery | Corrupted or unreadable saved draft on phone | Shows recovery card `"Saved setup needs attention. GameTime couldn’t safely open the setup saved on this phone."` with retry button. |
| 6 | Account Deletion | Network error during account deletion re-authentication | Presents inline failure block `"Deletion didn’t finish. Account deletion is temporarily unavailable. Try again in a moment or contact support."` |

---

## 5. Caveats
- Specification mining is based strictly on `docs/COPY.md`, `ORIGINAL_REQUEST.md`, and existing codebase documentation/tests. No production code changes were executed during this analysis.
- UI test assertions in `GameTimeUITests.swift` validate exact strings (e.g. environment disclosures, consent sentences, accessibility labels). Any string modifications made during theme replacement must update corresponding test assertions in lockstep.

---

## 6. Conclusion
The GameTime codebase possesses a strict, well-documented copy specification in `docs/COPY.md` and UI test constraints in `GameTimeUITests.swift`. The upcoming design transition from the Daybreak aesthetic to the Strava-inspired athletic design language must eliminate warm paper themes (`CompetitiveTrustTheme`), pastel pills, floating bento cards, and Daybreak component names, while preserving every exact payment consent string, environment disclosure, domain term mapping, and forbidden word constraint.

---

## 7. Verification Method

To independently verify these specification rules and constraints:
1. **Inspect Copy Spec File**:
   ```bash
   view_file /Users/user/Documents/GitHub/GameTime/docs/COPY.md
   ```
2. **Run UI Test Suite for Copy Compliance**:
   ```bash
   xcodebuild -scheme GameTime -destination 'generic/platform=iOS' test -only-testing:GameTimeUITests
   ```
3. **Verify Forbidden Language Assertion**:
   Inspect `assertNoForbiddenLanguage` in `ios/GameTime/GameTimeUITests/GameTimeUITests.swift:2069`.
