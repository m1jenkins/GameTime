-- Caller owns BEGIN/ROLLBACK. Fictional fixture and private clock seams only.
create function pg_temp.pa_actor(n integer) returns uuid language sql immutable as $$
 select ('ee100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.pa_req(n integer) returns uuid language sql immutable as $$
 select ('ee200000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.pa_login(n integer) returns void language plpgsql as $$ begin
 perform set_config('request.jwt.claim.sub',pg_temp.pa_actor(n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.pa_actor(n),'role','authenticated','session_id',pg_temp.pa_req(n))::text,true);
end; $$;
insert into auth.users(id) select pg_temp.pa_actor(n) from generate_series(1,4) n;
insert into public.profiles(id,handle,display_name,timezone)
 select pg_temp.pa_actor(n),'attemptfixture'||n,'Fictional Runner','UTC' from generate_series(1,4) n;
insert into auth.sessions(id,user_id) select pg_temp.pa_req(n),pg_temp.pa_actor(n) from generate_series(1,4) n;
select public.set_performance_commitment_admission_v1(true,array[pg_temp.pa_actor(1),pg_temp.pa_actor(4)]);
create temp table pa_saved(name text primary key,id uuid);
grant select,insert on pa_saved to authenticated;
create function pg_temp.pa_id(n text) returns uuid language sql as $$ select id from pa_saved where name=n $$;
create function pg_temp.pa_create(q integer) returns uuid language plpgsql security definer set search_path='' as $$
 declare s timestamptz:='2026-07-02T12:00:00.123456Z'; d timestamptz:='2026-08-31T12:00:00.123456Z'; digest text;
 begin
 digest:=encode(extensions.digest(app.performance_commitment_terms_v1(auth.uid(),360,s,d,'America/Chicago','performance-commitment-fixture-5k-v1')::text,'sha256'),'hex');
 return app.create_performance_commitment_at_v1(pg_temp.pa_req(q),360,s,d,'America/Chicago','performance-commitment-fixture-5k-v1',digest,true,'2026-07-01T12:00:00.123456Z');
end; $$;
select pg_temp.pa_login(1);
set local role authenticated;
insert into pa_saved values('main',pg_temp.pa_create(10));
reset role;
select public.curate_commitment_fixture_event_v1(pg_temp.pa_req(101),'2026-07-03T12:00:00.123456Z','2026-07-03T14:00:00.123456Z');
select public.curate_commitment_fixture_event_v1(pg_temp.pa_req(102),'2026-08-03T12:00:00.123456Z','2026-08-03T14:00:00.123456Z');
select public.curate_commitment_fixture_event_v1(pg_temp.pa_req(103),'2026-08-31T10:00:00.123456Z','2026-08-31T12:00:00.123456Z');
create function pg_temp.pa_nominate(q integer,e integer,n timestamptz default '2026-07-01T13:00:00.123456Z',bib text default 'bib-1')
 returns uuid language sql security definer set search_path='' as $$
 select app.nominate_commitment_attempt_at_v1(pg_temp.pa_req(q),pg_temp.pa_id('main'),pg_temp.pa_req(e),bib,n) $$;
create function pg_temp.pa_document(e integer,seconds integer default 359) returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('source','fixture_official_5k_v1','event_id',id,'distance_meters',5000,'timing_basis','organizer_chip',
 'precision_ms',1000,'published_bib','bib-1','status','finished','chip_seconds',seconds,'started_at',starts_at,'finished_at',starts_at+seconds*interval '1 second')
 from app.performance_attempt_events where id=pg_temp.pa_req(e) $$;
create function pg_temp.pa_capture(q integer,a text,e integer,seconds integer default 359,n timestamptz default '2026-08-04T12:00:00.123456Z',doc jsonb default null)
 returns uuid language sql security definer set search_path='' as $$
 select app.capture_commitment_attempt_at_v1(pg_temp.pa_req(q),pg_temp.pa_id('main'),pg_temp.pa_id(a),coalesce(doc,pg_temp.pa_document(e,seconds)),n) $$;
create function pg_temp.pa_review(q integer,s integer,previous integer default null,n timestamptz default '2026-08-04T13:00:00.123456Z',confirmed boolean default true)
 returns integer language sql security definer set search_path='' as $$
 select app.review_commitment_attempt_at_v1(pg_temp.pa_req(q),pg_temp.pa_id('main'),pg_temp.pa_req(s),previous,confirmed,n) $$;
create function pg_temp.pa_confirm(q integer,ids uuid[],n timestamptz default '2026-08-31T12:00:00.123456Z',confirmed boolean default true)
 returns uuid language sql security definer set search_path='' as $$
 select app.confirm_commitment_attempt_set_at_v1(pg_temp.pa_req(q),pg_temp.pa_id('main'),ids,confirmed,n) $$;
