# Pre-hardware Challenge Health contracts

Prompt 3 adds portable contracts and deterministic synthetic tests at the landed
Prompt 0A parent `7c34d52bc0250053819e35342a2b4fd9ed5d7382`. It does not enable
real-source consent, source acceptance, ingestion or any external feature gate.
There is no shipping GameTime watchOS app. D135's path remains Apple Watch activity
syncing into iPhone Health, followed by a future iPhone reader and minimum-fact
upload. No native source, entitlement, project, package manifest, server or runtime
integration is changed by this slice.

## Boundaries and ownership

All paths below are relative to `ios/GameTimeCore/` unless otherwise stated.

| File | Responsibility |
| --- | --- |
| `Sources/GameTimeCore/ChallengeHealthContracts.swift` | Versioned source-policy identity, actor/agreement binding, frozen query interval, metric/unit types, non-serializing observations and transport protocol |
| `Sources/GameTimeCore/ChallengeHealthAdapters.swift` | One adapter interface, four closed implementations, exactly seven readiness states and observation/policy separation |
| `Sources/GameTimeCore/ChallengeHealthReadSession.swift` | In-memory generation, account/terms and latest-attempt fences around an asynchronous store read |
| `Sources/GameTimeCore/ChallengeHealthRevisions.swift` | Synthetic replacement chain and exact-byte in-memory retry journal |
| `Tests/GameTimeCoreTests/ChallengeHealthAdapterTests.swift` | Metric, normalization, history, metadata, change and policy-closure scenarios |
| `Tests/GameTimeCoreTests/ChallengeHealthSessionTests.swift` | Deterministic readiness, cancellation and asynchronous race scenarios |
| `Tests/GameTimeCoreTests/ChallengeHealthRevisionTests.swift` | Replacements, actor/terms isolation, retry bytes, frozen boundaries and serialization privacy |
| `Tests/GameTimeCoreTests/Fixtures/FakeChallengeHealthStore.swift` | In-memory records and manually released continuations; no clock waits, device, network or persisted Health data |
| `docs/BETA_HEALTH_CONTRACTS.md` (repository root) | This contract, limitations and future seams |

`WeeklySourceRecord` and `WeeklySourceFeasibility` are reused unchanged. They
already retain tri-state manual metadata, source/sync identities, active workout
duration and window diagnostics without serialization or source acceptance.
Exact duplicate UUIDs collapse only after equality validation. Conflicting
same-ID records in one snapshot are invalid; successive snapshots may contain
lower same-ID edits. The existing 5,000-record resource guard is retained as a
diagnostic bound, never a physical threshold or completeness claim.

The existing native `WeeklyHealthSourceProbe` remains a private diagnostic reader
with three raw query families. Its Exercise values are **minutes**, and its
running records hold millimetres plus optional reported active duration. New
contracts do not silently relabel these as canonical Exercise seconds or timed
elapsed seconds. `PersonalHealthStepReader`, `PersonalHealthReadiness`, legacy
provenance classification, hourly payloads and upload queues are not changed or
adopted as new challenge policy. Their behavior is not physical acceptance.

Future native transport may conform to `ChallengeHealthStore` and return only
`ChallengeHealthStoreOutcome`. Its adapter mapping and asynchronous cancellation
must be reviewed before integration. It must fail an unavailable distance read
as unavailable, as the current probe does, rather than synthesize a zero-valued
workout. Source metadata is diagnostic input, not proof of origin. The native
authorization UI, protected persistence, observers and server ingestion stay
outside this ownership. No load-harness files or resources are owned here.

## Version 1 values and policy closure

`ChallengeHealthBinding` freezes actor UUID, challenge UUID, positive agreement
version, a 64-character lowercase hexadecimal terms digest, metric, absolute
microsecond challenge boundaries, timezone, calendar and an **unaccepted** policy
identifier/version. A local read adds its device-held request UUID, query window
and purpose. Challenge activity must query the exact frozen challenge window;
readiness history must end before or at the proposed challenge start and use the
same timezone/calendar. No device-current timezone is consulted to rebuild it.

The agreement/scheduling owner must supply the adopted pre-start history window:
30 calendar days for steps, Exercise and cumulative running; 90 for a comparable
whole timed workout. This slice validates and preserves supplied intervals; it
does not implement the calendar scheduler, comparable-distance selection or
baseline suggestions. A readiness-history request alone cannot make any public
adapter ready, regardless of the supplied interval's length.

| Adapter | Canonical observation | Unresolved physical policy |
| --- | --- | --- |
| `ChallengeHealthStepsAdapter` | Integer count | Eligible source/provenance, normalization and overlapping writer reconciliation |
| `ChallengeHealthExerciseAdapter` | Integer seconds | Exercise lineage, minutes-to-seconds normalization and reconciliation |
| `ChallengeHealthRunningDistanceAdapter` | Integer millimetres, cumulative | Workout/source eligibility, distance normalization and window crossings |
| `ChallengeHealthTimedRunAdapter` | Best qualifying whole-run `end - start` integer elapsed seconds | Whole-workout distance eligibility, measured tolerance and fractional elapsed normalization |

Public adapter initializers have no accepted-policy input. Public
`ChallengeHealthSourcePolicy` has only `.unaccepted`; successful queries and
metadata cannot construct accepted source capability. Every evaluation's real
consent, ingestion and trustworthy-miss properties are immutable `false`.

Internal `ChallengeHealthSyntheticPolicy` is available to `@testable` tests only.
Each fixture supplies explicit per-record exclusions/canonical contributions or
whole timed-run qualification, explicit resolution of overlap/reimport concerns,
and a supplied freshness deadline. This is a closed rehearsal path, not a
configurable real source allowlist. Missing decisions fail unresolved. Production
callers cannot inject this policy through the public API. Synthetic evaluation is
marked `syntheticOnly`, and still has no real acceptance or ingestion capability.

Fixture cumulative adapters sum supplied canonical contributions with overflow
checks. Fixture timed runs select the least positive integral elapsed duration
among explicitly qualifying whole workouts. Active duration, pause subtraction,
pace inference, segment slicing and a distance-tolerance default are absent.
Fractional elapsed durations remain unresolved rather than choosing rounding.
Boundary-crossing contributions remain unresolved unless explicitly excluded by
the synthetic fixture. These choices do not accept a physical boundary policy.

## Seven semantic readiness states

| State | Meaning in this contract |
| --- | --- |
| `unsupported` | The supplied device capability says Health is unavailable |
| `notConnected` | No completed source-request lifecycle for this metric/context |
| `checking` | A current bounded read is in progress |
| `ready` | Only an explicitly synthetic policy has admitted positive eligible, fresh pre-start history |
| `noEligibleDataYet` | No positive eligible observation; denial and genuine absence remain intentionally indistinguishable |
| `temporarilyUnavailable` | Protected data, offline/query failure or a cancelled current read |
| `staleOrIncomplete` | Prior visibility was lost, or binding/window/freshness/normalization/evidence is not usable |

Completing a permission request moves an enabled session at most to
`noEligibleDataYet`. A successful empty query and explicit zero never produce a
zero activity fact or ready state. A positive challenge-window activity value
does not establish readiness history or completeness. A limited-history read can
contain positive synthetic eligible history while still proving neither full
read access nor a trustworthy miss. `earliestAuthorizedSampleDate == nil` is
unknown, not full access. Freshness is separately supplied evidence and is not
derived from permission completion or a sample merely being present.

Snapshots, raw records, local read requests and evaluations have no `Encodable`
conformance. Completeness is an evidence category, never a client `complete`
boolean. Anchored changes, observer invalidations, truncated reads and explicit
tombstones produce no normalized aggregate; they require a bounded requery.
Disappearance between snapshots is `lostVisibility` unless there is explicit
deletion evidence. A subsequent `boundedSnapshotAfterDeletion` can carry explicit
on-device tombstone IDs alongside remaining records; it can lower the synthetic
observation without mistaking a delta for a whole-window read. It still proves
no complete access or miss. Session history retains unresolved prior visibility across
repeated empty reads instead of forgetting a possible permission-loss event.

## Replacement and replay rehearsal

`ChallengeHealthRevision` contains only the frozen binding, device-held request
UUID, revision UUID and previous-revision link, a `value` / `deleted` /
`unresolved` replacement, integer observation/freshness timestamps and evidence
category. The encoder marks every body `contractVersion: 1` and
`mode: synthetic_only`. It is not a production ingestion API. It cannot carry raw
sample IDs, source/device names, sync identities, routes, baseline/history windows
or earliest-authorized timestamps. Metric identity fixes the integer value's unit.

`ChallengeHealthRevisionJournal` encodes a body once with sorted JSON keys and
returns the saved `Data` for retries. Reusing a request UUID with different content
fails. A new revision must link to the latest revision, use a new revision UUID,
preserve actor/terms/metric/frozen window and have a nondecreasing observed time.
Lower values replace higher ones; deletion requires the explicit deletion
evidence category; lost visibility is unresolved. Switching binding drops this
journal's retry access, including an away-and-back switch. Nothing is sent.

The journal is deliberately in-memory and does not claim protection, crash
recovery, idempotent server acceptance, attestation, capacity limits, expiration,
or deletion of persisted data. A future outbox must supply bounded protected
storage, an independent session fence at send time and a separately reviewed
production wire schema. Constructing a synthetic revision cannot enable a real
route. No successful-read-to-revision conversion is implemented.

`ChallengeHealthReadSession` increments a generation on every configure and an
attempt on every read. It checks generation, latest attempt, complete request
identity and cancellation after the await. Changing actor, terms or request,
switching away and back, and completing an older read after a newer one all
discard stale output. The fake store exposes requested calls and releases them
explicitly so races are reproducible without sleep. A future native reader still
owns cancellation/stop of the underlying platform query; ignoring stale output
is not a claim that a native query was stopped.

## Current Apple documentation consulted

Primary documentation was retrieved on 2026-09-09. These are API/privacy facts,
not observations of a physical device or acceptance measurements:

- Health read denial is intentionally not distinguishable from unavailable
  readable data. Write authorization status cannot establish read permission.
  Positive limited-history dates may be exposed; an absent date entry can mean
  full access **or denial**. Future native integration must check availability of
  the limited-history API on its supported OS versions. [Authorization](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)
- Health data can be inaccessible while protected/locked. Authorization and
  storage privacy remain separate from measurement. [Privacy](https://developer.apple.com/documentation/healthkit/protecting-user-privacy)
- Anchored queries describe additions and deletions since an anchor. An anchor
  does not certify the completeness of a challenge window. [Anchored queries](https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery)
- Observer callbacks signal changes and need follow-up reads; the notification
  does not supply a reconciled total. [Observer queries](https://developer.apple.com/documentation/healthkit/executing-observer-queries)
- Background delivery needs its entitlement and completion handling; delivery
  frequency is a ceiling, not a freshness promise. It needs device validation.
  No background registration was performed here. [Background delivery](https://developer.apple.com/documentation/healthkit/hkhealthstore/enablebackgrounddelivery(for:frequency:withcompletion:))

## Required physical inputs and later owners

The existing `gametime-beta-source-acceptance-b7` task remains authoritative.
[Physical sessions](BETA_PHYSICAL_SESSIONS.md) and
[source investigation](BETA_SOURCE_INVESTIGATION.md) remain unperformed for this
slice. No new captain question or acceptance task is created.

1. Select and opt into physical iPhone/paired Watch sessions, with private raw
   observations and device/OS scope. Establish eligible source rules per metric,
   manual/import/nil handling, source/sync identity semantics and overlap/dedup
   reconciliation. No manufacturer/bundle-name heuristic is accepted here.
2. Establish Exercise lineage and all canonical quantity normalization/rounding,
   including edits, lower corrections, deletion versus loss of visibility, late
   sync and incomplete/limited history.
3. Decide workout window-boundary handling and measured whole-run distance
   tolerance; establish elapsed fractional-second normalization without excluding
   pauses. No fallback numeric tolerance or physical accuracy value is included.
4. Observe lock/offline/revocation, observer/background behavior, refresh delays,
   timezone/calendar/midnight/DST behavior and late-sync freshness. Establish if
   any accepted source policy can support trustworthy misses; unresolved sources
   remain off, and a ready positive-history state alone cannot support a miss.
5. Version accepted source terms and policy identifiers before native adapters,
   goal suggestions, real consent or attested minimum-data ingestion can use them.
   Existing agreements and fictional sources keep their original semantics.

`gametime-beta-release-readiness-b7` retains device/distribution, support, legal,
retention and publication choices. Local code acceptance resolves none of them.
Prompt 3 owns no downstream implementation, load harness or release gate.

## Validation scope

Run focused `swift test --filter ChallengeHealth`, the full portable GameTimeCore
suite using a unique `--scratch-path`, and the read-only
`python3 scripts/check-iphone-product.py` source guard. Exact commit, commands,
exit codes, counts, failed attempts and scratch/log identities belong in the
task's `implementation-report.md` and `command-manifest.json`.

Tests cover synthetic units, manual/import/nil/source/sync metadata, overlaps,
exact duplicates and out-of-order additions, lower edits, tombstones/lost
visibility, late sync, limited history, pauses/whole runs/distance, crossings,
frozen intervals, transport failures, permission ambiguity, cancellation,
actor/terms/generation fences, replacement chains, exact retry bytes and raw-data
serialization exclusions. These are software assertions only. Native builds,
Simulator execution, background delivery, authorization prompts, real reads,
physical accuracy, signed ingestion, server deployment and runtime journeys are
unperformed and are not represented as passing.
