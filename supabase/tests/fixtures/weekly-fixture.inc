-- Rollback-only fictional fixtures. Caller owns BEGIN/ROLLBACK. No hosted runner.
insert into auth.users(id) select ('ed000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid from generate_series(1,40) n;
insert into public.profiles(id,handle,display_name,timezone)
 select id,'weeklyfixture'||right(id::text,4),'Weekly Fixture','America/Chicago' from auth.users where id::text like 'ed000000-%';
insert into auth.sessions(id,user_id)
 select ('ee000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,('ed000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid from generate_series(1,40) n;
insert into public.friendships(user_a,user_b,requested_by,status)
 select a.id,b.id,a.id,'accepted' from public.profiles a cross join public.profiles b where a.id::text like 'ed000000-%' and b.id::text like 'ed000000-%' and a.id<b.id;
select public.set_weekly_runtime_v1(true,true,true,array(select id from public.profiles where id::text like 'ed000000-%'));
create function pg_temp.actor(n integer) returns uuid language sql as $$select ('ed000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.req(n integer) returns uuid language sql as $$select ('ee000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.login(n integer) returns void language plpgsql as $$begin
 perform set_config('request.jwt.claim.sub',pg_temp.actor(n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.actor(n),'session_id',pg_temp.req(n))::text,true);
 perform set_config('role','authenticated',true);
end; $$;
create function pg_temp.terms(first_actor integer,total integer,week date default '2026-09-07',stamp timestamptz default '2026-08-31T10:00:00Z') returns jsonb
language sql security definer set search_path='' as $$select app.weekly_terms_v1((select jsonb_agg(jsonb_build_object('actor_id',pg_temp.actor(n),'target_steps',70000)) from generate_series(first_actor,first_actor+total-1) n),week,'America/Chicago',pg_temp.actor(first_actor),stamp)$$;
create function pg_temp.create_friend(r uuid,t jsonb,n timestamptz default '2026-08-31T10:00:00Z') returns uuid
language sql security definer set search_path='' as $$select app.weekly_create_at_v1(r,t,encode(extensions.digest(t::text,'sha256'),'hex'),true,n)$$;
create function pg_temp.accept(r uuid,c uuid,n timestamptz default '2026-08-31T11:00:00Z') returns uuid
language sql security definer set search_path='' as $$select app.weekly_join_at_v1(r,c,(select terms_digest from app.weekly_agreements where id=c),true,(select mode from app.weekly_agreements where id=c),n)$$;
create function pg_temp.exit(r uuid,c uuid,k text,n timestamptz default '2026-09-08T11:00:00Z') returns uuid
language sql security definer set search_path='' as $$select app.weekly_exit_at_v1(r,c,k,n)$$;
create function pg_temp.file(r uuid,c uuid,rev integer,reason text,n timestamptz) returns uuid
language sql security definer set search_path='' as $$select app.weekly_file_at_v1(r,c,rev,reason,n)$$;
create function pg_temp.make_friend(first_actor integer,total integer,week date default '2026-09-07') returns uuid language plpgsql as $$
declare c uuid; n integer; begin
 perform pg_temp.login(first_actor); c:=pg_temp.create_friend(extensions.gen_random_uuid(),pg_temp.terms(first_actor,total,week));
 for n in first_actor+1..first_actor+total-1 loop perform pg_temp.login(n); perform pg_temp.accept(extensions.gen_random_uuid(),c); end loop;
 perform set_config('role','none',true); return c;
end; $$;
create function pg_temp.capture(c uuid,steps integer,status text default 'complete',n timestamptz default '2026-09-15T04:00:00Z') returns void language plpgsql as $$
declare actor uuid; day date; begin
 for actor in select actor_id from app.weekly_participants where challenge_id=c and accepted_at is not null loop
  for day in select (x->>'date')::date from app.weekly_agreements g cross join lateral jsonb_array_elements(g.terms->'days') x where id=c loop
   perform app.weekly_fixture_at_v1(extensions.gen_random_uuid(),c,actor,day,status,steps,n);
  end loop;
 end loop;
end; $$;
create temp table weekly_test_ids(name text primary key,id uuid);
grant all on weekly_test_ids to authenticated;
