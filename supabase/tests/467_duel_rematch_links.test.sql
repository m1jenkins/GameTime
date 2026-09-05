-- Phase 2(d), rollback-only participant projection tests. No operator data added.
begin;
select no_plan();
set local timezone='UTC';
create function pg_temp.actor(n integer) returns uuid language sql immutable as $$
  select ('db100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.session(n integer) returns uuid language sql immutable as $$
  select ('db200000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.login(n integer) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub',pg_temp.actor(n)::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.actor(n),'role','authenticated',
    'session_id',pg_temp.session(n))::text,true);
end; $$;
insert into auth.users(id) select pg_temp.actor(n) from generate_series(1,5) n;
insert into public.profiles(id,handle,display_name,timezone)
  select pg_temp.actor(n),'nativeprojection'||n,'Fictional Runner','UTC' from generate_series(1,5) n;
insert into auth.sessions(id,user_id) select pg_temp.session(n),pg_temp.actor(n) from generate_series(1,5) n;
insert into public.friendships(user_a,user_b,requested_by,status)
  values(pg_temp.actor(1),pg_temp.actor(2),pg_temp.actor(1),'accepted'),
        (pg_temp.actor(3),pg_temp.actor(4),pg_temp.actor(3),'accepted');
select public.set_duel_admission_v1(true,array(select pg_temp.actor(n) from generate_series(1,4) n));
select public.set_duel_lifecycle_enabled_v1(true);
create temp table ids(name text,id uuid);
grant select,insert on ids to authenticated;
create function pg_temp.id(n text) returns uuid language sql as $$select id from ids where name=n$$;
create function pg_temp.make(a integer,b integer,age integer) returns uuid language plpgsql as $$
declare t timestamptz:=clock_timestamp()-make_interval(days=>age); e uuid:=extensions.gen_random_uuid(); c uuid;
begin
  perform public.curate_duel_fixture_event_v1(e,t+interval '3 days',t+interval '3 days 2 hours','America/Chicago');
  perform pg_temp.login(a);
  c:=app.create_duel_at_v1(extensions.gen_random_uuid(),pg_temp.actor(b),e,'duel-fixture-5k-v1',true,t);
  perform pg_temp.login(b);
  perform app.respond_duel_at_v1('accept_duel_v1',extensions.gen_random_uuid(),c,'duel-fixture-5k-v1',
    (select terms_digest from public.duel_challenges where id=c),t+interval '1 hour');
  return c;
end; $$;
insert into ids values('old',pg_temp.make(1,2,20));
create function pg_temp.notice(c uuid,t timestamptz,phase text default 'provisional') returns text language plpgsql as $$
declare i jsonb; d jsonb;
begin
  i:=app.duel_lifecycle_load_at_v1(c,t);
  d:=jsonb_build_object('version','duel-fixture-official-5k-v1','challengeId',c,'termsDigest',i->'agreement'->'terms_digest',
    'phase',phase,'proofRevision',0,'outcome',jsonb_build_object('kind','void','reason','unresolved_proof'),
    'disputeClosesAt',null,'reviewDueAt',null,'supportCorrectionRequired',false);
  return app.duel_lifecycle_commit_at_v1(i,d,t);
end; $$;

select pg_temp.notice(pg_temp.id('old'),clock_timestamp()-interval '8 days');
select pg_temp.notice(pg_temp.id('old'),clock_timestamp(),'ready_to_finalize');
select public.curate_duel_fixture_event_v1(pg_temp.session(100),clock_timestamp()+interval '5 days',clock_timestamp()+interval '5 days 2 hours','America/Chicago');
select pg_temp.login(1);
set local role authenticated;
select throws_ok($$select public.rematch_duel_v1(pg_temp.session(101),pg_temp.id('old'),pg_temp.session(100),'duel-fixture-5k-v1',false)$$,'22023',null,'fresh creator consent required');
insert into ids values('new',public.rematch_duel_v1(pg_temp.session(101),pg_temp.id('old'),pg_temp.session(100),'duel-fixture-5k-v1',true));
reset role;
select isnt(pg_temp.id('new'),pg_temp.id('old'),'rematch is a fresh aggregate');
select is((select previous_challenge_id from app.duel_rematches where challenge_id=pg_temp.id('new')),pg_temp.id('old'),'provenance is separate');
select is((select count(*)::int from public.duel_participants where challenge_id=pg_temp.id('new') and accepted_at is not null),1,'only fresh creator consent saved');
select is((select count(*)::int from public.duel_participants where challenge_id=pg_temp.id('old') and accepted_at is not null),2,'historical consent preserved');
set local role authenticated;
select is(public.rematch_duel_v1(pg_temp.session(101),pg_temp.id('old'),pg_temp.session(100),'duel-fixture-5k-v1',true),pg_temp.id('new'),'exact rematch retry');
select throws_ok($$select public.rematch_duel_v1(pg_temp.session(101),pg_temp.id('old'),pg_temp.session(100),'duel-fixture-5k-v1',false)$$,'22023',null,'changed rematch payload rejected');
select throws_ok($$select public.rematch_duel_v1(pg_temp.session(102),pg_temp.id('new'),pg_temp.session(100),'duel-fixture-5k-v1',true)$$,'55000',null,'unfinished prior duel cannot rematch');
select is(public.issue_duel_link_v1(pg_temp.session(103),pg_temp.id('new')),pg_temp.id('new'),'creator issues link');
insert into ids values('link',(public.get_my_duel_link_v1(pg_temp.id('new'))->>'token')::uuid);
reset role;
select is((select expires_at=least(created_at+interval '24 hours',(select accept_by from public.duel_challenges where id=pg_temp.id('new'))) from app.duel_invitation_links where token=pg_temp.id('link')),true,'link bounded by 24h and consent cutoff');
set local role authenticated;
select throws_ok($$select public.resolve_duel_link_v1(pg_temp.id('link'))$$,'42501',null,'creator is not named recipient');
select throws_ok($$select * from app.duel_invitation_links$$,'42501',null,'no direct private link read');
select throws_ok($$select app.read_duel_link_at_v1(null,pg_temp.id('link'),clock_timestamp())$$,'42501',null,'private clock seam denied');
reset role;
select pg_temp.login(3);
set local role authenticated;
select throws_ok($$select public.resolve_duel_link_v1(pg_temp.id('link'))$$,'42501',null,'forwarded link grants no access');
reset role;
select pg_temp.login(2);
set local role authenticated;
select is(public.resolve_duel_link_v1(pg_temp.id('link')),jsonb_build_object('challengeId',pg_temp.id('new')),'target resolves only destination');
select throws_ok($$select public.get_my_duel_link_v1(pg_temp.id('new'))$$,'42501',null,'recipient cannot read issuer token record');
select throws_ok($$select public.issue_duel_link_v1(pg_temp.session(105),pg_temp.id('new'))$$,'42501',null,'recipient cannot issue');
reset role;
select is((select count(*)::int from public.duel_participants where challenge_id=pg_temp.id('new') and accepted_at is not null),1,'opening link never consents');
create function pg_temp.expired_link() returns jsonb language plpgsql security definer as $$
begin return app.read_duel_link_at_v1(null,pg_temp.id('link'),(select expires_at from app.duel_invitation_links where token=pg_temp.id('link'))); end $$;
set local role authenticated;
select throws_ok('select pg_temp.expired_link()','42501',null,'expiry equality denied');
reset role;
insert into public.blocks(blocker_id,blocked_id) values(pg_temp.actor(1),pg_temp.actor(2));
set local role authenticated;
select throws_ok($$select public.resolve_duel_link_v1(pg_temp.id('link'))$$,'42501',null,'blocked target denied');
reset role;
delete from public.blocks where blocker_id=pg_temp.actor(1) and blocked_id=pg_temp.actor(2);
insert into public.friendships(user_a,user_b,requested_by,status) values(pg_temp.actor(1),pg_temp.actor(2),pg_temp.actor(1),'accepted') on conflict(user_a,user_b) do update set status='accepted';
select public.set_duel_admission_v1(false,'{}');
select pg_temp.login(1);
set local role authenticated;
select is(public.rematch_duel_v1(pg_temp.session(101),pg_temp.id('old'),pg_temp.session(100),'duel-fixture-5k-v1',true),pg_temp.id('new'),'gate-off recovers prior rematch');
select is(public.issue_duel_link_v1(pg_temp.session(103),pg_temp.id('new')),pg_temp.id('new'),'gate-off recovers prior link request');
select throws_ok($$select public.issue_duel_link_v1(pg_temp.session(104),pg_temp.id('new'))$$,'42501',null,'gate-off denies new link');
select is(public.revoke_duel_link_v1(pg_temp.session(106),pg_temp.id('new'),pg_temp.id('link')),pg_temp.id('new'),'gate-off safe revoke');
select is(public.issue_duel_link_v1(pg_temp.session(103),pg_temp.id('new')),pg_temp.id('new'),'issue retry never reactivates revoked link');
select is(public.get_my_duel_link_v1(pg_temp.id('new')),null::jsonb,'revoked creator projection empty');
reset role;
select pg_temp.login(2);
set local role authenticated;
select throws_ok($$select public.resolve_duel_link_v1(pg_temp.id('link'))$$,'42501',null,'revoked link denied');
reset role;
select public.set_duel_admission_v1(true,array[pg_temp.actor(1),pg_temp.actor(2)]);
select pg_temp.login(1);
set local role authenticated;
select public.issue_duel_link_v1(pg_temp.session(107),pg_temp.id('new'));
insert into ids values('second-link',(public.get_my_duel_link_v1(pg_temp.id('new'))->>'token')::uuid);
reset role;
select isnt(pg_temp.id('link'),pg_temp.id('second-link'),'replacement uses new token');
savepoint cancelled_link;
set local role authenticated;
select public.cancel_duel_v1(pg_temp.session(109),pg_temp.id('new'));
reset role;
select pg_temp.login(2);
set local role authenticated;
select throws_ok($$select public.resolve_duel_link_v1(pg_temp.id('second-link'))$$,'42501',null,'cancelled invitation link closes immediately');
reset role;
rollback to cancelled_link;
savepoint deleted_recipient;
select public.delete_account(pg_temp.actor(2));
set local role authenticated;
select throws_ok($$select public.get_my_duel_link_v1(pg_temp.id('new'))$$,'42501',null,'creator cannot share with deleted recipient');
reset role;
select pg_temp.login(2);
set local role authenticated;
select throws_ok($$select public.resolve_duel_link_v1(pg_temp.id('second-link'))$$,'42501',null,'deleted recipient cannot open stale link');
reset role;
rollback to deleted_recipient;

select pg_temp.login(2);
set local role authenticated;
select is(public.accept_duel_v1(pg_temp.session(108),pg_temp.id('new'),'duel-fixture-5k-v1',public.get_duel_v1(pg_temp.id('new'))->>'terms_digest'),pg_temp.id('new'),'second actor explicitly consents to new rules');
select throws_ok($$select public.resolve_duel_link_v1(pg_temp.id('second-link'))$$,'42501',null,'accepted invitation link closes');
reset role;
select is((select count(*)::int from public.duel_participants where challenge_id=pg_temp.id('new') and accepted_at is not null),2,'two fresh consents');
select pg_temp.login(1);
delete from auth.sessions where id=pg_temp.session(1);
set local role authenticated;
select throws_ok($$select public.issue_duel_link_v1(pg_temp.session(103),pg_temp.id('new'))$$,'42501',null,'revoked session loses even exact recovery');
reset role;
set local role anon;
select throws_ok($$select public.resolve_duel_link_v1(pg_temp.id('second-link'))$$,'42501',null,'unauthenticated link resolution denied');
reset role;
select finish();
rollback;
