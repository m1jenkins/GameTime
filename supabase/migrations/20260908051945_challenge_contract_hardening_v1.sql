-- Forward changes in the new domain only. Old agreements remain byte-identical.
create or replace function app.challenge_session_v1() returns uuid language plpgsql set search_path='' as $$
declare a uuid:=auth.uid(); live uuid;begin
 perform 1 from app.challenge_runtime_v1 where singleton for update;
 if current_setting('role')<>'authenticated' or not app.is_active_actor(a) then raise exception 'challenge_session_required' using errcode='42501';end if;
 -- A logout/revocation that wins this lock rejects the request. Otherwise the
 -- authorized transaction finishes before revocation, never after it unnoticed.
 select id into live from auth.sessions where id::text=auth.jwt()->>'session_id' and user_id=a
  and (not_after is null or not_after>clock_timestamp()) for share;
 if live is null then raise exception 'challenge_session_required' using errcode='42501';end if;
 return a;
end $$;
create function app.challenge_personal_terms_v1(a uuid,p_policy text,p_config jsonb,p_target bigint) returns jsonb language plpgsql set search_path='' as $$
declare pol jsonb:=app.challenge_policy_v1(p_policy);cfg jsonb;begin
 if pol->>'mode'<>'personal' or p_target is null or p_target not between 1 and 1000000000 then raise exception 'challenge_invalid_target' using errcode='22023';end if;
 cfg:=app.challenge_window_v1(p_config,app.challenge_now_v1());
 if (pol->>'metric'='timed')<>(cfg ? 'distance_mm') then raise exception 'challenge_distance_required_for_timed' using errcode='22023';end if;
 return jsonb_build_object('policy',p_policy,'source',pol->>'source','mode','personal','competition','goal','metric',pol->>'metric','unit',pol->>'unit','comparator',pol->>'comparator',
 'config',cfg,'version',1,'participants',jsonb_build_array(jsonb_build_object('actor_id',a,'target',p_target)),
 'simulation','nonredeemable','review_hours',48,'resolution_hours',72,'missing_rule','exclude_refund_minimum','exit_rule','exclude_refund_minimum','minimum',1,
 'allocation_rule','return_qualifiers_split_misses_remainder_unallocated');
end $$;
create function public.challenge_personal_preview_v1(p_policy text,p_config jsonb,p_target bigint) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid;terms jsonb;begin
 a:=app.challenge_session_v1();terms:=app.challenge_personal_terms_v1(a,p_policy,p_config,p_target);
 return jsonb_build_object('terms',terms,'digest',encode(extensions.digest(terms::text,'sha256'),'hex'));
end $$;
create function app.challenge_personal_commit_v1(a uuid,p jsonb) returns jsonb language plpgsql set search_path='' as $$
declare terms jsonb;cfg jsonb;pol jsonb;cid uuid:=extensions.gen_random_uuid();c app.challenge_lobbies_v1;digest text;n timestamptz:=app.challenge_now_v1();begin
 perform app.challenge_admit_v1(a);
 if p-array['op','policy','config','target','digest','consent']<>'{}' or not(p ?& array['op','policy','config','target','digest','consent'])
 or p->'consent' is distinct from 'true'::jsonb or jsonb_typeof(p->'target') is distinct from 'number' or p->>'target' !~ '^[0-9]+$' then raise exception 'challenge_consent_mismatch' using errcode='22023';end if;
 terms:=app.challenge_personal_terms_v1(a,p->>'policy',p->'config',(p->>'target')::bigint);
 digest:=encode(extensions.digest(terms::text,'sha256'),'hex');cfg:=terms->'config';pol:=app.challenge_policy_v1(p->>'policy');
 if p->>'digest' is distinct from digest then raise exception 'challenge_consent_mismatch' using errcode='22023';end if;
 if not exists(select 1 from app.challenge_readiness_v1 where actor_id=a and metric=pol->>'metric' and recorded_at between n-(case when pol->>'metric'='timed' then interval '90 days' else interval '30 days' end) and n) then raise exception 'challenge_readiness_required' using errcode='42501';end if;
 perform id from public.profiles where id=a for update;perform app.challenge_session_v1();
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_lobbies_v1(id,creator_id,policy,config,starts_at,ends_at,status,created_at,minimum,capacity,agreement_version)
 values(cid,a,p->>'policy',cfg,(cfg->>'starts_at')::timestamptz,(cfg->>'ends_at')::timestamptz,'scheduled',n,1,1,1) returning * into c;
 perform app.challenge_slot_v1(a,c);
 insert into app.challenge_members_v1(challenge_id,actor_id,selected,target) values(cid,a,true,(p->>'target')::bigint);
 insert into app.challenge_slots_v1 values(cid,a,'personal',pol->>'metric',c.starts_at,c.ends_at);
 insert into app.challenge_agreements_v1(challenge_id,version,terms,created_at) values(cid,1,terms,n);
 insert into app.challenge_consents_v1 values(cid,1,a,digest,n);
 return jsonb_build_object('id',cid,'revision',c.revision,'status','scheduled');
end $$;
do $$ declare definition text;begin
 definition:=pg_get_functiondef('public.challenge_mutate_v1(uuid,jsonb)'::regprocedure);
 definition:=replace(definition,' allowed:=case op', E' if op=''personal_commit'' then\n  result:=app.challenge_personal_commit_v1(a,p_payload);\n  insert into app.challenge_requests_v1 values(a,p_request_id,p_payload,result,app.challenge_now_v1());return result;\n end if;\n allowed:=case op');
 definition:=replace(definition,'if pol->>''mode''=''community'' then','if pol->>''mode''<>''friend'' then');
 definition:=replace(definition,'if op in (''invite'',''select'') and pol->>''mode''<>''friend''', 'if op in (''invite'',''select'',''configure'',''target'',''freeze'',''reopen'') and pol->>''mode''<>''friend''');
 definition:=replace(definition,'cfg:=app.challenge_window_v1(p_payload->''config'',c.created_at);', E'cfg:=app.challenge_window_v1(p_payload->''config'',c.created_at);\n   if (pol->>''metric''=''timed'')<>(cfg ? ''distance_mm'') then raise exception ''challenge_distance_required_for_timed'' using errcode=''22023'';end if;');
 definition:=replace(definition,'''participants'',jsonb_agg(jsonb_build_object(''actor_id'',actor_id,''target'',target) order by actor_id)', '''participants'',jsonb_agg(jsonb_strip_nulls(jsonb_build_object(''actor_id'',actor_id,''target'',target)) order by actor_id)');
 definition:=replace(definition,'''metric'',pol->>''metric'',''unit'',pol->>''unit'',''config''', '''metric'',pol->>''metric'',''unit'',pol->>''unit'',''comparator'',pol->>''comparator'',''config''');
 execute definition;
 definition:=pg_get_functiondef('app.challenge_tick_v1(uuid,boolean)'::regprocedure);
 definition:=replace(definition,'if notice.challenge_id is null then', 'if notice.challenge_id is null or notice.result is distinct from result then');
 definition:=replace(definition,'values(p_id,1,result,n,n+interval ''48 hours'')','values(p_id,coalesce(notice.revision,0)+1,result,n,n+interval ''48 hours'')');
 execute definition;
 definition:=pg_get_functiondef('public.challenge_grant_operator_v1(uuid,uuid,text,timestamptz)'::regprocedure);
 definition:=replace(definition,'if not app.is_active_actor(p_actor)', 'if p_actor is null or p_id is null or p_expires is null or p_capability is null or app.challenge_actor_unavailable_v1(p_actor)');execute definition;
 definition:=pg_get_functiondef('public.challenge_operator_cases_v1(uuid)'::regprocedure);
 definition:=replace(definition,'if not exists(', 'if app.challenge_actor_unavailable_v1(a) or not exists(');execute definition;
end $$;
revoke all on function app.challenge_personal_terms_v1(uuid,text,jsonb,bigint),app.challenge_personal_commit_v1(uuid,jsonb),public.challenge_personal_preview_v1(text,jsonb,bigint) from public,anon,authenticated,service_role;
grant execute on function public.challenge_personal_preview_v1(text,jsonb,bigint) to authenticated;
-- Avoid PL/pgSQL ambiguity with the member's goal column named target.
do $$ declare definition text;begin
 definition:=pg_get_functiondef('public.challenge_operator_action_v1(uuid,jsonb)'::regprocedure);
 definition:=regexp_replace(definition,'\mtarget\M','subject_actor','g');
 execute definition;
end $$;
