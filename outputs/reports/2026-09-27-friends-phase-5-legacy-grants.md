# Friends Phase 5: close dormant legacy grants

Written and verified locally on September 27, 2026, on branch
`claude/audit-pack`. The migration is
`supabase/migrations/20260927120000_close_legacy_social_grants_v1.sql` and the
proof is `supabase/tests/535_close_legacy_social_grants.test.sql`. **Not
applied to hosted.** Hosted migration history doesn't match the repo (see the
[build 1 settings receipt](2026-09-26-friends-build1-settings.md)), so no
migration can go up until that history is repaired. Nothing was pushed.

## Inventory

These are all the `anon` and `authenticated` grants on the legacy social graph,
read from a fresh local replay of every migration. `anon` held none of them.

| Grant to `authenticated` | Callers in `ios/` | Callers in `supabase/functions/` | Build 1 or Personal need | Decision |
| --- | --- | --- | --- | --- |
| execute `find_profile_by_handle(text)` | `SupabaseFriendshipsClient.findExactHandle`, reached only behind `legacySocialRuntimeEnabled` | none | none; build 1 uses `friend_lookup_v1`, which has the 30-per-minute cap | **revoked** |
| execute `join_group_by_code(text)` | none | none | none | **revoked** |
| execute `rotate_group_join_code(uuid)` | none | none | none | **revoked** |
| `friendships` select, insert, update, delete | `requestFriendship`, `acceptFriendship`, `removeFriendship`, all behind `legacySocialRuntimeEnabled` | none | none; the friend commands are security definer | **revoked** |
| `blocks` select, insert, delete | none | none | none; `friend_block_v1` and `challenge_block_v1` are security definer | **revoked** |
| `groups` select, insert, update(name) | none | none | none | **revoked** |
| `group_members` select, delete | none | none | none | **revoked** |
| execute `list_my_friendship_cards()` | `AppModel` behind `legacySocialRuntimeEnabled`; `DuelStore` and `WeeklyStore`, both loopback-only experiments | none | none in build 1, but the loopback experiments still read it | kept; read-only over the caller's own pairs |
| `profiles` select, insert and update of listed columns | profile setup and the Personal profile | none | Personal profile setup | kept |

`legacySocialRuntimeEnabled` is false everywhere except the explicit
`AppConfiguration.fixture` for V2 regression tests. No row-level policy, view
or security-invoker function outside these four tables reads them, so closing
the grants can't break another table's policy. The 16 legacy policies stay in
place behind the closed grants. The service role's grants are unchanged.

Out of scope: the duel, weekly, performance-following and legacy contest RPCs.
They are separate dormant products with their own admission switches and
loopback-only native transport. D134 retires them later.

## Test changes

- **535** proves the revocations, including PUBLIC and column grants. It also
  checks that every friend command works with `commands_only` both off and on,
  as do a friends challenge (create, invite by username, freeze, agree, list),
  `challenge_block_v1` and a personal goal preview. On the Personal side it
  covers own-profile read and rename, plus `create_personal_challenge_v2`,
  `list_my_accountability_challenges_v2` and `cancel_personal_challenge_v1`.
  With the old grants restored, 13 of its assertions fail.
- Historical files 010, 020, 030, 040, 080, 170, 475, 480, 482 and 529 still
  exercise the policies, triggers and functions behind the old grants. Each
  restores exactly the old set inside its own rolled-back transaction, using
  `supabase/tests/fixtures/legacy-social-grants.inc`. The three assertions that
  named the old grants now assert they are gone.
- The dblink race files 476 and 481 now do their raw unfriend and block as the
  table owner, since a dblink session can't see a rolled-back grant.
- `scripts/friends-local-http.ts` accepts either the grant refusal or the
  `commands_only` refusal for direct writes. It also checks over HTTP that
  `find_profile_by_handle` is closed.

## Verification

| Check | Result |
| --- | --- |
| `scripts/weekly-local-verify.sh` at `fd4e976` | passed: 118 SQL files / 5,306 assertions, 950 Deno tests, Swift core, persisted weekly lifecycle smoke; disposable project `gametime-weekly-verify.jek8nj1u`, stopped |
| `scripts/friends-local-verify.sh` at `fd4e976` | passed: 140 HTTP checks, including the closed lookup; disposable project stopped |

A dev replay before the final run hit one failure in
`527_private_account_health`. That file passed alone three times with the
grants closed and passed in the final full run. It looks order-dependent and is
unrelated to these grants. It's noted here in case it recurs.

## Before applying to hosted

1. Repair hosted migration history (prompt 5).
2. Read back the grants on `gametime-p11b` and compare them with this
   inventory.
3. Apply the migration with the owner's approval, then read back the ACLs that
   535 checks.
