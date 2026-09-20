# Signal creation — September 20, 2026

The native creation flow now follows Type → Activity and goal → Dates → Amount → Review. Direct Personal entry starts at Activity and shows four steps. The private Staging configuration remains Personal steps only. Large editable values, native glass controls and a receipt-based confirmation replace the long form.

## Source and scope

Started from clean local `main` at `5b4870f`, on `codex/signal-creation`. That baseline already contains the accepted private-phone readiness/consent fixes and D141 received-score leaderboards. No reset, stash, clone, worktree or overwrite of another task's work was needed. Native implementation is committed at `9092d50`. [source-manifest.json](source-manifest.json) identifies its files by SHA-256; the final local main commit, including the report, is recorded in the handoff.

The change reuses `ChallengeV1Store`, its client and exact saved requests, and `ChallengeHealthFlowStore`. It adds one observable draft owner, step views and Signal input controls. It also replaces the shared date spreadsheet with a readable date span. Existing consent strings, agreements, backend/schema, policies, permissions, transport gates and Staging configuration remain unchanged.

The default remains 7 full local days, starting 2 days ahead, and $20 simulated ($1–$500, whole dollars). Targets start empty. Exact steps, minutes/seconds, kilometre precision and timed-run distance remain editable. Changing the time zone preserves the chosen calendar date and exact stored zone ID. Daylight-saving tests cover a 25-hour day.

Edits invalidate preview, consent and readiness context. Back during a pending preview invalidates its response; it cannot jump forward after the person navigates away. Closed drafts and changed actors cannot consume late results. Recovery resends the saved request body and ID, and confirmation uses the accepted receipt and recorded model. Recovered Personal requests keep their Personal confirmation even when reopened from generic Create.

## Visual result

[Interactive comparison](../../../.lavish/signal-creation-2026-09-20/index.html) uses the approved Signal palette, system typography, open rows and blue accent. Every screenshot is a real browser reference or native simulator capture; no generated mockups replace implementation evidence.

| Decision | Before | After |
|---|---|---|
| Activity and goal | [Long form](before-personal-create.png) | [Large precise input](after-activity-steps.png), [distance](after-activity-distance.png), [timed run](after-activity-timed.png) |
| Dates | Raw zone ID and repeated fact rows | [Calendar, readable zone and local-day span](native-final-compact-dates.png) |
| Amount | Small field among all other choices | [Single large amount](native-final-compact-amount.png) |
| Review | [Expanded agreement](before-personal-review.png) | [Goal band and dates](after-review-top.png), [source, outcomes, collapsed rules and explicit consent](after-review-consent.png) |
| Success | Dismissed creation | [Recorded confirmation](after-saved.png), [scheduled detail](after-detail.png), [rules and safe exits](after-detail-lower.png) |
| Material | Existing mixed controls | [Native glass](native-final-compact-activity.png), [system Reduce Transparency + Reduce Motion](system-solid-compact-activity.png), [iOS 18 solid](ios18-compact-activity.png) |

The reference's fictional names, goals, dates, chart values, browser tab bar inside creation, and older policy wording were not copied into production. Native creation uses a modal navigation stack. The new larger inputs follow the owner's approved simplification, beyond the original browser's small fields. The amount is never promoted upward. Complete rules remain available by disclosure; source limits, simulated outcomes, exit/review rights and consent remain visible before committing.

Standard light and dark, compact 375-point width, accessibility text, keyboard-open, Increase Contrast, system Reduce Transparency/Reduce Motion, and iOS 18 fallbacks were captured. Large text moves activity choices to one column and date boundaries to vertical layout. The native accessibility hit-region audit passes; circular adjustment controls are also checked at 44 points or larger. Progress, selection traits, headings, input labels and Back/Close remain accessible. Human VoiceOver reading order and physical-phone material acceptance remain unperformed.

## Connected and surrounding routes

| Route | Inspected evidence and result | Remaining distinction |
|---|---|---|
| Personal creation → review → saved → detail | Ordinary app, fictional loopback Auth/Health, all four inputs and a recorded steps goal. Large value/blue band/date span now follow Signal. | Physical Health permissions/data and owner's phone session not exercised. |
| Personal activity/correction/review/history | Existing ordinary-app journey passes 10,001 → 9,999 correction, actual notice, review and final return; [history capture](lifecycle-didnt-count-history.png). | History's broader list composition remains denser than the study. No invented loss or daily chart series. |
| Shared friend creation | Goals with friends v1 and received-score leaderboard v2 both save and open recorded local lobbies. The leaderboard accepts all four activities without a target. Two/six-person mounted details, rules and exits checked. | The reference includes social presentation beyond this creation change. |
| Home | [Native empty Home](before-home.png) and [current reference](reference-home.png) inspected. Signal title, blue, open layout, glass navigation and retained route match the adopted system. | Empty fixture cannot establish the reference's populated weekly chart fidelity; no fake chart added. |
| Challenges / invitations | [Native entry](before-challenges-entry.png) and [reference](reference-challenges.png), [invitation reference](reference-invitation.png) inspected. Current entry preserves an explicit invitation field and separate agreement. | Native entry is a dense list, unlike reference segments/open sections. Full invitation acceptance was not replayed in this task. |
| You | [Native](before-you.png) and [reference](reference-you.png) inspected. Signal open rows, Health controls and navigation present. | Current counts are challenge counts, not the reference's fictional activity metrics. |
| Community | Reference and mounted native detail/join states inspected; privacy threshold/mature-count render regressions pass. | The ordinary app fixture has no community catalog entry. No claim of full ordinary community journey acceptance. |
| Existing challenges | [Retained native route](before-existing.png) opened with fictional earlier agreements and rechecked after implementation. Historical copy and contracts preserved. | At accessibility text sizes, the retained screen has an existing vertical-divider/scroll composition issue ([capture](after-retained-access.png)). Retained Personal/Solo/charity flows were not requalified end to end. |

## Verification ledger

All native tests used XcodeBuildMCP, project `ios/GameTime/GameTime.xcodeproj`, Debug scheme `GameTime`, owned DerivedData `/private/tmp/gametime-signal-creation-build`. Tests use `extraArgs` with `-only-testing:` selectors; final runs disable parallel test workers.

| Check | Result | Result bundle suffix / evidence |
|---|---|---|
| Baseline ordinary-app capture | 1 pass | `18-23-01-061Z_pid65444_9a55c53d.xcresult` |
| Personal save/detail + friend leaderboard + preview failure | 3 pass; initial compact AX-frame assertion failed and was corrected to audit actual system hit regions | `18-57-04-826Z_pid65444_72d00cbe.xcresult` |
| Existing Health correction/review/history journey | 1 pass | `18-43-20-924Z_pid65444_66c117e7.xcresult` |
| Final compact native controls/hit-region audit | 1 pass | `19-01-45-774Z_pid65444_3855ca89.xcresult` |
| Seven readiness states with screenshots | 1 pass | `18-59-56-959Z_pid65444_560543de.xcresult` |
| System Reduce Transparency + Reduce Motion, ordinary app | 1 pass | `19-05-22-245Z_pid65444_172aa539.xcresult` |
| iOS 18.6 compact journey + draft/visual tests | 11 pass, 0 fail, 0 skip | `19-06-46-288Z_pid65444_5bc720c8.xcresult` |
| Dark accessibility-extra-large ordinary journey | 1 pass | `19-08-35-398Z_pid65444_897d7036.xcresult` |
| Final focused native regression set | 45 pass, 0 fail, 0 skip | `19-10-33-790Z_pid65444_17a347bf.xcresult` |
| Final dark large-text check + friend goal/retained access | 2 pass, 0 fail, 0 skip | `19-17-47-190Z_pid65444_3d349920.xcresult` |
| Repeated material/layout matrix after disabled-label refinement | 1 pass, 0 fail, 0 skip | `19-19-48-969Z_pid65444_31c59bd4.xcresult` |
| Debug / Staging / Release simulator builds | All pass | Build logs: `19-21-03-690Z_pid65444_7d394f3a`, `19-21-12-201Z_pid65444_0376eb43`, `19-24-43-253Z_pid65444_dba745b8` |
| Active iPhone product guard | Pass: 192 source inputs, three iPhone targets; all four built products pass | `python3 scripts/check-iphone-product.py --app <product>` |
| Signed Staging device product | Pass: 0.8.1 (926.20.1), signature verified, not installed | [Build receipt](build-receipt.json) |

Result bundles and build logs remain in `/Users/user/Library/Developer/XcodeBuildMCP/workspaces/GameTime-7b9ccaa5aefb/`. The dated filenames above are prefixed `test_sim_2026-09-20T` under `result-bundles/`. No full weekly, release or backend acceptance matrix is claimed. The older `ChallengeV1UITests` navigation was adapted and compiled; its separate `__beta/control` fixture journeys were not all replayed. Current ordinary-app and shared creation checks use the existing P9 controller instead.

The task created one owned disposable local Supabase project with `scripts/p8-real-health-verify.py prepare`, applied the existing September 20 migrations forward to that project, and used `scripts/p9-signal-health-controller.ts` for fictional Auth, clock and synthetic activity. It did not reset another checkout's stack or target hosted credentials. The controller exited cleanly after restoring its test clock and revoking its fictional sessions; ownership-checked cleanup removed the task’s containers/network and its temporary P9 manifest symlink. Private manifests and auth values stay outside the repository.

Earlier failures are retained in local result bundles. They included a test-runner cache mismatch, a missing numeric keyboard dismissal, an ambiguous native/custom Done locator, inherited dark text on a blue primary control, icon overlap at accessibility sizes, and a stale preview navigation race. These were fixed. The final visual pass also corrected disabled primary-button contrast in dark mode, then repeated the actual journey and material matrix. Screenshot helpers initially ignored scroll safe-area insets, omitting bottom controls; corrected captures now include them. The old rendered agreement assertion expected a raw zone ID; it now checks the readable city/name while unit tests preserve the exact ID. Native bar visual bounds are smaller than their system hit region, so the final test audits hit regions instead of equating them with visual bounds. Direct preference writes did not activate Reduce Transparency; those attempts skipped and were replaced by a passing Settings-driven UI test. Initial temporary full-test invocation used an unsupported selector argument and was stopped; it is not acceptance evidence.

### Commands and fixture scope

The final 45-test invocation used `test_sim` with `-parallel-testing-enabled NO` and these selectors:

- `GameTimeTests/ChallengeCreationDraftTests`
- `GameTimeTests/ChallengeHealthFlowStoreTests`
- `GameTimeTests/ChallengeV1NativeTests`
- `GameTimeTests/SignalRenderedTests`
- `GameTimeTests/SignalThemeAdversarialTests`

Ordinary-app checks selected `GameTimeUITests/SignalCreationUITests` methods individually and the existing `GameTimeUITests/ChallengeHealthSignalUITests` lifecycle journey. They used existing authenticated-app and synthetic-Health fixture arguments against the owned loopback controller. Four metrics were edited/validated; steps were committed for the full recorded journey. Pure state/mounted tests cover the seven readiness states (including no matching activity, which does not infer Health authorization), unavailable/retry, preview loading/failure, validation and saved-request recovery.

The mounted matrix uses 375 × 812 viewports with canned fictional server responses. It exercises the same production step views but is distinct from the ordinary app and its server-backed receipt journey. Screenshots record individual scroll positions; the ordinary-app screenshots include actual keyboard and bottom safe-area behavior. No screenshot or fixture is evidence of real Health data.

Simulator builds used `build_sim` with scheme/configuration `GameTime`/`Debug`, `GameTime-Staging`/`Staging` and `GameTime`/`Release`. Product inspection uses `python3 scripts/check-iphone-product.py --app <built-app>`. The pre-existing `WeeklyModels.swift:275` trailing-closure warning remains; no new build warning was introduced.

### Prepared Staging product

The signed app is preserved in the ignored build directory:
`build/signal-creation-staging-20260920-926.20.1/GameTime.app`.
Its native source is `9092d50`, version `0.8.1`, build `926.20.1`, bundle ID `com.mjenkins.gametime.staging`. The build-number override identifies this product without changing the source configuration. Existing Staging private-account and runtime flags remain as recorded in [build-receipt.json](build-receipt.json), along with SHA-256 hashes and build log paths.

`build_device` succeeded using the generic iOS destination. `codesign --verify --deep --strict` passes. A first sandboxed signature check could not access the normal trust services and reported `CSSMERR_TP_NOT_TRUSTED`; the same read-only verification with normal macOS access passed, as did verification of the preserved copy. Nothing was re-signed or changed to work around trust.

The [Lavish comparison](../../../.lavish/signal-creation-2026-09-20/index.html) is open locally. Its stage selector, material selector, image loading and wide/narrow browser layout were checked. It uses the owner's selected Signal design system. No report was published externally.

## Copy, material and acceptance limits

`unslop` was applied to new app text and this handoff, using the crisp preset and `docs/COPY.md`. The app-copy and report scans found no banned phrases or structural violations. Soft report repetition/readability flags arise from technical filenames, table rows and explicit acceptance limits; those records are preserved. Repeated imperative labels across separate steps are intentional UI navigation, not prose to vary. A preview connection failure now points to the actual Review action. Historical consent/source/legal strings were preserved.

Native material uses Apple's [current SwiftUI Liquid Glass guidance](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views): native glass/glassProminent buttons on iOS 26, one glass activity group with an opaque selected inset, and system navigation controls. Numbers, date facts, rules, consent and plots remain on solid content. Solid capsule/circle fallbacks retain the control shape, and the flow adds no motion animation.

Device installation, phone relaunch, physical Health/source validation, human VoiceOver and release/distribution acceptance are unperformed. The corrected Staging product is prepared for a later coordinated in-place update only. The owner's phone container, account, saved goals and pending requests were not touched. Nothing was pushed, deployed or changed in hosted settings.
