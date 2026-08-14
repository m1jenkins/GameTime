# Handoff Report: Milestone M4 (Challenge Creation Flow Overhaul)

## 1. Observation

Direct observations from analysis of `ios/GameTime/GameTime/PersonalChallengeFlow.swift`, `CompetitiveTrustTheme.swift`, `ChallengeVisualComponents.swift`, `PersonalAccountabilityModels.swift`, `docs/COPY.md`, `ORIGINAL_REQUEST.md`, `PROJECT.md`, and `GameTimeUITests.swift`:

### Current Implementation & Structure (`PersonalChallengeFlow.swift`)
- **Main View Entry Point**: `struct CreatePersonalChallengeFlow: View` (Lines 4–1299).
- **Environment & State Bindings**:
  - `@Environment(PersonalAccountabilityStore.self) private var store` (Line 5)
  - `@Environment(AppModel.self) private var appModel` (Line 6)
  - `@Environment(AppRouter.self) private var router` (Line 7)
  - `@Environment(\.dismiss) private var dismiss` (Line 8)
  - `@Environment(\.demoMode) private var demoMode` (Line 9)
  - `@Environment(\.accessibilityReduceMotion) private var reduceMotion` (Line 10)
  - `@Environment(\.dynamicTypeSize) private var dynamicTypeSize` (Line 11)
  - State: `draft: PersonalChallengeDraft`, `requestID: UUID`, `step: Step`, `paymentConsentAccepted: Bool`, `paymentSheet: PaymentSheet?`, `paymentSheetSetupID: String?`, `startsImmediately: Bool`, `now: Date`, etc.
- **Flow Navigation Steps (`Step: Int, CaseIterable`)**:
  - `.metric`: Line 43 ("What you’ll track", hidden in `visibleSteps`)
  - `.cadence`: Line 44 ("How it counts")
  - `.target`: Line 45 ("Your goal")
  - `.commitment`: Line 46 ("Your amount")
  - `.start`: Line 47 ("When you start", hidden in `visibleSteps` unless startNow or detail)
  - `.healthAccess`: Line 48 ("Apple Health")
  - `.payment`: Line 49 ("Test payment", shown only if `personalSettlementMode == .stripeSandbox`)
  - `.review`: Line 50 ("Check and confirm")
- **Legacy Visual Patterns Currently Used**:
  - `DaybreakCard` container (Lines 76–78): uses 7pt shadow (`radius: 7, y: 3`), rounded corners, soft card background.
  - Step progress indicator (Lines 194–210): `Capsule()` views with height 6 and soft coral/rail colors.
  - Cadence choices (Lines 237–263): Uses `choice(icon:title:detail:selected:)` with rounded SF Symbols (`figure.walk`, `calendar.day.timeline.left`, `sum`).
  - Target step volume input (Lines 264–293): `TextField("Step goal", ...)` wrapped in `.background(CompetitiveTrustTheme.paperSunk, in: RoundedRectangle(cornerRadius: 16))`.
  - Commitment stake choices (Lines 294–328, 340–371): `commitmentAmountChoice` rendering `LazyVGrid` or `VStack` of buttons with `RoundedRectangle(cornerRadius: 14)` backgrounds.
  - Navigation controls (Lines 823–921): `TrustPrimaryButtonStyle` (`RoundedRectangle(cornerRadius: 8)` with `signalOrange` background, black text) and `TrustCompactButtonStyle`.
- **Accessibility Identifiers in `PersonalChallengeFlow.swift`**:
  - `personal.cadence.daily` / `personal.cadence.cumulative` (Line 256)
  - `personal.target` (Line 288) & `personal.target.done` (Line 97)
  - `personal.commitment.1000` through `personal.commitment.5000` (Line 365)
  - `personal.commitment.protection` (Line 327)
  - `personal.start.day` (Line 392), `personal.start.hour` (Line 400), `personal.start.tomorrow` (Line 411), `personal.start.next-hour` (Line 423), `personal.start.consequence` (Line 435), `personal.start.now` (Line 816)
  - `personal.health.verify` (Line 559)
  - `personal.payment.consent` (Line 627) & `personal.payment.setup` (Line 880)
  - `personal.receipt` (Line 652)
  - `personal.receipt.group.\(group.id.rawValue)` (Line 700)
  - `personal.receipt.fact.\(fact.id.rawValue)` (Line 741)
  - `personal.receipt.more-details` (Line 767)
  - `personal.receipt.detail.\(detail.id.rawValue)` (Line 804)
  - `personal.review.stale-start` (Line 676)
  - `personal.submit` (Line 847)
  - `personal.continue` (Line 855 / Line 888)
  - `personal.back` (Line 898)
  - `personal.pending.discard-review` (Line 913)
  - `personal.environment-disclosure` (Line 71 & 660)

### Design & Vocabulary Specifications (`ORIGINAL_REQUEST.md`, `COPY.md`, `CompetitiveTrustTheme.swift`)
- **Theme Foundation (`CompetitiveTrustTheme.swift`)**:
  - `darkBackground`: `#000000`
  - `graphiteSurface`: `#121212`
  - `card`: `#121212` (dark) / `#FFFFFF` (light)
  - `hairlineDivider`: `#2C2C2E` (dark) / `#E5E5EA` (light)
  - `signalOrange`: `#FC5200`
  - `athleticGreen`: `#00D084`
  - `tabularFont(size:weight:)`: SF Pro Display / SF Mono with `.monospacedDigit()`
- **Anti-Slop Guidelines (`ORIGINAL_REQUEST.md` R4)**:
  - Eliminate warm-paper onboarding slides, rounded bento cards, soft pills, and fake loading animations.
  - Deliver a high-efficiency athletic commitment builder: Target step volume selection, 7-day cadence selection (daily vs cumulative), test commitment stake selection ($10–$50 locked) presented in a tactile segmented layout.
  - Use dark graphite surfaces (`#121212`) with 1px hairline dividers (`#2C2C2E`).
  - Monospaced tabular typography for steps, stakes, and dates.
- **Copy Rules (`docs/COPY.md`)**:
  - Environment banner: "Payment test mode — no real money moves." (sandbox) / "Test commitment — no money will be charged." (test-only)
  - Payment consent text: "By starting, you agree that GameTime may create one \(amount) test charge only if this challenge is confirmed missed after the review window. Missing or unclear step data never counts as a miss."
  - Zero forbidden terms (no *friend*, *invitation*, *standings*, *winner*, *charity*, *tie-break*, *snapshot*, *frozen terms*, *cadence* shown on user-facing text).

---

## 2. Logic Chain

1. **Analysis of Current Flow vs Requirement R4**:
   - `PersonalChallengeFlow.swift` contains complete underlying state management and store bindings for challenge creation (draft validation, Stripe PaymentSheet setup, HealthKit permission checks, pending submission recovery).
   - However, the visual presentation relies on legacy `DaybreakCard` styling with soft shadows, paper-sunk text field containers with 16pt corner radius, pill progress indicators, and standard system font choices for step targets and stakes.
   - Requirement R4 demands replacing these soft, warm-paper Daybreak elements with high-utility, Strava-dominant athletic components: dark graphite `#121212` cards with 1px `#2C2C2E` hairline dividers, tactile segmented stake selectors, monospaced tabular typography, and high-density step volume inputs.

2. **Tactile Segmented Layout for Stakes ($10–$50)**:
   - `PersonalChallengeDraft.allowedCommitmentAmountsMinor` contains `[1_000, 2_000, 3_000, 4_000, 5_000]`.
   - Currently, `commitmentAmountChoice` renders individual `LazyVGrid` buttons with 14pt rounded corners and action coral background.
   - To build a Strava-style tactile segmented layout:
     - Group all 5 stake options ($10, $20, $30, $40, $50) inside a single dark graphite container (`#121212`) bounded by a 1px `#2C2C2E` border with 4pt corner radius.
     - Divide the options with 1px vertical hairline dividers (`#2C2C2E`).
     - Highlight the selected segment with Strava Signal Orange (`#FC5200`) background or border accent and crisp monospaced tabular text (`CompetitiveTrustTheme.tabularFont(size: 16, weight: .bold)`).
     - Each segment button retains its accessibility identifier `personal.commitment.\(amount)` and accessibility value `Selected` / `Not selected`.

3. **High-Efficiency Target Step Volume Selector**:
   - The target step volume selection step (`.target`) requires tabular monospaced digits for step count display.
   - Replace `paperSunk` container with a dark graphite box (`#121212`), 1px `#2C2C2E` border, 4pt corner radius.
   - Set the step goal font to `CompetitiveTrustTheme.tabularFont(size: 36, weight: .bold)` or `CompetitiveTrustTheme.displayFont`.
   - Provide direct quick-preset buttons (e.g. Daily: 7,000, 10,000, 12,500 steps; Cumulative: 50,000, 70,000, 100,000 steps) formatted in high-contrast athletic style to allow 1-tap goal adjustment.
   - Maintain text field accessibility identifier `personal.target` and keyboard done button identifier `personal.target.done`.

4. **7-Day Cadence Selection (Daily vs Cumulative)**:
   - Replace soft `choice` rows with high-contrast athletic split cards for `.daily` and `.cumulative`.
   - Each option displays a sharp 1px hairline border (`#2C2C2E`), `#121212` background, active Strava Signal Orange (`#FC5200`) border and icon accent when selected.
   - Text uses bold athletic headline typography ("EVERY DAY" vs "WEEK TOTAL") and concise subheadline explanations.
   - Accessibility identifiers `personal.cadence.daily` and `personal.cadence.cumulative` remain unchanged.

5. **Step Progress Header & Surface Containers**:
   - Replace soft pill progress header (`Capsule()`) with a high-density segment progress bar: sharp rectangular segments with 1px gaps or borders, active steps filled in `#FC5200`, inactive steps in `#2C2C2E`.
   - Replace `DaybreakCard` container in `CreatePersonalChallengeFlow` with an athletic container (`AthleticCard` or `trustCard()`) featuring `#121212` background, 1px `#2C2C2E` hairline border, 4pt corner radius, and zero soft shadows.

6. **Monospaced Tabular Typography Integration**:
   - All numerical values in the flow—step targets (e.g. `10,000`), stake amounts (e.g. `$20`), start dates/times (e.g. `12:00 AM`), review summary facts—use `CompetitiveTrustTheme.tabularFont` to align digits cleanly.

7. **Contract & Interface Compatibility**:
   - All state logic, Store interactions (`PersonalAccountabilityStore`), pending creation recovery (`store.pendingCreation`), Stripe payment sheet flow (`preparePaymentSheet`, `handlePaymentSheetResult`), and submission handling (`submit`) remain fully intact without altering domain models or store contracts.
   - All accessibility identifiers checked by `GameTimeUITests` (e.g. `testCumulativeCreationOmitsFixedMetricAndStartSteps`, `testMainModeCanStartNowAndExposeSyncNow`) must be strictly preserved.

---

## 3. Caveats

- **No Caveats**: All components, store bindings, accessibility identifiers, copy rules, and UI test expectations for `PersonalChallengeFlow.swift` have been completely inspected and verified against the codebase.

---

## 4. Conclusion

The refactoring strategy for `PersonalChallengeFlow.swift` (Milestone M4) is fully planned and ready for implementation. The proposed design removes all warm-paper Daybreak anti-patterns (soft shadows, rounded bento cards, paper-sunk text inputs, soft capsule progress pills) and replaces them with a high-efficiency Strava-dominant athletic commitment builder:

1. **Athletic Dark Surfaces**: Surfaces styled in `#121212` graphite with 1px `#2C2C2E` hairline dividers and 4pt border radius.
2. **Tactile Segmented Stake Selector**: Segmented control layout for $10, $20, $30, $40, $50 stakes with monospaced tabular typography and Strava Signal Orange (`#FC5200`) active state.
3. **High-Density Step Volume Input**: Monospaced tabular digits (`CompetitiveTrustTheme.tabularFont`) for target step count with quick-preset targets.
4. **Athletic Cadence Cards**: Sharp 1px bordered split cards for 7-day Daily vs Cumulative cadence selection.
5. **Strict Accessibility & Store Binding Compatibility**: Preservation of all 20+ `personal.create.*` and `personal.*` accessibility identifiers and full integration with `PersonalAccountabilityStore`.

---

## 5. Proposed Swift Refactoring Blueprint for `PersonalChallengeFlow.swift`

Below is the concrete code blueprint to be implemented in `ios/GameTime/GameTime/PersonalChallengeFlow.swift`:

```swift
// Proposed Refactored Component Snippets for PersonalChallengeFlow.swift

// MARK: - Athletic Progress Header
private var progressHeader: some View {
    HStack(spacing: 4) {
        ForEach(visibleSteps, id: \.rawValue) { item in
            Rectangle()
                .fill(
                    (visibleSteps.firstIndex(of: item) ?? 0)
                        <= (visibleSteps.firstIndex(of: step) ?? 0)
                    ? CompetitiveTrustTheme.signalOrange
                    : CompetitiveTrustTheme.hairlineDivider
                )
                .frame(height: 4)
        }
    }
    .accessibilityLabel(
        "Step \((visibleSteps.firstIndex(of: step) ?? 0) + 1) of \(visibleSteps.count)"
    )
}

// MARK: - Tactile Segmented Commitment Stake Selector
private var commitmentContent: some View {
    VStack(alignment: .leading, spacing: 16) {
        Text("SELECT COMMITMENT STAKE")
            .font(CompetitiveTrustTheme.monoFont(size: 12, weight: .bold))
            .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            .tracking(1.0)
        
        HStack(spacing: 0) {
            ForEach(PersonalChallengeDraft.allowedCommitmentAmountsMinor, id: \.self) { amount in
                Button {
                    draft.commitmentAmountMinor = amount
                } label: {
                    Text((Double(amount) / 100).formatted(.currency(code: "USD")))
                        .font(CompetitiveTrustTheme.tabularFont(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            draft.commitmentAmountMinor == amount
                                ? CompetitiveTrustTheme.signalOrange
                                : CompetitiveTrustTheme.graphiteSurface
                        )
                        .foregroundStyle(
                            draft.commitmentAmountMinor == amount
                                ? Color.black
                                : CompetitiveTrustTheme.primaryText
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("personal.commitment.\(amount)")
                .accessibilityValue(draft.commitmentAmountMinor == amount ? "Selected" : "Not selected")
                
                if amount != PersonalChallengeDraft.allowedCommitmentAmountsMinor.last {
                    Rectangle()
                        .fill(CompetitiveTrustTheme.hairlineDivider)
                        .frame(width: 1)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(CompetitiveTrustTheme.hairlineDivider, lineWidth: 1)
        )
        
        Label(
            commitmentProtection.text,
            systemImage: "checkmark.shield"
        )
        .font(CompetitiveTrustTheme.uiFont(size: 13, relativeTo: .caption, weight: .medium))
        .foregroundStyle(CompetitiveTrustTheme.secondaryText)
        .accessibilityIdentifier("personal.commitment.protection")
    }
}

// MARK: - High-Efficiency Step Goal Target Input
private var targetContent: some View {
    VStack(alignment: .leading, spacing: 16) {
        Text(draft.cadence == .daily ? "TARGET STEP VOLUME / DAY" : "TARGET STEP VOLUME / WEEK")
            .font(CompetitiveTrustTheme.monoFont(size: 12, weight: .bold))
            .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            .tracking(1.0)
        
        HStack {
            TextField("Step goal", value: $draft.targetSteps, format: .number)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .target)
                .font(CompetitiveTrustTheme.tabularFont(size: 36, weight: .bold))
                .foregroundStyle(CompetitiveTrustTheme.primaryText)
                .multilineTextAlignment(.leading)
                .accessibilityIdentifier("personal.target")
            
            Text("steps")
                .font(CompetitiveTrustTheme.monoFont(size: 14, weight: .semibold))
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
        }
        .padding(14)
        .background(CompetitiveTrustTheme.graphiteSurface)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(CompetitiveTrustTheme.hairlineDivider, lineWidth: 1)
        )
        
        // Quick Presets
        HStack(spacing: 8) {
            let presets = draft.cadence == .daily ? [7000, 10000, 12500, 15000] : [50000, 70000, 100000]
            ForEach(presets, id: \.self) { preset in
                Button {
                    draft.targetSteps = preset
                } label: {
                    Text(preset.formatted(.number))
                        .font(CompetitiveTrustTheme.tabularFont(size: 13, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(draft.targetSteps == preset ? CompetitiveTrustTheme.signalOrange.opacity(0.15) : CompetitiveTrustTheme.graphiteSurface)
                        .foregroundStyle(draft.targetSteps == preset ? CompetitiveTrustTheme.signalOrange : CompetitiveTrustTheme.secondaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(draft.targetSteps == preset ? CompetitiveTrustTheme.signalOrange : CompetitiveTrustTheme.hairlineDivider, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

---

## 6. Verification Method

To independently verify the implementation of Milestone M4:

1. **Build Verification**:
   ```bash
   xcodebuild -scheme GameTime -destination 'generic/platform=iOS' build
   ```
2. **Unit Test Verification**:
   ```bash
   xcodebuild -scheme GameTime -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:GameTimeTests/PersonalAccountabilityTests
   ```
3. **UI Test Verification**:
   ```bash
   xcodebuild -scheme GameTime -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:GameTimeUITests/GameTimeUITests/testCumulativeCreationOmitsFixedMetricAndStartSteps
   xcodebuild -scheme GameTime -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:GameTimeUITests/GameTimeUITests/testMainModeCanStartNowAndExposeSyncNow
   ```
4. **Visual & Vocabulary Inspection**:
   - Inspect `PersonalChallengeFlow.swift` to verify zero legacy Daybreak pills, zero soft shadows, 1px `#2C2C2E` dividers, and `#121212` graphite surfaces.
   - Verify zero forbidden terms from `docs/COPY.md`.
