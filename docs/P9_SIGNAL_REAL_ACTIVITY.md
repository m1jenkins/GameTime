# P9 Signal real activity — local implementation contract

D139 records the owner’s selected scope. The implementation branch is
`codex/p9-signal-real-activity`, directly from P8
`8a9d1f007ab235d580d83bae47077a26f13090a7`. Main began at `848ef6e` and advanced separately to `cb3a0ec` during this task;
it now contains P8 but not P9.
The [implementation report](../outputs/reports/2026-09-20-p9-signal-real-activity.md)
records exact source, commands, results, failures and unperformed acceptance.
This is local software work using synthetic readers and owned loopback resources.

## Delivery comes before new activity

`ChallengeHealthTransportCoordinator` is one app-lifetime lease shared by P8
readiness and activity, retained metric uploads, Personal coverage and diagnostic
requests. Each endpoint keeps its own exact body, receipt checks and recovery.
The diagnostic writer now has a protected, backup-excluded exact-request journal.
`AssertionCounterDecoder` lives in GameTimeCore; production imports no conformance target.

After acquiring the lease and checking the actor/session, reload every registered
journal. Validate all assertions before sending any, then recover in ascending
assertion-counter order per key. Gaps are allowed. Malformed assertions and
conflicting duplicate counters fail closed. Failed earlier delivery blocks new
signing. Hold the lease through signing, durable save, send, receipt validation
and acknowledgement. Never repair a saved request by changing bytes or signing again.

Launch/foreground/recovery opportunities drain signed work even with an empty
challenge list or after ingestion closes. Gate-off recovery can retrieve an exact
committed response; it does not authorize a new fact. Existing terminal key
rejection behavior remains endpoint-specific. Sign-out keeps owner-scoped files;
only the owning account’s valid session may resume them.

## Health ownership and lifecycle

AppModel owns `ChallengeHealthFlowStore`, separate from ChallengeV1Store. A typed
mapper accepts activity only from fresh authorized server terms with matching
source, metric, digest, agreement version, frozen instants and timed distance.
The nullable `source_policy_version` projection also describes open lobbies and
restricted rows without exposing their hidden agreement. Membership and redaction
remain server-owned. Local draft contexts cannot produce challenge uploads.

Each actor/session/binding/window/purpose gets its own reader. Suggestion history
is a distinct purpose. The local comparison cache uses private persistence types,
complete file protection and backup exclusion; raw snapshot types remain outside
network serialization. It stores only reconciliation fields, at most 40 bounded
files per actor (16 MiB each), and at most 64 pending challenge IDs. Restore only
an exact binding, then do a fresh bounded read. Cache corruption or inaccessible
state cannot supply a positive replacement. Retire completed comparison records.

Seven readiness states remain distinct: unsupported, notConnected, checking,
ready, noEligibleDataYet, temporarilyUnavailable, staleOrIncomplete. Permission
completion, successful empty queries and authentic assertions do not prove
readiness or completeness. Final consent/community joining requires an
acknowledged matching readiness check, at most five minutes old, plus deliberate
consent. Terms/distance changes invalidate that context and pending consent.

Browsing and drafting need no Health access. Access is requested contextually.
Readiness uses 30 days for quantities/cumulative distance and 90 days for comparable
timed runs. Suggestions use 28 days for cumulative totals and 90 days for timed
runs, stay local, and require deliberate selection. Cumulative suggestion is
`ceil(total × days / 28 × 1.10)`; timed is `floor(best comparable seconds × 0.95)`.
There are no leaderboard or community-target suggestions and no live 98% helper.

Authenticated launch, foreground, manual Refresh, connection completion, relevant
Health observers, protected-data availability and connectivity/session recovery
coalesce into bounded work. Observers complete promptly; hourly background delivery
is an opportunity, not a guarantee. Retained Personal observers remain usable.
Cancel native queries and fence completions by actor, logical session and binding
operation. Navigation cancellation never withdraws a challenge. Suspension clears
restricted local presentation and stops new reads/signatures; support, appeal and
exit routes remain. Accepted account deletion clears the new owner-scoped caches,
journals and signer state. Ordinary sign-out does not.

Before every replacement, recover signed work and re-read server terms. A current
failed/partial refresh produces explicit unresolved replacement work while ingestion
is open; it must not silently keep an old positive result current. Display local
activity, pending delivery, server update, provisional and final result separately.
Initial submissions close at end +24 hours; corrections at end +48 hours, both
inclusive. Review closes 48 hours after the actual notice, resolution 72 hours
from filing. After correction closes, only server refresh and exact recovery occur.

## Source versions and results

| Source | Current behavior |
| --- | --- |
| `apple_watch_steps_v1` | D138 Watch quantities, reconciliation, whole-step floor, explicit deletions and unresolved disappearance. |
| `apple_watch_exercise_v1` | Strict causal exclusions remain unenforceable; readiness/admission and positive ingestion stay unavailable. Historical agreements and requests keep their meaning. |
| `apple_watch_exercise_credit_v2` | Separate adapter/registry/terms for new agreements. Retain D138 writer/Watch rules and reconciled switching. Exclude identifiable manual/unsupported records; accept unknown **causal** origin. Other uncertainty remains unresolved. Reconcile first, then `floor(total minutes × 60)` once. |
| `apple_workout_outdoor_distance_v1` | Whole outdoor runs inside both frozen boundaries; crossing workouts excluded. Reconcile supported Watches and floor cumulative millimetres. |
| `apple_workout_outdoor_timed_v1` | Whole runs within inclusive 100–102% of selected distance. Elapsed start-to-finish includes pauses, rounds up. Success requires strictly below target; equality/slower does not establish a miss. |

The Exercise reader now uses active `min(end, observation time)` bounds, bounded
plus anchored queries, explicit deleted UUIDs, scope fencing and native cancellation.
New Exercise terms freeze accepted causal uncertainty into each new friend/Personal
digest. New-version screens say **Activity minutes** and explain Apple Exercise
credit, including indirectly derived credit and that this is not every movement minute.
Community stays steps-only. Minimal normalized network envelopes are unchanged;
old exact-request decoding and historical consent remain intact. No raw records,
routes, source names, comparison history or suggestion baselines leave the phone.

Positive activity can prove success; incomplete history never proves a miss or
complete ranking. Real `value` observations are distinct from fictional `complete`
facts. Deleted/unresolved values never become zero, a loss, or rank.

| Flow | Result and simulated allocation |
| --- | --- |
| Personal goal | Proven success returns the entry; unresolved activity ultimately voids and returns it. |
| Two friends | Both succeed: both entries return. One unresolved leaves fewer than two resolvable participants: whole challenge voids and both recover their entry. |
| Six friends | Four successes and two unresolved: four met, two excluded, everyone recovers their own entry. No confirmed misses exist to redistribute. |
| Community steps | Individual success/exclusion with configured outcome minimum. Below minimum: void and return entries. |
| Real leaderboard | New creation unavailable for each metric. Existing records retain review, exits, history and unresolved/void processing; no inferred ranking or winner. |

Community counts require at least five joined, active, nonremoved participants
and a server snapshot at least 15 minutes old. Never substitute local counts;
this disclosure threshold is separate from the configured outcome minimum.
Existing invitations, exact username lookup, own targets, roster freezing,
reconsent, notices, reviews, reports, appeals and non-punitive exits remain.
Existing challenges and historical Personal creation/refresh/history remain usable.

## Reproducing focused local checks

Use fresh task-owned resources. The P9 wrapper reuses P8’s guarded setup and
populated-upgrade runner, with both new forward migrations in order:

```sh
python3 scripts/p9-signal-health-verify.py prepare --manifest /private/tmp/<owned>/stack.json
python3 scripts/p9-signal-health-verify.py apply-forward --manifest /private/tmp/<owned>/stack.json
python3 scripts/p9-signal-health-verify.py check --manifest /private/tmp/<owned>/stack.json --tap 523_challenge_signal_health_v2
```

The script’s `check` option can receive repeated `--tap` selectors for affected
historical suites. Never reset or attach to another checkout’s project. Its
manifest contains credentials: keep mode 0600, out of logs and version control.
The synthetic native controller accepts only this owned loopback stack:

```sh
deno run --config supabase/functions/deno.json --allow-net=127.0.0.1 --allow-env \
  --allow-read=/private/tmp/<owned>/stack.json --allow-write=/private/tmp/<owned>/native.json \
  --allow-run=docker scripts/p9-signal-health-controller.ts \
  /private/tmp/<owned>/stack.json /private/tmp/<owned>/native.json
```

The current native tests read `/private/tmp/gametime-p9/native.json`; use that
path for this harness or deliberately change the test-only locator. The controller
creates fictional Auth actors, verifies synthetic assertions through actual Edge
handlers and PostgREST, and changes only its owned source clock. Run the ordinary
AppModel tests before the June UI journey, serially. The full four-metric matrix
respects actor-wide server quotas and can exceed the MCP five-minute reply limit;
the underlying Xcode result bundle remains authoritative. A failed community
run can leave its single published fixture open. For a fresh publication, rebuild
only this manifest-owned disposable stack instead of bypassing the one-community
rule or deleting product history. `--authenticated-app-local
--p9-synthetic-health` is explicitly local-only and instantiates no physical
Health reader or Apple signer. Full product periods are advanced with the source
clock, not shortened. SIGTERM restores the prior clock, closes local ingestion
and revokes its fictional sessions. Stop it before running the P8 HTTP/race runner,
which owns the same test clock while active. `p8-real-health-http.ts` now accepts
`exercise` for v2 as well as steps/distance/timed. Cleanup uses the manifest’s owner
checks and preserves receipts outside disposable databases.

## Unchanged external boundaries

Nine supported goals plus four unavailable leaderboard states are the local P9
result. D140 makes the nine goals the working Beta scope and defers friend
leaderboards; four goal-metric source acceptance remains open. All 18 external
readiness entries, checked-in transport and default server gates remain closed. Local community
settings are fixtures, not publication choices. Hosting identities, community
launch settings, operating approval, replacement retirement and full P12/P13
acceptance remain separate. No deployment, distribution, recruitment, money,
physical Health upload, historical cleanup or restart of P7 is part of P9.
