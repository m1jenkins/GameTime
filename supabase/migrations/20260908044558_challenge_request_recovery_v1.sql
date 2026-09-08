-- Atomically fence an unsent/failed exact action. If it already committed, return
-- its original receipt; otherwise a durable tombstone prevents a late arrival.
create function public.challenge_abandon_v1(p_request_id uuid,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid; saved app.challenge_requests_v1; result jsonb:='{"status":"cancelled_request"}'; begin
 if p_request_id is null or jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>16384 then raise exception 'challenge_invalid_request' using errcode='22023'; end if;
 a:=app.challenge_session_v1();
 select * into saved from app.challenge_requests_v1 where actor_id=a and request_id=p_request_id;
 if found then
  if saved.payload is distinct from p_payload then raise exception 'challenge_request_conflict' using errcode='22023'; end if;
  return saved.response;
 end if;
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_requests_v1 values(a,p_request_id,p_payload,result,app.challenge_now_v1());
 return result;
end $$;
revoke all on function public.challenge_abandon_v1(uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.challenge_abandon_v1(uuid,jsonb) to authenticated;
