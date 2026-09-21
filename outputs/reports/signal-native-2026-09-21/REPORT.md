# Signal native follow-through — September 21, 2026

This implements the owner's feedback on installed 0.8.1 (926.20.1). Direct Personal creation now has two stages: **Goal & dates → Review**. Home and Challenges lead with saved goals, and You reads the ordinary app's `ChallengeV1Store`. Settings sit behind the profile's toolbar button. Retained Personal still uses its original store and agreements.

[Open the visual report](../../../.lavish/signal-native-2026-09-21/index.html). It uses Signal's approved palette, typography, opaque facts and open sections. Native screenshots are labeled separately from browser illustrations. The report's examples use fictional local accounts and activity.

## What changed

- Goal entry shows the selected dates, duration and unit together. Dates, time zone and simulated amount use compact editors. Generic creation keeps Type; direct Personal skips it. Suggestions require a deliberate choice. All four metric inputs and their precision remain supported where policy allows them.
- Review keeps source limits, outcomes, dates, amount, exit and review rights visible before unchanged explicit consent. Complete rules use a disclosure. The stable draft, session/actor fencing, preview/readiness resets, exact pending retry and recorded success remain in place.
- Challenges separates Active, Upcoming and Finished, groups personal/friend/community records, and keeps attention above the filters. The entire row is tappable. Saving the first upcoming goal selects Upcoming. Home features the actual next goal.
- You leads with identity and a saved goal, then scoped counts and records. Personal activity stays separate from challenge results. No lifetime totals or streaks are fabricated. The [profile data contract](../../../docs/design/SIGNAL_PROFILE_DATA.md) defines ownership, calculations, freshness, pagination and account clearing.
- Invitations, shared creation/lobbies, detail, activity, review, history, community entry, account/privacy/support and retained agreements use the same spacing, readable dates and opaque fact groups. Community reporting, incomplete-agreement refusal and saved-membership navigation remain visible. Decorative dividers stay horizontal at large text sizes.

No backend contract, scoring rule, D141 policy version, availability restriction, historical consent, Health permission or financial gate changed. The signed Staging product retains the private-account settings accepted for the preceding phone build.

Unsupported lifetime activity and streaks are explicitly unavailable. Loaded challenge counts are scoped; partial pages use plus signs or dashes, expired/failed reads do not become zero, and applicable finalized competitive allocations alone establish wins/losses. No chart aggregates overlapping challenge scores into personal activity.

## Visual comparison and journeys

The starting source was local `main` at `d7a9f7d`; the September 20 native report supplies before captures from the installed implementation. Browser reference source includes the September 13 Signal study and `.lavish/signal-screen-completion/` through `d7a9f7d`, including the newer profile. Its illustrated activity, streak and competitive totals are not production requirements.

Live rendering of the local browser reference was blocked by browser security policy after the Chrome bridge failed. We inspected its source and saved current renders; no alternate route was used to bypass the block. Native captures were rendered anew in Simulator. The visual report shows that distinction.

| Journey | Observed result |
| --- | --- |
| Personal entry → edits → review → confirmation → detail | Goal and dates stay together; exact input, invalid values, date retention, amount changes and consent/readiness resets exercised. A fictional 10,000-step goal was recorded. |
| Relaunch → Home → Challenges → You | The same saved goal appears in all three places. The complete upcoming count increases by one. Settings, privacy and support remain reachable. |
| Invitation entry and availability | Typing retains focus; malformed input cannot continue. The saved lobby keeps username invitation and safe exits. Link generation stays disabled without a configured HTTPS origin; no share destination or external recipient was used. |
| Shared creation → recorded lobby | Friend goals v1 and received-score leaderboard v2 save and open their recorded lobbies. Leaderboards have no personal target field. |
| Activity → correction → review → final → history | Synthetic activity, review and return assertions are recorded in the verification ledger. Missing activity is not a competitive loss. |
| Community and shared safety | Native mounted catalog/join/detail states cover delayed/hidden counts, joined membership, incomplete rules, reporting and safe exits. There was no catalog entry in the ordinary local account; no full community enrollment is claimed. |
| Existing challenges | Retained agreements, locked terms and sandbox cancellation exercised. Retained Personal/Solo/charity backend acceptance was not rerun. |

Captures include light/dark, 375-point compact layouts, accessibility text, keyboard open, increased contrast and reduced transparency/motion. Mounted model-backed renders supplement ordinary app touch journeys. They do not prove human VoiceOver order or physical-device legibility.

## Verification and source identity

Native source is committed as `4ff837ddf858ae467497ea467b14f3090d3410d9`. Final test counts, build identities and result bundle paths are recorded in `verification.json` and `build-receipt.json` with their exact performed scope. `capture-provenance.json` maps exported screenshots to runs; earlier generations remain useful failure evidence and are not final acceptance by themselves.

The integrated run passed **65 tests, with no failures or skips**. Focused follow-ups passed for the final result wording, invitation focus, dark accessibility text, iOS 18 fallback, retained accessibility text and reduced appearance. Failed attempts and their corrections remain in the ledger.

Debug, Staging and Release simulator products passed. The iPhone-only product guard passed for all three and the signed Staging device product. Signed **0.8.1 (926.21.1)** is preserved at `build/signal-native-staging-20260921-926.21.1/GameTime.app`; its verified signature, hashes and unchanged configuration are in [the build receipt](build-receipt.json). It has not been installed.

Testing uses XcodeBuildMCP with the project `ios/GameTime/GameTime.xcodeproj`, owned DerivedData `/private/tmp/gametime-signal-native-completion`, and focused selectors. No full historical weekly or hosted acceptance matrix is claimed.

The task used one disposable loopback Supabase stack created with `scripts/p8-real-health-verify.py prepare`, with the existing September 20 migrations applied forward. `scripts/p9-signal-health-controller.ts` supplies fictional Auth, a controllable clock and synthetic activity. Private manifests stay outside the repository. The controller restored its clock, disabled its fictional runtime and revoked its sessions. Ownership-checked cleanup removed the task stack and manifest aliases. No other checkout's database was reset.

## Failures found during verification

Visual inspection caught banner overlap with navigation, a divider that could become vertical inside a retained button, tiny large-text selectors, and keyboard obstruction of goal input. The fixes move the simulation label into scroll content, use explicit horizontal rules, give large-text selections their own rows, and scroll the focused entry above the keyboard.

Final result screens now retain the review-request timestamp without telling the person to refresh an already confirmed result. One-day duration labels use the singular, and finished attention records no longer sit above a contradictory empty-history message.

The ordinary lifecycle test exposed a row whose empty center did not open detail; its full rectangular hit area is now explicit. Profile review found that cached section flags could outlive aggregate store invalidation; stale counts now become dashes. Invitation typing initially replaced its field after the first character and lost keyboard focus; confirmed accounts now keep the same disclosure view while it expands in place. A new saved goal initially stayed hidden behind Active; the first upcoming goal now selects Upcoming after creation closes.

Earlier failures also included stale UI-test wording, an invalid read-only SwiftUI environment override in a test, and reused fictional actors with equal test-clock creation timestamps. Those failures are preserved in result bundles. The new invitation test also assumed sharing was enabled; the missing-origin restriction was correct, so the test now asserts that gate. Its earlier failure hung in UI teardown; the owned simulator runner was stopped and cleanup now restores the local clock independently. Current assertions check the visible return fact and use an unused fictional actor for the final lifecycle run.

The large-text Settings navigation attempt failed before the app journey; its normal-layout rerun passed. Follow-up runs completed the app journey but exposed a Settings restoration race after changing Reduce Motion. Cleanup now reopens Settings before restoring transparency and checks the restored value. Retained agreement/cancellation also passed with an explicit accessibility text launch setting.

The signed-out/onboarding UI test passes but still emits an unattributed “Invalid frame dimension (negative or non-finite)” runtime warning. Removing redundant keyboard scrolling did not remove the warning. No clipped or missing control was established by that warning; it remains an investigation item, not a clean-warning claim. The existing `WeeklyModels.swift` trailing-closure compiler warning also remains.

## Remaining acceptance

The phone was not uninstalled, reset or updated. The prepared signed build is for a later coordinated in-place installation. Physical light/dark/material/keyboard review, actual Health readings and full real-deadline outcomes remain unperformed here. Human VoiceOver reading order, comprehension, motor accessibility and comfort at the largest text settings remain separate acceptance.
