-- M3 — The evidence ledger, device attestation, and attested ingest.
--
-- Everything before this milestone was an agreement. This is the first
-- milestone that records a claim about the physical world, which is the only
-- kind of row in this schema that someone has a financial motive to falsify.
--
--   device_attestations  one App Attest key per device, with its replay counter
--   ingest_batches       one row per accepted ingest request; the audit trail
--   metric_snapshots     the ledger: hourly measurements with their provenance
--   contest_evidence     a view: the current admissible figure per bucket
--
-- Conventions inherited: extensions in `extensions`, RLS helpers in the private
-- `app` schema, every function with an explicit search_path, revoke-then-grant
-- rather than relying on the absence of a policy (D21).
--
-- ---------------------------------------------------------------------------
-- The shape of the ledger, in four sentences
-- ---------------------------------------------------------------------------
-- A snapshot is one *observation*: "at this moment, this client reported that
-- this participant's `steps` for this hour, from this source, was 812." They are
-- appended and never rewritten, so a figure that grows as late samples arrive
-- accumulates rows rather than changing one.
--
-- Reading it back therefore has two steps. Within one source a bucket's
-- revisions are a monotone series, so the current figure is the largest of them;
-- across sources the contributions are disjoint, so they add.
-- `contest_evidence` is that reduction, and it is what M4 scores.
--
-- ---------------------------------------------------------------------------
-- Three things that are deliberately absent
-- ---------------------------------------------------------------------------
-- * No client write path of any kind. `authenticated` holds SELECT on all
--   three tables and nothing else. A row appears only through
--   `public.record_metric_batch()`, which service_role alone may call, because
--   the thing that authorises the write is a signature over the payload and
--   RLS cannot check a signature.
-- * No plausibility ceiling on `value`. "40,000 steps in one hour is not
--   real" is a tunable threshold, and D6 puts thresholds in TypeScript and
--   invariants here. What this migration enforces is only what has no tuning
--   parameter: the window, the alignment, the monotonicity, the append-only.
-- * No DELETE trigger on the ledger, which is not an oversight. See the note
--   above `metric_snapshots_forbid_update` — a cascade from a deleted account
--   is a real DELETE, and the ledger must not be the reason an account cannot
--   be deleted. That bug already happened once (D34) and this is the same
--   family.

-- ===========================================================================
-- SECTION 1 — Enumerations
-- ===========================================================================

-- Where a measurement came from, in the domain's words rather than HealthKit's.
-- The mapping from `HKSourceRevision`, `HKDevice` and
-- `HKMetadataKeyWasUserEntered` onto these four values lives in the client, in
-- one place, so Apple's identifiers do not leak into the schema.
--
-- The split that matters is not "trustworthy or not" but "has a tuning
-- parameter or not":
--
--   device       first-party Apple hardware reported it and the user did not
--                type it. Admissible.
--   third_party  another app wrote it to HealthKit. Admissible, because Strava
--                recording a genuine run is this, and so is a step-spoofing
--                app — telling those apart is a heuristic, which is M5's and
--                belongs in TypeScript (D6).
--   manual       the user typed it into the Health app. Never admissible.
--   unknown      the sample carried no usable provenance metadata at all.
--                Never admissible: absent evidence of origin is not evidence.
create type public.metric_provenance as enum (
  'device',
  'third_party',
  'manual',
  'unknown'
);

-- App Attest keys attested in Apple's development environment are not evidence
-- of anything in production: a development attestation can be produced from a
-- debug build on a device the attacker controls. The distinction arrives in the
-- attestation's AAGUID and is recorded here so that a row's origin stays
-- auditable after the fact. Refusing the wrong one for the running deployment
-- is the Edge Function's job, since the database has no idea which environment
-- it is serving.
create type public.attestation_environment as enum ('development', 'production');

-- ===========================================================================
-- SECTION 2 — Tables
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- device_attestations
-- ---------------------------------------------------------------------------
-- One row per App Attest key, which is one row per (app install, device). The
-- public key is extracted from Apple's attestation certificate once, at
-- registration; every later ingest is an ECDSA signature verified against it.
--
-- This table is where anti-cheat rule 9 actually lives. The Edge Function
-- checks the signature — that needs crypto — and this table holds the two
-- facts a signature check cannot establish on its own: that the key belongs to
-- the user claiming it, and that the assertion has not been seen before.
create table public.device_attestations (
  -- Apple's key identifier is the SHA-256 digest of the public key, so it is
  -- stored as the 32 raw bytes rather than as base64. That is not tidiness:
  -- it lets "the key id is the digest of the key it names" be a CHECK, which
  -- makes substituting one key's id onto another key's bytes impossible at the
  -- database layer rather than merely unlikely in the function that writes it.
  key_id            bytea primary key,

  user_id           uuid not null references public.profiles (id) on delete cascade,

  -- The uncompressed P-256 point, 0x04 || X || Y, which is the form Apple
  -- digests to produce the key id and the form Web Crypto imports as "raw".
  public_key        bytea not null,

  environment       public.attestation_environment not null,

  -- App Attest's assertion counter. Monotonically increasing, enforced by a
  -- trigger: this is the replay defence, and it is an invariant rather than a
  -- heuristic, so it belongs here and not in TypeScript (D6).
  sign_count        bigint not null default 0,

  -- Set rather than deleted. A key is evidence about how a batch arrived, so
  -- revoking it must not erase the batches it signed.
  revoked_at        timestamptz,

  attested_at       timestamptz not null default now(),
  last_asserted_at  timestamptz,
  updated_at        timestamptz not null default now(),

  constraint device_attestations_public_key_is_uncompressed_p256
    check (octet_length(public_key) = 65 and get_byte(public_key, 0) = 4),

  constraint device_attestations_key_id_is_public_key_digest
    check (key_id = extensions.digest(public_key, 'sha256')),

  constraint device_attestations_sign_count_non_negative
    check (sign_count >= 0)
);

comment on table public.device_attestations is
  'One App Attest key per device install. Holds the public key and the assertion replay counter.';
comment on column public.device_attestations.key_id is
  'Apple''s key id: the raw SHA-256 of public_key. A CHECK holds the two to each other.';
comment on column public.device_attestations.sign_count is
  'App Attest assertion counter. Strictly increasing; this is the replay defence.';
comment on column public.device_attestations.revoked_at is
  'Set to retire a key. Never deleted, because it is evidence about the batches it signed.';

create index device_attestations_user_idx
  on public.device_attestations (user_id);

-- ---------------------------------------------------------------------------
-- ingest_batches
-- ---------------------------------------------------------------------------
-- One row per accepted ingest request. Two jobs, and the second is the one
-- worth the table.
--
-- First, it is the idempotency record. A phone that times out mid-request
-- retries, and a retry must not be refused merely because its assertion
-- counter has already been consumed — so `client_batch_id` is checked before
-- the counter is, and a replay returns the original result rather than an
-- error. That is the ordinary idempotency-key contract, and this domain wants
-- it for the ordinary reason.
--
-- Second, it is the attestation audit trail. Asking "was this evidence
-- attested, by which key, under which counter, and how far behind the
-- measurement did it arrive" is a question a settlement dispute will ask, and
-- it is answerable here without carrying the attestation on every one of the
-- several hundred snapshot rows a single sync produces.
--
-- A batch is scoped to one contest. That is what makes acceptance
-- all-or-nothing with an unambiguous error: the window check and the status
-- check are properties of the contest, so a batch spanning two of them would
-- have to either fail wholesale for a reason naming only one, or half-succeed.
create table public.ingest_batches (
  id                 uuid primary key default gen_random_uuid(),

  contest_id         uuid not null,
  user_id            uuid not null,

  -- Client-generated, stable across retries of the same batch.
  client_batch_id    uuid not null,

  -- Null only under the App Attest development bypass (D11), which cannot be
  -- enabled in staging or production. `attested` records which of the two
  -- happened, permanently, so a deployment can be audited with
  -- `select count(*) from public.ingest_batches where not attested`.
  key_id             bytea references public.device_attestations (key_id) on delete cascade,
  sign_count         bigint,
  attested           boolean not null,

  -- SHA-256 over the exact bytes the assertion was computed on. Recording it
  -- is what makes the signature checkable after the fact: without it, "this
  -- batch was attested" is a claim about a payload nobody kept.
  payload_digest     bytea not null,

  observation_count  integer not null,

  -- Two clocks, deliberately. `observed_at` is when the phone read HealthKit
  -- and `recorded_at` is when the server accepted it, so the gap between them
  -- is visible — and so is the gap between either and the bucket being
  -- reported, which is the reporting lag M5 quarantines on.
  observed_at        timestamptz not null,
  recorded_at        timestamptz not null default now(),

  -- One batch per client id per user. This is the idempotency key.
  constraint ingest_batches_client_batch_id_unique
    unique (user_id, client_batch_id),

  -- Redundant against the primary key, and needed as the target of the
  -- three-column foreign key from metric_snapshots below.
  constraint ingest_batches_identity_unique
    unique (id, contest_id, user_id),

  -- Evidence can only be tendered by somebody on the roster.
  constraint ingest_batches_participant_fkey
    foreign key (contest_id, user_id)
    references public.contest_participants (contest_id, user_id) on delete cascade,

  constraint ingest_batches_payload_digest_is_sha256
    check (octet_length(payload_digest) = 32),

  constraint ingest_batches_observation_count_positive
    check (observation_count > 0),

  -- An attested batch names the key and the counter that attested it; an
  -- unattested one names neither. Declarative, so no code path can leave a
  -- batch claiming to be attested by nothing.
  constraint ingest_batches_attestation_fields_match
    check (attested = (key_id is not null and sign_count is not null))
);

comment on table public.ingest_batches is
  'One row per accepted ingest request: the idempotency key and the attestation audit trail.';
comment on column public.ingest_batches.client_batch_id is
  'Client-generated and stable across retries. Checked before the assertion counter is consumed.';
comment on column public.ingest_batches.payload_digest is
  'SHA-256 of the bytes the assertion signed, so the signature stays checkable after the fact.';
comment on column public.ingest_batches.attested is
  'False only under the development bypass (D11). Never true without a key and a counter.';

create index ingest_batches_contest_user_idx
  on public.ingest_batches (contest_id, user_id, recorded_at desc);

-- ---------------------------------------------------------------------------
-- metric_snapshots
-- ---------------------------------------------------------------------------
-- The ledger. Append-only, one row per observation.
--
-- There is no unique constraint across (contest, user, metric, bucket_start),
-- and its absence is the design rather than an omission. HealthKit's figure
-- for an hour grows: a watch syncs late, a workout is written after the fact.
-- A ledger that stored one row per bucket would have to overwrite it, which
-- destroys the record of what was claimed and when — and *when* is precisely
-- what distinguishes a late sync from a fabrication. So a revision appends,
-- both rows survive, and the reporting lag of each is visible.
create table public.metric_snapshots (
  id                uuid primary key default gen_random_uuid(),

  batch_id          uuid not null,

  -- Denormalised from the batch so that the RLS policy and the scoring query
  -- can filter without joining. Kept honest by the three-column foreign key
  -- below rather than by convention: the pair here must be the pair on the
  -- batch, so the two cannot drift.
  contest_id        uuid not null,
  user_id           uuid not null,

  -- Not constrained to the contest's own metric. Cross-metric corroboration —
  -- 20,000 steps and no active energy in the same hour — is one of M5's
  -- strongest signals, and it needs the metrics the contest is not scoring.
  metric            public.contest_metric not null,

  -- The hour this measurement covers, half-open: [bucket_start, +1 hour).
  --
  -- Aligned to a whole hour *in the participant's frozen timezone*, not in
  -- UTC, and that is not interchangeable. Not every zone is a whole number of
  -- hours from UTC — India is +05:30, Nepal +05:45, Chatham +13:45 — so a
  -- UTC-aligned hour straddles the local day boundary for about a fifth of the
  -- world's population, and daily cadence would silently attribute part of
  -- Tuesday to Monday for exactly those participants. A locally-aligned hour
  -- lies inside one local day by construction, which is the property D5's
  -- "did you hit 10k on *your* Tuesday" actually requires.
  bucket_start      timestamptz not null,

  -- The server's reading of which local day and hour the bucket falls in,
  -- stamped at insert from the participant's frozen zone. Derived, but stored
  -- rather than recomputed: the row is append-only and the zone is immutable,
  -- so the two can never come to disagree, and storing it means the day
  -- attribution a settlement rests on is the one recorded at the time rather
  -- than whatever a later query would compute.
  local_day         date not null,
  local_hour        smallint not null,

  value             numeric(12, 2) not null,

  provenance        public.metric_provenance not null,

  -- Generated, so it cannot be set to disagree with the provenance it derives
  -- from. `manual` and `unknown` are the two cases with no tuning parameter,
  -- which is what makes admissibility an invariant and not a heuristic.
  --
  -- Note the direction this settles: an inadmissible observation is *stored*,
  -- not refused. The client reports what HealthKit told it and the server
  -- decides what counts, because a client that filters its own evidence is a
  -- client whose silence we would have to trust. A user's 20,000 hand-typed
  -- steps are a fact about that user, and refusing the row would discard it.
  is_admissible     boolean not null
    generated always as (provenance in ('device', 'third_party')) stored,

  -- How many HealthKit samples were summed into this bucket. One sample
  -- carrying an hour's worth of steps and sixty carrying a minute each are
  -- different stories, and M5 has reason to read the difference.
  sample_count      integer not null,

  source_bundle_id  text,
  device_model      text,

  observed_at       timestamptz not null,
  recorded_at       timestamptz not null default now(),

  -- Three columns rather than one, so the denormalised contest and user must
  -- match the batch they arrived in.
  constraint metric_snapshots_batch_fkey
    foreign key (batch_id, contest_id, user_id)
    references public.ingest_batches (id, contest_id, user_id) on delete cascade,

  -- One observation per bucket per metric per provenance within a batch. A batch
  -- carrying the same three twice is a client bug, and this makes it a loud one.
  --
  -- Provenance is part of the key rather than one value per bucket, and the
  -- reason is a fairness problem rather than a modelling preference. A single
  -- hour routinely contains samples from more than one source — an iPhone's
  -- pedometer, a watch, a running app, and sometimes a figure the user typed
  -- into the Health app years ago. Collapsing that to one row would mean
  -- choosing one provenance for the hour, and the only safe choice is the least
  -- trusted one present — which would make one stray hand-typed step discard
  -- 5,000 genuine ones and lose somebody a day they actually walked.
  --
  -- Splitting keeps each source's contribution separately admissible, so the
  -- hand-typed part is excluded and the rest counts. `contest_evidence` is what
  -- puts the parts back together.
  constraint metric_snapshots_one_per_bucket_per_batch
    unique (batch_id, metric, bucket_start, provenance),

  constraint metric_snapshots_value_non_negative check (value >= 0),
  constraint metric_snapshots_sample_count_positive check (sample_count > 0),
  constraint metric_snapshots_local_hour_range check (local_hour between 0 and 23),

  constraint metric_snapshots_source_bundle_id_length
    check (source_bundle_id is null or char_length(source_bundle_id) between 1 and 200),
  constraint metric_snapshots_device_model_length
    check (device_model is null or char_length(device_model) between 1 and 100)
);

comment on table public.metric_snapshots is
  'Append-only evidence ledger. One row per observation of one hour of one metric.';
comment on column public.metric_snapshots.bucket_start is
  'Start of a one-hour bucket, aligned to a whole hour in the participant''s frozen zone.';
comment on column public.metric_snapshots.local_day is
  'Server-derived local day of the bucket. Stamped at insert; never supplied by a client.';
comment on column public.metric_snapshots.is_admissible is
  'Generated. False for manual and unknown provenance, which never count toward a target.';
comment on column public.metric_snapshots.sample_count is
  'HealthKit samples summed into this bucket. One giant sample is a different story from sixty.';

-- The scoring read: every bucket for one participant in one contest.
create index metric_snapshots_bucket_idx
  on public.metric_snapshots (contest_id, user_id, metric, bucket_start);

-- The daily-cadence read: one participant's days.
create index metric_snapshots_local_day_idx
  on public.metric_snapshots (contest_id, user_id, local_day);

create index metric_snapshots_batch_idx
  on public.metric_snapshots (batch_id);

-- ===========================================================================
-- SECTION 3 — Trigger functions
-- ===========================================================================

-- How long after a contest's window closes evidence for it is still accepted.
--
-- A named constant rather than a literal because M7's finaliser must not run
-- before it has elapsed, and two copies of this number would eventually differ
-- by one being tuned. It is the one genuinely tunable figure this migration
-- puts in SQL, and it is here rather than in TypeScript because it gates
-- whether a row may exist at all.
--
-- Six hours is a compromise between two real costs. Too short and a phone that
-- spent the night asleep loses its owner the last day of the contest through no
-- fault of theirs — HealthKit's background delivery is opportunistic, and a
-- watch only syncs when it is near its phone. Too long and the window in which
-- a participant already knows they lost, and can still write into the hours
-- they lost it in, gets wider. M5 narrows the second cost further by
-- quarantining observations whose reporting lag is large; this only has to
-- bound it.
create or replace function app.ingest_grace_period()
returns interval
language sql
immutable
set search_path = ''
as $$
  select interval '6 hours';
$$;

comment on function app.ingest_grace_period() is
  'How long after ends_at evidence is still accepted. M7 must not finalize before it elapses.';

-- Everything about a snapshot that the participant's own contest decides:
-- whether the row may exist at all, which local day it falls in, and whether
-- it walks a figure backwards.
--
-- Definer rights, for the same reason M2's transition trigger has them: this
-- reads contests and contest_participants, and under invoker rights those
-- reads would be silently narrowed to whatever the writing role can see
-- through RLS. A check that returns "no such contest" because a policy hid it
-- is a check that passes for the wrong reason.
create or replace function app.prepare_metric_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status          public.contest_participant_status;
  v_timezone        text;
  v_contest_status  public.contest_status;
  v_starts_at       timestamptz;
  v_ends_at         timestamptz;
  v_local           timestamp;
  v_highest         numeric(12, 2);
begin
  select p.status, p.timezone, c.status, c.starts_at, c.ends_at
    into v_status, v_timezone, v_contest_status, v_starts_at, v_ends_at
  from public.contest_participants p
  join public.contests c on c.id = p.contest_id
  where p.contest_id = new.contest_id
    and p.user_id = new.user_id;

  if v_status is null then
    raise exception 'no roster row for user % on contest %', new.user_id, new.contest_id
      using errcode = 'foreign_key_violation';
  end if;

  -- Evidence from someone who is not running in the contest measures nothing.
  -- An invitation is not participation, and a withdrawal ends it.
  if v_status <> 'accepted' then
    raise exception
      'only an accepted participant may record evidence (status %)', v_status
      using errcode = 'restrict_violation';
  end if;

  -- The contest must be open. Not pending: there is nothing to measure before
  -- the window exists. Not cancelled or finalized: a settled contest is
  -- closed evidence, which is the finalized-contest immutability D6 asks for.
  if v_contest_status <> 'active' then
    raise exception
      'contest % is not accepting evidence (status %)', new.contest_id, v_contest_status
      using errcode = 'restrict_violation';
  end if;

  -- The grace window. `status = active` alone would let a contest whose cron
  -- finalisation never ran accept evidence indefinitely, which is a stalled
  -- job turning into an exploit.
  if now() >= v_ends_at + app.ingest_grace_period() then
    raise exception
      'the ingest window for contest % closed at %',
      new.contest_id, v_ends_at + app.ingest_grace_period()
      using errcode = 'restrict_violation';
  end if;

  -- The bucket must lie wholly inside the agreed window.
  --
  -- This is the other half of D25. That rule stops a contest naming a window
  -- already in the past; this one stops evidence being tendered for hours
  -- outside the window it named. Either one alone leaves the exploit open from
  -- the other end, and neither is expensive.
  --
  -- "Wholly inside" rather than "starts inside" on purpose: a bucket that
  -- began before the last hour of the window would carry activity from after
  -- the contest ended. A window that is not itself hour-aligned therefore has
  -- an unusable partial hour at each end, which is the conservative direction
  -- to fail in.
  if new.bucket_start < v_starts_at
     or new.bucket_start + interval '1 hour' > v_ends_at
  then
    raise exception
      'bucket % is outside the window of contest % (% to %)',
      new.bucket_start, new.contest_id, v_starts_at, v_ends_at
      using errcode = 'invalid_parameter_value';
  end if;

  -- An hour that has not finished cannot have been measured. Without this,
  -- every contest with a window still open would accept a complete set of
  -- winning figures for the rest of it, in advance, from a client that simply
  -- made them up — and the window rule above would happily allow it, because
  -- those hours are inside the agreed window.
  --
  -- No tolerance for clock skew, for D25's reason: a grace period here is
  -- exactly the amount of the future it lets you report. A client that is a
  -- second early retries a second later, which costs it nothing.
  if new.bucket_start + interval '1 hour' > now() then
    raise exception 'bucket % has not finished yet (now %)', new.bucket_start, now()
      using errcode = 'invalid_parameter_value';
  end if;

  -- Alignment, and then the local day, both read from the frozen zone. A
  -- participant who has accepted always has one: the CHECK on
  -- contest_participants makes timezone required for `accepted`.
  v_local := new.bucket_start at time zone v_timezone;

  if v_local <> date_trunc('hour', v_local) then
    raise exception
      'bucket % is not aligned to a whole hour in % (local %)',
      new.bucket_start, v_timezone, v_local
      using errcode = 'invalid_parameter_value';
  end if;

  new.local_day  := v_local::date;
  new.local_hour := extract(hour from v_local)::smallint;

  -- Monotonicity. The figure for a bucket may be revised upward as late
  -- samples arrive; it may not be walked back.
  --
  -- This is not framed as anti-cheat, and it would be dishonest to: only the
  -- participant may write their own rows, so a downward revision harms nobody
  -- but its author. What it buys is that "the value for this bucket" is
  -- single-valued — the latest observation and the largest observation are the
  -- same number — so the scoring engine, the standings, and any later audit
  -- cannot arrive at different totals from the same ledger. It also makes a
  -- genuine deletion in the Health app surface as a dispute for M7 rather than
  -- as a quiet rewrite of banked evidence.
  --
  -- Keyed on provenance as well, because that is the grain a value has: each
  -- source's contribution to an hour grows on its own, and comparing a watch's
  -- figure against a running app's would refuse perfectly ordinary data.
  --
  -- Rows inserted earlier in the same statement are visible here, so a batch
  -- cannot smuggle a decrease past this by ordering.
  select max(value) into v_highest
  from public.metric_snapshots
  where contest_id = new.contest_id
    and user_id = new.user_id
    and metric = new.metric
    and bucket_start = new.bucket_start
    and provenance = new.provenance;

  if v_highest is not null and new.value < v_highest then
    raise exception
      'bucket % of % from % already stands at %; a figure cannot be revised down to %',
      new.bucket_start, new.metric, new.provenance, v_highest, new.value
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

comment on function app.prepare_metric_snapshot() is
  'BEFORE INSERT on metric_snapshots. Window, alignment, local-day stamping, and monotonicity.';

-- The App Attest assertion counter only ever goes up.
--
-- Apple increments it on every assertion the key produces, so a counter that
-- has not advanced is a replayed assertion and a counter that has gone
-- backwards is a forged one. Enforced here rather than in the Edge Function
-- because it has to be atomic with consuming it: two concurrent requests
-- carrying the same assertion would both pass a read-then-write check in
-- application code, and this is the one check standing between a captured
-- request and unlimited replay of it.
create or replace function app.enforce_sign_count_monotonicity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.sign_count < old.sign_count then
    raise exception
      'assertion counter for this key is at %; % is a replay',
      old.sign_count, new.sign_count
      using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;

comment on function app.enforce_sign_count_monotonicity() is
  'BEFORE UPDATE on device_attestations. The App Attest replay defence, as an invariant.';

-- ===========================================================================
-- SECTION 4 — Triggers
-- ===========================================================================

create trigger device_attestations_set_updated_at
  before update on public.device_attestations
  for each row execute function app.set_updated_at();

-- Which key, whose it is, and what it attests to are all settled at
-- registration. `key_id` and `public_key` are additionally held to each other
-- by a CHECK, so freezing them is the second mechanism rather than the only
-- one (D21).
create trigger device_attestations_freeze_identity
  before update on public.device_attestations
  for each row execute function app.forbid_column_change(
    'key_id', 'user_id', 'public_key', 'environment', 'attested_at'
  );

create trigger device_attestations_enforce_sign_count
  before update on public.device_attestations
  for each row execute function app.enforce_sign_count_monotonicity();

create trigger metric_snapshots_prepare
  before insert on public.metric_snapshots
  for each row execute function app.prepare_metric_snapshot();

-- ---------------------------------------------------------------------------
-- Append-only, and why only half of it is a trigger
-- ---------------------------------------------------------------------------
-- UPDATE is refused outright. DELETE is refused by withholding the grant
-- (section 6) and by there being no policy — but deliberately *not* by a
-- trigger, and the reason is the trap D34 records.
--
-- A referential action is a real statement. `metric_snapshots` cascades from
-- `ingest_batches`, which cascades from `contest_participants`, which cascades
-- from `profiles`, which cascades from `auth.users`. So deleting an account
-- issues a genuine DELETE against this table, and a blanket BEFORE DELETE
-- prohibition would refuse it and take the account deletion down with it —
-- meaning no account that had ever recorded a step could be deleted, which is
-- exactly the shape of the bug that had been live in M1 since it shipped.
--
-- Verified rather than assumed: `110_evidence_ledger.test.sql` deletes an
-- account with banked evidence and asserts it succeeds, and would fail if a
-- DELETE trigger were added here later.
--
-- This is the honest state of it rather than a happy one. The evidence for a
-- settled obligation should outlive the account, and today it does not — the
-- deferred decision on account deletion versus contest history owns that, and
-- its answer is to anonymise the profile rather than cascade. Once that lands,
-- the cascade path disappears and a DELETE trigger here becomes correct.
create trigger metric_snapshots_forbid_update
  before update on public.metric_snapshots
  for each row execute function app.forbid_mutation();

create trigger ingest_batches_forbid_update
  before update on public.ingest_batches
  for each row execute function app.forbid_mutation();

-- ===========================================================================
-- SECTION 5 — Access model
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.device_attestations enable row level security;
alter table public.ingest_batches enable row level security;
alter table public.metric_snapshots enable row level security;

-- Your own keys. Not secret — a public key is public and the counter is not
-- interesting — but there is no reason for anyone else to enumerate the
-- devices you sign in from, which is closer to a location trail than it looks.
create policy device_attestations_select_own on public.device_attestations
  for select to authenticated
  using (user_id = (select auth.uid()));

-- Your own evidence, plus that of anyone you are actually running against.
--
-- The second half reuses M2's `app.shares_active_contest()` rather than a
-- fresh predicate, which inherits D33's reasoning exactly: both parties must
-- have *accepted* and the contest must have *opened*. That matters more here
-- than it did for profiles. Hourly measurements over a month are a detailed
-- picture of when someone sleeps, works and travels, so "shares any contest in
-- any state" would let anyone buy a month of that with an invitation the
-- recipient never answered. What the accepted-and-opened form grants is
-- narrower and is what a dispute needs: the evidence you are being judged
-- against, held by the person judging you back.
--
-- It sits outside the block check for D29's reason. Blocking your opponent
-- must not blank out the record a settlement rests on, or "block whoever is
-- winning" becomes a way to make the evidence unreadable.
create policy ingest_batches_select_own_or_rival on public.ingest_batches
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or app.shares_active_contest(user_id, (select auth.uid()))
  );

create policy metric_snapshots_select_own_or_rival on public.metric_snapshots
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or app.shares_active_contest(user_id, (select auth.uid()))
  );

-- No INSERT, UPDATE or DELETE policy on any of the three, and no grant either
-- (section 6). What authorises a write here is an ECDSA signature over the
-- request body, and RLS cannot check a signature — so there is no policy that
-- could express the rule, and a client write path would be one that skipped
-- it. Ingest goes through section 6's function, as service_role, after the
-- Edge Function has verified the assertion.

-- ---------------------------------------------------------------------------
-- contest_evidence — the reduction M4 scores
-- ---------------------------------------------------------------------------
-- One row per (contest, participant, metric, bucket): the current admissible
-- figure, plus how it got there.
--
-- This exists so that "the value for this bucket" is defined in exactly one
-- place. The alternative is the scoring engine reducing the ledger itself,
-- which means the definition of admissibility and of latest-wins lives in
-- TypeScript while the invariants that make it sound live here, and the two
-- drift. D3 keeps one scoring engine for the same reason.
--
-- Two steps, because the ledger has two grains. Within one provenance a bucket's
-- figure is a monotone series of revisions, so the current value is `max(value)`
-- — and that is not a shortcut for "the most recently recorded": the
-- monotonicity trigger makes them the same number, and an aggregate cannot pick
-- the wrong row when two observations share a timestamp. Across provenances the
-- contributions are disjoint, so they add.
--
-- Getting this backwards in either direction is a scoring bug rather than a
-- style choice. Summing revisions would count a late sync twice; taking the max
-- across provenances would discard everything but the largest source.
--
-- `local_day` and `local_hour` are grouped rather than aggregated even though
-- they are functionally dependent on the bucket. Aggregating them would paper
-- over a disagreement; grouping means a bucket that somehow acquired two
-- different local days shows up as two rows and fails a test.
--
-- security_invoker is load-bearing and its absence would be a silent hole. A
-- view runs as its *owner* by default, and the owner here is the migration
-- role, which owns the underlying table and is therefore exempt from its
-- policies — so without this the view would hand every authenticated user the
-- entire ledger, RLS notwithstanding. Asserted in the suite as a privilege
-- test rather than trusted to review.
create view public.contest_evidence
with (security_invoker = true)
as
with per_source as (
  select
    contest_id,
    user_id,
    metric,
    bucket_start,
    local_day,
    local_hour,
    provenance,
    max(value)          as value,
    sum(sample_count)   as sample_count,
    count(*)            as observation_count,
    min(recorded_at)    as first_recorded_at,
    max(recorded_at)    as last_recorded_at
  from public.metric_snapshots
  where is_admissible
  group by contest_id, user_id, metric, bucket_start, local_day, local_hour, provenance
)
select
  contest_id,
  user_id,
  metric,
  bucket_start,
  local_day,
  local_hour,
  sum(value)                      as value,
  sum(sample_count)::bigint       as sample_count,
  sum(observation_count)::integer as observation_count,
  min(first_recorded_at)          as first_recorded_at,
  max(last_recorded_at)           as last_recorded_at
from per_source
group by contest_id, user_id, metric, bucket_start, local_day, local_hour;

comment on view public.contest_evidence is
  'Current admissible figure per bucket. The one definition of "the value for this hour".';

-- ===========================================================================
-- SECTION 6 — Callable API
-- ===========================================================================

-- The only way a row appears in either ledger table.
--
-- In `public` rather than `app` because PostgREST can only reach exposed
-- schemas and the Edge Function calls it over the Data API — so this is a
-- public function that only service_role may execute, and the revoke in
-- section 6 is doing real work rather than tidying. That is the second
-- instance of D32's pattern, which said the revoke should become a reviewed
-- default for anything that no policy calls rather than something remembered
-- per function; it is applied here as one.
--
-- The division of labour with the Edge Function is D6's, drawn where the
-- milestone's own crypto falls:
--
--   TypeScript  verifies the ECDSA signature over the payload, the rpId hash,
--               the AAGUID against the deployment environment, and the
--               certificate chain. All of that needs crypto and none of it is
--               expressible as an invariant.
--   Here        the counter has advanced, the key belongs to this user, the
--               key is not revoked, the batch is not a replay, and every
--               observation satisfies the ledger's rules. All of that is an
--               invariant and none of it needs crypto.
--
-- The counter check in particular has to be here. In application code it is a
-- read followed by a write, and two concurrent copies of a captured request
-- would both read the old value and both pass.
create or replace function public.record_metric_batch(
  p_user_id         uuid,
  p_contest_id      uuid,
  p_client_batch_id uuid,
  p_payload_digest  bytea,
  p_observed_at     timestamptz,
  p_observations    jsonb,
  p_key_id          bytea default null,
  p_sign_count      bigint default null
)
returns table (batch_id uuid, observation_count integer, replayed boolean)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_existing   public.ingest_batches;
  v_batch_id   uuid;
  v_count      integer;
  v_key        public.device_attestations;
begin
  if p_user_id is null or p_contest_id is null or p_client_batch_id is null then
    raise exception 'user, contest and client batch id are all required'
      using errcode = 'invalid_parameter_value';
  end if;

  if jsonb_typeof(p_observations) <> 'array' then
    raise exception 'observations must be a JSON array'
      using errcode = 'invalid_parameter_value';
  end if;

  v_count := jsonb_array_length(p_observations);

  if v_count = 0 then
    raise exception 'a batch must carry at least one observation'
      using errcode = 'invalid_parameter_value';
  end if;

  -- A bound on how much one request can do. Not a tuning knob for accuracy:
  -- 2000 hourly observations is eleven weeks of a single metric, so anything
  -- larger is a mistake or an attempt to make one transaction expensive.
  if v_count > 2000 then
    raise exception 'a batch may carry at most 2000 observations, got %', v_count
      using errcode = 'program_limit_exceeded';
  end if;

  -- Idempotency first, and specifically before the counter is touched. A retry
  -- of a request that already succeeded carries an assertion whose counter has
  -- been consumed, so checking the counter first would turn every timed-out
  -- retry into a permanent failure.
  select * into v_existing
  from public.ingest_batches
  where user_id = p_user_id
    and client_batch_id = p_client_batch_id;

  if v_existing.id is not null then
    -- Same key, different contents is not a retry, it is two different batches
    -- wearing one id. Refusing is the only safe answer: silently returning the
    -- first result would drop the second batch's evidence without telling
    -- anyone.
    if v_existing.payload_digest <> p_payload_digest then
      raise exception
        'batch % was already recorded with a different payload', p_client_batch_id
        using errcode = 'unique_violation';
    end if;

    return query
      select v_existing.id, v_existing.observation_count, true;
    return;
  end if;

  if p_key_id is not null then
    if p_sign_count is null then
      raise exception 'an attested batch must carry an assertion counter'
        using errcode = 'invalid_parameter_value';
    end if;

    -- Locked, so that the read of the counter and the write of it are one
    -- step. Without the lock this is the classic check-then-act race and the
    -- replay defence is decorative.
    select * into v_key
    from public.device_attestations
    where key_id = p_key_id
    for update;

    if v_key.key_id is null then
      raise exception 'unknown attestation key'
        using errcode = 'insufficient_privilege';
    end if;

    -- One error for "not your key" and "no such key", so this cannot be used
    -- to enumerate which keys exist.
    if v_key.user_id <> p_user_id then
      raise exception 'unknown attestation key'
        using errcode = 'insufficient_privilege';
    end if;

    if v_key.revoked_at is not null then
      raise exception 'this device key was revoked at %', v_key.revoked_at
        using errcode = 'insufficient_privilege';
    end if;

    -- Strictly greater. Equal is a replay of the assertion that produced the
    -- stored value, not a fresh one.
    if p_sign_count <= v_key.sign_count then
      raise exception
        'assertion counter % is not ahead of the recorded %',
        p_sign_count, v_key.sign_count
        using errcode = 'restrict_violation';
    end if;

    update public.device_attestations
    set sign_count = p_sign_count,
        last_asserted_at = now()
    where key_id = p_key_id;
  end if;

  insert into public.ingest_batches (
    contest_id, user_id, client_batch_id, key_id, sign_count,
    attested, payload_digest, observation_count, observed_at
  )
  values (
    p_contest_id, p_user_id, p_client_batch_id, p_key_id, p_sign_count,
    p_key_id is not null, p_payload_digest, v_count, p_observed_at
  )
  returning id into v_batch_id;

  insert into public.metric_snapshots (
    batch_id, contest_id, user_id, metric, bucket_start, value,
    provenance, sample_count, source_bundle_id, device_model, observed_at,
    -- Both are overwritten by the trigger from the participant's frozen zone.
    -- They are listed only because the columns are NOT NULL and a client has
    -- no business supplying them.
    local_day, local_hour
  )
  select
    v_batch_id,
    p_contest_id,
    p_user_id,
    (o ->> 'metric')::public.contest_metric,
    (o ->> 'bucket_start')::timestamptz,
    (o ->> 'value')::numeric,
    (o ->> 'provenance')::public.metric_provenance,
    coalesce((o ->> 'sample_count')::integer, 1),
    o ->> 'source_bundle_id',
    o ->> 'device_model',
    p_observed_at,
    'epoch'::date,
    0
  from jsonb_array_elements(p_observations) as o;

  return query select v_batch_id, v_count, false;
end;
$$;

comment on function public.record_metric_batch is
  'Attested ingest. service_role only: the Edge Function checks the signature, this checks the invariants.';

-- ===========================================================================
-- SECTION 7 — Privileges
-- ===========================================================================
-- As in M1 and M2: revoke Supabase's default ALL, then grant back only the
-- verbs that have a matching policy (D21).

revoke all on public.device_attestations, public.ingest_batches,
              public.metric_snapshots
  from anon, authenticated;

revoke all on public.contest_evidence from anon, authenticated;

grant select on public.device_attestations to authenticated;
grant select on public.ingest_batches to authenticated;
grant select on public.metric_snapshots to authenticated;
grant select on public.contest_evidence to authenticated;

-- Deliberately withheld, each by a missing grant as well as a missing policy:
--   device_attestations  INSERT/UPDATE/DELETE — registration is attested, and
--                        the counter is not the client's to move
--   ingest_batches       INSERT/UPDATE/DELETE — a batch is the record of an
--                        attested request; writing one directly would be
--                        forging that record
--   metric_snapshots     INSERT — the whole milestone. There is no
--                        unattested route into the ledger.
--                        UPDATE/DELETE — it is append-only.

-- The same treatment D32 gave app.activate_due_contests(), and for the same
-- reason: Postgres grants EXECUTE on a new function to PUBLIC, so a definer
-- function that writes the evidence ledger is callable by every signed-in user
-- until it is explicitly revoked. Left as created, any client could write any
-- other user's evidence, unattested, by passing their uuid.
revoke all on function public.record_metric_batch(
  uuid, uuid, uuid, bytea, timestamptz, jsonb, bytea, bigint
) from public, anon, authenticated;

grant execute on function public.record_metric_batch(
  uuid, uuid, uuid, bytea, timestamptz, jsonb, bytea, bigint
) to service_role;

-- Registration is the other half, and it is service_role-only for the same
-- reason: what authorises it is a verified attestation object, which only the
-- Edge Function has looked at.
create or replace function public.register_device_key(
  p_user_id     uuid,
  p_key_id      bytea,
  p_public_key  bytea,
  p_environment public.attestation_environment
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_existing public.device_attestations;
begin
  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'complete onboarding before registering a device'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing
  from public.device_attestations
  where key_id = p_key_id;

  if v_existing.key_id is not null then
    -- Re-registration by the same owner is idempotent: a client that lost its
    -- response and retried should not be stuck. Re-registration by anyone else
    -- is refused, because a key id is the digest of a key only one Secure
    -- Enclave holds, so a second owner claiming it is either a stolen
    -- attestation or a collision, and neither should be resolved in the
    -- claimant's favour.
    --
    -- Note what this deliberately does not do: reset the counter. Otherwise
    -- re-attesting would be a way to rewind the replay defence.
    if v_existing.user_id <> p_user_id then
      raise exception 'this device key is already registered to another account'
        using errcode = 'unique_violation';
    end if;
    return;
  end if;

  insert into public.device_attestations (key_id, user_id, public_key, environment)
  values (p_key_id, p_user_id, p_public_key, p_environment);
end;
$$;

comment on function public.register_device_key is
  'Records a verified App Attest key. service_role only. Idempotent for its owner, refused for anyone else.';

revoke all on function public.register_device_key(
  uuid, bytea, bytea, public.attestation_environment
) from public, anon, authenticated;

grant execute on function public.register_device_key(
  uuid, bytea, bytea, public.attestation_environment
) to service_role;

-- app.ingest_grace_period() is called by app.prepare_metric_snapshot(), which
-- is definer, and by M7's finaliser. No policy calls it and no client has any
-- reason to, so it gets D32's default.
revoke all on function app.ingest_grace_period() from public, anon, authenticated;
grant execute on function app.ingest_grace_period() to service_role;
