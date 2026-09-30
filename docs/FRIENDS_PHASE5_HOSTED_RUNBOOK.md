# Friends Phase 5: hosted runbook

Written September 27, 2026, from source and receipts only. Steps 6a and 1 ran
on September 28 ([receipt](../outputs/reports/2026-09-28-friends-phase-5-hosted.md)).
Steps 2, 4 and 5 ran that evening; step 3 then ran at 22:27 UTC
([applied receipt](../outputs/reports/2026-09-28-phase5-steps2-5.md#step-3-applied)).
Apple-only sign-up is open and both app bundles are configured. Do not repeat
completed hosted writes. Step 7 still requires the phone's build identity and
successful real saves. The
[September 30 readiness receipt](../outputs/reports/testflight-readiness-2026-09-30/README.md)
distinguishes current read-only verification from the dated instructions below.
Every step is a hosted read or write on `gametime-p11b`
(`lyushhqoednheqwzsmxh`), and each one needs the approval named in it. Approval
for one step doesn't cover the next. This runbook is a plan: it doesn't
authorize a push, a deployment, an Apple change or TestFlight.

Scope: the rest of Phase 5 in the [friends plan](FRIENDS_TESTFLIGHT_PLAN.md#phase-5--hosted-in-progress)
and the D142 finish line (`DECISIONS.md`, D142 **Finish line**).

## Before you start

**The code blocker is fixed** in `ca76092` (September 28). `delete-account`
read its Apple settings from `SUPABASE_AUTH_EXTERNAL_APPLE_CLIENT_ID` and
`SUPABASE_AUTH_EXTERNAL_APPLE_SECRET`. Hosted Supabase reserves the
`SUPABASE_` prefix (`supabase/functions/_shared/env.ts:76`), and
`supabase secrets set` in CLI 2.109.1 skips those names with "Env name cannot
start with SUPABASE_, skipping". Hosted doesn't inject them either, so the
function would have failed at startup on `requireEnv`. It now reads
`GAMETIME_APPLE_CLIENT_ID` and `GAMETIME_APPLE_CLIENT_SECRET`
(`supabase/functions/delete-account/index.ts:29-35`), and `.env.example` lists
both. `config.toml:330-332` is unchanged, because it configures local Auth,
not the function.

**Order.** 6a (backup) → 1 (migrations) → 2 (`delete-account`) → 3 (Apple and
sign-up) → 4 (trial off) → 5 (support) → 7 (saves check) → 6b (record). Steps 3
and 4 belong in one sitting. Sign-up is opened only after deletion works.
Friends who sign up can't take part until the trial is off
([Sept 26 receipt](../outputs/reports/2026-09-26-friends-build1-settings.md),
"Can a friend who isn't enrolled take part?").

**Shared setup.** Run these on the owner's Mac. `SRC` is the `main` commit that
contains this runbook, both pending migrations and the blocker fix.

```sh
export P11B=lyushhqoednheqwzsmxh
export REPO=/Users/user/Documents/GitHub/GameTime
export SRC=<approved main commit>
export PRIV="$HOME/GameTime-private/p11b-phase5-$(date -u +%Y%m%d)"   # outside Git
mkdir -p "$PRIV" && chmod 700 "$PRIV"

# A scratch copy of supabase/ at SRC, linked to p11b. The checkout's own link
# points at the historical jrkzdttophnmkxjoyioo, so it's never used.
export SCRATCH="$(mktemp -d /tmp/p11b-phase5.XXXXXXXX)"
git -C "$REPO" archive "$SRC" supabase | tar -x -C "$SCRATCH"
( cd "$SCRATCH" && git -C "$REPO" ls-tree -r --name-only "$SRC" supabase |
  while read -r f; do git -C "$REPO" show "$SRC:$f" | cmp -s - "$f" || echo "DIFF $f"; done )
# Expect no output.
supabase link --project-ref "$P11B" --workdir "$SCRATCH"
# Leave the database password empty. The CLI uses its temporary login role, as
# on September 23; no password is stored.
```

Hosted SQL runs through the Supabase MCP `execute_sql` with the project ref
`lyushhqoednheqwzsmxh` named, as `postgres`. Wrap reads in
`begin read only; … rollback;`. Readbacks that name accounts, goals or Stripe
objects go to `$PRIV`, never into Git; the repo is public.

**Goal fingerprint.** Run this before step 1 and after every write step. The
result must stay the same apart from the changes each step expects. The owner
has an active Steps goal with a $20 sandbox commitment (Sep 27 – Oct 4 UTC).

```sql
begin read only;
select
  (select count(*) from app.challenge_lobbies_v1) as goals,
  (select md5(string_agg(concat_ws('|', id, policy, status, revision, agreement_version,
     starts_at, ends_at), E'\n' order by id)) from app.challenge_lobbies_v1) as goals_md5,
  (select count(*) from app.challenge_commitment_agreements_v1) as commitments,
  (select coalesce(jsonb_object_agg(status, n), '{}') from
     (select status, count(*) n from app.challenge_commitment_charges_v1 group by status) c) as charges,
  (select count(*) from supabase_migrations.schema_migrations) as migrations;
rollback;
```

The goal status and revision change on their own as time passes: the
Outdoor runs goal ends October 1 05:00 UTC. Compare any change against its
schedule before treating it as damage.

## Step 6a: take a backup before any write

**Why first.** Supabase backs up Pro, Team and Enterprise projects daily; the
docs don't list Free, and recommend `supabase db dump` for Free projects
([Database Backups](https://supabase.com/docs/guides/platform/backups)). D143
in step 1 drops tables. This dump is the only rollback this runbook has.

**Approval.** A hosted read that copies personal and Health data to the Mac.

**Precondition.** `$PRIV` exists with mode 700 and lies outside every Git
checkout and synced folder.

```sh
supabase db dump --linked --workdir "$SCRATCH" -f "$PRIV/schema.sql"
supabase db dump --linked --workdir "$SCRATCH" --data-only -f "$PRIV/data.sql"
supabase db dump --linked --workdir "$SCRATCH" --role-only -f "$PRIV/roles.sql"
shasum -a 256 "$PRIV"/*.sql > "$PRIV/dump.sha256"
```

**Readback.** All three files are non-empty.
`grep -c 'challenge_commitment_agreements_v1' "$PRIV/data.sql"` is at least 1.
`grep -c 'CREATE TABLE' "$PRIV/schema.sql"` is in the hundreds. Keep
`dump.sha256`.

**Rollback.** None needed; this writes nothing to hosted. Delete the dump once
TestFlight no longer needs it.

## Step 1: repair the migration history, then push D143 and the grants

**The state.** Hosted recorded D144 as `20260926024624` (applied through the
MCP, which stamps the current time). The repo names it `20260925000000`.
Hosted lacks `20260923070000_retire_charity_v1` (D143)
([Sept 26 receipt](../outputs/reports/2026-09-26-friends-build1-settings.md),
"Observed, not changed"). `20260927120000_close_legacy_social_grants_v1` is
also pending.

**Don't follow the CLI's suggestion.** `db push` refuses while hosted has a
version the repo lacks. It suggests `migration repair --status reverted
20260926024624` and then `--include-all`. That would re-run D144 against objects
that already exist and fail on the first `create table`. The plan below also
marks `20260925000000` applied, so the push skips it.

D143 and D144 share no functions. Checked in source: D143 creates, replaces or
drops 13 functions and D144 21, with no overlap. The legacy-grants migration
touches neither.

**Approval.** 1.1 and 1.2 are reads. 1.3 writes to the migration history only.
1.4 applies two migrations. Ask for each separately, or for 1.3 and 1.4
together once 1.2 passes.

### 1.1 Read back the history and save the D144 row

```sql
begin read only;
select version, name from supabase_migrations.schema_migrations
where version >= '20260920' order by version;
rollback;
```

Expect 103 rows in total, ending with `20260922230100` and `20260926024624`.
There should be no `20260923070000`, `20260925000000` or `20260927120000`. Then
save the whole D144 row, which the rollback in 1.3 needs:

```sql
begin read only;
select to_jsonb(m) from supabase_migrations.schema_migrations m where version = '20260926024624';
rollback;
```

Save it as `$PRIV/d144-history-row.json`. Then:

```sh
supabase migration list --linked --workdir "$SCRATCH"
```

Expect `20260926024624` on the remote only, and `20260923070000`,
`20260925000000` and `20260927120000` local only.

### 1.2 Diff hosted D144 against the migration file (read-only)

**(a) Stored text.** This is quick, but it doesn't decide the diff.

```sql
begin read only;
select coalesce(array_length(statements, 1), 0) as statement_count,
       md5(array_to_string(statements, E'\n')) as statements_md5
from supabase_migrations.schema_migrations where version = '20260926024624';
rollback;
```

Compare the result with
`md5 -q "$SCRATCH/supabase/migrations/20260925000000_challenge_personal_commitment_v1.sql"`.
A match with one statement means the file was sent as written. A mismatch can
be a whitespace difference, so (b) decides.

**(b) Live definitions.** Run the same query on hosted and on a disposable
local stack built from `SRC`, then compare. On the local stack, D143 runs
before D144 and the grants migration after it. None of them touch D144's
objects, so the fingerprints must be equal.

```sql
-- BEGIN d144-fingerprint
begin read only;
with fns as (
  select p.oid::regprocedure::text as k, md5(pg_get_functiondef(p.oid)) as h,
         coalesce(array_to_string(p.proacl, ','), '') as acl
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('app', 'public')
    and (p.proname like 'challenge_commitment%'
         or p.proname in ('challenge_personal_commit_v1', 'challenge_evaluate_v1'))
), tabs as (
  select c.oid::regclass::text as k, c.relrowsecurity::text as rls,
         coalesce(array_to_string(c.relacl, ','), '') as acl,
         (select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' ||
            a.attnotnull || ':' || coalesce(pg_get_expr(d.adbin, d.adrelid), ''), ',' order by a.attnum)
          from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
          where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped) as cols,
         (select string_agg(k2.conname || '=' || pg_get_constraintdef(k2.oid), ',' order by k2.conname)
          from pg_constraint k2 where k2.conrelid = c.oid) as cons,
         (select string_agg(pg_get_indexdef(i.indexrelid), ',' order by i.indexrelid::regclass::text)
          from pg_index i where i.indrelid = c.oid) as idx
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'app' and c.relkind = 'r' and c.relname like 'challenge_commitment%'
), trg as (
  select tgrelid::regclass::text || '.' || tgname as k, md5(pg_get_triggerdef(oid)) as h
  from pg_trigger where not tgisinternal and tgname like 'challenge_commitment%'
)
select 'functions' as kind, count(*), md5(string_agg(k || h || acl, '|' order by k)) from fns
union all
select 'tables', count(*), md5(string_agg(k || rls || acl || coalesce(cols, '') ||
  coalesce(cons, '') || coalesce(idx, ''), '|' order by k)) from tabs
union all
select 'triggers', count(*), md5(string_agg(k || h, '|' order by k)) from trg;
rollback;
-- END d144-fingerprint
```

Expected counts are functions 21, tables 7 and triggers 5 (four immutability
triggers plus `challenge_commitment_final`). The local side:

```sh
awk '/^-- BEGIN d144-fingerprint/,/^-- END d144-fingerprint/' \
  "$REPO/docs/FRIENDS_PHASE5_HOSTED_RUNBOOK.md" > "$PRIV/d144-fingerprint.sql"
# From a clean checkout at SRC. Leaves only its own disposable project running.
WEEKLY_VERIFY_PORT_BASE=57320 scripts/weekly-local-verify.sh --keep-stack
psql "postgresql://postgres:postgres@127.0.0.1:57322/postgres" -f "$PRIV/d144-fingerprint.sql"
supabase stop --workdir <printed verification directory> --no-backup
```

**Pass.** All three rows match on both sides. **Fail.** Any row differs. Then
stop and change nothing. To find the object, replace the final `select … union
all …` with `select 'fn', k, h || acl from fns union all select 'tab', k, rls ||
acl || cols || coalesce(cons,'') || coalesce(idx,'') from tabs union all select
'trg', k, h from trg order by 1, 2`. Run it on both sides and diff the output.
A real difference needs its own forward migration and owner approval before
any repair.

### 1.3 Repair the history

**Preconditions.** 1.1 matches, 1.2 passes, and the step 6a dump exists.

```sh
supabase migration repair --status reverted 20260926024624 --linked --workdir "$SCRATCH"
supabase migration repair --status applied  20260925000000 --linked --workdir "$SCRATCH"
```

**Readback.** Run `supabase migration list --linked --workdir "$SCRATCH"`.
`20260925000000` is on both sides and `20260926024624` is gone. Only
`20260923070000` and `20260927120000` are local only. SQL still counts 103
rows. The goal fingerprint is unchanged: repair touches
`supabase_migrations.schema_migrations` only.

**Rollback.** Restore the saved row:

```sql
begin;
delete from supabase_migrations.schema_migrations where version = '20260925000000';
insert into supabase_migrations.schema_migrations
select * from jsonb_populate_record(null::supabase_migrations.schema_migrations,
  '<contents of $PRIV/d144-history-row.json>'::jsonb);
commit;
```

### 1.4 Push D143 and the legacy-grant closure

**Preconditions**, all read-only:

```sql
begin read only;
select
  (select count(*) from public.donation_obligations) as obligations,      -- must be 0; D143 refuses otherwise
  (select count(*) from public.charities) as charities,
  (select count(*) from public.contest_participants where charity_id is not null) as nominations,
  (select jsonb_object_agg(f, coalesce(array_to_string(p.proacl, ','), 'default'))
     from unnest(array['public.find_profile_by_handle(text)', 'public.join_group_by_code(text)',
                       'public.rotate_group_join_code(uuid)']) f
     join pg_proc p on p.oid = f::regprocedure) as function_acl,
  (select jsonb_object_agg(t, coalesce(array_to_string(c.relacl, ','), 'default'))
     from unnest(array['public.friendships', 'public.blocks', 'public.groups', 'public.group_members']) t
     join pg_class c on c.oid = t::regclass) as table_acl;
rollback;
```

Save the result as `$PRIV/pre-push-acl.json`. Compare the ACLs with the
[legacy-grants inventory](../outputs/reports/2026-09-27-friends-phase-5-legacy-grants.md).
Stop if hosted grants something the inventory doesn't list. If charities or
nominations aren't 0, D143 drops data: stop, and ask the owner.

```sh
supabase db push --dry-run --include-all --linked --workdir "$SCRATCH"
```

The dry run must list exactly `20260923070000_retire_charity_v1.sql` and
`20260927120000_close_legacy_social_grants_v1.sql`. Anything else stops the run.
`--include-all` is needed because `20260923070000` sorts before the last
applied version.

```sh
supabase db push --include-all --linked --workdir "$SCRATCH"
```

**Readback.**

```sql
begin read only;
select
  (select count(*) from supabase_migrations.schema_migrations) as migrations,   -- 105
  to_regclass('public.charities') is null as charities_gone,
  to_regclass('public.donation_obligations') is null as obligations_gone,
  not exists (select 1 from information_schema.columns where table_schema = 'public'
    and table_name = 'contest_participants' and column_name = 'charity_id') as nomination_gone,
  (select jsonb_agg(jsonb_build_object('role', r, 'object', f,
     'execute', has_function_privilege(r, f, 'execute')))
   from unnest(array['anon', 'authenticated']) r,
        unnest(array['public.find_profile_by_handle(text)', 'public.join_group_by_code(text)',
                     'public.rotate_group_join_code(uuid)']) f) as functions,  -- all false
  (select jsonb_agg(jsonb_build_object('role', r, 'object', t,
     'any', has_table_privilege(r, t, 'select,insert,update,delete')))
   from unnest(array['anon', 'authenticated']) r,
        unnest(array['public.friendships', 'public.blocks', 'public.groups', 'public.group_members']) t) as tables,  -- all false
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname like 'friend\_%\_v1'
     and has_function_privilege('authenticated', p.oid, 'execute')) as friend_rpcs;  -- 10
rollback;
```

Also run the goal fingerprint (migrations +2, otherwise unchanged) and
`supabase migration list` (no differences left).

**Rollback.**
- Grants: re-grant exactly what `$PRIV/pre-push-acl.json` recorded, for
  example `grant execute on function public.find_profile_by_handle(text) to
  authenticated;`, for each entry that the push removed. The table ACL doesn't
  show column grants; hosted also had `grant update (name) on public.groups to
  authenticated;`.
- D143 has no down migration. The preconditions proved that the dropped tables
  held nothing, so rolling back means writing a new forward migration from
  `$PRIV/schema.sql`. No data needs restoring. That needs its own approval.

## Step 2: deploy `delete-account`

**What it needs.** The function takes exactly one Apple client ID and one
client secret. It uses them for the token exchange and the revocation
(`delete-account/apple.ts:66-67`, `:102-103`). The ID is
`com.mjenkins.gametime`, the TestFlight and Release bundle (`project.pbxproj`
build phase). The secret must be generated for that ID. Never pass a
comma-separated list. The Auth provider's client ID setting (`config.toml:330`,
and step 3) is a list and used to share the variable name. The function sends
the whole string to Apple as `client_id`, and Apple refuses it.

**Approval.** Setting two function secrets, and deploying one new function.

### 2.1 Preconditions

1. The blocker fix is on `main` at `SRC`.
2. **Environment and Stripe.** D144 set Stripe test keys on p11b. With both
   keys present, `delete-account` builds a Stripe client at startup
   (`index.ts:13-24`). That client throws if `GAMETIME_ENV` is `production`
   (`_shared/stripe_sandbox.ts:16-21`), and the function never boots.

   ```sh
   supabase secrets list --project-ref "$P11B" -o json > "$PRIV/secrets-before.json"
   jq -r '.[].name' "$PRIV/secrets-before.json" | sort
   printf %s staging | shasum -a 256
   jq -r '.[] | select(.name=="GAMETIME_ENV") | .value' "$PRIV/secrets-before.json"
   ```

   Expect `GAMETIME_ENV`, `STRIPE_SECRET_KEY` and `STRIPE_PUBLISHABLE_KEY` among
   the names. `GAMETIME_ENV`'s listed digest should equal the SHA-256 of
   `staging`. If it doesn't, confirm the value in the dashboard. If it's
   `production`, stop: either the Stripe keys are unset first, which breaks
   the three D144 functions, or the environment stays `staging`. **Standing
   rule:** p11b's `GAMETIME_ENV` can't become `production` while the Stripe
   test keys are set.
3. **Generate the secret on the Mac.** You need the Sign in with Apple key
   (`.p8`, outside Git), its key ID and team `87Z29RTC26`. Apple caps the
   lifetime at 6 months; this uses 180 days. On September 28 the key wasn't
   on the owner's Mac (receipt, "Step 2"). It must be a key with Sign in with
   Apple enabled: an App Store Connect API key has the same file name and
   gets `invalid_client`.

   ```sh
   APPLE_P8=/path/outside/git/AuthKey_XXXX.p8 APPLE_KEY_ID=XXXX python3 - <<'PY' > "$PRIV/apple-secret.jwt"
   import os, time, jwt   # PyJWT and cryptography, in a venv outside the repo
   now = int(time.time())
   print(jwt.encode({"iss": "87Z29RTC26", "iat": now, "exp": now + 180 * 86400,
                     "aud": "https://appleid.apple.com", "sub": "com.mjenkins.gametime"},
                    open(os.environ["APPLE_P8"]).read(), algorithm="ES256",
                    headers={"kid": os.environ["APPLE_KEY_ID"]}))
   PY
   chmod 600 "$PRIV/apple-secret.jwt"
   ```

   **Check it with Apple.** This goes to Apple, not hosted:

   ```sh
   curl -sS https://appleid.apple.com/auth/token -d client_id=com.mjenkins.gametime \
     --data-urlencode "client_secret@$PRIV/apple-secret.jwt" -d code=not-a-real-code \
     -d grant_type=authorization_code
   ```

   Expect `{"error":"invalid_grant"}`, which means the client was accepted.
   `invalid_client` means the key, team or `sub` is wrong.

   **Record** the issue and expiry dates (UTC), who renews, and the renewal
   date (expiry minus 14 days) in the Phase 5 receipt. Never record the secret
   itself. Who renews is an open owner input.

### 2.2 Set the secrets and deploy

```sh
umask 077
{ echo "GAMETIME_APPLE_CLIENT_ID=com.mjenkins.gametime"
  echo "GAMETIME_APPLE_CLIENT_SECRET=$(cat "$PRIV/apple-secret.jwt")"; } > "$PRIV/apple.env"
grep -c , <(head -1 "$PRIV/apple.env")    # must print 0
supabase secrets set --env-file "$PRIV/apple.env" --project-ref "$P11B"
rm "$PRIV/apple.env"

supabase functions deploy delete-account --project-ref "$P11B" --workdir "$SCRATCH" \
  --use-api --import-map "$SCRATCH/supabase/functions/deno.json" --no-verify-jwt
```

`--no-verify-jwt` matches `config.toml` (`[functions.delete-account]
verify_jwt = false`); the handler verifies the caller itself. Without the
import map the bundle can't resolve its imports (D144).

### 2.3 Readback, without deleting anyone

```sh
supabase secrets list --project-ref "$P11B" -o json | jq -r '.[].name' | sort
supabase functions list --project-ref "$P11B"
curl -sS -w '\n%{http_code}\n' -X GET "https://$P11B.supabase.co/functions/v1/delete-account"
curl -sS -w '\n%{http_code}\n' -X POST -H 'content-type: application/json' -d '{}' \
  "https://$P11B.supabase.co/functions/v1/delete-account"
```

Expect:
- Both new secret names are listed.
- `delete-account` is `ACTIVE`. The other eight functions keep their code:
  `secrets set` restarts every function and bumps its version by one (seen
  September 28), so compare `ezbr_sha256` and `updated_at` in
  `functions list -o json` before and after, not the version.
- The GET returns 400 with "GET is not supported here". This shows the module
  loaded: the Apple settings were found and the Stripe setup passed.
- The empty POST returns 401 with "sign in again", before any database call.

A 5xx or `BOOT_ERROR` means it failed at startup; check the function logs and
roll back. Never send an Apple authorization code, a real session token or a
real deletion receipt as a check. The first real deletion is a tester's own
choice from a TestFlight build.

**Staging stops deleting.** A Staging build signs in as
`com.mjenkins.gametime.staging`, so the function's exchange with the
production ID fails. The exchange runs before the deletion request is saved
(`handler.ts`, `exchangeAuthorizationCode` before `database.begin`). The
account is left unchanged and the app shows an error. Don't delete an account
from Staging. Deletion works again for the owner once they switch to TestFlight
and delete Staging, which Phase 6 already plans. Retiring Staging closes this.

**Also seen in source.** Account deletion doesn't cover D144 rows. Deletion
reads the legacy Personal sandbox customer only
(`20260812194559_account_deletion_provider_lookup.sql:22`). The
`app.challenge_commitment_*` rows and their Stripe test customer have no
foreign key to the account and would be left behind. Only the owner has such
rows, and D144 is out of build 1. This is logged here; it doesn't block this
step.

**Rollback.** `supabase functions delete delete-account --project-ref "$P11B"`
and `supabase secrets unset GAMETIME_APPLE_CLIENT_ID GAMETIME_APPLE_CLIENT_SECRET
--project-ref "$P11B"`. After that, don't leave sign-up open (step 3).

## Step 3: Apple provider and sign-up

**Approval.** An Apple provider change and opening sign-up, both named in
D142's Boundaries.

**Preconditions.** Step 2 passed. The `SUPABASE_ACCESS_TOKEN` personal access
token is in the environment, not in a file in any checkout. Read back first:

```sh
AUTH="https://api.supabase.com/v1/projects/$P11B/config/auth"
KEYS='{external_apple_enabled, external_apple_client_id, disable_signup, external_email_enabled,
  external_phone_enabled, external_anonymous_users_enabled, security_manual_linking_enabled}'
curl -sS -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" "$AUTH" | jq "$KEYS" > "$PRIV/auth-before.json"
cat "$PRIV/auth-before.json"
```

Only these keys are saved; the full response includes provider secrets.
`external_apple_client_id` must contain `com.mjenkins.gametime.staging`. The
owner is still on Staging, so it stays. If any key comes back `null`, the API
names differ from this runbook: stop and use the dashboard instead
(Authentication → Sign In / Providers).

**Change.** Append the production ID and keep the existing order:

```sh
IDS="$(jq -r '.external_apple_client_id' "$PRIV/auth-before.json"),com.mjenkins.gametime"
jq -n --arg ids "$IDS" '{external_apple_enabled: true, external_apple_client_id: $ids,
  disable_signup: false, external_email_enabled: false, external_phone_enabled: false,
  external_anonymous_users_enabled: false, security_manual_linking_enabled: false}' > "$PRIV/auth-patch.json"
curl -sS -X PATCH -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H 'content-type: application/json' --data @"$PRIV/auth-patch.json" "$AUTH" | jq "$KEYS"
```

Here a comma-separated list is correct: this is the Auth provider, which
accepts several client IDs. Native sign-in with an ID token doesn't use the
provider's secret field. On September 28 the owner asked for it to be set to
the same client secret anyway, so the OAuth flow is complete. Add
`external_apple_secret` to the patch from the file
(`jq --rawfile s "$PRIV/apple-secret.jwt"`), never on the command line, and
renew it together with the function secret.

**Readback.** Run the GET again. The result is the patch values, with both
bundle IDs in the list. On the phone, the Staging app still signs in.
Sign-up can't be tested with a new person until a TestFlight build exists
(Phase 6).

**Rollback.** PATCH `{"disable_signup": true, "external_apple_client_id":
"<value from auth-before.json>"}`. Accounts that already exist keep signing in.

## Step 4: turn off the private trial

D142 keeps no per-person allowlist (`DECISIONS.md`, D142 **Access**), so turning
the trial off follows from D142. Only the timing is the owner's call. Do it in
the same sitting as step 3.

**Approval.** The owner's approval of the timing.

**Precondition.** The per-policy allowlist has to be enforced. With the trial
off and the allowlist not enforced, every real policy opens, community
included (plan, "The trial guard"). Read back:

```sql
begin read only;
select
  (select to_jsonb(t) from app.challenge_private_device_trial_v1 t) as trial,
  (select to_jsonb(r) from app.challenge_policy_runtime_v1 r) as policy_runtime,
  (select jsonb_agg(policy || '/' || source_policy_version order by policy)
     from app.challenge_policy_allowlist_v1) as allowlist,
  (select to_jsonb(f) from app.friend_runtime_v1 f) as friend_runtime,
  (select count(*) from app.challenge_private_device_accounts_v1) as enrolled;
rollback;
```

Required values:
- Trial: `enabled` true, `require_device_verification` false.
- Policy runtime: `allowlist_enforced` true, `account_mode` true,
  `links_enabled` false.
- Allowlist: exactly the six build 1 pairs, the four `friend_*_goal_v1` plus
  `personal_steps_goal_v1` and `personal_distance_goal_v1`.
- Friend runtime: `commands_only` true.
- Enrolled accounts: 1.

**Change.** The guard is inside the statement, so the update fails closed:

```sql
update app.challenge_private_device_trial_v1 set enabled = false
where singleton and enabled
  and exists (select 1 from app.challenge_policy_runtime_v1
              where singleton and allowlist_enforced and account_mode and not links_enabled)
returning enabled;
```

Expect exactly one row with `enabled = false`. Zero rows means a precondition
changed: stop.

**Readback.** Run the precondition query again. Only `trial.enabled` has
changed. Then check what the owner is offered through the owner's live session,
as on September 26. The IDs come from step 5.1.

```sql
-- Not read only: challenge_session_v1 locks the session row FOR SHARE.
begin;
select set_config('request.jwt.claims', json_build_object('sub', '<OWNER_ID>',
  'role', 'authenticated', 'session_id', '<SESSION_ID>')::text, true);
set local role authenticated;
select public.challenge_availability_v1();
rollback;
```

Expect:
- `restricted` true, `account_allowed` true.
- `verification_mode` `private_account`, which account mode now provides.
- The six policies.
- `links` false, `community` false.

The goal fingerprint is unchanged. Leave the enrolled row alone: it has no
effect with the trial off, and deleting it would delete data.

**Rollback.** `update app.challenge_private_device_trial_v1 set enabled = true
where singleton;`. Accounts that aren't enrolled then lose new real-activity
actions and uploads, including in goals they already agreed to.

## Step 5: support access with no new code

`scripts/beta-operator.py` can't be used here. It talks only to `127.0.0.1` and
signs in with a local password (`beta-operator.py:49`, `:241-242`), and hosted
has no password accounts. Everything below goes through the MCP as `postgres`.
`postgres` passes the service check on service functions
(`20260904225326_duel_agreement_v1.sql:222-227`: role `none` and
`session_user = 'postgres'`).

**Approval.** Each grant or renewal, each suspension and the end-of-test revoke
are hosted writes. Reading the queue writes one audit row.

### 5.1 Find the owner's IDs (read-only, kept in `$PRIV`)

```sql
begin read only;
select a.actor_id,
  (select s.id from auth.sessions s where s.user_id = a.actor_id
     and (s.not_after is null or s.not_after > now())
   order by coalesce(s.refreshed_at, s.updated_at, s.created_at) desc limit 1) as session_id
from app.challenge_private_device_accounts_v1 a;
rollback;
```

This returns one row today. Once sign-up opens, take the owner's ID from this
saved result, not from a fresh "only account" query. The session ID is the
phone's live session, so fetch it again each time you use it.

### 5.2 Weekly support grant (at most 7 days)

Use the audited, idempotent path: `challenge_admin_request_v2` saves a receipt
and calls `challenge_grant_support_v1`, which enforces the 7-day limit and
writes the audit row (`20260919023548_challenge_admin_request_v2.sql:18-104`;
`20260912013929_challenge_private_community_v1.sql:257-265`). Before calling,
pick both values and write them into `$PRIV/support-log.md`:

```sh
uuidgen | tr A-Z a-z                       # REQUEST_ID
date -u -v+6d -v+23H +%Y-%m-%dT%H:%M:%SZ   # EXPIRES, under the 7-day limit
```

```sql
select public.challenge_admin_request_v2('<REQUEST_ID>'::uuid,
  jsonb_build_object('version', 'challenge_admin_request_v2', 'operation', 'grant_support',
                     'actor_id', '<OWNER_ID>', 'expires_at', '<EXPIRES>'));
```

A retry with the same two values returns the saved receipt. Changing either
one with the same request ID fails with `challenge_request_conflict`.
`duel_service_required` means the MCP isn't running as `postgres`: stop.

**Readback.**

```sql
begin read only;
select
  (select expires_at from app.challenge_support_grants_v1 where actor_id = '<OWNER_ID>') as expires_at,
  (select response from app.challenge_admin_requests_v2 where request_id = '<REQUEST_ID>') as receipt,
  (select payload from app.challenge_operator_audit_v1 where operator_id = '<OWNER_ID>'
     and payload->>'op' = 'grant_global_support' order by recorded_at desc limit 1) as audit;
rollback;
```

**Renewal.** Once a week, with a new request ID and a new expiry, before the
old one lapses. Set a calendar reminder for the expiry date minus a day. A new
grant replaces the expiry.

**Revoke** at the end of the test, or to roll back. Use a new request ID:

```sql
select public.challenge_admin_request_v2('<NEW_REQUEST_ID>'::uuid,
  jsonb_build_object('version', 'challenge_admin_request_v2', 'operation', 'revoke_support',
                     'actor_id', '<OWNER_ID>'));
```

### 5.3 Read the report queue as the owner

This runs in the owner's own session, so the `read_global_reports` audit row
names the owner. It ends in `commit` so that row is kept.

```sql
begin;
select set_config('request.jwt.claims', json_build_object('sub', '<OWNER_ID>',
  'role', 'authenticated', 'session_id', '<SESSION_ID>')::text, true);
set local role authenticated;
select public.challenge_support_reports_v1(null, null);
commit;
```

A page holds at most 100 reports. For the next page, pass the last row's
`created_at` and `id` together. Readback: the newest `read_global_reports` row
in `app.challenge_operator_audit_v1` for the owner. `challenge_support_required`
means the grant has lapsed (5.2).

### 5.4 Suspending an account

Before calling, write these into `$PRIV/support-log.md`:
- the request ID (`uuidgen`)
- the account being suspended
- the reason: `username`, `unwanted_contact` or `unsafe_behavior`
- the report IDs that led to it

The request ID is what makes a retry safe. Reuse it if the call's outcome is
unclear.

```sql
begin;
select set_config('request.jwt.claims', json_build_object('sub', '<OWNER_ID>',
  'role', 'authenticated', 'session_id', '<SESSION_ID>')::text, true);
set local role authenticated;
select public.challenge_support_suspend_v1('<REQUEST_ID>'::uuid, '<SUBJECT_ID>'::uuid, '<REASON>');
commit;
```

**Readback.** Check `select suspended, reason, recorded_at from
app.challenge_suspensions_v1 where actor_id = '<SUBJECT_ID>'`. Also check that
`app.challenge_operator_audit_v1` has a row with `id = '<REQUEST_ID>'`. The
person's unfinished challenges take their safe exits.

**No rollback while the owner is the only support person.** Reinstating goes
through an appeal, and the appeal must be decided by someone other than the
person who suspended (`20260912013929…:352-360`,
`challenge_independent_support_required`). Suspend only when needed. A second
support person is an open owner input.

## Step 7: confirm Steps and outdoor distance still save

This is D142's hosted acceptance for this build: a real hosted save for Steps
and for outdoor distance after deployment.

**Preconditions.**
- The phone runs a build from `dff4be9` or later. The September 27 refusal
  receipt found no successful upload after September 26 16:35 UTC and an
  installed build without recovery
  ([receipt](../outputs/reports/2026-09-27-health-refused-upload.md)). Check the
  current installation before deciding it needs an update. If needed, update
  the same Staging bundle in place, preserving its account and journal, after
  device approval. Do not install a second uploading bundle for this account.
- Take `CUTOVER` as the UTC time of the last write in steps 1–4.
- Timing: the Outdoor runs goal (Sep 24 – Oct 1) takes updates only until its
  corrections close on October 3 05:00 UTC. After that, a new outdoor-distance
  goal is needed. It can be a friend goal once testers join.

**Approval.** Read-only.

```sql
begin read only;
select l.policy, count(*) as saves, max(f.recorded_at) as latest,
       jsonb_agg(distinct r.verification_mode) as modes, jsonb_agg(distinct f.state) as states
from app.challenge_real_health_facts_v1 f
join app.challenge_lobbies_v1 l on l.id = f.challenge_id
join app.challenge_real_health_requests_v1 r on r.request_id = f.request_id
where f.recorded_at > '<CUTOVER>'::timestamptz
group by l.policy order by l.policy;
rollback;
```

**Pass.** At least one save after `CUTOVER` for a Steps policy and one for a
distance policy (`*_steps_goal_v1`, `*_distance_goal_v1`). Mode
`private_account`. The Edge Function logs for `ingest-challenge-health` show
200s and no new `binding_invalid` refusals. **Record** only the counts and
times, not the values. Activity minutes and timed runs get their first hosted
saves from the first tester challenges (D142).

**Rollback.** None; this writes nothing.

## Step 6b: backup and pause on the Free plan

**Where to check.**
- **Plan:** Dashboard → Organization → Billing. The MCP's `get_organization`
  also shows it.
- **Backups:** Dashboard → Database → Backups. Record whether it lists any
  scheduled backup. Supabase's docs list daily backups for Pro, Team and
  Enterprise only, so on Free expect none. The step 6a dump is then the only
  backup.
- **Pause:** Supabase pauses Free projects after about a week of low activity.
  It emails a warning about a week ahead. A paused project can be resumed from
  the dashboard for 90 days
  ([Project Pausing](https://supabase.com/docs/guides/platform/free-project-pausing)).
  While paused, the app gets HTTP 540 and nothing saves. Record the project's
  status (MCP `get_project`) and whether any pause warning has arrived.

**Record** these in the Phase 5 receipt:
- the plan
- what the Backups page shows
- the dump's time, files and SHA-256 (not the contents)
- the pause findings
- the owner's decision: accept Free with a dump before each hosted write and a
  weekly dump during the test, or move to Pro

Moving to Pro is a paid change, and a separate owner decision.

## Recording

Write one receipt, `outputs/reports/<date>-friends-phase-5-hosted.md`, with
each step's time, source commit, readbacks and anything skipped. Leave out IDs,
secrets, targets and Health values. Then update Phase 5 in the plan and add a
`docs/WORKING_BASELINE.md` entry. Readbacks with IDs stay in `$PRIV`.
