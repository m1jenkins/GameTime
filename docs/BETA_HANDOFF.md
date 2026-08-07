# Better Bet external beta — handoff

**Written:** August 7, 2026
**Head commit:** `984845f feat: retire the staging identity and name the product Better Bet`
**Target:** invite-only TestFlight beta, no more than 10 named iPhone testers

This document is the current state of the work and the order to finish it. It
records what was verified by running it, not what other documents claim. Where
a claim is unproven it says so.

The product is now **Better Bet**. The repository, Xcode targets, schemes, and
most in-app prose still say GameTime; that is deliberate and explained under
[Loose ends](#loose-ends).

## How to re-check this document

Every line below can be re-derived. Nothing here needs to be taken on trust.

```bash
bash scripts/check-beta-candidate.sh   # shipping build settings
./scripts/test-all.sh                  # database, backend, and shared client
supabase migration list --linked       # what the hosted backend actually has
```

The Xcode suites are macOS-only and live in `.github/workflows/ci.yml`.

## Where things stand

### Green, verified by running it

| Suite | Result |
| --- | --- |
| Backend functions (Deno) | 389 pass; format, lint, and type-check clean |
| Shared client (GameTimeCore) | 103 pass |
| iPhone app, Xcode suite | Passes — unit tests plus 14 UI tests |
| Shipping build settings | `check-beta-candidate.sh`: **16 passed, 0 blockers** |
| Release build | Installs and opens to the signed-out screen |

### Red

**One database test fails.** `supabase/tests/420_production_attestation_provenance.test.sql`
fails at test 25 and then aborts, so 26 of a planned 32 assertions run. The
whole suite is 44 files and 1,732 assertions; this is the only failure.

The test expects `record_trusted_personal_diagnostic_v1` called with a
development key to reach the hold-clearance trigger added in
`20260806145502_production_diagnostic_clearance_guard.sql` and raise `23001`
with *only a production-origin trusted diagnostic may clear Personal
eligibility*. It instead gets `42501`, *the trusted device assertion could not
be accepted*, from an assertion check that runs earlier.

Both outcomes refuse the development diagnostic, so the fail-closed guarantee
holds either way. What is wrong is that the test and the implementation
disagree about which layer refuses it, and the later assertions never run. The
fix is a judgment call nobody has made yet: either the test asserts the wrong
error, or the earlier check makes the trigger unreachable on this path and the
trigger belongs somewhere else.

### Behind

The hosted backend is **five migrations behind** the repository:

```
20260806143539_production_attestation_provenance
20260806144639_production_attestation_settlement_guards
20260806145058_production_diagnostic_provenance_audit
20260806145502_production_diagnostic_clearance_guard
20260806173723_personal_result_worker
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

### Step 4 — Fix the failing database test

Decide whether `420_production_attestation_provenance.test.sql` test 25 is
asserting the wrong error, or whether the clearance trigger is unreachable and
belongs at a different layer. Fix one side, then confirm the file runs all 32
assertions.

**Done when:** `./scripts/db-test.sh` exits zero.

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

### Step 6 — Stripe kill switch and beta allowlist

No allowlist or kill switch for Stripe exists anywhere in the migrations. The
only allowlist in the repository belongs to the dormant Solo domain. Earlier
planning documents assert these controls exist; they do not.

They must be enforced at the database mutation boundary, not in an Edge
Function. Authenticated users can execute some Stripe setup and creation RPCs
directly, so a function-level switch is bypassable.

Turning the switch off must stop new setup, commitments, charge-authorizing
decisions, and dispatch, while still allowing owner status reads, signed
webhook reconciliation, and audited no-charge or waiver resolution for
obligations that already exist.

**Done when:** flipping the switch off blocks new payment activity and leaves
existing obligations resolvable, proven by pgTAP.

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

1. Push the five pending migrations.
2. Redeploy the changed Edge Functions.
3. Enable the Personal result worker schedule. The worker is written and its
   tests pass, but `20260806173723` creates the job dormant, and nothing
   currently schedules it. Without it a finished challenge never resolves.
4. Confirm the hosted Stripe secrets, the webhook destination, and its
   signature verification.
5. Read back `app.solo_contract_runtime` and `app.solo_beta_eligibility` on the
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
- *1,678 pgTAP assertions, green* no longer holds. The suite is now 1,732
  assertions with one failing file, introduced by work that was uncommitted
  when those documents were written.

The audits also read as though a large amount of engineering remains. It does
not. The core loop — sign in, create a challenge, read Health, accumulate
progress — works and is well covered. What remains is mostly the thin layer
around it: deletion, support, payment status, and hosted publication.
