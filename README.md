# GameTime

An iOS social accountability app. Friends stake charitable donations against
each other's personal goals; the loser donates an agreed amount to a charity the
winner picks. No cash prizes, no payouts to users, no pots — the stake is a
pledge, and the app tracks whether it was honored.

The product is verification credibility. These are people betting against
friends who will try to cheat, so anti-cheat and data provenance are core domain
logic, built and tested as such — not a later phase.

**Status: M0 complete.** Scaffold, local Supabase, migration and test harness,
CI. No domain schema yet.

---

## Repository layout

```
supabase/
  config.toml            Local stack configuration
  migrations/            Hand-written SQL. The only way schema changes.
  tests/                 pgTAP suites: schema, constraints, RLS
  functions/
    _shared/             Scoring engine, anti-cheat rules, shared utilities
    deno.json            Deno tasks, imports, lint and format config
  seed.sql               Local/CI seed data. Never required by a test.
ios/
  GameTimeCore/          Portable Swift package. No Apple frameworks.
                         Builds and tests on Linux CI.
  (app target lands in M8)
scripts/
  dev-up.sh              Start the local stack
  db-test.sh             Reset the database and run pgTAP
  test-all.sh            Everything CI runs, in CI's order
DECISIONS.md             Every non-obvious choice and why
```

## Prerequisites

| Tool         | Version tested | Notes                                       |
| ------------ | -------------- | ------------------------------------------- |
| Supabase CLI | 2.109.1        | `brew install supabase/tap/supabase`        |
| Docker       | 29.x           | Must be running before `dev-up.sh`          |
| Deno         | 2.9.x          | `brew install deno`                         |
| Swift        | 6.3.x          | Ships with Xcode 16+; standalone on Linux   |
| Xcode        | see below      | Only needed from M8, for the app target     |

## Setup

```bash
git clone <this repo> && cd GameTime

# 1. Secrets. Apple credentials are only needed once auth is wired up (M1);
#    the stack starts without them and just warns.
cp .env.example .env.local

# 2. Bring up Postgres, PostgREST, Auth, Storage, Studio.
./scripts/dev-up.sh

# 3. Reset the database from migrations and run the schema suite.
./scripts/db-test.sh
```

Local endpoints once the stack is up:

| Service          | URL                                                |
| ---------------- | -------------------------------------------------- |
| API gateway      | http://127.0.0.1:54321                             |
| Postgres         | `postgresql://postgres:postgres@127.0.0.1:54322/postgres` |
| Studio           | http://127.0.0.1:54323                             |
| Mail (Mailpit)   | http://127.0.0.1:54324                             |

Realtime and analytics are switched off on purpose — see DECISIONS.md D8.

## Running tests

```bash
./scripts/test-all.sh          # everything, in CI's order
```

Or individually:

```bash
./scripts/db-test.sh                                     # pgTAP
cd supabase/functions && deno test --allow-env           # Edge Functions
cd ios/GameTimeCore && swift test                        # Client core
```

Three suites, three jobs in CI, one command locally. They must stay in step:
if you add a suite, add it to both `scripts/test-all.sh` and
`.github/workflows/ci.yml`.

## Working on the schema

Migrations are hand-written SQL files under `supabase/migrations/`, named
`YYYYMMDDHHMMSS_description.sql`. Nothing is changed through the Supabase
dashboard and the CLI's diff engine is not part of the workflow — the
constraints, triggers, and RLS policies in this schema carry intent that a
generated diff would strip.

```bash
# New migration
touch supabase/migrations/$(date -u +%Y%m%d%H%M%S)_add_something.sql

# Apply it, plus the seed, and run the suite
./scripts/db-test.sh
```

Two conventions the baseline migration sets up, both asserted by
`supabase/tests/000_harness.test.sql`:

- Extensions live in the `extensions` schema, never `public`.
- Helper functions used by RLS policies live in `app`, which is not exposed
  through the Data API. A policy can call them; a client cannot.

## Test-harness capabilities

The harness proves out the three things later milestones depend on:

- **pgTAP** — schema shape, privileges, and that `app.forbid_mutation()`
  genuinely rejects UPDATE and DELETE. Append-only is the property the whole
  evidence ledger rests on, so it is asserted from the first commit.
- **Deno** — Edge Function logic, tested by importing handlers directly rather
  than booting the runtime container.
- **Swift Testing** — portable client logic under Swift 6 strict concurrency.

## Known environment constraints

Two things that bit during M0, recorded so they do not cost anyone a second
afternoon:

- **`edge-runtime` needs a raisable `RLIMIT_NOFILE`.** In a sandbox capped at
  4096 without `CAP_SYS_RESOURCE`, the container cannot start. Work around it
  with `EXCLUDE_SERVICES=edge-runtime ./scripts/dev-up.sh`. Function *tests* are
  unaffected — they run under plain Deno by design (DECISIONS.md D9).
- **Supabase CLI telemetry can fake a test failure.** The CLI flushes PostHog on
  shutdown; where that endpoint is unreachable the flush times out and the CLI
  exits non-zero with every test passing. The scripts and CI export
  `DO_NOT_TRACK=1`, which is the right default here anyway. Keep it if you add
  a script that shells out to the CLI.
- **pg-delta is switched off.** It tried to fetch from npm inside a container on
  every `db reset`, which fails outright on a TLS-intercepting network. Nothing
  here diffs a schema, so it is disabled in `config.toml`.

## Client target

iOS 18.0, Swift 6 language mode. This was a reasoned pick rather than a measured
one — M0 was built in a Linux container with no Xcode — so confirm it against
your toolchain with `xcodebuild -version`. The reasoning is in DECISIONS.md D2;
changing it is one line in `Package.swift`.

## Milestones

- [x] **M0** — Scaffold, local Supabase, migration and test harness, CI
- [ ] **M1** — Schema and RLS for identity, friendships, groups
- [ ] **M2** — Contest creation, invitations, participant state machine
- [ ] **M3** — HealthKit sync, attested ingest, `metric_snapshots`
- [ ] **M4** — Scoring engine with fixture tests, including fraudulent fixtures
- [ ] **M5** — Anti-cheat rules and integrity scoring
- [ ] **M6** — Geofence check-ins and workout-overlap validation
- [ ] **M7** — Settlement, disputes, charity pledge lifecycle, cron finalization
- [ ] **M8** — Minimal SwiftUI shell
