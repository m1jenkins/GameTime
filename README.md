# GameTime

GameTime is an iPhone app for private friend challenges and personal activity
commitments. **Signal is the approved native design system:** Home, Challenges
and You use system typography, adaptive colors, open rows and native controls.
Existing Personal challenges remain accessible until replacement acceptance.
All new challenge amounts are nonredeemable simulation.

Develop from `main` in `/Users/user/Documents/GitHub/GameTime`, using an isolated
task branch when needed. Read `git status --short --branch` before changing files.
[Working baseline](docs/WORKING_BASELINE.md) owns current source and verification
status; [remaining plan](docs/GAMETIME_REMAINING_IMPLEMENTATION_PLAN.md) owns next
work. This is a local implementation baseline, **not Beta readiness**.

## Current status

Published `main` was verified at `1dacc6644f2100567d85fbaa2970bb7285bbaa35` on
September 15, 2026. It includes P4–P6, Signal/P9A, P7 and P10 preparation,
S2/P8 privacy and recovery corrections, local P11A worker/operator/deletion
implementation, and the bounded P9 shared-session app connection.

Ordinary signed-in Signal can use the existing authenticated challenge client
when explicitly configured. `GAMETIME_CHALLENGE_V1_ENABLED` remains off in
checked-in configuration. Local fixtures and disposable HTTP checks do not
establish real Apple identity, accepted Health sources or hosted operation.

P7–P13 still require four accepted physical sources and timed-run tolerance,
real ingestion/adapters and all 13 source-backed policies, approved hosted
identities/settings and operating checks, then integrated candidate,
physical/accessibility/human and release acceptance. All 18
[readiness entries](docs/release/beta/readiness.json) remain false. The baseline
cleanup does not start those tasks or authorize distribution, hosting or money.
The owner [started a private P7 device session](outputs/reports/2026-09-18-p7-device-session.md)
on September 18; its partial observations do not accept any source.

## Start here

| Need | Authority |
| --- | --- |
| Current source, completed work and evidence | [Working baseline](docs/WORKING_BASELINE.md) |
| Remaining sequence and bounded tasks | [Remaining plan](docs/GAMETIME_REMAINING_IMPLEMENTATION_PLAN.md), [prompt pack](docs/FIRSTMATE_REMAINING_IMPLEMENTATION_PROMPTS.md) |
| Adopted product rules | [Project memory](PROJECT_MEMORY.md), [business model](docs/BUSINESS_MODEL.md), [Beta contract](docs/BETA_IMPLEMENTATION_PLAN.md), [decisions](DECISIONS.md) |
| UI design and native verification | [Signal contract](docs/design/SIGNAL_UI_MIGRATION.md), [adopted study](outputs/design/2026-09-13-clickable-app-alternate/DESIGN.md) |
| User-facing language | [Copy contract](docs/COPY.md), required before changing any app string |
| iPhone, Watch-origin data, community and capacity boundaries | [Remaining-work contract](docs/BETA_REMAINING_WORK_CONTRACT.md) |
| Source and release gates | [Physical sessions](docs/BETA_PHYSICAL_SESSIONS.md), [acceptance](docs/BETA_REAL_VALIDATION_ACCEPTANCE.md), [handoff](docs/BETA_REAL_VALIDATION_HANDOFF.md) |
| Local challenge walkthrough | [Preview and ordinary-session guide](docs/BETA_LOCAL_PREVIEW.md) |
| Local worker, operator and recovery commands | [Operations guide](docs/BETA_OPERATIONS_LOCAL.md) |
| Checkout recovery and cleanup disposition | [Consolidation record](docs/WORKTREE_CONSOLIDATION_STATUS.md) |

## Run and check locally

The checked-in Xcode project is the build source of truth; no project generation
is needed. Open `ios/GameTime/GameTime.xcodeproj`, select `GameTime`, and choose
an iPhone Simulator. See the [native guide](ios/GameTime/README.md) for schemes,
configuration, retained fixtures and focused test examples.

```sh
xcodebuild build -project ios/GameTime/GameTime.xcodeproj \
  -scheme GameTime -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath tmp/DerivedData CODE_SIGNING_ALLOWED=NO

python3 scripts/check-iphone-product.py \
  --app "$PWD/tmp/DerivedData/Build/Products/Debug-iphonesimulator/GameTime.app"

swift test --package-path ios/GameTimeCore
```

For an offline presentation check, launch the Debug app with `--fixture-mode
--fixture-product-shell`. `--fixture-mode` alone exercises retained Personal.
Use the [local preview guide](docs/BETA_LOCAL_PREVIEW.md) for fictional friend,
personal and community HTTP journeys. Interactive demo mode can read device
Health; it is not the deterministic test fixture.

For the historical weekly portable gate, run `scripts/weekly-local-verify.sh`
from a committed checkout. It owns a unique disposable local stack. Follow
[weekly acceptance](docs/WEEKLY_LOCAL_ACCEPTANCE.md) for exact prerequisites and
commands; never run `db reset` or the reset-owning `scripts/db-test.sh` against
another checkout's running project. Weekly verification is a separate historical
contract, not Beta source or release evidence.

## Repository layout

| Path | Purpose |
| --- | --- |
| `ios/GameTime/` | Signal iPhone app, retained product routes, native and UI tests |
| `ios/GameTimeCore/` | Swift package for normalization, source contracts and durable queues |
| `ios/GameTimeConformance/` | Separate historical/generic App Attest engineering harness |
| `supabase/migrations/`, `supabase/tests/` | Applied schema history and behavioral SQL regressions |
| `supabase/functions/` | Authenticated service boundaries and TypeScript tests |
| `scripts/` | Existing local runners, product guards and operating tools |
| `docs/` | Operative contracts, acceptance, release decisions and evidence |
| `outputs/reports/` | Dated performed checks, preserved failures and source identities |
| `outputs/design/2026-09-13-clickable-app-alternate/` | Approved Signal browser reference; fictional data |

## Preserved products and data

Personal remains a seven-day daily or cumulative steps agreement with internal
test-only or Stripe sandbox behavior. New/open migrated agreements use automatic
Apple Health snapshot v2; missing final step data does not count against the
person. Historical agreements retain their own policies and exact consent.
[Personal acceptance](docs/PERSONAL_HEALTH_SNAPSHOT_V2_ACCEPTANCE.md) owns that
contract and its unperformed device/hosted checks.

Local duel, performance-commitment and weekly implementations retain their
separate versions and fixture restrictions. The new `challenge_*_v1` domain
implements the D134/D135 Beta contract; generic distance fields or dormant social
code are not substitutes for it. [PLAN.md](PLAN.md) preserves the historical
roadmap. [Dormant subsystem contracts](docs/archive/2026-08-03_DORMANT_SUBSYSTEMS.md)
cover Solo, charity, legacy social and geofence behavior. Historical Watch source
is inert and remains outside active targets. Cleanup never converts agreements
or deletes their data.

## The evidence ledger

The historical hourly ledger is distinct from Personal snapshot v2 and the new
Beta source contracts. `metric_snapshots` appends observations;
`contest_evidence` selects admissible values. Within a source, revisions are
monotone and the largest value wins; disjoint sources add. Hours align to the
participant's timezone epoch, not UTC. The Apple-device adapter merges overlapping
iPhone/Watch records before upload; those device totals must not be added twice.

Authenticated clients cannot directly write this ledger. Signed ingest verifies
exact request bytes and identity before a service-only RPC applies replay,
counter, window and append-only invariants atomically. Stable request IDs recover
lost responses; changed content under the same ID is rejected. Personal v2 uses
its separate authenticated daily-snapshot policy. Neither historical mechanism
accepts the new real-source Beta policies. See [D6/D36 and the ledger decisions](DECISIONS.md),
[conformance guide](docs/M6_5_DEVICE_CONFORMANCE.md), and
[Beta Health contracts](docs/BETA_HEALTH_CONTRACTS.md).

Dated reports retain their original test counts, failures and limits. Historical
paths and next-task instructions are not current resource ownership or permission
to repeat a deployment, device session or cleanup.
