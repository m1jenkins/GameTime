# Implement the approved Signal creation experience

Work on GameTime in `/Users/user/Documents/GitHub/GameTime`. Implement the
Signal creation flow described below. I have already selected
Signal; do not create a new visual direction. Carry this through local
implementation, focused verification, documentation, commit and merge into
local `main`. Do not stop after proposing another plan. Do not push or deploy,
change hosted settings, or reinstall/relaunch my phone during my current test.

My main complaint: creating a personal goal feels like a spreadsheet with far
too much writing. Use visuals, large editable numbers and buttons. Keep the
Signal design. Do not just split the same wall of text over several screens.

Use `$unslop` at `/Users/user/.codex/skills/unslop/SKILL.md` for new app copy and
the handoff. Mobbin is available if a specific input or selection interaction
needs a reference; keep it secondary to Signal and inspect the actual images.

My Lavish feedback on the first proposal: “I like this but it's a little plain,
no liquid glass.” Keep the simpler flow, and give the controls the Liquid Glass
depth shown in Signal. A flat blue button is not enough.

## Context and authority

While creating a personal goal in the ordinary Staging app, I found that it did
not look like the Signal experience we approved. Investigation confirmed that
Signal is already the normal native theme, but `ChallengeV1Create` still uses
one long form where the approved reference has a guided five-stage flow.
The creation screen's layout and navigation differ from the reference. Do not assume it is an old
build, a Cobalt theme switch or a request to change the palette again.

Read `AGENTS.md` and its required files, especially `docs/WORKING_BASELINE.md`,
the latest `DECISIONS.md`, `docs/COPY.md` and
`docs/design/SIGNAL_UI_FIDELITY_PLAN.md`. Design authority is:

- `docs/design/SIGNAL_UI_MIGRATION.md`
- `outputs/design/2026-09-13-clickable-app-alternate/DESIGN.md`
- The current `index.html`, `signal.js`, CSS and `LIQUID_GLASS_REVIEW.md` in that
  same directory. Render and inspect the reference; dated screenshots can be
  older than its later refinements.

Its fictional values, product rules and browser chrome are not production
requirements. Preserve current adopted rules and exact historical agreements.
Use the relevant iOS visual-design, SwiftUI and native verification skills.

## Start without disturbing current work

Inspect status, branches and current local `main` first. At handoff,
`codex/private-goal-consent` at `7bca11c` had uncommitted native/backend fixes for
goal review and activity readiness. Local `main` separately reached `dbc769c`
with D141 received-score leaderboard work. These are dated observations, not
instructions to reset to either commit. Re-read their latest state.

Use a short-lived `codex/` branch from current main. Preserve dirty work and
coordinate through an isolated worktree if necessary. Do not reset, stash,
overwrite or commit another task's changes. Integrate accepted phone fixes
before final verification; keep current readiness/recovery behavior and D141's
version distinctions. Do not blindly restore the older blanket leaderboard ban.
Independent reference/component work can proceed while another task finishes.

## Implement the flow

First capture the current native creation/review/detail with fictional local
data and compare them with the current Signal reference. Audit Home, Challenges,
You, shared friend creation, invitations/community entry and retained Existing
challenges. Record matches, concrete mismatches and unverified routes; prioritize
the full new Personal journey. Do not claim unrelated routes match without
looking at them or silently expand into a product/architecture rewrite.

Replace `ChallengeV1Create`'s long form with five native stages:

1. **Type:** accessible full-width choice buttons. Generic Create includes this
   stage; direct Personal entry skips this answered question and shows progress
   for the remaining four stages. Preserve current mode/version availability.
2. **Activity and goal:** activity buttons and a large editable goal number with
   its unit/period, optional deliberately selected suggestion, and timed-run
   distance where needed. Do not invent a target default from the mockup.
3. **Dates:** large duration, calendar, readable time zone and start/end span using existing
   full-local-day/server-time semantics.
4. **Amount:** large editable dollar value with the current default/range and
   the short simulation disclosure. Avoid amount upsells and precision sliders.
5. **Review:** visual summary, complete rules behind a named disclosure, activity status,
   explicit unchecked consent and the clear final creation action.

Ordinary steps should need only a short heading, control labels and at most one
brief helper sentence. Show explanation on demand or when an error needs it.
Use a large editable number with native numeric entry and accessible controls;
keep precise entry for every valid value. Replace the raw `Area/City` field
with a readable zone selector while preserving valid choices and exact IDs.
Keep one obvious primary button, usable Back/Close and simple progress. Never
hide consent-critical facts, source limits or error recovery to hit a text quota.
Do not make the review another spreadsheet or expand every rule by default.

Use one stable draft owner across child steps. Preserve choices when going
back, initialize defaults once, and make dependent-field resets explicit.
Do not run whole-flow cancellation when an individual step disappears.
Keep actor/session/draft fencing and ignore stale async responses. Changes to
agreed details must invalidate preview/consent and the readiness context required
by the current accepted Health implementation. Browsing/permission completion
never supplies consent. Retain current date/amount defaults and validation.

Reuse `SignalTheme`, existing native controls and semantic typography. Match
the reference's hierarchy, alignment, open rows, action emphasis and appropriate
materials. Keep facts/rules/plots opaque, retain approved accent bands, and
preserve supported older-iOS solid fallbacks. Every step needs accessible Back,
Close and one clear advancing action. Handle keyboard and large text properly.

Make the glass treatment explicit: circular Back/Close and adjustment buttons;
one glass group for activity choices with a clear selected inset; a blue-tinted
glass capsule for Continue/final creation; and untinted secondary actions.
Keep numbers, date facts, rules, consent and charts on solid backgrounds.
Do not add blur to the whole screen or layer glass on every content block.

Use the Liquid Glass skill and Apple's current guidance. Prefer system bars and
iOS 26+ `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)`; custom controls
can use `glassEffect` after layout and `GlassEffectContainer` for related effects.
Reuse the Signal components and keep interactive effects limited to controls.
Browser CSS is an appearance sketch, not the native implementation. Retain
matching solid geometry on older iOS, Reduce Transparency and Increase Contrast,
and respect Reduce Motion. Capture native glass and solid versions of the same
screen; labels and selected states must remain legible in both.

Keep all detailed agreement information accessible, including source meaning,
exact dates/time zone, simulated amount/outcomes, exit and review rules.
Preserve consent wording and server contracts. Errors must retain input and
give an actionable next step. Use `docs/COPY.md` for every changed string.

After accepted server success, show the recorded goal, scheduled/active status
and a route to its detail using existing receipt/model data. Correct confirmed
Signal mismatches in connected Personal confirmation, detail, review/history
and shared creation components. Never invent activity, a successful save, a
balance or a missing-data loss to match a mockup. Preserve safe exits, privacy,
historical Personal/Solo/charity access, and pending exact-request recovery.

Likely native files include `ChallengeV1EntryViews.swift`, `ChallengeV1Views.swift`,
`SignalChallengeViews.swift`, `SignalTheme.swift`, `ChallengeHealthViews.swift`
and `AppShellView.swift`. Inspect actual callers and tests before splitting
views. Reuse stores/clients; avoid a parallel flow or new theme flag. This task
does not authorize backend/schema changes, new Health permissions, policy or
consent versions, transport-gate changes, payments or historical data cleanup.

## Verify what a person actually sees and does

Build Debug, Staging and Release simulator products and run
`scripts/check-iphone-product.py`. Extend/adapt focused `ChallengeV1UITests`,
`ChallengeHealthSignalUITests` and relevant units. Preserve assertions while
updating navigation and identifiers. Use existing fictional ordinary-app/Health
journeys and an owned disposable local stack only when needed.

Verify all four Personal metric inputs; Back/value retention; invalid input;
review after edits; consent reset; stale preview/account-switch responses;
activity failure/retry; and duplicate/pending submissions using existing exact
recovery. Smoke shared friend creation/current policy versions and retained
access. Do not reset another checkout's database or submit my real goal.

Capture and inspect the entire flow and saved detail: standard light/dark,
compact width, large accessibility text, keyboard open, supported iOS 18 solid
fallback, and relevant reduced-transparency/contrast/motion states. Include
loading, unavailable/denied activity, retry and pending/saved states. Check
accessible selection/progress, focus order, 44-point targets, clipping and safe
areas. Separate automated evidence from unperformed human VoiceOver checks.

Compare native screenshots beside the matching current Signal reference with
comparable content. Explain justified native or policy differences. A renamed
component, changed palette, passing tests or preview screen is not sufficient.
Reject the result if ordinary creation still reads like a form full of paragraphs:
the current decision, chosen value and next button must be obvious at a glance.
Use focused checks; do not run the full historical weekly/release/backend matrix
unless an actual change or failure requires it.

## Finish and hand off

Produce a dated report with source identity, before/after native screenshots,
reference comparisons, commands/results, failures, remaining route gaps and
unperformed physical/human checks. Update the Signal migration record honestly
without rewriting its historical results. Commit your completed authorized
work, integrate concurrent accepted fixes, rerun affected checks and merge into
local main. Retire the temporary worktree after preserving its artifacts.

Prepare an identifiable corrected Staging build for a coordinated in-place phone
update. Preserve the phone's container, account, saved goals and pending requests;
do not uninstall or interrupt my current session. Report when the build is
ready, and do not claim it is installed until that action is actually performed.

Finish with what changed, which screens were visually verified, remaining gaps,
the local main commit and the build status. Call this locally complete only
when the staged creation and connected Personal journey match the adopted
design, consequential behavior is preserved and shared routes pass regression
checks. Keep device/human acceptance and any unreviewed routes explicit.
