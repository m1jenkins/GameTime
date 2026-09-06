-- Two fictional principals and real local session rows; public product RPCs.
-- This is not an HTTP/native smoke or an invitation to a real person.
begin;
set local timezone='UTC';
create function pg_temp.assert(value boolean,message text) returns void language plpgsql as $$ begin
 if value is distinct from true then raise exception '%',message; end if;
end; $$;
insert into auth.users(id) values('edd10000-0000-0000-0000-000000000001'),('edd10000-0000-0000-0000-000000000002');
insert into public.profiles(id,handle,display_name,timezone) values
 ('edd10000-0000-0000-0000-000000000001','following_example_owner','Fictional Owner','America/Chicago'),
 ('edd10000-0000-0000-0000-000000000002','following_example_friend','Fictional Friend','America/Chicago');
insert into auth.sessions(id,user_id) values
 ('edd20000-0000-0000-0000-000000000001','edd10000-0000-0000-0000-000000000001'),
 ('edd20000-0000-0000-0000-000000000002','edd10000-0000-0000-0000-000000000002');
insert into public.friendships(user_a,user_b,requested_by,status) values
 ('edd10000-0000-0000-0000-000000000001','edd10000-0000-0000-0000-000000000002','edd10000-0000-0000-0000-000000000001','accepted');
set local role service_role;
select public.set_performance_commitment_admission_v1(true,array['edd10000-0000-0000-0000-000000000001'::uuid]);
select public.set_commitment_progress_enabled_v1(true);
select public.set_commitment_following_enabled_v1(true);
set local role authenticated;
set local request.jwt.claim.sub='edd10000-0000-0000-0000-000000000001';
set local request.jwt.claims='{"sub":"edd10000-0000-0000-0000-000000000001","role":"authenticated","session_id":"edd20000-0000-0000-0000-000000000001"}';
select clock_timestamp()+interval '24 hours' as starts_at \gset
select :'starts_at'::timestamptz+interval '1440 hours' as deadline_at \gset
select public.preview_performance_commitment_v1(1500,:'starts_at',:'deadline_at','America/Chicago','performance-commitment-fixture-5k-v1')->>'terms_digest' as digest \gset
select public.create_performance_commitment_v1('edd20000-0000-0000-0000-000000000101',1500,:'starts_at',:'deadline_at',
 'America/Chicago','performance-commitment-fixture-5k-v1',:'digest',true) as commitment_id \gset
select public.create_commitment_milestone_v1('edd20000-0000-0000-0000-000000000102',:'commitment_id','Choose a race',:'starts_at');
select public.record_commitment_progress_v1('edd20000-0000-0000-0000-000000000103',:'commitment_id','This note stays private.',clock_timestamp());
select public.publish_commitment_progress_v1('edd20000-0000-0000-0000-000000000104',:'commitment_id',1)->>'publication_id' as publication_id \gset
select public.publish_commitment_progress_v1('edd20000-0000-0000-0000-000000000105',:'commitment_id',2);
-- Versioned owner consent to goal facts and the explicitly published cards.
select public.invite_commitment_follower_v1('edd20000-0000-0000-0000-000000000106',:'commitment_id',
 'edd10000-0000-0000-0000-000000000002','goal_and_selected_progress_v1',true)->>'follow_id' as follow_id \gset
set local request.jwt.claim.sub='edd10000-0000-0000-0000-000000000002';
set local request.jwt.claims='{"sub":"edd10000-0000-0000-0000-000000000002","role":"authenticated","session_id":"edd20000-0000-0000-0000-000000000002"}';
select pg_temp.assert(public.get_commitment_follow_v1(:'follow_id')->'access_allowed'='false'::jsonb,'Invitation must not share automatically');
-- Independent explicit follower consent; opening/listing never accepts.
select public.respond_commitment_follow_v1('edd20000-0000-0000-0000-000000000107',:'follow_id',true) as acceptance \gset
select public.get_commitment_follow_v1(:'follow_id') as shared \gset
select pg_temp.assert(:'shared'::jsonb->'access_allowed'='true'::jsonb,'Consented friend must see selected progress');
select pg_temp.assert(not(:'shared' ~ 'This note stays private|amount|terms|recipient|request_id'),'Private fields must stay private');
select jsonb_pretty(:'shared'::jsonb) as follower_projection;
select public.react_commitment_progress_v1('edd20000-0000-0000-0000-000000000108',:'follow_id',:'publication_id','cheer');
set local role service_role;
select public.set_commitment_following_enabled_v1(false);
set local role authenticated;
set local request.jwt.claim.sub='edd10000-0000-0000-0000-000000000001';
set local request.jwt.claims='{"sub":"edd10000-0000-0000-0000-000000000001","role":"authenticated","session_id":"edd20000-0000-0000-0000-000000000001"}';
select public.end_commitment_follow_v1('edd20000-0000-0000-0000-000000000109',:'follow_id','revoke');
set local request.jwt.claim.sub='edd10000-0000-0000-0000-000000000002';
set local request.jwt.claims='{"sub":"edd10000-0000-0000-0000-000000000002","role":"authenticated","session_id":"edd20000-0000-0000-0000-000000000002"}';
select pg_temp.assert(public.respond_commitment_follow_v1('edd20000-0000-0000-0000-000000000107',:'follow_id',true)=:'acceptance'::jsonb,'Exact receipt must remain recoverable');
select pg_temp.assert(public.get_commitment_follow_v1(:'follow_id')->'access_allowed'='false'::jsonb,'Exact recovery must not restore sharing');
select public.report_commitment_follow_v1('edd20000-0000-0000-0000-000000000110',:'follow_id','support','Fictional request for help after sharing ended.');
set constraints all immediate;
rollback;
