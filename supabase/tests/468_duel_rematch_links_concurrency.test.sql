-- Two real transactions, with observed blocking; exclusively fictional de records.
begin;
select no_plan();
select extensions.dblink_connect('link_setup','host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres');
select extensions.dblink_connect('link_one','host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres application_name=link_race_one');
select extensions.dblink_connect('link_two','host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres application_name=link_race_two');
select extensions.dblink_exec('link_setup',$setup$begin;
set local timezone='UTC';
create function pg_temp.actor(n integer) returns uuid language sql immutable as $$
  select ('de100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.session(n integer) returns uuid language sql immutable as $$
  select ('de200000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.login(n integer) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub',pg_temp.actor(n)::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.actor(n),'role','authenticated',
    'session_id',pg_temp.session(n))::text,true);
end; $$;
insert into auth.users(id) select pg_temp.actor(n) from generate_series(1,5) n;
insert into public.profiles(id,handle,display_name,timezone)
  select pg_temp.actor(n),'linkrace'||n,'Fictional Runner','UTC' from generate_series(1,5) n;
insert into auth.sessions(id,user_id) select pg_temp.session(n),pg_temp.actor(n) from generate_series(1,5) n;
insert into public.friendships(user_a,user_b,requested_by,status)
  values(pg_temp.actor(1),pg_temp.actor(2),pg_temp.actor(1),'accepted'),
        (pg_temp.actor(3),pg_temp.actor(4),pg_temp.actor(3),'accepted');
do $x$ begin perform public.set_duel_admission_v1(true,array(select pg_temp.actor(n) from generate_series(1,4) n)); end $x$;
do $x$ begin perform public.set_duel_lifecycle_enabled_v1(true); end $x$;
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

do $x$ begin perform pg_temp.notice(pg_temp.id('old'),clock_timestamp()-interval '8 days'); end $x$;
do $x$ begin perform pg_temp.notice(pg_temp.id('old'),clock_timestamp(),'ready_to_finalize'); end $x$;
do $x$ begin perform public.curate_duel_fixture_event_v1(pg_temp.session(100),clock_timestamp()+interval '5 days',clock_timestamp()+interval '5 days 2 hours','America/Chicago'); end $x$;
commit;$setup$);
create temp table ids(name text,id uuid);
insert into ids select * from extensions.dblink('link_setup','select * from ids') x(name text,id uuid);
insert into ids values('event','de200000-0000-0000-0000-000000000100');
create function pg_temp.id(n text) returns uuid language sql as $$select id from ids where name=n$$;
create function pg_temp.actor(n integer) returns uuid language sql immutable as $$
 select ('de100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.req(n integer) returns uuid language sql immutable as $$
 select ('de200000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid$$;
select extensions.dblink_exec('link_one',$install$create function pg_temp.action(n integer,q text) returns text language plpgsql as $fn$
declare r text;
begin
 perform set_config('request.jwt.claim.sub',('de100000-0000-0000-0000-'||lpad(n::text,12,'0')),true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',('de100000-0000-0000-0000-'||lpad(n::text,12,'0')),
 'session_id',('de200000-0000-0000-0000-'||lpad(n::text,12,'0')),'role','authenticated')::text,true);
 perform set_config('role','authenticated',true);
 begin execute q into r; exception when others then r:=SQLSTATE; end;
 perform set_config('role','none',true);
 return r;
end; $fn$;$install$);
select extensions.dblink_exec('link_two',$install$create function pg_temp.action(n integer,q text) returns text language plpgsql as $fn$
declare r text;
begin
 perform set_config('request.jwt.claim.sub',('de100000-0000-0000-0000-'||lpad(n::text,12,'0')),true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',('de100000-0000-0000-0000-'||lpad(n::text,12,'0')),
 'session_id',('de200000-0000-0000-0000-'||lpad(n::text,12,'0')),'role','authenticated')::text,true);
 perform set_config('role','authenticated',true);
 begin execute q into r; exception when others then r:=SQLSTATE; end;
 perform set_config('role','none',true);
 return r;
end; $fn$;$install$);
create function pg_temp.race(first_sql text,second_sql text,hold_seconds double precision default 0)
returns table(first_result text,second_result text,blocked boolean) language plpgsql as $$
declare deadline timestamptz:=clock_timestamp()+interval '4 seconds';
begin
 perform extensions.dblink_exec('link_one','begin; set local statement_timeout=''8s''');
 perform extensions.dblink_exec('link_two','begin; set local statement_timeout=''8s''');
 select x.r into first_result from extensions.dblink('link_one',first_sql) x(r text);
 perform extensions.dblink_send_query('link_two',second_sql);
 loop
  perform pg_stat_clear_snapshot();
  select exists(select 1 from pg_stat_activity where application_name='link_race_two'
    and cardinality(pg_blocking_pids(pid))>0) into blocked;
  exit when blocked or clock_timestamp()>=deadline;
  perform pg_sleep(0.01);
 end loop;
 perform pg_sleep(hold_seconds);
 perform extensions.dblink_exec('link_one','commit');
 select x.r into second_result from extensions.dblink_get_result('link_two') x(r text);
 perform * from extensions.dblink_get_result('link_two') x(r text);
 perform extensions.dblink_exec('link_two','commit');
 return next;
end; $$;
create temp table outcomes(name text,first_result text,second_result text,blocked boolean);
create function pg_temp.query(n integer,q text) returns text language sql as $$select format('select pg_temp.action(%s,%L)',n,q)$$;
-- A runtime wait must not admit a request after its session naturally expires.
select extensions.dblink_exec('link_setup','update auth.sessions set not_after=clock_timestamp()+interval ''0.5 seconds'' where user_id=''de100000-0000-0000-0000-000000000001''');
insert into outcomes select 'rematch session expiry',* from pg_temp.race(
 'select singleton::text from app.duel_runtime for update',
 pg_temp.query(1,format('select public.rematch_duel_v1(%L,%L,%L,%L,true)',pg_temp.req(210),pg_temp.id('old'),pg_temp.id('event'),'duel-fixture-5k-v1')),0.8);
select is((select second_result from outcomes where name='rematch session expiry'),'42501','rematch rechecks expiry after runtime wait');
select extensions.dblink_exec('link_setup','update auth.sessions set not_after=null where user_id=''de100000-0000-0000-0000-000000000001''');
insert into outcomes select 'rematch vs rematch',* from pg_temp.race(
 pg_temp.query(1,format('select public.rematch_duel_v1(%L,%L,%L,%L,true)',pg_temp.req(201),pg_temp.id('old'),pg_temp.id('event'),'duel-fixture-5k-v1')),
 pg_temp.query(1,format('select public.rematch_duel_v1(%L,%L,%L,%L,true)',pg_temp.req(202),pg_temp.id('old'),pg_temp.id('event'),'duel-fixture-5k-v1')));
select is((select second_result from outcomes where name='rematch vs rematch'),'23505','one concurrent creator reservation');
insert into ids select 'new',first_result::uuid from outcomes where name='rematch vs rematch';
select extensions.dblink_exec('link_setup','update auth.sessions set not_after=clock_timestamp()+interval ''0.5 seconds'' where user_id=''de100000-0000-0000-0000-000000000001''');
insert into outcomes select 'link session expiry',* from pg_temp.race(
 'select singleton::text from app.duel_runtime for update',
 pg_temp.query(1,format('select public.issue_duel_link_v1(%L,%L)',pg_temp.req(211),pg_temp.id('new'))),0.8);
select is((select second_result from outcomes where name='link session expiry'),'42501','link issue rechecks expiry after runtime wait');
select extensions.dblink_exec('link_setup','update auth.sessions set not_after=null where user_id=''de100000-0000-0000-0000-000000000001''');
-- A committed issue retains its session lock until the transaction finishes.
insert into outcomes select 'link then session revocation',* from pg_temp.race(
 pg_temp.query(1,format('select public.issue_duel_link_v1(%L,%L)',pg_temp.req(212),pg_temp.id('new'))),
 format('with d as (delete from auth.sessions where user_id=%L returning id) select count(*)::text from d',pg_temp.actor(1)));
select is((select second_result from outcomes where name='link then session revocation'),'1','revocation completes after authorized link commit');
select is((select x.r from extensions.dblink('link_one',pg_temp.query(1,format('select public.issue_duel_link_v1(%L,%L)',pg_temp.req(212),pg_temp.id('new')))) x(r text)),'42501','revoked session cannot recover link issue');
select extensions.dblink_exec('link_setup','insert into auth.sessions(id,user_id) values(''de200000-0000-0000-0000-000000000001'',''de100000-0000-0000-0000-000000000001'')');
insert into outcomes select 'issue vs exact retry',* from pg_temp.race(
 pg_temp.query(1,format('select public.issue_duel_link_v1(%L,%L)',pg_temp.req(203),pg_temp.id('new'))),
 pg_temp.query(1,format('select public.issue_duel_link_v1(%L,%L)',pg_temp.req(203),pg_temp.id('new'))));
select is(first_result,second_result,'concurrent issue exact retry recovers') from outcomes where name='issue vs exact retry';
insert into ids select 'link',x.id from extensions.dblink('link_setup',format('select token from app.duel_invitation_links where challenge_id=%L and revoked_at is null',pg_temp.id('new'))) x(id uuid);
insert into outcomes select 'revoke vs resolve',* from pg_temp.race(
 pg_temp.query(1,format('select public.revoke_duel_link_v1(%L,%L,%L)',pg_temp.req(204),pg_temp.id('new'),pg_temp.id('link'))),
 pg_temp.query(2,format('select public.resolve_duel_link_v1(%L)',pg_temp.id('link'))));
select is((select second_result from outcomes where name='revoke vs resolve'),'42501','waiting resolution sees revocation');
select x.r from extensions.dblink('link_one',pg_temp.query(1,format('select public.issue_duel_link_v1(%L,%L)',pg_temp.req(205),pg_temp.id('new')))) x(r text);
insert into ids select 'second-link',x.id from extensions.dblink('link_setup',format('select token from app.duel_invitation_links where challenge_id=%L and revoked_at is null',pg_temp.id('new'))) x(id uuid);
insert into outcomes select 'accept vs resolve',* from pg_temp.race(
 pg_temp.query(2,format('select public.accept_duel_v1(%L,%L,%L,public.get_duel_v1(%L)->>''terms_digest'')',pg_temp.req(206),pg_temp.id('new'),'duel-fixture-5k-v1',pg_temp.id('new'))),
 pg_temp.query(2,format('select public.resolve_duel_link_v1(%L)',pg_temp.id('second-link'))));
select is((select second_result from outcomes where name='accept vs resolve'),'42501','waiting resolution sees acceptance without adding consent');
select ok(blocked,name||': observed lock wait') from outcomes order by name;
select extensions.dblink_exec('link_setup',$cleanup$
  set session_replication_role=replica;
  delete from app.duel_invitation_links where challenge_id in (select id from public.duel_challenges where creator_id::text like 'de100000-%');
  delete from app.duel_rematches where challenge_id in (select id from public.duel_challenges where creator_id::text like 'de100000-%');
  delete from app.duel_lifecycle_support where challenge_id in (select id from public.duel_challenges where creator_id::text like 'de100000-%');
  delete from app.duel_lifecycle_settlements where challenge_id in (select id from public.duel_challenges where creator_id::text like 'de100000-%');
  delete from app.duel_lifecycle_results where challenge_id in (select id from public.duel_challenges where creator_id::text like 'de100000-%');
  delete from app.duel_lifecycle_closures where challenge_id in (select id from public.duel_challenges where creator_id::text like 'de100000-%');
  delete from app.duel_lifecycle_resolutions where case_id in (select id from app.duel_lifecycle_cases where actor_id::text like 'de100000-%');
  delete from app.duel_lifecycle_cases where challenge_id in (select id from public.duel_challenges where creator_id::text like 'de100000-%');
  delete from app.duel_lifecycle_notices where challenge_id in (select id from public.duel_challenges where creator_id::text like 'de100000-%');
  delete from app.duel_lifecycle_activations where challenge_id in (select id from public.duel_challenges where creator_id::text like 'de100000-%');
  update app.duel_lifecycle_runtime set enabled=false;
  -- Retain control audit entries: they are actual service gate changes and
  -- must not be confused with unrelated audit history during scoped cleanup.
  delete from app.duel_proof_access_audit where reviewer_id::text like 'de100000-%';
  delete from app.duel_proof_revisions where reviewer_id::text like 'de100000-%';
  delete from app.duel_proof_sources where id::text like 'de200000-%';
  delete from app.duel_proof_grants where reviewer_id::text like 'de100000-%';
  update app.duel_proof_runtime set enabled=false;
  delete from app.duel_requests where actor_id::text like 'de100000-%';
  delete from app.duel_enrollments where actor_id::text like 'de100000-%';
  delete from public.duel_participants where actor_id::text like 'de100000-%';
  create temp table event_cleanup as select distinct event_id from public.duel_challenges where creator_id::text like 'de100000-%';
  delete from public.duel_challenges where creator_id::text like 'de100000-%';
  delete from public.duel_event_fixtures where id in (select event_id from event_cleanup) or id::text like 'de200000-%';
  delete from app.duel_beta_allowlist where actor_id::text like 'de100000-%';
  update app.duel_runtime set admission_enabled=false;
  delete from public.friendships where user_a::text like 'de100000-%' or user_b::text like 'de100000-%';
  delete from app.profile_handle_claims where actor_id::text like 'de100000-%';
  delete from app.active_profile_auth_bindings where actor_id::text like 'de100000-%';
  delete from public.profiles where id::text like 'de100000-%';
  delete from auth.sessions where user_id::text like 'de100000-%';
  delete from auth.users where id::text like 'de100000-%';
  set session_replication_role=origin;
$cleanup$);
select extensions.dblink_disconnect('link_one');
select extensions.dblink_disconnect('link_two');
select extensions.dblink_disconnect('link_setup');
select * from finish();
rollback;
