-- Rollback-only fictional actors exercise the operator-enabled private path.
begin;
select no_plan();

insert into auth.users(id) values
 ('bf000000-0000-0000-0000-000000000701'),
 ('bf000000-0000-0000-0000-000000000702');
insert into public.profiles(id,handle,display_name,timezone) values
 ('bf000000-0000-0000-0000-000000000701','private701','Fictional Private','UTC'),
 ('bf000000-0000-0000-0000-000000000702','private702','Fictional Other','UTC');
insert into auth.sessions(id,user_id) values
 ('ba000000-0000-0000-0000-000000000701','bf000000-0000-0000-0000-000000000701'),
 ('ba000000-0000-0000-0000-000000000702','bf000000-0000-0000-0000-000000000702');
select public.challenge_real_health_runtime_v1(true,true,false);

create temp table private_ids as select
 'bf000000-0000-0000-0000-000000000701'::uuid actor,
 'ba000000-0000-0000-0000-000000000701'::uuid session,
 'bf000000-0000-0000-0000-000000000702'::uuid outsider,
 'ba000000-0000-0000-0000-000000000702'::uuid outsider_session,
 'd5270000-0000-4000-8000-000000000001'::uuid readiness_request,
 'd5270000-0000-4000-8000-000000000002'::uuid progress_request,
 extensions.digest('private fictional body','sha256') digest;

select throws_ok(
 $$select public.challenge_real_health_readiness_v1('d5270000-0000-4000-8000-000000000001',
   'bf000000-0000-0000-0000-000000000701','apple_watch_steps_v1',clock_timestamp()-interval '1 minute',
   'ba000000-0000-0000-0000-000000000701',clock_timestamp()+interval '1 hour',null,null,
   extensions.digest('private fictional body','sha256'),false,null)$$,
 '42501','challenge_private_account_health_disabled',
 'unsigned readiness is denied by default');

update app.challenge_private_device_trial_v1 set enabled=true where singleton;
insert into app.challenge_private_device_accounts_v1(actor_id)
select actor from private_ids;
select throws_ok(
 $$select public.challenge_real_health_readiness_v1('d5270000-0000-4000-8000-000000000001',
   'bf000000-0000-0000-0000-000000000701','apple_watch_steps_v1',clock_timestamp()-interval '1 minute',
   'ba000000-0000-0000-0000-000000000701',clock_timestamp()+interval '1 hour',null,null,
   extensions.digest('private fictional body','sha256'),false,null)$$,
 '42501','challenge_private_account_health_disabled',
 'enrollment alone does not disable device verification');
update app.challenge_private_device_trial_v1
set require_device_verification=false where singleton;

select throws_ok(
 $$select public.challenge_real_health_readiness_v1('d5270000-0000-4000-8000-000000000003',
   'bf000000-0000-0000-0000-000000000702','apple_watch_steps_v1',clock_timestamp()-interval '1 minute',
   'ba000000-0000-0000-0000-000000000702',clock_timestamp()+interval '1 hour',null,null,
   extensions.digest('other fictional body','sha256'),false,null)$$,
 '42501','challenge_private_account_health_disabled',
 'another signed-in account cannot use the unsigned private path');
select throws_ok(
 $$select public.challenge_real_health_readiness_v1('d5270000-0000-4000-8000-000000000004',
   'bf000000-0000-0000-0000-000000000701','apple_watch_steps_v1',clock_timestamp()-interval '1 minute',
   'ba000000-0000-0000-0000-000000000701',clock_timestamp()+interval '1 hour',null,1,
   extensions.digest('half proof','sha256'),false,null)$$,
 '22023','challenge_real_health_readiness_invalid',
 'a half proof cannot enter the unsigned path');

create temp table private_readiness_receipt as
select public.challenge_real_health_readiness_v1(
 (select readiness_request from private_ids),(select actor from private_ids),'apple_watch_steps_v1',
 clock_timestamp()-interval '1 minute',(select session from private_ids),clock_timestamp()+interval '1 hour',
 null,null,(select digest from private_ids),false,null) receipt;
select is((select verification_mode from app.challenge_real_health_readiness_requests_v1
 where request_id=(select readiness_request from private_ids)),'private_account',
 'accepted readiness records its explicit private-account mode');
select is((select count(*) from public.device_attestations where user_id=(select actor from private_ids)),0::bigint,
 'private readiness did not fabricate a device key');
select is((select response from app.challenge_real_health_readiness_requests_v1
 where request_id=(select readiness_request from private_ids)),(select receipt from private_readiness_receipt),
 'the readiness receipt is durable');

-- A supplied proof still takes the original device/receipt/counter path.
insert into public.device_attestations(key_id,user_id,public_key,environment)
select extensions.digest(decode('04'||repeat('11',64),'hex'),'sha256'),actor,
 decode('04'||repeat('11',64),'hex'),'development' from private_ids;
insert into app.device_attestation_receipts(key_id,initial_receipt,current_receipt,current_receipt_verified_at)
select key_id,'\x01','\x01',clock_timestamp() from public.device_attestations
where user_id=(select actor from private_ids);
select lives_ok($$select public.challenge_real_health_readiness_v1(
 'd5270000-0000-4000-8000-000000000005',
 'bf000000-0000-0000-0000-000000000701','apple_watch_steps_v1',clock_timestamp()-interval '1 minute',
 'ba000000-0000-0000-0000-000000000701',clock_timestamp()+interval '1 hour',key_id,1,
 extensions.digest('signed fictional body','sha256'),false,null)
 from public.device_attestations where user_id='bf000000-0000-0000-0000-000000000701'$$,
 'a supplied proof still uses the signed readiness path');
select is((select verification_mode from app.challenge_real_health_readiness_requests_v1
 where request_id='d5270000-0000-4000-8000-000000000005'),'app_attest',
 'signed readiness retains the app-attest ledger mode');
select is((select sign_count from public.device_attestations where user_id=(select actor from private_ids)),1::bigint,
 'only the signed request consumes the device counter');

-- A complete fictional Personal agreement is required before progress.
select set_config('app.challenge_write_v1','on',true);
create temp table private_challenge as select
 'd5270000-0000-4000-8000-000000000010'::uuid id,
 clock_timestamp()-interval '1 hour' starts_at,
 clock_timestamp()+interval '1 day' ends_at;
insert into app.challenge_lobbies_v1(id,creator_id,policy,config,starts_at,ends_at,
 status,created_at,minimum,capacity,agreement_version,real_source_policy_version)
select c.id,p.actor,'personal_steps_goal_v1',
 jsonb_build_object('starts_at',c.starts_at,'ends_at',c.ends_at),c.starts_at,c.ends_at,
 'active',clock_timestamp(),1,1,1,'apple_watch_steps_v1'
from private_challenge c cross join private_ids p;
insert into app.challenge_agreements_v1(challenge_id,version,terms,created_at)
select id,1,jsonb_build_object('source_policy_version','apple_watch_steps_v1',
 'config',jsonb_build_object('starts_at',starts_at,'ends_at',ends_at)),clock_timestamp()
from private_challenge;
insert into app.challenge_members_v1(challenge_id,actor_id,selected,target)
select c.id,p.actor,true,100 from private_challenge c cross join private_ids p;
insert into app.challenge_slots_v1(challenge_id,actor_id,mode,metric,starts_at,ends_at)
select c.id,p.actor,'personal','steps',c.starts_at,c.ends_at
from private_challenge c cross join private_ids p;
insert into app.challenge_consents_v1(challenge_id,version,actor_id,digest,recorded_at)
select a.challenge_id,1,p.actor,a.digest,clock_timestamp()
from app.challenge_agreements_v1 a cross join private_ids p
where a.challenge_id=(select id from private_challenge);

create temp table private_payload as
select jsonb_build_object(
 'contract_version',1,'actor_id',p.actor,'challenge_id',c.id,'agreement_version',1,
 'terms_digest',a.digest,'source_policy_version','apple_watch_steps_v1','metric','steps',
 'window_starts_at',c.starts_at,'window_ends_at',c.ends_at,'request_id',p.progress_request,
 'revision',1,'previous_revision',null,'state','value','value',100,
 'observed_at',clock_timestamp(),'queried_through_at',clock_timestamp()) body
from private_challenge c cross join private_ids p
join app.challenge_agreements_v1 a on a.challenge_id=c.id and a.version=1;
create temp table private_progress_receipt as
select public.challenge_real_health_ingest_v1(
 (select progress_request from private_ids),(select body from private_payload),
 (select session from private_ids),clock_timestamp()+interval '1 hour',null,null,
 extensions.digest((select body from private_payload)::text,'sha256'),false) receipt;
select is((select verification_mode from app.challenge_real_health_requests_v1
 where request_id=(select progress_request from private_ids)),'private_account',
 'accepted progress records its private-account mode');
select is((select value from app.challenge_real_health_facts_v1
 where request_id=(select progress_request from private_ids)),100::bigint,
 'the complete consented Personal fact is saved without device proof');
select is((select sign_count from public.device_attestations where user_id=(select actor from private_ids)),1::bigint,
 'unsigned progress did not consume the signed device counter');
select is(public.challenge_real_health_ingest_v1(
 (select progress_request from private_ids),(select body from private_payload),
 (select session from private_ids),clock_timestamp()+interval '1 hour',null,null,
 extensions.digest((select body from private_payload)::text,'sha256'),true),
 (select receipt from private_progress_receipt),
 'exact progress recovery returns the saved receipt while intake is paused');

select throws_ok(
 $$select public.challenge_real_health_readiness_v1('d5270000-0000-4000-8000-000000000021',
   'bf000000-0000-0000-0000-000000000701','apple_workout_outdoor_timed_v1',clock_timestamp()-interval '1 minute',
   'ba000000-0000-0000-0000-000000000701',clock_timestamp()+interval '1 hour',null,null,
   extensions.digest('timed fictional body','sha256'),false,5000000)$$,
 '42501','challenge_private_trial_personal_steps_only',
 'the private account path still refuses timed outdoor readiness');
select lives_ok(
 $$select public.challenge_real_health_readiness_v1('d5270000-0000-4000-8000-000000000022',
   'bf000000-0000-0000-0000-000000000701','apple_workout_outdoor_distance_v1',clock_timestamp()-interval '1 minute',
   'ba000000-0000-0000-0000-000000000701',clock_timestamp()+interval '1 hour',null,null,
   extensions.digest('distance fictional body','sha256'),false,null)$$,
 'the enrolled private account can save outdoor-run distance readiness');

select set_config('app.challenge_write_v1','on',true);
create temp table private_distance as select
 'd5270000-0000-4000-8000-000000000030'::uuid id,
 'd5270000-0000-4000-8000-000000000023'::uuid progress_request,
 clock_timestamp()-interval '1 hour' starts_at,
 clock_timestamp()+interval '1 day' ends_at;
insert into app.challenge_lobbies_v1(id,creator_id,policy,config,starts_at,ends_at,
 status,created_at,minimum,capacity,agreement_version,real_source_policy_version)
select c.id,p.actor,'personal_distance_goal_v1',
 jsonb_build_object('starts_at',c.starts_at,'ends_at',c.ends_at),c.starts_at,c.ends_at,
 'active',clock_timestamp(),1,1,1,'apple_workout_outdoor_distance_v1'
from private_distance c cross join private_ids p;
insert into app.challenge_agreements_v1(challenge_id,version,terms,created_at)
select id,1,jsonb_build_object('source_policy_version','apple_workout_outdoor_distance_v1',
 'config',jsonb_build_object('starts_at',starts_at,'ends_at',ends_at)),clock_timestamp()
from private_distance;
insert into app.challenge_members_v1(challenge_id,actor_id,selected,target)
select c.id,p.actor,true,5000000 from private_distance c cross join private_ids p;
insert into app.challenge_slots_v1(challenge_id,actor_id,mode,metric,starts_at,ends_at)
select c.id,p.actor,'personal','distance',c.starts_at,c.ends_at
from private_distance c cross join private_ids p;
insert into app.challenge_consents_v1(challenge_id,version,actor_id,digest,recorded_at)
select a.challenge_id,1,p.actor,a.digest,clock_timestamp()
from app.challenge_agreements_v1 a cross join private_ids p
where a.challenge_id=(select id from private_distance);
create temp table private_distance_payload as
select jsonb_build_object(
 'contract_version',1,'actor_id',p.actor,'challenge_id',c.id,'agreement_version',1,
 'terms_digest',a.digest,'source_policy_version','apple_workout_outdoor_distance_v1','metric','distance',
 'window_starts_at',c.starts_at,'window_ends_at',c.ends_at,'request_id',c.progress_request,
 'revision',1,'previous_revision',null,'state','value','value',5000000,
 'observed_at',clock_timestamp(),'queried_through_at',clock_timestamp()) body
from private_distance c cross join private_ids p
join app.challenge_agreements_v1 a on a.challenge_id=c.id and a.version=1;
select lives_ok(
 $$select public.challenge_real_health_ingest_v1(
   (select progress_request from private_distance),(select body from private_distance_payload),
   (select session from private_ids),clock_timestamp()+interval '1 hour',null,null,
   extensions.digest((select body from private_distance_payload)::text,'sha256'),false)$$,
 'the enrolled private account can save an outdoor-run distance update');
select is((select value from app.challenge_real_health_facts_v1
 where request_id=(select progress_request from private_distance)),5000000::bigint,
 'the consented outdoor distance fact is saved without device proof');

select * from finish();
rollback;
