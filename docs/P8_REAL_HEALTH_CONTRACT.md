# P8 real Health contract

D138 records the owner's selected policies. This document describes their
engineering interpretation; physical observations stay in the dated P7 session.
Local implementation is on `codex/p8-real-sources` from
`848ef6ee02d95b57bdad4b36d3c7600a4ba3f192`. External gates remain closed.
The [software verification record](../outputs/reports/2026-09-19-p8-real-health.md)
separates performed checks from platform and P9 integration limits.

## Source attribution and its limits

Use HealthKit's OS-owned `sourceRevision.source.bundleIdentifier` together with
`sourceRevision.productType`, preserving missing manual metadata as unknown.
HealthKit identifies the app/device responsible for saving an object through
its [source revision](https://developer.apple.com/documentation/healthkit/hkobject/sourcerevision).
Device names and manufacturer strings are descriptive, not admission rules.

The V1 engineering interpretation recognizes the exact `com.apple.health`
namespace boundary and ASCII `Watch<digits>,<digits>` product-type grammar.
This is a versioned device-family interpretation, not an Apple-published closed
device list or a measured P7 result. Unknown product/source combinations remain
unresolved. Explicit manual entries and identified unsupported writers/devices
are excluded. A missing manual-entry marker never admits a record by itself.

Apple Exercise Time has a concrete causal-lineage limitation: HealthKit's
quantity samples identify their writer/device but do not expose a link to the
activity or workout that caused the Exercise credit. The strict exclusion of
credit derived from manual/imported/third-party workouts therefore cannot be
established by that tuple. Its real capability must remain unavailable under
the adopted policy; a ring total is not a substitute.

For running, the supported interpretation is an Apple system writer on a Watch,
a running workout and explicit `HKMetadataKeyIndoorWorkout == false`. The
[indoor-workout metadata](https://developer.apple.com/documentation/healthkit/hkmetadatakeyindoorworkout)
describes whether the record is marked indoor/outdoor. No route upload or GPS
attestation is introduced. Elapsed time uses `endDate - startDate`, not
[workout duration](https://developer.apple.com/documentation/healthkit/hkworkout/duration),
which excludes pauses.

## Reconciliation and missingness

Query the full frozen steps/Exercise window. Crossing quantity records cannot
be divided without known in-window contributions. Running uses only whole
workouts inside both boundaries. Equal UUID records collapse after content
equality; conflicting same-ID records remain unresolved. A confirmed higher
sync revision from the same writer and sync identity can replace a prior
revision. Independent nonoverlapping Watches add; unexplained overlap does not
choose a preferred Watch. Totals can decrease.

[Anchored queries](https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery)
can return explicit deletion UUIDs. An absent row in a fresh snapshot is not a
deletion. Read permission and complete visibility are intentionally opaque in
HealthKit. No successful empty read establishes zero, a miss, or complete
history. Positive readiness is distinct from trustworthy finality.

## Ingestion and recovery

The new `ingest-challenge-health` boundary signs exact normalized JSON bytes.
It verifies the authenticated actor/session and App Attest signature; the
database checks the live session, suspension, key ownership/revocation, exact
request identity and monotonically increasing device counter under locks.
App Attest proves app-key possession, not a Health record's truth/completeness.

The envelope binds contract version, actor, challenge, agreement version/digest,
fixed source-policy version, metric, frozen instants, request ID, replacement
revision/parent, value/deleted/unresolved state, observation time and query-through
time. Timed uploads additionally bind `distance_mm` to the selected distance
in both the live configuration and frozen agreement: 17 activity fields for
timed running, 16 for other metrics. The readiness envelope has six fields
for timed running and five otherwise; comparable readiness for 5 km cannot
admit 10 km. It excludes raw records, routes, source names, history, baselines and
client-authored completeness/qualification/final flags. Values replace previous
values; they never add to or take the maximum of prior uploads.

The iPhone journal persists exact bodies and signatures before sending, under
account-specific protected files excluded from backup. It stores no access
token. Relaunch retries preserve the original bytes. Account/session changes
and cancellation fence signing and response application. Gate-off recovery
can retrieve an exact committed response but cannot create a new fact.

The two P8 clients require a shared transport coordinator backed by both
journals. Its account lease spans session preparation, signing, persistence,
sending and acknowledgement. Each client drains its existing exact requests
before signing another; pending work in the other journal blocks a new signature
until its owner recovers it. Relaunch checks the saved journals again. A failed
retry cannot be bypassed by signing a later request.

Server grants and RLS are explicit together, following the current
[Supabase API guidance](https://supabase.com/docs/guides/api/securing-your-api).
Facts and request payloads remain in the private schema. Existing fictional,
Personal, Solo and charity agreements keep their meaning and consent bytes.


## Results and local capability

| Source | Implemented local behavior | Remaining limit |
| --- | --- | --- |
| `apple_watch_steps_v1` | Bounded and anchored Watch quantities, downward whole-count totals, explicit deletions and unresolved replacements | Positive totals are lower bounds, not complete history |
| `apple_watch_exercise_v1` | Local reader, minute-to-second normalization checks, explicit unsupported readiness, rejection of positive upload and real admission | Public quantity APIs do not expose the causal activity needed to enforce the adopted exclusions |
| `apple_workout_outdoor_distance_v1` | Whole outdoor workouts, reconciled Watch changes, floor aggregate millimetres | No complete-history assertion or confirmed miss |
| `apple_workout_outdoor_timed_v1` | Raw recorded distance within inclusive 100–102%, ceil whole elapsed seconds including pauses, strict elapsed below target | A qualifying observed run is an upper bound on the best time, not a complete leaderboard |

The real server evaluator consumes its own immutable normalized ledger and
reuses the thirteen-policy allocation oracle. A quantity lower bound at the
target, or timed upper bound below the target, can prove a met goal. Below-target
quantities, absent/unreadable data, unresolved replacements, and all real
leaderboards remain unresolved/void. No query or App Attest assertion certifies
complete Health history. Software-seeded Exercise contracts test defensive
refusal/void behavior; they are not reachable real admission.

Initial submissions remain open through end +24 hours, and corrections through
end +48 hours, inclusive. Provisional processing follows the correction window;
72-hour notice overdue monitoring is operational, not permission to shorten a
late notice. Review closes 48 hours after the actual notice and resolution is
72 hours after actual filing. Existing withdrawals, minimums, exclusions, ties,
nonredeemable allocation and historical consent remain unchanged.

A failed or partial refresh must not silently retain a previous positive fact.
`realReplacementDecision.normalizedReplacement` maps uncertainty to an explicit
unresolved replacement, without calling it a deletion or zero. The request still
requires the same frozen binding and monotonically advancing revision.

## P9 integration boundary

These readers and default-off transport clients are not connected to ordinary
Signal flows in P8. P9 must connect readiness, consent, ongoing refresh,
correction, review and history without exposing raw Health history. Preserve
all seven readiness states; keep 30-day quantity/distance history, 90-day
comparable timed history and 28-day suggestions on-device. The timed suggestion
is 95% of the best comparable elapsed time, rounded down.

P9 must reuse one shared P8 coordinator for readiness and activity, and extend
signing-through-commit/recovery coordination to any retained Personal writer
using the same App Attest key. The P8 coordinator covers its two clients; it
does not govern existing Personal delivery. Signing through an uncoordinated
writer before an earlier uncommitted request is recovered can advance the
server counter and permanently reject the older assertion. Drain pending exact
requests before signing another writer's request; do not blindly regenerate
signatures. Coordination with retained writers remains a P9 integration gate.

Exercise availability, complete leaderboards/misses, P9 app integration,
approved hosting/operations, privacy/human/release acceptance and distribution
remain separate. The owner has closed the measured P7 effort; none of these
software checks requests or invents additional physical measurements.
