# Friends TestFlight Phase 3: iOS 18.6 recheck

September 23, 2026. This rechecks the native Phase 3 work under [D142](../../DECISIONS.md#d142-first-private-testflight-adds-friends-opens-apple-sign-up-and-ships-goals-first) from clean local `main` at `11c7092`, after the requested floor `574b8d6`. The implementation was already on `main` in `ccb11a4`, `24b094e`, `1e6fd8c` and `45fc933`; [its original receipt](2026-09-22-friends-phase-3-native.md) describes the Friends store, screens, server-reported policies, TestFlight configuration and candidate checker. This recheck changes no product behavior or approved Phase 1 board.

## Changes in this recheck

- The app and `GameTimeTests` target compiled before any source edit. The reported `Int` versus `[TimeInterval]` error in `ChallengeHealthFlowStoreTests.swift` did not reproduce, so there was no compile fix to make.
- The full-page screenshot text recognition on iOS 18.6 read the visible `km` beside `20` as `m`. The separate `testGoalUnitsStayBesideTheirValuesAndContinueStaysVisibleWhileScrolling` passed and checks both the unit and its position. The duplicate full-page OCR assertion was removed.
- The Blocked people UI test now scrolls its bottom row above the tab bar before tapping it. On iOS 18.6 the first run's tap landed on Challenges; after the test adjustment, the Blocked and Unblock flow passed.

## What ran

All simulator checks used the lowest available iOS 18.x runtime here: iPhone 16, iOS 18.6 (`FEA51266-716C-4587-8AA9-111D210B93D6`).

| Check | Result |
| --- | --- |
| `GameTime` Debug app build, then `GameTimeTests` build for testing | Both compiled. No `ChallengeHealthFlowStoreTests` type error. |
| Focused unit tests: `FriendsStoreTests`, `ChallengeCreationDraftTests`, `ChallengeCreationFlowTests`, `ChallengeAppConfigurationTests` | 48 passed, 0 failed, 0 skipped after the OCR test adjustment. The first run had 47 passed and the duplicate OCR assertion failed. |
| Affected `LiveDesignUITests` on the approved design fixture | Eight passed in the focused run. Blocked people failed because the tap hit the tab bar; its isolated rerun passed after scrolling the row. The all-in-one 13-test tool call timed out before it returned a result and is not counted as a pass. |
| `FriendsNativeSmokeTests` against a fresh, disposable Supabase stack | Passed. The test used the production `FriendsStore` and `SupabaseChallengeV1Client` with four fictional signed-in, age-confirmed accounts. It covered the six reported policies, account mode, closed links/community, exact lookup, request/crossed request, accept, decline, block, unblock, report, stale cancel and lookup limit. |
| Disposable stack | Unique project `gametime-friends-phase3-pn0z1pn0`, loopback ports 57760–57769 and isolated network `10.253.0.0/24`. It applied the Phase 2 friend and allowlist migrations plus the two later Phase 4 fix migrations present on current `main`. The task-owned stack stopped with `--no-backup`; the network was already removed by Supabase. The private test manifest was removed and fictional sessions revoked. No other checkout's stack was reset. |
| `GameTime-TestFlight` simulator build, without signing | Passed. Built Info.plist has production bundle `com.mjenkins.gametime`, `testflight` environment, P11B URL, challenges and account mode on, `test_only` settlement and no Stripe return. |
| Candidate checker and its fixtures | `scripts/tests/check-beta-candidate.test.sh` passed; `scripts/check-beta-candidate.sh --testflight` had 18 passes and the three existing owner blockers: privacy policy URL, beta terms URL and monitored support email. `scripts/tests/check-iphone-product.test.py` passed 15 tests. |

## Not run or established here

- No Phase 4 full friend-goal matrix or `scripts/weekly-local-verify.sh` was rerun. [The Phase 4 receipt](2026-09-22-friends-phase-4-local.md) records those earlier local checks.
- No physical-device, human VoiceOver, Dynamic Type remediation, signed archive, TestFlight upload, Apple provider change or hosted mutation was performed. The TestFlight candidate checker is source preflight, not distribution acceptance.
- No real-user sign-up, friendship, activity upload or result was observed in this recheck. The local stack used fictional accounts and a loopback API.

## Handoff

The original Phase 3 handoff was Phase 4 local verification: friend and Personal goals, membership limits, correction and final-result cases, closed links/community, accessibility and regression checks. That work has since been recorded as locally complete in the [Phase 4 receipt](2026-09-22-friends-phase-4-local.md). Its open human/device items remain: text-size support across the September 22 design, VoiceOver and physical-device acceptance, and the product decision about real totals below a goal showing “Didn't count.” This recheck did not advance Phase 5 hosting or Phase 6 distribution.
