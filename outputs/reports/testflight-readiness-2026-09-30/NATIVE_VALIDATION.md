# Native validation, September 30, 2026

The production app inputs used for this run match
`f1dd690f4db5125b69407e7d8beaf4925e357c0b`. They are unchanged from the
`b16685b` archive's native source. The September 29 full native receipt remains
relevant to those inputs; this run preserves its original results and adds
fresh checks rather than repeating the full accessibility/UI gate.

The checkout contained unrelated design/copy edits and generated material.
This work preserves them. The only tracked native changes prepared by this
task correct two test measurement helpers; they change no app code, appearance,
strings, money behavior, or configuration.

## Environment and isolation

- Xcode 27.0, build `27A5237l`.
- iPhone 17 Pro simulator, iOS 27.0 (`24A5408d`),
  `B3E5DFC7-ED3F-4620-B86A-4F20B2AEAA2A`.
- Derived data, logs, `.xcresult` bundles, exported screenshots and movies are
  under ignored `tmp/testflight-readiness-2026-09-30/native/`.
- Every simulator journey uses the deterministic fictional fixture boundary.
  No interactive demo mode, device Health reads, hosted account, hosted mutation,
  physical install, upload, or tester invitation was performed.
- Only this task controlled the selected simulator.

## Completed checks

| Check | Local result | Evidence under the ignored native directory |
| --- | --- | --- |
| `GameTimeCore` | 187 Swift Testing tests in 20 suites and 3 XCTest cases passed | `core-tests.log` |
| TestFlight candidate source preflight | 23 passed, 0 blockers | `candidate-check.log` |
| Candidate checker regression fixtures | Passed | `candidate-check-fixtures.log` |
| iPhone product guard tests | 15 passed | `product-guard-tests.log` |
| Active iPhone inputs/product guard | Passed for source, Debug, TestFlight and Staging products; HealthKit linked, no Watch payload/link | `source-product-guard.log`, `debug-product-guard.log`, `testflight-product-guard.log`, `staging-product-guard.log` |
| Debug build and fictional launch | Succeeded, 84.8 seconds | `debug-build.log` |
| TestFlight simulator build | Succeeded, 122.4 seconds; 0.9.0 (2), `com.mjenkins.gametime`, p11b | `testflight-build.log`, `built-product-metadata.json` |
| Staging device product build | Succeeded, 110.8 seconds; 0.9.0 (930.26.1), `com.mjenkins.gametime.staging`, p11b | `staging-device-build.log`, `built-product-metadata.json` |
| Staging signature | `codesign --verify --deep --strict` passed using the existing Apple Development identity, team `87Z29RTC26` | `staging-codesign-verify.log`, `staging-signature.log`, `staging-entitlements.plist` |
| Staging provisioning eligibility | Existing development profile includes the physical iPhone resolved from saved device metadata; valid through August 11, 2027; matching team and staging application identifier | `staging-profile-eligibility.json` |
| Creation measurement regression class | 13 passed, 0 failed or skipped after the sRGB helper correction | `creation-fixed.xcresult`, `creation-fixed.log` |
| Rendered rank methods | 2 passed, 0 failed or skipped with strict bounded contextual OCR | `rank-context-targeted.xcresult`, `rank-context-targeted-summary.json`, `rank-context-targeted-attachments/manifest.json` |
| Overlapping-response regression class | 21 passed, 0 failed or skipped, including both mounted methods | `overlap-context-class.xcresult`, `overlap-context-class-summary.json`, `overlap-context-class-attachments/manifest.json` |

The builds retain two existing app warnings: main-actor isolation around
`LiveGoalFloodlight.initials`, and a confusable trailing closure in
`WeeklyModels`. Native test compilation also reports four existing mutable
capture warnings in Health transport/friends fixtures.

## Fresh native tests and preserved failures

The fresh Debug run selected all `GameTimeTests` and six current
`LiveDesignUITests`: the four shell routes, saved friend lobby/invitations,
separate invitation consent, Health before creation, Health before agreement,
and no progress before Health is connected.

The actual Xcode result finalized with **673 passed, 2 failed, 11 skipped**:
all six selected UI journeys passed. The two failures are rendered-view test
measurements. They are retained in `native-focused.xcresult`,
`native-focused-summary.json`, `native-focused.log` and `initial-attachments/`.
The MCP client timed out after 300 seconds; the underlying Xcode run continued
and finalized its result at 454.6 seconds. The summary above comes from that
finalized bundle, not the tool timeout.

An unchanged isolated retry reproduced both failures in 21.1 seconds
(`native-failed-methods-retry.xcresult`). They were investigated before edits:

1. **Creation button edge:** the saved PNG uses Display P3. The button's raw
   pixel was `(51, 90, 246)`; explicit conversion to sRGB gives precisely the
   light fill token `(36, 91, 255)`. The image visibly contains the complete
   button. The helper now draws into explicit sRGB and resolves the actual
   `SignalTheme.accentFill` token in light traits, matching the mounted view.
   The narrow eight-byte tolerance and every viewport/docking assertion stay
   intact. All **13 creation-class tests passed** after this change
   (`creation-fixed.xcresult`, `creation-fixed.log`).
2. **Rank before an overlapping response:** the saved image visibly shows
   rank 1 beside You and 12,000 steps, and rank 2 beside the other person with
   321 steps. Whole-viewport Vision text omitted the first rank and appended
   `w 1` elsewhere. This assertion ran before responses overlapped. The scoped
   helper instead locates the rendered You glyphs and checks the exact numeric
   rank in a bounded adjacent image crop. Totals, finality, no-extra-fetch and
   stale-response store assertions remain intact. The two initial isolated-digit
   OCR attempts passed the final-result method but returned an empty array for
   the clearly visible single `1`, including the attempted fast recognizer.
   Both failed measurement iterations and their images remain in
   `rank-fixed.xcresult`, `rank-fixed-fast.xcresult` and their attachment directories.
   Offline Vision checks on the retained bounded rank-and-You images identified
   the actual numbers without digit hints. The final helper enlarges that
   context, independently locates You, accepts only an exact positive numeral
   immediately left of that name within the same row, and requires the
   associated numeral array to equal the expected rank. It uses no alternate
   candidates, expected-digit hints, letter conversion, extra fetch or remount.

The final strict targeted run passed **2 of 2** mounted methods in 37.9 seconds
(`rank-context-targeted.xcresult`). The full affected overlapping-response class
then passed **21 of 21** tests in 49.6 seconds (`overlap-context-class.xcresult`).
Each run retains before/accepted/after-late contextual images, crops and recognized
text in its exported attachment manifest. Both initially failing classes now
pass in full. The original broad-run count is preserved above; a new broad run
was not repeated after these two test-only helper corrections.

## Prepared Staging product

The local app is at
`tmp/testflight-readiness-2026-09-30/native/StagingDeviceDerivedData/Build/Products/Staging-iphoneos/GameTime.app`.
The build command overrides only `CURRENT_PROJECT_VERSION=930.26.1`; the
checked-in TestFlight version and the existing development archive remain
0.9.0 (2). No provisioning update flag, credential change, account acceptance,
or distribution signing was used. The log records `generic/platform=iOS`;
it does not target or install to a physical phone.

The prepared app uses the existing staging bundle and p11b. Its verified signed
entitlements include Sign in with Apple, HealthKit and background delivery,
development push/App Attest and `get-task-allow=true`, as expected for Staging.
Signature inspection inside the restricted shell initially could not read the
Mac certificate trust store; the same read-only checks passed with appropriate
filesystem access. `built-product-metadata.json` records its binary SHA-256.

Read-only decoding of the embedded profile confirms that the physical iPhone
resolved from the saved device inventory is already among its two provisioned
devices. The profile is valid from August 11, 2026 through August 11, 2027 and
matches the signing team and staging application identifier. The phone was
unavailable in that inventory. This establishes local profile eligibility, not
successful connection, installation, or launch. The sanitized
`staging-profile-eligibility.json` records the comparison without device identifiers.

This file does not establish the version currently installed on Mason's phone.
Before any separately authorized in-place update, inspect the actual phone's
installed version and confirm the staging bundle. Do not install the production
TestFlight bundle beside Staging while both would upload for the active account.

## Fictional challenge recording

`tmp/testflight-readiness-2026-09-30/native/fictional-simulator-challenge-demo.mp4`
is a **44.1-second, 3.4 MB, 828 × 1910** movie assembled from the real simulator
UI captured while the passing fixture tests ran. A persistent added caption
labels it **Fictional simulator demo — Debug fixtures**. Chapters show the
Health explanation, creation with chosen friends, invitation review with consent
left unchecked, seeded active progress, and a separate seeded finished record.

This is a local review draft with separate fictional examples, not one live
challenge advancing through time. It does not demonstrate actual Apple sign-in,
Watch/Health access, hosted scoring, or a real settled goal. No movie has been
submitted to Apple. The unedited 130.4-second recording is retained as
`fictional-native-fixture-raw.mp4`; `build-fictional-demo.py` records the exact
clip ranges and caption assembly. `fictional-demo-preview.png` is a still.

## Unperformed checks

No fresh full 774-test native/UI accessibility run, separate historical
conformance harness, physical Apple sign-in or Health session, human VoiceOver
review, distribution export, archive replacement, TestFlight upload, or App
Store Connect mutation was performed. Simulator proof cannot replace those
physical, human, hosted, or distribution checks. See the main reconciliation
receipt for their current status and the exact next owner action.
