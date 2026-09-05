-- Real independent transactions; pg_blocking_pids proves each competing call
-- waited. Only fictional db/dc records are committed and then cleaned up.
begin;
select no_plan();
create function pg_temp.actor(n integer) returns uuid language sql immutable as $$
  select ('db000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid;
$$;
create function pg_temp.req(n integer) returns uuid language sql immutable as $$
  select ('dc000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid;
$$;
select extensions.dblink_connect('life_setup','host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres');
select extensions.dblink_connect('life_one','host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres application_name=life_race_one');
select extensions.dblink_connect('life_two','host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres application_name=life_race_two');
select extensions.dblink_exec('life_setup',$setup$
  insert into auth.users(id) select ('db000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid from generate_series(1,40) n;
  insert into public.profiles(id,handle,display_name,timezone)
    select id,'liferace'||right(id::text,4),'Fictional Reviewer Race','UTC' from auth.users where id::text like 'db000000-%';
  insert into auth.sessions(id,user_id)
    select ('dc000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
      ('db000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid from generate_series(1,40) n;
  insert into public.friendships(user_a,user_b,requested_by,status)
    select a.id,b.id,a.id,'accepted' from public.profiles a cross join public.profiles b
    where a.id::text like 'db000000-%' and b.id::text like 'db000000-%' and a.id<b.id;
  create function pg_temp.prepare(n integer,ends timestamptz,capture_at timestamptz default null) returns void language plpgsql as $fn$
  declare a uuid:=('db000000-0000-0000-0000-'||lpad((2*n-1)::text,12,'0'))::uuid;
    b uuid:=('db000000-0000-0000-0000-'||lpad((2*n)::text,12,'0'))::uuid;
    e uuid:=('dc000000-0000-0000-0000-'||lpad((1000+n)::text,12,'0'))::uuid;
    s uuid:=('dc000000-0000-0000-0000-'||lpad((2000+n)::text,12,'0'))::uuid;
    c uuid; reviewer uuid; d jsonb;
  begin
    perform public.curate_duel_fixture_event_v1(e,ends-interval '2 hours',ends,'UTC');
    perform set_config('request.jwt.claim.sub',a::text,true);
    c:=app.create_duel_at_v1(e,b,e,'duel-fixture-5k-v1',true,ends-interval '2 days');
    perform set_config('request.jwt.claim.sub',b::text,true);
    perform app.respond_duel_at_v1('accept_duel_v1',s,c,'duel-fixture-5k-v1',
      (select terms_digest from public.duel_challenges where id=c),ends-interval '1 day');
    for i in 39..40 loop
      reviewer:=('db000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid;
      perform public.set_duel_proof_reviewer_v1(
        ('dc000000-0000-0000-0000-'||lpad((n*100+i)::text,12,'0'))::uuid,c,reviewer,true);
    end loop;
    d:=jsonb_build_object('eventId',e,'course','fixture_course_5k_v1','wave','fixture_common_wave_v1',
      'distanceMeters',5000,'timingBasis','organizer_chip','precisionSeconds',1,'rows',jsonb_build_array(
        jsonb_build_object('actorId',a,'mappedBib','fictional-bib-11','publishedBib','fictional-bib-11','status','finished','chipSeconds',1200),
        jsonb_build_object('actorId',b,'mappedBib','fictional-bib-22','publishedBib','fictional-bib-22','status','finished','chipSeconds',1250)));
    if capture_at is null then perform public.capture_duel_proof_fixture_v1(s,c,d);
    else perform app.duel_proof_capture_at_v1(s,c,d,capture_at); end if;
  end; $fn$;
  do $do$ begin
    perform public.set_duel_admission_v1(true,array(select id from public.profiles where id::text like 'db000000-%'));
    perform public.set_duel_proof_enabled_v1(true); perform public.set_duel_lifecycle_enabled_v1(true);
    for n in 1..8 loop perform pg_temp.prepare(n,clock_timestamp()-interval '4 days',clock_timestamp()-interval '3 days'); end loop;
  end; $do$;
$setup$);

-- The coordinator never holds the actor locks used by the competing sessions.
create temp table snapshots(n integer primary key,i jsonb);
insert into snapshots select n,x.i from generate_series(1,8) n cross join lateral extensions.dblink('life_setup',
  format('select public.load_duel_lifecycle_v1((select id from public.duel_challenges where creator_id=%L))',pg_temp.actor(2*n-1))) x(i jsonb);
create function pg_temp.decision(i jsonb,phase text default 'provisional') returns jsonb language sql as $$
 select jsonb_build_object('version','duel-fixture-official-5k-v1','challengeId',i->'agreement'->'id',
 'termsDigest',i->'agreement'->'terms_digest','proofRevision',jsonb_array_length(i->'proofRevisions'),'phase',phase,
 'outcome',jsonb_build_object('kind','void','reason','unresolved_proof'),
 'disputeClosesAt',null,'reviewDueAt',null,'supportCorrectionRequired',false)$$;
create function pg_temp.commit_query(n integer,phase text default 'provisional') returns text language sql as $$
 select format('select public.commit_duel_lifecycle_v1(%L::jsonb,%L::jsonb)',i,pg_temp.decision(i,phase)) from snapshots where snapshots.n=commit_query.n$$;
create function pg_temp.race(first_sql text,second_sql text)
returns table(first_result text,second_result text,blocked boolean) language plpgsql as $$
declare deadline timestamptz:=clock_timestamp()+interval '4 seconds';
begin
 perform extensions.dblink_exec('life_one','begin; set local statement_timeout=''8s''');
 perform extensions.dblink_exec('life_two','begin; set local statement_timeout=''8s''');
 select x.r into first_result from extensions.dblink('life_one',first_sql) x(r text);
 perform extensions.dblink_send_query('life_two',second_sql);
 loop
  perform pg_stat_clear_snapshot();
  select exists(select 1 from pg_stat_activity where application_name='life_race_two'
    and cardinality(pg_blocking_pids(pid))>0) into blocked;
  exit when blocked or clock_timestamp()>=deadline;
  perform pg_sleep(0.01);
 end loop;
 perform extensions.dblink_exec('life_one','commit');
 select x.r into second_result from extensions.dblink_get_result('life_two') x(r text);
 perform * from extensions.dblink_get_result('life_two') x(r text);
 perform extensions.dblink_exec('life_two','commit');
 return next;
end; $$;
create temp table outcomes(name text,first_result text,second_result text,blocked boolean);
insert into outcomes select 'notice vs notice',* from pg_temp.race(pg_temp.commit_query(1),pg_temp.commit_query(1));
select is((select second_result from outcomes where name='notice vs notice'),'stale','notice append invalidates competing worker input');
insert into outcomes select 'exit vs worker',r.* from snapshots cross join lateral pg_temp.race(format('select public.cancel_duel_event_v1(%L,%L)',pg_temp.req(8001),i->'agreement'->>'id'),pg_temp.commit_query(2)) r where n=2;
select is((select second_result from outcomes where name='exit vs worker'),'stale','safe exit wins over stale provisional publication');
insert into outcomes select 'deletion vs worker',* from pg_temp.race(format('select public.delete_account(%L)',pg_temp.actor(5)),pg_temp.commit_query(3));
select is((select second_result from outcomes where name='deletion vs worker'),'stale','deletion tombstone invalidates worker');
-- Publish no-proof notices and then race a final worker with a case filing.
select x.r from extensions.dblink('life_setup',pg_temp.commit_query(4)) x(r text);
update snapshots set i=x.i from extensions.dblink('life_setup',format('select public.load_duel_lifecycle_v1((select id from public.duel_challenges where creator_id=%L))',pg_temp.actor(7))) x(i jsonb) where n=4;
select extensions.dblink_exec('life_one',format($install$
 create function pg_temp.file_case() returns uuid language plpgsql as $fn$
 declare c uuid; result uuid;
 begin
  select id into c from public.duel_challenges where creator_id=%L;
  perform set_config('request.jwt.claim.sub',%L,true);
  perform set_config('request.jwt.claims',%L,true);
  perform set_config('role','authenticated',true);
  result:=public.file_duel_review_v1(%L,c,0,'wrong_result');
  perform set_config('role','none',true);
  return result;
 end; $fn$;
$install$,pg_temp.actor(7),pg_temp.actor(7),jsonb_build_object('sub',pg_temp.actor(7),'session_id',pg_temp.req(7)),pg_temp.req(8002)));
insert into outcomes select 'case vs worker',* from pg_temp.race('select pg_temp.file_case()',pg_temp.commit_query(4));
select is((select second_result from outcomes where name='case vs worker'),'stale','case append invalidates worker');
-- Final result race uses a hard-cap clock seam: no notices means void timeout.
update snapshots set i=x.i from extensions.dblink('life_setup',format('select app.duel_lifecycle_load_at_v1((select id from public.duel_challenges where creator_id=%L),clock_timestamp()+interval ''31 days'')',pg_temp.actor(9))) x(i jsonb) where n=5;
create function pg_temp.final_query(n integer) returns text language sql as $$
 select format('select app.duel_lifecycle_commit_at_v1(%L::jsonb,%L::jsonb,%L::timestamptz)',i,
 jsonb_set(pg_temp.decision(i,'ready_to_finalize'),'{outcome,reason}','"finality_timeout"'),i->>'now') from snapshots where snapshots.n=final_query.n$$;
insert into outcomes select 'final vs final',* from pg_temp.race(pg_temp.final_query(5),pg_temp.final_query(5));
select is((select second_result from outcomes where name='final vs final'),'stale','only one final result commits');
select is((select count(*) from app.duel_lifecycle_results where challenge_id=(select (i->'agreement'->>'id')::uuid from snapshots where n=5)),1::bigint,'one immutable final result');
select is((select count(*) from app.duel_enrollments where challenge_id=(select (i->'agreement'->>'id')::uuid from snapshots where n=5) and released_at is null),0::bigint,'concurrent final releases slots once');

-- Both sessions execute the real proof/review boundary with an active reviewer.
do $$ declare conn text; begin
 foreach conn in array array['life_setup','life_one','life_two'] loop
  perform extensions.dblink_exec(conn,$install$
   create function pg_temp.proof_inner(c uuid,s uuid,rev integer,t timestamptz) returns integer
   language sql security definer set search_path='' as $fn$
    select app.duel_proof_append_at_v1(extensions.gen_random_uuid(),c,s,rev,
     (select jsonb_build_array(jsonb_build_object('actorId',creator_id,'identityConfirmed',true),
       jsonb_build_object('actorId',invitee_id,'identityConfirmed',true)) from public.duel_challenges where id=c),t)
   $fn$;
   create function pg_temp.proof_action(n integer,rev integer,t timestamptz default null) returns text
   language plpgsql as $fn$
   declare c uuid; result text;
   begin
    select id into c from public.duel_challenges where creator_id=('db000000-0000-0000-0000-'||lpad((2*n-1)::text,12,'0'))::uuid;
    perform set_config('request.jwt.claim.sub','db000000-0000-0000-0000-000000000039',true);
    perform set_config('request.jwt.claims','{"sub":"db000000-0000-0000-0000-000000000039","session_id":"dc000000-0000-0000-0000-000000000039"}',true);
    perform set_config('role','authenticated',true);
    result:=pg_temp.proof_inner(c,('dc000000-0000-0000-0000-'||lpad((2000+n)::text,12,'0'))::uuid,rev,t)::text;
    perform set_config('role','none',true); return result;
   exception when others then return sqlstate;
   end; $fn$;
   create function pg_temp.resolve_case() returns text language plpgsql as $fn$
   declare k uuid; result uuid;
   begin
    select id into k from app.duel_lifecycle_cases where actor_id='db000000-0000-0000-0000-000000000007';
    perform set_config('request.jwt.claim.sub','db000000-0000-0000-0000-000000000039',true);
    perform set_config('request.jwt.claims','{"sub":"db000000-0000-0000-0000-000000000039","session_id":"dc000000-0000-0000-0000-000000000039"}',true);
    perform set_config('role','authenticated',true);
    result:=public.resolve_duel_review_v1(extensions.gen_random_uuid(),k,'uphold');
    perform set_config('role','none',true); return result::text;
   end; $fn$;
  $install$);
 end loop;
end; $$;
select is(x.r,'1','initial proof admitted before cutoff') from extensions.dblink('life_setup',
 'select pg_temp.proof_action(6,0,clock_timestamp()-interval ''3 days''+interval ''1 hour'')') x(r text);
update snapshots set i=x.i from extensions.dblink('life_setup',format('select public.load_duel_lifecycle_v1((select id from public.duel_challenges where creator_id=%L))',pg_temp.actor(11))) x(i jsonb) where n=6;
insert into outcomes select 'correction vs worker',* from pg_temp.race('select pg_temp.proof_action(6,1)',pg_temp.commit_query(6));
select is((select first_result from outcomes where name='correction vs worker'),'2','correction appends revision two');
select is((select second_result from outcomes where name='correction vs worker'),'stale','correction invalidates evaluated input');
update snapshots set i=x.i from extensions.dblink('life_setup',format('select public.load_duel_lifecycle_v1((select id from public.duel_challenges where creator_id=%L))',pg_temp.actor(7))) x(i jsonb) where n=4;
insert into outcomes select 'resolution vs worker',* from pg_temp.race('select pg_temp.resolve_case()',pg_temp.commit_query(4));
select is((select second_result from outcomes where name='resolution vs worker'),'stale','resolution invalidates worker input');
select is(x.r,'1','second initial proof admitted') from extensions.dblink('life_setup',
 'select pg_temp.proof_action(7,0,clock_timestamp()-interval ''3 days''+interval ''1 hour'')') x(r text);
update snapshots set i=x.i from extensions.dblink('life_setup',format('select app.duel_lifecycle_load_at_v1((select id from public.duel_challenges where creator_id=%L),clock_timestamp()+interval ''31 days'')',pg_temp.actor(13))) x(i jsonb) where n=7;
insert into outcomes select 'final vs correction',* from pg_temp.race(pg_temp.final_query(7),'select pg_temp.proof_action(7,1)');
select is((select first_result from outcomes where name='final vs correction'),'final','final result commits');
select is((select second_result from outcomes where name='final vs correction'),'55000','waiting correction denied after finality');
select ok(blocked,name||': second session waited on first') from outcomes order by name;
select extensions.dblink_exec('life_setup',$cleanup$
  set session_replication_role=replica;
  delete from app.duel_lifecycle_support where challenge_id in (select id from public.duel_challenges where creator_id::text like 'db000000-%');
  delete from app.duel_lifecycle_settlements where challenge_id in (select id from public.duel_challenges where creator_id::text like 'db000000-%');
  delete from app.duel_lifecycle_results where challenge_id in (select id from public.duel_challenges where creator_id::text like 'db000000-%');
  delete from app.duel_lifecycle_closures where challenge_id in (select id from public.duel_challenges where creator_id::text like 'db000000-%');
  delete from app.duel_lifecycle_resolutions where case_id in (select id from app.duel_lifecycle_cases where actor_id::text like 'db000000-%');
  delete from app.duel_lifecycle_cases where challenge_id in (select id from public.duel_challenges where creator_id::text like 'db000000-%');
  delete from app.duel_lifecycle_notices where challenge_id in (select id from public.duel_challenges where creator_id::text like 'db000000-%');
  delete from app.duel_lifecycle_activations where challenge_id in (select id from public.duel_challenges where creator_id::text like 'db000000-%');
  update app.duel_lifecycle_runtime set enabled=false;
  -- Retain control audit entries: they are actual service gate changes and
  -- must not be confused with unrelated audit history during scoped cleanup.
  delete from app.duel_proof_access_audit where reviewer_id::text like 'db000000-%';
  delete from app.duel_proof_revisions where reviewer_id::text like 'db000000-%';
  delete from app.duel_proof_sources where id::text like 'dc000000-%';
  delete from app.duel_proof_grants where reviewer_id::text like 'db000000-%';
  update app.duel_proof_runtime set enabled=false;
  delete from app.duel_requests where actor_id::text like 'db000000-%';
  delete from app.duel_enrollments where actor_id::text like 'db000000-%';
  delete from public.duel_participants where actor_id::text like 'db000000-%';
  delete from public.duel_challenges where creator_id::text like 'db000000-%';
  delete from public.duel_event_fixtures where id::text like 'dc000000-%';
  delete from app.duel_beta_allowlist where actor_id::text like 'db000000-%';
  update app.duel_runtime set admission_enabled=false;
  delete from public.friendships where user_a::text like 'db000000-%' or user_b::text like 'db000000-%';
  delete from app.profile_handle_claims where actor_id::text like 'db000000-%';
  delete from app.active_profile_auth_bindings where actor_id::text like 'db000000-%';
  delete from public.profiles where id::text like 'db000000-%';
  delete from auth.sessions where user_id::text like 'db000000-%';
  delete from auth.users where id::text like 'db000000-%';
  set session_replication_role=origin;
$cleanup$);
select extensions.dblink_disconnect('life_one');
select extensions.dblink_disconnect('life_two');
select extensions.dblink_disconnect('life_setup');
select * from finish();
rollback;
