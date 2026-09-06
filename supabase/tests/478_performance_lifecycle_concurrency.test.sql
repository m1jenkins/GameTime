-- Real independent transaction races; coordinator owns no competing actor locks.
begin;
select no_plan();
select extensions.dblink_connect('pl_setup','host='||host(inet_server_addr())||' port=5432 dbname=postgres user=postgres password=postgres');
select extensions.dblink_connect('pl_one','host='||host(inet_server_addr())||' port=5432 dbname=postgres user=postgres password=postgres application_name=pl_race_one');
select extensions.dblink_connect('pl_two','host='||host(inet_server_addr())||' port=5432 dbname=postgres user=postgres password=postgres application_name=pl_race_two');
select extensions.dblink_exec('pl_setup',$setup$
-- Rollback-only shared fixture for SQL and the actual evaluator/worker smoke.
-- Every timestamp below is a fictional clock injection, not elapsed operation.
begin;
set local timezone='UTC';
create function pg_temp.actor(n integer) returns uuid language sql immutable as $$
 select ('e6100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.req(n integer) returns uuid language sql immutable as $$
 select ('e6200000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.login(n integer) returns void language plpgsql as $$ begin
 perform set_config('request.jwt.claim.sub',pg_temp.actor(n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.actor(n),'role','authenticated','session_id',pg_temp.req(n))::text,true);
end; $$;
insert into auth.users(id) select pg_temp.actor(n) from generate_series(1,30) n;
insert into public.profiles(id,handle,display_name,timezone)
 select pg_temp.actor(n),'lifecyclerace'||n,'Fictional Runner','UTC' from generate_series(1,30) n;
insert into auth.sessions(id,user_id) select pg_temp.req(n),pg_temp.actor(n) from generate_series(1,30) n;
do $$ begin perform public.set_performance_commitment_admission_v1(true,array(select pg_temp.actor(n) from generate_series(1,29) n)); perform public.set_commitment_lifecycle_enabled_v1(true); end; $$;
do $$ begin perform public.set_commitment_attempts_enabled_v1(true); end; $$;
create temp table saved(name text primary key,value jsonb);
grant select,insert,update on saved to authenticated;
create function pg_temp.id(n integer) returns uuid language sql as $$select (value->>0)::uuid from saved where name='c'||n$$;
create function pg_temp.attempt(q text) returns text language plpgsql as $$ begin
 execute q; return 'ok'; exception when others then return sqlstate; end; $$;
create function pg_temp.terms(a uuid,s timestamptz,d timestamptz) returns jsonb language sql security definer set search_path='' as $$select app.performance_commitment_terms_v1(a,360,s,d,'America/Chicago','performance-commitment-fixture-5k-v1')$$;
create function pg_temp.prepare(n integer) returns uuid language plpgsql as $$
declare c uuid; t jsonb; s timestamptz:='2026-05-02T12:00:00.123456Z'; d timestamptz:='2026-07-01T12:00:00.123456Z'; begin
 perform pg_temp.login(n); perform set_config('role','authenticated',true);
 t:=pg_temp.terms(auth.uid(),s,d);
 c:=pg_temp.create_at(pg_temp.req(100+n),t);
 perform set_config('role','none',true);
 insert into saved values('c'||n,jsonb_build_array(c));
 perform public.set_commitment_attempt_reviewer_v1(pg_temp.req(200+n),c,pg_temp.actor(30),true);
 perform public.set_commitment_lifecycle_operator_v1(pg_temp.req(300+n),c,pg_temp.actor(30),'review',clock_timestamp()+interval '6 days');
 return c;
end; $$;
-- Private helpers remain owned by postgres and use explicit role checks in RPCs.
-- SECURITY DEFINER permits only the test clock seam while current role is authenticated.
create function pg_temp.create_at(q uuid,t jsonb) returns uuid language sql security definer set search_path='' as $$
 select app.create_performance_commitment_at_v1(q,360,(t->>'starts_at')::timestamptz,(t->>'deadline_at')::timestamptz,
 'America/Chicago','performance-commitment-fixture-5k-v1',encode(extensions.digest(t::text,'sha256'),'hex'),true,'2026-05-01T12:00:00.123456Z')$$;
-- Replace the direct private call above with this clock wrapper for role realism.
create function pg_temp.nominate_at(q uuid,c uuid,e uuid) returns uuid language sql security definer set search_path='' as $$
 select app.nominate_commitment_attempt_at_v1(q,c,e,'bib-1','2026-05-01T13:00:00.123456Z')$$;
create function pg_temp.review_at(q uuid,c uuid,s uuid,r integer,t timestamptz) returns integer language sql security definer set search_path='' as $$
 select app.review_commitment_attempt_at_v1(q,c,s,r,true,t)$$;
create function pg_temp.proof(n integer,slot integer,seconds integer,t timestamptz default '2026-06-01T12:00:00.123456Z',missing boolean default false)
returns integer language plpgsql as $$
declare c uuid:=pg_temp.id(n); e uuid:=pg_temp.req(1000+n*10+slot); a uuid; s uuid:=extensions.gen_random_uuid(); r integer; doc jsonb;
begin
 select id into a from app.performance_attempt_nominations where commitment_id=c and event_id=e;
 if a is null then
   perform public.curate_commitment_fixture_event_v1(e,'2026-05-03T12:00:00.123456Z','2026-05-03T14:00:00.123456Z');
   perform pg_temp.login(n); perform set_config('role','authenticated',true);
   a:=pg_temp.nominate_at(e,c,e); perform set_config('role','none',true);
 end if;
 doc:=jsonb_build_object('source','fixture_official_5k_v1','event_id',e,'distance_meters',5000,'timing_basis','organizer_chip',
 'precision_ms',1000,'published_bib','bib-1','status',case when missing then 'missing' when seconds=0 then 'dnf' else 'finished' end,
 'chip_seconds',case when seconds=0 or missing then null else seconds end,
 'started_at',case when seconds=0 or missing then null else '2026-05-03T12:00:00.123456Z'::timestamptz end,
 'finished_at',case when seconds=0 or missing then null else '2026-05-03T12:00:00.123456Z'::timestamptz+seconds*interval '1 second' end);
 perform app.capture_commitment_attempt_at_v1(s,c,a,doc,t);
 select max(revision) into r from app.performance_attempt_revisions where commitment_id=c and attempt_id=a;
 perform pg_temp.login(30); perform set_config('role','authenticated',true);
 perform public.get_commitment_attempt_source_v1(c,s);
 r:=pg_temp.review_at(s,c,s,r,t);
 perform set_config('role','none',true); return r;
end; $$;
create function pg_temp.confirm_at(q uuid,c uuid,ids uuid[]) returns uuid language sql security definer set search_path='' as $$
 select app.confirm_commitment_attempt_set_at_v1(q,c,ids,true,'2026-07-01T12:00:00.123456Z')$$;
create function pg_temp.confirm(n integer) returns uuid language plpgsql as $$ declare ids uuid[]; c uuid:=pg_temp.id(n); begin
 select coalesce(array_agg(id order by id),'{}'::uuid[]) into ids from app.performance_attempt_nominations where commitment_id=c;
 perform pg_temp.login(n); perform set_config('role','authenticated',true);
 perform pg_temp.confirm_at(pg_temp.req(400+n),c,ids); perform set_config('role','none',true); return c;
end; $$;
create function pg_temp.file_at(q uuid,c uuid,r integer,reason text,t timestamptz) returns jsonb language sql security definer set search_path='' as $$
 select app.performance_lifecycle_case_at_v1(q,c,r,reason,t)$$;
create function pg_temp.file(n integer,r integer,t timestamptz,q integer default 500) returns uuid language plpgsql as $$ declare result jsonb; begin
 perform pg_temp.login(n); perform set_config('role','authenticated',true);
 result:=pg_temp.file_at(pg_temp.req(q+n),pg_temp.id(n),r,'wrong_result',t);
 perform set_config('role','none',true); return (result->>'case_id')::uuid;
end; $$;
create function pg_temp.resolve_at(q uuid,k uuid,d text,t timestamptz) returns jsonb language sql security definer set search_path='' as $$
 select app.performance_lifecycle_resolve_at_v1(q,k,d,t)$$;
create function pg_temp.resolve(n integer,k uuid,d text,t timestamptz) returns jsonb language plpgsql as $$ declare result jsonb; begin
 perform pg_temp.login(30); perform set_config('role','authenticated',true);
 perform public.read_commitment_lifecycle_operator_v1(pg_temp.id(n),'review');
 result:=pg_temp.resolve_at(pg_temp.req(600+n),k,d,t);
 perform set_config('role','none',true); return result;
end; $$;
create function pg_temp.exit_at(q uuid,c uuid,d text,t timestamptz) returns uuid language sql security definer set search_path='' as $$
 select app.close_performance_commitment_at_v1(q,c,d,t)$$;
create function pg_temp.exit(n integer,d text,t timestamptz) returns uuid language plpgsql as $$ declare result uuid; begin
 perform pg_temp.login(n); perform set_config('role','authenticated',true);
 result:=pg_temp.exit_at(pg_temp.req(700+n),pg_temp.id(n),d,t);
 perform set_config('role','none',true); return result;
end; $$;

do $$ declare n integer; c uuid; r integer; begin
 for n in 1..13 loop
  c:=pg_temp.prepare(n);
  if n in (2,4,8,11) then perform pg_temp.proof(n,0,360); r:=1; else r:=0; end if;
  perform set_config('app.performance_lifecycle_write_v1','on',true);
  insert into app.performance_lifecycle_notices values(c,r,pg_temp.actor(n),'2026-07-04T12:00:00.123456Z','{"kind":"inconclusive","reason":"unresolved_proof"}');
 end loop;
 perform pg_temp.file(4,1,'2026-07-05T12:00:00.123456Z');
end; $$;
commit;
$setup$);
create temp table saved(name text primary key,value jsonb);
insert into saved select name,value from extensions.dblink('pl_setup','select name,value from saved') x(name text,value jsonb);
create function pg_temp.actor(n integer) returns uuid language sql immutable as $$
 select ('e6100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.req(n integer) returns uuid language sql immutable as $$
 select ('e6200000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.login(n integer) returns void language plpgsql as $$ begin
 perform set_config('request.jwt.claim.sub',pg_temp.actor(n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.actor(n),'role','authenticated','session_id',pg_temp.req(n))::text,true);
end; $$;
create function pg_temp.id(n integer) returns uuid language sql as $$select (value->>0)::uuid from saved where name='c'||n$$;
create function pg_temp.attempt(q text) returns text language plpgsql as $$ begin
 execute q; return 'ok'; exception when others then return sqlstate; end; $$;
create function pg_temp.terms(a uuid,s timestamptz,d timestamptz) returns jsonb language sql security definer set search_path='' as $$select app.performance_commitment_terms_v1(a,360,s,d,'America/Chicago','performance-commitment-fixture-5k-v1')$$;

-- Install only test wrappers in each remote session; no public test functions.
do $install$ declare conn text; begin
 foreach conn in array array['pl_one','pl_two'] loop
  perform extensions.dblink_exec(conn,$defs$
create temp table saved(name text primary key,value jsonb);
grant select,insert,update on saved to authenticated;
create function pg_temp.actor(n integer) returns uuid language sql immutable as $$
 select ('e6100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.req(n integer) returns uuid language sql immutable as $$
 select ('e6200000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.login(n integer) returns void language plpgsql as $$ begin
 perform set_config('request.jwt.claim.sub',pg_temp.actor(n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.actor(n),'role','authenticated','session_id',pg_temp.req(n))::text,true);
end; $$;
create function pg_temp.id(n integer) returns uuid language sql as $$select (value->>0)::uuid from saved where name='c'||n$$;
create function pg_temp.attempt(q text) returns text language plpgsql as $$ begin
 execute q; return 'ok'; exception when others then return sqlstate; end; $$;
create function pg_temp.terms(a uuid,s timestamptz,d timestamptz) returns jsonb language sql security definer set search_path='' as $$select app.performance_commitment_terms_v1(a,360,s,d,'America/Chicago','performance-commitment-fixture-5k-v1')$$;
create function pg_temp.prepare(n integer) returns uuid language plpgsql as $$
declare c uuid; t jsonb; s timestamptz:='2026-05-02T12:00:00.123456Z'; d timestamptz:='2026-07-01T12:00:00.123456Z'; begin
 perform pg_temp.login(n); perform set_config('role','authenticated',true);
 t:=pg_temp.terms(auth.uid(),s,d);
 c:=pg_temp.create_at(pg_temp.req(100+n),t);
 perform set_config('role','none',true);
 insert into saved values('c'||n,jsonb_build_array(c));
 perform public.set_commitment_attempt_reviewer_v1(pg_temp.req(200+n),c,pg_temp.actor(30),true);
 perform public.set_commitment_lifecycle_operator_v1(pg_temp.req(300+n),c,pg_temp.actor(30),'review',clock_timestamp()+interval '6 days');
 return c;
end; $$;
create function pg_temp.create_at(q uuid,t jsonb) returns uuid language sql security definer set search_path='' as $$
 select app.create_performance_commitment_at_v1(q,360,(t->>'starts_at')::timestamptz,(t->>'deadline_at')::timestamptz,
 'America/Chicago','performance-commitment-fixture-5k-v1',encode(extensions.digest(t::text,'sha256'),'hex'),true,'2026-05-01T12:00:00.123456Z')$$;
create function pg_temp.nominate_at(q uuid,c uuid,e uuid) returns uuid language sql security definer set search_path='' as $$
 select app.nominate_commitment_attempt_at_v1(q,c,e,'bib-1','2026-05-01T13:00:00.123456Z')$$;
create function pg_temp.review_at(q uuid,c uuid,s uuid,r integer,t timestamptz) returns integer language sql security definer set search_path='' as $$
 select app.review_commitment_attempt_at_v1(q,c,s,r,true,t)$$;
create function pg_temp.proof(n integer,slot integer,seconds integer,t timestamptz default '2026-06-01T12:00:00.123456Z',missing boolean default false)
returns integer language plpgsql as $$
declare c uuid:=pg_temp.id(n); e uuid:=pg_temp.req(1000+n*10+slot); a uuid; s uuid:=extensions.gen_random_uuid(); r integer; doc jsonb;
begin
 select id into a from app.performance_attempt_nominations where commitment_id=c and event_id=e;
 if a is null then
   perform public.curate_commitment_fixture_event_v1(e,'2026-05-03T12:00:00.123456Z','2026-05-03T14:00:00.123456Z');
   perform pg_temp.login(n); perform set_config('role','authenticated',true);
   a:=pg_temp.nominate_at(e,c,e); perform set_config('role','none',true);
 end if;
 doc:=jsonb_build_object('source','fixture_official_5k_v1','event_id',e,'distance_meters',5000,'timing_basis','organizer_chip',
 'precision_ms',1000,'published_bib','bib-1','status',case when missing then 'missing' when seconds=0 then 'dnf' else 'finished' end,
 'chip_seconds',case when seconds=0 or missing then null else seconds end,
 'started_at',case when seconds=0 or missing then null else '2026-05-03T12:00:00.123456Z'::timestamptz end,
 'finished_at',case when seconds=0 or missing then null else '2026-05-03T12:00:00.123456Z'::timestamptz+seconds*interval '1 second' end);
 perform app.capture_commitment_attempt_at_v1(s,c,a,doc,t);
 select max(revision) into r from app.performance_attempt_revisions where commitment_id=c and attempt_id=a;
 perform pg_temp.login(30); perform set_config('role','authenticated',true);
 perform public.get_commitment_attempt_source_v1(c,s);
 r:=pg_temp.review_at(s,c,s,r,t);
 perform set_config('role','none',true); return r;
end; $$;
create function pg_temp.confirm_at(q uuid,c uuid,ids uuid[]) returns uuid language sql security definer set search_path='' as $$
 select app.confirm_commitment_attempt_set_at_v1(q,c,ids,true,'2026-07-01T12:00:00.123456Z')$$;
create function pg_temp.confirm(n integer) returns uuid language plpgsql as $$ declare ids uuid[]; c uuid:=pg_temp.id(n); begin
 select coalesce(array_agg(id order by id),'{}'::uuid[]) into ids from app.performance_attempt_nominations where commitment_id=c;
 perform pg_temp.login(n); perform set_config('role','authenticated',true);
 perform pg_temp.confirm_at(pg_temp.req(400+n),c,ids); perform set_config('role','none',true); return c;
end; $$;
create function pg_temp.file_at(q uuid,c uuid,r integer,reason text,t timestamptz) returns jsonb language sql security definer set search_path='' as $$
 select app.performance_lifecycle_case_at_v1(q,c,r,reason,t)$$;
create function pg_temp.file(n integer,r integer,t timestamptz,q integer default 500) returns uuid language plpgsql as $$ declare result jsonb; begin
 perform pg_temp.login(n); perform set_config('role','authenticated',true);
 result:=pg_temp.file_at(pg_temp.req(q+n),pg_temp.id(n),r,'wrong_result',t);
 perform set_config('role','none',true); return (result->>'case_id')::uuid;
end; $$;
create function pg_temp.resolve_at(q uuid,k uuid,d text,t timestamptz) returns jsonb language sql security definer set search_path='' as $$
 select app.performance_lifecycle_resolve_at_v1(q,k,d,t)$$;
create function pg_temp.resolve(n integer,k uuid,d text,t timestamptz) returns jsonb language plpgsql as $$ declare result jsonb; begin
 perform pg_temp.login(30); perform set_config('role','authenticated',true);
 perform public.read_commitment_lifecycle_operator_v1(pg_temp.id(n),'review');
 result:=pg_temp.resolve_at(pg_temp.req(600+n),k,d,t);
 perform set_config('role','none',true); return result;
end; $$;
create function pg_temp.exit_at(q uuid,c uuid,d text,t timestamptz) returns uuid language sql security definer set search_path='' as $$
 select app.close_performance_commitment_at_v1(q,c,d,t)$$;
create function pg_temp.exit(n integer,d text,t timestamptz) returns uuid language plpgsql as $$ declare result uuid; begin
 perform pg_temp.login(n); perform set_config('role','authenticated',true);
 result:=pg_temp.exit_at(pg_temp.req(700+n),pg_temp.id(n),d,t);
 perform set_config('role','none',true); return result;
end; $$;
create function pg_temp.action(n integer,q text) returns text language plpgsql as $$ declare r text; begin
 if n>0 then perform pg_temp.login(n); perform set_config('role','authenticated',true); end if;
 begin execute q into r; exception when others then r:=sqlstate; end;
 perform set_config('role','none',true); return r;
end; $$;
$defs$);
  perform extensions.dblink_exec(conn,'insert into saved select ''c''||row_number() over(order by actor_id),jsonb_build_array(id) from app.performance_commitment_agreements where actor_id::text like ''e6100000-%''');
 end loop;
end; $install$;
create function pg_temp.race(first_sql text,second_sql text,hold_seconds double precision default 0)
returns table(first_result text,second_result text,blocked boolean) language plpgsql as $$
declare deadline timestamptz:=clock_timestamp()+interval '4 seconds';
begin
 perform extensions.dblink_exec('pl_one','begin; set local statement_timeout=''8s''');
 perform extensions.dblink_exec('pl_two','begin; set local statement_timeout=''8s''');
 select x.r into first_result from extensions.dblink('pl_one',first_sql) x(r text);
 perform extensions.dblink_send_query('pl_two',second_sql);
 loop
  perform pg_stat_clear_snapshot();
  select exists(select 1 from pg_stat_activity where application_name='pl_race_two' and cardinality(pg_blocking_pids(pid))>0) into blocked;
  exit when blocked or clock_timestamp()>=deadline;
  perform pg_sleep(0.01);
 end loop;
 perform pg_sleep(hold_seconds);
 perform extensions.dblink_exec('pl_one','commit');
 select x.r into second_result from extensions.dblink_get_result('pl_two') x(r text);
 perform * from extensions.dblink_get_result('pl_two') x(r text);
 perform extensions.dblink_exec('pl_two','commit');
 return next;
end; $$;

create function pg_temp.query(actor integer,q text) returns text language sql as $$select format('select pg_temp.action(%s,%L)',actor,q)$$;
create function pg_temp.commit_query(n integer,phase text default 'ready_to_finalize',t timestamptz default '2026-07-11T12:00:00.123456Z') returns text language plpgsql as $$
declare snapshot jsonb; decision jsonb; begin
 select x.r into snapshot from extensions.dblink('pl_setup',format('select app.performance_lifecycle_load_at_v1(%L,%L)',pg_temp.id(n),t)) x(r jsonb);
 decision:=jsonb_build_object('version','performance-fixture-official-5k-v1','commitmentId',pg_temp.id(n),'termsDigest',snapshot->'agreement'->>'terms_digest',
 'proofRevision',jsonb_array_length(snapshot->'proofRevisions'),'phase',phase,'outcome','{"kind":"inconclusive","reason":"unresolved_proof"}'::jsonb,
 'disputeClosesAt',null,'reviewDueAt',null,'supportCorrectionRequired',false);
 return pg_temp.query(0,format('select app.performance_lifecycle_commit_at_v1(%L::jsonb,%L::jsonb,%L)',snapshot,decision,t));
end; $$;
create temp table outcomes(name text,first_result text,second_result text,blocked boolean);
insert into outcomes select 'notice retries',* from pg_temp.race(pg_temp.commit_query(1,'provisional'),pg_temp.commit_query(1,'provisional'));
select is(second_result,'provisional','existing notice commits idempotently') from outcomes where name='notice retries';
insert into outcomes select 'correction then worker',* from pg_temp.race(pg_temp.query(0,'select pg_temp.proof(2,0,359,''2026-07-10T12:00:00.123456Z'')::text'),pg_temp.commit_query(2));
select is(second_result,'stale','reviewed correction invalidates loaded snapshot') from outcomes where name='correction then worker';
insert into outcomes select 'case then worker',* from pg_temp.race(pg_temp.query(0,'select pg_temp.file(3,0,''2026-07-10T12:00:00.123456Z'')::text'),pg_temp.commit_query(3));
select is(second_result,'stale','case invalidates loaded final') from outcomes where name='case then worker';
insert into outcomes select 'resolution then worker',* from pg_temp.race(pg_temp.query(0,'select pg_temp.resolve(4,(select id from app.performance_lifecycle_cases where commitment_id=pg_temp.id(4)),''uphold'',''2026-07-10T12:00:00.123456Z'')::text'),pg_temp.commit_query(4));
select is(second_result,'stale','resolution invalidates loaded final') from outcomes where name='resolution then worker';
insert into outcomes select 'exit then worker',* from pg_temp.race(pg_temp.query(0,'select pg_temp.exit(5,''withdrawal'',''2026-07-10T12:00:00.123456Z'')::text'),pg_temp.commit_query(5));
select is(second_result,'stale','withdrawal invalidates loaded final') from outcomes where name='exit then worker';
insert into outcomes select 'deletion then worker',* from pg_temp.race(pg_temp.query(0,format('select public.delete_account(%L)::text',pg_temp.actor(6))),pg_temp.commit_query(6));
select is(second_result,'stale','deletion invalidates loaded final') from outcomes where name='deletion then worker';
insert into outcomes select 'final then exit',* from pg_temp.race(pg_temp.commit_query(7),pg_temp.query(7,format('select public.close_performance_commitment_v1(%L,%L,''withdrawal'')::text',pg_temp.req(2007),pg_temp.id(7))));
select is(second_result,'55000','final blocks waiting withdrawal') from outcomes where name='final then exit';
insert into outcomes select 'final then correction',* from pg_temp.race(pg_temp.commit_query(8),pg_temp.query(0,'select pg_temp.proof(8,0,359,''2026-07-12T12:00:00.123456Z'')::text'));
select is(second_result,'55000','final blocks waiting proof') from outcomes where name='final then correction';
insert into outcomes select 'final then final',* from pg_temp.race(pg_temp.commit_query(9),pg_temp.commit_query(9));
select is(second_result,'stale','second final must reload authoritative first result') from outcomes where name='final then final';
insert into outcomes select 'settlement then settlement',* from pg_temp.race(pg_temp.query(0,'select public.settle_commitment_simulation_v1(pg_temp.id(9))::text'),pg_temp.query(0,'select public.settle_commitment_simulation_v1(pg_temp.id(9))::text'));
select is(first_result,second_result,'concurrent settlement returns same receipt') from outcomes where name='settlement then settlement';
insert into outcomes select 'unreviewed source then worker',* from pg_temp.race(pg_temp.query(0,'select app.capture_commitment_attempt_at_v1(pg_temp.req(3011),pg_temp.id(11),(select attempt_id from app.performance_attempt_sources where commitment_id=pg_temp.id(11) limit 1),(select document from app.performance_attempt_sources where commitment_id=pg_temp.id(11) limit 1),''2026-07-10T12:00:00.123456Z'')::text'),pg_temp.commit_query(11));
select is(second_result,'stale','captured source also invalidates complete proof snapshot') from outcomes where name='unreviewed source then worker';
insert into outcomes select 'gate shutdown then worker',* from pg_temp.race('select public.set_commitment_lifecycle_enabled_v1(false)::text',pg_temp.commit_query(12));
select is(second_result,'42501','waiting worker observes disabled gate') from outcomes where name='gate shutdown then worker';
select x.r from extensions.dblink('pl_setup','select public.set_commitment_lifecycle_enabled_v1(true)') x(r boolean);
select extensions.dblink_exec('pl_setup','update auth.sessions set not_after=clock_timestamp()+interval ''0.5 seconds'' where user_id=''e6100000-0000-0000-0000-000000000013''');
insert into outcomes select 'session expiry during wait',* from pg_temp.race('select singleton::text from app.performance_lifecycle_runtime for update',pg_temp.query(13,format('select public.get_commitment_lifecycle_v1(%L)::text',pg_temp.id(13))),0.8);
select is(second_result,'42501','natural session expiry rechecked after runtime wait') from outcomes where name='session expiry during wait';
insert into outcomes select 'session revocation then history',* from pg_temp.race(format('with d as(delete from auth.sessions where user_id=%L returning id) select count(*)::text from d',pg_temp.actor(10)),pg_temp.query(10,format('select public.get_commitment_lifecycle_v1(%L)::text',pg_temp.id(10))));
select is(second_result,'42501','revoked session cannot read history') from outcomes where name='session revocation then history';
insert into outcomes select 'operator revocation then read',* from pg_temp.race(format('select public.set_commitment_lifecycle_operator_v1(%L,%L,%L,''review'',null)::text',pg_temp.req(4002),pg_temp.id(2),pg_temp.actor(30)),pg_temp.query(30,format('select public.read_commitment_lifecycle_operator_v1(%L,''review'')::text',pg_temp.id(2))));
select is(second_result,'42501','waiting operator loses revoked permission') from outcomes where name='operator revocation then read';
select x.r from extensions.dblink('pl_setup',format('select public.set_commitment_lifecycle_operator_v1(%L,%L,%L,''review'',clock_timestamp()+interval ''0.5 seconds'')',pg_temp.req(4003),pg_temp.id(3),pg_temp.actor(30))) x(r bigint);
insert into outcomes select 'operator expiry during wait',* from pg_temp.race('select singleton::text from app.performance_lifecycle_runtime for update',pg_temp.query(30,format('select public.read_commitment_lifecycle_operator_v1(%L,''review'')::text',pg_temp.id(3))),0.8);
select is(second_result,'42501','operator expiry rechecked after wait') from outcomes where name='operator expiry during wait';
select ok(blocked,name||': observed lock wait') from outcomes order by name;
select ok(first_result not in ('42501','22023','55000','23505','23514','23503'),name||': first action succeeded') from outcomes order by name;
select extensions.dblink_exec('pl_setup',$cleanup$
begin;
set local session_replication_role=replica;
delete from app.performance_lifecycle_audit where commitment_id in(select id from app.performance_commitment_agreements where actor_id::text like 'e6100000-%');
delete from app.performance_lifecycle_requests where commitment_id in(select id from app.performance_commitment_agreements where actor_id::text like 'e6100000-%');
delete from app.performance_lifecycle_support where commitment_id in(select id from app.performance_commitment_agreements where actor_id::text like 'e6100000-%');
delete from app.performance_lifecycle_settlements where commitment_id in(select id from app.performance_commitment_agreements where actor_id::text like 'e6100000-%');
delete from app.performance_lifecycle_resolutions where case_id in(select id from app.performance_lifecycle_cases where commitment_id in(select id from app.performance_commitment_agreements where actor_id::text like 'e6100000-%'));
delete from app.performance_lifecycle_cases where commitment_id in(select id from app.performance_commitment_agreements where actor_id::text like 'e6100000-%');
delete from app.performance_lifecycle_grants where commitment_id in(select id from app.performance_commitment_agreements where actor_id::text like 'e6100000-%');
delete from app.performance_lifecycle_notices where commitment_id in(select id from app.performance_commitment_agreements where actor_id::text like 'e6100000-%');
delete from app.performance_lifecycle_activations where commitment_id in(select id from app.performance_commitment_agreements where actor_id::text like 'e6100000-%');
delete from app.performance_lifecycle_results where commitment_id in(select id from app.performance_commitment_agreements where actor_id::text like 'e6100000-%');
delete from app.performance_lifecycle_retention where commitment_id in(select id from app.performance_commitment_agreements where actor_id::text like 'e6100000-%');
delete from app.performance_attempt_audit where commitment_id in(select id from app.performance_commitment_agreements where actor_id::text like 'e6100000-%');
delete from app.performance_attempt_requests where commitment_id in(select id from app.performance_commitment_agreements where actor_id::text like 'e6100000-%');
delete from app.performance_attempt_revisions where commitment_id in(select id from app.performance_commitment_agreements where actor_id::text like 'e6100000-%');
delete from app.performance_attempt_sources where commitment_id in(select id from app.performance_commitment_agreements where actor_id::text like 'e6100000-%');
delete from app.performance_attempt_nominations where commitment_id in(select id from app.performance_commitment_agreements where actor_id::text like 'e6100000-%');
delete from app.performance_attempt_confirmations where commitment_id in(select id from app.performance_commitment_agreements where actor_id::text like 'e6100000-%');
delete from app.performance_attempt_grants where commitment_id in(select id from app.performance_commitment_agreements where actor_id::text like 'e6100000-%');
delete from app.performance_attempt_retention where commitment_id in(select id from app.performance_commitment_agreements where actor_id::text like 'e6100000-%');
delete from app.performance_attempt_events where id::text like 'e6200000-%';
delete from app.performance_commitment_requests where actor_id::text like 'e6100000-%';
delete from app.performance_commitment_enrollments where actor_id::text like 'e6100000-%';
delete from app.performance_commitment_consents where actor_id::text like 'e6100000-%';
delete from app.performance_commitment_agreements where actor_id::text like 'e6100000-%';
delete from app.performance_commitment_beta_allowlist where actor_id::text like 'e6100000-%';
update app.performance_commitment_runtime set admission_enabled=false;
update app.performance_attempt_runtime set enabled=false;
update app.performance_lifecycle_runtime set enabled=false;
delete from app.profile_handle_claims where actor_id::text like 'e6100000-%';
delete from app.active_profile_auth_bindings where actor_id::text like 'e6100000-%';
delete from public.profiles where id::text like 'e6100000-%';
delete from auth.sessions where user_id::text like 'e6100000-%';
delete from auth.users where id::text like 'e6100000-%';
commit;
$cleanup$);
select extensions.dblink_disconnect('pl_one');
select extensions.dblink_disconnect('pl_two');
select extensions.dblink_disconnect('pl_setup');
select * from finish();
rollback;
