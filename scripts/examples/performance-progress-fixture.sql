-- Caller owns BEGIN/ROLLBACK. Fictional actors and private clock seams only.
create function pg_temp.pp_actor(n integer) returns uuid language sql immutable as $$
 select ('e7100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.pp_req(n integer) returns uuid language sql immutable as $$
 select ('e7200000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.pp_login(n integer) returns void language plpgsql as $$ begin
 perform set_config('request.jwt.claim.sub',pg_temp.pp_actor(n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.pp_actor(n),'role','authenticated','session_id',pg_temp.pp_req(n))::text,true);
end; $$;
insert into auth.users(id) select pg_temp.pp_actor(n) from generate_series(1,3) n;
insert into public.profiles(id,handle,display_name,timezone)
 select pg_temp.pp_actor(n),'progressfixture'||n,'Fictional Runner','UTC' from generate_series(1,3) n;
insert into auth.sessions(id,user_id) select pg_temp.pp_req(n),pg_temp.pp_actor(n) from generate_series(1,3) n;
select public.set_performance_commitment_admission_v1(true,array[pg_temp.pp_actor(1),pg_temp.pp_actor(2)]);
create temp table pp_saved(name text primary key,value jsonb);
grant select,insert,update on pp_saved to authenticated;
create function pg_temp.pp_id(n text) returns uuid language sql as $$ select (value->>0)::uuid from pp_saved where name=n $$;
create function pg_temp.pp_create(q integer) returns uuid language plpgsql security definer set search_path='' as $$
 declare s timestamptz:='2026-07-02T12:00:00.123456Z'; d timestamptz:='2026-08-31T12:00:00.123456Z'; t jsonb;
 begin
 t:=app.performance_commitment_terms_v1(auth.uid(),360,s,d,'America/Chicago','performance-commitment-fixture-5k-v1');
 return app.create_performance_commitment_at_v1(pg_temp.pp_req(q),360,s,d,'America/Chicago','performance-commitment-fixture-5k-v1',encode(extensions.digest(t::text,'sha256'),'hex'),true,'2026-07-01T12:00:00.123456Z');
end; $$;
select pg_temp.pp_login(1);
set local role authenticated;
insert into pp_saved values('main',jsonb_build_array(pg_temp.pp_create(10)));
select pg_temp.pp_login(2);
insert into pp_saved values('other',jsonb_build_array(pg_temp.pp_create(10)));
reset role;
select pg_temp.pp_login(1);
create function pg_temp.pp_milestone(q integer,title text default 'Choose an event',due timestamptz default '2026-07-10T12:00:00.123456Z',n timestamptz default '2026-07-01T13:00:00.123456Z')
 returns jsonb language sql security definer set search_path='' as $$
 select app.write_commitment_progress_at_v1(pg_temp.pp_req(q),pg_temp.pp_id('main'),'milestone_created',null,title,due,null,null,null,null,n) $$;
create function pg_temp.pp_note(q integer,note text default 'First practice run',mid uuid default null,occurred timestamptz default '2026-07-02T13:00:00.123456Z',n timestamptz default '2026-07-03T13:00:00.123456Z')
 returns jsonb language sql security definer set search_path='' as $$
 select app.write_commitment_progress_at_v1(pg_temp.pp_req(q),pg_temp.pp_id('main'),'check_in',mid,null,null,null,null,note,occurred,n) $$;
create function pg_temp.pp_status(q integer,status text,revision integer,n timestamptz default '2026-07-04T13:00:00.123456Z')
 returns jsonb language sql security definer set search_path='' as $$
 select app.write_commitment_progress_at_v1(pg_temp.pp_req(q),pg_temp.pp_id('main'),'milestone_status',pg_temp.pp_id('milestone'),null,null,status,revision,null,null,n) $$;
