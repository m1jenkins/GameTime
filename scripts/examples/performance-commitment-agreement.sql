-- Fictional principal/session, no provider calls. Always rolled back.
begin;
set local timezone='UTC';
insert into auth.users(id) values('ee100000-0000-0000-0000-000000000001');
insert into public.profiles(id,handle,display_name,timezone)
  values('ee100000-0000-0000-0000-000000000001','commitment_example','Fictional Runner','America/Chicago');
insert into auth.sessions(id,user_id)
  values('ee200000-0000-0000-0000-000000000001','ee100000-0000-0000-0000-000000000001');
set local role service_role;
select public.set_performance_commitment_admission_v1(true,array['ee100000-0000-0000-0000-000000000001'::uuid]);
set local role authenticated;
set local request.jwt.claim.sub='ee100000-0000-0000-0000-000000000001';
set local request.jwt.claims='{"sub":"ee100000-0000-0000-0000-000000000001","role":"authenticated","session_id":"ee200000-0000-0000-0000-000000000001"}';
select clock_timestamp()+interval '24 hours' as starts_at \gset
select :'starts_at'::timestamptz+interval '1440 hours' as deadline_at \gset
select public.preview_performance_commitment_v1(1500,:'starts_at',:'deadline_at','America/Chicago',
  'performance-commitment-fixture-5k-v1') as preview \gset
select jsonb_pretty(:'preview'::jsonb->'terms') as rules_to_review;
select :'preview'::jsonb->>'terms_digest' as digest \gset
-- In a client, send only after the owner explicitly consents to these rules.
select public.create_performance_commitment_v1('ee200000-0000-0000-0000-000000000101',1500,
  :'starts_at',:'deadline_at','America/Chicago','performance-commitment-fixture-5k-v1',:'digest',true) as commitment_id \gset
set local role service_role;
select public.set_performance_commitment_admission_v1(false,'{}');
set local role authenticated;
select public.create_performance_commitment_v1('ee200000-0000-0000-0000-000000000101',1500,
  :'starts_at',:'deadline_at','America/Chicago','performance-commitment-fixture-5k-v1',:'digest',true)=:'commitment_id'::uuid as exact_recovery_with_gate_off;
select public.close_performance_commitment_v1('ee200000-0000-0000-0000-000000000102',:'commitment_id','cancel');
select jsonb_pretty(public.get_performance_commitment_v1(:'commitment_id')) as retained_receipt;
set constraints all immediate;
rollback;
