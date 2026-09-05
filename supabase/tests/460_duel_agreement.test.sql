-- Deterministic agreement, privacy, rollback and boundary tests. Every fixture
-- and test-only clock wrapper is rolled back; production exposes no clock.
begin;
select no_plan();
set local timezone='UTC';

create function pg_temp.actor(n integer) returns uuid language sql immutable as $$
  select ('d1000000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid;
$$;
create function pg_temp.req(n integer) returns uuid language sql immutable as $$
  select ('d2000000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid;
$$;
create function pg_temp.login(n integer) returns void language sql as $$
  select set_config('request.jwt.claim.sub',pg_temp.actor(n)::text,true)::void;
$$;
create function pg_temp.make(n integer,invitee integer default 2,event_num integer default 1,
  at_time timestamptz default '2026-10-31 12:00Z') returns uuid
language sql security definer set search_path='' as $$
  select app.create_duel_at_v1(pg_temp.req(n),pg_temp.actor(invitee),pg_temp.req(1000+event_num),
    'duel-fixture-5k-v1',true,at_time);
$$;
create function pg_temp.respond(op text,n integer,c uuid,at_time timestamptz default '2026-10-31 13:00Z',
  digest text default null,policy_version text default 'duel-fixture-5k-v1') returns uuid language sql security definer set search_path='' as $$
  select app.respond_duel_at_v1(op,pg_temp.req(n),c,
    case when op='accept_duel_v1' then policy_version end,
    case when op='accept_duel_v1' then coalesce(digest,(select terms_digest from public.duel_challenges where id=c)) end,
    at_time);
$$;
create table pg_temp.saved(name text primary key,id uuid);
grant select,insert on pg_temp.saved to authenticated;
create function pg_temp.saved(n text) returns uuid language sql as $$select id from pg_temp.saved where name=n$$;

select is((select admission_enabled from app.duel_runtime),false,'fresh admission is off');
select is((select count(*) from app.duel_beta_allowlist),0::bigint,'fresh allowlist is empty');
select is((select count(*) from public.duel_event_fixtures),0::bigint,'no stale dated event is seeded');
select is((select count(*) from cron.job where command ilike '%duel%'),0::bigint,'no duel scheduler registered');
select is((select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('app','public') and c.relname like 'duel_%' and c.relkind='r' and not c.relrowsecurity),
  0::bigint,'every new table has RLS enabled');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('app','public') and p.proname like '%duel%v1' and p.prosecdef
    and not ('search_path=""'=any(p.proconfig))),0::bigint,'all new definers have an empty search path');

insert into auth.users(id) select pg_temp.actor(n) from generate_series(1,12) n;
insert into public.profiles(id,handle,display_name,timezone)
select pg_temp.actor(n),'dueltest'||n,'Fictional Runner '||n,'UTC' from generate_series(1,12) n;
insert into public.friendships(user_a,user_b,requested_by,status)
select pg_temp.actor(a),pg_temp.actor(b),pg_temp.actor(a),'accepted'
from generate_series(1,11) a cross join generate_series(2,12) b where a<b and b<>12;
select public.curate_duel_fixture_event_v1(pg_temp.req(1001),'2026-11-01 15:00Z','2026-11-01 17:00Z','America/Chicago');
select public.curate_duel_fixture_event_v1(pg_temp.req(1002),'2026-11-05 15:00Z','2026-11-05 17:00Z','UTC');
select public.curate_duel_fixture_event_v1(pg_temp.req(1003),'2026-11-30 11:00Z','2026-11-30 12:00Z','UTC');
select public.curate_duel_fixture_event_v1(pg_temp.req(1004),'2026-11-30 11:00Z','2026-11-30 12:00:00.000001Z','UTC');
select public.curate_duel_fixture_event_v1(pg_temp.req(1005),'2026-10-31 13:00Z','2026-10-31 14:00Z','UTC');
select throws_ok($$select public.curate_duel_fixture_event_v1(pg_temp.req(1001),'2026-11-01 16:00Z','2026-11-01 17:00Z','UTC')$$,
  '22023','duel_event_identity_conflict','curated event identity cannot be repointed');
select throws_ok($$select public.curate_duel_fixture_event_v1(pg_temp.req(1099),'infinity','infinity','UTC')$$,
  '22023',null,'non-finite event rejected');
select throws_ok($$select public.curate_duel_fixture_event_v1(pg_temp.req(1099),'2026-11-01 15:00Z','2026-11-01 17:00Z','Mars/Base')$$,
  '22023',null,'unknown display timezone rejected');

set local role authenticated;
select pg_temp.login(1);
select throws_ok($$select pg_temp.make(1)$$,'42501','duel_admission_denied','off gate rejects create');
select throws_ok($$select public.set_duel_admission_v1(true,array[pg_temp.actor(1)])$$,'42501',null,'client cannot enable gate');
select throws_ok($$select public.curate_duel_fixture_event_v1(pg_temp.req(99),now(),now(),'UTC')$$,'42501',null,'client cannot curate');
select throws_ok($$select app.create_duel_at_v1(pg_temp.req(1),pg_temp.actor(2),pg_temp.req(1001),'duel-fixture-5k-v1',true,now())$$,
  '42501',null,'client cannot inject time');
reset role;
select public.set_duel_admission_v1(true,array[pg_temp.actor(1)]);
set local role authenticated;
select throws_ok($$select pg_temp.make(1)$$,'42501',null,'both actors must be allowlisted');
reset role;
select public.set_duel_admission_v1(true,array(select pg_temp.actor(n) from generate_series(1,12) n));
set local role authenticated;
select throws_ok($$select pg_temp.make(1,1)$$,'22023','duel_invalid_terms','self duel refused');
select throws_ok($$select pg_temp.make(1,12)$$,'42501',null,'unaccepted friendship refused');
select throws_ok($$select pg_temp.make(1,2,99)$$,'22023','duel_event_unavailable','unknown event refused');
select throws_ok($$select public.create_duel_v1(pg_temp.req(1),pg_temp.actor(2),pg_temp.req(1001),'organizer_chip_5k_v1',true)$$,
  '22023',null,'unsupported source/policy refused');
select throws_ok($$select public.create_duel_v1(pg_temp.req(1),pg_temp.actor(2),pg_temp.req(1001),'duel-fixture-5k-v1',false)$$,
  '22023',null,'explicit creator consent required');
select throws_ok($$select public.create_duel_v1(pg_temp.req(1),pg_temp.actor(2),pg_temp.req(1001),'duel-fixture-5k-v1',true,'live',5000,1)$$,
  '42883',null,'there is no amount fee or live-mode request overload');
select throws_ok($$select pg_temp.make(1,2,4)$$,'22023',null,'event ending one microsecond beyond 30 elapsed days refused');
select throws_ok($$select pg_temp.make(1,2,5)$$,'22023',null,'creation at start minus one hour is too late');
insert into pg_temp.saved values('a',pg_temp.make(1));
select is(pg_temp.make(1),pg_temp.saved('a'),'exact create retry returns same agreement');
select throws_ok($$select pg_temp.make(1,3)$$,'22023','duel_request_payload_conflict','changed invitee under key refused');
select throws_ok($$select pg_temp.make(1,2,2)$$,'22023',null,'changed event under key refused');
select throws_ok($$select pg_temp.make(2,3)$$,'23505','duel_slot_occupied','creator has only one slot');
select is((public.get_duel_v1(pg_temp.saved('a'))->'terms'->'policy'->>'stake_cents_each'),'2000','server fixes simulated 2000 cents');
select is((public.get_duel_v1(pg_temp.saved('a'))->'terms'->'policy'->>'fee_cents_each'),'0','fee fixed to zero');
select is((public.get_duel_v1(pg_temp.saved('a'))->'terms'->'policy'->>'mode'),'simulated','mode fixed to simulation');
select is((select count(*) from public.duel_participants),2::bigint,'pair sees exactly two consent rows');
select is((select count(*) from public.duel_participants where accepted_at is not null),1::bigint,'creator consents at creation');
select is((select accept_by from public.duel_challenges where id=pg_temp.saved('a')),'2026-11-01 14:00Z'::timestamptz,'cutoff uses common event instant across DST');
create temp table original_terms as select terms,terms_digest from public.duel_challenges where id=pg_temp.saved('a');
set local timezone='Pacific/Auckland';
select is((select terms from public.duel_challenges where id=pg_temp.saved('a')),(select terms from original_terms),'changing display timezone never changes frozen JSON');
select is(pg_temp.make(1),pg_temp.saved('a'),'exact retry independent of session timezone');
set local timezone='UTC';
select throws_ok($$select pg_temp.respond('accept_duel_v1',3,pg_temp.saved('a'))$$,'42501','duel_invitee_required','creator cannot supply second consent');

-- Incoming invitations do not reserve B. Multiple creators may name B.
select pg_temp.login(3);
insert into pg_temp.saved values('c',pg_temp.make(4));
select is((select count(*) from public.duel_challenges),1::bigint,'unrelated agreement hidden by RLS');
select throws_ok($$select public.get_duel_v1(pg_temp.saved('a'))$$,'42501','duel_unavailable','unrelated detail denied');
select throws_ok($$select public.accept_duel_v1(pg_temp.req(5),pg_temp.saved('a'),'duel-fixture-5k-v1','x')$$,'42501',null,'unrelated accept denied');
select pg_temp.login(2);
select is((select count(*) from public.list_my_duels_v1()),2::bigint,'invitee sees both pending invitations');
select is((select terms from public.duel_challenges where id=pg_temp.saved('a')),(select terms from original_terms),'invitee reads identical complete terms');
select is((select terms_digest from public.duel_challenges where id=pg_temp.saved('a')),(select terms_digest from original_terms),'invitee reads identical complete digest');
select throws_ok($$select pg_temp.respond('accept_duel_v1',6,pg_temp.saved('a'),digest=>'wrong')$$,'22023','duel_consent_mismatch','wrong full digest refused');
select throws_ok($$select pg_temp.respond('accept_duel_v1',6,pg_temp.saved('a'),policy_version=>'wrong')$$,
  '22023','duel_consent_mismatch','wrong policy version refused');
select throws_ok($$select pg_temp.respond('cancel_duel_v1',6,pg_temp.saved('a'))$$,'42501',null,'unaccepted invitee uses decline, cannot cancel');
select throws_ok($$select pg_temp.respond('accept_duel_v1',6,pg_temp.saved('a'),'2026-11-01 14:00Z')$$,
  '55000','duel_acceptance_expired','cutoff equality is too late');
select is(pg_temp.respond('accept_duel_v1',6,pg_temp.saved('a'),'2026-11-01 13:59:59.999999Z'),pg_temp.saved('a'),'one microsecond before cutoff accepts');
select is((public.get_duel_v1(pg_temp.saved('a'))->>'status'),'scheduled','two consents persist scheduled');
select throws_ok($$select pg_temp.respond('accept_duel_v1',7,pg_temp.saved('c'))$$,'23505','duel_slot_occupied','accepted actor cannot occupy second duel');
select throws_ok($$select pg_temp.respond('accept_duel_v1',8,pg_temp.saved('a'))$$,'55000','duel_already_accepted','new key cannot consent twice');
select throws_ok($$select pg_temp.respond('decline_duel_v1',6,pg_temp.saved('a'))$$,'22023',null,'request key cannot change operation');
reset role;
select is((select count(*) from app.duel_enrollments where released_at is null),3::bigint,'exactly A B and C hold slots');
select is((select count(*) from app.duel_requests),3::bigint,'refused requests leave no committed request row');
select public.set_duel_admission_v1(false,'{}');
set local role authenticated;
select pg_temp.login(1);
select is(pg_temp.make(1,2,1,'2027-01-01'),pg_temp.saved('a'),'create recovery survives cutoff and gate off');
select pg_temp.login(2);
select is(pg_temp.respond('accept_duel_v1',6,pg_temp.saved('a'),'2027-01-01'),pg_temp.saved('a'),'accept recovery survives cutoff and gate off');
select is((select count(*) from public.list_my_duels_v1()),2::bigint,'history survives gate off and removed allowlist');
select throws_ok($$select pg_temp.respond('accept_duel_v1',7,pg_temp.saved('c'))$$,'42501',null,'gate off blocks new acceptance');
select throws_ok($$select pg_temp.respond('cancel_duel_v1',9,pg_temp.saved('a'),'2026-11-01 15:00Z')$$,
  '55000','duel_already_started','cancel at start equality refused');
select is(pg_temp.respond('cancel_duel_v1',9,pg_temp.saved('a'),'2026-11-01 14:30Z'),pg_temp.saved('a'),'accepted invitee can safely cancel with gate off');
select is(pg_temp.respond('cancel_duel_v1',9,pg_temp.saved('a'),'2027-01-01'),pg_temp.saved('a'),'exact cancellation recovery after start');
select is(pg_temp.respond('decline_duel_v1',10,pg_temp.saved('c')),pg_temp.saved('c'),'decline safely works with gate off');
select is(pg_temp.respond('decline_duel_v1',10,pg_temp.saved('c'),'2027-01-01'),pg_temp.saved('c'),'decline exact recovery survives time');
reset role;
select is((select count(*) from app.duel_enrollments where released_at is null),0::bigint,'cancel and decline release all slots');
select is((select count(*) from public.duel_participants where accepted_at is not null),3::bigint,'cancellation preserves explicit consents');
select is((select count(*) from public.duel_participants where declined_at is not null),1::bigint,'decline history retained');
set constraints all immediate;
set constraints all deferred;

-- Immutable facts and no direct table/service bypass, even with forged GUC.
select throws_ok($$update public.duel_policy_versions set specification='{}'$$,'23001',null,'policy immutable');
select throws_ok($$update public.duel_event_fixtures set display_timezone='UTC'$$,'23001',null,'event immutable');
select throws_ok($$update public.duel_challenges set terms=terms||'{"mode":"live"}'$$,'23001',null,'complete terms immutable');
select throws_ok($$update public.duel_participants set consent_terms_digest='x' where accepted_at is not null$$,'23001',null,'consent immutable');
select throws_ok($$delete from app.duel_requests$$,'23001',null,'request ledger retained');
select throws_ok($$truncate public.duel_challenges cascade$$,'23001',null,'privileged truncate cannot erase agreement audit');
set local role service_role;
select throws_ok($$insert into public.duel_policy_versions values('live','{}')$$,'42501',null,'service cannot invent policy');
select throws_ok($$update app.duel_runtime set admission_enabled=true$$,'42501',null,'service direct gate write denied');
select throws_ok($$select app.expire_duel_invitation_at_v1(pg_temp.saved('a'),now())$$,'42501',null,'service cannot call private clock helper');
select throws_ok($$select public.create_duel_v1(pg_temp.req(99),pg_temp.actor(2),pg_temp.req(1001),'duel-fixture-5k-v1',true)$$,'42501',null,'service cannot impersonate user RPC');
reset role;
set local role authenticated;
select set_config('app.duel_write_v1','on',true);
select throws_ok($$update public.duel_challenges set status='scheduled'$$,'42501',null,'client direct update denied with forged GUC');
select throws_ok($$insert into public.duel_participants(challenge_id,actor_id,role) values(pg_temp.saved('a'),pg_temp.actor(3),'invitee')$$,
  '42501',null,'client cannot add third participant');
select throws_ok($$delete from public.duel_participants$$,'42501',null,'client cannot delete consent');
select throws_ok($$select * from app.duel_requests$$,'42501',null,'requests private');
select throws_ok($$select * from app.duel_enrollments$$,'42501',null,'enrollments private');
select throws_ok($$select * from app.duel_beta_allowlist$$,'42501',null,'allowlist private');
select throws_ok($$select public.list_my_duels_v1(101)$$,'22023',null,'history pagination bounded');
set local role anon;
select throws_ok($$select public.get_duel_v1(pg_temp.saved('a'))$$,'42501',null,'anonymous detail denied');
select throws_ok($$select * from public.duel_challenges$$,'42501',null,'anonymous table read denied');
reset role;

-- Expiry at both cutoff shapes, subsequent creation and transaction rollback.
select public.set_duel_admission_v1(true,array(select pg_temp.actor(n) from generate_series(1,12) n));
set local role authenticated;
select pg_temp.login(4);
insert into pg_temp.saved values('expiry',pg_temp.make(20,5,2));
select is((select accept_by from public.duel_challenges where id=pg_temp.saved('expiry')),'2026-11-03 12:00Z'::timestamptz,'72 elapsed hour cutoff wins for later event');
reset role;
select is(app.expire_duel_invitation_at_v1(pg_temp.saved('expiry'),'2026-11-03 11:59:59.999999Z'),false,'expiry before cutoff no-op');
select is(app.expire_duel_invitation_at_v1(pg_temp.saved('expiry'),'2026-11-03 12:00Z'),true,'expiry at equality closes');
select is(app.expire_duel_invitation_at_v1(pg_temp.saved('expiry'),'2026-11-04'),false,'repeated expiry is no-op');
set local role authenticated;
select pg_temp.login(4);
insert into pg_temp.saved values('autoold',pg_temp.make(21,5,2));
insert into pg_temp.saved values('autonew',pg_temp.make(22,5,3,'2026-11-03 12:00Z'));
select is((public.get_duel_v1(pg_temp.saved('autoold'))->>'status'),'expired','next create atomically expires overdue creator slot');
select is((public.get_duel_v1(pg_temp.saved('autonew'))->>'status'),'invited','next create acquires released slot');
select pg_temp.login(6);
insert into pg_temp.saved values('maxwindow',pg_temp.make(23,7,3));
select is((public.get_duel_v1(pg_temp.saved('maxwindow'))->>'status'),'invited','exact 30 elapsed day window accepted');
reset role;

-- Force failure at the last write, after an overdue slot was released.
create function pg_temp.reject_request() returns trigger language plpgsql as $$
begin raise exception 'injected_failure' using errcode='P0001'; end; $$;
create trigger duel_test_failure before insert on app.duel_requests for each row execute function pg_temp.reject_request();
set local role authenticated;
select throws_ok($$select pg_temp.make(24,7,3,'2026-11-04')$$,'P0001','injected_failure','late write failure rolls back complete creation');
select is((public.get_duel_v1(pg_temp.saved('maxwindow'))->>'status'),'invited','failed create rolls back opportunistic expiry too');
reset role;
drop trigger duel_test_failure on app.duel_requests;
select is((select count(*) from app.duel_requests where request_id=pg_temp.req(24)),0::bigint,'failed create leaves no request');
select is((select count(*) from app.duel_enrollments where actor_id=pg_temp.actor(6) and released_at is null),1::bigint,'failed create leaves exactly original slot');

select pg_temp.login(9);
insert into pg_temp.saved values('acceptrollback',pg_temp.make(25,5));
create trigger duel_test_failure before insert on app.duel_requests for each row execute function pg_temp.reject_request();
set local role authenticated;
select pg_temp.login(5);
select throws_ok($$select pg_temp.respond('accept_duel_v1',26,pg_temp.saved('acceptrollback'))$$,'P0001','injected_failure','late acceptance failure rolls back state consent and slot');
select is((public.get_duel_v1(pg_temp.saved('acceptrollback'))->>'status'),'invited','failed acceptance preserves invitation');
select is((select count(*) from public.duel_participants where challenge_id=pg_temp.saved('acceptrollback') and accepted_at is not null),1::bigint,'failed acceptance records no second consent');
reset role;
drop trigger duel_test_failure on app.duel_requests;
select is((select count(*) from app.duel_enrollments where actor_id=pg_temp.actor(5) and released_at is null),0::bigint,'failed acceptance reserves no invitee slot');

-- Block checks at create and accept. Agreement-only history remains readable
-- for safe cancellation; no new profile visibility is granted by a duel.
insert into public.blocks(blocker_id,blocked_id) values(pg_temp.actor(8),pg_temp.actor(9));
set local role authenticated;
select pg_temp.login(8);
select throws_ok($$select pg_temp.make(30,9)$$,'42501',null,'blocked pair cannot create');
select pg_temp.login(10);
insert into pg_temp.saved values('blocked',pg_temp.make(31,11));
reset role;
insert into public.blocks(blocker_id,blocked_id) values(pg_temp.actor(10),pg_temp.actor(11));
set local role authenticated;
select pg_temp.login(11);
select throws_ok($$select pg_temp.respond('accept_duel_v1',32,pg_temp.saved('blocked'))$$,'42501',null,'block after creation prevents acceptance');
select is((select count(*) from public.profiles where id=pg_temp.actor(10)),0::bigint,'duel does not grant opponent profile visibility across block');
select pg_temp.login(10);
select is(pg_temp.respond('cancel_duel_v1',33,pg_temp.saved('blocked')),pg_temp.saved('blocked'),'block does not prevent safe cancellation');
reset role;

-- Real-clock agreements exercise the unchanged D81 service deletion RPC.
select public.curate_duel_fixture_event_v1(pg_temp.req(1010),clock_timestamp()+interval '2 days',clock_timestamp()+interval '2 days 2 hours','UTC');
select pg_temp.login(8);
insert into pg_temp.saved values('deleted',public.create_duel_v1(pg_temp.req(40),pg_temp.actor(7),pg_temp.req(1010),'duel-fixture-5k-v1',true));
select pg_temp.login(7);
select public.accept_duel_v1(pg_temp.req(41),pg_temp.saved('deleted'),'duel-fixture-5k-v1',(select terms_digest from public.duel_challenges where id=pg_temp.saved('deleted')));
select public.delete_account(pg_temp.actor(8));
select is((select status from public.duel_challenges where id=pg_temp.saved('deleted')),'cancelled','pre-start deletion cancels scheduled duel');
select is((select close_reason from public.duel_challenges where id=pg_temp.saved('deleted')),'account_deleted','deletion reason retained');
select is((select count(*) from app.duel_enrollments where challenge_id=pg_temp.saved('deleted') and released_at is null),0::bigint,'deletion releases both slots');
select is((select count(*) from public.duel_participants where challenge_id=pg_temp.saved('deleted') and accepted_at is not null),2::bigint,'deletion preserves both consents');
select ok((select deleted_at is not null from public.profiles where id=pg_temp.actor(8)),'actor is tombstoned');
select is((select count(*) from app.duel_beta_allowlist where actor_id=pg_temp.actor(8)),0::bigint,'deletion revokes allowlist');
set local role authenticated;
select pg_temp.login(8);
select is((select count(*) from public.duel_challenges),0::bigint,'stale JWT cannot read duel rows');
select is((select count(*) from public.duel_participants),0::bigint,'stale JWT cannot read consents');
select throws_ok($$select public.get_duel_v1(pg_temp.saved('deleted'))$$,'42501',null,'deleted actor detail denied');
select throws_ok($$select public.create_duel_v1(pg_temp.req(40),pg_temp.actor(7),pg_temp.req(1010),'duel-fixture-5k-v1',true)$$,
  '42501',null,'deleted actor cannot recover committed create');
select pg_temp.login(7);
select is(public.accept_duel_v1(pg_temp.req(41),pg_temp.saved('deleted'),'duel-fixture-5k-v1',(select terms_digest from public.duel_challenges where id=pg_temp.saved('deleted'))),
  pg_temp.saved('deleted'),'active peer can recover committed consent after opponent deletion');
select is((public.get_duel_v1(pg_temp.saved('deleted'))->>'status'),'cancelled','active peer retains minimal agreement history');
select pg_temp.login(9);
select throws_ok($$select public.create_duel_v1(pg_temp.req(42),pg_temp.actor(8),pg_temp.req(1010),'duel-fixture-5k-v1',true)$$,'42501',null,'deleted invitee refused');
reset role;

-- Read-only due-expiry projection is based on real server time and leaves the
-- retained row alone. Creation's clock seam supplies an overdue invitation.
select pg_temp.login(11);
insert into pg_temp.saved values('readexpiry',pg_temp.make(43,7,10,clock_timestamp()-interval '80 hours'));
set local role authenticated;
select is((public.get_duel_v1(pg_temp.saved('readexpiry'))->>'expiry_due')::boolean,true,'read reports overdue invitation');
select is((public.get_duel_v1(pg_temp.saved('readexpiry'))->>'status'),'invited','read does not mutate expired state');
reset role;
set constraints all immediate;
select * from finish();
rollback;
