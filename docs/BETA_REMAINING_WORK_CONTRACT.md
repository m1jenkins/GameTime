# Beta remaining-work contract — September 9, 2026

D135 records these explicit owner decisions. They supplement D134 and supersede
conflicting future-scope statements in older plans. They do not reinterpret
historical agreements, source policies, data, results or acceptance evidence.

## Six owner decisions

1. **iPhone product; no GameTime watchOS app or WatchConnectivity dependency.**
   Apple Watch records activity into Apple Health. The GameTime iPhone app reads
   eligible Watch-origin HealthKit data and uploads only minimum normalized
   scoring facts. This is the adopted architecture; eligibility, completeness,
   adapters and real ingestion still require their separately versioned work and
   acceptance. An empty successful read never establishes a miss.
2. **A paired physical Apple Watch is required for launch.** Its availability
   does not block pre-hardware implementation waves. Physical iPhone/Watch source
   acceptance remains necessary before distribution; Simulator checks cannot
   replace it. A private device session still needs explicit opt-in and exact
   device selection under the existing source decision task.
3. **Beta community is one operator-published private cohort.** User-hosted
   community challenges are a separately versioned future feature. No community
   publication or discovery is authorized by this contract.
4. **Own progress may be current; exact anonymous aggregates require delayed
   disclosure.** The disclosure cohort must contain at least five joined,
   active, nonremoved participants. Exact anonymous community aggregates must
   come only from a server snapshot at least 15 minutes old. Under five, expose
   no exact numerator, denominator, participant count, qualifier count, total,
   or alternative differential signal. Five is a disclosure threshold, not the
   challenge outcome minimum. This is a remaining implementation contract;
   existing fictional projections are not evidence that it is implemented.
5. **Capacity planning has two distinct workloads.** These are planning and
   characterization targets, not measured capacity or approved live settings:

   | Workload | Registered | DAU | Concurrent sessions | Burst requests/second | Community size |
   | --- | ---: | ---: | ---: | ---: | ---: |
   | Beta planning target | 2,000 | 250 | 100 | 25 | One 250-person cohort |
   | Long-term characterization | 25,000 | 5,000 | 1,000 | 150 | 10,000 |

   The Beta cohort size is a planning target. Actual publication settings,
   including outcome minimum and capacity, remain subject to source,
   comprehension and operating acceptance. No load harness or throughput claim
   is created here.
6. **Every amount remains visibly nonredeemable simulation.** No real charge,
   deposit, balance, payout, fee or thing of value is enabled. Preserve existing
   agreements and their historical test-only/sandbox restrictions.

## Prompt 0A implementation boundary

The isolated implementation parent is exactly
`9c84459e88246e1a34cd2acd6c6f9477384cefec`. Firstmate supplied the completed
independent D9-1 through D9-4 closure and fresh complete Prompt 0 gate at that SHA.
The captain's conditional override permits implementation from this verified
unlanded descendant. It does not accept or land the candidate, approve a merge,
or authorize later implementation waves in this task.

Prompt 0A removes the dedicated Watch runtime from all active GameTime project
configurations. `GameTimeApp` no longer constructs or activates the phone
connectivity coordinator. The project has no Watch target, product, build
phases, configuration list or shared Watch source membership. Its three active
shared schemes build only the iPhone product and its tests.

Historical source remains inert:

- `ios/GameTime/GameTimeWatch/` retains the Watch app and connection views/model.
- `ios/GameTime/GameTimeWatchShared/` retains the handshake types.
- `ios/GameTime/HistoricalWatch/` retains the former phone coordinator, three
  handshake test methods and Watch scheme, with unchanged file contents.

None of those directories belongs to an active target. The three retired
handshake methods describe the removed runtime and are no longer iPhone tests;
this is explicit product retirement, not skipped required tests or a dependency
hidden by test selection. No historical Swift source is deleted. The iPhone
HealthKit entitlement inputs, usage descriptions and Health reading code remain.
There is no project generator in the active repository; the checked-in
`ios/GameTime/GameTime.xcodeproj/project.pbxproj` is the source of truth.

`python3 scripts/check-iphone-product.py` inspects every active project target,
source membership, local package source, configuration and shared scheme. It
rejects Watch runtime references even behind Debug/Staging conditionals or
Release exclusions, and requires the iPhone HealthKit capability. Candidate
preflight invokes that same guard. Its mutation regressions are in
`scripts/tests/check-iphone-product.test.py`.

After a build, use `python3 scripts/check-iphone-product.py --app /absolute/path/GameTime.app`
to inspect bundle contents and every Mach-O executable/dylib/framework. It
rejects Watch payloads, metadata, links and runtime symbols, and requires the
Health usage description and linked HealthKit framework. This reads an existing
product; it neither builds nor signs it and does not open a readiness gate.
Unsigned products establish source/link/packaging evidence, not a provisioned
physical capability or distribution acceptance.

## Verification and handoff

Final candidate evidence belongs in the private task report
`/Users/user/firstmate-workspace/data/gametime-beta-contract-d9/report.md` and its
command/evidence index. Commit the intended source/docs first; record fresh checks
against that exact commit without a later documentation-only SHA change.
Required scope: focused project/packaging regression guards, candidate fixtures,
Personal copy, relevant native launch/source units, Debug and Staging Simulator,
Release Simulator and unsigned iPhoneOS Release builds, changed-document relative
links, historical file/entitlement/migration preservation and `git diff --check`.
Use unique task-owned outputs and a new Simulator if runtime tests are needed.
No existing lab, preview, controller, Simulator or result may be reused/reset.

The supplied parent gate is prior evidence, not a Prompt 0 rerun at this child.
This worker's verification is not an independent Prompt 0A review. Local Xcode
27/iOS 26.5 evidence must not be labeled CI-pinned Xcode/iOS 26.2 evidence.
Acceptance and landing remain pending Firstmate/captain review. The clean Prompt
0A commit is the common parent for later authorized Wave 1 tasks; this task stops
without implementing any of them.

## Remaining decisions and closed gates

- `gametime-beta-source-acceptance-b7` remains authoritative for private physical
  opt-in, the four accepted source policies and measured timed-distance tolerance.
  All physical observations, real adapters/ingestion and real-source journeys
  remain unperformed/unaccepted here. No source semantics are invented.
- `gametime-beta-release-readiness-b7` retains exact release identities/host,
  support/operator coverage, retention/deletion policy, community publication
  settings, human comprehension/accessibility and hosted operating acceptance.
  D135 settles architecture, disclosure rules and planning workloads, not those
  remaining numeric/policy decisions.
- All 18 entries in [readiness.json](release/beta/readiness.json) remain false.
  No database, migration, agreement, source acceptance, server privacy/aggregation
  logic, UI redesign, publication, deployment, distribution, recruitment,
  external message, push, merge or real-money operation is part of Prompt 0A.

See the [Beta plan](BETA_IMPLEMENTATION_PLAN.md), [continuation acceptance](BETA_REAL_VALIDATION_ACCEPTANCE.md),
[handoff](BETA_REAL_VALIDATION_HANDOFF.md), [physical sessions](BETA_PHYSICAL_SESSIONS.md)
and [rollout preparation](BETA_ROLLOUT_PREPARATION.md). Historical verification
counts and resource instructions in older ledgers remain dated records, not
permission for a new worker to use their resources.
