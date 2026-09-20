begin;
select no_plan();

-- Synthetic contract fixtures only. Source-aware creation/consent is covered
-- by 519 and the signed HTTP driver; this matrix isolates real RPC processing
-- across all thirteen policies without enabling the fictional fixture gate.
create or replace function app.challenge_real_health_now_v1()
returns timestamptz language sql volatile set search_path='' as $$
 select coalesce(nullif(current_setting('test.p8_matrix_now',true),'')::timestamptz,clock_timestamp())
$$;
select set_config('test.p8_matrix_now','2026-10-03 12:00:00+00',true);
insert into auth.users(id) select ('bf000000-0000-0000-0000-'||lpad((580+i)::text,12,'0'))::uuid from generate_series(1,3)i;
insert into public.profiles(id,handle,display_name,timezone)
select id,'p8matrix'||right(id::text,3),'Synthetic Matrix','UTC' from auth.users where id::text like 'bf000000-0000-0000-0000-00000000058%';
insert into auth.sessions(id,user_id)
select ('ba000000-0000-0000-0000-'||lpad((580+i)::text,12,'0'))::uuid,
       ('bf000000-0000-0000-0000-'||lpad((580+i)::text,12,'0'))::uuid from generate_series(1,3)i;
create function pg_temp.ma(n integer) returns uuid language sql as $$select ('bf000000-0000-0000-0000-'||lpad((580+n)::text,12,'0'))::uuid$$;
create function pg_temp.ms(n integer) returns uuid language sql as $$select ('ba000000-0000-0000-0000-'||lpad((580+n)::text,12,'0'))::uuid$$;
insert into public.device_attestations(key_id,user_id,public_key,environment)
select extensions.digest(decode('04'||repeat(lpad(i::text,2,'0'),64),'hex'),'sha256'),pg_temp.ma(i),decode('04'||repeat(lpad(i::text,2,'0'),64),'hex'),'development' from generate_series(1,2)i;
insert into app.device_attestation_receipts(key_id,initial_receipt,current_receipt,current_receipt_verified_at)
select key_id,'\x01','\x01',clock_timestamp() from public.device_attestations where user_id in(pg_temp.ma(1),pg_temp.ma(2));
select public.challenge_real_health_runtime_v1(true,true,true);
select set_config('request.jwt.claim.sub',pg_temp.ma(1)::text,true);
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.ma(1),'session_id',pg_temp.ms(1))::text,true);
select set_config('role','authenticated',true);
select public.challenge_confirm_age_v1('ba000000-0000-0000-0000-000000000581',true);
select set_config('role','none',true);

create function pg_temp.source(p_metric text) returns text language sql immutable as $$
 select case p_metric when 'steps' then 'apple_watch_steps_v1' when 'exercise' then 'apple_watch_exercise_v1'
 when 'distance' then 'apple_workout_outdoor_distance_v1' else 'apple_workout_outdoor_timed_v1' end
$$;
create function pg_temp.matrix_room(p_policy text) returns uuid language plpgsql as $$
declare cid uuid:=extensions.gen_random_uuid(); metric text:=split_part(p_policy,'_',2); mode text:=split_part(p_policy,'_',1);
 people integer:=case when mode='personal' then 1 else 2 end; source text:=pg_temp.source(metric); terms jsonb; i integer;
begin
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_lobbies_v1(id,creator_id,policy,config,starts_at,ends_at,status,agreement_version,created_at,minimum,capacity,real_source_policy_version)
 values(cid,pg_temp.ma(1),p_policy,jsonb_build_object('amount_cents',100)||case when metric='timed' then '{"distance_mm":5000000}'::jsonb else '{}' end,
 '2026-10-03 00:00:00+00','2026-10-04 00:00:00+00','active',1,'2026-10-01 00:00:00+00',people,6,source);
 terms:=jsonb_build_object('policy',p_policy,'metric',metric,'source',source,'source_policy_version',source,'simulation','nonredeemable',
  'config',jsonb_build_object('starts_at','2026-10-03 00:00:00+00','ends_at','2026-10-04 00:00:00+00')||case when metric='timed' then '{"distance_mm":5000000}'::jsonb else '{}' end);
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

create function pg_temp.run_real_matrix() returns setof text language plpgsql as $$
declare metric text; mode text; competition text; policy text; cid uuid; people integer; i integer; result jsonb; p jsonb; source text; status text;
begin
 for metric,mode,competition in
  select m,md,c from unnest(array['steps','exercise','distance','timed'])m
  cross join unnest(array['friend','personal'])md cross join unnest(array['goal','leaderboard'])c where md='friend' or c='goal'
  union all select 'steps','community','goal'
 loop
  policy:=mode||'_'||metric||'_'||competition||'_v1'; source:=pg_temp.source(metric); people:=case when mode='personal' then 1 else 2 end;
  perform set_config('test.p8_matrix_now','2026-10-03 12:00:00+00',true);
  cid:=pg_temp.matrix_room(policy);
  if metric='exercise' then
   return next ok(not app.challenge_real_health_policy_available_v1(source),policy||': capability unavailable without causal origin');
   p:=pg_temp.matrix_payload(cid,1,1,900);
   begin
    perform pg_temp.matrix_ingest(1,p);
    return next fail(policy||': refuses positive Exercise credit');
   exception when sqlstate '22023' then return next pass(policy||': refuses positive Exercise credit'); end;
  end if;
  for i in 1..people loop
   perform pg_temp.matrix_ingest(i,pg_temp.matrix_payload(cid,i,1,case when metric='exercise' then null else 900 end,case when metric='exercise' then 'unresolved' else 'value' end));
  end loop;
  return next is((select count(*) from app.challenge_facts_v1 where challenge_id=cid),0::bigint,policy||': no fictional score rows');
  if metric<>'exercise' then
   perform pg_temp.matrix_ingest(1,pg_temp.matrix_payload(cid,1,2,899));
   return next is((select value from app.challenge_real_health_facts_v1 where challenge_id=cid and actor_id=pg_temp.ma(1) order by revision desc limit 1),899::bigint,policy||': lower replacement is authoritative');
   return next is(app.challenge_fact_projection_v1(cid,pg_temp.ma(1))->>'value','899',policy||': source-aware progress reads replacement');
  end if;
  result:=app.challenge_real_health_evaluate_v1(cid);
  return next is(result->>'outcome',case when metric='exercise' or competition='leaderboard' then 'void' else 'scored' end,policy||': server derives only supportable results');
  perform set_config('test.p8_matrix_now','2026-10-06 00:00:01+00',true);
  status:=public.challenge_process_v1(cid);
  return next is(status,'review',policy||': processing publishes a provisional notice');
  return next ok((select bool_and(review_by-recorded_at=interval '48 hours') from app.challenge_notices_v1 where challenge_id=cid),policy||': actual notice receives 48 hours');
  -- The filing is a software fixture because RPC filing authorization is
  -- independently exercised by 518/HTTP. The real processor consumes it.
  perform set_config('app.challenge_write_v1','on',true);
  insert into app.challenge_reviews_v1(id,challenge_id,notice_revision,actor_id,reason,filed_at,resolve_by)
  values(extensions.gen_random_uuid(),cid,1,pg_temp.ma(1),'wrong_total',app.challenge_real_health_now_v1(),app.challenge_real_health_now_v1()+interval '72 hours');
  perform public.challenge_resolve_v1((select id from app.challenge_reviews_v1 where challenge_id=cid),pg_temp.ma(3),'upheld');
  return next ok((select bool_and(resolve_by-filed_at=interval '72 hours') from app.challenge_reviews_v1 where challenge_id=cid),policy||': resolution window starts at filing');
  perform set_config('test.p8_matrix_now','2026-10-08 00:00:02+00',true);
  status:=public.challenge_process_v1(cid);
  return next is(status,case when metric='exercise' or competition='leaderboard' then 'void' else 'final' end,policy||': reviewed result reaches final history');
  return next is((select f.result->>'simulation' from app.challenge_finals_v1 f where f.challenge_id=cid),'nonredeemable',policy||': allocations remain simulated');
 end loop;
end $$;
select * from pg_temp.run_real_matrix();

-- Distances are minimally attested readiness context, never a workout record.
select set_config('test.p8_matrix_now','2026-10-01 12:00:00+00',true);
select lives_ok($$select public.challenge_real_health_readiness_v1(extensions.gen_random_uuid(),pg_temp.ma(1),'apple_workout_outdoor_timed_v1',
 app.challenge_real_health_now_v1(),pg_temp.ms(1),clock_timestamp()+interval '1 hour',key_id,sign_count+1,
 extensions.digest('timed-readiness-5k','sha256'),false,5000000) from public.device_attestations where user_id=pg_temp.ma(1)$$,
 'timed readiness accepts the selected comparable distance');
select ok(app.challenge_real_health_has_readiness_v1(pg_temp.ma(1),'apple_workout_outdoor_timed_v1',5000000,app.challenge_real_health_now_v1()),'matching timed distance can be admitted');
select ok(not app.challenge_real_health_has_readiness_v1(pg_temp.ma(1),'apple_workout_outdoor_timed_v1',10000000,app.challenge_real_health_now_v1()),'a 5K read cannot admit a 10K commitment');

-- The unchanged closed-world result oracle still applies strict comparisons
-- and normalized ties when a complete input is available in its own contract.
select is(app.challenge_evaluate_policy_v1('personal_timed_goal_v1',jsonb_build_array(jsonb_build_object('actor_id',pg_temp.ma(1),'target',1000,'excluded',false,'state','complete','value',1000)),100,1)->'participants'->pg_temp.ma(1)::text->>'status','missed','timed equality remains a strict miss only in the complete-input oracle');
select is(app.challenge_evaluate_policy_v1('friend_timed_leaderboard_v1',jsonb_build_array(jsonb_build_object('actor_id',pg_temp.ma(1),'target',null,'excluded',false,'state','complete','value',900),jsonb_build_object('actor_id',pg_temp.ma(2),'target',null,'excluded',false,'state','complete','value',900)),100,2)->'participants'->pg_temp.ma(1)::text->>'returned_cents','100','normalized elapsed ties retain equal allocation');


-- Exercise remains unavailable at the actual admission API; distance/timed
-- Personal use the same explicit real preview and immutable consent contract.
create function pg_temp.real_personal_admission_checks() returns setof text language plpgsql as $$
declare metric text; source text; cfg jsonb; preview jsonb; payload jsonb; receipt jsonb; rid uuid; cid uuid;
begin
 perform set_config('test.p8_matrix_now','2026-10-01 12:00:00+00',true);
 for metric in select unnest(array['distance','timed']) loop
  source:=pg_temp.source(metric);
  cfg:='{"start_date":"2026-10-05","days":1,"timezone":"UTC","amount_cents":100}'::jsonb
   ||case when metric='timed' then '{"distance_mm":5000000}'::jsonb else '{}'::jsonb end;
  perform public.challenge_real_health_readiness_v1(extensions.gen_random_uuid(),pg_temp.ma(1),source,
   app.challenge_real_health_now_v1(),pg_temp.ms(1),clock_timestamp()+interval '1 hour',key_id,sign_count+1,
   extensions.digest(convert_to(source,'UTF8'),'sha256'),false,case when metric='timed' then 5000000 end)
   from public.device_attestations where user_id=pg_temp.ma(1);
  perform set_config('request.jwt.claim.sub',pg_temp.ma(1)::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.ma(1),'session_id',pg_temp.ms(1))::text,true);
  perform set_config('role','authenticated',true);
  preview:=public.challenge_personal_preview_v1('personal_'||metric||'_goal_v1',cfg,1000,source);
  rid:=extensions.gen_random_uuid();
  payload:=jsonb_build_object('op','personal_commit','policy','personal_'||metric||'_goal_v1','config',cfg,
    'target',1000,'digest',preview->>'digest','consent',true,'source_policy_version',source);
  receipt:=public.challenge_mutate_v1(rid,payload);
  return next is(public.challenge_mutate_v1(rid,payload),receipt,metric||' Personal exact retry recovers consent receipt');
  perform set_config('role','none',true);
  cid:=(receipt->>'id')::uuid;
  return next is((select a.digest from app.challenge_agreements_v1 a where a.challenge_id=cid and a.version=1),preview->>'digest',metric||' Personal retains exactly previewed real terms');
  return next is((select c.real_source_policy_version from app.challenge_lobbies_v1 c where c.id=cid),source,metric||' Personal consent selects real source before data');
 end loop;
 perform set_config('role','authenticated',true);
 return next throws_ok($q$select public.challenge_personal_preview_v1('personal_exercise_goal_v1','{"start_date":"2026-10-05","days":1,"timezone":"UTC","amount_cents":100}',100,'apple_watch_exercise_v1')$q$,
  '22023','challenge_invalid_real_health_source','Exercise cannot obtain real Personal admission');
 -- A second timed configuration must supply its own comparable readiness.
 cfg:=cfg||'{"distance_mm":10000000}'::jsonb;
 preview:=public.challenge_personal_preview_v1('personal_timed_goal_v1',cfg,1000,source);
 payload:=jsonb_build_object('op','personal_commit','policy','personal_timed_goal_v1','config',cfg,
    'target',1000,'digest',preview->>'digest','consent',true,'source_policy_version',source);
 begin
  perform public.challenge_mutate_v1(extensions.gen_random_uuid(),payload);
  return next fail('5K readiness must not authorize a 10K Personal commitment');
 exception when sqlstate '42501' then return next pass('5K readiness cannot authorize a 10K Personal commitment'); end;
 perform set_config('role','none',true);
end $$;
select * from pg_temp.real_personal_admission_checks();


-- Equal normalized elapsed time does not meet a strict timed goal, and a
-- positive subset cannot establish a miss. A later faster run can prove met.
select set_config('test.p8_matrix_now','2026-10-03 12:00:00+00',true);
select set_config('test.p8_timed_room',pg_temp.matrix_room('personal_timed_goal_v1')::text,true);
select pg_temp.matrix_ingest(1,pg_temp.matrix_payload(current_setting('test.p8_timed_room')::uuid,1,1,1000));
select is(app.challenge_real_health_evaluate_v1(current_setting('test.p8_timed_room')::uuid)->'participants'->pg_temp.ma(1)::text->>'status','void','real timed equality cannot qualify and cannot prove a miss');
select throws_ok($$select pg_temp.matrix_ingest(1,pg_temp.matrix_payload(current_setting('test.p8_timed_room')::uuid,1,2,999)||'{"distance_mm":10000000}'::jsonb)$$,'22023','challenge_real_health_binding_invalid','normalized elapsed time is bound to its selected frozen distance');
select pg_temp.matrix_ingest(1,pg_temp.matrix_payload(current_setting('test.p8_timed_room')::uuid,1,2,999));
select is(app.challenge_real_health_evaluate_v1(current_setting('test.p8_timed_room')::uuid)->'participants'->pg_temp.ma(1)::text->>'status','met','a lower whole elapsed time establishes the strict real goal');

-- Exact ingress cutoffs and binding checks use a new immutable contract and
-- only advance the disposable source clock. No consented timestamp is edited.
select set_config('test.p8_boundary_room',pg_temp.matrix_room('friend_steps_goal_v1')::text,true);
select set_config('test.p8_matrix_now','2026-10-05 00:00:00+00',true);
select lives_ok($$select pg_temp.matrix_ingest(1,pg_temp.matrix_payload(current_setting('test.p8_boundary_room')::uuid,1,1,200))$$,'initial real sync is accepted exactly at end plus 24 hours');
select set_config('test.p8_matrix_now','2026-10-05 00:00:00.000001+00',true);
select throws_ok($$select pg_temp.matrix_ingest(2,pg_temp.matrix_payload(current_setting('test.p8_boundary_room')::uuid,2,1,200))$$,'22023','challenge_invalid_real_health_revision','a first submission just after 24 hours is refused');
select set_config('test.p8_matrix_now','2026-10-06 00:00:00+00',true);
select lives_ok($$select pg_temp.matrix_ingest(1,pg_temp.matrix_payload(current_setting('test.p8_boundary_room')::uuid,1,2,150))$$,'lower correction is accepted exactly at end plus 48 hours');
select throws_ok($$select pg_temp.matrix_ingest(1,pg_temp.matrix_payload(current_setting('test.p8_boundary_room')::uuid,1,3,140)||jsonb_build_object('observed_at','2026-10-05 00:00:00+00'))$$,'22023','challenge_invalid_real_health_revision','a correction cannot move observation freshness backward');
select throws_ok($$select pg_temp.matrix_ingest(1,pg_temp.matrix_payload(current_setting('test.p8_boundary_room')::uuid,1,3,140)||jsonb_build_object('terms_digest',repeat('0',64)))$$,'22023','challenge_real_health_binding_invalid','a real correction cannot change frozen terms');
select throws_ok($$select pg_temp.matrix_ingest(1,pg_temp.matrix_payload(current_setting('test.p8_boundary_room')::uuid,1,3,140)||jsonb_build_object('window_ends_at','2026-10-04 00:00:00.000001+00'))$$,'22023','challenge_real_health_binding_invalid','a real correction cannot widen the frozen window');
select throws_ok($$select pg_temp.matrix_ingest(1,pg_temp.matrix_payload(current_setting('test.p8_boundary_room')::uuid,1,3,140)||'{"source_policy_version":"apple_workout_outdoor_distance_v1","metric":"distance"}'::jsonb)$$,'22023','challenge_real_health_binding_invalid','a real correction cannot change the source policy or metric');
select lives_ok($$select pg_temp.matrix_ingest(1,pg_temp.matrix_payload(current_setting('test.p8_boundary_room')::uuid,1,3,null,'deleted'))$$,'a confirmed deletion remains an explicit revision rather than zero');
select is(app.challenge_fact_projection_v1(current_setting('test.p8_boundary_room')::uuid,pg_temp.ma(1))->>'state','deleted','participant progress preserves the explicit deleted state');
select set_config('test.p8_matrix_now','2026-10-06 00:00:00.000001+00',true);
select throws_ok($$select pg_temp.matrix_ingest(1,pg_temp.matrix_payload(current_setting('test.p8_boundary_room')::uuid,1,4,100))$$,'22023','challenge_invalid_real_health_revision','a correction just after 48 hours is refused');

select * from finish();
rollback;
