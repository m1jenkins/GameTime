# GameTime

An iOS social accountability app. Friends stake charitable donations against
each other's personal goals; the loser donates an agreed amount to a charity the
winner picks. No cash prizes, no payouts to users, no pots — the stake is a
pledge, and the app tracks whether it was honored.

The product is verification credibility. These are people betting against
friends who will try to cheat, so anti-cheat and data provenance are core domain
logic, built and tested as such — not a later phase.

**Status: M2 complete.** Scaffold, CI, the social graph, and contests —
creation, invitations, and the participant state machine, with RLS. No
measurement ingest yet, so nothing is scored.

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

# 1. Secrets. Apple credentials are only needed once a client actually signs in
#    (M8); the stack starts without them and just warns.
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

One trap worth knowing before you write a comparison against `handle` or
`join_code`. Both are `citext`, and the citext `=` operator lives in the
`extensions` schema — so inside a function declared `search_path = ''` it is
invisible, and the comparison silently falls back to case-sensitive `text = text`.
Write `lower(col::text) = lower($1)`. The unique index is unaffected either way,
which is what makes the bug quiet: uniqueness stays case-insensitive while
lookups stop matching. See DECISIONS.md D14.

## The social graph

M1's tables. All five have RLS enabled and no `anon` access at all.

| Table           | Shape                                                        |
| --------------- | ------------------------------------------------------------ |
| `profiles`      | One row per onboarded user, keyed to `auth.users`. Its existence *is* the onboarding flag. |
| `friendships`   | One row per pair, canonically ordered `user_a < user_b`. `requested_by` carries direction. |
| `groups`        | Durable crews. Flat membership: no owner, no roles, no removing others. |
| `group_members` | Roster. Joining needs a code; leaving is a delete.           |
| `blocks`        | Directed. Readable only by the blocker.                      |

Three things are not reachable as table writes, because they cannot be expressed
as a row policy — RLS answers "may this caller read this row", not "does this
caller already know a secret":

```sql
select * from public.find_profile_by_handle('mikej');   -- exact match, never a search
select public.join_group_by_code('DEVCREW2');           -- idempotent, refuses across a block
select public.rotate_group_join_code('<group uuid>');   -- any member; the code is generated
```

Deliberate absences, each enforced by a withheld grant as well as a missing
policy (DECISIONS.md D21): no DELETE on `profiles` (accounts go through
`auth.users`), no DELETE on `groups` (the last member leaving reaps it), no
INSERT on `group_members` (that is `join_group_by_code`), and no UPDATE on
`groups.join_code` (that is `rotate_group_join_code`).

The seed builds a small graph — `@runner`, `@cyclist`, `@Lifter`, one accepted
friendship, one pending request, and a `Dev Crew` group whose join code is
`DEVCREW2` — plus M2's charities and one contest carrying three roster states at
once. To browse it as a particular user rather than as superuser:

```sql
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a1111111-1111-1111-1111-111111111111"}', true);
select * from public.profiles;   -- now filtered as @runner sees it
```

## Contests

M2's tables. All three have RLS enabled and no `anon` access.

| Table                  | Shape                                                        |
| ---------------------- | ------------------------------------------------------------ |
| `charities`            | Curated donation destinations. Read-only to clients; the list is maintained out of band. |
| `contests`             | The terms and the window. Frozen at creation, status forward-only, never deleted. |
| `contest_participants` | The roster and the invitation lifecycle in one table. Rows are never deleted. |

A duel is not a separate kind of contest — it is `max_participants = 2`, since
D4 already made a duel the N=2 case of the same structure. `group_id` is an
independent, optional scope that decides who may be invited (DECISIONS.md D22).

### The participant state machine

```
                              ┌──► accepted ──► withdrawn
                              │    needs a       pending only,
                              │    timezone      never the author
   (author) ──► accepted      │    and a
                              │    charity
   (invited) ─────────────────┼──► declined
                              │
                              └──► lapsed
                                   system only: activation or cancellation
```

The author is enrolled as `accepted` when the contest is created. Once the
contest leaves `pending` the roster is frozen — no new participants, and no
status, charity, or timezone changes at all. That freeze is what makes blocking
an opponent useless as a way out of a contest you are losing (D29), and it is
why `lapsed` is a status no client can write (D31).

### What is not reachable as a table write

Three things, for the same reason M1's join-by-code is a function: they are not
properties of a row.

```sql
-- Creation writes two tables atomically, and the author's roster row needs a
-- timezone and a charity, neither of which is a column on `contests`.
select public.create_contest(
  p_title => 'Step Duel', p_metric => 'steps', p_cadence => 'daily',
  p_target_value => 10000, p_stake_cents => 2500,
  p_starts_at => now() + interval '1 day',
  p_ends_at   => now() + interval '8 days',
  p_timezone => 'America/New_York', p_charity_id => '<charity uuid>',
  p_max_participants => 2);

-- Author only, pending only. Lapses every outstanding invitation.
select public.cancel_contest('<contest uuid>');

-- Cron's entry point: opens contests that have come due if two people accepted,
-- voids the rest. Not callable by `authenticated`, deliberately — see D32.
select app.activate_due_contests();
```

Inviting and answering *are* plain table writes, because both are row
properties and so can be expressed as policies:

```sql
-- Author only, while pending, to a friend or a co-member of the contest's
-- group, and never across a block in either direction.
insert into public.contest_participants (contest_id, user_id, invited_by)
values ('<contest uuid>', '<invitee uuid>', '<author uuid>');

-- Answering. The charity is required to accept and the timezone freezes here.
update public.contest_participants
set status = 'accepted', timezone = 'Europe/London', charity_id = '<charity uuid>'
where contest_id = '<contest uuid>';
```

Deliberate absences, each enforced by a withheld grant as well as a missing
policy (D21, D24): no INSERT, UPDATE, or DELETE on `charities`; no INSERT on
`contests` (that is `create_contest()`); no UPDATE on `contests` at all, because
the terms are frozen and the status is not the client's to move; and no DELETE on
either `contests` or `contest_participants`, because a contest that happened is
evidence and withdrawal is a status rather than an erasure.

One rule worth knowing before you write a fixture: a participant other than the
author cannot be inserted already `accepted`. They arrive as `invited` and
answer, which is what the seed does — see the two-step insert in `seed.sql`.

### Charities are empty in production, on purpose

`seed.sql` populates three openly fictional charities for local development:
invented names, `00-000000N` EINs, and `.test` hosts, which RFC 2606 reserves so
they cannot resolve. The production list is an owner action against verified EINs
and is deliberately *not* shipped as a data migration — a plausible but wrong EIN
routes a real donation to the wrong organisation and looks correct doing it. See
DECISIONS.md D26, which also records why an empty table is the right failure mode
until then.

## Test-harness capabilities

The harness proves out the three things later milestones depend on:

- **pgTAP** — schema shape, privileges, and that `app.forbid_mutation()`
  genuinely rejects UPDATE and DELETE. Append-only is the property the whole
  evidence ledger rests on, so it is asserted from the first commit.
  M1 adds RLS coverage, which works by impersonating a user inside the test
  transaction — `set local role authenticated` plus a `request.jwt.claims` GUC —
  because superuser bypasses policies entirely and a suite that forgets this
  asserts nothing. Assertions made after `reset role` see every row in the
  database, seed included, so scope them to their own fixtures.
  M2 adds lifecycle coverage, which needs one more trick: anything that happens
  on a schedule takes its clock as a parameter — `app.activate_due_contests(ts)`
  defaults to `now()` so cron can call it bare, and the suite passes a future
  timestamp instead. A scheduled job that cannot be tested without waiting for
  wall-clock time is a job that does not get tested.
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
- [x] **M1** — Schema and RLS for identity, friendships, groups
- [x] **M2** — Contest creation, invitations, participant state machine
- [ ] **M3** — HealthKit sync, attested ingest, `metric_snapshots`
- [ ] **M4** — Scoring engine with fixture tests, including fraudulent fixtures
- [ ] **M5** — Anti-cheat rules and integrity scoring
- [ ] **M6** — Geofence check-ins and workout-overlap validation
- [ ] **M7** — Settlement, disputes, charity pledge lifecycle, cron finalization
- [ ] **M8** — Minimal SwiftUI shell
