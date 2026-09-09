-- Recheck wall-clock expiry after acquiring the session lock. A qualifying
-- unchanged tuple may have waited past not_after before FOR SHARE returns.
-- Keep the shared lock: revocation/deletion that wins it still denies access.
create or replace function app.challenge_session_v1() returns uuid
language plpgsql set search_path = '' as $$
declare
 a uuid := auth.uid();
 live uuid;
 expires timestamptz;
begin
 perform 1 from app.challenge_runtime_v1 where singleton for update;
 if current_setting('role') <> 'authenticated' or not app.is_active_actor(a) then
  raise exception 'challenge_session_required' using errcode = '42501';
 end if;
 select id, not_after into live, expires from auth.sessions
  where id::text = auth.jwt()->>'session_id' and user_id = a
   and (not_after is null or not_after > clock_timestamp()) for share;
 if live is null or expires <= clock_timestamp() or not app.is_active_actor(a) then
  raise exception 'challenge_session_required' using errcode = '42501';
 end if;
 return a;
end $$;
-- CREATE OR REPLACE preserves the existing invoker mode and restricted ACL.
