# GameTime native UI rewrite — September 22, 2026

The owner authorized replacing the app UI with the approved Home, Goal / Rules,
Challenges, You and create/invite direction, then comparing native screenshots
and revising mismatches. This is the implementation and verification record.

## What is now connected

Ordinary authenticated launch mounts `SignalProductShell` → `LiveChallengeShell`.
Home, Challenges and You are the app's three tabs. The old tab hierarchy is no
longer a normal or service-unavailable fallback. Startup, sign-in, onboarding,
Settings, Health, privacy, account actions and retained Personal history use the
new presentation as well. Earlier source retained for compatibility is not a
second selectable UI.

The screens use the existing `AppModel`, `ChallengeV1Store`, profile, invitation,
Health and Personal stores. Create, invitation review, consent, decline/leave,
refresh, result/review, account deletion and exact-request recovery still invoke
their existing operations. Account changes clear navigation and presented data;
late and restricted responses cannot restore another account's private content.
Earlier Personal agreements and attempted request recovery remain accessible
through newly styled history/detail routes without restoring legacy creation.

## Visual comparison

Open [the review board](index.html) for side-by-side, adjustable overlay and native
views. [The portable copy](review-portable.html) embeds all comparison images.
The design source is the user's locked September 21 mockups, not a new theme.

| Screen | Approved reference | Native capture |
| --- | --- | --- |
| Home | [Reference](references/home-cool-palette.png) | [Native](captures/home.png) |
| Goal / Rules | [Reference](references/goal-modules.png) | [Native](captures/goal.png) |
| Challenges | [Reference](references/challenges-library.png) | [Native](captures/challenges.png) |
| You | [Reference](references/you-metric-record.png) | [Native](captures/you.png) |

Additional actual screens: [Full rules](captures/rules.png),
[creation](captures/create.png), and [Settings](captures/settings.png).
Captures are lossless 1170 × 2532 screenshots of the iPhone 13 simulator
(390 × 844 points, iOS 26.5). They are SwiftUI views, not web content or images
displayed inside the app. The explicit DEBUG-only `--fixture-live-design` client
feeds the fictional reference records through the ordinary app stores.

Revisions made after viewing the first native captures:

- Home: tightened metric spacing, matched the profile avatar size, aligned the
  friend row, quiet stake line and primary action with the reference.
- Goal: fixed the compressed status column and the large metric's vertical
  layout; all three verdict cards, timeline and actions fit the first screen.
- You: restored natural metric height and adjusted record-summary/card spacing.
- Shared controls: reduced over-prominent glass edges/shadows while retaining
  real iOS 26 material and solid accessibility fallbacks.
- Create: prevented step names breaking inside words; labels retain their
  intrinsic width, with vertical fallback for larger text. Removed the opening
  Type step; Goal → Challenge → Friends is the default. Advanced mode choices
  are restricted to generic entry; direct-policy and private-step entries keep
  their original gates.

The final independent visual review found no material layout mismatch or clipped
controls across the four main screens. Small differences remain in system status
indicators, SF Symbol stroke/shape and native font rasterization. The native Goal
summary also uses uniform secondary text instead of the reference's bold goal
prefix. These are not a claim of pixel-identical rendering.

## Locked tokens and deliberately preserved behavior

Background `#FAFBFC`; surface `#F0F2F5`; text `#111318`; accent `#245BFF`;
warning `#9A6700`; secondary text `#606975`. Light appearance, heavy tightly
spaced italic metrics, thick progress rails, rounded cards and restrained
materials apply throughout. Selected-control tint is `#F4F7FF`, adjusted so amber
text meets the existing contrast check without changing the locked base palette.

Production does not invent the mock's names, photos or totals. Challenge titles
derive from the available dates/activity and avatars use available names/initials.
The portrait atlas and named example records are selected only by explicit DEBUG
fixtures. Unknown activity stays unknown. Partial activity does not establish a
miss; production uses “In progress” where a lower pace cannot establish “Behind”.
The reference's amber Behind example is fixture-only.

Exact agreed targets, consent, simulated amount limits, allocation and review
rules are preserved, including rules that differ from design-example copy.
Creation starts at Goal, followed by Challenge and Friends. Other modes sit in
Advanced rather than an extra opening Type page. The existing friend agreement
still collects each person's target in the saved lobby; this differs from the
mock's early target field. The previously documented limits on arbitrary names,
address-book discovery, zero stakes and contact portraits also remain in force.
Private agreed leaderboard policies remain accessible only in their existing
contexts; the default path has no public leaderboard. Settings carries the
simulation/Health/account depth. No hosted schema, deployment, admission, payment
or exercise-source policy changed.

## Verification

Performed on the dedicated local iPhone 13 simulator; the existing phone and
its account container were not changed.

- Debug build and ordinary native simulator launch passed.
- Release simulator build passed, proving the default route compiles without
  DEBUG screenshot fixtures. Both builds retain one pre-existing
  `WeeklyModels.swift:275` trailing-closure warning.
- All six new `LiveDesignUITests` have passed across focused runs: all four native
  routes, progressive rules, creation entry, invitation review/unchecked
  consent/confirmed decline, onboarding/profile/sign-out, and Health/privacy/
  cancelled account deletion. After the final entry change, all **23** selected
  creation draft, recovery, rendered flow and app interaction tests passed with
  no failures or skips, including Goal → Challenge → Friends in the running app.
- Focused account/routing, creation, policy, live-presentation, theme-contrast,
  privacy restrictions, departure, overlapping responses, profile, Health and
  rendered-agreement regressions were exercised. Final rerun details follow below.
- `scripts/check-iphone-product.py` and `git diff --check` passed.

The [per-test ledger](verification-ledger.json) records the latest observed
outcome across this task's broad initial run and focused reruns: **595 passed,
10 skipped, no remaining failed current test names**. This is an aggregate,
not a claim that the full historical suite passed in one final run. The ten
skips require separately owned disposable backend/Health smoke controllers.
The earlier failed assertions and superseded test names remain in the ledger.
The three migrated authenticated creation UI suites still require their owned
local controller to execute; only the isolated six-test `LiveDesignUITests`
journeys were run here.

Final local evidence under
`~/Library/Developer/XcodeBuildMCP/workspaces/GameTime-7b9ccaa5aefb/`:

- Release: `logs/build_sim_2026-09-22T06-18-29-612Z_pid24251_5c2a7bab.log`.
- Final 23 creation checks:
  `result-bundles/test_sim_2026-09-22T06-20-40-885Z_pid24251_9d528216.xcresult`.
- Final Debug build/run:
  `logs/build_run_sim_2026-09-22T06-24-09-783Z_pid24251_db3b50ea.log`.

Earlier failing runs remain evidence, not passes: an initial broad unit run
exposed expectations tied to the retired UI, followed by focused migrations and
reruns. The retained tests now render the actual new views and preserve exact
targets, consent, privacy, final results and stale-response assertions. OCR checks
were corrected where Vision interleaved neighboring rank text with wrapped names;
the complete visible name is still checked. One UI test-runner launch returned a
simulator Busy/preflight error before any test executed; its subsequent rerun is
recorded separately.

The onboarding journey initially tapped a page button covered by the keyboard
despite XCTest reporting it hittable. The test now uses the real keyboard Done
submission and passes through saved profile, Account and sign-out. That simulator
launch also emits an unlocalized “Invalid frame dimension” warning. No failing
layout or negative custom frame was identified, and no speculative production
change was made for it.

### Limits

The historical full UI suite for retired Today/Personal tab and creation routes
was not declared passing or silently removed. The new app interaction suite and
migrated render/model tests cover the replaced routes. This task does not establish
human VoiceOver acceptance, physical-device material/performance acceptance,
hosted end-to-end completion, or wider Beta/release readiness. No new physical
installation was performed; the September 21 Staging installation remains the
last device receipt. The private phone/server trial remains Personal Apple Watch
steps only. No push or hosted action is part of this local UI rewrite.
