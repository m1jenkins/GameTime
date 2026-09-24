# GameTime

GameTime is an iPhone app for private friend challenges and personal activity
commitments. The current app uses the September 22 approved Signal presentation
with Home, Challenges and You. Existing Personal challenges remain accessible
until replacement acceptance. All new challenge amounts are nonredeemable
simulation.

Develop from local `main` in `/Users/user/Documents/GitHub/GameTime`. Check
`git status --short --branch` before editing and use a short-lived task branch.
Completed authorized work is committed and merged locally; pushing is separate.

## Start here

Read this page and [project memory](PROJECT_MEMORY.md), then the relevant latest
entry in [the working baseline](docs/WORKING_BASELINE.md). The
[friends TestFlight plan](docs/FRIENDS_TESTFLIGHT_PLAN.md) owns the current
D142 delivery sequence and open gates. Local implementation, hosted changes and
release acceptance are recorded separately; none should be inferred from a
historical completion report.

| Need | Reference |
| --- | --- |
| Implemented behavior and performed checks | [Working baseline](docs/WORKING_BASELINE.md) |
| Current next work and first-build scope | [Friends TestFlight plan](docs/FRIENDS_TESTFLIGHT_PLAN.md) |
| Adopted direction and product rules | [Project memory](PROJECT_MEMORY.md), [business model](docs/BUSINESS_MODEL.md), [Beta contract](docs/BETA_IMPLEMENTATION_PLAN.md), relevant [decisions](DECISIONS.md) |
| Current UI and approved mocks | Latest adoption in [Signal migration](docs/design/SIGNAL_UI_MIGRATION.md) |
| App language | [Copy contract](docs/COPY.md), required before changing app text |
| Source contracts and acceptance | [P8 Health contract](docs/P8_REAL_HEALTH_CONTRACT.md), [P9 app integration](docs/P9_SIGNAL_REAL_ACTIVITY.md), [acceptance](docs/BETA_REAL_VALIDATION_ACCEPTANCE.md) |
| Local walkthrough and operations | [Preview guide](docs/BETA_LOCAL_PREVIEW.md), [operations guide](docs/BETA_OPERATIONS_LOCAL.md) |
| Broader roadmap and retained products | [Remaining Beta plan](docs/GAMETIME_REMAINING_IMPLEMENTATION_PLAN.md), [PLAN.md](PLAN.md) |
| Historical prompts, agent runs and recovery | [Archive index](docs/archive/README.md) |

Search `ios/`, `supabase/` and `scripts/` for implementation first. Default `rg`
searches omit dated reports, archived docs, evidence captures and Lavish studies
via `.ignore`. Follow a current contract's link or use `rg --no-ignore` on a
specific historical directory when checking old evidence. Reusable agent skills
remain in `.agents/skills/`; retired task prompts live in Git history.

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
| `.lavish/gametime-live-goal-2026-09-21/`, `.lavish/gametime-friends-2026-09-22/` | Current approved mocks, linked from the visual contract and friends plan; fictional data |
| `outputs/design/`, `docs/archive/`, `docs/evidence/` | Dated designs, historical contracts and verification artifacts |

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
cover Solo, legacy social and geofence behavior; D143 removed charity. Historical Watch source
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
