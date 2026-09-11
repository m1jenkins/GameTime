# Cobalt UI verification — September 11, 2026

The visual implementation uses the attached Home reference. These are local,
fictional checks on the accepted `a18f00f` baseline; they do not open distribution
or prove physical Health, hosted account, support/deletion or payment readiness.

## Results by scope

| Scope | Result and evidence |
| --- | --- |
| Core presentation and sections | 17 checks passed, zero skipped, at 19:45; includes native policy/model and section routing checks. |
| Authenticated native HTTP | `testTwoAndSixPersonProductionNativeJourney` passed at 19:54, zero skipped. Covers all 13 policies, two/six-person paths, eligibility, links/reconsent, recovery, reviews/results and safety. This run precedes final styling; transport/store behavior was not changed afterward. |
| Two/six-person touch journeys | Both passed, zero skipped, 20:06 run (860.6 seconds). Actual creation/lobby/consent/active/review/final captures are retained. Typography/spacing was subsequently refined. |
| Historical consumer UI | 11 selected flows passed in the 20:27 run, including Personal consent/test payment/recovery, dirty-close, automatic progress, settings, accessibility/Reduce Motion, duel and commitment safe exits. Two unrelated Beta audit/header checks failed in that same run and are not counted as successes. |
| Historical sign-in, loading and settings after final font | Three UI tests passed, zero skipped, 20:58 run; nine current Simulator screenshots retained. |
| All 13 metric/detail presentations | Passed native render/privacy assertions on iOS 26 at 20:49 and on iOS 18 at 21:01. Includes exact fractional distance, elapsed-time units and no inferred progress for timed leaderboards. |
| Privacy races after final metric layout | Three mounted departure/overlap regressions passed at 20:55; the other 16 race/model cases and Home overlap passed at 20:51. No redacted identity, target or activity reappears after held responses complete. |
| Theme | All three semantic contrast/font/content-shadow checks pass on iOS 26 and 18. White on the blue feature panel has 5.94:1 contrast; white on its You selection has 4.84:1. |
| Compact authenticated flow | iPhone 13 mini / iOS 18.6: sign-in/tab/sign-out and four metric choices/personal consent reset pass, zero skipped, 21:01 run. |
| Final Home | Current, compact, dark and accessibility fixtures verify the three-section hierarchy and actual metric values. Font registration and italic traits are asserted; the authenticated UI test checks the GameTime accessibility label. The iOS 18 final Home/header rerun passed (2 tests, zero skipped) at 21:07. |
| Product boundary | `scripts/check-iphone-product.py --app …/Debug-iphonesimulator/GameTime.app` passes: iPhone app, HealthKit linked, no watch payload or link. |

## Unresolved accessibility findings

`testLocalAccessibilityPreparation` remains **failed**, not waived or filtered.
On iOS 26 the final inspected run reports contrast findings on partially visible
Home/history and lobby text at scroll boundaries. Earlier small hit-target and
Dynamic Type findings were corrected. The iOS 18 compact run additionally flags
Dynamic Type and potentially inaccessible text. These findings still need
resolution before accessibility acceptance. Semantic color contrast passing is
not a substitute for that system audit.

Normal, compact and accessibility-sized native layouts were inspected. The
large-text layout intentionally scrolls; it does not compress the sample into
one screen. Human VoiceOver reading order/comprehension and provider-owned
sheets have not been accepted in this pass.

## Test maintenance

- Mounted privacy OCR now expects `100 of 1,000 steps` and analogous corrected
  totals. All negative name/target/activity redaction checks remain intact.
- OCR image tiles overlap so a baseline crossing a tile boundary is not cut in
  both inputs. No required data is hidden to make the test pass.
- iOS 18 Vision transcribes the white condensed GameTime wordmark as “Came Time.”
  The image was inspected; the actual named italic font is loaded. The render
  check uses the New challenge header anchor and all required data, while an
  authenticated UI assertion verifies the exact GameTime accessibility label.
- Obsolete orange/black token snapshots were replaced with semantic contrast
  checks for both appearances and actual bundled-font checks.
- Unsigned iOS 18 test-host startup logs a HealthKit entitlement warning. The
  tested activity is fictional; no successful physical Health read is claimed.

## Retained artifacts

Native model renders: `screenshots/native` (iOS 26) and `screenshots/ios18`.
Actual OS/touch captures: `screenshots/forms`, `screenshots/legacy`,
`screenshots/touch-before-final-layout`. Historical weekly model renders:
`screenshots/weekly`. The names make earlier layout iterations explicit.

Full local result bundles and filtered build logs are under:
`~/Library/Developer/XcodeBuildMCP/workspaces/GameTime-7b9ccaa5aefb/`.
Important run IDs:

- `test_sim_2026-09-11T19-54-02-039Z_pid19149_6ea537b2.xcresult` — native HTTP.
- `test_sim_2026-09-11T20-06-08-476Z_pid19149_50787904.xcresult` — two/six touch.
- `test_sim_2026-09-11T20-27-08-133Z_pid19149_30dc89fa.xcresult` — historical UI and early Beta findings.
- `test_sim_2026-09-11T20-55-46-085Z_pid19149_72f19724.xcresult` — final privacy/Home checks; audit still failed.
- `test_sim_2026-09-11T20-58-36-077Z_pid19149_cadffdd1.xcresult` — theme/historical UI; audit still failed.
- `test_sim_2026-09-11T21-01-25-047Z_pid19149_06894408.xcresult` — compact runtime, with explicit OCR/audit failures.

Raw authenticated UI logs and ignored manifests can contain fictional local
credentials and are deliberately not included in the review artifacts.

Final compact Home/header result: `test_sim_2026-09-11T21-07-23-948Z_pid19149_e1660fb4.xcresult`.

## Final builds and cleanup

- Debug/Beta final Home test: passed, zero skipped, iOS 26.5, 21:12 run
  `test_sim_2026-09-11T21-12-41-459Z_pid19149_d26af0bc.xcresult`.
- Staging: build passed in 79.4 seconds,
  `build_sim_2026-09-11T21-09-12-570Z_pid19149_e1be5378.log`.
- Release: build passed in 81.0 seconds,
  `build_sim_2026-09-11T21-11-13-332Z_pid19149_f3ee5ff7.log`.
- Release product boundary checker also passes: HealthKit linked, no watch
  payload/link, expected three schemes. No signing or distribution occurred.
- The pre-existing `WeeklyModels.swift:275` trailing-closure warning remains.
  `git diff --check` passes.
- The owned preview controller has stopped. Its fictional account sessions were
  revoked, its private manifest removed, and fixture/admission/processing gates
  were verified closed. The owned Supabase stack was stopped with data retained;
  both empty owned Docker networks were removed. Other stacks were preserved.
