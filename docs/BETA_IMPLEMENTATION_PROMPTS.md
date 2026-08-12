# GameTime beta implementation prompts

> **Superseded August 12, 2026.** These prompts preserve the implementation
> sequence for historical `attested_hourly_v1`. Do not execute their Personal
> App Attest, manual metric/coverage retry, positive-sample readiness,
> diagnostic/hold, or final-sync instructions for new work. The controlling
> automatic-flow contract is D120 and
> [PERSONAL_HEALTH_SNAPSHOT_V2_ACCEPTANCE.md](PERSONAL_HEALTH_SNAPSHOT_V2_ACCEPTANCE.md).
> Generic/social App Attest code remains valid regression scope.

**Prepared:** August 6, 2026

Use these prompts in order, one per new Codex chat. Each prompt is deliberately
bounded so a chat can finish, verify, and hand off without silently expanding
the beta.

The controlling documents are:

- [Lean beta launch plan](BETA_LAUNCH_AUDIT.md)
- [Product and design audit](BETA_PRODUCT_DESIGN_AUDIT.md)
- [Personal acceptance reference](PERSONAL_V1_ACCEPTANCE.md)

## Prompt 1 — finish the trust fixes already in progress

```text
Work in /Users/macbookprom42025/Documents/GameTime.

Goal: finish and locally verify the existing in-progress trust fixes for the
locked Personal Stripe-sandbox beta:
1. production App Attest compatibility for a distribution/TestFlight build,
2. fail-closed creation until authoritative open-challenge and eligibility
   state has loaded, and
3. replaying durable saved metric/coverage requests before a fresh Health query
   or cutoff can reject them.

First read AGENTS.md, docs/BETA_LAUNCH_AUDIT.md,
docs/BETA_PRODUCT_DESIGN_AUDIT.md, PLAN.md, DECISIONS.md, and the relevant
App Attest/retry/Personal acceptance sections. Inspect git status and the full
current diff before editing. The worktree already contains substantial
uncommitted iOS, migration, Edge Function, and test work for these defects.
Treat it as user-owned work: understand and complete it; do not duplicate,
discard, reset, or broadly rewrite it.

Keep the scope to these three defects. Preserve .agents/, .mcp.json,
skills-lock.json, dormant Social/Solo/live-Stripe code, the current Stripe
sandbox beta path, and all unrelated dirty changes. Do not add product features
or refactor the architecture.

Required behavior:
- Release/distribution may require production App Attest; Local/Staging behavior
  remains intentionally separated.
- TestFlight production attestations and development attestations are never
  treated as interchangeable.
- Unknown or failed authoritative Personal state keeps Create unavailable and
  presents Retry.
- Saved signed metric and coverage requests retain their original exact bytes
  and are retried before any fresh query or cutoff decision.
- Network/device verification failure never becomes zero steps, a chargeable
  missed result, or permissive creation.

Add or update only focused tests for the changed behavior. Run the smallest
relevant tests first, then the existing repository verification appropriate to
the final diff. If a full local Supabase reset would disturb an existing stack,
stop and report that gate instead of taking ownership of it.

Do not push, deploy, publish migrations or Edge Functions, change Supabase
secrets, alter Apple accounts, upload a build, or submit TestFlight. Do not
print attestations, signed payloads, tokens, keys, health samples, or private
profiles.

Stop if the intended production identity, hosted verifier contract, or safe
ownership of a local Supabase stack cannot be established without an external
decision.

End with:
- what changed and why it matters,
- exact files changed,
- tests/checks run and their results,
- what remains unverified on a real TestFlight phone or hosted backend,
- one recommended next prompt.
```

## Prompt 2 — lock and clarify the beta iOS journey

```text
Work in /Users/macbookprom42025/Documents/GameTime.

Goal: make the existing iOS Personal journey match the locked lean-beta Stripe
sandbox contract and give testers clear next actions and recovery. This is a
focused SwiftUI change, not a redesign.

First read AGENTS.md, docs/BETA_LAUNCH_AUDIT.md,
docs/BETA_PRODUCT_DESIGN_AUDIT.md, PLAN.md, DECISIONS.md, and inspect git status
and current diffs. Preserve every unrelated or in-progress user change.

Implement the smallest safe UI slice:
1. Remove the one-option Steps page from the visible beta creation journey.
2. Remove the custom start page and controls from the visible beta journey.
   Continue to let the server derive the next local midnight.
3. Replace ambiguous amount/payment wording with the exact disclosure:
   “Payment test mode — no real money moves.” Also state plainly that
   only Stripe test card details are accepted and no real money moves.
4. Preserve the Stripe test-payment consent and PaymentSheet setup step.
5. Keep the final review explicit about cadence, step target, exact local
   start/end, frozen timezone, final-sync cutoff, manual sync, sandbox amount,
   review deadline, and simulated-settlement rule.
6. Add one state-aware next-action/deadline line or card on Today for scheduled,
   active, saved upload, needs attention, final-sync window, waiting for result,
   overdue result, and final result.
7. Add honest Health no-data/limited-access recovery with Try Again, settings
   instructions, and support routing. Never claim read permission was denied.
8. Surface durable pending-cancellation recovery on Today or Challenges with
   Retry Cancellation, Refresh, and support fallback.
9. Add detail load-failure/not-found recovery and a clear waiting/overdue result
   state.
10. Apply the existing fixed-light appearance to configuration failure, signed
   out, onboarding, launch, and the signed-in shell. Do not design dark mode.

Keep Today, Challenges, and You as the only tabs. Preserve dormant custom-start,
Social, Solo, and live-Stripe code but keep it unreachable. Keep the Stripe
sandbox payment route reachable. Do not change database schemas, settlement
rules, Health evidence semantics, App Attest, hosted functions, or distribution
signing.

Use existing components and the warm-paper visual language. Keep touch targets
at least 44 points, state meaning independent of color, and copy readable at
accessibility XXXL. Update focused unit/UI fixtures and assertions in the same
change. Visually inspect every changed screen at a normal size and
accessibility XXXL. Include a dark-device regression check for Signed Out and
Onboarding while the app remains intentionally light.

Do not push, deploy, upload, publish, or change Apple/Supabase accounts.

Stop and ask only if the support destination is required to complete navigation
but no real value exists; do not invent an email address or URL.

End with:
- what changed and why it matters,
- screenshots or precise visual observations for changed screens,
- tests/checks run and results,
- any candidate-only or physical-device proof still open,
- one recommended next prompt.
```

## Prompt 3 — add Account & Support with real destinations

```text
Work in /Users/macbookprom42025/Documents/GameTime.

Goal: add one small Account & Support destination under You for the lean
external beta.

First read AGENTS.md, docs/BETA_LAUNCH_AUDIT.md,
docs/BETA_PRODUCT_DESIGN_AUDIT.md, PLAN.md, DECISIONS.md, and inspect the current
worktree and diffs. Preserve all unrelated work.

Before implementation, locate confirmed project values for:
- the public Privacy Policy URL,
- the public Beta Terms URL,
- the monitored beta-support/feedback destination.

If any value is absent, do not invent or publish a placeholder. Implement only
the parts that can safely land without false destinations, clearly identify the
missing founder decision, and leave the launch checklist unchecked.

The Account & Support surface should contain:
- Apple Health access help,
- Privacy Policy,
- Beta Terms,
- Contact Beta Support,
- app version and build number,
- Sign out.

Do not add a tappable Delete Account row that leads to an incomplete or
placeholder flow. Keep it absent until Prompt 9 lands the end-to-end behavior.

Add compact Privacy Policy, Beta Terms, and Contact Support actions to Signed
Out and a real Contact Support action to configuration failure. These must work
before account creation.

Correct the current privacy claim that payment terms stay only between the user
and GameTime. Once Stripe PaymentSheet is reachable, the copy and public policy
must explain that Stripe processes test payment details while GameTime stores
only the provider identifiers/status needed for the sandbox workflow. Link
Privacy Policy and Beta Terms from the test-payment consent step.

Reuse the support destination from configuration failure, Health recovery,
saved-cancellation failure, challenge-detail failure, overdue result, and
deletion failure where those states exist. Use safe URL handling, clear
accessibility labels, and honest unavailable/retry behavior. Do not add a
fourth tab, general settings framework, feedback database, chat, analytics SDK,
or built-in screenshot reporter.

Update focused UI tests for navigation, URL availability, version/build, Larger
Text, and accessibility labels. Visually inspect normal and accessibility XXXL
layouts.

Do not deploy or publish a website, change App Store Connect metadata, send
email, push code, upload a build, or make any Apple/Supabase account change.

End with:
- what changed and why it matters,
- the exact real destinations used or still missing,
- tests/checks and visual verification,
- what remains for deletion and TestFlight metadata,
- one recommended next prompt.
```

## Prompt 4 — add the automatic Personal result worker

```text
Work in /Users/macbookprom42025/Documents/GameTime.

Goal: add and locally prove one service-only automatic result worker for the
locked Personal Stripe-sandbox beta. Do not create a general scheduler platform
or deploy it.

First read AGENTS.md, docs/BETA_LAUNCH_AUDIT.md,
docs/BETA_PRODUCT_DESIGN_AUDIT.md, docs/PERSONAL_V1_ACCEPTANCE.md, PLAN.md,
DECISIONS.md, all current Personal assessment/result migrations and tests, and
the current Supabase scheduled-Function/Cron guidance. Inspect git status and
overlapping diffs. Preserve all unrelated or in-progress changes.

An untracked personal-result-worker migration appeared concurrently during the
August 6 audit. Establish its ownership and review it before editing. If it is
the intended implementation, finish and verify it; do not create a duplicate.
If ownership is unclear, stop and report the exact ambiguity.

Reuse the existing protected versioned assessment and first-result publication
operations. The one small service-only worker must:
- find only Personal challenges due after the 24-hour grace period,
- process a bounded batch,
- use existing completeness, outage, quarantine, and eligibility-hold rules,
- publish at most one immutable result,
- be idempotent and safe to rerun beside a final device sync,
- leave uncertain evidence inconclusive and never guess,
- never call Stripe or directly create a test charge; an exact missed-result
  publication may open only the existing sandbox review workflow,
- not create standings, winners, donations, or Social/Solo outcomes,
- emit privacy-safe run counts/errors and support an overdue/failure query for
  the founder's daily beta check.

Keep schedule configuration separate from hosted activation. Store credentials
only through the approved secret mechanism; do not put secrets in migrations,
logs, examples, or test output.

Add focused tests for met, missed with one sandbox review opened,
incomplete/inconclusive with no review, safe rerun, concurrent final sync,
cross-account isolation, bounded batching, partial failure, and overdue
visibility. Run the smallest relevant tests and then the existing full local
database/backend verification if local stack ownership is safe.

Do not publish migrations or Edge Functions, enable a hosted Cron job, set
secrets, deploy, push, alter production data, or claim hosted proof.

Stop if the intended hosted scheduler owner, secret source, or production
assessment version requires an external decision.

End with:
- what changed and why it matters,
- the worker's exact selection/idempotency behavior,
- tests/checks run and results,
- the separate hosted deployment/scheduling/smoke-test approval gate,
- one recommended next prompt.
```

## Prompt 5 — complete the Stripe sandbox UX, locally

```text
Work in /Users/macbookprom42025/Documents/GameTime.

Goal: complete and locally verify the user-facing Stripe sandbox journey for
the lean external beta. This is test mode only. No real money, live Stripe
objects, prizes, or production payment claims are allowed. Keep this chat to
iOS models, state, screens, copy, and focused tests.

First read AGENTS.md, docs/BETA_LAUNCH_AUDIT.md,
docs/BETA_PRODUCT_DESIGN_AUDIT.md, PLAN.md, DECISIONS.md, README.md, the current
Stripe sandbox status RPC, iOS PaymentSheet/client code, UI tests, and current
official Stripe mobile SetupIntent and testing guidance. Inspect git status and
every overlapping diff. Preserve all unrelated and concurrent work.

Investigate first. Reuse the existing PaymentSheet + SetupIntent flow, frozen
consent, exact challenge commit, review RPC, and owner status RPC. Do not build
a second payment system or introduce Checkout, Sources, Charges API, raw card
handling, live keys, or client-created charges.

Implement the smallest missing product slice:
1. Add a typed iOS client/store model for
   get_my_personal_stripe_sandbox_status_v1.
2. Add one Payment test status card to challenge detail for method_saved,
   review_open with an exact deadline, under_review, waived/no_charge,
   charge_pending, charged, requires_action, and collection_failed.
3. Load authoritative review/payment state on detail open and manual Refresh so
   a relaunch cannot show a stale review form.
4. Provide Refresh and Contact Support for nonterminal/failed states. Do not
   loop-poll Stripe or infer success on the client.
5. For requires_action or collection_failed, present one explicit
   user-authorized recovery or founder-waiver route supplied by the server.
   Never silently create or retry a second test charge.
6. Make every ambiguous payment state say it is Stripe test mode and that no
   real money moved.
7. Tell testers never to enter a real card. Link to Stripe's published test-card
   instructions and the real Privacy Policy and Beta Terms from consent.
8. Correct privacy copy so it says Stripe processes test payment details while
   GameTime keeps only the provider identifiers/status needed for the sandbox.

Keep the server/signed webhook authoritative. Never log or persist raw card
data, SetupIntent client secrets, secret keys, authorization tokens, full
provider payloads, or private profile/Health data.

Add focused Swift and UI tests for every visible state, relaunch/refresh,
duplicate review form prevention, consent/test-card/legal links, recovery CTA,
other-user isolation at the client boundary, accessibility XXXL, and VoiceOver
labels. Visually inspect creation, PaymentSheet handoff/recovery, review, and
every status card at normal and accessibility XXXL sizes.

Do not change database schemas or Edge Functions, contact Stripe, create or
alter Stripe Dashboard objects, use test cards against a hosted account, set
secrets, deploy, publish, push, upload, submit TestFlight review, or invite
testers.

Stop if the real privacy/terms/support destinations or the server recovery
contract do not exist. Report the exact gate; do not invent them.

End with:
- what changed and why it matters,
- exact visible sandbox states and server authority,
- screenshots/visual findings and tests run,
- backend/hosted/payment-recovery gates still unverified,
- one recommended next prompt.
```

## Prompt 6 — add Stripe sandbox access controls, locally

```text
Work in /Users/macbookprom42025/Documents/GameTime.

Goal: add and locally verify only the database-enforced access controls for the
Stripe sandbox beta. Do not add scheduling, operator review tooling, account
deletion, or iOS redesign in this chat.

First read AGENTS.md, docs/BETA_LAUNCH_AUDIT.md,
docs/BETA_PRODUCT_DESIGN_AUDIT.md, PLAN.md, DECISIONS.md, the Stripe sandbox
migration/functions/tests, and the current worktree diff. Preserve unrelated
and concurrent work.

Implement one global runtime switch and one exact tester allowlist at the
database mutation boundary. Cover setup, challenge commit, and every action
that could authorize or dispatch a simulated test charge. Revoke or securely
bind direct authenticated mutation RPC access so an Edge-Function-only check
cannot be bypassed.

When disabled:
- refuse new payment setup and commitments,
- refuse any new charge-authorizing decision and dispatch,
- keep owner status readable,
- keep signed webhook reconciliation working,
- keep audited no-charge/waiver resolution available for existing obligations.

Fail closed for missing configuration and other users. Preserve exact committed
retries only when their original authorization was valid under the frozen
contract. Do not weaken owner RLS or expose service-role functions.

Add focused pgTAP and Edge Function tests for switch on/off, allowlisted and
non-allowlisted users, direct-RPC bypass, exact retry, stale/deleted actors,
other-user isolation, status/webhook continuity, and safe waiver while off.

Do not add a hosted flag, set secrets, deploy, publish migrations/functions,
change production data, contact Stripe, push, upload, or submit TestFlight.

End with:
- what changed and why it matters,
- exact switch/allowlist behavior,
- tests/checks run and results,
- hosted activation gate still unverified,
- one recommended next prompt.
```

## Prompt 7 — add Stripe review and dispatch operations, locally

```text
Work in /Users/macbookprom42025/Documents/GameTime.

Goal: locally complete the review, recovery, and bounded dispatch operations for
the already-gated Stripe sandbox beta. Do not change account deletion or app
navigation in this chat.

First read AGENTS.md, docs/BETA_LAUNCH_AUDIT.md,
docs/BETA_PRODUCT_DESIGN_AUDIT.md, PLAN.md, DECISIONS.md, the current Stripe
review/charge/webhook code and tests, Prompt 6's gate implementation, and
current official Stripe webhook, idempotency, SetupIntent, and testing
guidance. Inspect the current diff and preserve unrelated work.

Implement the smallest operational slice:
1. One named, bounded, secret-authenticated schedule for review expiry and
   simulated test-charge dispatch.
2. One founder-only audited review-decision route and short runbook for
   requested, upheld, waived, overdue, requires-action, and failed states.
3. One explicit resolution for requires_action/collection_failed:
   user-authorized continuation of the same PaymentIntent when valid or an
   audited founder waiver. Never silently create a second test charge.
4. Stable Stripe idempotency identity across ambiguous retries.
5. A privacy-safe health query for overdue review/dispatch work.

Record and pin the currently supported Stripe API and SDK versions. Do not
upgrade them in this slice unless a demonstrated beta-blocking requirement
forces a separately reviewed change. Continue to reject every live key and
livemode=true object.

Never log or persist raw card data, client secrets, secret keys, identity
tokens, full webhook bodies, or private profile/Health data.

Add focused database and Edge Function tests for review expiry/decision, signed
duplicate/reordered webhooks, one simulated charge, ambiguous transport,
same-PaymentIntent recovery, no automatic retry, gate-off behavior, other-user
isolation, bounded scheduling, and health counts.

Do not contact Stripe, alter Stripe Dashboard objects, use hosted test cards,
set hosted secrets, enable hosted schedules, deploy, publish, push, upload, or
submit TestFlight.

End with:
- what changed and why it matters,
- exact review/recovery/dispatch behavior,
- tests/checks run and results,
- hosted Stripe/webhook/schedule gates still unverified,
- one recommended next prompt.
```

## Prompt 8 — make account deletion Stripe-safe, locally

```text
Work in /Users/macbookprom42025/Documents/GameTime.

Goal: settle and locally verify only the backend/provider semantics for deleting
an account that used the Stripe sandbox. Do not build the iOS deletion flow in
this chat.

First read AGENTS.md, docs/BETA_LAUNCH_AUDIT.md,
docs/BETA_PRODUCT_DESIGN_AUDIT.md, the database deletion foundation, Stripe
sandbox migration/functions, Prompt 6's gates, Prompt 7's review/dispatch
behavior, public policy/terms, and current Stripe customer-deletion guidance.
Inspect all overlapping diffs and preserve unrelated work.

Extend the existing service-only deletion transaction/orchestration so:
- deletion serializes against review decisions, charge claims, and webhooks,
- a deleted actor can never later receive a simulated test charge,
- open/pending sandbox obligations become an explicit safe waiver/cancel state,
- the Stripe test Customer and saved test payment details are deleted/detached
  when safe,
- any temporary retained record is minimal, exact, and matches the public
  policy,
- a lost deletion response can retry without reopening or duplicating work,
- stale sessions and other users cannot act on the deleted account.

Do not expose service-role operations to authenticated clients. Never log
authorization codes, provider secrets, raw payment data, webhook bodies, Health
data, or private profiles.

Add focused database/Edge tests for deletion before setup, after method save,
during open/under-review states, beside charge claim and webhook races, after a
test charge, exact retry, provider deletion failure, stale actor, and account
recreation.

Do not contact Stripe, alter provider data, set hosted secrets, deploy, publish,
push, upload, or submit TestFlight.

Stop if retention/deletion wording or provider behavior needs a founder/legal
decision. Report the exact gate rather than inventing policy.

End with:
- what changed and why it matters,
- exact Stripe deletion/retention and race behavior,
- tests/checks run and results,
- hosted/provider gates still unverified,
- one recommended next prompt.
```

## Prompt 9 — implement account deletion end to end, locally

```text
Work in /Users/macbookprom42025/Documents/GameTime.

Goal: implement and locally verify the smallest secure in-app account-deletion
journey using the Stripe-safe backend contract from Prompt 8. Do not deploy it.

First read AGENTS.md, docs/BETA_LAUNCH_AUDIT.md,
docs/BETA_PRODUCT_DESIGN_AUDIT.md, the current deletion implementation and
tests, Prompt 8's settled semantics, and current Apple account-deletion and Sign
in with Apple revocation guidance. Inspect overlapping diffs and preserve
unrelated work.

Implement one narrow flow:
1. Show Delete Account under Account & Support only when the flow is complete.
2. Explain exact deletion/retention consequences.
3. Require destructive confirmation and fresh Sign in with Apple.
4. Capture the fresh authorization code and revoke the Apple token server-side.
5. Call one authenticated service-only deletion orchestrator with exact retry.
6. Clear session, App Attest, Health/background-delivery registration, and
   every owner-scoped pending store only after confirmed server success.
7. Show deleting, success/signed-out, retry, and Contact Support states.

Fail closed. A failed or uncertain response must not claim success. Never log
authorization codes, tokens, service keys, signed payloads, payment details,
Health data, or private profiles.

Add focused Edge Function, Swift, and UI tests for exact retry, stale/other
user, Apple revocation failure, server/provider failure, successful local
cleanup, accessibility, and account recreation.

Do not invoke real Apple revocation, contact Stripe, alter provider data, set
hosted secrets, deploy, publish, push, upload, or submit TestFlight.

End with:
- what changed and why it matters,
- exact visible deletion behavior,
- tests/checks run and results,
- hosted/Apple/physical-device gates still unverified,
- one recommended next prompt.
```

## Prompt 10 — prepare one distribution candidate

```text
Work in /Users/macbookprom42025/Documents/GameTime.

Goal: prepare the source/configuration/assets for one locally reviewable
iPhone-only distribution candidate. Do not run the full frozen-candidate
verification in this chat.

First read AGENTS.md, docs/BETA_LAUNCH_AUDIT.md,
docs/BETA_PRODUCT_DESIGN_AUDIT.md, docs/PERSONAL_V1_ACCEPTANCE.md, PLAN.md,
DECISIONS.md, README.md, the current Release/Staging configuration, privacy
docs, and the entire current worktree diff. Reconcile documentation only where
it contradicts the locked beta scope. Preserve dormant Social/Solo/live-Stripe
code, the intended Stripe sandbox path, and unrelated dirty work.

Prepare one Release/distribution path with:
- the final approved Apple bundle/App ID and matching Supabase Auth identity,
- distribution signing expectations for Sign in with Apple, HealthKit, and
  production App Attest,
- Personal creation/Health/trusted uploads enabled only for the intended
  distribution environment,
- server-authoritative stripe_sandbox settlement,
- only the Stripe sandbox payment route reachable; no live Stripe,
  custom-start, Social, or Solo route,
- only a `pk_test` publishable key in client configuration; `sk_test`, webhook,
  and dispatch secrets remain hosted secrets and never enter the app,
- an explicitly non-production Stripe beta backend, signed test webhook, beta
  allowlist, kill switch, and one bounded simulated-settlement schedule,
- a final beta-specific Stripe return scheme that matches the approved app
  identity and returns correctly on the processed TestFlight build,
- iPhone-only device family,
- no embedded or reachable Watch companion in this candidate; preserve any
  concurrent Watch source for later scope rather than deleting it,
- an original app icon in the correct asset catalog,
- an accurate PrivacyInfo.xcprivacy and required-reason API review,
- a unique version/build number,
- founder-provided privacy, terms, support, and feedback values,
- a documented App Review access strategy and accurate review notes.

Do not invent the final bundle ID, legal URLs, support contact, reviewer
credentials, privacy disclosures, or export-compliance answer. If any are not
confirmed, stop that portion and present the exact founder decision needed.

Run only targeted configuration/conformance checks and one local distribution
build when signing inputs permit. Prepare accurate beta description, What to
Test, reviewer instructions, privacy/support values, Stripe published test-card
instructions, and an external-action approval checklist. Do not claim archive,
hosted, physical-device, processed-TestFlight, or App Review proof.

Do not deploy Supabase changes, contact Stripe, alter Stripe Dashboard data,
change secrets, alter Apple identifiers or signing in an account, create App
Store Connect records, upload an archive, submit TestFlight review, send
invitations, commit mixed user work, push, or publish.

End with:
- what changed and why it matters,
- the prepared version/build and identity values,
- targeted checks run and results,
- every missing founder/provider value,
- one recommended next prompt.
```

## Prompt 11 — verify one frozen candidate

```text
Work in /Users/macbookprom42025/Documents/GameTime.

Goal: verify one exact, already-prepared iPhone distribution candidate and
produce a founder-readable go/no-go packet. Do not change product scope or fix
unrelated defects in this chat.

First read AGENTS.md, docs/BETA_LAUNCH_AUDIT.md,
docs/BETA_PRODUCT_DESIGN_AUDIT.md, docs/PERSONAL_V1_ACCEPTANCE.md, the Prompt 10
handoff, and the complete current diff. Confirm the intended candidate source
state, version/build, and local-stack ownership before running anything. If the
worktree changed after preparation or contains unresolved overlapping work,
stop and identify the exact gate rather than claiming a frozen candidate.

For that exact source state:
1. Run the existing repository, database, backend, Swift, iOS, and conformance
   gates once. Do not manually repeat green suites.
2. Build the distribution configuration and inspect the archive when signing
   inputs permit: identity, entitlements, production App Attest, iPhone-only,
   no embedded Watch companion, icon, privacy manifest, required-reason APIs,
   version/build, and bundled public configuration.
3. Complete a bounded simulator visual/accessibility pass for first launch,
   sign-in, onboarding, creation, Health recovery, Today, detail, PaymentSheet
   consent/recovery, every Payment test status, Account & Support, and deletion
   at normal and accessibility XXXL sizes.
4. Check VoiceOver order/labels/values/actions, contrast, 44-point targets,
   Reduce Motion, non-color state communication, and fixed-light appearance.
5. Validate that no live Stripe key/object/path, custom start, Social, Solo,
   payment secret, placeholder URL, or unreachable support action ships.
6. Produce the exact later hosted, physical-iPhone, processed-TestFlight, and
   App Review acceptance checklist without performing those actions.

Clearly label evidence as:
- verified source/configuration,
- verified local build/tests,
- verified archive inspection,
- unverified hosted backend/Stripe schedule/webhook,
- unverified physical-iPhone Health/App Attest,
- unverified processed TestFlight,
- unverified App Review.

Do not reset a user-owned database, repair unrelated work, deploy, set secrets,
contact Stripe, alter Apple/Stripe/Supabase accounts, upload an archive, create
App Store Connect records, submit TestFlight review, invite testers, commit
mixed user work, push, or publish.

End with:
- what was checked and why it matters,
- exact source state and version/build,
- test/build/archive/visual results,
- a go/no-go table with verified/unverified/unknown labels,
- the smallest next external action requiring explicit founder approval.
```
