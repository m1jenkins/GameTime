-- Rollback-only owner agreement, clock, consent, privacy and retention tests.
begin;
select no_plan();
set local timezone='UTC';
create function pg_temp.actor(n integer) returns uuid language sql immutable as $$
  select ('ec100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.req(n integer) returns uuid language sql immutable as $$
  select ('ec200000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.login(n integer) returns void language plpgsql as $$ begin
  perform set_config('request.jwt.claim.sub',pg_temp.actor(n)::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.actor(n),'role','authenticated','session_id',pg_temp.req(n))::text,true);
end; $$;
insert into auth.users(id) select pg_temp.actor(n) from generate_series(1,12) n;
insert into public.profiles(id,handle,display_name,timezone)
  select pg_temp.actor(n),'commitmenttest'||n,'Fictional Runner','UTC' from generate_series(1,12) n;
insert into auth.sessions(id,user_id) select pg_temp.req(n),pg_temp.actor(n) from generate_series(1,12) n;
create temp table saved(name text primary key,id uuid);
grant select,insert on saved to authenticated;
create function pg_temp.id(n text) returns uuid language sql as $$select id from saved where name=n$$;
create function pg_temp.make(q integer,seconds integer default 1500,
  s timestamptz default '2026-10-31 12:00:00.123456Z',d timestamptz default '2026-12-30 12:00:00.123456Z',
  zone text default 'America/Chicago',n timestamptz default '2026-10-30 12:00:00.123456Z',consent boolean default true,
  expected_digest text default null,policy text default 'performance-commitment-fixture-5k-v1') returns uuid
language plpgsql security definer set search_path='' as $$ declare digest text; begin
  digest:=coalesce(expected_digest,encode(extensions.digest(app.performance_commitment_terms_v1(auth.uid(),seconds,s,d,zone,policy)::text,'sha256'),'hex'));
  return app.create_performance_commitment_at_v1(pg_temp.req(q),seconds,s,d,zone,policy,digest,consent,n);
end; $$;
create function pg_temp.close(q integer,c uuid,reason text,n timestamptz) returns uuid
language sql security definer set search_path='' as $$select app.close_performance_commitment_at_v1(pg_temp.req(q),c,reason,n)$$;

select is((select admission_enabled from app.performance_commitment_runtime),false,'admission defaults off');
select is((select count(*) from app.performance_commitment_beta_allowlist),0::bigint,'empty admission list');
select is((select count(*) from cron.job where command ilike '%performance_commitment%'),0::bigint,'no commitment schedule');
select is((select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='app'
  and c.relname like 'performance_commitment_%' and c.relkind='r' and not c.relrowsecurity),0::bigint,'RLS on every new table');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('app','public')
  and p.proname like '%performance_commitment%v1' and p.prosecdef and not ('search_path=""'=any(p.proconfig))),0::bigint,'empty definer search paths');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='app'
  and p.proname like '%performance_commitment%v1' and has_function_privilege('authenticated',p.oid,'execute')),0::bigint,'no private helper or clock grant');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
  and p.proname like '%performance_commitment%v1' and has_function_privilege('authenticated',p.oid,'execute')),5::bigint,'five owner RPCs only');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('app','public')
  and p.proname like '%performance_commitment%v1' and has_function_privilege('anon',p.oid,'execute')),0::bigint,'no anonymous RPCs');
select pg_temp.login(1);
set local role authenticated;
select throws_ok('select pg_temp.make(1)','42501',null,'gate-off rejects create');
select throws_ok('select public.set_performance_commitment_admission_v1(true,array[pg_temp.actor(1)])','42501',null,'participant cannot enable admission');
select throws_ok('select * from app.performance_commitment_agreements','42501',null,'private agreements cannot be read directly');
select throws_ok('select * from app.performance_commitment_requests','42501',null,'private payloads cannot be read directly');
reset role;
select public.set_performance_commitment_admission_v1(true,array[pg_temp.actor(2)]);
set local role authenticated;
select throws_ok('select pg_temp.make(1)','42501',null,'allowlist required');
reset role;
select public.set_performance_commitment_admission_v1(true,array(select pg_temp.actor(n) from generate_series(1,12) n));
-- An accepted duel and existing Personal agreement occupy their own slots.
insert into public.friendships(user_a,user_b,requested_by,status) values(pg_temp.actor(1),pg_temp.actor(2),pg_temp.actor(1),'accepted');
select public.set_duel_admission_v1(true,array[pg_temp.actor(1),pg_temp.actor(2)]);
select public.curate_duel_fixture_event_v1(pg_temp.req(100),clock_timestamp()+interval '3 days',clock_timestamp()+interval '3 days 2 hours','UTC');
set local role authenticated;
insert into saved values('personal',public.create_personal_challenge_v2(pg_temp.req(1),'daily',10000,1000,'UTC'));
insert into saved values('duel',public.create_duel_v1(pg_temp.req(1),pg_temp.actor(2),pg_temp.req(100),'duel-fixture-5k-v1',true));
select pg_temp.login(2);
select public.accept_duel_v1(pg_temp.req(1),pg_temp.id('duel'),'duel-fixture-5k-v1',public.get_duel_v1(pg_temp.id('duel'))->>'terms_digest');
reset role;
create temp table legacy_before as select
  (select jsonb_agg(to_jsonb(t)) from public.personal_challenge_terms t where challenge_id=pg_temp.id('personal')) personal,
  (select jsonb_agg(to_jsonb(t)) from app.duel_enrollments t where challenge_id=pg_temp.id('duel')) duel_slots,
  (select terms from public.duel_challenges where id=pg_temp.id('duel')) duel_terms,
  (select count(*) from public.solo_contracts) solo_count;
select pg_temp.login(1);
set local role authenticated;
select throws_ok('select pg_temp.make(1,consent=>false)','22023',null,'explicit consent required');
select throws_ok('select pg_temp.make(1,consent=>null)','22023',null,'null consent rejected');
select throws_ok($$select pg_temp.make(1,expected_digest=>'bad')$$,'22023',null,'wrong digest rejected');
select throws_ok($$select pg_temp.make(1,policy=>'solo-test-v1')$$,'22023',null,'old policy cannot authorize new agreement');
select throws_ok($$select pg_temp.make(1,zone=>'Mars/Base')$$,'22023',null,'unknown timezone rejected');
select throws_ok($$select pg_temp.make(1,s=>'infinity',d=>'infinity')$$,'22023',null,'nonfinite dates rejected');
select throws_ok($$select pg_temp.make(1,seconds=>0)$$,'22023',null,'zero target rejected');
select throws_ok($$select pg_temp.make(1,seconds=>null)$$,'22023',null,'null target rejected');
select throws_ok($$select pg_temp.make(1,seconds=>86401)$$,'22023',null,'target bounded');
select throws_ok($$select pg_temp.make(1,d=>'2026-11-28 12:00:00.123455Z')$$,'22023',null,'one microsecond short of 28 elapsed days rejected');
select throws_ok($$select pg_temp.make(1,d=>'2027-01-29 12:00:00.123457Z')$$,'22023',null,'one microsecond over 90 days rejected');
select throws_ok($$select pg_temp.make(1,n=>'2026-10-31 12:00:00.123456Z')$$,'22023',null,'creation at start is too late');
select throws_ok($$select pg_temp.make(1,n=>'2026-10-01 12:00:00.123455Z')$$,'22023',null,'start beyond 30 days rejected');
insert into saved values('main',pg_temp.make(1));
select is(pg_temp.make(1),pg_temp.id('main'),'exact retry recovers original');
select throws_ok('select pg_temp.make(1,seconds=>1501)','22023',null,'changed target under key rejected');
select throws_ok($$select pg_temp.make(1,zone=>'UTC')$$,'22023',null,'changed display zone under key rejected');
select throws_ok('select pg_temp.make(1,consent=>false)','22023',null,'changed consent under key rejected');
select throws_ok('select pg_temp.make(2)','23505',null,'one open commitment');
select throws_ok($$select pg_temp.make(2,s=>'2027-02-02 12:00Z',d=>'2027-04-03 12:00Z',n=>'2027-02-01 12:00Z')$$,
  '23505',null,'past deadline and finality cap do not implicitly release slot');
select throws_ok($$select pg_temp.close(1,pg_temp.id('main'),'cancel','2026-10-30 13:00Z')$$,'22023',null,'request namespace spans operations');
select is(public.get_performance_commitment_v1(pg_temp.id('main'))->>'phase','scheduled','owner reads scheduled agreement');
select is((select count(*) from public.list_my_performance_commitments_v1()),1::bigint,'owner history');
select throws_ok('select public.list_my_performance_commitments_v1(101)','22023',null,'bounded history');
select throws_ok($$select public.list_my_performance_commitments_v1(1,now(),null)$$,'22023',null,'paired cursor required');
reset role;
set constraints all immediate;
set constraints all deferred;
select is((select deadline_at-starts_at from app.performance_commitment_agreements where id=pg_temp.id('main')),interval '60 days','60 day window across DST');
select is((select terms#>>'{policy,forfeiture_recipient}' from app.performance_commitment_agreements where id=pg_temp.id('main')),'unselected','no recipient implied');
select is((select terms#>>'{policy,mode}' from app.performance_commitment_agreements where id=pg_temp.id('main')),'simulated','simulation only');
select is((select terms#>>'{policy,comparator}' from app.performance_commitment_agreements where id=pg_temp.id('main')),'lt','strict target frozen');
select is((select terms->>'target_ms' from app.performance_commitment_agreements where id=pg_temp.id('main')),'1500000','whole seconds represented as integer milliseconds');
select is((select terms->>'results_due_at' from app.performance_commitment_agreements where id=pg_temp.id('main')),'2027-01-02T12:00:00.123456+00:00','cutoff preserves microseconds');
select is((select s.terms_digest=c.terms_digest and s.accepted_at=c.created_at from app.performance_commitment_consents s
  join app.performance_commitment_agreements c on c.id=s.commitment_id where c.id=pg_temp.id('main')),true,'consent binds exact terms and acceptance time');
select is(app.performance_commitment_projection_v1(pg_temp.id('main'),'2026-10-31 12:00:00.123456Z')->>'phase','active','start equality is active');
select is(app.performance_commitment_projection_v1(pg_temp.id('main'),'2026-12-30 12:00:00.123456Z')->>'phase','awaiting_proof','deadline equality waits for proof');
select is(app.performance_commitment_projection_v1(pg_temp.id('main'),'2028-01-01Z')->>'status','open','overdue agreement never becomes an inferred miss');
select is((select count(*) from app.performance_commitment_enrollments where released_at is null),1::bigint,'clock projection does not release slot');
select set_config('app.performance_commitment_write_v1','on',true);
select throws_ok($$update app.performance_commitment_agreements set target_seconds=1400 where id=pg_temp.id('main')$$,'23001',null,'frozen target immutable');
select throws_ok($$update app.performance_commitment_consents set terms_digest='other' where commitment_id=pg_temp.id('main')$$,'23001',null,'consent immutable');
select throws_ok('delete from app.performance_commitment_agreements','23001',null,'agreements retained');
select throws_ok('truncate app.performance_commitment_requests','23001',null,'retry history cannot be truncated');
create function pg_temp.break_slot() returns void language plpgsql as $$ begin
  update app.performance_commitment_enrollments set released_at='2026-10-31 12:00Z' where commitment_id=pg_temp.id('main');
  set constraints all immediate;
end; $$;
select throws_ok('select pg_temp.break_slot()','23514',null,'deferred invariant rejects release without aggregate closure');
select pg_temp.login(2);
set local role authenticated;
select throws_ok($$select public.get_performance_commitment_v1(pg_temp.id('main'))$$,'42501',null,'other actor cannot read');
select throws_ok($$select public.close_performance_commitment_v1(pg_temp.req(2),pg_temp.id('main'),'injury')$$,'42501',null,'other actor cannot close');
select is((select count(*) from public.list_my_performance_commitments_v1()),0::bigint,'other actor history empty');
insert into saved values('min',pg_temp.make(1,d=>'2026-11-28 12:00:00.123456Z'));
reset role;
select pg_temp.login(3);
set local role authenticated;
insert into saved values('max',pg_temp.make(1,d=>'2027-01-29 12:00:00.123456Z'));
reset role;
select pg_temp.login(4);
set local role authenticated;
insert into saved values('leap',pg_temp.make(1,s=>'2028-02-01 12:00Z',d=>'2028-03-01 12:00Z',n=>'2028-01-31 12:00Z'));
reset role;
select is((select deadline_at-starts_at from app.performance_commitment_agreements where id=pg_temp.id('leap')),interval '29 days','leap day remains in window');
select pg_temp.login(5);
set local role authenticated;
insert into saved values('spring',pg_temp.make(1,s=>'2027-03-01 12:00Z',d=>'2027-03-29 12:00Z',n=>'2027-02-28 12:00Z'));
reset role;
set local timezone='Pacific/Auckland';
select pg_temp.login(1);
set local role authenticated;
select is(pg_temp.make(1),pg_temp.id('main'),'session timezone cannot change payload identity');
reset role;
set local timezone='UTC';
select public.set_performance_commitment_admission_v1(false,'{}');
set local role authenticated;
select is(pg_temp.make(1),pg_temp.id('main'),'gate-off keeps committed recovery');
select lives_ok($$select public.get_performance_commitment_v1(pg_temp.id('main'))$$,'gate-off keeps owner reads');
select throws_ok($$select pg_temp.close(3,pg_temp.id('main'),'cancel','2026-10-31 12:00:00.123456Z')$$,'55000',null,'cancel equality too late');
select throws_ok($$select pg_temp.close(3,pg_temp.id('main'),'withdrawal','2026-10-31 12:00:00.123455Z')$$,'55000',null,'withdrawal not prestart cancellation');
select is(pg_temp.close(3,pg_temp.id('main'),'cancel','2026-10-31 12:00:00.123455Z'),pg_temp.id('main'),'gate-off prestart cancellation works');
select is(pg_temp.close(3,pg_temp.id('main'),'cancel','2026-10-31 12:00:00.123455Z'),pg_temp.id('main'),'close exact retry');
select throws_ok($$select pg_temp.close(3,pg_temp.id('main'),'injury','2026-10-31 12:00:00.123455Z')$$,'22023',null,'close reason cannot change under key');
select throws_ok($$select pg_temp.close(4,pg_temp.id('main'),'injury','2026-10-31 12:00:00.123455Z')$$,'55000',null,'closed agreement cannot transition again');
select is(pg_temp.make(1),pg_temp.id('main'),'old create retry does not reopen closed goal');
reset role;
select is((select released_at=closed_at from app.performance_commitment_enrollments e join app.performance_commitment_agreements c on c.id=e.commitment_id where c.id=pg_temp.id('main')),true,'closure and slot release atomic');
select public.set_performance_commitment_admission_v1(true,array(select pg_temp.actor(n) from generate_series(1,12) n));
set local role authenticated;
insert into saved values('replacement',pg_temp.make(5,seconds=>1400));
reset role;
select isnt(pg_temp.id('main'),pg_temp.id('replacement'),'replacement requires new agreement and consent');
select pg_temp.login(2);
set local role authenticated;
select is(pg_temp.close(2,pg_temp.id('min'),'withdrawal','2026-10-31 12:00:00.123456Z'),pg_temp.id('min'),'withdrawal at start allowed');
reset role;
select pg_temp.login(3);
set local role authenticated;
select is(pg_temp.close(2,pg_temp.id('max'),'injury','2026-11-10 12:00Z'),pg_temp.id('max'),'injury exit needs no medical upload');
reset role;
select is((select status from app.performance_commitment_agreements where id=pg_temp.id('max')),'withdrawn','injury retained as withdrawal, not miss');
-- Real public preview/create boundary with clock-owned instants.
select pg_temp.login(6);
create temp table preview as select clock_timestamp()+interval '1 day' s,clock_timestamp()+interval '61 days' d;
grant select on preview to authenticated;
set local role authenticated;
insert into saved select 'public',public.create_performance_commitment_v1(pg_temp.req(1),1500,s,d,'America/Chicago',
  'performance-commitment-fixture-5k-v1',public.preview_performance_commitment_v1(1500,s,d,'America/Chicago',
    'performance-commitment-fixture-5k-v1')->>'terms_digest',true) from preview;
reset role;
select is((select count(*) from app.performance_commitment_consents where actor_id=pg_temp.actor(6)),1::bigint,'public preview and creation bind one consent');
delete from auth.sessions where user_id=pg_temp.actor(6);
set local role authenticated;
select throws_ok($$select public.get_performance_commitment_v1(pg_temp.id('public'))$$,'42501',null,'revoked session cannot read saved content');
select throws_ok($$select public.close_performance_commitment_v1(pg_temp.req(2),pg_temp.id('public'),'cancel')$$,'42501',null,'revoked session cannot mutate');
reset role;
select pg_temp.login(7);
update auth.sessions set not_after=clock_timestamp()-interval '1 second' where user_id=pg_temp.actor(7);
set local role authenticated;
select throws_ok('select pg_temp.make(1)','42501',null,'expired session rejected');
reset role;
-- Deletion uses the existing service tombstone route and retains this product's
-- immutable rows. The legacy purge has no authority over these private tables.
select pg_temp.login(8);
set local role authenticated;
insert into saved values('deleted',pg_temp.make(1,s=>clock_timestamp()+interval '1 day',d=>clock_timestamp()+interval '61 days',n=>clock_timestamp()));
reset role;
select lives_ok('select public.delete_account(pg_temp.actor(8))','existing deletion closes new prestart agreement');
select is((select close_reason from app.performance_commitment_agreements where id=pg_temp.id('deleted')),'account_deleted','deletion reason retained');
select is((select count(*) from app.performance_commitment_consents where commitment_id=pg_temp.id('deleted')),1::bigint,'deletion preserves consent');
select is((select count(*) from app.performance_commitment_requests where commitment_id=pg_temp.id('deleted')),1::bigint,'deletion preserves exact request');
select is((select count(*) from app.performance_commitment_beta_allowlist where actor_id=pg_temp.actor(8)),0::bigint,'deletion removes admission');
set local role authenticated;
select throws_ok('select pg_temp.make(1)','42501',null,'deleted actor cannot recover stale request');
reset role;
select pg_temp.login(9);
set local role authenticated;
insert into saved values('active-deleted',pg_temp.make(1,s=>clock_timestamp()-interval '2 days',d=>clock_timestamp()+interval '58 days',n=>clock_timestamp()-interval '3 days'));
reset role;
select lives_ok('select public.delete_account(pg_temp.actor(9))','deletion safely closes active simulated commitment');
select is((select status from app.performance_commitment_agreements where id=pg_temp.id('active-deleted')),'withdrawn','active deletion is withdrawal');
select is((select jsonb_agg(to_jsonb(t)) from public.personal_challenge_terms t where challenge_id=pg_temp.id('personal')),
  (select personal from legacy_before),'Personal terms unchanged throughout commitment create/close/delete');
select is((select jsonb_agg(to_jsonb(t)) from app.duel_enrollments t where challenge_id=pg_temp.id('duel')),
  (select duel_slots from legacy_before),'commitment never consumes or releases duel slots');
select is((select terms from public.duel_challenges where id=pg_temp.id('duel')),
  (select duel_terms from legacy_before),'duel terms unchanged');
select is((select count(*) from public.solo_contracts),(select solo_count from legacy_before),'Solo remains untouched');
create temp table retained as select
  (select jsonb_agg(to_jsonb(t) order by id) from app.performance_commitment_agreements t) agreements,
  (select jsonb_agg(to_jsonb(t) order by commitment_id) from app.performance_commitment_consents t) consents;
select lives_ok($$select * from app.run_raw_evidence_retention('2030-01-01Z',500)$$,'legacy retention still runs');
select is((select jsonb_agg(to_jsonb(t) order by id) from app.performance_commitment_agreements t),
  (select agreements from retained),'legacy retention cannot prune open or deleted commitment agreements');
select is((select jsonb_agg(to_jsonb(t) order by commitment_id) from app.performance_commitment_consents t),
  (select consents from retained),'legacy retention preserves new consents');
set constraints all immediate;
select * from finish();
rollback;
