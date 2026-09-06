# Weekly source investigation and new metric fixtures

Recorded September 6, 2026. This is local implementation evidence for the W1B
source prototype and independent W3/W4 rule prototypes. It is **not acceptance
of a physical source, a selectable real Exercise/distance mode, or the full W3/W4
stage**. Historical Personal, Solo, charity and fictional official-5K contracts
and their acceptance records are unchanged.

## Implemented boundary

| Component | Implemented behavior | Explicit limit |
| --- | --- | --- |
| `WeeklySourceFeasibility.swift` | Account/window-bound raw-record diagnosis; exact UUID deduplication, conflicting identity rejection, overlaps/reimports, manual versus absent marker, lost visibility, late arrivals and bounded captures | Always reports no qualifying total, no source admission and no confirmed-miss support. It never adds raw overlapping device totals. |
| `WeeklyHealthSourceProbe.swift` | Dedicated, unwired Debug/Staging read helper for step count, Apple Exercise time or running workouts; explicit opt-in defaults false; separate explicit permission request; at most 5,001 records read with 5,000 retained and truncation disclosed | No product route calls it. Release excludes it. No observer, upload, scheduler, cache, new app entitlement or change to existing permissions. Query success/empty results do not disclose read authorization. |
| `weekly-metric-fixtures.ts` | Separate exact-consent and observation binding; pure Exercise-minute, cumulative running-distance and whole-run timed-distance evaluation; injected microsecond clock; replacement corrections; fictional closed-set versus unknown data | No ingestion, migration, agreement persistence, worker, final result, allocation or payment. The literal fixture sources are the only accepted sources; never expose this evaluator as a client upload API. |
| `MetricPrototypeModels/Store/View.swift` | Separate `metric-prototype-agreement-v1` and actor-bound `metric-prototype-notebook-v1`; durable frozen consent and exact request replay; private replacement observations; chosen cumulative or whole-run timed distance; explicit default-off fixture entry | On-device fictional notebook only. No Health connection, social following, upload, payout, native scoring, notice/review process or final result. Typed Exercise contracts are tested but not offered in the selector. |

The default Personal query remains `HKStatisticsQuery` with `cumulativeSum` over
compatible writers, excluding only explicit `HKMetadataKeyWasUserEntered == true`.
The new probe does not reuse or modify that policy, `ProvenanceClassifier`, the
historical hourly bucketer or the official-5K evaluators. Existing generic
`exercise_minutes` and `distance_meters` enums do not confer new source support.

The probe returns raw records **only in memory to an explicit investigator**;
these include source/device identifiers and health values and must not enter
logs, telemetry, commits, public reports or participant projections. Its
aggregate assessment omits raw identifiers. It holds no account cache. A future
caller must discard a late capture when its account/window is no longer current;
the portable comparison helper rejects cross-account/window and older captures.

## Fixture contracts

- Exercise is `fixture_apple_exercise_minutes_v1`, with integer thousandths of
  a minute. One minute equals 1,000 fixture units; the 30-minute test target is
  only a fixture. Workout duration, calories, ring percentage and Garmin
  intensity minutes cannot enter this contract. The eight frozen local
  midnights describe Monday through Monday and preserve 167/169-hour DST weeks.
- Cumulative distance is `fixture_cumulative_running_distance_v1`, with integer
  millimeters from nonoverlapping fictional running workouts. It supports
  independently chosen targets and durations, including 1/14/120/365-day tests;
  the old 28–90-day range is not reused.
- Timed distance is `fixture_timed_running_distance_v1`, with a chosen distance,
  integer microsecond threshold, explicit strict `<` or inclusive `<=`, full
  end-minus-start elapsed time including pauses, and `whole_run_only` proof.
  The attempt start is inclusive and finish deadline exclusive; equality at
  the closing instant is rejected.
  A daily distance total or multiple shorter runs cannot establish an attempt.
  1,600 m is 1,600,000 mm; a true mile is 1,609,344 mm. Short/long tolerances are
  explicit fictional parameters, defaulted to zero in tests, and are not field
  accuracy approvals. Longer runs are not automatically segmented.
- Every consent contains the exact terms; every observation binds their
  canonical complete value, actor, agreement and source. Unknown fields,
  changed terms, duplicate IDs, malformed dates and unsafe/fractional integers
  are rejected rather than normalized. The binding is a deterministic fixture
  value, not an attestation or server authorization mechanism.
- Revisions replace the whole prior fixture snapshot, with sequential revision
  identity, strict recorded-time ordering and a supersession chain. Deletion
  and downward corrections can remove an earlier provisional success. A later
  slower run does not remove an earlier run still present in the snapshot.
- Explicit manual/imported fixture records do not qualify. Unknown provenance,
  unknown Exercise lineage, unknown fixture capture, duplicate origin IDs,
  overlapping eligible records, partial capture, query failure and source loss
  prevent a miss. Real clients cannot supply the fictional `closed_world` premise;
  no real ingestion exists.
  Even in fixtures a snapshot taken before activity ends cannot assert that
  the future contains no further activity.
- Upload/correction cutoff is exclusive: an observation at equality is refused.
  Decisions remain pending below target until the injected clock reaches that
  cutoff. Only a fictional closed snapshot captured at/after activity end can
  produce `confirmed_miss`; missing/uncertain data produces `unresolved`.
  Every result carries `fixture_only: true`, `final: false`, and
  `real_source_available: false`. No persisted result or review window is
  bypassed by a fixture decision.

`METRIC_FIXTURE_BOUNDS` limits computational inputs: 10,000 records/revision,
100 revisions, a 3,660-day activity window, 30-day correction-window ceiling,
integer observation/target limits and a one-day elapsed-target ceiling. They
are resource/validation choices, not recommended health goals, launch targets,
review deadlines, distance accuracy claims or approved commercial limits.

## Native private distance practice

The separate opt-in Debug/Staging prototype lets a person choose a distance in
meters, kilometers or true miles and a window. Timed records also freeze a time
limit in seconds, strict or inclusive comparison, full elapsed time including
pauses, whole-run proof and explicit fictional zero distance tolerances. No
distance is prefilled or required. The review displays the exact distance in
readable meters, exact decimal seconds and dates in the frozen timezone.

Agreement consent precedes the activity start. Every replacement observation
binds the complete frozen terms; missing, unavailable and lower observations
are supported. Revision timestamps must increase strictly, and new observations
are rejected at correction-cutoff equality. The local correction period is an
explicit 48-hour prototype value. This notebook always displays **unresolved,
not evaluated**; recording a high number does not score a goal. Only serialized
terms are handed to the sole TypeScript evaluator in a dedicated test artifact;
native observations have no implicit mapping to trusted fixture captures.

The notebook uses actor-named, backup-excluded files with complete file
protection and atomic writes. Signout clears visible state; reopening restores
only the same actor's notebook. Trusted account cleanup removes that actor's
file even after signout or with the feature disabled and fences later writes.
Exact saved requests recover before changed admission/cutoff checks; changed
payload reuse fails. Leaving freezes new observations and remains possible
after admission turns off. There are no asynchronous transport responses or
shared-progress reads in this prototype.
If the phone clock moves backward, leaving still succeeds: the private exit
record uses a logical timestamp no earlier than consent or the last saved
update. That timestamp never becomes a scoring clock or a final result.

Resource limits are three open records, 50 retained agreements, 100 revisions
per agreement, 1,024 ordinary request receipts and a bounded two-MiB file.
Reserved receipt slots and 64 KiB of reserved file space preserve a first exit
for every retained agreement when ordinary capacity is exhausted. These are
local resource bounds, not launch exposure or engagement policy.

### Separate lead review of the native prototype

The lead independently identified and the source author corrected:

| Finding | Correction and evidence |
| --- | --- |
| MP1: ordinary request capacity could block a safe exit | First-exit receipt/byte reserves now remain available after capacity and admission shutdown. `testFullRequestCapacityStillAllowsFirstExitWithGateOff` passed after filling all 1,024 ordinary receipt slots and recovering the exact exit. The final 15-test run includes the byte-reserve implementation. |
| MP2: raw internal units/ISO dates obscured the agreement, and capacity copy implied leaving always frees retained storage | Rules now show readable exact meter/second values and local dates; copy promises only reading history and leaving. Precision assertions cover 1,609.344 meters and 600.000001 seconds. |
| MP3: equal revision timestamps differed from the TypeScript contract | New revisions require strictly increasing instants; exact retries still recover. An equal-timestamp rejection regression passed. Native observations remain an explicitly separate unresolved notebook contract. |
| MP5: unsaved private target/time/date/proof inputs could survive an actor change even though consent was cleared | Both forms now clear every private field, request identity, confirmation and message on actor changes, including the global background-to-nil transition. The focused field-state regression passed for target, unit, format, elapsed comparison, dates and proof values in the final 15-test run. |

This is the lead's review of the source author's work, not a self-authored
independent-review verdict. No human comprehension or accessibility outcome is
claimed by the automated tests.

## Source findings from current official documentation

Reviewed September 6, 2026; these are documentation facts and implementation
inferences, not device observations:

| Source | Consequence |
| --- | --- |
| [Apple read authorization](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data) | HealthKit protects read-denial privacy; an app cannot equate missing samples with no activity. Current documentation also describes limited historical access. Device/OS-specific availability must be established before adding a limited-access query. |
| [Apple Exercise time](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/appleexercisetime) | Exercise time is a cumulative time quantity based on qualifying movement; it is not workout duration. The probe requests `.appleExerciseTime` in `.minute()` units. |
| [Manually adding workouts](https://support.apple.com/en-la/101952) | A manually entered workout's start/end can add Exercise credit. Inference: a positive ring total alone cannot prove sensor-only exercise; underlying generated lineage must be measured. |
| [Manual-entry metadata](https://developer.apple.com/documentation/healthkit/hkmetadatakeywasuserentered) | The key describes manual entry when provided. An absent marker remains nil in the probe; its absence is not new proof of automatic recording. |
| [Workout duration](https://developer.apple.com/documentation/healthkit/hkworkout/duration) | A workout's duration may be supplied directly or computed as active duration. The probe retains it only as diagnostic metadata; timed fixtures use start/end elapsed time. |

Apple metadata, a first-party-looking source name or an Apple device string
never enables the source. No rule currently proves a full trustworthy
closed-world activity set from a read-only phone query. If physical research
cannot resolve completeness and generated-lineage concerns, retain unresolved
outcomes or revise the source proposal under a new explicit policy.

## Checks actually run

Commands from repository root unless a directory is indicated:

| Check | Result |
| --- | --- |
| `cd supabase/functions && deno test _shared/weekly-metric-fixtures.test.ts` | Passed: 22 tests, including units, source/terms binding, manual/imported/unknown data, unknown captures across all three metrics, correction/deletion, duplicates/overlaps, cutoff microseconds, DST/travel, chosen distance/tolerance, strict/inclusive elapsed time, exclusive finish, longer windows and replay |
| `cd supabase/functions && deno lint _shared/weekly-metric-fixtures.ts _shared/weekly-metric-fixtures.test.ts` | Passed |
| `cd supabase/functions && deno fmt --check _shared/weekly-metric-fixtures.ts _shared/weekly-metric-fixtures.test.ts && deno check _shared/weekly-metric-fixtures.ts` | Passed |
| `cd ios/GameTimeCore && swift test --filter WeeklySourceFeasibilityTests --scratch-path /tmp/gametime-weekly-source-swift` | Passed: 10 source-diagnostic tests, including instantaneous Health quantities |
| Debug iOS Simulator build including the unwired probe | Passed on Xcode 27.0 SDK; log `/tmp/gametime-weekly-source-build.log` |
| `WeeklyHealthSourceProbeTests.testDefaultProbeCannotReadHealthOrRequestPermission` | Passed on iPhone 17 Pro / iOS 26.5 Simulator: one test covering all three metrics; log `/tmp/gametime-weekly-source-test.log` |
| `MetricPrototypeTests` | Passed: 15 Simulator tests, including complete private form clearing on account/background boundaries, backward-phone-clock safe exit, units, strict timing, DST Exercise contract, consent/terms binding, exact durable replay, downward/missing observations, cutoff equality, actor switch/deletion, corrupt storage, full request capacity and actual native contract export. Lead ran `/tmp/gametime-weekly-final-focused-native.log`; reviewer inspected the passing results. The earlier bridge artifact comes from `Test-GameTime-2026.09.06_01-37-46--0500.xcresult`. |
| `scripts/metric-native-bridge.ts` | Passed format/lint/type checks and execution against the exported actual native XCTest attachment: cumulative, strict/inclusive true-mile timed distance and typed Exercise DST terms are byte-exact with the sole TypeScript validator, and absent observations yield unresolved/nonfinal/unavailable results in all four cases |
| Full portable/historical and coordinated app regression gates | Lead integration owns the final run and records it in the roadmap delivery acceptance |

Reproduce the dedicated app test with an available simulator ID:

```sh
xcodebuild -project ios/GameTime/GameTime.xcodeproj -scheme GameTime \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=39D6A4BA-2A22-446F-83AA-3C8F73A99AF7' \
  -derivedDataPath /tmp/gametime-weekly-source-xcode \
  -only-testing:GameTimeTests/WeeklyHealthSourceProbeTests \
CODE_SIGNING_ALLOWED=NO test
```

To reproduce the native bridge, run the same command with
`-only-testing:GameTimeTests/MetricPrototypeTests`, then export attachments from
the generated `.xcresult`:

```sh
xcrun xcresulttool export attachments --path /path/to/result.xcresult \
  --output-path /tmp/gametime-metric-bridge
deno run --allow-read=/path/to/exported-attachment.json \
  scripts/metric-native-bridge.ts /path/to/exported-attachment.json
```

The export manifest identifies the attachment from
`MetricPrototypeTests/testExportActualNativeTermsForTypeScriptBridge()`.
This run used `/tmp/gametime-metric-bridge/C0A74A33-76DC-4C79-9729-C8C81FCFC8AF.json`.
The script consumes the actual Swift-serialized bytes; it does not substitute a
handwritten fixture or copy scoring logic into Swift.

## Exact remaining device and downstream actions

All rows below are **unperformed**. Mocks, SDK compilation and the Simulator
cannot satisfy them. Record device/OS/app versions, policy and timezone, bounded
counts and assessment outcomes; preserve raw Health data privately on-device.

| Required investigation | Exact next action and decision |
| --- | --- |
| Steps source/manual/import lineage | In a separately instrumented local Debug investigation on a physical iPhone and paired Watch, explicitly opt in to `WeeklyHealthSourceProbe(localInvestigationEnabled: true)`, request `.steps`, capture a frozen interval, then repeat after a known iPhone walk, Watch-only walk, manual Health steps and an imported third-party sample. Compare source/revision/device/manual metadata privately. No new competitive admission until distinguishability is established. |
| Merging, duplicate import, deletion and downward edits | Capture overlapping phone/Watch activity and duplicate reimports; compare the same interval before/after deletion or edits. Design an independently verified reconciliation rule; do not sum raw samples or infer definitive deletion merely from lost visibility. |
| Late sync, locked/offline and permission/source loss | Capture with Watch offline, reconnect after the interval, repeat locked/unlocked and after permission changes. Record actual observation timing and uncertainty; establish a safe unresolved path for every indistinguishable state. Query completion alone cannot support confirmed misses. |
| Frozen timezone, travel and DST | Repeat the same frozen interval after changing phone zone and across spring/fall dates; confirm original window identity and no mixed-account/state capture. |
| Exercise lineage | Explicitly request `.appleExerciseMinutes`; capture before/after a manual Health workout, imported iOS workout, approved Watch session and overlapping sessions, then deletion and late sync. Inspect whether generated Exercise samples preserve sufficient manual/import lineage. If not, keep Exercise unavailable; any sensor-workout alternative requires a separately named policy. |
| Running distance and timed precision | Explicitly request `.runningDistanceMillimeters`; field-test a measured 1,600 m route and true-mile route, pauses, GPS gaps, indoor/outdoor conditions, short-distance error, edits/deletions and imports. Define accuracy/tolerance and whole-run versus segment proof from measured samples before admission. Validate elapsed time separately from reported workout duration. |
| Trusted miss handling | Identify a server-verifiable, privacy-preserving source completeness rule or explicitly choose unresolved protection. Do not add a client `complete`/`verified` flag. This decision blocks new real-source results even if source identification improves. |
| W3/W4 local contracts versus real-source modes | Private fictional persisted agreements, replacement observations and a distance selector are now implemented and tested locally, independently of device approval. Actual Exercise/Health distance selection and real-source lifecycle admission stay blocked until source/policy evidence passes. W3/W4 shared agreements, source ingestion, persisted scoring/review/finality and authorized social following require their own subsequent contracts and acceptance; this private unresolved notebook does not claim them. |
| Accessibility and human comprehension | Run VoiceOver, Dynamic Type, assistive-control traversal and actual agreement/result comprehension on the eventual integrated screens; record participants and actual observations only after separately authorized distribution. |
| Pilot, providers and money | Obtain separate distribution/recruitment authorization and collect actual two-round pilot evidence. Apply Phase 6 provider/legal/platform/funds-flow/exposure gates separately. No Health prototype or fixture test enables any of them. |

No external message, participant recruitment, notification delivery, hosted
mutation, payment-provider operation or live/nonfictional financial state was
performed for this source/metric work.
