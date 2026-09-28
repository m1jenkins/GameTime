-- Friends plan Phase 5: close the dormant legacy social grants.
--
-- D142 build 1 reaches friends only through the friend_*_v1 commands, which
-- are security definer and hold their own checks, request IDs and limits. The
-- older direct paths stayed open to every signed-in account:
--
--   find_profile_by_handle   exact-handle lookup with no rate limit, so it
--                            sidestepped friend_lookup_v1's 30-per-minute cap
--   join_group_by_code,      groups have no build 1 surface
--   rotate_group_join_code
--   friendships, blocks,     direct select and writes under row-level policy;
--   groups, group_members    commands_only guards only friendships and blocks
--                            writes, and only once an operator sets it
--
-- No build 1, Personal or Edge function path calls any of them. The only
-- native caller is the legacy social client behind legacySocialRuntimeEnabled,
-- which is off outside explicit V2 regression fixtures.
--
-- Kept on purpose:
--   profiles direct select/insert/update, used by Personal profile setup;
--   list_my_friendship_cards, read-only over the caller's own pairs and still
--   read by the loopback-only duel and weekly experiments until D134 retires
--   them.
--
-- Definer functions, the challenge block, account deletion and the service
-- role keep their access; only anon and authenticated lose it. Row-level
-- policies stay in place so any later grant is still filtered. No data moves.

revoke execute on function public.find_profile_by_handle(text),
                           public.join_group_by_code(text),
                           public.rotate_group_join_code(uuid)
  from public, anon, authenticated;

revoke all on public.friendships, public.blocks, public.groups, public.group_members
  from anon, authenticated;
