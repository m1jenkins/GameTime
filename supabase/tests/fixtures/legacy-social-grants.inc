-- 20260927120000 closed the dormant legacy social grants; 535 proves they are
-- gone. Historical files that still exercise the row-level policies, triggers
-- and functions behind those grants restore exactly the old set inside their
-- own rolled-back transaction. Include it as the table owner, never from a
-- dblink session, so nothing outlives the file.
grant select, insert, update, delete on public.friendships to authenticated;
grant select, insert, delete on public.blocks to authenticated;
grant select, insert on public.groups to authenticated;
grant update (name) on public.groups to authenticated;
grant select, delete on public.group_members to authenticated;
grant execute on function public.find_profile_by_handle(text),
                          public.join_group_by_code(text),
                          public.rotate_group_join_code(uuid)
  to authenticated;
