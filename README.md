# GameTime

GameTime V1 is a personal accountability app. One person commits to a seven-day
steps goal, chooses a daily or cumulative cadence, selects a $10, $20, $30,
$40, or $50 test commitment, and chooses the day and hour the seven days open.
Stage A is structurally `test_only`: no client or server creation interface can
request a live fee, and no money is charged.

The product is verification credibility. HealthKit reads, App Attest-backed
uploads, explicit completed-hour coverage, frozen terms, and fail-closed results
are core domain logic rather than a later anti-cheat layer.

## What works right now

Run the `GameTime` scheme (Debug) on a **physical iPhone** against the local
stack and you can sign in, create a seven-day steps challenge with a test
commitment, and watch real HealthKit steps accumulate.

| Path | State |
| --- | --- |
| Sign in with Apple → onboarding → create challenge | Works, Debug + local stack |
| Choosing the start day and hour | Works, all configurations; deployed to Staging |
| HealthKit step reads | Works, Debug and Staging, physical device |
| Live step total on an active challenge | Works, labelled **not yet verified** |
| App Attest-signed upload and server-scored progress | Staging only; endpoints deployed, not yet exercised from a device |
| Hosted Staging backend | Personal V1 schema and all six Edge Functions deployed |
| Real fees | Blocked behind every Stage B gate in [PLAN.md](PLAN.md) |

**Two capabilities, gated separately.** `activitySyncEnabled` (Debug +
Staging) governs whether GameTime reads HealthKit. `attestedUploadEnabled`
(Staging only) governs whether it can sign that read and deliver it. Reading
Health and proving that read to a server are different things; fusing them
previously made the product unreachable until the entire stack was live.

Creating a challenge therefore requires a **local** step read that sees
first-party device steps — not a successful App Attest round-trip. The server
still refuses untrusted evidence when it scores, so no domain invariant moved.

### When the seven days open

The default is the next local midnight, and choosing it sends *no* start to the
server, so that default is resolved when the request commits rather than when
the form was filled in — a draft written before midnight and confirmed after it
must not ask for a start that has already passed.

A chosen start is any future whole local **hour** within 90 days, today
included. Whole hours are not a cosmetic restriction: `bucket_start` is a whole
local hour, and the server discards the partial hour a 15:40 start would open,
so the evidence for those twenty minutes could never be delivered and the
window would begin with a silently unscorable gap. On the hour, `starts_at`
lands exactly on the ledger grid. The client sends an instant rather than a
local date and hour because a `timestamptz` is unambiguous across a fall-back
transition, where one wall-clock hour names two different instants; hours a
spring-forward transition skips are never offered.

The seventh local date still closes at local midnight, so a later start
shortens **day one** instead of moving the end. A challenge opening at 15:00
has a first day of nine completed hours, and on a daily cadence that is the
same target in less time. That is a frozen term like any other, so the start
step and the review screen both state it before anyone confirms. Keeping the
end on a local midnight is also what holds the seven scored local dates and the
expected coverage buckets in agreement — every expected bucket falls inside the
dates `app.personal_daily_progress_v1` generates, so the aggregate count cannot
drift from the per-day counts.

This is also the fastest way to reach an active challenge for testing: the next
whole hour instead of the next midnight.

### What is not proven yet

- **The attested pipeline end to end.** `activity-diagnostic` and
  `personal-sync-coverage` were deployed on 2026-08-03 and fail closed to 401
  without auth, but no device has completed a signed diagnostic or coverage
  submission against them yet. Until one does, App Attest on this bundle is
  unproven.
- **Debug data is not Staging data.** Debug points at your local stack, so a
  challenge created there does not exist in hosted Staging. Switching schemes
  switches accounts and challenges.
- **The Solo domain is applied on hosted Staging, not held back.** An earlier
  revision of this file claimed migrations `20260803001438`, `20260803001455`,
  and `20260803014252` were local-only and that the hosted project stopped at
  `20260802165312`. That was wrong when written. On 2026-08-03
  `supabase migration list --linked` reported all three as applied remotely,
  and a hosted schema dump shows `solo_contracts`, `solo_evaluations`, and
  `solo_appeals` present. The practical consequence is the opposite of the old
  warning: a `supabase db push` of a later migration no longer drags Solo along,
  because Solo is already there. Verify with `supabase migration list --linked`
  before trusting either claim.

  What has **not** been re-checked is the hosted runtime state. The migrations
  create the domain switched off with an empty beta allowlist, and no app, Edge
  Function, or scheduler calls the Solo surface, but the current values of
  `app.solo_contract_runtime` and `app.solo_beta_eligibility` on the hosted
  project have not been read back. Do that before assuming Solo is inert there.
- **The Simulator.** It has no first-party device step samples, so the local
  probe finds nothing and creation stays blocked. This is inherent — the
  product scores device-recorded steps.
- **Two-actor privacy on real infrastructure.** Proven in pgTAP, not hosted.

[PLAN.md](PLAN.md) is the roadmap;
[docs/PERSONAL_V1_ACCEPTANCE.md](docs/PERSONAL_V1_ACCEPTANCE.md) is the bounded
Stage A acceptance record.

### Dormant by design

The owner-only Solo contract domain (Steps 2A–2B) and the former
friend-and-charity challenge are implemented, tested, and switched off. V1 does
not expose friends, invitations, rosters, standings, winners, charities,
reactions, or tie-breaks, and never reinterprets a legacy contest as personal
accountability. Their documentation lives in
[docs/archive/2026-08-03_DORMANT_SUBSYSTEMS.md](docs/archive/2026-08-03_DORMANT_SUBSYSTEMS.md).

Switched off is a statement about the runtime switch, not about where the
schema exists. The Solo tables are present on hosted Staging — see
"What is not proven yet" above.

## Repository layout

```
supabase/
  config.toml            Local stack configuration
  migrations/            Hand-written SQL. The only way schema changes.
  tests/                 pgTAP suites: schema, constraints, RLS
  functions/
    _shared/             App Attest, ingest, scoring, and privacy-safe DB adapters
    _test/               Fixture builders and the scoring corpus. Never deployed.
    attest-device/       Registers one App Attest key per device install [deployed]
    ingest-metrics/      The only route into the evidence ledger [deployed]
    ingest-checkin/      Attested geofence/workout validation sidecar [deployed]
    activity-diagnostic/ Attested trusted-HealthKit diagnostic summary [deployed]
    personal-sync-coverage/ Attested completed-hour coverage [deployed]
    deliver-push/        Payload-free notification outbox dispatcher [deployed]
    deno.json            Deno tasks, imports, lint and format config
  seed.sql               Local/CI seed data. Never required by a test.
ios/
  GameTimeCore/          Portable Swift package. No Apple frameworks.
                         Bucketing, provenance, check-in validation, metric
                         retry primitives, and a restorable exact-byte
                         check-in queue.
                         Builds and tests on Linux CI.
  GameTime/              Personal V1 product app plus unit/UI targets. Live
                         Supabase adapters, Apple auth, personal challenge and
                         exact-retry activity flows, and isolated fixtures;
                         Release personal mutation is locked.
  GameTimeConformance/   Independent M6.5 App Attest smoke harness only.
scripts/
  dev-up.sh              Start the local stack
  db-test.sh             Reset the database and run pgTAP
  test-all.sh            Everything CI runs, in CI's order
  m6-5-configure-staging.sh  Pin and upload safe App Attest staging secrets
  m6-5-staging-fixture.sql   Repeatable staging contest/geofence fixture
docs/
  COPY.md                     How the app talks, and the domain-to-plain glossary
  M6_5_DEVICE_CONFORMANCE.md  Physical-iPhone/staging release gate
  PERSONAL_V1_ACCEPTANCE.md   Personal Stage A and two-actor privacy proof
  M8_1_STAGING_ACCEPTANCE.md  Preserved legacy social acceptance record
  archive/                Historical plans and audit evidence
CLAUDE.md                Repository conventions, for humans and agents alike
DECISIONS.md             Every non-obvious choice and why
PLAN.md                  The one active path to Personal Accountability V1
```

## What the app says

The domain vocabulary in this README — trusted evidence, frozen terms,
coverage, eligibility holds, cadence, attestation — is exact, and it stays
exact in the schema, the ledger, and `DECISIONS.md`. **None of it goes on
screen.** Verification is what GameTime does for someone; making them learn
its vocabulary hands them the work instead.

Screen copy says what happened and what to do next, in the words the person
would use: *steps* rather than trusted steps, *Health check* rather than
diagnostic, *draft* rather than retry record, *"this one didn't count"* rather
than inconclusive-and-waived. [docs/COPY.md](docs/COPY.md) holds the rules and
the full glossary, and it is required reading before changing any user-facing
string — including the `errorDescription` of a `LocalizedError`, which is copy
like any other. `GameTimeUITests` asserts on visible copy, so a wording change
and its assertions belong in the same commit.

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

### Run on your own iPhone against the local stack

This is the fastest working loop and the one that exercises real HealthKit.

1. **Point Debug at your Mac.** Create
   `ios/GameTime/Configuration/LocalOverrides.xcconfig` (gitignored, already
   included by `Debug.xcconfig`):

   ```
   SUPABASE_URL = http:/$()/<your-lan-ip>:54321
   SUPABASE_PUBLISHABLE_KEY = <PUBLISHABLE_KEY printed by dev-up.sh>
   ```

   Find the address with `ipconfig getifaddr en0`. The `$()` is required —
   xcconfig treats a bare `//` as a comment. The phone and Mac must share a
   network; Kong already binds `0.0.0.0:54321`.

2. **Enable Sign in with Apple locally.** Add to `.env.local`, then restart
   the stack:

   ```
   SUPABASE_AUTH_EXTERNAL_APPLE_CLIENT_ID=com.mjenkins.gametime.staging
   SUPABASE_AUTH_EXTERNAL_APPLE_SECRET=local-unused-native-id-token-flow
   ```

   GameTime uses the native `id_token` flow, so GoTrue validates the token
   against Apple's public keys and checks its audience against this client ID.
   The secret only matters for the web redirect flow, which is unused.

3. **Run the `GameTime` scheme** on a provisioned device. Grant Health access
   when asked, tap **Verify Health access**, and create a challenge. Choose a
   start on the next whole hour rather than the default next midnight if you
   want an active challenge to test against sooner; the first bucket is
   syncable once that hour has finished.

If `supabase start` appears to hang, check for a macOS keychain dialog — the
CLI reads its stored access token and blocks on the prompt.

### Run the installed product

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

A historical ledger of what was built, kept for provenance. It records
repository work, not deployed or device-proven behaviour — several entries
below describe capabilities that exist in code but have never run outside a
test. **"What works right now" at the top of this file is authoritative for
current state.** PLAN.md holds the remaining gates.

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
  - [ ] **Later M8 (legacy/social follow-up)** — Core Location/workouts,
        product App Attest lifecycle hardening, durable inbox/APNs, evidence
        persistence, M7 review/actionable
        settlement/dispute screens, accessibility hardening, and privacy/App
        Store work
- [x] **M9 personal accountability V1 repository slice** — The implementation adds
      the three-tab personal experience, atomic test-only challenge lifecycle,
      private personal evidence/result records, and a Staging-only HealthKit
      observer path. The local simulator layer passes 103 product unit tests, 10
      product UI tests, 10 App Attest conformance tests, and unsigned Debug,
      Staging, and Release builds. The portable local gate also passes 1,617
      pgTAP assertions, 350 Deno tests, 103 GameTimeCore tests, schema lint, and
      local security/performance advisors. Xcode 26.2's expected no-AppIntents
      metadata self-skip is accepted under D83 rather than hidden or worked
      around with an unused dependency.
- [ ] **M9 Stage A acceptance** — The repository-local simulator layer is
      complete. Hosted Staging acceptance and signed physical-iPhone
      foreground/background delivery proof remain open. No deployment,
      TestFlight release, or live fee is authorized by the repository slice.
- [x] **M10 Steps 2A–2B owner-only Solo repository slices** — The disabled Solo
      aggregate freezes policy-locked test contracts, append-only evaluation and
      appeal facts, and logical settlement. Its new atomic v2 boundary adds one
      immutable private processor-neutral fake authorization and append-only
      fake resolution events while preserving contract-only v1 creation. The
      runtime switch remains off, the beta allowlist remains empty, and no app,
      Edge, scheduler, hosted, provider, or money-moving integration is enabled.
