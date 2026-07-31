# GameTime

An iOS social accountability app. Friends stake charitable donations against
each other's personal goals. Normally each loser donates an agreed amount to a
charity the winner picked; a declared all-donate tie sends each accepted
participant's stake to their own nomination. No cash prizes, no payouts to
users, no pots — the stake is a pledge, and the app tracks whether it was
honored.

The product is verification credibility. These are people betting against
friends who will try to cheat, so anti-cheat and data provenance are core domain
logic, built and tested as such — not a later phase.

**Status:** The iOS product, friendship and challenge loop, manual steps sync, privacy-bounded standings, and safe retry foundations are implemented. GameTime is not yet a functional two-user alpha because the hosted lifecycle and physical two-device run remain open. [PLAN.md](PLAN.md) contains the one active path to that result.

The app does not collect or enforce real donations. Settlement, disputes, push notifications, background sensors, and production release work remain outside the functional-alpha scope. Historical milestone evidence is archived in [docs/archive/2026-07-30_IMPLEMENTATION_STATUS.md](docs/archive/2026-07-30_IMPLEMENTATION_STATUS.md).

## Repository layout

```
supabase/
  config.toml            Local stack configuration
  migrations/            Hand-written SQL. The only way schema changes.
  tests/                 pgTAP suites: schema, constraints, RLS
  functions/
    _shared/             App Attest, ingest, scoring, and integrity assessment
    _test/               Fixture builders and the scoring corpus. Never deployed.
    attest-device/       Registers one App Attest key per device install
    ingest-metrics/      The only route into the evidence ledger
    ingest-checkin/      Attested geofence/workout validation sidecar
    deno.json            Deno tasks, imports, lint and format config
  seed.sql               Local/CI seed data. Never required by a test.
ios/
  GameTimeCore/          Portable Swift package. No Apple frameworks.
                         Bucketing, provenance, check-in validation, metric
                         retry primitives, and a restorable exact-byte
                         check-in queue.
                         Builds and tests on Linux CI.
  GameTime/              M8 product app plus unit/UI targets. Live Supabase
                         adapters, Apple auth, social/challenge loop, and an
                         isolated Debug/Staging demo; Release contest mutation
                         is locked and fixture code is absent.
  GameTimeConformance/   Independent M6.5 App Attest smoke harness only.
scripts/
  dev-up.sh              Start the local stack
  db-test.sh             Reset the database and run pgTAP
  test-all.sh            Everything CI runs, in CI's order
  m6-5-configure-staging.sh  Pin and upload safe App Attest staging secrets
  m6-5-staging-fixture.sql   Repeatable staging contest/geofence fixture
docs/
  M6_5_DEVICE_CONFORMANCE.md  Physical-iPhone/staging release gate
  M8_1_STAGING_ACCEPTANCE.md  Two-user Apple-authenticated product proof
  archive/                Historical plans and audit evidence
DECISIONS.md             Every non-obvious choice and why
PLAN.md                  The one active path to a functional two-user alpha
```

## Prerequisites

| Tool         | Version tested | Notes                                       |
| ------------ | -------------- | ------------------------------------------- |
| Supabase CLI | 2.109.1        | `brew install supabase/tap/supabase`        |
| Docker       | 29.x           | Must be running before `dev-up.sh`          |
| PostgreSQL client | 17.x      | `psql` is required by database/staging scripts |
| Bash         | 5.x            | All repository scripts are Bash             |
| Deno         | 2.9.4          | `brew install deno`                         |
| Swift        | 6.2.3 / 6.3 CI | Xcode locally; standalone image in CI       |
| Xcode        | 26.2            | iOS 26.2 SDK; product and conformance targets deploy to iOS 18 |

## Setup

```bash
git clone <this repo> && cd GameTime

# 1. Secrets. Apple credentials are needed for device conformance and sign-in
#    work (M6.5/M8); the stack starts without them and just warns.
cp .env.example .env.local

# 2. Bring up Postgres, PostgREST, Auth, Storage, Studio.
./scripts/dev-up.sh

# 3. Reset the database from migrations and run the schema suite.
./scripts/db-test.sh
```

### Run the iOS product

The installed app carries its public Supabase URL and publishable mobile key;
there is no per-tester `.env` or xcconfig step. Open
`ios/GameTime/GameTime.xcodeproj`, select `GameTime-Staging`, choose a simulator
or provisioned device, and run. A signed archive or TestFlight build contains
the same configuration and can launch on every compatible device on which it
is installed. The app target fails its build before compilation if that public
configuration is missing, malformed, or paired with the wrong Apple bundle ID.

Testers should install one signed build (normally through TestFlight); they do
not clone the repository, edit configuration, or join the developer team.
The current product identity is `com.mjenkins.gametime.staging` on Apple team
`87Z29RTC26`. Developers compiling for a physical device need access to that
team; people installing an already signed build do not. Only the public
Supabase URL and `sb_publishable_…` key are compiled into the app. Apple private
keys, Supabase secret/service-role keys, and database credentials remain
server-side.

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
(cd supabase/functions && deno task fmt:check \
  && deno task lint && deno task check && deno task test) # Edge Functions
(cd ios/GameTimeCore && swift test)                       # Client core
```

CI has three portable jobs—pgTAP, Deno, and GameTimeCore—plus a `macos-26`
job that explicitly selects Xcode 26.2. The macOS job tests the product and
conformance schemes and builds both Staging and Release without signing.
`scripts/test-all.sh` remains the portable local/CI subset because Xcode is not
available on Linux.

## Working on the schema

Migrations are hand-written SQL files under `supabase/migrations/`, named
`YYYYMMDDHHMMSS_description.sql`. Nothing is changed through the Supabase
dashboard and the CLI's diff engine is not part of the workflow — the
constraints, triggers, and RLS policies in this schema carry intent that a
generated diff would strip.

```bash
# New migration
supabase migration new add_something

# Apply it, plus the seed, and run the suite
./scripts/db-test.sh
```

Two conventions the baseline migration sets up, both asserted by
`supabase/tests/000_harness.test.sql`:

- Ordinary relocatable extensions live in the `extensions` schema, never
  `public`. M7's non-relocatable `pg_cron` is the documented exception: it is
  registered in `pg_catalog` and owns a locked-down `cron` schema.
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
| `profiles`      | One durable actor row per onboarded user. Active rows have a private auth binding; deleted rows become non-discoverable tombstones. |
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
policy (DECISIONS.md D21 and D81): no DELETE on `profiles` (the service-only
`delete_account()` transaction tombstones the durable actor and then removes
authentication), no DELETE on `groups` (the last member leaving reaps it), no
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

The product calls the invitation flow a **challenge**; the stable database and
RPC vocabulary remains **contest**. A two-person challenge is
`max_participants = 2`, while multi-friend creation closes the roster at the
creator plus the selected invitees, up to the existing 20-person contest cap.
`group_id` is an independent, optional scope that decides who may be invited
(DECISIONS.md D22 and D89).

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
status, charity, or base-timezone changes at all. That freeze is what makes
blocking an opponent useless as a way out of a contest you are losing (D29),
and it is why `lapsed` is a status no client can write (D31).

A genuine relocation does not loosen that trigger or rewrite the base zone.
M5 records a separate request, one immutable vote from every other accepted
participant, and an applied change only after unanimous approval. The server
chooses the effective instant. Old buckets keep their old zone; future buckets
use the new one; an hour cut by the transition belongs to neither epoch.

### What is not reachable as a table write

Five things, for the same reason M1's join-by-code is a function: they are not
properties of a row.

```sql
-- Creation writes two tables atomically, and the author's roster row needs a
-- timezone and a charity, neither of which is a column on `contests`.
select public.create_contest(
  p_title => 'Step Challenge', p_metric => 'steps', p_cadence => 'daily',
  p_target_value => 10000, p_stake_cents => 2500,
  p_starts_at => now() + interval '1 day',
  p_ends_at   => now() + interval '8 days',
  p_timezone => 'America/New_York', p_charity_id => '<charity uuid>',
  p_max_participants => 2);

-- Author only, pending only. Lapses every outstanding invitation.
select public.cancel_contest('<contest uuid>');

-- Cron's entry point: opens contests that have come due if two people accepted,
-- cancels the rest before opening. Not callable by `authenticated`,
-- deliberately — see D32.
select app.activate_due_contests();

-- Active accepted participants may request a prospective relocation. Every
-- other accepted participant must consent; retries of the same vote are safe.
select public.request_timezone_change('<contest uuid>', 'Asia/Kathmandu');
select public.review_timezone_change('<request uuid>', true);
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

## Transactional notification outbox and activation

M7.2a adds `notification_intents`, an append-only ledger written by the same
transaction as its business transition. It stores only recipient, event type,
opaque entity ID, reminder stage, and server timestamps—never health totals,
location, receipts, integrity allegations, or dispute notes. Authenticated
users can read only their own intents while their profile is active;
`service_role` has read-only delivery access, and neither role can call the
trusted emitter. Delivery attempts, read state, APNs tokens, and presentation
remain M8 ledgers.

Invitations, contest activation/cancellation, account-deletion participation
changes, timezone-consent request/resolution, quarantine-review
request/approval, D76 escalation, and D76 terminal resolution emit semantic,
idempotent intents. Rejection is never mislabeled as resolution, and no intent
contains evidence values, integrity allegations, or an operator note.

The shared `pg_cron` registry contains named activation, raw-retention, and D76
deadline jobs. `gametime-activate-due-contests` and
`gametime-process-quarantine-review-deadlines` run every minute; raw retention
runs hourly. Application roles cannot use the `cron` schema. pgTAP proves each
registry entry and manually driven worker semantics. Only activation and
retention have the separately recorded hosted observations; this D76
implementation has not been deployed or observed against committed hosted rows.

## Provisional standings, final results, and obligations

M8.3c adds one service-only `publish_contest_standings_v1` boundary and one
accepted-participant `get_contest_standings_v1` read surface. The publisher
stores complete versioned snapshots. Final publication also freezes one
explicit `winner`, `all_donate`, `void`, or `inconclusive` result and creates
exactly one obligation per debtor in the same transaction: each loser points to
the winner's frozen charity, while every accepted participant in an
`all_donate` result points to their own nomination.

The read RPC never exposes the base ledgers directly. Provisional ordering is
live progress, not a predicted winner: the caller sees their own exact
integrity score, flags, and bounded rationale while rivals remain redacted.
Final rankings reveal the frozen inputs and attach an obligation only to the
row that owes it. Results, snapshots, entries, and obligations are append-only;
final publication waits for ingest grace, rejects unresolved quarantine, and
serializes against both metric and geofence writes. The product renders these
states in challenge detail with separate loading/error caches that clear on an
account transition.

This is still a dormant normal first-result foundation, not an enabled
winner/obligation finalizer. The local D76 timer can write only the fail-closed
`inconclusive:review_timeout` result from a matching frozen assessment and
creates no obligation. No hosted caller invokes the trusted publisher.
Operated adjudicator authorization/queues, disputes, actionability, settlement,
M6.5, deployment, and staging gates still apply.

## Durable account deletion and raw-evidence retention

The reconciled D81 migration separates authentication lifetime from
contest identity. A service-only `delete_account(uuid)` transaction resolves
pending participation, creates any still-needed workflow capability, removes
social state, revokes device registrations, replaces the profile with a random
non-discoverable tombstone, and finally removes the Auth principal. Accepted
active-contest rosters and immutable audit facts keep the stable actor UUID.
Direct Auth deletion and UUID reuse are refused, and every authenticated table
policy and actor RPC rechecks the active profile so an unexpired JWT cannot act
after the tombstone commits.

The launch policy `raw-evidence-retention-v1` removes exact location samples
after 30 days and raw metric/source, device-registration, and opaque App Attest
receipt material after 90 days. Contest-scoped material waits for persisted
workflow finality; scoped holds and operator cutoffs delay pruning. The hourly
`gametime-prune-raw-evidence` job is the only deletion authority: it records an
immutable digest-only retention event, never removes an active device
registration, and preserves rosters, ingest audit facts, quarantines, accepted
check-ins, and key fingerprints. Result-, obligation-, dispute-, and
donation-receipt tables will attach their child scopes to this foundation as
those M7 slices land.

This is backend infrastructure, not an end-to-end account-deletion feature yet.
There is no reauthentication/confirmation flow, user-facing service endpoint,
one-time capability handoff and recovery path, or client capability API. The
D81 migrations and the forward generated-column repair are deployed to staging.
A committed synthetic lineage passed both a manual retention cycle and the
hourly hosted job, including source-ID scrubbing, generated-range
recomputation, exact-location pruning, immutable audit events, and idempotency.
CI, concurrency, production-shaped staging-copy timing, hosted advisors, and
hold/failure recovery still gate production deployment.

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
| `evidence_quarantines` | Review-required retroactive observations. Never rewrites the ledger. |
| `evidence_quarantine_reviews` | Append-only opponent votes on a quarantine. |

**There is no client write path into the evidence ledger.** `authenticated`
holds `SELECT` on its three underlying relations and nothing else. A row appears
only through `public.record_metric_batch()`, which `service_role` alone may
execute, because
the thing that authorises the write is a signature over the request body and RLS
cannot check a signature.

### A bucket is a local hour

`bucket_start` is aligned to a whole hour **in the participant's applicable
timezone epoch**, not in UTC, and the two are not interchangeable. The first
epoch is the zone frozen at acceptance; later epochs require unanimous opponent
approval. India is +05:30,
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

The current M8 explicit-steps adapter is a deliberately narrower bridge into
that general ledger. Raw samples establish the allowed Apple source revisions
and devices, while `HKStatisticsCollectionQuery` produces HealthKit's merged
Apple-device total for each completed local hour. That prevents overlapping
iPhone and Apple Watch records from being treated as disjoint contributions.
The adapter sends one `device` row and does not claim manual, unknown, or
third-party values. Adding those sources later requires a reviewed reconciled
payload model; summing them into the merged device total would be incorrect.

M5 reads the same metadata through `contest_evidence_sources`, a
`security_invoker` sidecar view that selects the current admissible contribution
for each provenance without changing `contest_evidence`. The `m5-v3` integrity
configuration carries a reviewed bundle-identifier allow-list and separate,
tunable penalties for an unrecognized, missing, or malformed third-party
identifier. Device provenance is not subject to that rule. Every third-party row
still counts toward the target; reputation can only raise
`third_party_source_reputation` flags and lower the bounded integrity score used
by a declared tie-break.

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
| Whether a *particular* app is trustworthy        | not refused; M5 integrity-score sidecar |

The split is DECISIONS.md D6's: crypto in TypeScript, invariants in SQL. The
counter is the sharpest example — it is checked in SQL specifically because the
check has to be atomic with consuming it, and in application code it is a read
followed by a write that two copies of a captured request would both pass.

## Attested ingest

Four routes across three Edge Functions, all `POST`, all requiring a signed-in
caller.

```
POST /functions/v1/attest-device/challenge   -> { challenge, expiresInSeconds }
POST /functions/v1/attest-device             { keyId, attestation }
                                               -> { registered, environment,
                                                    validationCategory?,
                                                    bundleVersion? }
POST /functions/v1/ingest-metrics            { contestId, clientBatchId,
                                               observedAt, observations[] }
POST /functions/v1/ingest-checkin             { contestId, geofenceId,
                                               clientCheckinId, locations[],
                                               workout? }
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
| `APPLE_BUNDLE_ID`              | Primary reviewed bundle ID. The guarded staging uploader requires `com.gametime.conformance`; check-in verification remains bound to this identity. |
| `APPLE_ADDITIONAL_BUNDLE_IDS`  | Optional comma-separated product identities for App Attest registration and metric assertions in local, test, or staging only. Strictly unique, at most three, and rejected in production. |
| `APP_ATTEST_ROOT_CA_PEM`       | Apple's App Attest root. **Required**; the functions refuse to start without it. |
| `APP_ATTEST_RECEIPT_ROOT_CA_PEM` | Apple's Root CA G3 for independent PKCS#7 receipt verification. **Required** by `attest-device`. |
| `APP_ATTEST_ALLOW_DEVELOPMENT` | Accept development-environment attestations. Defaults on in local and test, refused outright in production. |
| `ATTEST_DEV_BYPASS`            | Accept an unattested batch or check-in. Same refusal in staging and production (D11). |
| `GAMETIME_ENV`                 | `local`, `test`, `staging`, or `production`. Required in hosted functions; the app-owned name avoids Supabase's reserved secret prefix. |
| `GAMETIME_ATTEST_CHALLENGE_SECRET` | Dedicated 32+ character HMAC key. Required in staging and production. |
| `SUPABASE_JWKS`                | Hosted Supabase injects the project's asymmetric signing keys; all three handlers verify the signature, project issuer, and authenticated audience in code. |
| `SUPABASE_SECRET_KEYS`         | Hosted Supabase injects named opaque admin keys. The default key reaches only guarded RPCs and is never put in an Authorization header. |

Apple's current App Attestation Root CA and Root CA G3 are fetched from the
[direct Apple PEM](https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem),
and [direct Apple DER](https://www.apple.com/certificateauthority/AppleRootCA-G3.cer),
checked against their recorded SHA-256 fingerprints, and uploaded by
`scripts/m6-5-configure-staging.sh`. Both staging scripts refuse to run until
the reviewed project ref is present in `supabase/staging-project-ref`; the
fixture wrapper also matches that identity against the database URL host. See
[`docs/M6_5_DEVICE_CONFORMANCE.md`](docs/M6_5_DEVICE_CONFORMANCE.md) for the
complete staging and real-iPhone procedure.

A batch or check-in accepted under `ATTEST_DEV_BYPASS` is marked
`attested = false`, permanently. These are real audit queries, and both should
return zero outside local development:

```sql
select count(*) from public.ingest_batches where not attested;
select count(*) from public.geofence_checkins where not attested;
```

## Geofence check-ins

`POST /functions/v1/ingest-checkin` is the M6 sidecar ingestion path. It uses the
same JWT ownership, App Attest key, exact-body signature, monotonic counter, and
stable client-id retry contract as metric ingest. The signed JSON contains an
explicit contest and geofence id, 2–256 raw Core Location observations, and one
workout interval:

- Every location carries an absolute RFC 3339 instant, latitude, longitude,
  horizontal accuracy, and Core Location's simulation/accessory signals.
- The workout carries an absolute half-open interval, activity type, HealthKit
  provenance, and optional source bundle id.
- `clientCheckInId` and the exact signed body bytes stay unchanged across a
  retry. An identical replay returns the first result; the same id with different
  bytes is refused.

The portable queue exposes a codable pending-request value and a validating
restore initializer, so an app relaunch preserves the exact bytes and retry id.
At capacity it refuses the new request visibly; it never evicts an older
Core Location claim that cannot be reconstructed later.

The client never declares that it was inside. `contest_geofences` is a
service-provisioned definition that must be inserted before activation and is
immutable thereafter. It contains the center, radius, accuracy ceiling, minimum
dwell, maximum sample gap, and minimum workout overlap.
`record_geofence_checkin()` orders the absolute instants, computes a Haversine
distance for each raw observation, and records one explicit sample
classification: `inside`, `outside`, `low_accuracy`, or `simulated`.

Credited dwell is the sum of adjacent `inside -> inside` intervals no longer
than the configured sample gap. Workout overlap is the intersection of the
workout with those credited intervals—not with the first-to-last visit envelope.
Both calculations are timezone-independent and use half-open ranges, so touching
endpoints do not overlap.

Every well-formed attempt that reaches Postgres is append-only, including failed
validation. Its primary outcome records whether it was accepted, outside the
contest window, future-dated, simulated, inaccurate, outside the fence, short on
dwell or workout overlap, backed by an untrusted workout, or conflicting with
already accepted visit/workout evidence. Only accepted attempts reserve time:
partial GiST exclusions prevent one user from accepting overlapping check-in or
workout ranges, and a partial unique index prevents accepting the same workout
id twice. A failed attempt therefore remains auditable without blocking a
corrected retry.

Check-ins never mutate `metric_snapshots`, `contest_evidence`, qualification, or
totals. `contest_checkin_integrity` feeds the versioned M6 integrity flags, while
`contest_location_observations` exposes only inside samples from accepted,
attested attempts to the existing impossible-travel rule. Neither timezone nor
HealthKit totals is treated as a location.

Exact coordinates are owner-only under RLS and remain available to the
service-role integrity assessor. Accepted active or finalized rivals can audit
the immutable geofence terms and derived check-in outcomes, but cannot inspect
another participant's raw, failed, or trusted coordinate rows.

## Scoring

`supabase/functions/_shared/scoring.ts` is the only implementation of who won
(DECISIONS.md D3). It is a pure function — contest terms, the accepted roster,
and the rows of `contest_evidence` in; standings and an outcome out. No I/O, no
clock, no randomness, so the same frozen input always gives the same answer. M7
persists the result and configuration versions before later retention may prune
raw evidence.

**A contest is pass/fail against its own terms, and the comparison is among those
who passed.** Highest score does not win. This is what the cadence enum already
says: `cumulative` means reach the target once across the window, `daily` means
reach it on every day. So:

| Qualifiers | Outcome |
| --- | --- |
| exactly one | that participant wins |
| several | a tie, resolved by `contests.tie_break` |
| none | void — nobody donates |

The case that settles it: two friends each pledge $25 against a 100,000-step
month and walk 40,000 and 12,000. Under "highest total wins" somebody who missed
their goal by 60% collects a donation for a month in which neither of them did
the thing they staked money on. See D51.

That makes **ties the ordinary result**, not an edge case — which is why
`tie_break` is declared at creation and defaults to `integrity_score`.

### Daily cadence rates days, it does not count them

A daily contest asks about the local days each timezone epoch *wholly* covers,
starting with the participant's frozen base zone, and ranks on
`qualifyingDays / scoreableDays`.

A window that is seven whole days in New York is six whole days plus two
part-days in Kathmandu (+05:45). Ranking on the raw count would cap the Kathmandu
participant at 6 against the New Yorker's 7 and make them unable to win a contest
they played perfectly. Rating makes them comparable: 6/6 and 7/7 are both 1.0.

Part-days are dropped from the numerator *and* the denominator — an 18-hour day
cannot be judged against a whole-day target. That also closes an attack the
ledger cannot: evidence in a part-day is legitimately writable, so otherwise
somebody who missed a Wednesday could stuff the edge day and manufacture a
qualifying day out of an hour that was never a day. See D52.

Every scoring call must supply the complete applied timezone-change ledger,
including an explicit empty array when there are no changes. Omitting it raises
instead of silently reverting a relocated participant to the base zone.

### Totals are integers underneath

Every value is `numeric(12, 2)`, so scoring converts to whole hundredths and sums
as integers. `28.45 + 1.24 + 0.20 + 0.11` is `29.999999999999996` in doubles, so
a participant logging exactly 30.00 minutes against a 30-minute target fails a
float comparison — and that comparison is the qualification test. See D53.

### An unresolvable tie is reported, not guessed

The bare M4 engine still reports `integrity_score_unavailable` when it is called
without scores. M5's `scoreContestWithIntegrity()` computes a complete score map
for every accepted participant and supplies it through the engine's existing
optional input. A unique highest score wins; equal scores remain explicitly
`tie_break_inconclusive`.

Every alternative is worse: falling back to the higher total substitutes a
tie-break the participants did not agree to, voiding cancels a contest somebody
won, and ordering by user id settles a donation by whose UUID sorts lower.
Standings *are* fully ordered — a leaderboard has to render — but ordering never
decides the outcome. See D54.

### The engine scores; it does not flag

90,000 steps in one hour scores as 90,000, and a bucket first reported eleven days
late scores too. Plausibility needs a tuning parameter, which makes it a heuristic,
which puts it in M5 (D6). The engine carries the aggregates M5 reads — bucket and
sample counts, the largest single hour, the worst reporting lag — rather than
acting on them. Both cases are fixtures that must *pass*, so nobody mistakes the
engine's silence for a verdict. See D55.

The one thing it refuses is a ledger that contradicts itself: a bucket carrying
two different `local_day` values raises rather than picking one.

### The corpus is the specification

`supabase/functions/_test/scoring_fixtures.ts` holds every case as plain data —
no functions, no classes. If optimistic offline standings ever force a second
engine in Swift, the two have to be held to one corpus, and a test asserts the
fixtures survive a JSON round trip so they cannot quietly stop being portable
(D3's escape hatch).

Each fixture carries a `why` explaining what it pins, so changing an expectation
means saying which property is being given up. The fraudulent cases come in two
kinds, and the split is the point: cross-metric padding, out-of-window backfill
and part-day stuffing must **not** work; an implausible hour and an eleven-day-late
report must work, and be visible in the summary.

The corpus also crosses the date line: the same civil date can be one whole day
in each of two timezone epochs, and those days must never be merged.

## Integrity assessment

`supabase/functions/_shared/integrity.ts` is a pure sidecar to the M4 engine. Its
configuration has a version, per-metric hourly ceilings, corroboration rules,
reviewed third-party bundle identifiers and reputation tiers, timezone-change
penalties, geofence/workout validation penalties, travel distance/speed limits,
lag and quarantine thresholds, severity, points per flag, and per-rule penalty
caps. The current configuration is `m6-v1`; the exact `m5-v2` and `m5-v3`
configurations remain loadable for reproducible historical assessment. The
default score starts at 100 and floors at 0, but those are configuration too.

The assessor emits explicit flags:

| Flag | Signal |
| --- | --- |
| `plausibility_ceiling` | One hourly metric exceeds its configured ceiling. |
| `cross_metric_corroboration` | A large contest-metric hour has none of its configured companion signals. |
| `third_party_source_reputation` | An admissible third-party contribution has an unrecognized, missing, or malformed bundle identifier. |
| `timezone_change` | An opponent-approved prospective timezone epoch was applied. |
| `geofence_checkin_failure` | An attested check-in failed a location, contest-window, dwell, or visit-overlap validation. |
| `workout_overlap_validation` | A check-in failed workout trust, temporal overlap, reuse, or workout-range overlap validation. |
| `impossible_travel` | Two trusted location observations require travel above the configured speed after subtracting both accuracy radii. |
| `reporting_lag` | An hour arrived materially after it closed. |
| `retroactive_evidence_quarantine` | The lag crosses the review-required threshold. |

Impossible travel takes explicit location observations; hourly HealthKit totals
and timezone changes do not contain a location, and the code does not pretend
otherwise. M6's accepted, attested geofence locations are the concrete producer.

Flags never alter totals or qualification. A retroactive quarantine is durable
review state beside the snapshot: the generated `is_admissible` value stays the
same and `contest_evidence` still returns the value. In a duel, the opponent must
approve; in a group, a strict majority of the other accepted participants must.
Silence stays `pending`. M7 must block a settlement-bearing result until a
complete integrity assessment exists and every quarantine is approved or
explicitly cleared. Pending review and rejection without clearance follow D76's
bounded escalation path to `inconclusive`; neither quietly applies a second
evidence filter.

D76 stores one immutable 72-hour peer-review deadline no earlier than
ingest-grace close. A rejection escalates immediately; unanswered peer review
escalates at the inclusive boundary. Adjudication gets one bounded seven-day
deadline anchored no earlier than grace close. Only the service mutation
boundary can record explicit clearance, using an idempotency key. If no
clearance wins before the deadline, the named worker appends `review_timeout`,
reuses the frozen assessment standings, finalizes only as `inconclusive`, and
creates no donation obligation. The peer vote, escalation, terminal event, and
payload-free intents remain append-only through participant tombstoning.

Raw `ingest_batches`, `metric_snapshots`, and `evidence_quarantines` are readable
only by their subject; quarantine vote rows are readable only by the reviewer
who cast them. Accepted rivals use `list_contest_quarantine_reviews(contest_id)`
and `get_quarantine_revision_history(quarantine_id)`, which bind authorization
to the evidence row's own contest, disclose only a pending claim that caller
still must judge, and omit device/source identifiers, attestation material,
arbitrary details, signal keys, and reviewer identities. The subject gets
aggregate review state through `list_my_evidence_quarantines(contest_id)`.

Timezone consent is deliberately stricter than quarantine review because it
changes the scoring contract rather than judging one claim: every other accepted
participant must approve. Scoring computes whole days separately inside each
approved epoch, and both the server and client drop transition-cut hours.

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
  M6 adds exact geofence boundaries, capped dwell gaps, half-open workout
  intersections, attested retries/counter replay, overlapping accepted ranges,
  append-only evidence, and owner/rival/unrelated RLS coverage.
- **Deno** — Edge Function logic, tested by importing handlers directly rather
  than booting the runtime container. M3's suites mint their own P-256 keys and
  their own Apple-shaped certificate chain, so every rejection path in the
  attestation and assertion code runs against real cryptography rather than a
  stub. What that cannot establish is *conformance* — it proves the verifier
  agrees with the test's signer, not that either agrees with an iPhone. See the
  owner action in DECISIONS.md D46.
  M4 adds a different shape again: the scoring engine is pure, so its suite is a
  data-driven corpus rather than a set of hand-written cases. The harness is
  deliberately thin — it asserts only what each fixture declares — so behaviour
  changes surface as changed expectations in the corpus, next to the `why` that
  says what property is being traded away.
  M6 exercises the check-in handler with real assertion cryptography, malformed
  and spoofed locations, stable retries, database-error mapping, and a portable
  data fixture for the new versioned integrity flags.
- **Swift Testing** — portable client logic under Swift 6 strict concurrency.
  M3's suites cover the cases a UTC-hour implementation gets wrong: half-hour and
  45-minute zone offsets, and both daylight-saving transitions, where a local day
  is 23 or 25 hours long. M6 mirrors the server's advisory Haversine
  classification, adjacent-segment dwell, and workout intersection, then proves
  the queue reuses a stable request id and the exact body bytes that were signed.

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
- **Deno format checks require LF line endings.** A Windows checkout with
  `core.autocrlf=true` can make `deno fmt --check` report otherwise unchanged
  TypeScript files as unformatted. Use an LF checkout (or WSL) before judging
  the source from that result.

## Client targets

iOS 18.0, Swift 6 language mode. The portable package remains Apple-framework
free and Linux-testable. `ios/GameTime` is the production-shaped app;
`ios/GameTimeConformance` remains the focused App Attest harness. Both build and
test under the explicit Xcode 26.2 macOS job. The target rationale and M8
boundaries are in DECISIONS.md D2, D10, and D83–D86.

## Milestones

This is the ledger of what is built. What comes next, the remaining
implementation gates, and work not yet reflected here are in PLAN.md.

- [x] **M0** — Scaffold, local Supabase, migration and test harness, CI
- [x] **M1** — Schema and RLS for identity, friendships, groups
- [x] **M2** — Contest creation, invitations, participant state machine
- [x] **M3** — Portable HealthKit bucketing/provenance/queue core, attested
      ingest, and `metric_snapshots` (live HealthKit queries land in M8)
- [x] **M4** — Scoring engine with fixture tests, including fraudulent fixtures
- [x] **M5** — Anti-cheat rules, integrity scoring, evidence review, source
      reputation, and opponent-approved timezone changes
- [x] **M6** — Geofence check-ins, workout-overlap validation, trusted-location
      integrity inputs, and a restorable exact-byte client queue
- [ ] **M6.5** — Real-device App Attest conformance against staging
- [x] **M7.1** — Settlement/finalization product contract (D74–D82; decisions
      only)
- [x] **M7.2a** — Payload-free notification outbox, transition emitters, and a
      named one-minute contest-activation job
- [x] **M7 / D81 foundation** — Durable actor tombstones, atomic
      service-only account deletion, stale-JWT denial, scoped continuation
      capabilities, and guarded versioned raw-evidence retention; local
      869-assertion/lint gates and committed staging retention cycles
      pass, while broader concurrency/production-shaped migration and
      hosted-advisor gates remain
- [x] **M7 / D77 evidence boundary** — Owner-only metric/quarantine audit
      relations plus exact-contest, phase-aware, redacted quarantine-review
      surfaces
- [x] **M7 first-result foundation** — Append-only provisional/final snapshots,
      explicit first results, service-only grace/roster/quarantine-gated
      publication, accepted-participant redacted reads, and exact per-debtor
      obligations; no hosted finalizer is enabled
- [x] **M7 / D76 deadline foundation** — Immutable grace-anchored peer and
      adjudication deadlines, immediate rejection escalation, idempotent
      service-only clearance, named local worker, payload-free transition
      intents, and fail-closed `inconclusive:review_timeout`; operated
      adjudicator authorization and hosted acceptance remain open
- [ ] **M7.2b** — Observe hosted cron activation and run ingest, timezone, and
      check-in flows against the scheduler-opened contest
- [ ] **M7 remainder** — Operated adjudicator/finalizer authorization and
      queues, actionable settlement, disputes, charity pledge lifecycle,
      reliability, and remaining deadline/retention operations
- [ ] **M8** — Product iOS program remains in progress
  - [x] **M8.1 repository slice** — Product target, native Apple-auth exchange,
        onboarding, exact-handle friendships, atomic challenge
        creation/invitation/acceptance, four-tab navigation, fixtures, and
        green PR #11 product/conformance Xcode CI; a signed iPhone
        install/auth/profile-reload observation now passes, while the
        Apple-name prefill and two-user staging proof remain open
  - [x] **M8.2a pending challenge durability** — Versioned, per-actor protected
        storage preserves canonical immutable terms and the request UUID before
        an attempt; ambiguous responses survive relaunch for explicit
        same-request retry, while corruption, changed records, account
        transitions, and a second request fail closed
  - [x] **M8.3a challenge creation** — Explicitly select 1–19 accepted friends,
        review the complete closed roster, and submit one canonical
        `create_contest_with_invites_v1` request; version-2 persistence migrates
        version-1 single-invite saved-duel records without changing their
        request identity or timestamps
  - [x] **M8.3c M7-backed standings** — Challenge detail distinguishes
        provisional progress from frozen final rankings, preserves rival
        integrity redaction until final, displays explicit result rationale,
        and shows only the participant's own loser/all-donate obligation
  - [x] **M8.3d on-device demo** — Debug and Staging can isolate a local fixture
        model from the retained live session, search `david1` or `david2`,
        instantly accept the synthetic request for one-tester challenge
        creation, and discard all demo state on exit; Release excludes it
  - [x] **M8 explicit Apple-device steps slice** — Staging exposes
        user-initiated HealthKit authorization and sync for active accepted
        steps challenges, uses HealthKit's merged phone/watch statistics for
        completed frozen-local-hour buckets, reports confirmed totals, and
        persists account-isolated exact metric/App Attest bytes for explicit
        retry; physical two-account and hosted-verifier acceptance remain open
  - [ ] **Later M8** — Background HealthKit delivery, Core Location/workouts,
        product App Attest lifecycle hardening, durable inbox/APNs, evidence
        persistence, M7 review/actionable
        settlement/dispute screens, accessibility hardening, and privacy/App
        Store work
