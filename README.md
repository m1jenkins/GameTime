# GameTime

An iOS social accountability app. Friends stake charitable donations against
each other's personal goals; the loser donates an agreed amount to a charity the
winner picks. No cash prizes, no payouts to users, no pots — the stake is a
pledge, and the app tracks whether it was honored.

The product is verification credibility. These are people betting against
friends who will try to cheat, so anti-cheat and data provenance are core domain
logic, built and tested as such — not a later phase.

**Status: M3 complete.** Scaffold, CI, the social graph, contests, and the
evidence ledger — attested ingest of hourly HealthKit measurements with their
provenance. Nothing is scored yet; M4 is the scoring engine.

---

## Repository layout

```
supabase/
  config.toml            Local stack configuration
  migrations/            Hand-written SQL. The only way schema changes.
  tests/                 pgTAP suites: schema, constraints, RLS
  functions/
    _shared/             App Attest, CBOR, ingest plumbing. Scoring lands in M4.
    _test/               Fixture builders. Never imported by a deployed function.
    attest-device/       Registers one App Attest key per device install
    ingest-metrics/      The only route into the evidence ledger
    deno.json            Deno tasks, imports, lint and format config
  seed.sql               Local/CI seed data. Never required by a test.
ios/
  GameTimeCore/          Portable Swift package. No Apple frameworks.
                         Bucketing, provenance, and the offline ingest queue.
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

## The evidence ledger

M3's tables. This is the first schema in the repo that records a claim about the
physical world, which is the only kind of row anyone has a financial motive to
falsify.

| Table                 | Shape                                                        |
| --------------------- | ------------------------------------------------------------ |
| `device_attestations` | One App Attest key per device install, with its replay counter. |
| `ingest_batches`      | One row per accepted ingest request: the idempotency key and the attestation audit trail. |
| `metric_snapshots`    | The ledger. One row per observation of one hour of one metric from one source. |
| `contest_evidence`    | A view: the current admissible figure per bucket. What M4 scores. |

**There is no client write path.** `authenticated` holds `SELECT` on all three
tables and nothing else. A row appears only through
`public.record_metric_batch()`, which `service_role` alone may execute, because
the thing that authorises the write is a signature over the request body and RLS
cannot check a signature.

### A bucket is a local hour

`bucket_start` is aligned to a whole hour **in the participant's frozen
timezone**, not in UTC, and the two are not interchangeable. India is +05:30,
Nepal +05:45, Chatham +13:45 — so a UTC-aligned hour straddles the local day
boundary for a large fraction of the world, and a daily-cadence goal would credit
part of Tuesday to Monday for exactly those participants, silently. See
DECISIONS.md D36.

The server stamps `local_day` and `local_hour` from that zone at insert. A client
never supplies them; whatever it sends is overwritten.

### A revision appends

HealthKit's figure for an hour grows as a watch syncs late or a workout is written
after the fact, so there is deliberately **no** unique constraint across
`(contest_id, user_id, metric, bucket_start)`. Reading it back has two steps, and
`contest_evidence` is the only place that should do it:

- within one source, the revisions are a monotone series, so the current figure is
  the **largest**;
- across sources, the contributions are disjoint, so they **add**.

Getting that backwards in either direction is a scoring bug: summing revisions
counts a late sync twice, and taking the max across sources discards everything
but the largest app.

### Provenance, and what counts

```
device       first-party Apple hardware, not user-entered      admissible
third_party  another app wrote it to HealthKit                 admissible
manual       typed into the Health app                         never
unknown      no usable provenance metadata at all              never
```

An inadmissible observation is **stored, not refused**. The client reports what
HealthKit told it and the server decides what counts, because a client that
filters its own evidence is a client whose silence you have to trust. `manual` and
`unknown` are excluded by a generated column, so no code path can store a row
whose admissibility disagrees with its provenance.

Provenance is part of the ledger's key, which is what stops one stray hand-typed
step from voiding an hour that also holds five thousand genuine ones.

### What is refused, and where

| Rule                                             | Enforced by |
| ------------------------------------------------ | ----------- |
| The signature covers this exact payload          | `_shared/appattest.ts` |
| The chain reaches Apple's root                   | `_shared/appattest.ts` |
| The assertion counter has advanced               | SQL, under a row lock |
| The batch is not a replay                        | SQL, before the counter is spent |
| The bucket is inside the contest window          | SQL |
| The bucket's hour has finished                   | SQL |
| The bucket is aligned to the participant's hour  | SQL |
| A figure is not revised downward                 | SQL |
| Nothing rewrites the ledger                      | SQL |
| Whether a *particular* app is trustworthy        | nobody yet — M5 |

The split is DECISIONS.md D6's: crypto in TypeScript, invariants in SQL. The
counter is the sharpest example — it is checked in SQL specifically because the
check has to be atomic with consuming it, and in application code it is a read
followed by a write that two copies of a captured request would both pass.

## Attested ingest

Two endpoints, both `POST`, both requiring a signed-in caller.

```
POST /functions/v1/attest-device/challenge   -> { challenge, expiresInSeconds }
POST /functions/v1/attest-device             { keyId, attestation }
POST /functions/v1/ingest-metrics            { contestId, clientBatchId,
                                               observedAt, observations[] }
```

`ingest-metrics` carries its credentials as **headers**, not fields:

```
x-gametime-key-id:     <base64 of Apple's key id>
x-gametime-assertion:  <base64 of the CBOR assertion>
```

because an assertion cannot be a field of the document it signs. The body is
exactly the bytes the assertion covers; it is read once and hashed before
anything parses it, since JSON has many encodings of one value and hashing a
re-serialised body would hash a different document than the client signed.

`clientBatchId` is the idempotency key and it must be **stable across retries**.
`record_metric_batch()` checks it before it consumes an assertion counter, so a
request that timed out after the server committed comes back as
`{ replayed: true }` rather than an error. A reused id with a different payload is
refused, because silently returning the first result would drop the second
batch's evidence.

### Configuration

| Variable                       | Notes |
| ------------------------------ | ----- |
| `APPLE_TEAM_ID`                | Ten alphanumerics. With the bundle id this is the App ID Apple binds attestations to. |
| `APPLE_BUNDLE_ID`              | |
| `APP_ATTEST_ROOT_CA_PEM`       | Apple's App Attest root. **Required**; the functions refuse to start without it. |
| `APP_ATTEST_ALLOW_DEVELOPMENT` | Accept development-environment attestations. Defaults on in local and test, refused outright in production. |
| `ATTEST_DEV_BYPASS`            | Accept an unattested batch. Same refusal in staging and production (D11). |
| `SUPABASE_JWT_SECRET`          | Both endpoints verify the caller's JWT in code as well as at the gateway. |

> **Before launch:** `APP_ATTEST_ROOT_CA_PEM` needs Apple's actual root
> certificate, from https://www.apple.com/certificateauthority/. It is
> configuration rather than a constant in the source on purpose — a pinned root
> that is plausible and wrong either rejects every attestation or accepts a chain
> Apple never issued, and those bytes should be fetched rather than recalled. See
> DECISIONS.md D46, which also records the two Apple-format details that need
> confirming against a real device.

A batch accepted under `ATTEST_DEV_BYPASS` is marked `attested = false` on
`ingest_batches`, permanently. So this is a real audit query, and it should
return zero:

```sql
select count(*) from public.ingest_batches where not attested;
```

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
  M3 adds one more, and it is the least obvious: a suite that needs a *live*
  contest has to build the row directly with `contests_assert_future_window`
  turned off, because `create_contest()` refuses a window that opens in the past
  (D25) and a contest starting in the future has no finished hour to report into.
  That is scaffolding rather than a hole — `060_contests.test.sql` is what proves
  the trigger works — but a suite that quietly skipped it would be asserting
  against an empty ledger.
- **Deno** — Edge Function logic, tested by importing handlers directly rather
  than booting the runtime container. M3's suites mint their own P-256 keys and
  their own Apple-shaped certificate chain, so every rejection path in the
  attestation and assertion code runs against real cryptography rather than a
  stub. What that cannot establish is *conformance* — it proves the verifier
  agrees with the test's signer, not that either agrees with an iPhone. See the
  owner action in DECISIONS.md D46.
- **Swift Testing** — portable client logic under Swift 6 strict concurrency.
  M3's suites cover the cases a UTC-hour implementation gets wrong: half-hour and
  45-minute zone offsets, and both daylight-saving transitions, where a local day
  is 23 or 25 hours long.

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
- [x] **M3** — HealthKit sync, attested ingest, `metric_snapshots`
- [ ] **M4** — Scoring engine with fixture tests, including fraudulent fixtures
- [ ] **M5** — Anti-cheat rules and integrity scoring
- [ ] **M6** — Geofence check-ins and workout-overlap validation
- [ ] **M7** — Settlement, disputes, charity pledge lifecycle, cron finalization
- [ ] **M8** — Minimal SwiftUI shell
