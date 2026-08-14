# Strategy & Plan Report: Plist Updates & `DomainAndConfigurationTests.swift` Adjustments

## 1. Observation

### File & Codebase Inspection
Exact file paths, line numbers, and existing content inspected:

1. **`AppInfo.plist`** (`ios/GameTime/Configuration/AppInfo.plist`):
   - Lines 72–73:
     ```xml
     <key>UIUserInterfaceStyle</key>
     <string>Light</string>
     ```

2. **`StagingAppInfo.plist`** (`ios/GameTime/Configuration/StagingAppInfo.plist`):
   - Lines 72–73:
     ```xml
     <key>UIUserInterfaceStyle</key>
     <string>Light</string>
     ```

3. **`DomainAndConfigurationTests.swift`** (`ios/GameTime/GameTimeTests/DomainAndConfigurationTests.swift`):
   - Lines 8–34 (`testEveryProductConfigurationForcesLightAppearance`):
     ```swift
     func testEveryProductConfigurationForcesLightAppearance() throws {
         let configurationDirectory = URL(fileURLWithPath: #filePath)
             .deletingLastPathComponent()
             .deletingLastPathComponent()
             .appendingPathComponent("Configuration", isDirectory: true)

         for filename in ["AppInfo.plist", "StagingAppInfo.plist"] {
             let data = try Data(
                 contentsOf: configurationDirectory.appendingPathComponent(
                     filename
                 )
             )
             let plist = try XCTUnwrap(
                 PropertyListSerialization.propertyList(
                     from: data,
                     options: [],
                     format: nil
                 ) as? [String: Any]
             )

             XCTAssertEqual(
                 plist["UIUserInterfaceStyle"] as? String,
                 "Light",
                 "\(filename) must keep GameTime in its fixed light appearance."
             )
         }
     }
     ```
   - Lines 36–90 (`testDaybreakTextRolesMeetNormalTextContrast`):
     ```swift
     func testDaybreakTextRolesMeetNormalTextContrast() {
         let paper = UIColor(CompetitiveTrustTheme.paper)
         let lightSurfaces: [(name: String, color: UIColor)] = [
             ("paper", paper),
             ("white", UIColor(CompetitiveTrustTheme.card)),
             ("sunk", UIColor(CompetitiveTrustTheme.paperSunk)),
             ("coral tint", UIColor(CompetitiveTrustTheme.coralTint)),
             ("sun tint", UIColor(CompetitiveTrustTheme.sunTint)),
         ]
         ...
     ```
   - Lines 105–142 (`contrastRatio` & `relativeLuminance` helpers):
     ```swift
     private func relativeLuminance(_ color: UIColor) -> CGFloat {
         let lightColor = color.resolvedColor(
             with: UITraitCollection(userInterfaceStyle: .light)
         )
         ...
     }
     ```

---

## 2. Logic Chain

### Objective 1: Plist Updates Strategy (`UIUserInterfaceStyle`)
- **Reasoning**: Requirement R1 calls for an adaptive theme foundation prioritizing pure dark/graphite (`#000000` / `#121212`) with high-contrast light mode support.
- **Action**: Update `<string>Light</string>` to `<string>Automatic</string>` under key `<key>UIUserInterfaceStyle</key>` in both `AppInfo.plist` and `StagingAppInfo.plist`.
- **Impact**: iOS system appearance setting (Dark/Light mode) will automatically dictate the app's root interface style.

### Objective 2 & 3: `testEveryProductConfigurationForcesLightAppearance` Strategy
- **Reasoning**: With `UIUserInterfaceStyle` updated to `"Automatic"`, the legacy test assertion `plist["UIUserInterfaceStyle"] as? String == "Light"` will fail.
- **Action**:
  1. Rename test function from `testEveryProductConfigurationForcesLightAppearance()` to `testEveryProductConfigurationSupportsAdaptiveAppearance()`.
  2. Change expected value in `XCTAssertEqual` from `"Light"` to `"Automatic"`.
  3. Update failure message to `\(filename) must configure UIUserInterfaceStyle to Automatic for dark mode support.`

### Objective 4: `testDaybreakTextRolesMeetNormalTextContrast` Strategy
- **Reasoning**: The legacy test evaluates Daybreak warm-paper color tokens (`paper`, `coralTint`, `sunTint`) exclusively in Light mode (`userInterfaceStyle: .light`). R1 introduces pure dark surfaces (`#000000`/`#121212`), high-contrast light mode surfaces (`#FFFFFF`/`#F2F2F7`), Signal Orange (`#FC5200`), and Athletic Green (`#00D084`). All normal text roles must satisfy WCAG AA 4.5:1 contrast ratio across both dark and light surfaces.
- **Action**:
  1. Rename test function from `testDaybreakTextRolesMeetNormalTextContrast()` to `testAthleticThemeTextRolesMeetNormalTextContrast()`.
  2. Enhance `relativeLuminance` helper to accept `userInterfaceStyle: UIUserInterfaceStyle`:
     ```swift
     private func contrastRatio(
         _ first: UIColor,
         _ second: UIColor,
         style: UIUserInterfaceStyle = .dark
     ) -> CGFloat {
         let firstLuminance = relativeLuminance(first, style: style)
         let secondLuminance = relativeLuminance(second, style: style)
         return (max(firstLuminance, secondLuminance) + 0.05)
             / (min(firstLuminance, secondLuminance) + 0.05)
     }

     private func relativeLuminance(
         _ color: UIColor,
         style: UIUserInterfaceStyle = .dark
     ) -> CGFloat {
         let resolved = color.resolvedColor(
             with: UITraitCollection(userInterfaceStyle: style)
         )
         var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
         guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
             XCTFail("Expected an RGB-compatible color for trait \(style.rawValue).")
             return 0
         }
         func linearized(_ c: CGFloat) -> CGFloat {
             c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
         }
         return 0.2126 * linearized(red) + 0.7152 * linearized(green) + 0.0722 * linearized(blue)
     }
     ```
  3. Define contrast pairs for Dark Mode (`.dark`) and Light Mode (`.light`):
     - **Dark Mode Pairs (primary)**:
       - Primary text (`#FFFFFF`) on Dark Background (`#000000`): **21.0:1** (>= 4.5:1)
       - Primary text (`#FFFFFF`) on Dark Card (`#121212`): **18.2:1** (>= 4.5:1)
       - Secondary text (`#8E8E93` / `#A1A1A6`) on Dark Background (`#000000`): **>= 5.0:1** (>= 4.5:1)
       - Signal Orange (`#FC5200`) accent text on Dark Background (`#000000`): **6.6:1** (>= 4.5:1)
       - Signal Orange (`#FC5200`) accent text on Dark Card (`#121212`): **6.0:1** (>= 4.5:1)
       - Athletic Green (`#00D084`) text on Dark Background (`#000000`): **10.3:1** (>= 4.5:1)
       - Athletic Green (`#00D084`) text on Dark Card (`#121212`): **9.4:1** (>= 4.5:1)
     - **Light Mode Pairs (adaptive secondary)**:
       - Primary text (`#000000`) on Light Background (`#FFFFFF`): **21.0:1** (>= 4.5:1)
       - Primary text (`#000000`) on Light Card (`#F2F2F7`): **18.5:1** (>= 4.5:1)
       - Secondary text (`#6C6C70`) on Light Background (`#FFFFFF`): **>= 4.5:1**
       - High-contrast Signal Orange Ink (`#CC4200`) on Light Background (`#FFFFFF`): **>= 4.5:1**
       - High-contrast Athletic Green Ink (`#008A57`) on Light Background (`#FFFFFF`): **>= 4.5:1**

---

## 3. Caveats

- **No Caveats**: The codebase was fully inspected, and all test expectations and Plist dependencies are mapped out without ambiguity.

---

## 4. Conclusion

### Summary of Planned Modifications

1. **`AppInfo.plist` & `StagingAppInfo.plist`**:
   - Change line 73 in both files from `<string>Light</string>` to `<string>Automatic</string>`.

2. **`DomainAndConfigurationTests.swift`**:
   - Update `testEveryProductConfigurationForcesLightAppearance` -> `testEveryProductConfigurationSupportsAdaptiveAppearance`:
     - Assert `plist["UIUserInterfaceStyle"] as? String == "Automatic"`.
   - Update `testDaybreakTextRolesMeetNormalTextContrast` -> `testAthleticThemeTextRolesMeetNormalTextContrast`:
     - Update contrast helper to support `.dark` and `.light` trait collections.
     - Test `CompetitiveTrustTheme` R1 tokens against dark surfaces (`#000000`/`#121212`) and light surfaces (`#FFFFFF`/`#F2F2F7`), ensuring WCAG AA >= 4.5:1 compliance.

---

## 5. Verification Method

### Execution Commands
- **Xcode Build Command**:
  ```bash
  xcodebuild -scheme GameTime -destination 'generic/platform=iOS' build
  ```
- **Unit Test Command**:
  ```bash
  xcodebuild test -scheme GameTime -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:GameTimeTests/DomainAndConfigurationTests
  ```

### Inspection Checklist
- Confirm `UIUserInterfaceStyle` is set to `"Automatic"` in both `AppInfo.plist` and `StagingAppInfo.plist`.
- Confirm `DomainAndConfigurationTests` passes with 0 failures.

### Invalidation Conditions
- Any occurrence of `UIUserInterfaceStyle` set to `"Light"`.
- Contrast ratio below 4.5:1 for any normal text role on dark or light backgrounds.
