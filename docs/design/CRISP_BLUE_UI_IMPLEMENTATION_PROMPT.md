# Implement GameTime's crisp cobalt design across the iPhone app

> **Superseded September 13, 2026.** Signal is the official UI/UX and cobalt is deprecated. Do not execute this historical prompt. Use [Signal native migration and cobalt retirement](SIGNAL_UI_MIGRATION.md).

You are the SwiftUI implementation owner for GameTime. Turn the approved v2 home-screen concept into a coherent, fully functioning native UI across every app-owned iPhone screen and reachable state. Implement the work, run the app, exercise its flows, and iterate on rendered results. Do not stop after a plan, a token change, a component gallery, or the Home screen.

## Visual authority and project context

The approved visual reference is:
`/Users/user/Documents/GitHub/GameTime/output/imagegen/gametime-home-crisp-blue-v2.png`

Inspect the actual image before coding. Its reference notes and generation prompt are alongside it. Bring a copy into the implementation checkout's design documentation so the handoff is portable. This image establishes visual direction, not production data, API shape, or fixed screen coordinates.

Read the applicable AGENTS.md, then PROJECT_MEMORY.md, CLAUDE.md, docs/COPY.md, the current Beta implementation plan, and the latest acceptance/handoff documents. Use `CRISP_BLUE_UI_SCREEN_MATRIX.md` alongside this prompt as the starting inventory; update it against the checkout actually selected.

The direction is adopted: small-group friend challenges and personal performance commitments. Use the approved cobalt concept rather than restarting visual exploration or returning to the previous orange/green or pastel card-stack designs.

## 1. Resolve the implementation baseline before editing

The original workspace has extensive unrelated uncommitted changes and an older app shell. Do not assume it is the newest implementation or reset, stash, overwrite, or absorb its changes indiscriminately.

Read-only inspection on September 11, 2026 found:
- Original workspace: `/Users/user/Documents/GitHub/GameTime`, main at `577bc32`, dirty.
- Newer local Beta checkout: `/Users/user/.treehouse/gametime-beta-7b9cca/2/gametime-beta`.
- That checkout was clean on `fm/gametime-beta-real-validation-c8` at `9c84459`, a descendant of `9ce9ea6`.
- It includes `ChallengeV1Shell`, `ChallengeV1Store`, the new challenge models/clients, all thirteen local fictional policies, and subsequent privacy corrections. Review/landing gates in its handoff are still distinct from code availability.

Recheck this information; it is a dated observation, not permission to declare the candidate accepted. Locate any newer canonical descendant and use an isolated `codex/` worktree or checkout from the resolved base. Record the exact starting commit and any intentional carried changes. Preserve the original dirty checkout, retained candidate, active Simulator, controller, and databases. Do not rebuild the old shell merely because it is the current directory.

If the correct candidate cannot be established, finish the read-only inventory and identify the exact baseline question. Otherwise proceed autonomously with local UI implementation. No deployment, merge, distribution, database reset, or external service activation is implied.

## 2. Define the visual system before migrating screens

Visual thesis: an athletic, precise interface with expressive numbers, a decisive cobalt feature area, open white content, and familiar native controls.

Use the image as the principal reference. Make these rules reusable:
- White/near-white canvas; ink text; cobalt as the dominant brand accent; cool-gray metadata, separators, avatar backgrounds, and progress tracks.
- Starting light values: canvas #FAFBFD, surface #FFFFFF, ink #101724, secondary text #526176, cobalt #244DE6, pale selection #EAF0FF, track/divider #E1E7F0. These are implementation starting points; tune actual rendered contrast and match the approved image.
- One dominant visual focus per screen. Reserve broad cobalt panels for an active challenge or similarly important object. Forms, settings, rules, and disputes remain quieter.
- Heavy condensed/slightly oblique display type for the wordmark, selected feature titles, and a few important metrics. Upright, highly readable type for names, navigation, body copy, form labels, rules, and dates.
- Tabular numerals for changing totals, scores, and aligned rankings. Always associate numbers with their metric and unit.
- A four-point spacing rhythm; approximately 20–24-point phone margins; generous separation between sections. Heights grow with content.
- Restrained content corners, approximately 12–16 points; thin dividers and open sections instead of enclosing every element in a card. Progress bars have a flatter profile, around 2–4-point corners.
- Initials/monograms only. Use a subtle You treatment plus a non-color cue. Keep departed or redacted identities redacted.
- Quiet running-track line decoration only where it supports the feature composition. It carries no data, has no interaction, and is hidden from accessibility.
- No neon, trophies, streaks, confetti, generic runner icons on every card, pressure language, decorative trading charts, or financial spectacle.

Name tokens by purpose: canvas, textPrimary, textSecondary, brand, onBrand, selection, divider, progressTrack, error, warning, success. Keep status colors semantically distinct and restrained, with text or symbols; cobalt must not become the sole indication of every outcome.

Inspect and reconcile existing `CompetitiveTrustTheme`, `Daybreak*`, `Athletic*`, `Trust*`, and `Matchday*` helpers. Establish one coherent source of truth. A temporary compatibility layer is acceptable during migration; remove obsolete active styling once consumers are migrated. Do not merely change orange aliases to blue while retaining every old composition.

Inspect bundled fonts and their licenses/registered names. Use Dynamic Type-aware system condensed typography where it fits; bundle a suitable licensed font only if necessary for the approved display character. Verify actual glyph rendering, number widths, weights, and italic support. Never stretch text with transforms or silently accept a fallback font. Do not ignore a `relativeTo` parameter in a font helper. Body/rules copy must remain native and readable.

The concept is light mode. Deliver that reference faithfully while preserving readable system dialogs, keyboard, and existing supported appearance behavior. If the product remains intentionally light-only, retain that choice consistently; if it already supports dark appearance, provide and verify semantic dark equivalents. Do not silently drop an existing supported mode or treat a dark exploration as another approved design.

## 3. Build reusable, functioning components

Implement shared components with real states, not screenshot-only views:
- Screen container, page header/wordmark, section heading, and toolbar actions.
- Featured challenge summary, ranked participant row, initials avatar, and secondary challenge row.
- Personal metric/goal progress and upcoming-goal row.
- Form section, labeled input, metric selection, date/window selection, numeric entry, primary/secondary/destructive button treatment.
- Rules/consent summary with full terms access, pending action/recovery notice, result/review presentation.
- Loading, empty, partial, stale, error, unavailable, and redacted content treatments.

Use standard SwiftUI navigation, sheets, menus, controls, focus, keyboard, and dismissal behavior where possible. Preserve accessibility identifiers or update their tests deliberately. Button styling must retain pressed, disabled, loading, selected, destructive, and accessibility states.

The inspected deployment target is iOS 18. Preserve it unless current project authority says otherwise. Use actual supported Liquid Glass APIs for iOS 26+ controls/navigation, with an iOS 18 fallback. Verify APIs against current Apple documentation and the installed SDK. Prefer native bars; only keep custom navigation when its existing behavior has a concrete need, and verify tab semantics and accessibility.

Keep glass on the navigation/control layer. Challenge, progress, rules, and result content stays opaque. Use proper safe-area layout and scroll clearance; do not hard-code the screenshot's tab-bar height or reproduce its status bar/Dynamic Island in app content. Respect Reduce Transparency and Reduce Motion.

## 4. Migrate the entire screen and state inventory

Create/update a tracked inventory of every reachable route, modal, form step, menu, alert, and conditional screen. Inspect runtime routing and view composition, not filenames alone. Classify each as active Beta, reachable legacy, internal tool, system/provider-owned, or planned/unavailable.

Migrate foundations first, then Home and shell, challenge browsing/detail, creation/lobby/consent, results/review/recovery, and account/Health/privacy/support. Bring still-reachable legacy screens into the same visual language while preserving their historical semantics. Internal diagnostic tools need legible consistent styling, not a new consumer product. There is no new watchOS app in this task.

For each inventory row record: source/route, applicable states, required interactions, implementation status, screenshot evidence, test evidence, and any explicit external dependency. No silent omissions. System-owned Apple/Health/payment dialogs retain their platform UI; style and verify the app-owned handoff around them.

Home should express the v2 hierarchy when its data permits:
1. Actionable consent/review/recovery items when present.
2. Featured active friend challenge with readable standings.
3. Personal progress.
4. Upcoming goal.
5. Other supported sections and history.

Do not bury urgent server-projected actions merely to reproduce the idealized mockup. Keep a clear primary focus and preserve the server's action ordering. At ordinary text size the three sample sections should fit on a representative phone; at accessibility sizes allow scrolling and reflow.

## 5. Wire real behavior and preserve product semantics

Use the selected checkout's existing stores, typed models, client protocols, authentication, request recovery, and server projections. The new Beta code is concentrated in `ChallengeV1Views.swift`, `ChallengeV1EntryViews.swift`, `ChallengeV1Sections.swift`, `ChallengeV1Models.swift`, `ChallengeV1Policy.swift`, `ChallengeV1Store.swift`, `ChallengeV1Client.swift`, and `ChallengeInvitation.swift`; verify current locations.

All visible actions must work through the proper existing boundary: navigate, edit, validate, submit, refresh, retry, dismiss, or explain a genuine unavailable prerequisite. No dead buttons, local-only success toasts for failed mutations, decorative pickers, fabricated contacts, or fake production data.

Preserve:
- Friend goals versus target-free friend leaderboards versus personal goals versus private community goals.
- All four metrics and their actual parsing, normalized units, comparisons, and rounding. A timed running goal is not an ordinary cumulative-distance bar.
- Two-to-six friend capacity for the new contract; do not reinterpret older two-to-five weekly agreements.
- Per-person target proposal, creator roster selection, immutable agreements, and fresh explicit consent after terms change.
- Frozen window/timezone semantics, actual server deadlines, ties/co-winners, review and correction history, and safe exits.
- Missing/unknown activity as unknown, never zero or a loss. A successful Health request does not establish reading permission or completeness.
- Actor-bound data, background redaction, expiry fences, partial departure redaction, blocked/removed counterpart hiding, own-history access, and stale-response protection.
- Server freshness checks, in-flight action handling, exact request identifiers, durable retry/abandon behavior, and interrupted navigation recovery.
- Privacy-minimized community data; do not turn it into a public friend-style leaderboard or expose unsupported counts.
- Required test/simulation disclosures and exact consequential consent/payment copy. The mockup's omission of money does not authorize removing contractual disclosures from real flows.

Sample data belongs only in clearly isolated previews or fixtures. Derive names, totals, dates, target ratios, selections, and state from real models. Reuse the approved example to compare visuals: Maya 42,850 steps, You 38,620, Jordan 35,400; personal 95 of 150 min; dates Sep 7–13 and Sep 14–20. Compute 95/150 rather than hard-coding 63%.

This is UI implementation and integration with existing capabilities. Do not redesign the backend, invent new policies, enable live money, remove feature gates, activate hosted services, or claim physical Health acceptance. If a required capability is genuinely absent, make its status honest, record the dependency, and finish independent UI work. Existing functioning local journeys remain usable; unavailable integrations cannot be represented as complete.

## 6. Execute in reviewable phases

Produce one dependency-aware plan, then execute it. Suggested phases:
1. Baseline, screen/state inventory, before screenshots.
2. Tokens, typography, shared components, native navigation/material behavior.
3. Home plus a representative friend leaderboard and personal goal, rendered against v2.
4. Creation, lobby, invitation, roster/target proposal, consent, and community entry.
5. Active details, results, review, recovery, account, Health, privacy/support, and all remaining reachable legacy/edge screens.
6. Full visual/interaction verification and cleanup.

If using parallel agents, first finish shared foundations and assign nonoverlapping file ownership. One coordinator owns the theme, app shell, integration, Simulator, and test controller. Do not let workers create independent visual systems or drive the same Simulator concurrently.

Do not stop after the first phase or an attractive demo path. Keep the screen matrix current until every in-scope screen has been implemented and verified, or an exact external blocker has been documented.

## 7. Verify rendered UI and functioning journeys

Use the installed iOS build/debug tooling. Discover current schemes and available simulators. The inspected candidate has `GameTimeBetaLocal` and a `--beta-challenges-local` launch path; these are useful starting points, not authorization to reuse its retained controller or database. Read the candidate's runbooks, choose an owned disposable verification setup, and use a separate DerivedData directory.

Build the relevant Debug/Beta scheme plus Staging and Release to catch shared-style regressions without opening release gates. Run existing relevant native, routing, privacy, and UI tests, including current equivalents of `ChallengeV1NativeTests`, `ChallengeSectionTests`, `ChallengeV1NativeSmokeTests`, `ChallengeV1UITests`, and affected legacy suites. Do not count controller-dependent skipped tests as passed.

Exercise complete supported journeys:
- Two- and six-person creation, invite, target proposal where applicable, freeze, independent consent, active progress, and final/review/exit.
- Target-free leaderboard creation and detail; all four metric representations and ties/unknown results.
- Personal creation, invalid input, review/consent, progress, upcoming state, and result.
- Community catalog/join/detail with correct privacy.
- Cold/warm invitation handling, sign-in/age prerequisite, stale/expired/revoked/full links, cancellation and recovery.
- Interrupted requests, retry/abandon, partial refresh failure, account switching, redaction, and foreground/background changes.
- Available account, Health, reporting/blocking, privacy/support, and destructive confirmation paths.

Verify screenshots and interactions on a compact iPhone and representative current iPhone, default and accessibility Dynamic Type, supported appearances, Increase Contrast, Reduce Transparency, and Reduce Motion. Test long names, long localized text, large values, empty lists, and three/six participant rows. Check keyboard avoidance, focus order, VoiceOver labels/values, tab selection, back gestures, dismissal, and minimum 44-point touch targets.

Use meaningful regression tests for behavior and risky adaptations; do not replace useful tests with assertions that merely mirror new implementation details. Automated audits support, but do not replace, visual inspection. Do not filter out audit failures to obtain a green result.

## 8. Deliver

Finish with:
- Functioning SwiftUI code and integrated screen coverage.
- A short design-system document with actual token/type/component decisions.
- A completed screen/state matrix, including explicit limitations.
- Native Simulator screenshots of Home, leaderboard/detail, creation, consent, personal progress, results/review, You, and representative adverse/accessibility states.
- Exact build/test commands and outcomes, with failures/skips or unperformed checks reported honestly.
- A concise summary of what changed and any remaining external dependencies.

No mockup-only completion, no theme-only completion, and no claim that the new Beta is ready for distribution because a UI build passed.

## Design references

- Approved v2 image above is the primary visual authority.
- [Nike Run Club activity typography](https://mobbin.com/screens/990cfe5c-7b29-4608-a26f-6797264cf2fd).
- [Strava ranking clarity](https://mobbin.com/screens/f1396c9f-c085-434e-b1d6-bdde6a259bfe).
- [Apple: adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).
- [Apple: Dynamic Type with custom fonts](https://developer.apple.com/documentation/swiftui/applying-custom-fonts-to-text).
- [Apple: font width](https://developer.apple.com/documentation/swiftui/font/width).

Use the iOS visual-design, SwiftUI patterns, Liquid Glass, and Simulator/debugging skills where available. Keep the work centered on the approved design and the app's actual behavior.

