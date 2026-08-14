# Theme Engine & Design System Investigation Report

## 1. Observation

### File & Codebase Survey
A comprehensive analysis was conducted on the GameTime iOS app codebase located in `ios/GameTime/GameTime/`. The following key files define and use the theme system:

1. **`CompetitiveTrustTheme.swift`** (`ios/GameTime/GameTime/CompetitiveTrustTheme.swift`):
   - Defines `CompetitiveTrustTheme` palette tokens:
     - Warm Paper Background: `paper` (`RGB(1.00, 0.969, 0.941)` / `#FFF7F0`), `paperSunk` (`RGB(0.969, 0.925, 0.886)` / `#F7ECE2`).
     - Card & Ink: `card` (`#FFFFFF`), `primaryText` (`RGB(0.110, 0.082, 0.137)` / `#1C1523`), `secondaryText` (`RGB(0.431, 0.392, 0.471)` / `#6E6478`), `tertiaryText` (`RGB(0.365, 0.322, 0.404)` / `#5D5267`), `disabledText` (`RGB(0.655, 0.616, 0.686)` / `#A79DAF`), `inverseSecondaryText` (`RGB(0.880, 0.840, 0.910)` / `#E0D6E8`).
     - Borders & Guide Lines: `border` (`RGB(0.949, 0.902, 0.855)` / `#F2E6DA`), `strongBorder` (`RGB(0.894, 0.827, 0.769)` / `#E4D3C4`), `rail` (`RGB(0.945, 0.922, 0.965)` / `#F1EBFA`), `guide` (`RGB(0.788, 0.749, 0.820)` / `#C9BFD1`).
     - Accent Colors: `coral` (`RGB(1.00, 0.353, 0.271)` / `#FF5A45`), `coralPressed`, `coralInk`, `coralTint` (`#FFEFEF`), `coralTintStrong`, `actionCoral`; `sun` (`RGB(1.00, 0.714, 0.153)` / `#FFB627`), `sunInk`, `sunTint` (`#FFEECC`); `mint` (`RGB(0.071, 0.753, 0.541)` / `#12C08A`), `mintInk`.
     - Multi-Participant Ramp: `participantRamp` containing 7 pastel hues.
   - Fonts:
     - `displayFont`: Custom font `"BricolageGrotesque-96ptExtraBold"`.
     - `uiFont`: Custom font `"HankenGrotesk-Regular"`.
   - Modifiers & View Extensions:
     - `TrustCardModifier` / `trustCard()` (lines 188–211): Floating bento box with `cornerRadius: 24`, continuous rounded rectangle, 1px `border` stroke, and drop shadow `shadow(color: primaryText.opacity(0.05), radius: 7, y: 3)`.
     - `trustScreenBackground()` (line 213): Hidden scroll content background with `paper` fill.
     - `daybreakScreenChrome()` (lines 218–227): Forces `.preferredColorScheme(.light)` and `paper` background/toolbar.
     - `daybreakTabScrollClearance()` (line 230): `.contentMargins(.bottom, 88, for: .scrollContent)`.
   - Button Styles & Pills:
     - `TrustPrimaryButtonStyle`, `TrustSecondaryButtonStyle`, `SunPillButtonStyle`, `TrustCompactButtonStyle`: All enforce `Capsule()` geometry with soft pastel background fills (`coralTint`, `sun`, `actionCoral`).
     - `TrustStatusPill`: Capsule pill with soft background tints (mint 12% opacity, coral tint, sun tint, primaryText 6% opacity).
   - Global Navigation & Tab Bar Appearance:
     - `DaybreakAppearance.install()` (lines 112–179): Installs `UINavigationBar` and `UITabBar` appearances with opaque `paper` backgrounds, light navigation title descriptors (`.rounded`), and `actionCoral` tint.

2. **Hardcoded Forced Light Mode Locations**:
   - `AppShellView.swift` (line 72): `.preferredColorScheme(.light)`.
   - `GameTimeApp.swift` (lines 240, 476, 564, 729): `.preferredColorScheme(.light)`.
   - `LaunchingView.swift` (line 43): `.preferredColorScheme(.light)`.
   - `CompetitiveTrustTheme.swift` (line 220): `.preferredColorScheme(.light)`.
   - Plist files: `ios/GameTime/Configuration/AppInfo.plist` (line 72) & `StagingAppInfo.plist` (line 72) contain `<key>UIUserInterfaceStyle</key><string>Light</string>`.

3. **Existing Tests & Verification Tools**:
   - `DomainAndConfigurationTests.swift` (`ios/GameTime/GameTimeTests/DomainAndConfigurationTests.swift`):
     - Line 8: `testEveryProductConfigurationForcesLightAppearance()` verifies `UIUserInterfaceStyle == "Light"` in plist files.
     - Line 36: `testDaybreakTextRolesMeetNormalTextContrast()` tests `CompetitiveTrustTheme` color contrast ratios (>= 4.5:1) against `paper`, `card`, `paperSunk`, `coralTint`, and `sunTint` surfaces.
   - `GameTimeUITests` (`ios/GameTime/GameTimeUITests/GameTimeUITests.swift`):
     - Asserts on specific accessibility identifiers such as `personal.create`, `personal.details`, `personal.pace.day.0`, `personal.pace.week-total`, `personal.environment-disclosure`, `tab.today`, `tab.challenges`, `tab.you`.

4. **Component Usage Map**:
   - `AppShellView.swift`: `.tint(CompetitiveTrustTheme.actionCoral)`, `.toolbarBackground(CompetitiveTrustTheme.paper, for: .tabBar)`.
   - `TodayView.swift`: `DaybreakCard`, `DaybreakSectionLabel`, `PersonalProgressBar`, `PersonalSevenDayTimeline`, `daybreakTabScrollClearance()`, `daybreakScreenChrome()`, `displayFont`, `uiFont`.
   - `ChallengesView.swift`: `DaybreakSectionLabel`, `PersonalChallengeCard`, `DaybreakCard`, `DaybreakCard(tone: .pledge)`, `TrustStatusPill`, `TrustPrimaryButtonStyle`, `TrustSecondaryButtonStyle`.
   - `PersonalChallengeDetailView.swift`: `DaybreakCard`, `PersonalStatusPill`, `PersonalPaceCard`, `PersonalChallengeDetailsCard`, `daybreakTabScrollClearance()`, `daybreakScreenChrome()`.
   - `PersonalChallengeFlow.swift`: `DaybreakCard`, `EnvironmentDisclosureBanner`, `DaybreakAccessibility`, `daybreakScreenChrome()`, `TrustPrimaryButtonStyle`, `TrustSecondaryButtonStyle`, `TrustCompactButtonStyle`.
   - `YouView.swift`: `DaybreakCard`, `DaybreakSectionLabel`, `InitialsAvatar`, `TrustSecondaryButtonStyle`, `daybreakTabScrollClearance()`, `daybreakScreenChrome()`.
   - `ChallengeVisualComponents.swift`: `DaybreakSectionLabel`, `DaybreakCard`, `ChallengeField`, `ChallengeCountdown`, `ChallengeStatTile`, `ChallengeRosterChip`.
   - `FeatureComponents.swift`: `FriendshipCardRow`, `ContestCardRow`, `InlineLoadStateView`.
   - `PersonalAccountabilityComponents.swift`: `PersonalChallengeCard`, `PersonalStatusPill`, `PersonalProgressBar`, `PersonalHealthProgressStatus`, `EmptyTrustState`, `PendingPersonalCancellationRecoveryCard`.
   - `PersonalPaceComponents.swift`: `PersonalPaceCard`, `PersonalPaceTiles`, `PersonalChallengeDetailsCard`, `PaceGuideLine`.

---

## 2. Logic Chain

1. **Identification of Legacy Anti-Patterns**:
   - Observations show that `CompetitiveTrustTheme.swift` implements the warm paper "Daybreak" aesthetic using cream paper backgrounds (`#FFF7F0`), pastel accent tints (`coralTint`, `sunTint`), custom decorative fonts (`BricolageGrotesque`, `HankenGrotesk`), floating bento cards (`TrustCardModifier` / `DaybreakCard` with drop shadows and 24pt corner radius), over-rounded capsule buttons/pills, and forced Light Mode.
   - These directly conflict with the R1 requirement of a high-utility, Strava-dominant athletic design language with pure dark/graphite surfaces (`#000000`/`#121212`), high-contrast light mode support, high-visibility accents, tabular numbers, and zero AI-slop anti-patterns (no pastel gradients, no floating bento boxes, no glowing cards, no bubble pills).

2. **R1 Strava-Style Athletic Foundation Specification**:
   - **Adaptive Pure Dark / Graphite Foundation**:
     - Dark Mode (primary): `#000000` / `#121212` background, elevated dark neutral cards (`#1C1C1E` / `#2C2C2E`).
     - Light Mode (adaptive secondary): Clean high-contrast neutral light surfaces (`#FFFFFF` / `#F2F2F7`), eliminating warm cream paper (`#FFF7F0`).
     - Remove all forced `.preferredColorScheme(.light)` calls across `GameTimeApp.swift`, `AppShellView.swift`, `LaunchingView.swift`, and `CompetitiveTrustTheme.swift`.
     - Update `UIUserInterfaceStyle` in `AppInfo.plist` and `StagingAppInfo.plist` from `Light` to `Automatic` (or remove restriction).
   - **Signature High-Visibility Athletic Palette**:
     - Strava Signal Orange: `#FC5200` (`RGB(1.0, 0.322, 0.0)`), replacing warm coral (`#FF5A45`) for primary interactive actions and highlights.
     - Athletic Green: `#00D084` (`RGB(0.0, 0.816, 0.518)`), replacing mint (`#12C08A`) for target achievement, positive progress, and verified states.
     - Sharp Neutral Dividers: Hairline flat dividers `#2C2C2E` (dark mode) / `#E5E5EA` (light mode), replacing warm paper borders (`#F2E6DA`).
   - **Bold Athletic Typography & Tabular Numbers**:
     - Adopt SF Pro Display for headers and structural labels.
     - Enforce SF Mono / `.monospacedDigit()` for all numeric values (step metrics, 7-day split totals, pacing deltas `+/-`, financial stakes `$10–$50`, timers) so numbers align in tabular columns.
     - Replace playful fonts (`BricolageGrotesque`, `HankenGrotesk`) with system athletic typography.
   - **Card & Button Architecture Overhaul**:
     - Replace 24pt rounded bento cards and drop shadows with flat, high-density athletic surfaces (e.g. 8–12pt corner radius, hairline 1px borders, zero drop shadows).
     - Replace over-rounded `Capsule()` buttons and pastel pills (`TrustStatusPill`, `SunPillButtonStyle`) with sharp, high-contrast rectangular or slightly rounded athletic buttons and flat badge indicators.

3. **Impact on Testing & Verification**:
   - `DomainAndConfigurationTests.swift` contains `testEveryProductConfigurationForcesLightAppearance` and `testDaybreakTextRolesMeetNormalTextContrast`. With R1, `testEveryProductConfigurationForcesLightAppearance` must be updated or replaced to verify adaptive appearance (or dark appearance default), and color contrast tests must verify accessibility (>= 4.5:1 ratio) for Signal Orange (`#FC5200`), Athletic Green (`#00D084`), pure dark `#000000`/`#121212`, and light mode neutral surfaces.
   - Accessibility identifiers in `GameTimeUITests` must be strictly preserved on all replaced/redesigned components (`personal.create`, `personal.details`, `personal.pace.day.0`, `personal.environment-disclosure`, `tab.today`, `tab.challenges`, `tab.you`, etc.).

---

## 3. Caveats

- **No Caveats**: The codebase was fully inspected across all theme files, view controllers, plists, unit tests, and UI tests.

---

## 4. Conclusion

1. `CompetitiveTrustTheme.swift` currently locks the app into the legacy "Daybreak" aesthetic with warm paper backgrounds (`#FFF7F0`), pastel tints, playful non-tabular custom fonts (`BricolageGrotesque`, `HankenGrotesk`), floating bento cards with drop shadows, bubble capsule buttons, and forced Light Mode (`UIUserInterfaceStyle = Light`).
2. Redesigning to R1 requires replacing `CompetitiveTrustTheme.swift` with an adaptive Strava-inspired Athletic Design System featuring pure dark/graphite (`#000000`/`#121212`), high-contrast light mode, Signal Orange (`#FC5200`), Athletic Green (`#00D084`), neutral dividers (`#2C2C2E`), SF Pro Display / SF Mono tabular numbers, and flat high-density card surfaces without drop shadows or pastel pills.
3. Every component (`TodayView`, `ChallengesView`, `PersonalChallengeDetailView`, `CreatePersonalChallengeFlow`, `YouView`, `ChallengeVisualComponents`, `PersonalPaceComponents`, `PersonalAccountabilityComponents`, `FeatureComponents`) must migrate to the new theme tokens while preserving all existing accessibility identifiers and `docs/COPY.md` vocabulary contracts.
4. Test suites (`DomainAndConfigurationTests.swift` and `GameTimeUITests`) must be updated to align with the adaptive dark/light appearance and color contrast checks.

---

## 5. Verification Method

### Test Execution Commands
- **Xcode Build Command**:
  ```bash
  xcodebuild -scheme GameTime -destination 'generic/platform=iOS' build
  ```
- **Unit Test Command**:
  ```bash
  xcodebuild test -scheme GameTime -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:GameTimeTests
  ```
- **UI Test Command**:
  ```bash
  xcodebuild test -scheme GameTime -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:GameTimeUITests
  ```

### Inspection Verification
- Inspect `CompetitiveTrustTheme.swift` to verify theme tokens (`#000000`, `#121212`, `#FC5200`, `#00D084`, `#2C2C2E`) and removal of drop shadows, pastel pills, and forced `.preferredColorScheme(.light)`.
- Inspect `AppInfo.plist` & `StagingAppInfo.plist` to confirm `UIUserInterfaceStyle` updated for dark/adaptive support.
- Inspect `DomainAndConfigurationTests.swift` to ensure color contrast tests verify R1 tokens against pure dark and light surfaces.

### Invalidation Conditions
- Any occurrence of soft pastel gradients, glowing card drop shadows (`shadow(color: ...)`), playful custom fonts (`BricolageGrotesque`), or forced light mode scheme overrides.
- Any failure in `xcodebuild build` or `xcodebuild test`.
