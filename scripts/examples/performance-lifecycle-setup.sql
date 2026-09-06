-- Rollback-only shared fixture for SQL and the actual evaluator/worker smoke.
-- Every timestamp below is a fictional clock injection, not elapsed operation.
begin;
set local timezone='UTC';
create function pg_temp.actor(n integer) returns uuid language sql immutable as $$
 select ('e7100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.req(n integer) returns uuid language sql immutable as $$
 select ('e7200000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.login(n integer) returns void language plpgsql as $$ begin
 perform set_config('request.jwt.claim.sub',pg_temp.actor(n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.actor(n),'role','authenticated','session_id',pg_temp.req(n))::text,true);
end; $$;
insert into auth.users(id) select pg_temp.actor(n) from generate_series(1,30) n;
insert into public.profiles(id,handle,display_name,timezone)
 select pg_temp.actor(n),'lifecyclefixture'||n,'Fictional Runner','UTC' from generate_series(1,30) n;
insert into auth.sessions(id,user_id) select pg_temp.req(n),pg_temp.actor(n) from generate_series(1,30) n;
select public.set_performance_commitment_admission_v1(true,array(select pg_temp.actor(n) from generate_series(1,29) n));
select public.set_commitment_attempts_enabled_v1(true);
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
