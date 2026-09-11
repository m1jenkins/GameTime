# GameTime remaining implementation plan

**Prepared:** September 8, 2026  
**Planning baseline:** clean First Mate continuation `fm/gametime-beta-real-validation-c8` at `9ce9ea6`  
**Finish line:** external Beta 1 / TestFlight readiness, simulated nonredeemable amounts only  
**Status:** implementation plan, not authorization to deploy, distribute, recruit, delete data, or enable money  
**Design:** explicitly out of scope; functional accessibility and state correctness remain in scope

This plan continues the adopted friend-duels and personal-performance-commitments
direction. It does not reinterpret or migrate historical Personal, Solo, duel,
performance, or weekly agreements. The pre-c8 roadmap remains useful history, but
its implementation-status claims are superseded by the clean c8 acceptance ledger.

## Outcome

GameTime already has a substantial **local fictional Beta implementation**. The
remaining work is not “build the entire new app.” It is to turn that candidate into
a source-backed, scalable, operable, physically verified release:

1. preserve and land the clean c8 work without losing the dirty original checkout;
2. make the c8 candidate and controller suites repeatable, skip-free, and CI-ready;
3. remove the global database mutex and other known Beta-scale bottlenecks;
4. finish the operator-published private community cohort, including the selected
   delayed-count privacy contract and 250-person Beta capacity;
5. read eligible Apple Watch-origin activity through HealthKit on the iPhone, with
   no dedicated GameTime watchOS app;
6. upload only minimum, versioned challenge facts with correction/replay protection;
7. perform physical iPhone/Watch source acceptance when hardware is available;
8. prove the selected Beta load envelope on a dedicated nonproduction environment;
9. complete hosted, operational, human, accessibility, and release-candidate gates.

Work should continue while the Apple Watch is being sourced. Physical Watch evidence
remains a hard launch gate, but it is not a reason to leave the database, test,
community, native integration, or Health abstraction work idle.

## Locked owner decisions

| Topic | Adopted planning decision | Implementation consequence |
| --- | --- | --- |
| Apple Watch | GameTime reads Apple Watch-origin data after it reaches the iPhone HealthKit store. There is no GameTime watchOS app. | Do not build WatchConnectivity, a Watch UI, or workout controls. Treat late Watch sync, overlap, provenance, edits, and deletions as iPhone HealthKit source-policy cases. |
| Community Beta | Start with one operator-published private steps cohort. | Finish and harden c8's existing community domain; keep publication operator-only and default-off. |
| Future community | People may eventually host community challenges. | Add narrow publisher/ownership seams now, but do not expose user publication in Beta 1. Future publishing needs separate safety, abuse, discovery, and acceptance work. |
| Community counts | Exact anonymous aggregate counts are visible only when the disclosure cohort has at least five joined, active, nonremoved participants, and are delayed by at least 15 minutes. | Return a non-exact threshold state below five; publish fixed-cadence aggregate snapshots with `as_of`, never live per-person changes. The privacy threshold is not the challenge outcome minimum. |
| Beta capacity | 2,000 registered accounts, 250 DAU, 100 concurrent sessions, 25 requests/second burst, one 250-person community cohort. | This is the Beta acceptance envelope. Current c8's 100-person cap and singleton lock do not meet it. |
| Long-term capacity | 25,000 registered accounts, 5,000 DAU, 1,000 concurrent sessions, 150 requests/second burst, one 10,000-person cohort. | Choose data shapes and lock ownership that do not require another aggregate rewrite, but do not block Beta on a full long-term hosted load pass. |

## Audited baseline: what is actually done

The clean c8 continuation is 22 commits ahead of `origin/main`; it has not been
pushed or merged. The original checkout remains on `577bc32` with extensive
uncommitted product, copy, and design changes. Every implementation prompt must
start by resolving this provenance rather than assuming `main` is current.

| Area | Verified in c8 | Still missing |
| --- | --- | --- |
| New challenge aggregate | Separate forward `challenge_*_v1` migrations, immutable agreements, lobby/reconsent, exact requests, lifecycle, corrections, reviews, exits, finals, links, safety, and all 13 policies. | Real-source agreement versions and real ingestion. Do not rebuild the aggregate. |
| Native Beta product | Debug/local Home · Challenges · You shell; authenticated local HTTP across all 13 policies; full two- and six-person steps touch journeys. | The new shell/client is still Debug/loopback-only; Release remains the legacy route and candidate checks still expect legacy Stripe sandbox behavior. A hosted HTTPS client, nonredeemable Release route, broader full-UI matrix, signed-device, and human acceptance are missing. |
| Correctness evidence | 3,882 SQL assertions / 84 files, 835 Deno tests, 113 core Swift tests, 396 native cases (392 pass, four controller skips), 20 separate authenticated HTTP cases. | One fresh skip-free committed-candidate gate, c8 CI, migration-upgrade proof, fault/load/physical/human layers. |
| Recent bugs | Five reproduced lifecycle/privacy defects fixed: reopened draft finalization, unreadable pending-request privacy, hung refresh expiry, outsider block disruption, and departed-member disclosure. | Independent diff review, full post-c8 historical UI/Release rerun, regression mutation/fuzzing, and new findings listed below. |
| Community | Local fictional publication, catalog, join, consent/readiness, capacity, own-only detail, anonymous counts, report/block/removal, scoped operator actions, and closure. | Selected delayed-count behavior, 250 capacity, scalable locks/rollups, real steps, settings, hosted operator/support process, retention, human acceptance. |
| Health investigation | Debug-only explicit-opt-in source investigation is wired and isolated from product services, uploads, observers, and Release. | Every physical session is unperformed; no source is accepted. |
| Shipping Health | Historical Personal steps reader, protected cache, observer/background-delivery patterns. | Four competitive adapters, seven-state readiness, source policies, minimum-data ingestion, source binding, and physical proof. Historical Personal rules are too permissive to reuse. |
| Apple Watch | The Watch can be a Health data source after syncing to the iPhone. A nonshipping handshake prototype also exists. | Physical Watch-origin data acceptance. The prototype watchOS target is not product scope and must remain excluded or be retired separately. |
| Scale | Targeted integrity races and a bounded fictional worker. | No data generator, HTTP load harness, p95/p99 thresholds, soak, hosted plan, pooler exercise, or capacity report. |
| External readiness | Local runbooks, association template, privacy/terms draft, and 18 explicit closed gates. | All 18 gates remain closed, including sources, host, support, retention, human acceptance, distribution, and analytics. |

Primary evidence lives in the c8 checkout:

- `docs/BETA_REAL_VALIDATION_ACCEPTANCE.md`
- `docs/BETA_REAL_VALIDATION_HANDOFF.md`
- `docs/BETA_FINISH_LINE_ACCEPTANCE.md`
- `docs/BETA_PHYSICAL_SESSIONS.md`
- `docs/BETA_ROLLOUT_PREPARATION.md`
- `docs/release/beta/readiness.json`

## Critical findings the plan must address

### 1. Every authenticated database call currently takes a global write lock

`app.challenge_session_v1()` locks the singleton `challenge_runtime_v1` row with
`FOR UPDATE`. Reads, Home sections, catalog, details, mutations, and worker passes
therefore serialize across unrelated accounts and unrelated challenges. The batch
worker can hold the same singleton while processing up to 50 challenges.

This design is useful for deterministic local races, but it is the first likely
Beta bottleneck: lock waits occupy connections, worker latency blocks clients, and
one slow transaction can create pool exhaustion. It must be measured unchanged and
then replaced with scoped locking before hosted capacity acceptance.

Required lock ownership:

- ordinary reads: no write lock;
- session revocation: session or actor generation row;
- account-wide admission limit: actor row, always locked in deterministic order;
- reusable link ceiling: link/token row;
- same-challenge roster/consent/capacity: lobby or reservation row;
- community progress: member progress row, not the cohort row;
- worker claims: due-work row with `FOR UPDATE SKIP LOCKED`, short claim transaction,
  and idempotent completion;
- multi-actor safety changes: sorted actor/profile locks, then challenge lock.

### 2. The local community implementation is real work, but not the selected Beta

C8 allows only one nonfinal fictional community and caps capacity at 100. Counts
are effectively current, and lifecycle/projections remain coupled to the global
mutex. The selected Beta requires 250 entrants, a five-person display threshold,
and snapshots delayed by at least 15 minutes.

The existing report model also needs a privacy correction: reports do not carry an
explicit challenge identifier, but a challenge-scoped operator query can surface a
report whenever reporter and subject share another challenge. A challenge-scoped
moderator can also trigger a global suspension. Both scopes must become explicit.

### 3. HealthKit cannot prove read denial or a true zero

HealthKit intentionally hides read-denial state. A successful empty read may mean
no activity, limited history, denied access, unavailable encrypted data, or a source
that has not synced yet. Apple also notes that the Health store can be unavailable
while the phone is locked and that observer/background behavior must be tested on
a device.

Therefore:

- permission-prompt completion cannot mean ready;
- an empty query cannot become a missed goal;
- clients cannot declare completeness, qualification, or finality;
- a late Watch sync or deletion must be able to lower/replace a prior total;
- unresolved source evidence must remain unresolved through server finalization;
- all four source policies stay independently default-off until accepted.

### 4. “Apple Watch integration” does not require a watchOS target

The desired flow is:

```text
Apple Watch records activity
        ↓ Apple Health sync
iPhone HealthKit store
        ↓ GameTime source policy + frozen challenge window
protected on-device replacement snapshot
        ↓ minimum authenticated/attested facts only
challenge_*_v1 ingestion and server-derived lifecycle
```

No WatchConnectivity payload, Watch sign-in, watchOS entitlement, companion UI, or
workout-write permission is needed. The existing “Test only” Watch target must not
be mistaken for this requirement.

### 5. Current correctness races are not load tests

The existing concurrency driver proves selected integrity boundaries by making
contenders wait. It does not measure throughput, end-user HTTP latency, pooler
pressure, independent challenge parallelism, foreground stampedes, community join
storms, scheduler backlog, or multi-hour stability. A separate load discipline is
required.

### 6. The current Release artifact is not the new Beta product

The ChallengeV1 shell and client are presently Debug/loopback-only, while the
existing Release candidate checker still validates the legacy product and Stripe
sandbox/redirect assumptions. A passing legacy archive therefore cannot prove that
the c8 Beta is shippable. The candidate gate must be versioned around the selected
nonredeemable product: hosted HTTPS challenge client, accepted source-policy
versions, fixture/debug routes unreachable, no payment path, no embedded Watch app
or `WCSession`, and exact HealthKit/privacy/universal-link configuration.

## Work that can proceed before an Apple Watch is available

| Can start now | Must wait for physical Watch/iPhone evidence |
| --- | --- |
| Preserve/review/land c8 | Accept actual eligible Apple Watch source lineage |
| Build a skip-free candidate and CI gate | Observe phone-only, Watch-only, and both-device overlap |
| Create deterministic synthetic datasets and unchanged baseline measurements | Observe delayed/offline Watch synchronization |
| Remove global read/mutation mutex and redesign worker claims | Validate edits, deletions, reimports, and downward corrections |
| Add keyset projections, measured indexes, and privacy-safe observability | Verify locked/background Health behavior on a device |
| Implement delayed community aggregate snapshots and 250-person capacity | Decide timed-run distance tolerance from repeated measurements |
| Define framework-free Health contracts, fakes, readiness state machine, protected queues, and source-versioned ingestion behind closed gates | Accept Exercise lineage and trustworthy-miss limitations |
| Add HealthKit protocol adapters against deterministic fixtures | Run real progress → correction → review → final journeys |
| Prepare purpose strings, privacy inventory, and release configuration without enabling it | Signed Release device and TestFlight validation |

## Dependency map and execution order

| Phase | Work package | Can run in parallel with | Blocks |
| --- | --- | --- | --- |
| 0 | Preserve and adopt c8 baseline | Nothing that writes product code | Every later ship task |
| 1 | Candidate gate and QA infrastructure | Phase 2 read-only scale baseline; Phase 3 pure Health contracts | Reliable regression evidence |
| 2A | Measure c8 unchanged at production-shaped cardinalities | Phase 1; Phase 3 | Lock/query redesign evidence |
| 2B | Partition locks, queue workers, batch projections | Phase 3 only; SQL packages are sequential | Beta load and community capacity |
| 3 | Pre-hardware Health contracts, fakes, readiness, disabled ingestion shell | Phases 1–2 | Fast post-device source implementation |
| 4 | Community delayed counts, safety scopes, 250 capacity, publisher seam | Phase 3; after 2B | Community Beta acceptance |
| 5 | Physical Health/Watch source sessions and policy decisions | Community/load/client work | Production source adapters |
| 6 | Accepted adapters, background reconciliation, attested ingestion, native integration | Final community tests | Source-backed Beta |
| 7 | Hosted staging, Beta-A load/fault/soak, operations and retention | Physical human checks | Release candidate |
| 8 | Full candidate, physical/human acceptance, authorized TestFlight | None | Beta distribution |

Phases 2B and 4 both replace shared database functions and must not be implemented
concurrently. Land each as a forward migration, rerun all historical and new-domain
tests, then start the next SQL package.

## Phase 0 — preserve and adopt the clean c8 baseline

### Work

1. Treat `/Users/user/.treehouse/gametime-beta-7b9cca/2/gametime-beta` and commit
   `9ce9ea6` as the implementation candidate.
2. Inventory the dirty original checkout without altering it. Preserve every
   uncommitted product/copy/design file and its provenance.
3. Independently review `577bc32..9ce9ea6`, with particular attention to:
   - the five c8 privacy/lifecycle fixes;
   - all `SECURITY DEFINER` functions, grants, search paths, session checks, and RLS;
   - lobby reopen/reconsent and exact-request recovery;
   - block, exit, report, removal, and suspension visibility;
   - historical agreement/migration preservation.
4. Run one fresh committed-candidate gate that includes the c8 suites, all
   controller-dependent tests without skips, the full historical UI suite,
   Debug/Staging/unsigned Release builds, and conformance.
5. Create a collision map between c8 and the original dirty changes. Present a
   guarded local landing proposal; merge only with explicit captain approval.
6. Record the resulting canonical commit. Every later worker must start there.

### Done when

- c8 is either guardedly landed or explicitly named as the sole base for every
  active worker;
- no user-owned dirty file has been reset, overwritten, or silently attributed;
- one fresh skip-free candidate report exists;
- the five reproduced bugs have independent regression review;
- no old migration or agreement byte was rewritten.

## Phase 1 — make bug testing continuous and release-shaped

### Test harness changes

1. Parameterize `beta-native-smoke.py` and related controllers:
   - simulator ID;
   - Supabase project/workdir and port base;
   - controller port;
   - DerivedData and result-bundle path;
   - manifest/evidence directory;
   - actor namespace and cleanup policy.
2. Fail the candidate gate when a required controller test skips. Separate an
   intentionally unavailable environment from a passing product suite.
3. Add CI/self-hosted CI lanes for:
   - portable SQL/Deno/core verification;
   - `GameTimeBetaLocal` authenticated controllers;
   - native units and UI journeys;
   - Staging and unsigned Release builds;
   - upgrade migration from retained pre-c8 data;
   - minimum supported and current iOS simulators;
   - Address Sanitizer and Thread Sanitizer where supported;
   - repeated flaky-test detection.
4. Because no watchOS product will ship, do not build a new Watch UI test program.
   Keep the prototype excluded from Release and add a packaging assertion that no
   GameTime Watch app is embedded. Retire the prototype only in a separate cleanup
   change after references are inventoried.
5. Replace or version the legacy candidate check. The Release archive must launch
   the new product shell over configured HTTPS, contain no local fixture actors or
   clocks, expose no Stripe/payment route, carry the exact HealthKit/privacy/AASA
   configuration, and have a recorded binary hash that matches the tested build.

### Automated bug matrix

| Layer | Required additions |
| --- | --- |
| Pure policy/property | All 13 policies; values at target−1/target/target+1; strict timed equality; ties; all-miss; integer remainders; 1/30-day windows; DST/travel; delayed notices; review boundary microseconds. |
| Database | RLS/IDOR for every projection; exact retry vs changed payload; stale/revoked sessions; 6th/7th roster; 3rd/4th unsettled; 20th/21st link redemption; block/remove/delete/suspend races; lower/deleted/unresolved revisions. |
| Migration | Seed representative historical Personal/Solo/duel/performance/weekly/new-domain rows on the old schema, apply every forward migration, and compare immutable terms/results/visibility before and after. |
| Native/store | Account switching during requests; late stale response; corrupted recovery file; protected-file unavailable; offline/online; app kill/relaunch; partial section failure; cached privacy expiry; Dynamic Type and localization-safe values. |
| HTTP/Auth | Two and six actors, all 13 policies, response loss, JWT expiry, revocation during mutation, abusive retries, rate limits, and server-time skew. |
| Fault | Edge 5xx/timeout, database timeout, worker pause, pool pressure, duplicate/out-of-order observations, process restart, and scheduler replay. |
| Physical/human | Health/Watch matrix, locked/background behavior, VoiceOver, Voice Control/Switch Control, comprehension, voluntary exit, and monitored support. |

### Defect policy

- **P0:** privacy disclosure, cross-account authorization, wrong final result,
  consent/terms mismatch, unrecoverable destructive loss. No open P0 at any Beta.
- **P1:** unsafe exit/block/deletion, source correction lost, stuck lifecycle,
  session-revocation failure, missing result recovery, or launch-blocking crash. No
  open P1 before TestFlight.
- **P2:** degraded recovery, incorrect nonfinal state, accessibility blocker, or
  sustained SLO failure. Must have owner disposition and regression coverage.
- Every fixed production defect gets the smallest-layer regression plus the relevant
  end-to-end case. A rerun without a regression is not closure.

## Phase 2 — establish scalable database and worker foundations

### 2A. Measure before changing

Create deterministic synthetic data at three cardinalities in disposable projects:

- 2,000 accounts / Beta-A shape;
- 25,000 accounts / long-term-B shape;
- 1,000,000 challenge-related rows to expose deep-history and revision-plan failures.

Include realistic active/history ratios, four metrics, friend groups, personal
goals, one community cohort, invitation links, requests, downward corrections,
reviews, reports, blocks, exits, and due work. Seed through batched SQL or `COPY`,
not public APIs, and provide a scoped purge command for synthetic records only.

Capture `EXPLAIN (ANALYZE, BUFFERS)` and cold/warm results for:

- Home sections and detail/history;
- community discovery, detail, join, capacity, and delayed aggregate read;
- exact username lookup and invitation redemption;
- ingestion/current-revision lookup;
- due-work discovery and worker claim;
- reports/moderation/audit;
- account deletion/deidentification lookups.

Do not add speculative indexes. Add foreign-key, composite, or partial indexes only
when the measured query shape supports them, and remeasure both read gain and write
cost.

### 2B. Remove global serialization

1. Split session validation from feature-gate mutation. Ordinary reads must never
   take `FOR UPDATE` on a singleton.
2. Preserve immediate session-revocation correctness with an actor/session generation
   check whose lock is scoped to that session or actor.
3. Establish and test one deterministic lock order: session/actor → link → lobby →
   sorted participant actors → per-member/source row.
4. Keep transactions short. No network call, evaluator-wide scan, or multi-item
   worker loop may run while holding a shared global lock.
5. Introduce due-work rows or indexed due columns. Workers claim bounded items with
   `FOR UPDATE SKIP LOCKED`, commit claims quickly, process independently, and record
   attempts, `next_attempt_at`, error code, and dead-letter/overdue state.
6. Maintain per-member latest observation/result rows and append-only revisions.
   Community progress updates lock only that member's current row.
7. Maintain small cohort counter/aggregate rows. Capacity reservation is atomic on
   the cohort capacity row, but progress and reads do not touch it.
8. Replace complete-history arrays and per-item projection loops with bounded batch
   projections and stable keyset cursors. Never use deep `OFFSET` pagination.
9. Tune RLS for scale: indexed ownership columns, `(select auth.uid())` where
   applicable, explicit grants, and no table/view bypass.

### 2C. Contention acceptance

The redesign is done only when tests prove both sides:

- unrelated accounts/challenges progress concurrently;
- same-actor admissions, same-link redemptions, final capacity slots, same-lobby
  mutations, and session revocations still serialize safely;
- zero deadlocks and zero invariant/privacy failures under repeated randomized races;
- a paused/failing worker cannot block reads, safe exits, reviews, or admission pause;
- all historical and c8 correctness suites still pass.

## Phase 3 — build the Health/Watch source boundary before hardware arrives

This phase deliberately builds contracts and failure handling without pretending
that Simulator or fixtures qualify a real source.

### 3A. Freeze framework-free contracts

Define versioned types for:

- frozen challenge interval and timezone;
- metric unit: step count, Exercise seconds, running millimetres, elapsed seconds;
- source-policy identifier/version;
- observation revision ID and previous-revision link;
- `value`, `deleted`, and `unresolved` replacement outcomes;
- earliest authorized date when positively available;
- observed-at/source-freshness timestamps;
- completeness evidence category, never a client-authored `complete` Boolean;
- actor, challenge, agreement version, terms digest, and device-held request ID.

Recommended seven-state readiness contract:

1. `unsupported` — Health data is unavailable on this device;
2. `notConnected` — GameTime has not completed a source request for this metric;
3. `checking` — a bounded Health query is in progress;
4. `ready` — positive eligible source-backed history supports the proposed window;
5. `noEligibleDataYet` — the query returned no eligible data; denial/true zero are
   intentionally not distinguished;
6. `temporarilyUnavailable` — lock, query, protected-file, or transient system
   failure prevents a trustworthy read;
7. `staleOrIncomplete` — prior evidence exists but freshness/window/source-policy
   requirements are no longer satisfied.

The names are code semantics, not final design copy. A permission prompt never
transitions directly to `ready`.

For final consent or join readiness, require a positive selected-source history
signal before the proposed challenge starts: at least one eligible Watch-origin
record in the prior 30 days for steps, Exercise Time, and cumulative running
distance; for timed running, at least one comparable eligible Watch-origin whole
workout in the prior 90 days. This is a source-availability confidence signal, not
proof that HealthKit access is complete. A missing signal remains
`noEligibleDataYet` or `staleOrIncomplete`; it must never become zero or a missed
result.

### 3B. Adapter interfaces and fakes

Build one adapter protocol and four metric-specific implementations behind it:

- competitive steps;
- Apple Exercise Time normalized to integer seconds;
- cumulative eligible running-workout distance in integer millimetres;
- best eligible whole timed-running workout using `end - start` elapsed seconds.

Before physical evidence, concrete eligibility is injected through a closed source
policy. Tests must cover source IDs, nil metadata, manual/import markers, overlapping
samples, sync identifiers/versions, duplicated UUIDs, late additions, deletions,
lower replacements, boundary-straddling samples, truncation, query failure, and
limited-history dates.

Do not finalize the allowlist, overlap algorithm, Exercise lineage, crossing-workout
policy, or timed distance tolerance from fixtures. Those remain Phase 5 decisions.

### 3C. Protected local state and upload queue

- Scope caches by account + challenge + agreement/source-policy version.
- Use complete file protection and atomic replacement.
- Fence every asynchronous result by account, terms digest, and request generation.
- Requery the full authoritative challenge window after observer notifications;
  anchored queries may trigger work but cannot alone prove a complete total.
- Allow replacement values to decrease or become deleted/unresolved.
- Persist exact signed request bytes for retry; retry those before generating a new
  request. Never log Health samples, routes, source identifiers, payloads, or tokens.
- Clear current private values on sign-out, account deletion, terms change, or
  unreadable/corrupt state while retaining only the minimum recoverable encrypted
  request material required by the approved retention policy.

### 3D. Disabled real-ingestion boundary

Add forward-only new real-source agreement and ingestion versions, but keep every
source and real ingestion schema/runtime switch constrained off.

The server accepts only minimum facts:

- actor/challenge/agreement/source-policy identity;
- canonical total or deleted/unresolved replacement;
- monotonic revision identity and prior-revision identity;
- frozen window and observed-at/freshness facts;
- exact idempotency request identity;
- attestation/integrity evidence required by the final accepted source policy.

It rejects raw samples, routes, workouts, source device names, baseline history,
client-authored qualification, client-authored completeness, results, winners, or
allocations. The server derives progress/review/finality through the existing
challenge lifecycle.

## Phase 4 — finish the selected community Beta and preserve a future host seam

### 4A. Selected privacy behavior

1. Own progress remains exact and private.
2. Stranger names, individual totals, ranks, timestamps, and roster remain absent.
3. When the disclosure cohort has fewer than five joined, active, nonremoved
   participants, return:
   - counts as `null`, not `0`;
   - `minimum_display_count = 5`;
   - an explicit threshold-not-met state.
4. At or above five disclosure-cohort members, compute approved exact anonymous
   joined/qualified counts on a fixed server cadence no more frequent than every 15
   minutes. Five controls disclosure only; it does not set an outcome minimum.
5. Return a snapshot revision and `as_of` time. Clients must not infer or synthesize
   a fresher value.
6. Cache/projection endpoints must not leak live counts through alternate fields,
   internal lobby revisions, ETags, error distinctions, operator endpoints, or
   request timing. Use fixed snapshot buckets; do not implement a client timer or a
   simple rolling `event_time + 15 minutes` reveal.
7. Catalog/detail discovery requires explicit Beta eligibility, confirmed age, an
   active nonsuspended account, and the discovery switch. Admission may be paused
   without making already-authorized safe reads, exits, or reviews unavailable.

### 4B. Capacity and lifecycle

- Raise the tested Beta capacity to 250 only after per-member progress and the global
  lock are removed.
- Exercise a synchronized 250-person join, final-slot contention, reconnect/retry,
  and operator-close race.
- Parameterize target, minimum, capacity, duration, timezone, and simulated amount;
  keep publication disabled until the owner approves actual values.
- Preserve the shared three-unsettled limit and the explicit community overlap
  exception.
- Keep lifecycle work per member/per cohort and bounded; do not materialize a giant
  participant/revision JSON document or rewrite result arrays on every update.

### 4C. Safety scope corrections

- Add `challenge_id` or an explicit account-global scope to each report. A
  challenge-scoped reviewer must never see a report filed in an unrelated context.
- Separate challenge removal from account suspension.
- Only an explicitly global, audited support role may impose a global suspension.
- Add expiration, revocation, appeal/reinstatement state, and race tests for grants.
- Apply rate limits/quotas to discovery, username lookup, link redemption, joins,
  reports, and repeated mutations. Auth rate limits alone are insufficient.

### 4D. Future participant-hosted seam, not a Beta feature

Use a versioned publisher model such as operator vs account-hosted and an explicit
publisher identity, but grant publish authority only to the operator/service in
Beta 1. Assert that ordinary authenticated users cannot publish.

Do **not** build participant publishing, a public directory, feed, profiles,
comments, reactions, or stranger standings now. A later community-hosting phase
must add host eligibility, creation quotas, moderation responsibility, discovery,
abuse prevention, removal/appeals, host-departure behavior, and its own load/privacy
acceptance.

## Phase 5 — perform physical Apple Health and Watch-source acceptance

When a compatible paired Watch is available, continue the existing First Mate task
`gametime-beta-source-acceptance-b7`; do not create a duplicate. The owner must give
explicit opt-in for the exact iPhone and paired Watch before installation or reads.
Raw observations remain volatile/on-device; only categorical findings enter the
repository.

Run the prepared sessions in `docs/BETA_PHYSICAL_SESSIONS.md`:

1. **Access and steps:** phone-only, Watch-only, both-device overlap, source
   distinction, and session clearing.
2. **Exercise and running feasibility:** Exercise lineage, indoor/outdoor running,
   known distance, pause/resume, reported vs whole elapsed duration, full-window vs
   boundary-straddling workout.
3. **Corrections and failure:** manual/import, edit/delete, reimport, delayed Watch
   sync, offline, locked device, permission changes, and app termination.
4. **Boundaries:** frozen timezone after travel, local midnight, actual DST when
   practical, end/+24h/+48h result windows. Explicitly test a first Watch sync after
   +24h: the current fixture contract rejects a first fact then unless an unresolved
   fact already exists, so this policy must be accepted or changed before launch.

Evidence-gated decisions after the sessions:

- eligible source allowlist and how unsupported third-party writers are treated;
- overlap/reconciliation rule for phone + Watch samples;
- whether Exercise lineage is trustworthy enough to keep the metric;
- whole-workout handling at challenge boundaries (safest provisional rule: include
  only fully contained workouts; no proration);
- timed-running acceptable distance band based on repeated measured runs;
- what can support `ready`, `staleOrIncomplete`, and a trustworthy miss;
- background refresh expectations and user recovery when the store is locked.

If any metric cannot produce a defensible policy, leave only that source disabled
and bring the product-scope conflict back to the owner. The current adopted finish
line still requires all four metrics; do not silently ship a steps-only Beta.

## Phase 6 — implement accepted real adapters and source-backed journeys

For each accepted metric, in its own bounded slice:

1. freeze a source-policy memo and version;
2. implement the production HealthKit query/reconciliation adapter;
3. connect on-device suggestion calculations without uploading baseline history;
4. register metric-specific observer/background delivery and always call HealthKit's
   completion handler after bounded processing;
5. connect protected replacement state and durable exact retry;
6. enable its real-source agreement/ingestion path only in the approved local/staging
   acceptance environment;
7. prove progress → lower/deleted correction → delayed Watch sync → provisional
   notice → review → immutable final;
8. rerun all 13 policies that depend on that metric and all historical regressions.

Metric rules:

- **Steps:** source-aware cumulative replacement; never naïvely sum overlapping
  phone/Watch samples.
- **Exercise:** `appleExerciseTime` converted to integer seconds; keep disabled if
  eligible lineage cannot be defended.
- **Cumulative running:** eligible whole running workouts; distance in integer
  millimetres; no route upload.
- **Timed running:** one best qualifying whole workout, conservative `end - start`
  elapsed seconds including pauses, strict-under target comparison, accepted
  distance band; no segment inference.

## Phase 7 — hosted staging, operations, and Beta-A stress acceptance

No hosted action occurs without separate authorization. Use a dedicated
nonproduction project matching the intended Postgres/compute/pooler/Edge settings.
Do not load-test production.

### Hosted readiness

- apply reviewed forward migrations to a branch/preview/staging environment;
- explicitly expose only intended Data API functions/tables and verify RLS/grants;
- configure Sign in with Apple and the exact HTTPS host/team/bundle association;
- wire the new client to HTTPS; keep local fixture actors/clocks impossible in hosted
  configuration;
- provision scoped secrets, source/admission/processing/discovery flags, operator
  identities, scheduler, alerts, credential rotation, and kill-switch runbook;
- migrate any observability script off Supabase Management API `logs.all` before its
  September 23, 2026 removal;
- use transaction-mode pooling for short-lived/serverless database traffic and size
  the pool from observed peak usage, leaving headroom for Auth/PostgREST/operations;
- keep Edge requests within current platform memory, CPU, wall-clock, log, and bundle
  limits; move durable long-running work into idempotent database jobs.

### Beta-A load workloads

Use authenticated, separate synthetic accounts. A representative mix should include:

- Home section refresh and detail/history reads;
- source-ingestion replacement bursts after foreground/Watch sync;
- community catalog/detail/join and 250-person final-capacity contention;
- friend lobby, target, roster, consent, invitation redemption;
- reviews, exits, blocks, reports, and session revocation;
- due-work discovery, claim, retry, outage backlog, and drain.

Run:

1. **query-plan baseline** at 2K and 25K accounts;
2. **ramp** to 25 requests/second with 100 concurrent sessions;
3. **2× spike** to 50 requests/second for five minutes;
4. **foreground stampede** of 100 sessions within 30 seconds;
5. **community join storm** through the 249th/250th/251st slots;
6. **two-hour soak** near expected Beta sustained traffic;
7. **worker outage/replay** with accumulated due challenges;
8. **fault cases** for transient 5xx, JWT expiry, query timeout, database restart,
   pool pressure, duplicate/out-of-order revisions, and operator pause;
9. **recovery drill** proving reads/exits/reviews remain available and backlog drains
   without shortening review windows.

Use open arrival-rate scenarios and fail on dropped iterations rather than allowing
a slower system to silently generate less load.

### Proposed Beta-A pass thresholds

| Measure | Required result |
| --- | --- |
| Correctness/privacy | Zero cross-account disclosures, wrong results, lost accepted writes, double joins, cap violations, shortened deadlines, or invariant failures. |
| HTTP failures | Less than 1% unexpected failures; all expected throttles/conflicts classified separately. |
| Read latency | p95 ≤ 500 ms and p99 ≤ 1,500 ms for Home/detail/catalog under selected Beta load. |
| Mutation latency | p95 ≤ 800 ms and p99 ≤ 2,000 ms excluding deliberate contention losers. |
| Locking | Zero deadlocks; no unrelated-user wait on a global application lock; p95 application lock wait ≤ 100 ms. |
| Worker | Normal due work begins within 60 seconds; after the 2× outage backlog, 95% drains within 5 minutes and 100% within 15 minutes without reducing review time. |
| Pool | No pool exhaustion and at least 30% connection headroom at expected load. |
| Soak | Two hours with stable error/latency, memory, connections, queue lag, table/index growth, and no unbounded retries. |

Record p50/p95/p99, throughput, `dropped_iterations`, SQLSTATEs, lock waits,
connections, CPU/memory/I/O/cache, `pg_stat_statements`, rows/buffers, dead tuples,
autovacuum, Edge latency/errors, worker lag, database/index size, and estimated cost.
Metrics and logs must not contain Health totals, routes, source device identifiers,
usernames, amounts, review text, tokens, or signed payloads.

### Long-term-B proof after Beta stability

Repeat the same suite at 25,000 registered, 5,000 DAU, 1,000 concurrent, 150
requests/second, and a 10,000-person cohort with a four-hour soak. Failure does not
block the smaller Beta if the data shape is safe and the Beta envelope passes, but
the capacity report must state the highest proven envelope and bottleneck honestly.

Supabase's current production guidance recommends suitable indexes,
`pg_stat_statements`, load testing on staging, and contacting support before heavy
or launch-shaped tests. Pool sizing must follow observed peak connections, not a
copied constant.

## Phase 8 — release-candidate and human acceptance

### External decisions/inputs that must be resolved

- exact hosted Supabase project, region, compute/pool budget, and recovery objective;
- legal/accountable entity, reviewed privacy/terms, and Health disclosure;
- retention/deletion/deidentification rules by record class;
- monitored support destination, named operator/reviewer coverage, response SLA,
  appeal/reinstatement owner, and credential rotation;
- exact community target, duration, timezone, minimum, simulated amount, and
  rejoin/removal policy;
- Apple team, Release bundle, associated domain, Sign in with Apple configuration;
- explicit hosted, distribution, and recruitment authorization.

### Candidate gate

From one immutable commit and one recorded environment:

- all SQL/Deno/core/native/controller/UI/conformance/upgrade suites pass without
  required skips;
- Debug, Staging, and signed Release build from the same source;
- all four real sources have accepted policy/version/evidence;
- the exact Release/TestFlight binary, identified by hash, proves Watch-origin
  HealthKit ingestion for all four metrics even though no Watch companion is bundled;
- real phone + Watch journeys cover sync, corrections, review, and finality;
- Beta-A load/fault/soak report passes;
- RLS/advisors and least-privilege review pass;
- hosted Sign in with Apple and invitation links pass before/after sign-in;
- operator pause, worker outage/replay, credential rotation, and rollback drills pass;
- two and then six adults explain roster, goals, consent, source/missing behavior,
  ties, exits, review deadline, privacy, and simulated money in their own words;
- physical VoiceOver, Dynamic Type, Voice Control/Switch Control, reduced motion,
  offline recovery, account switching, and voluntary exit pass;
- archive inspection proves the new HTTPS Beta shell is active and Stripe/payment,
  fixture clocks/actors, Watch app, and `WCSession` are absent;
- there are no open P0/P1 defects and every P2 has explicit disposition;
- all 18 readiness gates have evidence-backed values; no test flips them implicitly.

Only after separate distribution and recruitment approval should a TestFlight cohort
be invited. Passing the plan is not that authorization.

## Risk register

| Risk | Impact | Mitigation / gate |
| --- | --- | --- |
| C8 remains outside canonical main | Later agents duplicate or overwrite verified work | Phase 0 provenance/landing is mandatory. |
| Global runtime mutex | Latency, connection starvation, worker/client coupling | Measure unchanged, then scoped locks and `SKIP LOCKED`; prove integrity and parallelism. |
| Empty Health read treated as zero | Wrong loss/result | Seven-state readiness, unresolved replacement, server-derived finality, physical source acceptance. |
| Watch late sync or deletion arrives after notice | Wrong or stale result | Whole-window replacement revisions, +48h corrections, new notice on changed result, physical delayed-sync tests. |
| Exercise provenance cannot be defended | Unfair metric | Keep source independently off and return to owner; do not infer from positive fixtures. |
| Community timing inference | Reveals individual behavior | k=5 threshold, fixed ≥15-minute exact snapshots, no alternate live fields. |
| Community report crosses challenge scopes | Privacy/support disclosure | Explicit report scope and challenge ID, least-privilege operator tests. |
| Challenge moderator can globally suspend | Excess authority | Split challenge removal from global support suspension; audited role/grant boundaries. |
| Deep history or due-work scan degrades | Slow Home/worker and pool pressure | Keyset pagination, batch projections, due index/queue, measured query plans. |
| Load test proves only local Docker | False confidence | Dedicated production-shaped nonproduction hosted run with monitoring. |
| Health data leaks into telemetry/evidence | Sensitive-data exposure | Minimum facts, complete protection, redacted categorical physical evidence, log schema tests. |
| User-hosted community prematurely expands scope | Moderation and abuse gap | Publisher seam only; ordinary publish denied; separate future product phase. |

## Decisions deliberately deferred to evidence or rollout

These do not block Phases 0–4, but the named phase may not pass without them:

- Watch/source allowlist, overlap reconciliation, Exercise lineage, workout-boundary
  behavior, and timed tolerance — decide after Phase 5 physical evidence;
- community target/window/timezone/simulated amount — decide before real publication;
- retention/deletion and report/audit purposes — decide before hosted volume and
  deletion implementation;
- hosted compute/pool/RTO/RPO — decide before Phase 7 provisioning;
- support/legal/operator identities — decide before hosted human acceptance.

## Definition of finished Beta 1

Beta 1 is ready for an authorization decision only when all of the following are
true:

- the c8-derived product is canonical and reproducibly green;
- all 13 policies run through the production Release shell;
- Apple Watch-origin data is read through iPhone HealthKit under an accepted policy;
- steps, Exercise, cumulative distance, and timed running each pass physical
  progress/correction/finality;
- the operator community supports 250 entrants and the chosen delayed-count privacy
  contract;
- the Beta-A load, spike, soak, fault, and recovery thresholds pass;
- hosted auth, links, scheduler, monitoring, support, retention, and rollback pass;
- physical accessibility and human comprehension pass;
- no P0/P1 defects remain;
- legacy data and agreements are preserved;
- distribution and recruitment are separately authorized.

## Current external technical references

- [Apple HealthKit overview](https://developer.apple.com/documentation/healthkit)
- [Apple: Authorizing access to health data](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)
- [Apple: Protecting user privacy](https://developer.apple.com/documentation/healthkit/protecting-user-privacy)
- [Apple: Executing observer queries](https://developer.apple.com/documentation/healthkit/executing-observer-queries)
- [Supabase production checklist](https://supabase.com/docs/guides/deployment/going-into-prod)
- [Supabase connection management](https://supabase.com/docs/guides/database/connection-management)
- [Supabase connection/pooler modes](https://supabase.com/docs/guides/database/connecting-to-postgres)
- [Supabase Edge Function limits](https://supabase.com/docs/guides/functions/limits)
- [Grafana k6 thresholds](https://grafana.com/docs/k6/latest/using-k6/thresholds/)
- [Grafana k6 arrival-rate allocation](https://grafana.com/docs/k6/latest/using-k6/scenarios/concepts/arrival-rate-vu-allocation/)
