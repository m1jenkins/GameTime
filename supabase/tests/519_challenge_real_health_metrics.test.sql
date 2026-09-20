begin;
select no_plan();


insert into auth.users(id) values
 ('bf000000-0000-0000-0000-000000000561'),
 ('bf000000-0000-0000-0000-000000000562'),
 ('bf000000-0000-0000-0000-000000000563'),
 ('bf000000-0000-0000-0000-000000000564');
insert into public.profiles(id,handle,display_name,timezone) values
 ('bf000000-0000-0000-0000-000000000561','realmetrics561','Real Metrics One','America/Chicago'),
 ('bf000000-0000-0000-0000-000000000562','realmetrics562','Real Metrics Two','America/Chicago'),
 ('bf000000-0000-0000-0000-000000000563','realmetrics563','Real Metrics Operator','America/Chicago'),
 ('bf000000-0000-0000-0000-000000000564','realmetrics564','Real Metrics Suspended','America/Chicago');
insert into auth.sessions(id,user_id) values
 ('ba000000-0000-0000-0000-000000000561','bf000000-0000-0000-0000-000000000561'),
 ('ba000000-0000-0000-0000-000000000562','bf000000-0000-0000-0000-000000000562'),
 ('ba000000-0000-0000-0000-000000000563','bf000000-0000-0000-0000-000000000563');
create function pg_temp.rh_actor(n integer) returns uuid language sql as $$select ('bf000000-0000-0000-0000-'||lpad((560+n)::text,12,'0'))::uuid$$;
create function pg_temp.rh_session(n integer) returns uuid language sql as $$select ('ba000000-0000-0000-0000-'||lpad((560+n)::text,12,'0'))::uuid$$;
create function pg_temp.rh_login(n integer) returns void language plpgsql as $$begin
 perform set_config('request.jwt.claim.sub',pg_temp.rh_actor(n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.rh_actor(n),'session_id',pg_temp.rh_session(n))::text,true);
 perform set_config('role','authenticated',true);
end $$;

-- The logical clock makes a future agreement active without editing its frozen
-- window.  The replacement rolls back with this test transaction.
create or replace function app.challenge_real_health_now_v1() returns timestamptz language sql volatile set search_path='' as $$
 select coalesce(nullif(current_setting('test.p8_real_health_now',true),'')::timestamptz,clock_timestamp())
$$;
select set_config('test.p8_real_health_now','2030-01-01T12:00:00Z',true);
select set_config('app.challenge_write_v1','on',true);
insert into public.device_attestations(key_id,user_id,public_key,environment) values
 (extensions.digest(decode('04'||repeat('21',64),'hex'),'sha256'),pg_temp.rh_actor(1),decode('04'||repeat('21',64),'hex'),'development'),
 (extensions.digest(decode('04'||repeat('22',64),'hex'),'sha256'),pg_temp.rh_actor(2),decode('04'||repeat('22',64),'hex'),'development');
insert into app.device_attestation_receipts(key_id,initial_receipt,current_receipt,received_at,current_receipt_verified_at)
select key_id,'\x01'::bytea,'\x01'::bytea,clock_timestamp()-interval '1 minute',clock_timestamp() from public.device_attestations where user_id in (pg_temp.rh_actor(1),pg_temp.rh_actor(2));
create function pg_temp.rh_key(n integer) returns bytea language sql as $$select key_id from public.device_attestations where user_id=pg_temp.rh_actor(n)$$;
create function pg_temp.rh_readiness(n integer,p_counter bigint) returns jsonb language sql volatile as $$
 select public.challenge_real_health_readiness_v1(extensions.gen_random_uuid(),pg_temp.rh_actor(n),'apple_watch_steps_v1',app.challenge_real_health_now_v1()-interval '1 minute',pg_temp.rh_session(n),clock_timestamp()+interval '1 hour',pg_temp.rh_key(n),p_counter,extensions.digest(convert_to('p8-real-health-readiness-'||n||'-'||p_counter,'UTF8'),'sha256'),false)
$$;
select public.challenge_real_health_runtime_v1(true,true,true);
select lives_ok($$select pg_temp.rh_readiness(1,1)$$,'first participant has an attested positive source read');
select lives_ok($$select pg_temp.rh_readiness(2,1)$$,'second participant has an independent attested positive source read');
select is((select count(*) from app.challenge_real_health_readiness_v1 where source_policy_version='apple_watch_steps_v1'),2::bigint,'readiness remains separate from scores and agreements');
insert into app.challenge_suspensions_v1(actor_id,suspended,operator_id,reason,recorded_at)
values ('bf000000-0000-0000-0000-000000000564',true,pg_temp.rh_actor(3),'unsafe_behavior',clock_timestamp());
select throws_ok(
  $$select public.challenge_publish_community_real_health_v1(
    'ba000000-0000-0000-0000-000000000570',
    'bf000000-0000-0000-0000-000000000564',
    '{"start_date":"2030-01-05","days":1,"timezone":"UTC","amount_cents":100}',
    100,2,6,'apple_watch_steps_v1'
  )$$,
  '42501','challenge_community_configuration_disabled',
  'a suspended service operator cannot publish a real-source community'
);

-- Authenticated RPC results are copied through a setting, then the test resets
-- before it inspects private records.  No private app table is exposed.
select pg_temp.rh_login(1);
select set_config('test.rh.age_one',public.challenge_confirm_age_v1('ba000000-0000-0000-0000-000000000573',true)::text,true);
select set_config('role','none',true);
select pg_temp.rh_login(1);
select set_config('test.rh.preview',public.challenge_personal_preview_v1('personal_steps_goal_v1','{"start_date":"2030-01-05","days":1,"timezone":"UTC","amount_cents":100}',100,'apple_watch_steps_v1')::text,true);
select set_config('role','none',true);
create temp table personal_draft(preview jsonb);
insert into personal_draft values(current_setting('test.rh.preview')::jsonb);
select pg_temp.rh_login(1);
select set_config('test.rh.personal_commit',public.challenge_mutate_v1('ba000000-0000-0000-0000-000000000571',jsonb_build_object('op','personal_commit','policy','personal_steps_goal_v1','config','{"start_date":"2030-01-05","days":1,"timezone":"UTC","amount_cents":100}'::jsonb,'target',100,'digest',(current_setting('test.rh.preview')::jsonb)->>'digest','consent',true,'source_policy_version','apple_watch_steps_v1'))::text,true);
select set_config('role','none',true);
create temp table personal_created(id uuid,response jsonb);
insert into personal_created select (current_setting('test.rh.personal_commit')::jsonb->>'id')::uuid,current_setting('test.rh.personal_commit')::jsonb;
select is((select real_source_policy_version from app.challenge_lobbies_v1 where id=(select id from personal_created)),'apple_watch_steps_v1','Personal commit freezes the selected source');
select is((select digest from app.challenge_agreements_v1 where challenge_id=(select id from personal_created) and version=1),(select preview->>'digest' from personal_draft),'Personal consent stores exactly the previewed source digest');
select pg_temp.rh_login(1);
select set_config('test.rh.personal_retry',public.challenge_mutate_v1('ba000000-0000-0000-0000-000000000571',jsonb_build_object('op','personal_commit','policy','personal_steps_goal_v1','config','{"start_date":"2030-01-05","days":1,"timezone":"UTC","amount_cents":100}'::jsonb,'target',100,'digest',(current_setting('test.rh.preview')::jsonb)->>'digest','consent',true,'source_policy_version','apple_watch_steps_v1'))::text,true);
select set_config('role','none',true);
select is(current_setting('test.rh.personal_retry')::jsonb,(select response from personal_created),'Personal exact retry preserves its receipt');

-- Community creation remains service-operated.  Its agreement has the source
-- binding before a participant can discover or join it.
select set_config('test.rh.community_id',public.challenge_publish_community_real_health_v1('ba000000-0000-0000-0000-000000000572',pg_temp.rh_actor(3),'{"start_date":"2030-01-05","days":1,"timezone":"UTC","amount_cents":100}',100,2,6,'apple_watch_steps_v1')::text,true);
create temp table community_created(id uuid);
insert into community_created values(current_setting('test.rh.community_id')::uuid);
select is((select terms->>'source_policy_version' from app.challenge_agreements_v1 where challenge_id=(select id from community_created) and version=1),'apple_watch_steps_v1','community agreement freezes the source before its consents');
select pg_temp.rh_login(1);
select set_config('test.rh.catalog',public.challenge_community_catalog_v1()::text,true);
select set_config('role','none',true);
select ok(current_setting('test.rh.catalog')::jsonb @> jsonb_build_array(jsonb_build_object('id',(select id from community_created))),'source-enabled community uses the existing bounded catalog');
select set_config('test.rh.join_payload',jsonb_build_object('op','join_community','id',(select id from community_created),'digest',(select digest from app.challenge_agreements_v1 where challenge_id=(select id from community_created) and version=1),'consent',true)::text,true);
select pg_temp.rh_login(2);
select throws_ok(
  $$select public.challenge_join_community_v1(
    'ba000000-0000-0000-0000-000000000574',current_setting('test.rh.join_payload')::jsonb
  )$$,
  '42501','challenge_age_required',
  'a direct real community join still requires the explicit 21-plus confirmation'
);
select set_config('test.rh.age_two',public.challenge_confirm_age_v1('ba000000-0000-0000-0000-000000000580',true)::text,true);
select set_config('role','none',true);
select pg_temp.rh_login(1);
select set_config('test.rh.join_one',public.challenge_join_community_v1('ba000000-0000-0000-0000-000000000575',current_setting('test.rh.join_payload')::jsonb)::text,true);
select set_config('role','none',true);
select pg_temp.rh_login(2);
select set_config('test.rh.join_two',public.challenge_join_community_v1('ba000000-0000-0000-0000-000000000576',current_setting('test.rh.join_payload')::jsonb)::text,true);
select set_config('role','none',true);
select is((select count(*) from app.challenge_consents_v1 where challenge_id=(select id from community_created) and version=1),2::bigint,'community participants give their own frozen-source consents');
select pg_temp.rh_login(2);
select set_config('test.rh.join_retry',public.challenge_join_community_v1('ba000000-0000-0000-0000-000000000576',current_setting('test.rh.join_payload')::jsonb)::text,true);
select set_config('role','none',true);
select is(current_setting('test.rh.join_retry')::jsonb,current_setting('test.rh.join_two')::jsonb,'community exact retry preserves its receipt');

-- Both frozen windows become active through the local source clock.  Facts are
-- sent through the attested ingress, including a Personal downward correction.
select set_config('test.p8_real_health_now','2030-01-05T01:00:00Z',true);
select public.challenge_process_v1((select id from personal_created));
select public.challenge_process_v1((select id from community_created));
create function pg_temp.rh_payload(p_challenge uuid,p_actor integer,p_request uuid,p_revision integer,p_previous integer,p_value bigint) returns jsonb language sql volatile as $$
 select jsonb_build_object('contract_version',1,'actor_id',pg_temp.rh_actor(p_actor),'challenge_id',c.id,'agreement_version',1,'terms_digest',a.digest,'source_policy_version','apple_watch_steps_v1','metric','steps','window_starts_at',c.starts_at,'window_ends_at',c.ends_at,'request_id',p_request,'revision',p_revision,'previous_revision',case when p_previous is null then 'null'::jsonb else to_jsonb(p_previous) end,'state','value','value',p_value,'observed_at',clock.now_at,'queried_through_at',clock.now_at)
 from app.challenge_lobbies_v1 c join app.challenge_agreements_v1 a on a.challenge_id=c.id and a.version=1 cross join lateral(select app.challenge_real_health_now_v1() now_at) clock where c.id=p_challenge
$$;
create function pg_temp.rh_ingest(p_actor integer,p_request uuid,p_payload jsonb,p_counter bigint) returns jsonb language sql volatile as $$
 select public.challenge_real_health_ingest_v1(p_request,p_payload,pg_temp.rh_session(p_actor),clock_timestamp()+interval '1 hour',pg_temp.rh_key(p_actor),p_counter,extensions.digest(convert_to(p_payload::text,'UTF8'),'sha256'),false)
$$;
select lives_ok($$select pg_temp.rh_ingest(1,'ba000000-0000-0000-0000-000000000577',pg_temp.rh_payload((select id from personal_created),1,'ba000000-0000-0000-0000-000000000577',1,null,100),2)$$,'Personal lower-bound progress enters through the real ingress');
select lives_ok($$select pg_temp.rh_ingest(1,'ba000000-0000-0000-0000-000000000578',pg_temp.rh_payload((select id from personal_created),1,'ba000000-0000-0000-0000-000000000578',2,1,50),3)$$,'Personal downward correction enters through the real ingress');
select is((select value from app.challenge_real_health_facts_v1 where challenge_id=(select id from personal_created) order by revision desc limit 1),50::bigint,'Personal correction replaces rather than accumulates progress');
select lives_ok($$select pg_temp.rh_ingest(1,'ba000000-0000-0000-0000-000000000579',pg_temp.rh_payload((select id from community_created),1,'ba000000-0000-0000-0000-000000000579',1,null,100),4)$$,'community progress enters through the real ingress after consent');
select set_config('test.p8_real_health_now','2030-01-08T00:00:01Z',true);
select is(public.challenge_process_v1((select id from personal_created)),'review','Personal processing derives a provisional result from the corrected source ledger');
select is(public.challenge_process_v1((select id from community_created)),'review','community processing derives a provisional result from the real source ledger');
select ok(exists(select 1 from app.challenge_notices_v1 where challenge_id=(select id from personal_created)),'Personal provisional notice uses the retained lifecycle primitive');
select ok(exists(select 1 from app.challenge_notices_v1 where challenge_id=(select id from community_created)),'community provisional notice uses the retained lifecycle primitive');
select * from finish();
rollback;
