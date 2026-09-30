# Staging update: hosted Health acceptance — September 30, 2026

The owner's September 30 approval was: **“i approve all changes. my iphone
is unlocked and ready for build”**. In this prepared-device action, it covers
the same-bundle Staging update and launch preserving the existing app data,
account, journal and active goals. This approval persists for the next attempt;
do not ask for it again. The main readiness agent owns installed-build
inspection, the conditional in-place update and launch. This Health agent
owns only the bounded read-only hosted acceptance checks below.

**Current disposition:** uploads recovered after the same-bundle Staging
update to **0.9.0 (930.26.1)**. The pre-update baseline had zero post-cutover
saves and 36 HTTP 422s. The final save check through **22:04:53 UTC** has
**16 distance facts and 15 Steps facts**, both `private_account`, all
`unresolved`. The clean post-recovery window **21:58:02 → 22:04:53 UTC** has
**31 HTTP 200s and no further observed refusal**. The full launch window
included one initial HTTP 422 at 21:58:01; it is recorded separately below.
All saved observations are stamped after launch. Accepted activity totals
and the phone's Health-card state remain unverified by this aggregate check.

## Scope and boundaries

- Backend: the same p11b project used by the approved Staging app.
- The executed aggregates are project-wide, grouped by policy; no owner
  filter was used. Timing after launch supports the recovery association but
  does not individually attribute every request or fact to the owner.
- Phase 5 cutover: **2026-09-28 22:27:11 UTC**.
- Pre-update baseline cutoff: **2026-09-30 21:49:39 UTC**, taken from the
  clock before the queries. The SQL save aggregate adds an upper bound at
  that instant so later saves cannot be attributed to the baseline.
- Only policy/count/time/mode/state aggregates and fixed-name refusal counts
  were selected. No activity values, raw log rows, request bodies, tokens,
  actor/session/challenge identifiers or per-person Health records were read
  or retained. Refusal names are matched server-side; raw messages are not
  selected. An additional runbook goal fingerprint is computed server-side
  and kept only in private ignored scratch; its hash is not printed or put
  in this public receipt.
- SQL runs inside `begin read only` / `rollback`. Log queries use explicit
  adjacent windows, each within the tool's 24-hour limit. They are not a
  polling loop, and overlapping checks are never added together.
- This agent performs no Xcode, device or simulator action, hosted mutation,
  deployment, credential change or goal change. The existing recovery fix was
  already verified as deployed; no redeploy is needed for this check.
- This agent has not independently inspected the installed phone version.
  Any installed-build identity or launch observation below will be explicitly
  attributed to the main device owner.

The [earlier Health audit](HEALTH_AUDIT.md) preserves deployed-source identity,
the focused 77-test Deno result and the reasoning for keeping one uploading
installation. The approved action is a same-bundle Staging update preserving
the account, journal and active goals; it is not a TestFlight second bundle.

## Pre-update baseline

The runbook Step 7 grouped save query returned **`[]`** for the interval
after **2026-09-28 22:27:11 UTC** through **2026-09-30 21:49:39 UTC**.
There are **zero saves**, with no latest save, modes or states to report.
This is not a statement about the person's underlying activity.

| UTC log window | HTTP 422 | HTTP 200 | Other statuses | First HTTP 422 | Latest HTTP 422 |
| --- | --- | --- | --- | --- | --- |
| Sep 28 22:27:11 → Sep 29 22:27:11 | 17 | 0 | None | Sep 28 23:18:21.950 | Sep 29 21:50:11.753 |
| Sep 29 22:27:11 → Sep 30 21:49:39 | 19 | 0 | None | Sep 29 22:50:13.733 | Sep 30 21:44:57.759 |
| Combined adjacent windows | **36** | **0** | **None** | Sep 28 23:18:21.950 | Sep 30 21:44:57.759 |

| UTC log window | PostgreSQL binding-invalid occurrences | Revision refusal occurrences | Request conflict occurrences | Latest binding-invalid occurrence |
| --- | --- | --- | --- | --- |
| Sep 28 22:27:11 → Sep 29 22:27:11 | 21 | 0 | 0 | Sep 29 21:50:11.704 |
| Sep 29 22:27:11 → Sep 30 21:49:39 | 24 | 0 | 0 | Sep 30 21:44:57.711 |
| Combined adjacent windows | **45** | **0** | **0** | Sep 30 21:44:57.711 |

These are **log occurrences, not distinct failed requests**. A refusal can
be logged more than once. The ingest function's own scoped logs matched none
of the three fixed refusal names in either window. The zero-match `maxIf`
epoch default is omitted rather than presented as a real timestamp.

The fresh baseline supersedes the earlier audit's cutoff at 20:56:13 UTC; the
counts from those overlapping audits must not be added together. The earlier
34-request result and this 36-request baseline describe different endpoints
of the same observation period.

**Inference only:** repeated closed-binding retries remain consistent with
an older installed client. These aggregates do not identify the rejected
binding or distinguish every possible terms/membership mismatch. The main
agent's later installed-app inspection establishes the version/build below;
it is separate device evidence.

## Device timeline and post-update comparison

| Milestone | UTC time | Evidence/disposition |
| --- | --- | --- |
| Hosted pre-update baseline cutoff | Sep 30 21:49:39 | Independently queried here. |
| Earlier device availability inventory | Not supplied | Main agent reported paired but unavailable; app inventory failed CoreDevice 4016 and USB inventory showed no iPhone. Unsandboxed read-only CoreDevice and USB/IORegistry checks confirmed the earlier block. This agent did not run those checks. |
| Successful installed-app inspection | Approximately Sep 30 21:56 | Main agent reports Staging 0.8.1 (926.26.1) only; no production/TestFlight GameTime bundle. |
| Same-bundle update completed | Sep 30 21:57:10–21:57:14 | Main agent reports install success and metadata Staging 0.9.0 (930.26.1); production bundle absent. |
| Updated Staging launch | Sep 30 21:57:58–21:57:59 | Main agent reports launch success, no fixture arguments/environment. Post-update log boundary is strictly 21:57:59 UTC. |
| Runbook fingerprint snapshot | Sep 30 21:58:42.372806 | Independently queried after launch: 8 goals, 1 commitment, no charge rows and 105 migrations. This is not a before-update fingerprint. |
| First post-update aggregate cutoff | Sep 30 22:00:19 | Independently queried here; details below. |
| Clean post-recovery/final save cutoff | Sep 30 22:04:53 | Independently queried here; excludes the initial refusal when counting clean-window requests. |
| Account/goals retention | After launch; exact time not supplied | Owner confirmed: “Account and goals are still there”. User observation, separate from hosted aggregates. |

The main agent reports that the source/binary hash still matches the prepared
candidate. The reported data-container paths differ before and after the
update. A changed container UUID/path alone does not establish whether
contents were cleared or migrated. The main agent independently reports that
the original Staging journal and comparison-cache directories/files are
present, using metadata only. Comparison-cache JSON files modified on
September 21 and September 26 remain present after the update, establishing
that these files predate it. The upload journal is present and modified at
21:59:40 UTC; normal upload recovery can change its contents. Neither agent
read bodies or Health values. Neither unchanged journal bytes nor an
unchanged data-container path is claimed. User-confirmed account/goals
retention is independent evidence.

The private post-launch goal fingerprint is retained in
`tmp/testflight-readiness-2026-09-30/private-goal-fingerprint-after-launch.json`
with file mode 600. The earlier `before` filename was corrected after the
actual launch timestamp arrived. A first fingerprint result could not be
parsed from the tool wrapper; the bounded retry produced the retained
21:58:42 snapshot. There is no valid pre-update fingerprint from this attempt,
so no before/after unchanged-hash assertion is made.

## First post-launch hosted check

The strict observation window is **2026-09-30 21:57:59 → 22:00:19 UTC**.
The Step 7 aggregate after the original cutover and the separate aggregate
after launch returned the same rows. All new saves in this check are after
the launch; the pre-update save baseline remains zero.

| Policy | Saved facts | Latest save UTC | Modes | States |
| --- | --- | --- | --- | --- |
| `personal_distance_goal_v1` | 13 | Sep 30 21:59:40.025755 | `private_account` | `unresolved` |
| `personal_steps_goal_v1` | 12 | Sep 30 21:59:31.564114 | `private_account` | `unresolved` |

| HTTP status | Requests | First UTC | Latest UTC |
| --- | --- | --- | --- |
| 422 | 1 | Sep 30 21:58:01.218 | Sep 30 21:58:01.218 |
| 200 | 23 | Sep 30 21:58:02.766 | Sep 30 21:59:40.084 |

No other HTTP status appeared. Scoped PostgreSQL logs had **one**
binding-invalid occurrence at **21:58:01.145 UTC**, zero revision refusals
and zero request conflicts. Scoped function logs matched none of the three
names. There was no further binding-invalid occurrence through 22:00:19 UTC.
Fact counts and HTTP request counts are different aggregates and need not be
equal; this check does not join or inspect individual requests.

**Recovery interpretation:** a single early permanent refusal followed by
successful current saves is consistent with the newer client retiring a
previously queued closed-binding request. The exact refused request identity
was deliberately not read, so that attribution remains an inference. It must
not be described as recurring post-update failure, nor omitted from the
post-launch result. The two-minute window is evidence for its own cutoff,
not a promise that no later refusal can occur.

## Clean post-recovery window and final save aggregate

The follow-up requested by the main agent deliberately starts **after** the
initial refusal: **2026-09-30 21:58:02 → 22:04:53 UTC**. It returned only
**31 HTTP 200 requests**, first at **21:58:02.766 UTC**, latest at
**22:04:02.566 UTC**. No HTTP 422 or other status appeared.

Scoped function logs matched none of the three refusal names. No PostgreSQL
rows matched the ingest-function context in this clean window, so no new
binding-invalid, revision-refusal or request-conflict occurrence was observed.
The zero-match timestamp default is omitted. This clean result does not erase
the initial post-launch refusal or establish anything after 22:04:53 UTC.
The first and clean post-launch windows overlap: their counts are **not added**.

The separate Step 7 save aggregate after the original cutover, bounded through
22:04:53 UTC, returned:

| Policy | Saved facts | Latest save UTC | Modes | States |
| --- | --- | --- | --- | --- |
| `personal_distance_goal_v1` | 16 | Sep 30 22:04:02.488336 | `private_account` | `unresolved` |
| `personal_steps_goal_v1` | 15 | Sep 30 22:01:38.616296 | `private_account` | `unresolved` |

The initial 23 HTTP-success responses and 25 persisted facts were separate
metrics. The final fact and clean-window request totals happen to be equal;
that is not evidence of a one-request/one-fact relationship.

## Observation freshness

One additional read-only aggregate, authorized by the main agent, groups
only policy/mode/state and counts/minimum/maximum metadata timestamps. It
looks at facts recorded after **21:57:59 UTC** through the same final
**22:04:53 UTC** cutoff and separates observations stamped before/from launch.

| Policy | First-check facts | First-check observations before launch | Final facts | Final observations before launch | Earliest observed UTC | Latest observed UTC |
| --- | --- | --- | --- | --- | --- | --- |
| `personal_distance_goal_v1` | 13 | 0 | 16 | 0 | Sep 30 21:58:01.875429 | Sep 30 22:04:01.128672 |
| `personal_steps_goal_v1` | 12 | 0 | 15 | 0 | Sep 30 21:58:03.209724 | Sep 30 22:01:37.875937 |

All 25 initial facts and all 31 final facts have observation timestamps after
launch. The earliest/latest queried-through timestamps match each policy's
observed range. First recorded timestamps are **21:58:02.691482 UTC** for
distance and **21:58:04.612759 UTC** for Steps; latest recorded timestamps
match the final save table. Mode is `private_account` and state `unresolved`
for every group.

These are fresh **client observation timestamps**. The saved facts do not
simply carry original pre-launch observation timestamps, but this does not
prove that a native Health read succeeded. The wire format omits the local
reason for an unresolved observation, so these aggregates cannot determine
its cause.

The count/mode/HTTP-success and clean ongoing-refusal checks are now
demonstrated through the stated cutoffs.
All saved states are `unresolved`, so this check does **not** demonstrate
accepted activity totals, restored visible scores or completion of physical
Health acceptance. The owner has confirmed account/goals retention but has
not yet supplied the updated app's Health-card state. The main agent owns
that device follow-up and any later observation boundary.

Step 7 passes only with at least one post-cutover Steps-policy save and one
distance-policy save (`*_steps_goal_v1`, `*_distance_goal_v1`), mode
**`private_account`**, HTTP 200 ingest results and no new binding-invalid
refusals. A successful install or launch alone is not that evidence. The
existing outdoor-distance correction window closes **October 3, 05:00 UTC**;
do not reopen or reinterpret it after that deadline.

## Remaining runtime check

The native validation agent's read-only source review found no proven new
reader/adapter defect. The unresolved wire representation omits the local
reason (`ios/GameTimeCore/Sources/GameTimeCore/ChallengeHealthUpload.swift:27–32`).
Reader/adapter rules are unchanged from `b86a006`; the later optional
comparison-cache field is backward compatible, and container UUIDs are not
part of its keys. Goal refresh queries the exact agreed goal dates. The
separate 30-day permission probe does not gate goal refresh.

Current Steps rules require Watch-origin steps. Current distance rules use
whole Apple Workout outdoor Watch runs contained within the agreed goal
window. Permission-sheet completion alone does not establish readable
Health access. These are existing source-policy constraints; this work did
not relax them or change a missing-data result.

The exact next runtime check belongs to the main device owner:

1. Refresh the active Steps goal and obtain the exact **Health-card heading
   and message**, without reporting a score or activity quantity.
2. If that message indicates an access issue, inspect the relevant Health
   read permissions. A connected account and successful HTTP response do not
   establish those permissions.
3. Use the resulting status to distinguish access, empty eligible activity,
   goal-window filtering or another local reason. The backend's `unresolved`
   state does not distinguish those causes. No further hosted queries were
   needed after the bounded freshness result in this receipt.

## Exact read-only query shapes

Save aggregate used for the baseline:

```sql
begin read only;
select l.policy, count(*) as saves, max(f.recorded_at) as latest,
       jsonb_agg(distinct r.verification_mode) as modes,
       jsonb_agg(distinct f.state) as states
from app.challenge_real_health_facts_v1 f
join app.challenge_lobbies_v1 l on l.id = f.challenge_id
join app.challenge_real_health_requests_v1 r on r.request_id = f.request_id
where f.recorded_at > '2026-09-28T22:27:11Z'::timestamptz
  and f.recorded_at <= '2026-09-30T21:49:39Z'::timestamptz
group by l.policy order by l.policy;
rollback;
```

Each status/reason query uses the explicit start/end parameters in its table.
The function filter below replaces the independently resolved deployment
identifier with a placeholder; no identifier is selected or recorded here.

```sql
select log_attributes['response.status_code'] as http_status,
       count(*) as requests, min(timestamp) as first_at,
       max(timestamp) as latest_at
from logs
where source = 'function_edge_logs'
  and log_attributes['function_id'] = '<INGEST_FUNCTION_ID_FROM_METADATA>'
group by http_status order by http_status;
```

```sql
select source,
       countIf(position(event_message, 'challenge_real_health_binding_invalid') > 0)
         as binding_invalid_occurrences,
       countIf(position(event_message, 'challenge_invalid_real_health_revision') > 0)
         as revision_refusal_occurrences,
       countIf(position(event_message, 'challenge_request_conflict') > 0)
         as request_conflict_occurrences,
       maxIf(timestamp, position(event_message, 'challenge_real_health_binding_invalid') > 0)
         as latest_binding_invalid_at
from logs
where (source = 'function_logs'
       and log_attributes['function_id'] = '<INGEST_FUNCTION_ID_FROM_METADATA>')
   or (source = 'postgres_logs'
       and position(log_attributes['parsed.context'], 'challenge_real_health_ingest_v1') > 0)
group by source order by source;
```

All five baseline calls completed successfully. No local tests were rerun as
part of this new acceptance check; their existing receipts remain distinct.
The four first-post-launch calls, three clean/final calls and one freshness
call also completed successfully. The first post-launch reason query adds
`minIf(timestamp, …)` for the first binding-invalid occurrence; otherwise
it uses the same fixed-name/scoped query above. Post-launch save queries use
the baseline shape with the lower/upper time bounds named in their sections.

The exact freshness query was:

```sql
begin read only;
select l.policy, r.verification_mode as mode, f.state,
       count(*) as saved_facts,
       count(*) filter (where f.observed_at < '2026-09-30T21:57:59Z'::timestamptz)
         as observed_before_launch,
       count(*) filter (where f.observed_at >= '2026-09-30T21:57:59Z'::timestamptz)
         as observed_from_launch,
       min(f.observed_at) as earliest_observed_at,
       max(f.observed_at) as latest_observed_at,
       min(f.queried_through_at) as earliest_queried_through_at,
       max(f.queried_through_at) as latest_queried_through_at,
       min(f.recorded_at) as first_recorded_at,
       max(f.recorded_at) as latest_recorded_at,
       count(*) filter (where f.recorded_at <= '2026-09-30T22:00:19Z'::timestamptz)
         as first_check_facts,
       count(*) filter (where f.recorded_at <= '2026-09-30T22:00:19Z'::timestamptz
                          and f.observed_at < '2026-09-30T21:57:59Z'::timestamptz)
         as first_check_observed_before_launch,
       count(*) filter (where f.recorded_at <= '2026-09-30T22:00:19Z'::timestamptz
                          and f.observed_at >= '2026-09-30T21:57:59Z'::timestamptz)
         as first_check_observed_from_launch
from app.challenge_real_health_facts_v1 f
join app.challenge_lobbies_v1 l on l.id = f.challenge_id
join app.challenge_real_health_requests_v1 r on r.request_id = f.request_id
where f.recorded_at > '2026-09-30T21:57:59Z'::timestamptz
  and f.recorded_at <= '2026-09-30T22:04:53Z'::timestamptz
group by l.policy, r.verification_mode, f.state
order by l.policy, r.verification_mode, f.state;
rollback;
```
