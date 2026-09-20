begin;
select no_plan();

-- Synthetic contract fixtures only. Source-aware creation/consent is covered
-- by 519 and the signed HTTP driver; this matrix isolates real RPC processing
-- across all thirteen policies without enabling the fictional fixture gate.
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


select ok(app.challenge_real_health_policy_available_v1('apple_watch_exercise_credit_v2'),'v2 has its own admission');
select ok(not app.challenge_real_health_policy_available_v1('apple_watch_exercise_v1'),'strict v1 stays unavailable');
select is((select terms->>'availability' from app.challenge_real_health_source_policies_v1 where version='apple_watch_exercise_v1'),'unavailable_causal_origin','historical registry terms unchanged');
select ok((app.challenge_exercise_credit_terms_v2('apple_watch_exercise_credit_v2')->'source_terms'->>'accepted_causal_uncertainty')::boolean,'new terms disclose accepted causal uncertainty');

create function pg_temp.p9_goals() returns setof text language plpgsql as $$
declare metric text; mode text; policy text; cid uuid; i integer; n integer; result jsonb; p jsonb;
begin
 for metric,mode in
  select m,md from unnest(array['steps','exercise','distance','timed'])m cross join unnest(array['friend','personal'])md
  union all select 'steps','community'
 loop
  policy:=mode||'_'||metric||'_goal_v1';
  foreach n in array (case when mode='personal' then array[1] else array[2,6] end) loop
   cid:=pg_temp.matrix_room(policy,n);
   for i in 1..n loop
    perform pg_temp.matrix_ingest(i,pg_temp.matrix_payload(cid,i,1,case when metric='timed' then 900 else 1100 end));
   end loop;
   result:=app.challenge_real_health_evaluate_v1(cid);
   return next is(result->'participants'->pg_temp.ma(1)::text->>'status','met',policy||': positive success, people='||n);
   return next is(result->'participants'->pg_temp.ma(1)::text->>'returned_cents','100',policy||': entry returns');
   for i in greatest(1,n-1)..n loop
    perform pg_temp.matrix_ingest(i,pg_temp.matrix_payload(cid,i,2,null,'unresolved'));
   end loop;
   result:=app.challenge_real_health_evaluate_v1(cid);
   return next is(result->>'outcome',case when n=6 then 'scored' else 'void' end,policy||': unresolved replacement follows outcome minimum');
   return next is((select count(*)::text from jsonb_each(result->'participants')e where e.value->>'status'='met'),case when n=6 then '4' else '0' end,policy||': no invented misses');
   return next is((select sum((e.value->>'returned_cents')::int)::int from jsonb_each(result->'participants')e),100*n,policy||': everyone recovers own entry');
   -- Preserve all exact committed receipts even when later facts replace them.
   p:=pg_temp.matrix_payload(cid,1,3,100);
   return next throws_ok(format('select pg_temp.matrix_ingest(1,%L::jsonb)',p||jsonb_build_object('source_policy_version','apple_watch_exercise_v1','metric','exercise')),'22023',null,policy||': source substitution refused');
  end loop;
 end loop;
 foreach metric in array array['steps','exercise','distance','timed'] loop
  cid:=pg_temp.matrix_room('friend_'||metric||'_leaderboard_v1');
  for i in 1..2 loop perform pg_temp.matrix_ingest(i,pg_temp.matrix_payload(cid,i,1,900)); end loop;
  return next is(app.challenge_real_health_evaluate_v1(cid)->>'outcome','void',metric||': retained leaderboard has no inferred ranking');
 end loop;
 cid:=pg_temp.matrix_room('community_steps_goal_v1',6,5);
 for i in 1..4 loop perform pg_temp.matrix_ingest(i,pg_temp.matrix_payload(cid,i,1,1100)); end loop;
 return next is(app.challenge_real_health_evaluate_v1(cid)->>'outcome','void','community outcome minimum five is distinct from disclosure minimum');
end $$;
select * from pg_temp.p9_goals();
select * from finish();
rollback;
