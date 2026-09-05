# Phase 3(b): nominated fictional attempts and strict target evaluation

Implemented locally September 5, 2026. This adds multiple event nominations,
private fictional organizer sources, independent reviewed corrections and a
pure evaluator for the existing Phase 3(a) agreement. It does not publish a
result, release an agreement slot or record a financial consequence.

## Agreement and attempt contract

The existing `performance-commitment-fixture-5k-v1` terms and owner consent
remain unchanged. Only official outdoor 5K chip times with whole-second
precision qualify. The target remains strict: 359 seconds meets a 360-second
target; 360 seconds does not. This does not implement a true mile.

Local implementation defaults, separately recorded in D125:

- A service-curated fictional event has a stable UUID, start/end instants, a
  5K distance and the agreed source. Its duration is at most 24 elapsed hours.
  An owner nominates it before its start and after agreement creation, with
  a bounded bib. The event starts at/after the frozen commitment start and
  finishes strictly before the deadline. Requiring the whole event window to
  fit is a conservative admission constraint; it does not expand the frozen
  attempt window. These are local defaults, not approved live organizer rules.
- At most 32 distinct events can be nominated per commitment. The same event
  cannot be nominated twice. A different agreement can independently nominate
  the same event if its own rules permit it. There is no automatic import,
  duplicate-provider reconciliation, retroactive nomination or bib edit.
- A finished record must bind the nominated event, source, distance and bib.
  Its actual chip start is at/after the event start, agreement creation and
  commitment start; its finish is within the event and before the exclusive
  deadline. Start-to-finish duration must exactly equal its whole chip seconds.
- Each review appends one attempt's new revision, naming that attempt's exact
  predecessor. Global revision numbers order the commitment's full history.
  Updating a different attempt preserves the earlier fast run. Only an explicit
  correction of that successful attempt can invalidate its contribution.
- A complete-set miss requires the owner's explicit confirmation of all sorted
  nomination IDs after the deadline and before the 72-hour proof cutoff, plus
  confirmed nonqualifying results for every nominated attempt. An empty set
  needs explicit `no_attempts` confirmation in the same window. Silence,
  missing/ambiguous records and incomplete sets cannot prove a miss. Any valid
  success suffices even if another attempt lacks proof.

Nominations, confirmations and reviews use actor-bound exact request UUIDs.
The request payload includes the operation and all submitted inputs. Recovery
returns the saved result with the attempt gate off, without redoing the action.
Changed payloads fail. Reviewer recovery still requires an active grant and
session; revocation does not leave a recovery route into private records.
This request namespace is separate from the agreement, duel and Personal ones.

## Storage, authorization and retention

The [new migration](../supabase/migrations/20260905194725_performance_attempts_v1.sql)
adds ten private `app.performance_attempt_*` tables. All have RLS, no client or
service table grants, and owner/context guards against direct writes, updates,
deletes and truncation. Only the singleton gate may be updated. Public RPCs
have an explicit role allowlist; private clock seams have no API grants.

| RPC | Authorized caller and behavior |
| --- | --- |
| `set_commitment_attempts_enabled_v1` | Service only; separate default-off attempt gate, audited changes |
| `curate_commitment_fixture_event_v1` | Service only; immutable fictional event UUID and times, exact replay |
| `list_commitment_attempt_events_v1` | Active owner; 1–100 eligible future events, excludes existing nominations |
| `nominate_commitment_attempt_v1` | Active owner; exact-request nomination of one event/bib |
| `confirm_commitment_attempt_set_v1` | Active owner; explicit true and the full sorted ID set, exact recovery |
| `get_commitment_attempts_v1` | Active owner; nominations, confirmation and redacted review receipts, including after gate shutdown or safe closure |
| `set_commitment_attempt_reviewer_v1` | Service only; append grant/revocation for one independent reviewer and commitment; old grant retries never restore access |
| `capture_commitment_attempt_fixture_v1` | Service only; bounded fictional document, server capture time and exact source-ID replay |
| `get_commitment_attempt_source_v1` | Granted, active independent reviewer; audited source retrieval |
| `review_commitment_attempt_v1` | Granted, active independent reviewer; prior source retrieval and explicit identity confirmation required |
| `get_commitment_attempt_snapshot_v1` | Service only; audited complete private evaluator snapshot under aggregate locks |

Owners, friends, followers and unrelated actors cannot read raw proof through
these APIs. Owner receipts omit chip times, bibs, source IDs/documents and
reviewer IDs; receipt metadata is not a published result. Source input is a
strict bounded object, without names, notes, routes, files or arbitrary URLs.
No real organizer source has been connected or verified.

All paths serialize sorted owner/reviewer profiles, caller session, runtime,
and agreement. Auth checks use active profile bindings and a real matching
unexpired session, with a second expiry check after blocking locks. A blocked
reviewer has no access. Grants are server-owned; user metadata has no authority.
Closing/deleting an owner prevents further proof access and new writes, while
retaining records. Independent support access after closure is later work.

A product-specific `performance_attempts_v1` retention hold is inserted with
the first nomination or empty-set confirmation. These local fictional records
have no purge route; they remain held pending the result/review retention
policy. The legacy raw-evidence worker cannot remove them, including across
long goal windows or account deletion. This is not a selected live retention
duration. Before accepting real proof, define case holds, support access,
post-final retention/release and an audited purge process for this product.

## Pure evaluator and later lifecycle boundary

[`performance_scoring.ts`](../supabase/functions/_shared/performance_scoring.ts)
validates the exact policy, owner consent and complete private snapshot. It
preserves PostgreSQL microseconds through UTC-offset, DST and leap-day tests.
Initial reviewed proof must arrive strictly before deadline + 72 elapsed hours;
corrections require an admitted initial revision for that attempt and arrive
strictly before deadline + 720 elapsed hours. Late fixture records are flagged
for support and cannot turn missing proof into a proven miss.

A candidate result appears only at/after the initial proof cutoff. Confirming
it requires a durable owner notice and seven full elapsed days for filing;
each filed case has seven full days for independent review. Each correction
needs its own notice/window. A cap never truncates a review window to force a
miss: missing notice, insufficient time, unresolved proof or reviewer timeout
ends without consequence. Existing safe closure yields zero consequence.
A supplied persisted final result remains authoritative; later proof only
flags a support correction.

Notices, participant cases, resolutions and final results are **pure fixture
inputs only** for this product. No commitment lifecycle worker, result tables,
notice delivery, support-correction intake or settlement was added. The smoke
uses actual persisted nominations/proof and separately injected lifecycle
fixtures. Do not treat an evaluator return value as durable finality or money.

## Verification

- Focused SQL: 68 assertions passed for nominations, boundaries, source/bib/
  precision validation, exact retries, independent review, correction chains,
  privacy, gate shutdown, session expiry, deletion and legacy retention.
- Real-session SQL: 20 assertions passed across eight observed transaction
  waits: competing reviews, exact correction retries, duplicate nominations,
  gate shutdown, reviewer revocation, session revocation, natural session expiry
  while waiting and account deletion.
- Pure Deno: 39 scenario tests passed for strict equality, success preservation,
  correction invalidation, confirmed nonfinishes versus missing proof, complete
  set/no-attempt acknowledgement, wrong source/distance/bib/precision, UTC
  microseconds, DST/leap day, notice/review boundaries, timeouts and finality.
- Persisted loopback smoke passed: success with a later slower attempt; explicit
  correction to exact target becomes a candidate miss; ambiguous second proof
  becomes unresolved. All three respect full injected review windows. The
  transaction rolls back its fixtures and gate changes.
- Local schema lint and warning/error advisors passed with no issues.

The full portable regression gate passed: 63 database files / 2,854 assertions,
607 Deno tests (including the 39 new scenarios), and 103 portable Swift tests.
The new migration is recorded locally as `20260905194725`. Final cleanup checks
confirmed attempt, commitment and duel admission off, empty commitment allowlist,
zero open commitment slots, zero attempt sources, and zero fictional attempt
sessions. No earlier migration was edited.

Reproduce from the repository root with the local stack running:

```sh
./scripts/test-all.sh
supabase test db --local supabase/tests/471_performance_attempts.test.sql supabase/tests/472_performance_attempts_concurrency.test.sql
deno run --allow-run=psql --allow-read=scripts/examples scripts/performance-attempt-local-smoke.ts
supabase db lint --local --schema app,public --level warning
supabase db advisors --local --type all --level warn
```

Logs: `/tmp/gametime-attempt-{focused,races,smoke,portable,lint,advisors}.log`.
The first focused invocation needed self-contained test fixtures because the
CLI container does not mount `scripts/examples`; this was corrected before the
passing run. The first full gate hit sandbox restrictions on local database
access and the Swift compiler cache; it was rerun with the required access.
No native source changed and no HTTP, device, VoiceOver or hosted acceptance
is claimed. Accelerated clocks do not prove months of real operation.

The current [Supabase changelog](https://supabase.com/changelog.md) and official
[RLS documentation](https://supabase.com/docs/guides/database/postgres/row-level-security)
were checked. No dependency, extension or platform configuration change was
needed. No hosted mutation, deployment, schedule, external message, provider
operation or live money was enabled.

## Checkpoint follow-up — September 5, 2026

The forward checkpoint migration tightens newly captured source JSON to the
evaluator’s timestamp and bib types. Exact recovery still precedes new
validation; previously admitted source documents are never rewritten. The
[checkpoint review](PHASE_3D_CHECKPOINT.md) records fresh regression evidence
separately from the original Phase 3(b) counts above.

## Phase 3(c) handoff

Implemented in [Phase 3(c) progress acceptance](PERFORMANCE_PROGRESS_V1_ACCEPTANCE.md).
The original handoff below is preserved as its scope.

Add named intermediate milestones and manual progress as a separate ledger.
Bind them to the owner and agreement, use actor-bound exact requests, bound
history reads and preserve deletion/retention behavior. Milestones and manual
progress must never count as qualifying organizer proof, change a target or
settle money. Keep the attempt ledger, frozen consent and private sources
separate. Add pure/SQL tests and update this acceptance chain.

Phase 3(d) owns explicit friend-following permissions and revocation. Phase
3(e) owns durable result notices, participant review/withdrawal history, a
clock-injected result lifecycle, immutable finals, post-final support and any
separately recorded simulated consequence. That slice must use atomic complete
snapshots and correction-aware commits; consuming a stale evaluator decision
without rechecking the snapshot is unsafe. Real organizer operations, native
commitment flows, hosted rollout, a true-mile policy and money remain separate.
