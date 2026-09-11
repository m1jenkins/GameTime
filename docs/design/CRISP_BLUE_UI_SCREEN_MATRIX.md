# Crisp cobalt UI — screen and state coverage

Prepared September 11, 2026. This is an implementation starting inventory, not a completion report. Use with [the implementation prompt](CRISP_BLUE_UI_IMPLEMENTATION_PROMPT.md).

The primary inventory was inspected in the clean Beta checkout at `/Users/user/.treehouse/gametime-beta-7b9cca/2/gametime-beta`, commit `9c84459`. The original workspace remains on the older shell at `577bc32` with unrelated dirty work. Recheck the current canonical implementation and all routing before assigning work. Source filenames below are under `ios/GameTime/GameTime/` unless stated otherwise.

Every listed family starts **unmigrated/unverified for crisp cobalt**. Copy the tables into the implementation ledger and add columns for owner, implementation status, screenshot, interaction/test evidence, and blocker. Expand composed screens into their actual conditional states; do not mark a family done from one screenshot.

## Active local Beta UI

| Screen or surface family | Existing source / component | Interactions and states to cover |
| --- | --- | --- |
| Local preview entry | ChallengeV1Views.swift / ChallengeLocalLaunchView | Missing configuration, sign-in, submitting, failure, invitation arriving before/after authentication; preserve the local-only nature of this form. |
| App shell and bottom navigation | ChallengeV1Views.swift / ChallengeV1Shell, ChallengeBottomNavigation, ChallengeScrollLegibility | Home/Challenges/You selection, independent navigation state, modal dismissal, keyboard and safe areas, accessibility navigation alternative. |
| Home | ChallengeV1Views.swift / ChallengeV1Shell; ChallengeV1Sections.swift | First load, truly empty, active friend challenge, personal progress, upcoming goal, consent/start/review priority, recent history, partial failure, stale saved sections, per-section pagination. |
| Durable action recovery | ChallengeV1Views.swift / recovery; ChallengeV1Store.swift | Saved/in-flight/interrupted action, retry same request, abandon/check completion, unreadable request, account ownership, errors without destroying drafts or private recovery bytes. |
| Challenges list and entry | ChallengeV1Views.swift / Challenges tab; ChallengeV1EntryViews.swift / ChallengeEntryPanel | Create, age confirmation, invite redemption, community discovery, section history, pagination, unavailable/empty/stale states. |
| Friend challenge creation | ChallengeV1EntryViews.swift / ChallengeV1Create | Friend goal vs leaderboard, four metrics, input validation, window/timezone, simulated amount, keyboard, busy/error/close. Leaderboards never expose a goal target. |
| Personal goal creation | ChallengeV1EntryViews.swift / ChallengeV1Create | Four metrics, valid/invalid targets, scheduled window, review preview, complete agreement, explicit consent, reset consent when draft changes, submitting/receipt. |
| Friend lobby — creator | ChallengeV1Views.swift / ChallengeV1Detail.lobby and people | Exact-username invite, link issuance, pending requests, select/remove/decline, own target proposal where relevant, roster freeze, incomplete prerequisites. |
| Friend lobby — invitee | ChallengeV1Views.swift / ChallengeV1Detail | Pending/requested/selected states, propose own goal, waiting for creator, leave, unauthorized fields/actions absent. |
| Rules and consent | ChallengeV1EntryViews.swift / ChallengeAgreementText; ChallengeV1Views.swift / rules and detail | Full rules, roster/goals, selected participant consent, stale agreement, revised terms, reopen/reconsent, submission failure, server freshness. |
| Invitation links | ChallengeInvitation.swift; ChallengeV1EntryViews.swift / ChallengeLinkIssuer, ChallengeEntryPanel | Issue/revoke/copy or existing share handoff, cold/warm open, authentication/age prerequisites, opaque pre-auth state, expired/revoked/full/malformed link, idempotent redemption. |
| Scheduled challenge | ChallengeV1Views.swift / ChallengeV1Detail, MatchdayChallengeCard | Future start, consent status, participant-selected goal where applicable, frozen timezone, allowed reopen/cancel/leave actions. |
| Active friend leaderboard | ChallengeV1Views.swift / ChallengeV1Detail.people, MatchdayChallengeCard | Aligned ranks/names/totals/units, 2–6 participants, You emphasis, ties, unknown/corrected results, metric-specific ordering, refresh, no target/percentage. |
| Active friend goal | ChallengeV1Views.swift / ChallengeV1Detail.people | Each person's own target, understandable per-person progress, differing targets, missing activity, privacy-safe participant actions. |
| Personal goal detail | ChallengeV1Views.swift / ChallengeV1Detail | Own progress, metric-specific meaning, date/target, missing/stale data, downward correction, safe exit; no opponents or leaderboard. |
| Community catalog and join | ChallengeV1EntryViews.swift / ChallengeEntryPanel, ChallengeCommunityJoin | Available/unavailable catalog, joining, readiness, agreement/consent, full/closed state, errors and retry. No consumer publication feature. |
| Community detail | ChallengeV1Views.swift / ChallengeV1Detail | Own activity only, anonymous aggregate information permitted by the actual contract, stale/withheld counts, exit, result/history. No stranger identities or rankings. |
| Provisional results and review | ChallengeV1Views.swift / notice, reviews and allocation | Notice revision, actual filing deadline, select review reason, submit, waiting/resolved/expired review, corrections, stale-disabled action, pending request recovery. |
| Final and closed history | ChallengeV1Views.swift / final, allocation, resultText | Goal met/missed/unknown, winner/co-winners/placed, void/cancelled/exited, permitted own receipt after redaction, exact simulated consequence, full retained rules. |
| Leave/cancel confirmation | ChallengeV1Views.swift / confirmationDialog | Specific target and consequence, cancel dismissal, submission, request recovery, eligibility/time boundary. |
| Report/block and privacy redaction | ChallengeV1EntryViews.swift / ChallengePersonSafety; detail participant rendering | Reason selection, report, block confirmation, shared data removal, departed counterpart redaction, own-history retention, account switch and late response. |
| You | ChallengeV1Views.swift / You tab | Activity/source status, actual account details if available, sign-out, help/privacy navigation, errors and pending prerequisites. |
| Privacy and terms | ChallengeV1Views.swift / ChallengeLocalDisclosures | Complete readable text, long content, system text settings, explicit current local limitations. Do not replace it with a falsely complete shipping policy. |

## Shared and still-reachable legacy UI

Apply the visual language wherever these remain reachable in supported configurations. Preserve their contracts and feature gates. Confirm reachability from RootView, AppRouter, AppShellView, launch arguments, and build configurations before classifying any row as inactive.

| Family | Sources | Coverage |
| --- | --- | --- |
| Launch, failure, sign-in, onboarding | GameTimeApp.swift / RootView, ConfigurationFailureView, SignedOutView, OnboardingView; LaunchingView.swift; AppleSignIn.swift | Launch/retry, account/session state, profile setup and validation, Apple sign-in handoff, support links, keyboard, content scaling. |
| Historical main shell and lists | AppShellView.swift, AppRouter.swift, TodayView.swift, ChallengesView.swift | Current Personal creation/active/empty/history, detail navigation, refresh, unavailable dormant routes; do not relabel old Personal records as new Beta challenges. |
| Historical Personal creation | PersonalChallengeFlow.swift | Every existing form step, cadence/target/date/test amount, permissions handoff, full agreement, test-payment state, submitting/recovery/receipt. |
| Historical Personal detail/progress | PersonalChallengeDetailView.swift, PersonalAccountabilityComponents.swift, PersonalPaceComponents.swift, PersonalPaymentStatusCard.swift | Local progress and timeline, source uncertainty, pace semantics, review, payment test states, cancellation and retained receipt. |
| Historical duel flows | DuelViews.swift, DuelInvitationView.swift, DuelLifecycleViews.swift | Home, friend selection, create/rematch, creator review, receipt, invitation, full rules, lifecycle/review, safe exit and recovery. |
| Historical performance commitment flows | PerformanceCommitmentViews.swift, PerformanceCommitmentLifecycleViews.swift | Home, create/review, saved goal, detail, lifecycle, review/support/exit, pending recovery; preserve available vs unimplemented progress/following distinctions. |
| Historical weekly/community flows | WeeklyViews.swift | Home, creation, rules, detail, cohort, sharing/following, lifecycle and recovery; retain the old 2–5-person seven-day contract. |
| Account, Health, privacy, support, deletion | YouView.swift | All existing account/settings rows, Health handoff, privacy, support, sign-out, deletion confirmation and failures. Do not use legacy deletion to delete new-domain data. |
| Internal-only practice/diagnostics | MetricPrototypeView.swift, WeeklyHealthSourceProbe.swift, StagingAcceptanceDiagnostics.swift, ChallengeControlDiagnostic | Keep usable and consistently legible; preserve explicit internal gating and reference controls used by diagnostics. No expansion into a new consumer feature. |
| Shared components | CompetitiveTrustTheme.swift, ChallengeVisualComponents.swift, FeatureComponents.swift, PersonalAccountabilityComponents.swift | Tokens, typography, avatar/participant state, buttons, form fields, load/error/empty state, status, contrast and interaction states. |

## Boundaries and required evidence

- **System/provider-owned:** Sign in with Apple authorization, Health permissions, system share/dialog behavior, and existing payment SDK UI. Do not recreate these as custom branded screens. Verify entry, cancellation, return, and error handling.
- **Not part of this iPhone redesign:** a new watchOS app, operator dashboard, new backend/policy system, public rollout, or actual source/payment activation.
- **Unavailable new-product capabilities:** identify them from the current candidate. Hosted sign-in/client, support delivery, retention/deletion, and physical source acceptance may still have external prerequisites. Preserve honest availability and record blockers rather than showing working-looking no-op controls.
- **Representative adverse states for each applicable family:** loading, empty, partial, stale/offline, failed, disabled, saving, recovered, permission/source unknown, redacted, and destructive confirmation. Do not add states the domain cannot actually produce.
- **Cross-screen checks:** compact/current phone, default/accessibility text, supported appearances, longer names/strings, large counts, all metric units, selected navigation, Reduce Transparency/Reduce Motion, VoiceOver reading order, keyboard and bottom-bar clearance.
- **Completion rule:** each applicable row must have actual rendered evidence and meaningful interaction coverage, or an explicit, accurate reason it is outside current reachability or externally blocked. The component gallery and approved Home fixture are comparison aids, not proof that all screens work.

