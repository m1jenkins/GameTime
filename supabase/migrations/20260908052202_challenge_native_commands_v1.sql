-- One native request envelope across the new domain. Its dispatcher never
-- accepts service operations, fixture clocks, source facts or operator grants.
create function app.challenge_command_payload_v1(p jsonb) returns jsonb language plpgsql immutable set search_path='' as $$
begin
 if p->>'op'='redeem_link' then
  if p-array['op','token']<>'{}' or p->>'token' is null or p->>'token' !~ '^[a-f0-9]{64}$' then raise exception 'challenge_link_unavailable' using errcode='42501';end if;
  return jsonb_build_object('op','redeem_link','token_hash',encode(extensions.digest(p->>'token','sha256'),'hex'));
 end if;
 return p;
end $$;
create function public.challenge_command_v1(p_request_id uuid,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid;op text:=p_payload->>'op';allowed text[];result jsonb;canonical jsonb;saved app.challenge_requests_v1;begin
 a:=app.challenge_session_v1();
 if p_request_id is null or jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>16384 then raise exception 'challenge_invalid_request' using errcode='22023';end if;
 canonical:=app.challenge_command_payload_v1(p_payload);
 select * into saved from app.challenge_requests_v1 where actor_id=a and request_id=p_request_id;
 if found then if saved.payload is distinct from canonical then raise exception 'challenge_request_conflict' using errcode='22023';end if;return saved.response;end if;
 allowed:=case op when 'confirm_age' then array['op','confirmed'] when 'issue_link' then array['op','id'] when 'redeem_link' then array['op','token']
 when 'revoke_link' then array['op','id'] when 'report' then array['op','subject','reason'] when 'block' then array['op','subject']
 when 'join_community' then array['op','id','digest','consent'] end;
 if allowed is not null and (p_payload-allowed<>'{}' or not(p_payload ?& allowed)) then raise exception 'challenge_invalid_request' using errcode='22023';end if;
 case op
 when 'confirm_age' then result:=public.challenge_confirm_age_v1(p_request_id,(p_payload->>'confirmed')::boolean);
 when 'issue_link' then result:=public.challenge_issue_link_v1(p_request_id,(p_payload->>'id')::uuid);
 when 'redeem_link' then result:=public.challenge_redeem_link_v1(p_request_id,p_payload->>'token');
 when 'revoke_link' then result:=public.challenge_revoke_link_v1(p_request_id,(p_payload->>'id')::uuid);
 when 'report' then result:=public.challenge_report_v1(p_request_id,(p_payload->>'subject')::uuid,p_payload->>'reason');
 when 'block' then result:=public.challenge_block_v1(p_request_id,(p_payload->>'subject')::uuid);
 when 'join_community' then result:=public.challenge_join_community_v1(p_request_id,p_payload);
 when 'resolve','remove','suspend' then result:=public.challenge_operator_action_v1(p_request_id,p_payload);
 else result:=public.challenge_mutate_v1(p_request_id,p_payload);
 end case;
 return result;
end $$;
create function public.challenge_stop_command_v1(p_request_id uuid,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
begin return public.challenge_abandon_v1(p_request_id,app.challenge_command_payload_v1(p_payload));end $$;
revoke all on function app.challenge_command_payload_v1(jsonb),public.challenge_command_v1(uuid,jsonb),public.challenge_stop_command_v1(uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.challenge_command_v1(uuid,jsonb),public.challenge_stop_command_v1(uuid,jsonb) to authenticated;
