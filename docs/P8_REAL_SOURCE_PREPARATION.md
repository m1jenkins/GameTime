# P8 preparation — real activity facts and processing

## Current implementation authority — September 19, 2026

[D138](../DECISIONS.md#d138-owner-selects-p8-source-rules-and-whole-run-distance-tolerance)
supersedes the open product questions in this preparation: Apple automatic
Watch steps/Exercise, Apple Workout outdoor runs, reconciled multiple Watches,
whole workouts entirely inside the frozen window, and inclusive 100–102% timed
distance with whole elapsed seconds rounded up. The owner signed off measured
physical testing; do not restart P7. Historical observations below remain
unchanged. The local P8 implementation and
[software checks](../outputs/reports/2026-09-19-p8-real-health.md) use separately
versioned real contracts. Exercise remains unavailable because causal origin
cannot be established; complete leaderboards and confirmed misses remain
unresolved. No checked-in transport, hosting or release gate has been opened. The
[real Health contract](P8_REAL_HEALTH_CONTRACT.md) separates selected rules,
supported API interpretations and concrete platform limits.

## Historical preparation

Prepared September 19, 2026 from the consolidated `main` checkout. [D137](../DECISIONS.md)
records the owner's P7 test sign-off and direction to prepare P8. The
[P7 session record](../outputs/reports/2026-09-18-p7-device-session.md) still
distinguishes performed observations from inconclusive and unperformed checks.
This is an implementation handoff, not a real-source policy, migration, source
acceptance, deployment or release authorization. All source/ingestion gates in
[readiness.json](release/beta/readiness.json) remain false.

## Reuse the existing seams

| Existing component | P8 use and current boundary |
| --- | --- |
| [`ChallengeHealth*`](../ios/GameTimeCore/Sources/GameTimeCore/ChallengeHealthContracts.swift), [health contract](BETA_HEALTH_CONTRACTS.md) | Frozen actor/agreement/metric/window identity, seven readiness states and revision rehearsal exist. Public adapters accept only `.unaccepted`; encoded revisions say `synthetic_only`. A real policy and transport must be separately versioned. |
| [`WeeklyHealthSourceProbe`](../ios/GameTime/GameTime/WeeklyHealthSourceProbe.swift) | Debug/Staging investigation only. It neither filters eligible sources nor proves read completeness. Do not wire it directly to scoring. |
| [`challenge_runtime_v1`](../supabase/migrations/20260908042918_challenge_steps_contract_v1.sql), [fictional lifecycle](../supabase/migrations/20260908043438_challenge_steps_lifecycle_v1.sql) | Existing challenge tables, requests, facts and worker patterns are reusable. Real ingestion and per-source flags have `CHECK (NOT ...)` guards; fixture capture and processing require fictional mode. Flipping a flag cannot turn this into real scoring. |
| [`ChallengeV1Client`](../ios/GameTime/GameTime/ChallengeV1Client.swift), [P8 concurrency result](../outputs/reports/2026-09-13-p8-concurrency.md) | Authenticated request/session patterns and the landed Privacy1/S1 corrections are foundations. The existing client is not an attested Health upload path; do not restart those corrected races. |

The historical `ingest-metrics` and Personal Health paths are separate
contracts. Their payloads, permissive source rules and persisted agreements do
not become new Beta facts by renaming or widening a flag.

## Source-policy inputs before real scoring

The owner's P7 sign-off applies to the test effort. These terms still need an
explicit version and a defensible rule before the respective P8 adapter can
admit real facts:

| Metric | Recorded observation | Rule still needed |
| --- | --- | --- |
| Steps | Phone- and Watch-origin steps appeared; overlap was flagged. A manual test entry remained invisible after the selected time was adjusted, but a positive-control read was not confirmed. | Eligible device/source lineage, manual/import exclusion, overlap/deduplication, correction and late-sync treatment, and trustworthy missed-goal handling. |
| Apple Exercise Time | Watch-origin records appeared; the hand-entry field was not supplied. | Whether generated Exercise samples distinguish manual/imported activity, overlap, correction and integer-second normalization. |
| Cumulative running | Watch-origin whole workouts appeared; one privately measured run was reported accurate; Watch-only runs later appeared after sync. | Eligible workout/source lineage, imports, duplicates, boundary crossing, edit/deletion, distance normalization and missing-data treatment. |
| Timed running | One paused run showed reported duration shorter than start-to-finish elapsed time; a whole record remained inspectable in the window check. | The cumulative-running rules plus a measured whole-workout distance tolerance, comparable-distance qualification and conservative whole elapsed-second precision. No tolerance was selected. |

For every metric, an empty or unavailable read remains unresolved, never a
confirmed zero or miss. A positive eligible record can support readiness only
under the adopted 30-day/90-day history rules; it cannot prove complete access.
If a policy cannot establish trustworthy miss handling, retain a safe
unresolved/void path and leave that source disabled. Do not invent a numeric
tolerance or a new source allowlist from the observations above.

## Bounded P8 implementation sequence

1. Record each accepted source policy as a new version: eligible provenance,
   overlap/reimport resolution, units and rounding, full-window versus whole-run
   boundaries, freshness, revisions/deletions and missing-data resolution.
   Freeze that version with actor, agreement digest, metric and absolute window.
   Policy-neutral contract design and rejection tests can be prepared while
   those decisions are made; no public adapter becomes accepted merely because
   a query succeeds.
2. Add a separate real ingestion boundary, default off. Accept only normalized
   minimum facts: actor/challenge/terms/source-policy binding, frozen window,
   replacement value or deleted/unresolved state, monotonic revision, freshness,
   exact request identity and required integrity binding. Reuse App Attest only
   where its existing claims fit. Reject raw records, routes, source names,
   baselines, arbitrary policy IDs and client-authored `complete`, `verified`,
   qualifying or final flags. Keep exact committed-response recovery and account
   isolation. Preserve all historical and fictional contracts.
3. Connect an iPhone-only real reader to the accepted adapter, with the seven
   readiness states and on-device history/suggestions. A permission prompt or
   empty successful read never becomes Ready. The Watch contributes through
   Apple Health on the iPhone; there is no GameTime Watch app.
4. Reuse the existing challenge admission/worker/review primitives to derive
   results server-side. Start with steps only **after** its policy is explicit,
   then carry the proven path to Exercise, cumulative running and timed running.
   Prove a real-contract create → consent → activity → downward correction →
   provisional notice → review → final simulated history journey without fixture
   shortcuts. Preserve the 24/48-hour activity/correction and notice-relative
   review windows, safe exits and exact retries.
5. Verify wrong actor/terms/window/policy, session switch, replay, response
   loss, concurrent revisions, deletion, late facts, partial/no reads and
   independent server outcome derivation. Include the already-landed Privacy1/S1
   race regressions, affected RLS/grant checks, old-data upgrade and historical
   agreement smoke. Use an owned disposable local database; no hosted mutation
   or physical-data upload is authorized by this packet.

When implementing new public-schema tables reachable through Supabase's Data
API, review explicit per-role grants **and** RLS together; current Supabase
[Data API defaults](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically)
no longer make new tables automatically reachable on new projects. Keep raw
fact storage private and expose only the narrowly authorized boundary. Do not
use a blanket grant or `SECURITY DEFINER` to make a permission failure vanish.

## Completion boundary

This preparation is complete when the owner disposition, code seams, missing
policy inputs, first safe slice and verification path are explicit. P8 itself
is complete only after versioned accepted policies, real minimum-fact ingestion,
source-backed results and the required local tests are implemented. P9 app
integration, hosted operation, all-mode distribution, human/physical release
checks and real money remain separate gates under the
[remaining plan](GAMETIME_REMAINING_IMPLEMENTATION_PLAN.md).
