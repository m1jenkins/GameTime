begin;
select no_plan();

-- D141 focused synthetic checks using the existing real-ingestion fixture helpers.
-- No hosted resource or physical activity is used.
create or replace function app.challenge_real_health_now_v1()
returns timestamptz language sql volatile set search_path='' as $$
 select coalesce(nullif(current_setting('test.p9_matrix_now',true),'')::timestamptz,clock_timestamp())
$$;
select set_config('test.p9_matrix_now','2026-10-03 12:00:00+00',true);
insert into auth.users(id) select ('bf000000-0000-0000-0000-'||lpad((780+i)::text,12,'0'))::uuid from generate_series(1,7)i;
insert into public.profiles(id,handle,display_name,timezone)
select id,'p9matrix'||right(id::text,3),'Synthetic Matrix','UTC' from auth.users where id::text like 'bf000000-0000-0000-0000-00000000078%';
insert into auth.sessions(id,user_id)
select ('ba000000-0000-0000-0000-'||lpad((780+i)::text,12,'0'))::uuid,
       ('bf000000-0000-0000-0000-'||lpad((780+i)::text,12,'0'))::uuid from generate_series(1,7)i;
create function pg_temp.ma(n integer) returns uuid language sql as $$select ('bf000000-0000-0000-0000-'||lpad((780+n)::text,12,'0'))::uuid$$;
create function pg_temp.ms(n integer) returns uuid language sql as $$select ('ba000000-0000-0000-0000-'||lpad((780+n)::text,12,'0'))::uuid$$;
insert into public.device_attestations(key_id,user_id,public_key,environment)
select extensions.digest(decode('04'||repeat(lpad(i::text,2,'0'),64),'hex'),'sha256'),pg_temp.ma(i),decode('04'||repeat(lpad(i::text,2,'0'),64),'hex'),'development' from generate_series(1,6)i;
insert into app.device_attestation_receipts(key_id,initial_receipt,current_receipt,current_receipt_verified_at)
select key_id,'\x01','\x01',clock_timestamp() from public.device_attestations where user_id in(select pg_temp.ma(n) from generate_series(1,6)n);
select public.challenge_real_health_runtime_v1(true,true,true);
select set_config('request.jwt.claim.sub',pg_temp.ma(1)::text,true);
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.ma(1),'session_id',pg_temp.ms(1))::text,true);
select set_config('role','authenticated',true);
select public.challenge_confirm_age_v1('ba000000-0000-0000-0000-000000000781',true);
select set_config('role','none',true);

create function pg_temp.source(p_metric text) returns text language sql immutable as $$
 select case p_metric when 'steps' then 'apple_watch_steps_v1' when 'exercise' then 'apple_watch_exercise_credit_v2'
 when 'distance' then 'apple_workout_outdoor_distance_v1' else 'apple_workout_outdoor_timed_v1' end
$$;
create function pg_temp.matrix_room(p_policy text,p_people integer default 2,p_minimum integer default 2) returns uuid language plpgsql as $$
declare cid uuid:=extensions.gen_random_uuid(); metric text:=split_part(p_policy,'_',2); mode text:=split_part(p_policy,'_',1);
 people integer:=case when mode='personal' then 1 else p_people end; source text:=pg_temp.source(metric); terms jsonb; i integer;
begin
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_lobbies_v1(id,creator_id,policy,config,starts_at,ends_at,status,agreement_version,created_at,minimum,capacity,real_source_policy_version)
 values(cid,pg_temp.ma(1),p_policy,jsonb_build_object('amount_cents',100)||case when metric='timed' then '{"distance_mm":5000000}'::jsonb else '{}' end,
 '2026-10-03 00:00:00+00','2026-10-04 00:00:00+00','active',1,'2026-10-01 00:00:00+00',case when mode='personal' then 1 else p_minimum end,6,source);
 terms:=jsonb_build_object('policy',p_policy,'metric',metric,'source',source,'source_policy_version',source,'simulation','nonredeemable',
  'config',jsonb_build_object('starts_at','2026-10-03 00:00:00+00','ends_at','2026-10-04 00:00:00+00')||case when metric='timed' then '{"distance_mm":5000000}'::jsonb else '{}' end);
 terms:=terms||app.challenge_received_leaderboard_terms_v2(p_policy);
 insert into app.challenge_agreements_v1(challenge_id,version,terms,created_at) values(cid,1,terms,'2026-10-01 00:00:00+00');
 for i in 1..people loop
  insert into app.challenge_members_v1(challenge_id,actor_id,selected,target)
  values(cid,pg_temp.ma(i),true,case when p_policy like '%_leaderboard_%' then null when metric='timed' then 1000 else 100 end);
  insert into app.challenge_slots_v1(challenge_id,actor_id,mode,metric,starts_at,ends_at)
  values(cid,pg_temp.ma(i),mode,metric,'2026-10-03 00:00:00+00','2026-10-04 00:00:00+00');
  insert into app.challenge_consents_v1 select cid,1,pg_temp.ma(i),digest,'2026-10-01 00:00:00+00' from app.challenge_agreements_v1 where challenge_id=cid;
 end loop;
 return cid;
end $$;
create function pg_temp.matrix_payload(cid uuid,actor integer,rev integer,val bigint,p_state text default 'value') returns jsonb language sql as $$
 select jsonb_build_object('contract_version',1,'actor_id',pg_temp.ma(actor),'challenge_id',c.id,'agreement_version',1,
 'terms_digest',a.digest,'source_policy_version',c.real_source_policy_version,'metric',split_part(c.policy,'_',2),
 'window_starts_at',c.starts_at,'window_ends_at',c.ends_at,'request_id',extensions.gen_random_uuid(),
 'revision',rev,'previous_revision',case when rev=1 then null else rev-1 end,'state',p_state,'value',val,
 'observed_at',app.challenge_real_health_now_v1(),'queried_through_at',least(c.ends_at,app.challenge_real_health_now_v1()))
 ||case when c.policy like '%_timed_%' then jsonb_build_object('distance_mm',(c.config->>'distance_mm')::bigint) else '{}'::jsonb end
 from app.challenge_lobbies_v1 c join app.challenge_agreements_v1 a on a.challenge_id=c.id and a.version=1 where c.id=cid
$$;
create function pg_temp.matrix_ingest(actor integer,p jsonb) returns jsonb language sql as $$
 select public.challenge_real_health_ingest_v1((p->>'request_id')::uuid,p,pg_temp.ms(actor),clock_timestamp()+interval '1 hour',key_id,sign_count+1,
 extensions.digest(convert_to(p::text,'UTF8'),'sha256'),false)
 from public.device_attestations where user_id=pg_temp.ma(actor)
$$;


create function pg_temp.received_scores() returns setof text language plpgsql as $$
declare metric text; cid uuid; result jsonb; p jsonb; saved jsonb; old_digest text;
begin
 foreach metric in array array['steps','exercise','distance','timed'] loop
  cid:=pg_temp.matrix_room('friend_'||metric||'_leaderboard_v2',3);
  perform pg_temp.matrix_ingest(1,pg_temp.matrix_payload(cid,1,1,900));
  perform pg_temp.matrix_ingest(2,pg_temp.matrix_payload(cid,2,1,1000));
  result:=app.challenge_real_health_evaluate_v1(cid);
  return next is(result->>'outcome','scored',metric||': saved partial history ranks');
  return next is(result->'participants'->pg_temp.ma(case when metric='timed' then 1 else 2 end)::text->>'status','winner',metric||': highest total / fastest saved run wins');
  return next is(result->'participants'->pg_temp.ma(3)::text->>'status','unranked',metric||': missing score is unranked');
  return next is(result->'participants'->pg_temp.ma(3)::text->>'returned_cents','100',metric||': missing score returns own entry');
  return next is((select sum((value->>'returned_cents')::int)::int from jsonb_each(result->'participants')),300,metric||': simulation conserved');
  return next ok(app.challenge_fact_projection_v1(cid,pg_temp.ma(3)) is null,metric||': absence is not numeric zero');
  -- Replacements are not accumulated or maxed with old values.
  perform pg_temp.matrix_ingest(2,pg_temp.matrix_payload(cid,2,2,900));
  result:=app.challenge_real_health_evaluate_v1(cid);
  return next is(result->'participants'->pg_temp.ma(1)::text->>'returned_cents','100',metric||': normalized ties share the valid pool');
  return next is(result->'participants'->pg_temp.ma(2)::text->>'returned_cents','100',metric||': correction replaces previous value');
  perform pg_temp.matrix_ingest(2,pg_temp.matrix_payload(cid,2,3,null,'deleted'));
  result:=app.challenge_real_health_evaluate_v1(cid);
  return next is(result->>'outcome','void',metric||': only one valid score voids');
  return next is((select sum((value->>'returned_cents')::int)::int from jsonb_each(result->'participants')),300,metric||': void returns all entries');
  cid:=pg_temp.matrix_room('friend_'||metric||'_leaderboard_v1',2);
  select digest into old_digest from app.challenge_agreements_v1 where challenge_id=cid;
  perform pg_temp.matrix_ingest(1,pg_temp.matrix_payload(cid,1,1,900));
  perform pg_temp.matrix_ingest(2,pg_temp.matrix_payload(cid,2,1,1000));
  return next is(app.challenge_real_health_evaluate_v1(cid)->>'outcome','void',metric||': old real leaderboard remains unresolved');
  return next is((select digest from app.challenge_agreements_v1 where challenge_id=cid),old_digest,metric||': old agreement stays unchanged');
 end loop;
 cid:=pg_temp.matrix_room('friend_steps_leaderboard_v2',3);
 perform set_config('test.p9_matrix_now','2026-10-06 00:00:00+00',true);
 p:=pg_temp.matrix_payload(cid,1,1,10);
 saved:=pg_temp.matrix_ingest(1,p);
 return next is(saved->>'revision','1','first score accepted exactly at correction cutoff');
 perform pg_temp.matrix_ingest(2,pg_temp.matrix_payload(cid,2,1,50));
 perform pg_temp.matrix_ingest(2,pg_temp.matrix_payload(cid,2,2,5));
 return next is(app.challenge_real_health_evaluate_v1(cid)->'participants'->pg_temp.ma(1)::text->>'status','winner','partial total ranks against corrected saved total');
 return next is((app.challenge_fact_projection_v1(cid,pg_temp.ma(2))->>'recorded_at')::timestamptz,'2026-10-06 00:00:00+00'::timestamptz,'projection reports server saved time');
 perform set_config('test.p9_matrix_now','2026-10-06 00:00:00.000001+00',true);
 return next throws_ok(format('select pg_temp.matrix_ingest(1,%L::jsonb)',pg_temp.matrix_payload(cid,1,2,10000)),'22023','challenge_invalid_real_health_revision','one microsecond late cannot replace saved score');
 return next throws_ok(format('select pg_temp.matrix_ingest(3,%L::jsonb)',pg_temp.matrix_payload(cid,3,1,10000)),'22023','challenge_invalid_real_health_revision','late first score remains unranked');
 perform public.challenge_real_health_runtime_v1(false,false,true);
 return next is((select public.challenge_real_health_ingest_v1(r.request_id,r.payload,pg_temp.ms(1),clock_timestamp()+interval '1 hour',r.device_key_id,r.assertion_counter,r.payload_digest,true)
  from app.challenge_real_health_requests_v1 r where r.request_id=(p->>'request_id')::uuid),saved,'lost reply recovers exact committed receipt after cutoff and gate closure');
 return next is(app.challenge_real_health_evaluate_v1(cid)->'participants'->pg_temp.ma(1)::text->>'status','winner','late rejection never overwrites the confirmed score');
 perform public.challenge_real_health_runtime_v1(true,true,true);
 return next is(public.challenge_process_v1(cid),'review','received scores use the existing review lifecycle');
 return next is((select review_by-recorded_at from app.challenge_notices_v1 where challenge_id=cid),interval '48 hours','actual notice starts full review period');
end $$;
select * from pg_temp.received_scores();

-- Authenticated creation and freezing must carry the new rule into the digest.
create function pg_temp.command(n integer,p jsonb) returns jsonb language plpgsql as $$
declare result jsonb;
begin
 perform set_config('request.jwt.claim.sub',pg_temp.ma(n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.ma(n),'session_id',pg_temp.ms(n))::text,true);
 perform set_config('role','authenticated',true);
 result:=public.challenge_mutate_v1(extensions.gen_random_uuid(),p);
 perform set_config('role','none',true);
 return result;
exception when others then perform set_config('role','none',true); raise;
end $$;
select set_config('test.p9_matrix_now','2026-10-01 12:00:00+00',true);
create function pg_temp.creation() returns setof text language plpgsql as $$
declare metric text; cid uuid; result jsonb; cfg jsonb; terms jsonb;
begin
 foreach metric in array array['steps','exercise','distance','timed'] loop
  cfg:='{"start_date":"2026-10-05","days":1,"timezone":"UTC","amount_cents":100}'::jsonb
    ||case when metric='timed' then '{"distance_mm":5000000}'::jsonb else '{}'::jsonb end;
  result:=pg_temp.command(1,jsonb_build_object('op','create','policy','friend_'||metric||'_leaderboard_v2','source_policy_version',pg_temp.source(metric),'config',cfg));
  cid:=(result->>'id')::uuid;
  return next is(result->>'status','lobby_open',metric||': new real version can create');
  return next throws_ok(format('select pg_temp.command(1,%L::jsonb)',jsonb_build_object('op','create','policy','friend_'||metric||'_leaderboard_v1','source_policy_version',pg_temp.source(metric),'config',cfg)),'22023','challenge_real_leaderboard_unavailable',metric||': old creation block stays');
  perform set_config('app.challenge_write_v1','on',true);
  insert into app.challenge_age_v1(actor_id,policy,confirmed_at) select pg_temp.ma(2),policy,clock_timestamp() from app.challenge_age_v1 where actor_id=pg_temp.ma(1) on conflict do nothing;
  insert into app.challenge_members_v1(challenge_id,actor_id,selected) values(cid,pg_temp.ma(2),true);
  -- Retire only the synthetic matrix slots so this independent lobby can freeze.
  delete from app.challenge_slots_v1 where challenge_id<>cid;
  result:=pg_temp.command(1,jsonb_build_object('op','freeze','id',cid,'revision',(select revision from app.challenge_lobbies_v1 where id=cid)));
  select a.terms into terms from app.challenge_agreements_v1 a where challenge_id=cid;
  return next is(terms->>'score_rule','received_by_correction_cutoff_v2',metric||': immutable agreement freezes received rule');
  return next is(terms->>'missing_rule','unranked_return_entry_minimum_two',metric||': consent includes missing-score treatment');
  return next is(terms->'config'->>'corrections_by','2026-10-08T00:00:00+00:00',metric||': existing correction deadline is frozen');
  if metric='exercise' then
   return next is(terms->>'source_policy_version','apple_watch_exercise_credit_v2','Exercise uses separately versioned credit');
   return next ok((terms->'source_terms'->>'accepted_causal_uncertainty')::boolean,'Exercise disclosure remains in digest');
  end if;
 end loop;
 return next ok(not app.challenge_real_health_policy_available_v1('apple_watch_exercise_v1'),'strict Exercise v1 stays unavailable');
 return next is(app.challenge_received_leaderboard_terms_v2('friend_steps_leaderboard_v1'),'{}'::jsonb,'historical terms get no new defaults');
end $$;
select * from pg_temp.creation();
-- An unrecovered update uses the existing review path rather than participant fault.
select set_config('test.p9_matrix_now','2026-10-03 12:00:00+00',true);
create temp table recovery_review(id uuid);
insert into recovery_review select pg_temp.matrix_room('friend_steps_leaderboard_v2',2);
select pg_temp.matrix_ingest(1,pg_temp.matrix_payload((select id from recovery_review),1,1,1000));
select pg_temp.matrix_ingest(2,pg_temp.matrix_payload((select id from recovery_review),2,1,5));
select set_config('test.p9_matrix_now','2026-10-06 00:00:01+00',true);
select public.challenge_process_v1((select id from recovery_review));
select lives_ok($$select pg_temp.command(2,jsonb_build_object('op','review','id',(select id from recovery_review),
 'revision',(select revision from app.challenge_lobbies_v1 where id=(select id from recovery_review)),
 'notice_revision',1,'reason','missing_activity'))$$,'participant can ask for review of an unrecovered update');
select set_config('test.p9_matrix_now','2026-10-08 00:00:02+00',true);
select is(public.challenge_process_v1((select id from recovery_review)),'review','pending review keeps finalization paused after notice deadline');
select is((select count(*) from app.challenge_finals_v1 where challenge_id=(select id from recovery_review)),0::bigint,'no simulated loss finalizes during review');
select set_config('test.p9_matrix_now','2026-10-09 00:00:02+00',true);
select is(app.challenge_real_health_evaluate_v1((select id from recovery_review))->>'outcome','void','unresolved review exclusion leaves fewer than two valid scores and safely voids');
select ok(not has_function_privilege('authenticated','app.challenge_received_leaderboard_terms_v2(text)','execute'),'new frozen-term helper is private');
select ok(not has_function_privilege('anon','app.challenge_received_leaderboard_v2(text)','execute'),'new policy helper is private');
select * from finish();
rollback;
