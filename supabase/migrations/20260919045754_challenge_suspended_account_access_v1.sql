-- Suspension restricts operations, not proof of the caller's identity. The
-- deletion migration widened this session fence to actor_unavailable, which
-- also denied status, appeals, own history, safe exits and review requests.
-- is_active_actor still rejects accepted deletion tombstones, deleted/missing
-- profiles, missing Auth principals and missing profile/Auth bindings.
--
-- Keep challenge_actor_unavailable_v1 unchanged: admission, discovery, social
-- redaction/safe reconciliation and independent operator/support authorization
-- must continue to treat suspension as unavailable. Exact saved receipts still
-- authenticate before replay; fresh operations retain their own authorization.
begin;

create or replace function app.challenge_session_v1()
returns uuid language plpgsql set search_path = '' as $$
declare a uuid := auth.uid(); live uuid; expires timestamptz;
begin
 if current_setting('role') <> 'authenticated' or a is null or not app.is_active_actor(a) then
  raise exception 'challenge_session_required' using errcode='42501';
 end if;
 select id,not_after into live,expires from auth.sessions
 where id::text=auth.jwt()->>'session_id' and user_id=a
  and (not_after is null or not_after>clock_timestamp()) for share;
 -- Recheck after the session row lock: elapsed expiry or identity deletion
 -- while waiting must not admit a stale JWT, including exact receipt retries.
 if live is null or expires<=clock_timestamp() or not app.is_active_actor(a) then
  raise exception 'challenge_session_required' using errcode='42501';
 end if;
 return a;
end $$;

commit;
