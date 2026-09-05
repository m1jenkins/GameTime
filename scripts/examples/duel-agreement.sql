-- Run via: bash scripts/duel-agreement-example.sh
-- Fictional Auth principals, no Apple/provider contact and no real credentials.
begin;
insert into auth.users(id) values
  ('d5000000-0000-0000-0000-000000000001'),('d5000000-0000-0000-0000-000000000002');
insert into public.profiles(id,handle,display_name,timezone) values
  ('d5000000-0000-0000-0000-000000000001','duel_example_a','Fictional Runner A','America/Chicago'),
  ('d5000000-0000-0000-0000-000000000002','duel_example_b','Fictional Runner B','America/Chicago');
insert into public.friendships(user_a,user_b,requested_by,status) values
  ('d5000000-0000-0000-0000-000000000001','d5000000-0000-0000-0000-000000000002',
   'd5000000-0000-0000-0000-000000000001','accepted');

-- Service-owned setup is part of the same rollback-only transaction.
set local role service_role;
select public.set_duel_admission_v1(true,array[
  'd5000000-0000-0000-0000-000000000001'::uuid,'d5000000-0000-0000-0000-000000000002'::uuid]);
select public.curate_duel_fixture_event_v1('d5000000-0000-0000-0000-000000001000',
  clock_timestamp()+interval '2 days',clock_timestamp()+interval '2 days 2 hours','America/Chicago');

-- A reviews the immutable event/policy and explicitly consents on creation.
set local role authenticated;
set local request.jwt.claim.sub='d5000000-0000-0000-0000-000000000001';
select public.create_duel_v1('d5000000-0000-0000-0000-000000000101',
  'd5000000-0000-0000-0000-000000000002','d5000000-0000-0000-0000-000000001000',
  'duel-fixture-5k-v1',true) as duel_id \gset
select public.get_duel_v1(:'duel_id')->>'terms_digest' as creator_digest \gset

-- B reads the same complete terms, then names their version and digest.
set local request.jwt.claim.sub='d5000000-0000-0000-0000-000000000002';
select jsonb_pretty(public.get_duel_v1(:'duel_id')->'terms') as agreement_to_review;
select public.get_duel_v1(:'duel_id')->>'terms_digest' = :'creator_digest' as identical_terms;
select public.accept_duel_v1('d5000000-0000-0000-0000-000000000102',
  :'duel_id','duel-fixture-5k-v1',:'creator_digest');
select public.get_duel_v1(:'duel_id')->>'status' as agreed_status;

-- A lost response can recover even after admission is disabled.
set local role service_role;
select public.set_duel_admission_v1(false,'{}');
set local role authenticated;
select public.accept_duel_v1('d5000000-0000-0000-0000-000000000102',
  :'duel_id','duel-fixture-5k-v1',:'creator_digest') = :'duel_id'::uuid as recovered_exact_request;
select public.cancel_duel_v1('d5000000-0000-0000-0000-000000000103',:'duel_id');
select public.get_duel_v1(:'duel_id')->>'status' as cancelled_status;
reset role;
set constraints all immediate;
rollback;
