# GameTime UI adoption and migration history

## Locked mock adoption and native rewrite — September 22, 2026

The owner adopted the Home, Goal / Rules, Challenges, You and create/invite
mockups from the September 21 study as the current app presentation, and
authorized a complete native UI rewrite with screenshot comparison and revision.
Use the [approved study](../../.lavish/gametime-live-goal-2026-09-21/README.md)
and the [native implementation record](../../.lavish/gametime-native-live-2026-09-22/IMPLEMENTATION.md)
for this direction. The implementation record owns the actual captures,
comparison iterations, validation results and remaining limits; this adoption
entry does not establish final verification or release acceptance.

The current visual contract is **cool athletic light**: background `#FAFBFC`,
card surface `#F0F2F5`, text `#111318`, accent `#245BFF` and warning `#9A6700`.
Use heavy, tightly spaced athletic metrics with secondary units, rounded cards,
thick progress, thin system symbols and restrained material. The app uses light
appearance. This expressly supersedes the September 13 cobalt-retirement and
non-italic/light-and-dark typography instructions below **only where they
conflict with this exact adopted palette, athletic type and light-only direction**.
It does not restore the former cobalt UI, its fonts or its compositions. Earlier
dated migration entries and studies remain historical evidence, not alternative
themes or authority to replace the approved mockups.

Current source wiring is explicit:

- [GameTimeApp.swift](../../ios/GameTime/GameTime/GameTimeApp.swift) selects the
  new launch, sign-in and profile-entry views. The `SignalProductShell` adapter
  in [AppShellView.swift](../../ios/GameTime/GameTime/AppShellView.swift) mounts
  [LiveChallengeShell](../../ios/GameTime/GameTime/LiveChallengeShell.swift) for
  ordinary signed-in use, with Home · Challenges · You and secondary Settings.
- Shared tokens and components live in
  [SignalTheme.swift](../../ios/GameTime/GameTime/SignalTheme.swift) and
  [LiveDesignComponents.swift](../../ios/GameTime/GameTime/LiveDesignComponents.swift).
  Goal details and progressive rules use `LiveGoalDetail` and `LiveGoalRules`;
  the record uses `LiveRecordView`. Creation, invitations, community entry,
  consent, activity, review, results and recovery use the new presentation with
  their existing clients and actions.
- Account, privacy, support and deletion use `LiveSettingsView` and the new
  account-entry views. Earlier Personal agreements remain available through
  `LivePersonalHistoryView` / `LivePersonalDetailView`; retaining their data and
  actions does not select the former Personal tab UI.

This is presentation work. No backend, admission, source policy, consent version,
allocation, review window or money gate is changed by the mock adoption. Exact
agreed targets, stakes and saved agreement rules remain authoritative, including
historical allocation rules that differ from a design-only example. Production
titles derive from available challenge dates/activity, and avatars use available
account names or initials. The named sample challenges, portraits and record
values belong to the explicitly selected DEBUG screenshot fixtures, not to a
live account. No physical-device installation is performed in this rewrite
task; the previously installed Staging receipt remains the device record until
a separately recorded installation.

## Original Signal adoption — September 13, 2026 (historical)

Owner direction, September 13, 2026: **Signal is GameTime's official UI/UX
design language. The crisp cobalt look is deprecated and must be fully replaced.**
This supersedes the September 11 cobalt design selection for future work.
This was the implementation contract for the dated migration below. The
September 22 adoption above controls the current visual presentation. Subsequent
local execution and its verification remain recorded separately here.

## Create and invite visual follow-through — September 21, 2026

The owner's subsequent create/invite study is connected to native creation,
invitation and confirmation routes. This scoped pass adopts its neutral metric
cards, athletic numbers and SF Symbols. Confirmed friend creation now opens
invitations directly; Personal still requires its existing reviewed agreement
and explicit consent. Exact username and durable link invitations reuse existing
clients. The [native integration record](../../.lavish/gametime-live-goal-2026-09-21/NATIVE_CREATE_INVITE.md)
separates implemented behavior, design-only assumptions, captures and verification.
The existing product gates, target ownership, amount rules, allocation and final
roster consent remain in force.

## Native interaction and profile follow-through — September 21, 2026

The owner’s installed-build feedback supersedes the five-stage interaction below.
Direct Personal creation now has **Goal & dates → Review**. Generic creation adds
Type only when needed. Dates and duration sit beside exact goal entry; compact
editors handle dates, zone and the simulated amount. Suggestions require a separate
choice. Existing defaults, precision, consent and request recovery remain intact.

Home leads with a saved goal. Challenges uses Active / Upcoming / Finished,
keeps attention above the filters and groups records by product. Detail, shared
lobbies, community entry, results/review and retained agreements use the same
open rows, opaque facts and native controls. Settings are secondary to identity
and saved goals in You.

The ordinary profile now reads `ChallengeV1Store`; retained Personal continues
to use its own store. The [profile data contract](SIGNAL_PROFILE_DATA.md) defines
record scope, pagination, freshness, account clearing and finalized competitive
results. Unsupported lifetime activity and streaks remain unavailable; no new
Health access or activity aggregation was introduced.

The [dated native report](../../outputs/reports/signal-native-2026-09-21/REPORT.md)
records the actual final checks, captures, source, prepared Staging product,
failures and remaining limits. Earlier migration statements below retain their
dated scope; they are not evidence that the installed feedback was already fixed.
Physical-device presentation, human VoiceOver/comprehension and release acceptance
remain separate. This task does not install the prepared build on the phone.

## Staged creation implementation — September 20, 2026

The authorized implementation now replaces `ChallengeV1Create`'s long form with
Type, Activity and goal, Dates, Amount and Review. Direct Personal entry skips
Type; the private Staging configuration retains its Personal steps restriction.
Large precise inputs, readable time zones, native glass controls, opaque goal
and date facts, collapsed complete rules and unchanged explicit consent are
implemented in the ordinary app. Saved confirmation uses the accepted receipt
and recorded challenge. Shared detail uses the same readable date span.

The [dated implementation report](../../outputs/reports/signal-creation-2026-09-20/REPORT.md)
records source identity, current-reference/before/after captures, tests, build
identity and the surrounding-route audit. It preserves the accepted phone fixes,
D141 policy versions, exact pending recovery and all existing agreements. No
backend, permission, transport or money gate changed. Broader Challenges-list
composition, complete invitation/community journeys, human VoiceOver and
physical-device acceptance remain explicit gaps. The corrected Staging build
is prepared separately; this task does not install or relaunch it on the phone.

## Fidelity follow-through planning — September 20, 2026

The owner reported that ordinary Staging personal-goal creation did not resemble
the approved Signal experience. At the time of planning, source inspection confirmed a remaining
interaction/composition gap: `ChallengeV1Create` presents one long form, whereas
the approved browser reference presents five guided stages. This does not
invalidate the theme migration or its dated checks below, but those results
do not establish complete fidelity to every approved journey. The owner's
current device screen was not independently captured during this inspection.

The [fidelity plan](SIGNAL_UI_FIDELITY_PLAN.md) and
[implementation prompt](../SIGNAL_UI_FIDELITY_IMPLEMENTATION_PROMPT.md) define
the proposed native follow-through, shared-route audit and rendered acceptance.
They are planning artifacts; the planning task did not implement or verify the
staged flow. Its instruction to preserve in-flight device fixes and later
adopted policy versions remains part of the implementation contract.
The owner's follow-up asks for large numbers, visual choices and buttons with
much less writing, using `unslop` for copy while retaining Signal. The plan
includes those requirements and skips choices already made by a direct entry.
Lavish feedback asks for more visible Liquid Glass on the controls. The revised
plan specifies native glass for navigation, selection and primary actions,
with solid content and accessible fallbacks. Its browser approximation does
not establish native material acceptance.

## Local execution — September 13, 2026

**P9A is implemented and locally verified.** Native source, tests and configuration
are published on `main` at `b351a47`, based on `b25834c`. The complete migration
was originally committed at `823ee0a` on `codex/signal-native-migration`;
supporting documentation/evidence was later committed through `885e8ad` and is
included in published main at `1dacc66`. The redundant local branch was pruned
on September 15; the [executed disposition](../HISTORICAL_BRANCH_DISPOSITION_20260915.md)
records incorporation and retained evidence.
Ordinary launch and reachable new/retained routes now use native Signal;
superseded cobalt rendering, decorative components and bundled fonts are removed.
See the [native migration report](../../outputs/reports/2026-09-13-signal-native-migration.md)
for source hashes, route coverage, screenshots and preserved failures.

Verification passed: 76 focused checks on iOS 26.5, 13 on iOS 18.6, and two
affected receipt journeys after the final large-text refinement. Debug, Staging
and Release simulator products build. These are local presentation results;
P7 source acceptance, P9 real integration and P12/P13 physical/human/release
qualification remain separate. No hosted, Health-upload or money gate changed.

## September 13 source and implementation contract (historical)

Use the existing [Signal design system](../../outputs/design/2026-09-13-clickable-app-alternate/DESIGN.md),
[clickable study](../../outputs/design/2026-09-13-clickable-app-alternate/index.html)
and [material review](../../outputs/design/2026-09-13-clickable-app-alternate/LIQUID_GLASS_REVIEW.md)
as the visual reference, including its refined invitations, agreement and personal
goal screens. Its fictional data, browser-only behavior and verification limits
remain as recorded. Adoption does not make its sample rules or values product policy.

Before this migration, inspection of local `main` at `b25834c` found:

- `GameTimeApp.swift` selects `CobaltProductShell` for ordinary signed-in use.
- `CompetitiveTrustTheme.swift` still defines cobalt colors, Barlow Condensed
  display type and shared components used across new and retained screens.
- `CobaltChallengeViews.swift` implements the cobalt header, feature panels,
  participant rows, metric typography and navigation material.
- Signal's committed implementation is HTML/CSS/JavaScript. An earlier planning
  note reported native completion, but that source has not been verified here.

Inspect available native work once and reuse any verified applicable changes.
If no native Signal candidate exists, implement the missing presentation from
the adopted study. An unlocated candidate must not block this work indefinitely.
Class names alone do not prove a visual migration; renaming cobalt is insufficient.

## September 13 native migration requirements (historical)

1. **Foundations:** introduce Signal semantic colors for light/dark appearance,
   system typography with tabular metrics, open aligned rows and spacing.
   Replace cobalt's condensed italic display treatment and old component styling.
   Keep blue: Signal has its own blue family. Match the adopted compositions,
   including opaque accent bands where specified, rather than banning all blue panels.
2. **Controls and charts:** keep totals, plots, histories, rules, consent and
   results opaque. Translate navigation, capsules, segments and selected-day
   readouts to native controls/materials with solid fallbacks on supported OS
   versions. Preserve geometry, selection, accessibility and reduced motion.
   Browser dimensions and CSS blur are references, not native implementation.
3. **Every reachable route:** migrate launch, sign-in, onboarding, Home,
   Challenges, You, all friend/personal/community creation and detail flows,
   invitations, consent, progress, correction, review, results, history,
   Health status, privacy, support, deletion and safe exits. Include sheets,
   loading, empty, unavailable, offline and error states. Keep retained Personal
   routes usable and restyle their presentation without changing agreements or
   historical consent; their eventual product retirement has separate acceptance.
4. **Default wiring and cleanup:** make ordinary app launch use Signal without
   a preview or opt-in flag. Update previews and relevant tests to the same
   presentation. Remove superseded cobalt rendering, unused tokens/fonts/assets
   and active build references after checking all consumers. No selectable cobalt
   theme or fallback may remain. Preserve dated evidence and archive references.
5. **Verify and record:** build the affected native app; run focused rendering
   and journey regressions on the final source. Capture ordinary signed-out and
   signed-in routes, compact/large text, light/dark and solid/reduced-motion states.
   Check the nine goal policies and four unavailable leaderboard states,
   two/six-person layouts, long rules, unknown/missing data,
   account transitions and retained Personal access. Record source identity,
   route coverage, actual results and any unperformed device/human checks.

Read [COPY.md](../COPY.md) before changing app text. Reuse stores, routes,
authentication, privacy, consent, retries and lifecycle rules. Charts may show
only authorized available data; missing daily values stay unknown. Do not widen
Health uploads or friend visibility to reproduce a study timeline. Preserve
simulation labels, neutral exits and responsible-engagement requirements.

## September 13 scheduling and completion (historical)

**P9A — Signal native migration** is independent of P7 physical source acceptance
and hosted configuration. Implement and verify presentation against existing
closed clients and explicit local fixtures while those dependencies are pending.
P9 then connects Signal to accepted real contracts. P12/P13 qualify the integrated
candidate and complete required physical/accessibility/human acceptance.

Cobalt retirement is complete only when the default native app and every
reachable route use Signal, obsolete styling/build inputs are removed, and
affected regressions pass. A browser preview, renamed class, sign-in screenshot
or changed palette alone does not satisfy acceptance. The local execution above
satisfies the presentation migration; it does not enable transport or establish
release readiness.
