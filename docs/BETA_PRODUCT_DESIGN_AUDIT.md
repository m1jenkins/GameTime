# GameTime beta product and design audit

**Audited:** August 6, 2026

**Automatic-progress reconciliation:** August 12, 2026

**Decision:** keep the product small; close the trust and recovery gaps before
inviting external testers.

## Automatic Apple Health design contract

This section supersedes the audit's older Personal manual-sync, coverage,
diagnostic/hold, positive-sample-readiness, and production-App-Attest
recommendations. Those remain useful only as a record of
`attested_hourly_v1`. The current design uses
`healthkit_nonmanual_daily_v1`:

- The only Health-specific action is **Connect Apple Health**.
- Progress appears automatically and consistently on Today, Challenges, detail,
  timeline, and pace.
- A quiet **Updated from Apple Health …** line may explain freshness.
- During grace, say **We'll keep checking Apple Health through …**.
- A transient Health error retains the prior value and marks it stale.
- With no successful snapshot, say **No step data available yet** and route to
  Apple Health settings help.
- Generic pull to refresh remains. Step-specific sync cards, buttons, saved-step
  actions, confirmed/unconfirmed status, coverage status, diagnostics, and holds
  do not.
- Completed challenge screens always show the frozen server result.

## Executive answer

GameTime already has the right first-beta structure:

- Today for the current commitment.
- Challenges for the current challenge and finished history.
- You for profile, Health, privacy, and account controls.
- At most one open seven-day Personal steps challenge per person, with a Stripe
  sandbox payment rehearsal in which no real money moves.

The beta does **not** need another tab, a separate history screen, social
features, live payments, streaks, charts, reminders, widgets, Apple Watch
support, or a larger onboarding tour.

It does need a small set of missing or incomplete launch behaviors:

1. Make the creation flow match the locked next-midnight, Stripe-sandbox
   contract.
2. Make the next action and exact deadline obvious on Today and in result
   states.
3. Add honest Health, cancellation, detail-load, and overdue-result recovery.
4. Add one Account & Support surface, including real legal/support links,
   version information, and Delete Account.
5. Add the service-only automatic result worker that turns finished challenges
   into final results.
6. Connect the existing sandbox status function to a complete user-visible
   review and simulated-settlement status, with safe recovery.
7. Finish the distribution identity, app icon, privacy manifest, iPhone-only
   setting, and automatic Apple Health path.
8. Verify common journeys with VoiceOver, Larger Text, contrast, and a real
   processed TestFlight build.

These are completion and trust tasks, not a new product phase.

## Evidence boundary

This is a read-only product, code, test, and research audit of the modified
working tree on `main` at commit `75286af`. Existing uncommitted iOS and
Supabase work was inspected and preserved.

The audit included:

- Current SwiftUI navigation, screens, state handling, and UI tests.
- Current Supabase migrations, Edge Functions, protected Personal result
  operations, and account-deletion foundation.
- Current Stripe PaymentSheet/SetupIntent, review, webhook, test-charge, and
  owner-status implementation.
- Existing simulator screenshots and accessibility-size fixtures.
- Current Apple guidance for HealthKit, TestFlight, App Attest, account
  deletion, privacy, review access, and accessibility.
- Current Supabase guidance for scheduled Edge Functions and job monitoring.
- Current Stripe guidance for SetupIntents, PaymentSheet, webhooks,
  idempotency, and test-customer deletion.
- Product-pattern research from Streaks, Apple Fitness, StepBet, and Beeminder.

No app code, database code, hosted backend, Apple account, or TestFlight state
was changed. No running simulator was available, so this audit does not claim a
new live visual pass. Existing screenshots show a coherent warm-paper visual
system, large primary actions, and clear Health states at accessibility XXXL;
the full journey still needs the bounded accessibility pass described below.

The controlling beta list changed concurrently during this audit from a
no-payment Stage A cohort to a Stripe sandbox rehearsal. This report preserves
that newer choice. `PLAN.md`, `DECISIONS.md`, user-facing copy, hosted scope,
and App Review notes still need one explicit reconciliation before candidate
freeze.

## Current screen and journey inventory

| Surface | What is already present | Beta finding |
| --- | --- | --- |
| App entry | Configuration failure, launch/loading, retry/offline, signed out, Sign in with Apple, and profile onboarding | Complete structure; root appearance and support recovery need work |
| App shell | Today, Challenges, and You, each with its own navigation path | Keep exactly these three tabs |
| Today | Authoritative loading/error handling, current challenge, progress, seven-day timeline, and create state | Use automatic snapshot progress, update time, and one state-aware next action |
| Challenges | Current challenge, finished history, unfinished setup recovery, empty state, and draft removal | No separate History tab needed; expose saved cancellation recovery |
| Creation | Metric, cadence, target, commitment, custom start, Health permission, Stripe PaymentSheet setup/consent, review, and draft recovery | Keep sandbox setup; use one Connect Apple Health action with no positive-sample gate |
| Challenge detail | Status, frozen terms, automatic timeline/progress, result, missed-result review, and pre-start cancellation | Add update/stale/grace/no-data states and complete sandbox settlement status |
| You | Profile, timezone, Health access, privacy explanation, history totals, and sign out | Add Apple Health settings recovery, Account & Support, and Delete Account |
| Privacy explanation | Private challenge, limited Health read, fail-closed missing-data, and no-social explanations | Good education, but not a public privacy policy, sandbox-data disclosure, or beta terms |

Primary implementation evidence:

- [App shell and tab structure](../ios/GameTime/GameTime/AppShellView.swift)
- [App entry and onboarding](../ios/GameTime/GameTime/GameTimeApp.swift)
- [Today](../ios/GameTime/GameTime/TodayView.swift)
- [Challenges and history](../ios/GameTime/GameTime/ChallengesView.swift)
- [Creation flow](../ios/GameTime/GameTime/PersonalChallengeFlow.swift)
- [Challenge detail and result states](../ios/GameTime/GameTime/PersonalChallengeDetailView.swift)
- [You and privacy explanation](../ios/GameTime/GameTime/YouView.swift)
- [Personal store and recovery state](../ios/GameTime/GameTime/PersonalAccountabilityStore.swift)
- [Stripe sandbox client boundary](../ios/GameTime/GameTime/SupabasePersonalPaymentClient.swift)
- [Stripe sandbox database foundation](../supabase/migrations/20260805131357_personal_stripe_sandbox_foundation.sql)
- [Current UI-test coverage](../ios/GameTime/GameTimeUITests/GameTimeUITests.swift)

## What should change for beta

### P0. Make creation match the product contract

The locked beta defaults to the next local midnight, offers a start-now choice
that counts today, and uses Steps as its only metric. The older flow presented:

- A screen where Steps is the only preselected choice.
- A custom start day and hour.
- “Tonight at midnight” and “Next hour” shortcuts.
- Ambiguous payment-like wording such as “How much are you putting on it?”

For beta, reduce the visible journey to six meaningful decisions or checks:

1. Daily or cumulative.
2. Step target.
3. Sandbox commitment amount.
4. Apple Health permission request.
5. Stripe test-payment consent and PaymentSheet setup.
6. Final review and confirmation.

The server remains authoritative for the next-midnight start. The review must
show the exact local start, end, automatic-checking cutoff, frozen timezone,
review deadline, simulated-settlement rule, and this exact
disclosure:

> Payment test mode — no real money moves.

The payment step should also say plainly that only Stripe test card details are
accepted and no real money moves. Keep dormant metric, custom-start, live
Stripe, Solo, and social paths intact but unreachable. This is a narrow beta
presentation change, not a model rewrite.

### P0. Give Today one unmistakable next action

Today already has progress content. Add a compact, state-aware line or
card that answers two questions without opening detail:

- What should I do next?
- By exactly when, in my local time?

Minimum states:

| State | Primary message and action |
| --- | --- |
| Scheduled | “Starts [local date/time]” and Review terms |
| Active, healthy | “[steps] remaining today/overall” and “Updated from Apple Health …” |
| Active, upload offline | Keep local progress; “We'll send this update when you're back online” |
| Needs attention | Plain-language reason, safest recovery action, and Help |
| Finalization window | “We'll keep checking Apple Health through [exact local date/time]” |
| Waiting for result | “Your result is being prepared” and Refresh |
| Result overdue | “This is taking longer than expected” with Refresh and Contact Support |
| Final | Met, missed, or inconclusive with View result |

Do not introduce a new dashboard, countdown animation, or notification system.

### P0. Add honest recovery for Health and saved requests

HealthKit deliberately does not tell an app whether step-read access was denied;
denied access can look the same as no available samples. GameTime already
understands that limitation in code, but the user recovery is incomplete.

For no-access/no-data:

- Say that access may be limited **or** there may be no recent
  device-recorded steps.
- Never label a zero result “Permission denied.”
- Offer Try Again.
- Explain the exact Apple Health settings path.
- Offer Contact Support.

Also surface the durable cancellation state that already exists locally. If a
pre-start cancellation was saved but its outcome is uncertain, Today or
Challenges should show:

- “Cancellation saved — still trying.”
- Retry Cancellation.
- Refresh.
- Contact Support if repeated attempts fail.

Creation must remain unavailable while the prior cancellation outcome is
unknown. A network failure must never be translated into zero steps, a missed
goal, or a successful cancellation.

### P0. Add one Account & Support surface

Do not scatter several new settings screens across the app. Add one
**Account & Support** destination under You with:

- Apple Health access help.
- Public Privacy Policy link.
- Public Beta Terms link.
- Contact Beta Support.
- App version and build number.
- Sign out.
- Delete Account.

Reuse the same support destination from configuration failure, Health recovery,
saved cancellation, detail failure, result overdue, and deletion failure.
Add compact Privacy Policy, Beta Terms, and Support links to the signed-out
screen as well, so people and App Review can reach them before account
creation. Configuration failure must expose a real support action, not just the
words “Contact support.”

The repository audit did not find confirmed public policy/terms URLs or a beta
support address. Implementation must stop and ask the founder for those values;
it must not invent or publish placeholders.

The current privacy card says payment terms stay only between the user and
GameTime. That is incomplete once Stripe PaymentSheet is reachable: Stripe
processes the test payment details, while GameTime should receive only
provider identifiers and status. Correct the in-app explanation and public
policy, and link Privacy Policy and Beta Terms from the payment-consent step.

### P0. Finish account deletion

The database contains a substantial service-only deletion transaction, but the
iOS-to-service journey is missing. The smallest credible flow is:

1. Delete Account under Account & Support.
2. A consequence review that explains what is deleted or retained.
3. A destructive confirmation.
4. Fresh Sign in with Apple authentication.
5. Apple token revocation.
6. Deletion or explicitly disclosed retention of the Stripe test Customer and
   saved test payment method.
7. One authenticated, service-only deletion orchestration endpoint.
8. Local session, App Attest, and pending-request cleanup only after the server
   confirms success.
9. Deleting, success, retry, and Contact Support states.

The endpoint must not expose the service-role database operation directly to a
client. Exact deletion semantics, retention language, and public policy copy
must agree before TestFlight review.

### P0. Produce results automatically

The app can render Personal results, and the database retains protected v1
assessment/publication operations. Snapshot v2 needs a finalizer that copies
the selected seven daily totals directly into the immutable result without a
legacy assessment reference. The existing named result schedule remains
inactive until backend-v2 smoke passes.

Add one small service-only worker that:

- Finds Personal challenges due after the 24-hour finalization period.
- Dispatches by frozen step-data policy, preserving the historical v1 path.
- For v2, selects only a snapshot queried through the challenge end and copies
  its seven totals directly into the result.
- Publishes at most one immutable result.
- Is idempotent and safe beside a final snapshot upload.
- Leaves uncertain evidence `inconclusive`; it never guesses.
- Records enough privacy-safe job output to identify overdue or failed work.

Use the existing single-purpose named schedule rather than a general job
platform. Keep it inactive through migration and authenticated backend smoke;
activation is a separate approved cutover step.

Relevant current Supabase references:

- [Schedule Edge Functions](https://supabase.com/docs/guides/functions/schedule-functions)
- [Cron jobs and run history](https://supabase.com/docs/guides/cron)

### P0. Complete Stripe sandbox status and recovery

The current implementation already uses the right basic shape for saving a
future payment method: Stripe PaymentSheet backed by a SetupIntent, explicit
consent tied to the frozen amount, an exact server commit, an owner review
request, signed webhooks, and an idempotent simulated off-session test charge.

The missing product link is after result publication. The database exposes
`get_my_personal_stripe_sandbox_status_v1`, but the iOS app does not fetch or
present its settlement states. The detail screen only shows the review request
and whether the seven-day window is open or closed. The review request is held
only in memory, so a relaunch can show the review form again instead of its
authoritative state.

The audit also found no repository implementation of the beta-specific Stripe
allowlist or runtime kill switch promised by the launch plan, and no schedule
that invokes the sandbox charge dispatcher. Authenticated users can directly
execute some Stripe setup/creation RPCs, so an Edge-Function-only switch would
be bypassable. These controls must live at the database mutation boundary.

Add one **Payment test status** card to challenge detail:

| Server state | User-facing meaning |
| --- | --- |
| `method_saved` | Test method saved; no test charge exists |
| `review_open` | Miss is provisional; request review by the exact local deadline |
| `under_review` | Test settlement paused while support reviews it |
| `waived` / `no_charge` | Closed with no simulated test charge |
| `charge_pending` | Simulated test charge is being processed |
| `charged` | Sandbox test charge completed; no real money moved |
| `requires_action` | Test settlement needs attention; show Refresh and Support |
| `collection_failed` | Test settlement failed; do not auto-retry from the client |

The server/webhook remains authoritative. The app may refresh status but must
not create a charge, infer success from client state, or loop-poll Stripe.
Every visible state must repeat that it is test mode where ambiguity is
possible.

`requires_action` and `collection_failed` currently have no recovery route and
can block a later challenge indefinitely. Add one explicit user-authorized
same-PaymentIntent recovery path or a founder-reviewed waiver path. It must
resolve the existing sandbox command, never silently create a second one.

Before beta, also:

- Run the review/charge worker on a bounded schedule behind the beta allowlist
  and kill switch.
- Gate direct database mutations as well as Edge Functions. Turning the switch
  off must stop new setup, commitments, charge-authorizing decisions, and
  dispatch while preserving owner status, signed webhook reconciliation, and
  audited no-charge/waiver resolution for existing obligations.
- Keep exact Stripe idempotency keys stable across ambiguous server retries.
- Accept only test keys, test Customers, test SetupIntents, test
  PaymentMethods, test PaymentIntents, and signed test webhooks.
- Never store or log raw card details, client secrets, provider secret keys,
  identity tokens, or webhook bodies.
- Add a one-page operator path for an opened review, an upheld/waived outcome,
  a failed test settlement, and an overdue command.
- Make account deletion provider-aware and serialize deletion against review,
  charge claim, and webhook handling so a deleted account cannot later receive
  a simulated test charge.
- Tell testers never to enter a real card and link only to Stripe's published
  test-card values in-app and in TestFlight What to Test.

The existing local source and tests are not hosted evidence. Hosted secrets,
webhook destination/signature verification, allowlist, kill switch, worker
schedule, end-to-end review decision, and visible final status remain
unverified.

Relevant Stripe references:

- [iOS PaymentSheet with a SetupIntent](https://docs.stripe.com/payments/mobile/accept-payment?platform=ios&type=setup)
- [Save a payment method for later use](https://docs.stripe.com/payments/save-and-reuse?platform=ios&ui=payment-sheet)
- [Use webhooks for authoritative payment status](https://docs.stripe.com/payments/payment-intents/verifying-status)
- [Idempotent requests](https://docs.stripe.com/api/idempotent_requests)
- [Delete a test Customer and card details](https://docs.stripe.com/api/customers/delete)
- [Stripe test cards](https://docs.stripe.com/testing)

### P0. Make the full fixed-light journey safe

Full dark-mode design can remain deferred. However, launch and the signed-in
shell force light appearance while configuration failure, signed out, and
onboarding do not consistently do so. Those screens use the warm-paper
background and can inherit dark-system foreground behavior.

Apply the fixed light appearance to the complete root journey and add one
dark-device regression check for Signed Out and Onboarding. This keeps the
current visual system legible without opening a dark-mode redesign.

### P0. Finish the distribution candidate

Repository inspection found that the current Release path still needs launch
work:

- Release now enables Personal creation only through `stripe_sandbox`; that
  concurrent scope change is not yet reconciled across `PLAN.md` and
  `DECISIONS.md`.
- Release still uses a staging bundle identity.
- The iPhone app and test targets are locked to the iPhone device family; iPad
  support is not a beta requirement.
- No main iPhone-app icon asset catalog was found in the repository inventory;
  concurrently added Watch assets do not satisfy the iPhone beta archive.
- Concurrent Watch source appeared during the audit. Preserve it, but do not
  embed or expose a Watch companion in the iPhone-only candidate unless the
  beta scope and physical-device acceptance plan are explicitly reopened.
- No `PrivacyInfo.xcprivacy` file was found in the repository inventory.
- Historical/generic App Attest work remains regression scope. It is not a
  Personal snapshot-v2 distribution gate.
- Stripe sandbox secrets, webhook, test-charge schedule, and provider cleanup
  are not hosted or end-to-end proof.
- The Stripe backend deliberately refuses a production provider environment.
  Document that the Release/TestFlight client still targets a clearly
  non-production Stripe beta backend with test keys; do not infer provider mode
  from an ambiguous hosted-project label.
- Release still hardcodes the `gametime-staging` Stripe return scheme; the
  final beta scheme and redirect must be frozen and proven on the processed
  TestFlight build.
- A reviewer-access strategy and review notes are not yet frozen.

These are candidate-build gates, not reasons to create several new
environments. Correct one Release configuration, preserve Staging for internal
work, and validate the resulting archive.

Primary evidence:

- [App configuration](../ios/GameTime/GameTime/AppConfiguration.swift)
- [Release configuration](../ios/GameTime/Configuration/Release.xcconfig)
- [Xcode project settings](../ios/GameTime/GameTime.xcodeproj/project.pbxproj)

### P0. Complete a bounded accessibility pass

Existing UI tests cover the shell, creation entry, old Health/manual-sync
states, saved creation recovery, loading/offline states, Dynamic Type, and
Reduce Motion. Replace the old Personal assertions with automatic cross-surface
progress, grace, stale, no-data, offline, and frozen-result coverage.

Before inviting testers, check on the exact candidate:

- VoiceOver order, labels, values, hints, and actions.
- Larger Text through every creation page, Health recovery, Today, detail,
  Account & Support, and deletion.
- Text and status contrast, especially small tertiary, coral, and mint text.
- Controls at least 44 points tall where they are interactive.
- State meaning that does not depend on color alone.
- No clipped action, frozen term, legal link, or destructive confirmation.
- No clipped payment consent, PaymentSheet recovery, review deadline, or
  settlement status.

Do not claim Apple accessibility support labels until the common journeys have
actually passed.

## P1. Worth doing after the first cohort is stable

These findings matter, but they should not hold the first ten testers unless
they cause a concrete failure:

- Replace the permanent public-username decision with a lower-friction private
  profile approach before a wider solo-product beta. For the first named
  cohort, keep the existing identity contract rather than opening a backend
  profile migration.
- Add inline username rules and privacy context during onboarding.
- Show visible “Signing in…” feedback during Apple authentication.
- Detect profile-timezone drift before creating a later challenge.
- Reduce repeated sandbox disclosure only after the promise remains
  unmistakable at creation and in frozen terms.
- Add an optional local reminder only if cohort evidence shows people need more
  clarity before automatic finalization. Notifications must not be required for
  core function.

## Explicitly do not add for this beta

- A fourth tab or separate History screen.
- A built-in bug-report composer; TestFlight already captures screenshot
  feedback and device/build context.
- Push notifications, reactions, nudges, or APNs infrastructure.
- Streaks, charts, trends, awards, search, filters, or analytics dashboards.
- Widgets, App Intents, Apple Watch, iPad, or background-sync guarantees.
- Personalized targets derived from historical Health data.
- Social sharing, friends, standings, leaderboards, chat, or referrals.
- Live Stripe mode, real-money charges, pots, prizes, or wagering language.
- Custom start days or hours.
- A marketing onboarding carousel.

## Why these recommendations fit the product

Comparable products support information hierarchy, not feature copying:

- [Streaks](https://streaksapp.com/) supports a single-glance daily status and
  visible remaining work. Its themes, widgets, Watch support, notes, and deeper
  statistics are unnecessary here.
- [Apple Fitness](https://support.apple.com/guide/iphone/get-started-with-fitness-ipha5dddb411/ios)
  leads with current progress and goals, then layers trends, awards,
  customization, and sharing. GameTime only needs the first layer.
- [StepBet's rules](https://stepbet.com/rules) make the pre-start check and
  post-period sync deadline explicit. GameTime needs that clarity without
  copying its game mechanics or warm-up week.
- [Beeminder's reminder guidance](https://help.beeminder.com/article/101-reminders)
  prioritizes how much remains and when it is due. GameTime can adopt that
  information order without aggressive notifications.

The app should retain its own warm-paper, card, timeline, and wordmark system.
It must not imitate Apple's Activity rings or another product's visual assets.

## External beta requirements behind the design

- Health access should be requested in context, with honest no-data behavior:
  [Apple HealthKit authorization](https://developer.apple.com/documentation/HealthKit/authorizing-access-to-health-data)
  and [HealthKit design guidance](https://developer.apple.com/design/human-interface-guidelines/healthkit).
- Retained generic or legacy targets that still use App Attest must keep Apple
  environments separate. Personal snapshot v2 does not use App Attest:
  [Preparing to use App Attest](https://developer.apple.com/documentation/DeviceCheck/preparing-to-use-the-app-attest-service).
- Account-creating apps need in-app account deletion, and Sign in with Apple
  tokens should be revoked:
  [Offering account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/).
- External builds follow the App Review Guidelines and need valid reviewer
  access, URLs, review notes, feedback information, and a working backend:
  [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
  and [Invite external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers).
- TestFlight builds must follow Apple's payment and gaming rules. Because this
  beta deliberately simulates a later consequence with Stripe, review notes
  must make clear that only test cards and sandbox objects are accepted, no
  funds or prizes exist, and live behavior remains disabled. Legal/App Review
  classification is a separate launch gate, not something code can prove:
  [App Review Guidelines, sections 2.2, 3.1, and 5.3](https://developer.apple.com/app-store/review/guidelines/).
- The privacy policy must be linked in App Store Connect and inside the app,
  and Health data use must be disclosed:
  [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/).
- Validate privacy manifests and required-reason APIs in the archived build:
  [Required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
  and [third-party SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/).
- Common tasks should pass VoiceOver, Larger Text, contrast, and non-color state
  communication before declaring accessibility support:
  [Accessibility labels overview](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/).

Apple's guidance is live documentation. Recheck it immediately before the
external TestFlight submission.

## Recommended implementation sequence

1. Finish and freeze the automatic Health reader, protected whole-snapshot
   cache, authenticated uploader, displayed-progress precedence, and
   fail-closed challenge availability.
2. Lock the visible creation contract; add Today's next action; surface Health,
   stale/no-data, cancellation, detail, and result recovery; make the full root
   safely light.
3. Add Account & Support using founder-provided real destinations.
4. Add and locally prove snapshot-v2 finalization and the automatic Personal
   result worker with its schedule inactive.
5. Connect and locally prove the sandbox status, relaunch-safe review, tester
   guidance, and explicit recovery UI.
6. Add and locally prove the database switch, tester allowlist, and direct-RPC
   access controls.
7. Add and locally prove the sandbox dispatcher schedule, founder review
   handling, and requires-action/failure recovery.
8. Make account deletion safe against Stripe review, claim, webhook, and
   provider-data races.
9. Add and locally prove the iOS/Apple/server account-deletion journey.
10. Deploy and smoke backend v2, then make the v2 iOS build mandatory and
    migrate only eligible future-cutoff open challenges.
11. Prepare the distribution configuration, assets, public values, and reviewer
    packet; verify one exact candidate locally, then separately approve hosted changes,
    Stripe test-mode configuration, archive upload, TestFlight review
    submission, and tester invitations.

The companion [implementation prompts](BETA_IMPLEMENTATION_PROMPTS.md) divide
that sequence into safe, reviewable chats.
