# M6.5 real-device App Attest conformance

This procedure is the release gate for M6.5. It exercises the production
registration, metric, and geofence envelopes against staging with one genuine
App Attest key. A simulator cannot complete it.

The repository-side harness, staging backend, and automated checks were
completed on 2026-07-25. The observation record at the end must remain unfilled,
and M6.5 must remain open, until an App Attest-capable Apple Developer Program
team provisions the connected iPhone target and a staging Auth user/fixture is
available.

## Expected proof

One run must establish all of these facts:

1. Staging boots with Apple's pinned root and with `ATTEST_DEV_BYPASS` absent.
2. A debug-signed physical-device target registers a development App Attest
   key. On iOS 27+, the server reports its validation category and bundle
   version; on iOS 18–26 it reports those signals as unavailable.
3. The stored key is a 65-byte uncompressed P-256 point and its SHA-256 digest
   equals Apple's decoded key id.
4. Apple's opaque receipt is captured only in the private receipt table,
   independently verified, and marked verified only after its PKCS#7 signature
   and Apple chain, receipt-signer purpose, App ID, creation time, and stored
   public-key binding all pass.
5. One exact signed metric body and one exact signed check-in body return 201.
6. Their assertion counters are positive and strictly increasing across the
   shared device key.
7. Replaying each identical signed request returns 200 with `replayed: true`,
   creates no second row, and does not advance the stored counter.
8. Staging contains no unattested metric batch or geofence check-in.

## 1. Provision and deploy staging

Prerequisites:

- A Supabase staging project, CLI login, project database password, and
  `SUPABASE_PROJECT_REF`.
- An active Apple Developer Program or Apple Developer Enterprise Program team
  and an explicit App ID with App Attest enabled. Xcode Personal Teams cannot
  provision the App Attest capability.
- `APPLE_TEAM_ID` and `APPLE_BUNDLE_ID` matching the conformance target.
- Supabase Auth credentials for one staging user who has completed profile
  onboarding. The iOS target accepts that user's access token at runtime.
- The staging project's publishable key for the post-deploy rejection probes.
- Supabase CLI, `psql`, `curl`, and OpenSSL.

Create the ignored local credential file from the checked-in template:

```bash
cp .env.m6-5-staging.example .env.m6-5-staging
```

Fill it locally, then load it into the current shell without printing any
values:

```bash
set -a
source .env.m6-5-staging
set +a
```

First verify the project in the Supabase dashboard is the dedicated staging
project. Replace the single `UNCONFIGURED` line in
`supabase/staging-project-ref` with its nonsecret 20-character project ref and
commit that reviewed identity before running either staging script. Then export
the same ref, link the repository, and apply every migration:

```bash
export SUPABASE_PROJECT_REF="$(tr -d '\n' < supabase/staging-project-ref)"
supabase link --project-ref "$SUPABASE_PROJECT_REF"
supabase db push
```

Export the Apple identifiers and a fresh dedicated challenge secret, then run
the guarded configuration script. It refuses any project other than the
checked-in staging identity:

```bash
export APPLE_TEAM_ID="ABCDEFGHIJ"
export APPLE_BUNDLE_ID="com.example.GameTimeConformance"
export GAMETIME_ATTEST_CHALLENGE_SECRET="$(openssl rand -hex 32)"
./scripts/m6-5-configure-staging.sh
```

The script downloads Apple's direct App Attestation Root CA and Root CA G3,
verifies both recorded SHA-256 fingerprints, uploads the public roots with the
required secrets, and unsets `ATTEST_DEV_BYPASS`. It intentionally enables
development attestations in staging because Xcode's debug entitlement produces
them. Production still refuses them.

Deploy all three functions. The handlers verify user sessions against the
project's injected JWKS in code, so the legacy gateway verifier stays disabled:

```bash
supabase functions deploy attest-device --project-ref "$SUPABASE_PROJECT_REF" --use-api \
  --import-map supabase/functions/deno.json
supabase functions deploy ingest-metrics --project-ref "$SUPABASE_PROJECT_REF" --use-api \
  --import-map supabase/functions/deno.json
supabase functions deploy ingest-checkin --project-ref "$SUPABASE_PROJECT_REF" --use-api \
  --import-map supabase/functions/deno.json
```

Confirm that the custom secret list names `GAMETIME_ENV`,
`GAMETIME_ATTEST_CHALLENGE_SECRET`, `APPLE_TEAM_ID`, `APPLE_BUNDLE_ID`,
`APP_ATTEST_ROOT_CA_PEM`, `APP_ATTEST_RECEIPT_ROOT_CA_PEM`, and
`APP_ATTEST_ALLOW_DEVELOPMENT`, but not `ATTEST_DEV_BYPASS`:

```bash
supabase secrets list --project-ref "$SUPABASE_PROJECT_REF"
```

If the staging project has no asymmetric Auth signing key, either rotate it to
an ES256/RS256 signing key before this run or explicitly configure the legacy
HS256 secret as `GAMETIME_LEGACY_JWT_SECRET`. Never use the public JWKS as the
attestation challenge secret. After any signing-key rotation, refresh the
staging user's session (or sign in again) before copying its access token; a
pre-rotation HS256 session is intentionally not accepted by a JWKS-only
deployment.

Because the gateway's legacy JWT verifier is disabled, prove the deployed
code-level verifier rejects requests before processing their bodies. Export
`STAGING_PUBLISHABLE_KEY`, then require both an absent and a forged bearer token
to receive 401 on all three paths:

```bash
api_base="https://${SUPABASE_PROJECT_REF}.supabase.co/functions/v1"
for endpoint in attest-device/challenge ingest-metrics ingest-checkin; do
  unauthenticated_status="$(
    curl --silent --output /dev/null --write-out '%{http_code}' \
      --request POST \
      --header "apikey: ${STAGING_PUBLISHABLE_KEY}" \
      "${api_base}/${endpoint}"
  )"
  forged_status="$(
    curl --silent --output /dev/null --write-out '%{http_code}' \
      --request POST \
      --header "apikey: ${STAGING_PUBLISHABLE_KEY}" \
      --header 'Authorization: Bearer not.a.jwt' \
      "${api_base}/${endpoint}"
  )"
  if [ "$unauthenticated_status" != 401 ] || [ "$forged_status" != 401 ]; then
    echo "${endpoint}: expected 401/401, got ${unauthenticated_status}/${forged_status}" >&2
    exit 1
  fi
  echo "${endpoint}: rejects absent and forged tokens"
done
```

## 2. Install the deterministic staging fixture

Use the UUID from the staging user's access-token `sub` claim. The latitude and
longitude are test-envelope inputs; M6.5 validates App Attest transport, not
live Core Location collection, which belongs to M8.

```bash
export CONFORMANCE_LATITUDE=41.8781136
export CONFORMANCE_LONGITUDE=-87.6297982
./scripts/m6-5-install-staging-fixture.sh
```

The wrapper accepts only Supabase's direct database URL whose
`db.<project-ref>.supabase.co` host matches the checked-in staging identity.
The SQL requires an onboarded profile, replaces only a fixed row already
carrying the expected synthetic identity, and leaves the device key and its
counter intact across reruns.

Use these fixed values in the iOS target:

| Field | Value |
| --- | --- |
| Contest ID | `65000000-0000-4000-8000-000000000001` |
| Geofence ID | `65000000-0000-4000-8000-000000000003` |
| Latitude | The value supplied to the fixture |
| Longitude | The value supplied to the fixture |
| Participant time zone | `UTC` |

## 3. Configure the real iPhone target

Open `ios/GameTimeConformance/GameTimeConformance.xcodeproj` and select the
shared `GameTimeConformance` scheme.

In Signing & Capabilities:

- Select the Apple Developer team identified by `APPLE_TEAM_ID`.
- Set the bundle identifier to the exact `APPLE_BUNDLE_ID` uploaded to staging.
- Keep the App Attest entitlement at `development`.
- Select a trusted physical iPhone running iOS 18 or later. Do not select a
  simulator.

If Xcode reports that a Personal Team does not support App Attest, stop there.
Do not remove the entitlement to force an install: sign in with an account that
belongs to an Apple Developer Program team, enable App Attest for the explicit
App ID, and rerun the staging configuration with that team's ID.

Enter these runtime values in the target:

- Base URL: `https://<project-ref>.supabase.co`
- The project's publishable key or legacy anon key
- The staging user's current access token
- The fixed contest and geofence IDs above
- The fixture latitude and longitude
- Participant time zone: `UTC`

The target stores Apple's non-secret key-id string in its app `UserDefaults` and
reuses it if the app relaunches before attestation. A full smoke run includes
Apple's one-time certification of that key, so tap **Run conformance** only once
per generated key. To perform another complete run after a success, delete and
reinstall the app and deliberately register a new key; the fixture does not
alter the prior server-side key or counter.

## 4. Run the smoke sequence

Build and run the shared scheme on the physical device. Tap **Run conformance**
once. The target performs this sequence without re-encoding any
signed body:

1. Request the account-bound challenge.
2. Generate or reuse one App Attest key.
3. Hash the decoded challenge and register Apple's attestation.
4. Encode one production metric payload, generate an assertion over its exact
   bytes, submit it, then replay the identical request and assertion.
5. Encode one production check-in payload, generate the next assertion over its
   exact bytes, submit it, then replay the identical request and assertion.

Capture the complete on-screen result. Expected statuses and invariants:

| Operation | Expected |
| --- | --- |
| Challenge | `200`, 32-byte decoded challenge |
| Registration | `200`, `registered=true`, `environment=development`, returned only after independent receipt verification and its digest-bound database marker; category and bundle version shown on iOS 27+, explicitly unavailable on iOS 18–26 |
| Metric first send | `201`, `replayed=false`, one observation |
| Metric exact replay | `200`, same batch id, `replayed=true` |
| Check-in first send | `201`, `replayed=false`; with the fixture samples its outcome is `accepted` |
| Check-in exact replay | `200`, same check-in id, `replayed=true` |
| Counters | `0 < metricCounter < checkInCounter`; each replay shows the same assertion counter as its first send |

Counter gaps are allowed: Apple increments the key whenever it generates an
assertion, including an assertion that never reaches the server. Equality is
allowed only for an exact idempotent retry, which the database recognizes by
stable client id and payload digest before counter consumption.

## 5. Audit the stored result

Pass the key-id string printed by the iOS target to `psql`:

```bash
psql "$STAGING_DATABASE_URL" \
  -v conformance_user_id="$CONFORMANCE_USER_ID" \
  -v key_id_base64="$APP_ATTEST_KEY_ID"
```

Run:

```sql
with expected as (
  select decode(:'key_id_base64', 'base64') as key_id
)
select
  d.user_id = :'conformance_user_id'::uuid as owner_matches,
  d.environment,
  octet_length(d.public_key) as public_key_bytes,
  get_byte(d.public_key, 0) as public_key_prefix,
  extensions.digest(d.public_key, 'sha256') = expected.key_id as key_id_matches,
  d.sign_count as stored_counter,
  octet_length(r.initial_receipt) as initial_receipt_bytes,
  octet_length(r.current_receipt) as current_receipt_bytes,
  r.received_at as receipt_received_at,
  r.current_receipt_verified_at
from expected
join public.device_attestations d using (key_id)
join app.device_attestation_receipts r using (key_id);

select
  b.client_batch_id,
  b.attested,
  b.sign_count as metric_counter,
  b.observation_count
from public.ingest_batches b
where b.contest_id = '65000000-0000-4000-8000-000000000001'
  and b.user_id = :'conformance_user_id'::uuid;

select
  c.client_checkin_id,
  c.attested,
  c.sign_count as checkin_counter,
  c.outcome,
  c.location_count
from public.geofence_checkins c
where c.contest_id = '65000000-0000-4000-8000-000000000001'
  and c.user_id = :'conformance_user_id'::uuid;

select
  (select count(*) from public.ingest_batches where not attested)
    as unattested_metric_batches,
  (select count(*) from public.geofence_checkins where not attested)
    as unattested_checkins;
```

Required results:

- `owner_matches` and `key_id_matches` are true.
- `public_key_bytes = 65`, `public_key_prefix = 4`, and both receipt byte counts
  are positive.
- `current_receipt_verified_at` is non-null and is greater than or equal to
  `receipt_received_at`. A null value means registration did not complete.
- Exactly one metric batch and one check-in exist for the fixed contest.
- Both are attested, and `0 < metric_counter < checkin_counter = stored_counter`.
- Both unattested counts are zero.

## 6. Record the live observation

Commit this section only after the run succeeds:

```text
Run date (UTC):
Git commit:
Staging project ref:
iPhone model:
iOS version:
Xcode version:
Apple team / bundle id:
App build version:
Key id:
Attestation environment:
Validation category:
Metric assertion counter:
Check-in assertion counter:
Receipt byte count:
Receipt independently verified at:
Metric first/replay status:
Check-in first/replay status:
Unattested metric/check-in counts:
Operator:
```

The receipt verifier is exercised automatically with Apple's published receipt
vector and generated adversarial certificate/PKCS#7 fixtures. At runtime,
registration first quarantines the candidate with an immutable database capture
time. The server then completes every receipt check and calls a
`service_role`-only marker that row-locks the candidate and compares its SHA-256
digest before setting `current_receipt_verified_at`. Verification, parsing,
chain, binding, freshness, race, or marker failures all leave the timestamp
null. The remaining M6.5 gate is this physical-device/staging observation.

Do not commit access tokens, database URLs, Apple credentials, device/staging
receipts, or staging secret values. Apple's already-public documentation vector
is the only receipt fixture checked in. The project ref is nonsecret and
intentionally committed as the operational staging allowlist.
