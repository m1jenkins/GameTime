# Better Bet external beta — handoff

**Written:** August 7, 2026
**Revised:** August 12, 2026 — automatic Health snapshot v2 is the active path
**Product head:** `984845f feat: retire the staging identity and name the product Better Bet`
**Target:** invite-only TestFlight beta, no more than 10 named iPhone testers

This document records what was verified by running it. The August 7 inventory
and numbered steps remain below for provenance; the replacement handoff here is
the current order.

The product is now **Better Bet**. The repository, Xcode targets, schemes, and
most in-app prose still say GameTime; that is deliberate and explained under
[Loose ends](#loose-ends).

## August 12 controlling handoff

New and eligible migrated Personal challenges use
`healthkit_nonmanual_daily_v1`. The August 7 manual-sync, hourly coverage,
diagnostic/eligibility-hold, positive-step readiness, and Personal production
App Attest work is frozen as historical `attested_hourly_v1` context. Generic
and social App Attest infrastructure remains; it is not a Personal-v2 launch
gate.

Finish in this order:

1. Complete and locally verify the separate Health reader, protected
   whole-snapshot cache, authenticated uploader, automatic trigger/coalescing
   store, clean v2 list/detail models, and frozen-result display.
2. Complete and locally verify the backend snapshot policy, owner-derived v2
   RPC, RLS/grants, idempotent replacement rules, finalizer, and migration.
3. Reconcile copy, permission text, privacy, acceptance, candidate preflight,
   and App Review notes with the automatic flow.
4. Deploy backend support with the named result schedule inactive and run the
   isolated authenticated/RLS/replay/lower-total/finalization/Stripe smoke.
5. Make the v2 iOS build mandatory for the named beta cohort.
6. Resolve already-due v1 challenges; preserve completed/cancelled history; then
   migrate only unresolved future-cutoff challenges and require a fresh full
   Health read.
7. Activate the result schedule as a separate approved action only after smoke,
   then prove one firing, immutable rerun, and emergency disable.
8. Run the physical-iPhone acceptance in
   [PERSONAL_HEALTH_SNAPSHOT_V2_ACCEPTANCE.md](PERSONAL_HEALTH_SNAPSHOT_V2_ACCEPTANCE.md),
   followed by the existing sandbox review/settlement and deletion journeys.

Do not translate hourly evidence, delete historical audit rows, require a
positive Health sample, restore a step-specific sync control, or treat legacy
App Attest conformance as Personal-v2 acceptance.

## August 7 verification record

Everything below this heading is the pre-snapshot-v2 handoff. Counts and
observations remain evidence for that revision, but its Personal trust gates and
rollout order no longer control.

## How to re-check this document

Every line below can be re-derived. Nothing here needs to be taken on trust.

```bash
bash scripts/check-beta-candidate.sh   # shipping build settings
bash scripts/check-beta-candidate.sh --personal-copy-only
                                      # removed Personal manual-sync copy/hooks
./scripts/test-all.sh                  # database, backend, and shared client
supabase migration list --linked       # what the hosted backend actually has
```

The Xcode suites are macOS-only and live in `.github/workflows/ci.yml`.

## Where things stand

### Green, verified by running it

| Suite | Result |
| --- | --- |
| Database (pgTAP) | 46 files, 1,815 assertions, all pass |
| Backend functions (Deno) | 391 pass; format, lint, and type-check clean |
| Shared client (GameTimeCore) | 103 pass |
| iPhone app, Xcode suite | Passes — unit tests plus 14 UI tests |
| Shipping build settings | `check-beta-candidate.sh`: **16 passed, 0 blockers** |
| Release build | Installs and opens to the signed-out screen |

### Behind

The last verified hosted snapshot was **five migrations behind** the repository.
The local Stripe controls add a sixth unhosted migration:

```
20260806143539_production_attestation_provenance
20260806144639_production_attestation_settlement_guards
20260806145058_production_diagnostic_provenance_audit
20260806145502_production_diagnostic_clearance_guard
20260806173723_personal_result_worker
20260807151320_personal_stripe_sandbox_beta_controls
```

Six Edge Function source files have also changed locally since the hosted
functions were last published. Eleven functions are deployed and `ACTIVE`.

## Evidence boundary

Green local suites are a regression foundation, not proof of a shipped app.
None of the following has been demonstrated:

- The processed TestFlight archive, its signing, or App Review approval.
- Production App Attest. A simulator cannot exercise it, and no device has
  completed a signed diagnostic or coverage submission against the hosted
  endpoints.
- HealthKit reads on a real phone. The simulator has no first-party device step
  samples, so creation stays blocked there by design.
- Any hosted behavior of the result worker, the Stripe sandbox loop, or
  two-account privacy on real infrastructure.
- Sign in with Apple under the new bundle identifier.

## Remaining steps, in order

### Step 4 — Fix the failing database test — **done**

Neither side of the judgment call was the problem. The test fixture registered
its two App Attest keys by inserting straight into `public.device_attestations`,
so neither key ever got the verified receipt row that
`app.consume_trusted_personal_assertion` requires. That check runs before
anything reads provenance, so it refused both keys with `42501` and the
clearance trigger was never reached.

The trigger is not unreachable. `consume_trusted_personal_assertion` checks
that a key is registered, unrevoked, and receipt-verified; it says nothing
about environment. A development-environment key that clears it lands on the
trigger, which is exactly the case the guard exists for. The two are layered,
not competing.

The fixture now registers both keys through `register_device_key` and
`mark_device_receipt_verified`, the way a device does. Test 25 fails closed on
the trigger's own `23001` and message, test 26 exercises a rollback that really
happens, and tests 27 to 32 run for the first time.

**Done:** `./scripts/db-test.sh` exits zero — 44 files, 1,738 assertions.

> `db-test.sh` resets the local database from migrations. It destroys local dev
> data. Back it up first if a device-test record matters:
> `pg_dump "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f backup.sql`

### Step 5 — Account & Support, including account deletion

The app has no way to delete an account. Apple requires one for any app that
creates accounts, and will reject the build without it. The `You` tab currently
holds a username, a Steps row, a privacy explainer, and Sign Out.

Add one **Account & Support** destination under `You` containing Health help,
Privacy Policy, Beta Terms, Contact Beta Support, the app version and build,
Sign Out, and Delete Account. Reuse its support route from launch, Health,
cancellation, detail, result, and deletion failures. Resist adding several
settings screens.

Delete Account must complete fresh authentication, revoke the Sign in with
Apple token, delete or disclose retention of the Stripe test Customer and
payment method, call the server deletion operation, clear local pending
requests, App Attest state, and session, and show honest success, retry, and
support states.

The database side already exists as `app.delete_account`. What is missing is
the Edge Function and the entire client surface — the app contains zero
references to deletion, privacy policy, terms, or support today.

**You must supply:** a real published privacy policy URL and a real monitored
support email. Do not invent either.

**Done when:** a tester can delete their account in the app, recreate it, and
every link in Account & Support resolves.

### Step 6 — Stripe kill switch and beta allowlist — **source done; rollout pending**

Migration `20260807151320_personal_stripe_sandbox_beta_controls` now provides a
database-owned global switch and exact-owner beta allowlist. It is seeded
disabled with no eligible owners. Only the service role can change either
control, and each change uses an exact-request ledger so a reused request ID
cannot silently change meaning.

The controls sit in the shared database mutation paths, so direct authenticated
RPC calls cannot bypass an Edge Function. While disabled they stop new payment
setup, commitments, charge-authorizing miss decisions, automatic confirmation,
command creation, and dispatch. Rows admitted under these controls carry frozen
authorization provenance; older rows are not retroactively treated as approved.

Disabling or revoking access does not strand safe work. Exact authorized retries,
owner status reads, review filing, waiver/no-charge resolution, setup-result
recording, signed webhook reconciliation, and provider-result reconciliation
remain available where appropriate. A disabled worker still performs the
fail-safe automatic waiver for an overdue unresolved review but returns no
charge work.

Focused pgTAP coverage proves default-off state, exact allowlisting,
cross-account refusal, stale-account refusal, direct-RPC enforcement, retry
semantics, disabled-state behavior, and reconciliation. Real-session races also
prove an admitted request and an atomic shutdown cannot deadlock, and account
deletion cannot overlap charge-command creation or leasing. The clean rebuild
passes 46 database files and 1,815 assertions; the full function suite passes
391 tests.

**No hosted project was changed.** The migration is unapplied, and the existing
hash-locked five-migration rollout packet does not include it. Regenerate and
review that packet before any hosted action; deploying, enabling the switch, and
adding named tester IDs each remain separately approval-gated.

### Step 7 — Payment status and a next action on Today

Two related gaps.

**Challenge detail shows no settlement status.** The database exposes
`get_my_personal_stripe_sandbox_status_v1`; the app calls it zero times. A
tester cannot see whether a test charge is pending, succeeded, needs attention,
or failed. Add one payment status card driven by the authoritative server
state. The app may refresh status but must never create a charge, infer success
from client state, or poll Stripe in a loop.

`requires_action` and `collection_failed` currently have no recovery route and
can block a tester indefinitely. Add one explicit user-authorized recovery on
the same PaymentIntent, or a founder-reviewed waiver. It must resolve the
existing sandbox command rather than silently creating a second one.

**Today states no next action.** It shows a status pill, the frozen terms, a
progress bar, and See details. Add one sentence giving the next action and the
exact local deadline for the scheduled, active, final-sync, result-pending,
overdue, and final states.

Every visible payment state must say it is test mode wherever that could be
ambiguous.

**Done when:** every reachable challenge and result state shows a correct next
action, a real deadline, and honest payment status.

### Step 8 — Publish to the hosted backend

Only after Steps 4 to 7 pass locally.

1. Regenerate the rollout packet for all six pending migrations, obtain the
   required approvals, and only then push that exact reviewed set.
2. Redeploy the changed Edge Functions.
3. Enable the Personal result worker schedule. The worker is written and its
   tests pass, but `20260806173723` creates the job dormant, and nothing
   currently schedules it. Without it a finished challenge never resolves.
4. Confirm the hosted Stripe secrets, the webhook destination, and its
   signature verification.
5. Read back `app.personal_stripe_sandbox_runtime` and
   `app.personal_stripe_sandbox_beta_eligibility` after migration and prove they
   are still disabled and empty. Enabling the switch or adding any tester UUID
   requires a separate explicit approval.
6. Read back `app.solo_contract_runtime` and `app.solo_beta_eligibility` on the
   hosted project. The Solo tables are present there. The migrations create the
   domain switched off with an empty allowlist, but the hosted runtime values
   have never been read back, so nobody has confirmed Solo is inert.

**This is a consequential external step. Get explicit approval before running
it.**

**Done when:** `supabase migration list --linked` shows nothing pending, and an
accelerated hosted smoke test proves one result, one incomplete result, one
review outcome, one test settlement, and a safe rerun.

### Step 9 — Prove it on a real iPhone

A simulator cannot prove HealthKit or production App Attest. Run six journeys
on the exact processed TestFlight build: identity, creation, trusted sync,
recovery, backend safety and sandbox settlement, and deletion. Run the common
journeys with VoiceOver and Larger Text, and confirm 44-point touch targets,
sufficient contrast, and that no state is communicated by color alone.

### Step 10 — Submit and invite

Freeze one reviewed commit and record its build number and backend versions.
Prepare the TestFlight beta description, What to Test, feedback email, review
contact, privacy URL, reviewer access instructions, Stripe's published
test-card values with an explicit never-use-a-real-card warning, and the
export-compliance answer.

Apple reviews the first external build before testers can join. After approval,
invite no more than 10 named testers. During the first cohort check crashes,
feedback, backend errors, and overdue challenges once a day, and stop new
invitations if a core journey fails.

## Outside this repository

These are not code changes and nobody can make them from the codebase.

- **Register `com.mjenkins.gametime` as an Apple App ID** with Sign in with
  Apple, HealthKit, and App Attest enabled. Release moved to this identifier on
  `984845f`; Debug and Staging keep `com.mjenkins.gametime.staging`.
- **Update the Sign in with Apple client ID in Supabase Auth** to match. Until
  both are done, sign-in fails on a device, and test accounts tied to the old
  identifier will not carry over.
- **Publish a privacy policy** at a stable URL.
- **Set up a monitored support inbox.**
- Confirm distribution signing for Sign in with Apple, HealthKit, and App
  Attest.

## Traps on this machine

**Every `git commit` hangs.** The global `~/.gitconfig` declares git-lfs
filters, but git-lfs is not installed, so commits block trying to spawn
`git-lfs filter-process` and leave a stale zero-byte `.git/index.lock`. The
real fix is `git config --global --remove-section filter.lfs` or
`brew install git-lfs`. Until then, prefix commits:

```bash
git -c filter.lfs.required=false -c filter.lfs.process= -c filter.lfs.clean=cat -c filter.lfs.smudge=cat commit -m "..."
```

**Disk space.** The volume filled during the August 6 audit and Release builds
failed at the dSYM `lipo` step with *No space left on device*. Roughly 12 GB was
reclaimed from Xcode's `DerivedData`, the SwiftUI Previews cache, and the npm
cache. Two reserves remain untouched: iPhone debug symbols (~6.5 GB) and unused
Docker images (~6.3 GB). Archiving for TestFlight needs several GB free.

**Wiping `DerivedData` also wipes resolved Swift packages.** Re-resolve before
building:

```bash
xcodebuild -resolvePackageDependencies -project ios/GameTime/GameTime.xcodeproj -scheme GameTime
```

## Loose ends

Small, known, and deliberately deferred.

- About 25 in-app prose strings still say GameTime, for example *We couldn't
  reach GameTime right now*. The August 7 rename covered the identity and what
  a tester sees — home-screen name, Health prompt, Stripe merchant name,
  wordmark, and VoiceOver labels — and stopped there.
- The wordmark is now `B//B`, mechanically mirroring the old `G//T`. It is a
  placeholder, not a designed mark.
- The Watch app's display name is still GameTime. The Watch is not embedded in
  the iPhone candidate, and `check-beta-candidate.sh` asserts that.
- The Staging build's Health prompt in `Configuration/StagingAppInfo.plist`
  uses *trusted diagnostic*. Both words are banned on screen by
  [COPY.md](COPY.md). Pre-existing and Staging-only.
- [README.md](../README.md) says all six Edge Functions are deployed. Eleven
  are. It also still presents the custom start-hour picker as a headline
  feature; the beta defers it and the creation flow already hides that step,
  along with the single-option metric step.
- `ios/GameTime/GameTime Watch App Watch App/` is an empty leftover from an
  Xcode template and is referenced by nothing.

## What earlier documents get wrong

Read [BETA_LAUNCH_AUDIT.md](BETA_LAUNCH_AUDIT.md) and
[BETA_PRODUCT_DESIGN_AUDIT.md](BETA_PRODUCT_DESIGN_AUDIT.md) for scope and
reasoning; both are useful. Two corrections from the August 6–7 verification
pass:

- Neither records that **the Release build could not open at all**. It threw
  `invalidStripeReturnURL` during configuration loading and rendered its
  failure screen instead of a product. Fixed on `984845f`.
- *1,678 pgTAP assertions, green* is the right shape but the wrong number. Step
  4 restored the then-current 1,738 assertions; the locally implemented Stripe
  controls and their focused coverage now bring the clean suite to 1,815
  assertions. [Step 4](#step-4--fix-the-failing-database-test--done) records the
  earlier fixture repair and [Step 6](#step-6--stripe-kill-switch-and-beta-allowlist--source-done-rollout-pending)
  records the new local-only control boundary.

The audits also read as though a large amount of engineering remains. It does
not. The core loop — sign in, create a challenge, read Health, accumulate
progress — works and is well covered. What remains is mostly the thin layer
around it: deletion, support, payment status, and hosted publication.
