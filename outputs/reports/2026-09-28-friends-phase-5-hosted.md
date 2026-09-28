# Friends Phase 5: hosted apply, backup and migrations

Applied September 28, 2026 to `gametime-p11b` (`lyushhqoednheqwzsmxh`) only,
from source `ca76092` on `main`, following the
[Phase 5 hosted runbook](../../docs/FRIENDS_PHASE5_HOSTED_RUNBOOK.md). Game
Time Dev ran it under Mason's September 27 standing approval for GameTime
changes to `gametime-p11b`. The CLI used a scratch copy of `supabase/` at
`ca76092`, byte-identical to Git and linked to p11b. The checkout's historical
link (`jrkzdttophnmkxjoyioo`) was not used.

**Stopped after step 1.** Step 2 needs the Sign in with Apple key, and it
isn't on the owner's Mac. Steps 3–5 wait for step 2's readback.

| Step | Result | Time (UTC) |
| --- | --- | --- |
| Blocker fix | `ca76092` on `main`, pushed | 11:59 |
| 6a backup | done | 12:01:53–12:05:08 |
| 1.1 history readback | passed | 12:06 |
| 1.2 D144 diff | passed | 12:07–12:10 |
| 1.3 history repair | done | 12:11:08–12:11:51 |
| 1.4 D143 and legacy grants | applied | 12:13:18–12:13:27 |
| 2 `delete-account` | **blocked**: no Apple key | — |
| 3 Apple provider and sign-up | not started | — |
| 4 private trial off | not started | — |
| 5 support access | not started | — |
| 7 saves check | precondition not met; read only | 12:20 |
| 6b backup and pause | recorded, read only | 12:18 |

## The blocker fix

`ca76092` makes `delete-account` read `GAMETIME_APPLE_CLIENT_ID` and
`GAMETIME_APPLE_CLIENT_SECRET`, since hosted secrets can't use the `SUPABASE_`
prefix. `.env.example` lists both. `config.toml`'s local Auth provider is
unchanged. `main` was fast-forwarded from `dd84f87` and pushed.

- `deno fmt`, `lint` and `check`, and the 14 `delete-account` tests, passed.
- A local boot with the new names answered GET with 400 "GET is not supported
  here" and an empty POST with 401 "sign in again". Without them, startup
  failed with a `ConfigError` naming `GAMETIME_APPLE_CLIENT_ID`.
- `scripts/weekly-local-verify.sh` passed at `ca76092`: 118 SQL files with
  5,306 assertions, 950 Deno tests, 187 Swift client core tests and the
  persisted weekly lifecycle smoke. Its disposable project was kept for 1.2,
  then stopped and removed.

## Goal fingerprint

The runbook's query, run before any write and after each write step:

| When | Goals | Goals MD5 | Commitments | Charges | Migrations |
| --- | --- | --- | --- | --- | --- |
| Before, 12:01:21 | 8 | `c3e8055af1ae33a0b917b999dfe8c53e` | 1 | none | 103 |
| After 1.3, 12:12:14 | 8 | same | 1 | none | 103 |
| After 1.4, 12:14:15 | 8 | same | 1 | none | 105 |
| Final, 12:21:47 | 8 | same | 1 | none | 105 |

The only change is the two migrations. Since the
[September 26 receipt](2026-09-26-friends-build1-settings.md), the owner left
the September 24 Steps goal (void), the committed Steps goal started
September 27, and two friend Activity minutes goals were created and cancelled.
All of that happened before this task. Two goals are active: Outdoor runs
(September 24 – October 1) and the committed Steps goal (September 27 –
October 4).

The settings were read at the end and are unchanged. The private trial is on
with device verification off. The allowlist is enforced with its six pairs,
account mode is on and links are off. Friend commands only, with a daily limit
of 20.

## Step 6a: backup

`supabase db dump` wrote three files through the scratch link. They're in the
owner's private folder, mode 700, outside every checkout.

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `schema.sql` | 1,971,125 | `21386b0aff1b21c103919c2b55ae2b1d8e6202cdc1f71afadbb99ca7055ceeb3` |
| `data.sql` | 8,367,430 | `cad27dded0b465e07054691119e537776713a5d6796090c25b45ed5e406ad91a` |
| `roles.sql` | 370 | `168a95a9c745af5ed4679751f90419ac9dc434240a213b03e32a06d5664c2308` |

All three are non-empty. The schema has 231 `CREATE TABLE`. The data file
copies 67 tables (59 in `app`, 5 in `auth`, 3 in `public`), including the
commitment agreements. `pg_dump` warned that a data-only restore of tables
with circular foreign keys needs `--disable-triggers`.

## Step 1: migration history, D143 and the legacy grants

### 1.1 and 1.2: read-only checks

- **History:** 103 rows ending `20260922230100` and `20260926024624`, with no
  `20260923070000`, `20260925000000` or `20260927120000`. `migration list`
  matched 102 versions. Only `20260926024624` was remote only, and only the
  three pending versions were local only. The whole D144 row was saved
  privately; its MD5 matches on hosted and on disk.
- **Stored text:** one statement, MD5 `4836b8f3ccdb5efa1536c138ab087964`, the
  same as `md5 -q` of `20260925000000_challenge_personal_commitment_v1.sql`.
  It was sent as written.
- **Live definitions:** the runbook's D144 fingerprint gave the same result on
  hosted (through both the CLI and the MCP) and on the local stack at
  `ca76092`.

| Kind | Count | MD5, hosted and local |
| --- | --- | --- |
| functions | 21 | `155dfe6445fc1b0c453894b1a384aaf5` |
| tables | 7 | `0e0e3a4e80d4cd1ca05bc6cacfb1383c` |
| triggers | 5 | `579c747c0eae9622f0f653a6cb846c6c` |

### 1.3: repair

`migration repair --status reverted 20260926024624`, then `--status applied
20260925000000`. Readback: `20260925000000` is on both sides,
`20260926024624` is gone, and only `20260923070000` and `20260927120000` are
local only. SQL still counted 103 rows and the goal fingerprint was unchanged.
The CLI stored the repaired row's statements from the file, split into 48;
the MCP had stored one.

### 1.4: push

**Preconditions.** Donation obligations 0, charities 0, nominations 0. Hosted
granted exactly what the
[legacy-grants inventory](2026-09-27-friends-phase-5-legacy-grants.md) lists,
all to `authenticated`, none to `anon` or PUBLIC:

- execute on `find_profile_by_handle`, `join_group_by_code` and
  `rotate_group_join_code`
- `friendships` select, insert, update and delete
- `blocks` select, insert and delete
- `groups` select and insert, plus the column grant update(`name`)
- `group_members` select and delete

The dry run listed exactly `20260923070000_retire_charity_v1.sql` and
`20260927120000_close_legacy_social_grants_v1.sql`, and
`db push --include-all` applied both.

**Readback.**

- 105 migrations. `migration list` matches all 105, with no differences.
- `charities`, `donation_obligations` and `contest_participants.charity_id` are
  gone.
- `anon` and `authenticated` can't execute the three functions or use the four
  tables. The `groups.name` column grant is gone too.
- `postgres` and `service_role` keep their table privileges.
  `list_my_friendship_cards` stays executable by `authenticated`. The 16
  legacy policies stay.
- `authenticated` can execute all 10 `friend_*_v1` commands.
- The D144 fingerprint is unchanged, and the goal fingerprint changed only by
  the 2 migrations.

**Advisors and logs afterwards.** The security advisor lists 182 INFO
"RLS enabled, no policy", 154 WARN "security definer function executable by
authenticated" and 1 WARN on leaked-password protection, which doesn't apply
because there are no password accounts. None of them names the charity objects
or the three closed functions. No advisor snapshot was taken before, so this
is not a before-and-after comparison. The performance advisor is INFO only: 77
unindexed foreign keys and 125 unused indexes, on existing tables. Postgres
logged 156 entries from 12:00 to 12:20, all `LOG` with SQLSTATE `00000`, and
the cron ticks kept completing through the push.

## Step 2: blocked on the Apple key

Preconditions 1 and 2 hold. The fix is at `ca76092`. `GAMETIME_ENV`'s listed
digest equals the SHA-256 of `staging`, both Stripe test keys are set, and no
`GAMETIME_APPLE_*` secret exists yet. Precondition 3 fails, because there is no
Sign in with Apple key to sign the client secret with. No secret was set and
nothing was deployed.

Searched, reading file names and labels only, never key contents:

- Spotlight, for files named `AuthKey_*` or `*.p8` and for text mentioning
  `AuthKey_`.
- The whole home folder by name (`*.p8`, `AuthKey*`, Sign in with Apple key
  names), including `~/GameTime-private`, Documents, Desktop, Downloads and
  iCloud Drive with its `.icloud` placeholders. Only caches, simulators and
  Docker data were skipped. Mounted volumes and the Trash were checked too.
- PEM private-key headers in those folders plus `~/.config`,
  `~/.appstoreconnect` and the Firstmate workspace. The only hits were the test
  keys in `deliver-push/apns*.ts` and archived copies of them.
- 115 env files that aren't templates: none sets an Apple client ID, secret or
  key.
- Keychain item labels in the login and System keychains, filtered for Apple
  key and client-secret terms: nothing relevant.
- **Not searched:** a full listing of keychain secure-note and key labels,
  which this session's permission policy refused, and the Passwords app and
  iCloud Keychain, which can't be read from here.

**To unblock.** The owner finds or creates a key with Sign in with Apple
enabled for `com.mjenkins.gametime`, team `87Z29RTC26` (Apple Developer →
Certificates, Identifiers & Profiles → Keys). Apple offers the `.p8` for
download only once, so a lost key means creating a new one. An App Store
Connect API key has the same `AuthKey_<KEY ID>.p8` name but gets
`invalid_client`. Save the file outside Git, for example in
`~/GameTime-private/` with mode 600, and pass on its key ID. Then run the
runbook from 2.1.3 on, from `ca76092` or later. Deploy with `--use-api`,
`--import-map …/deno.json` and `--no-verify-jwt`. Record the secret's issue
and expiry dates here, never the secret itself.

## Steps 3–5: not started

Each needs step 2's readback first. Sign-up stays closed, because it opens only
once deletion works. The private trial stays on and there is no support grant.

## Step 7: precondition not met

Read-only. Taking `CUTOVER` as the last step 1 write, 12:13:27, there are no
Health saves after it. The latest save on hosted is September 26 16:35 UTC. In
the 24 hours to 12:30, `ingest-challenge-health` (version 8) returned 17
responses of 422 and one of 401, and no 200s. That fits the phone still running
the Staging build from `b86a006`, which can't get past the refused upload
([receipt](2026-09-27-health-refused-upload.md)). Installing a build from
`dff4be9` or later is a separate device approval. The Outdoor runs goal takes
updates only until its corrections close on October 3 05:00 UTC.

## Step 6b: backup and pause

- **Plan:** Free.
- **Backups:** `supabase backups list` shows none, and point-in-time recovery is
  off, so the step 6a dump is the only backup. The dashboard page wasn't
  opened.
- **Project:** active and healthy, Postgres 17.6. Pause warnings arrive by
  email, which can't be checked from here.
- **Open owner decision:** stay on Free, with a dump before each hosted write
  and a weekly dump during the test, or move to Pro, which is a paid change.

## Not changed

No Edge Function deploy, secret, Auth or Apple provider setting, sign-up,
trial, allowlist, runtime switch, support grant, enrollment or data row. The
deployed functions are unchanged: worker, snapshot and monitor at version 5,
`attest-device` 4, `ingest-challenge-health` 8 and the three commitment
functions 3. `delete-account` is still not deployed. No Stripe, App Store
Connect or TestFlight action.

## Rollback

- **1.3:** restore the saved D144 row, as in the runbook's 1.3 rollback.
- **1.4 grants:** re-grant what the saved pre-push ACLs record. The column
  grant isn't in the table ACL; it needs `grant update (name) on public.groups
  to authenticated;`.
- **D143:** no down migration. The dropped tables were empty, so rolling back
  means a new forward migration from the saved schema, with its own approval.

The readbacks that name accounts, goals, IDs or secrets' digests stay on the
owner's Mac in `~/GameTime-private/p11b-phase5-20260928/`, mode 700, with the
dump and its `dump.sha256`.
