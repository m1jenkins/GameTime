# Signal UI adoption and cobalt retirement

Owner direction, September 13, 2026: **Signal is GameTime's official UI/UX
design language. The crisp cobalt look is deprecated and must be fully replaced.**
This supersedes the September 11 cobalt design selection for future work.
The adoption below remains the implementation contract. The subsequent local
execution and its verification are recorded separately here.

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

## Source and current implementation

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

## Required native migration

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

## Scheduling and completion

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
