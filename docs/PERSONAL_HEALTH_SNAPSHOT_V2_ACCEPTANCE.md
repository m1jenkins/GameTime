# Prove automatic Apple Health Personal progress

This is the controlling acceptance runbook for Personal challenges with
`step_data_policy = healthkit_nonmanual_daily_v1`. It proves automatic local
progress, ordinary authenticated snapshot upload, server finalization, frozen
history, and safe migration from unresolved Personal v1 challenges.

It does not rewrite completed or cancelled `attested_hourly_v1` history, prove
Apple Health behavior in Simulator, authorize hosted deployment, activate Cron,
publish TestFlight, or enable real payments. Stripe remains test-only.

## Locked contract

- Apple Health supplies its merged step total across compatible writers.
- Exclude only samples where `HKMetadataKeyWasUserEntered == true`.
- A writer that omits that marker is indistinguishable from automatic data.
- Completing **Connect Apple Health** is enough to create; no positive sample is
  required.
- One whole snapshot contains challenge ID, frozen-terms fingerprint,
  observation time, query-through time, and exactly seven ordered daily totals.
- The total is derived from those days. Never combine days from separate reads.
- A successful zero or lower value is authoritative. Preserve an older snapshot
  only when the Health query throws or data is temporarily unavailable.
- Local progress updates before upload. Network failure never hides it.
- Personal v2 has no App Attest, hourly coverage, diagnostic, eligibility hold,
  or step-specific sync control.
- Grace remains exactly 24 hours. Stripe remains sandbox-only.
- The final server result and its seven copied daily totals are immutable.

## Keep proof layers separate

Record local repository, Simulator, hosted Staging, processed TestFlight, and
physical-device evidence independently. A green layer does not imply the next.

Record only bounded identifiers, policy values, timestamps, HTTP status classes,
row counts, test counts, and result codes. Do not record raw Health samples,
access or refresh tokens, database credentials, full request bodies, payment
secrets, Apple private material, or another account's data.

## Repository-local gate

Run:

```sh
./scripts/test-all.sh

xcodebuild \
  -project ios/GameTime/GameTime.xcodeproj \
  -scheme GameTime \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  CODE_SIGNING_ALLOWED=NO \
  test

bash scripts/tests/check-beta-candidate.test.sh
git diff --check
```

Repository exit criteria:

- [ ] Every migration applies from an empty local database.
- [ ] pgTAP proves v2 authentication, authorization, idempotency, cutoff,
      finalization, migration, and immutable history behavior.
- [ ] Deno and Swift checks pass.
- [ ] Product unit and UI tests pass with no skipped v2 scenario.
- [ ] Debug, Staging, and Release simulator builds compile.
- [ ] Candidate-preflight fixtures pass without requiring Personal App Attest.
- [ ] A copy audit finds none of the removed Personal phrases or identifiers.
- [ ] Generic/social App Attest and historical Personal v1 regression suites
      remain green and explicitly separate from v2 acceptance.

## Health mapping

Use deterministic Health-reader tests for each case:

- [ ] The reader requests step count only.
- [ ] It queries each exact frozen local date with cumulative statistics.
- [ ] During an active challenge, `queryThrough` is the current moment and
      today's total is partial.
- [ ] During grace, the query is capped at the challenge end so late Watch data
      may revise any challenge day but post-window steps cannot enter.
- [ ] iPhone, Watch, and other compatible writers are merged by HealthKit rather
      than summed as disjoint sources.
- [ ] Samples explicitly marked manually entered are excluded.
- [ ] Samples with missing manual-entry metadata remain included.
- [ ] A successful all-zero query returns a seven-day zero snapshot.
- [ ] A later lower query returns the lower whole snapshot.
- [ ] A historical custom-hour start clips only the applicable first local day.
- [ ] The frozen timezone, not the phone's current travel timezone, owns dates.
- [ ] Spring-forward and fall-back dates remain one local day and produce
      exactly seven ordered date totals.
- [ ] A malformed date plan, unavailable Health data, or thrown query produces
      an error rather than a fabricated zero.

## Protected cache and automatic store

Prove the cache is keyed by authenticated account and challenge and bound to the
frozen-terms fingerprint:

- [ ] Save and restore one complete snapshot without changing any field.
- [ ] A new whole snapshot atomically replaces the old one.
- [ ] Corrupt bytes, unsupported versions, wrong account, wrong challenge, or a
      fingerprint mismatch are rejected.
- [ ] No path merges individual days from multiple snapshots.
- [ ] Sign-out and account switch remove the prior account's displayed state.
- [ ] A server-reported v2 policy retires old Personal hourly pending queues and
      local eligibility-hold state without deleting server audit rows.

Exercise every automatic trigger:

- [ ] Health permission request completion.
- [ ] Active challenge load.
- [ ] Challenge creation.
- [ ] App launch.
- [ ] Foreground transition.
- [ ] HealthKit observer change.
- [ ] General pull to refresh.

Concurrency and failure behavior:

- [ ] Overlapping triggers produce one active read and at most one trailing read.
- [ ] Repeated triggers while the trailing read is pending remain coalesced.
- [ ] Account or challenge switching cancels work or discards its late result.
- [ ] A successful read publishes to the UI and cache before upload begins.
- [ ] Offline or rejected upload leaves the displayed Health value unchanged.
- [ ] Reconnect uploads the latest whole snapshot, not every superseded read.
- [ ] Query failure retains the previous value and marks its update time stale.
- [ ] Successful zero clears an older positive value.
- [ ] A late Watch update replaces all seven days coherently.
- [ ] At cutoff, publication/finalization serialization yields either the final
      accepted snapshot or the already-frozen result, never a mixed history.

## Display precedence and product UI

Before cutoff, prove this exact order:

1. Latest successful live Health snapshot.
2. Matching protected local cache.
3. Server snapshot.
4. Legacy result fallback.

After cutoff, prove frozen server result first, then local fallback only when the
server is temporarily unavailable.

Across Today, the current Challenges card, challenge detail, seven-day timeline,
and pace components:

- [ ] The same total and daily values appear without tapping a sync action.
- [ ] An optional quiet line reads **Updated from Apple Health …**.
- [ ] During grace, copy reads **We'll keep checking Apple Health through …**
      with the exact frozen local cutoff.
- [ ] A transient Health error retains progress and marks its time stale.
- [ ] With no snapshot, copy reads **No step data available yet** and routes to
      Apple Health access help in settings.
- [ ] Completed screens always show the frozen result, even if current Health
      later changes.
- [ ] Generic pull to refresh remains available.
- [ ] The only Health-specific permission action is **Connect Apple Health**.

The reachable v2 UI must contain none of:

- **Sync my steps**
- **Send saved steps**
- **Not synced**
- **not confirmed** when referring to steps
- **Steps received**
- **Step syncing**
- coverage or completed-hour status
- diagnostic or eligibility-hold recovery
- Personal App Attest language
- `personal.sync`, `personal.sync.pending`, `personal.diagnostic.run`, or
  `personal.eligibility-hold` accessibility identifiers

Payment copy may still use **confirmed miss after review**; do not ban that
separate settlement phrase.

## Database and RPC

Prove the v2 data boundary with at least two independent authenticated actors:

- [ ] `step_data_policy` is frozen per challenge and accepts only the reviewed
      historical and automatic values.
- [ ] Completed/cancelled history remains `attested_hourly_v1` unless it was
      already created under v2; no migration rewrites it.
- [ ] `upsert_my_personal_health_snapshot_v2` derives the caller from auth and
      accepts no client owner ID.
- [ ] `anon` and cross-account calls fail.
- [ ] Authenticated clients have no direct mutable snapshot-table write grant.
- [ ] Owner reads expose only the clean v2 list/detail projection.
- [ ] Exactly seven ordered frozen local dates are required.
- [ ] Negative, non-finite, fractional, excessive, missing, duplicate, or extra
      totals fail.
- [ ] Future challenge dates must be zero.
- [ ] Observation and query-through timestamps obey lifecycle, clock-skew, end,
      and cutoff bounds.
- [ ] Wrong challenge, owner, policy, terms fingerprint, or lifecycle fails.
- [ ] An older observation is ignored without replacing the current row.
- [ ] An identical replay succeeds.
- [ ] Equal observation time with changed payload fails.
- [ ] A newer lower snapshot replaces the entire current row.
- [ ] Concurrent upserts serialize to one valid latest snapshot.
- [ ] Direct UPDATE/DELETE and unauthorized function execution fail.
- [ ] Results expose plain daily steps, observation/update times, policy, and
      terminal outcome without trusted, coverage, diagnostic, or assessment
      fields.

## Cutoff finalization and Stripe sandbox

At exactly `ends_at + 24 hours`:

- [ ] A snapshot queried through `ends_at` produces the normal daily or
      cumulative met/missed comparison.
- [ ] Missing snapshot or incomplete `queryThrough` produces commitment-waived
      `inconclusive`.
- [ ] Finalization copies the selected seven totals into the immutable result.
- [ ] The mutable open snapshot is removed in the same protected operation.
- [ ] A v2 result has no required legacy evidence-assessment reference.
- [ ] An exact rerun returns the existing result.
- [ ] A conflicting rerun cannot rewrite totals, outcome, or timestamps.
- [ ] A late upload racing finalization either commits before the freeze and is
      selected or loses after the immutable result; it cannot mutate history.
- [ ] `met_goal` creates no review or test charge command.
- [ ] `inconclusive` creates no review or test charge command.
- [ ] Only a complete `missed_goal` may open Stripe sandbox review.
- [ ] Stripe accepts test-mode objects only and no real payment processing is
      enabled.

## Backend-first rollout and cutover

Do not activate the result schedule while applying backend support.

1. Freeze and review the exact forward migration/RPC/function artifacts.
2. Apply backend support with Cron inactive.
3. Read back grants, RLS, function execute privileges, policy defaults, and job
   inactivity.
4. Run isolated authenticated smoke cases for owner success, cross-account
   refusal, malformed data, replay/stale/conflict, lower replacement, complete
   finalization, missing finalization, immutable rerun, and Stripe routing.
5. Make the v2-capable iOS build mandatory for the named beta cohort.
6. Inventory unresolved v1 scheduled, active, and grace-period challenges.
7. Resolve already-due v1 challenges before migration.
8. Leave completed and cancelled v1 history unchanged.
9. Migrate only unresolved open challenges whose cutoff remains in the future.
10. Require a fresh full Health read after migration; never translate hourly
    metrics or coverage into daily snapshot totals.
11. Confirm old local queues/holds retire only after the server reports v2.
12. Activate the existing result schedule as a separate approved step only
    after smoke passes, then verify one real firing and a safe rerun.

Cutover exit criteria:

- [ ] The mandatory-build gate prevents an older Personal client from operating
      a migrated challenge.
- [ ] Migration is idempotent and preserves frozen challenge terms.
- [ ] No already-due, completed, or cancelled row is reinterpreted.
- [ ] Server audit rows remain; destructive historical cleanup does not occur.
- [ ] Every migrated challenge requests a fresh automatic Health snapshot.
- [ ] The named result job is unique, active only after approval, observable,
      and separately disableable.

## Physical-device acceptance

Run on the exact signed candidate and record device/OS/build identifiers without
recording raw Health values:

- [ ] Fresh install and first **Connect Apple Health** permission flow.
- [ ] Permission completion allows creation with zero available steps.
- [ ] iPhone-only progress appears automatically after challenge creation.
- [ ] Watch-written steps catch up after delayed synchronization.
- [ ] A real observer wake triggers refresh in each enabled build configuration.
- [ ] Debug, Staging, and Release register observation on physical devices;
      fixtures, UI-test environments, and Simulator do not.
- [ ] A locked-device/unavailable read retains the prior snapshot and retries
      after unlock/foreground.
- [ ] Offline read displays locally; reconnect uploads without changing it.
- [ ] Foregrounding guarantees a new read even when no background wake occurred.
- [ ] General pull to refresh recovers without exposing a step-specific action.
- [ ] Challenge end caps the query at `ends_at`.
- [ ] Late Watch data during the full 24-hour grace updates the open snapshot.
- [ ] The cutoff freezes one immutable result and completed history remains
      stable afterward.

## Completion record

- [ ] Local repository gate complete.
- [ ] Hosted backend-v2 smoke complete with Cron inactive.
- [ ] Mandatory v2 build gate active for the beta cohort.
- [ ] Eligible unresolved challenge migration complete and audited.
- [ ] Physical-iPhone automatic-flow acceptance complete.
- [ ] Result schedule separately activated and observed.
- [ ] Frozen history and Stripe sandbox routing complete.
- [ ] Privacy policy, permission text, product copy, README, plan, decisions,
      beta handoff, and reviewer notes all describe the same policy.

Even a fully checked run does not approve real money. The trusted-client model,
Health/manual-entry limitations, legal terms, processor approval, App Review,
age/jurisdiction controls, and production operations require a new reviewed
policy before live payments.
