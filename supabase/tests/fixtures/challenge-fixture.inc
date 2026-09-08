-- Fictional rollback-only actors, authenticated SQL roles, service-owned clock.
insert into auth.users(id) select ('bf000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid from generate_series(1,40) n;
insert into public.profiles(id,handle,display_name,timezone)
 select id,'betafixture'||right(id::text,4),'Fictional Beta','America/Chicago' from auth.users where id::text like 'bf000000-%';
insert into auth.sessions(id,user_id)
 select ('ba000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,('bf000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid from generate_series(1,40) n;
insert into public.friendships(user_a,user_b,requested_by,status)
 select a.id,b.id,a.id,'accepted' from public.profiles a cross join public.profiles b where a.id::text like 'bf000000-%' and b.id::text like 'bf000000-%' and a.id<b.id;
create function pg_temp.ba(n integer) returns uuid language sql as $$select ('bf000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.br(n integer) returns uuid language sql as $$select ('ba000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.login_beta(n integer) returns void language plpgsql as $$begin
 perform set_config('request.jwt.claim.sub',pg_temp.ba(n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.ba(n),'session_id',pg_temp.br(n))::text,true);
 perform set_config('role','authenticated',true);
end $$;
create function pg_temp.clock_beta(n timestamptz,admission boolean default true,processing boolean default true) returns void language sql security definer set search_path='' as $$
 select public.challenge_runtime_v1(admission,true,processing,array(select id from public.profiles where id::text like 'bf000000-%'),n)
$$;
select pg_temp.clock_beta('2026-10-01T12:00Z');
select public.challenge_readiness_fixture_v1(pg_temp.ba(n)) from generate_series(1,40) n;
create function pg_temp.beta_mutate(c uuid,op text,extra jsonb default '{}',r uuid default extensions.gen_random_uuid()) returns jsonb language sql security definer set search_path='' as $$
 select public.challenge_mutate_v1(r,jsonb_build_object('id',c,'op',op,'revision',(select revision from app.challenge_lobbies_v1 where id=c))||extra)
$$;
create function pg_temp.beta_create() returns uuid language sql as $$
 select (public.challenge_mutate_v1(extensions.gen_random_uuid(),'{"op":"create","config":{"start_date":"2026-10-03","days":7,"timezone":"America/Chicago","amount_cents":100}}')->>'id')::uuid
$$;
create function pg_temp.beta_group(first_actor integer,people integer) returns uuid language plpgsql as $$
declare c uuid; i integer; begin
 perform pg_temp.login_beta(first_actor); c:=pg_temp.beta_create();
 perform pg_temp.beta_mutate(c,'target','{"target":10000}');
 for i in first_actor+1..first_actor+people-1 loop
  perform pg_temp.beta_mutate(c,'invite',jsonb_build_object('username','betafixture'||lpad(i::text,4,'0')));
  perform pg_temp.login_beta(i); perform pg_temp.beta_mutate(c,'target',jsonb_build_object('target',10000+i));
  perform pg_temp.login_beta(first_actor); perform pg_temp.beta_mutate(c,'select',jsonb_build_object('actor_id',pg_temp.ba(i),'selected',true));
 end loop;
 perform pg_temp.beta_mutate(c,'freeze');
 for i in first_actor..first_actor+people-1 loop
  perform pg_temp.login_beta(i);
  perform pg_temp.beta_mutate(c,'consent',jsonb_build_object('consent',true,'digest',public.challenge_detail_v1(c)->'agreement'->>'digest'));
 end loop;
 perform set_config('role','none',true); return c;
end $$;
create temp table beta_ids(name text primary key,id uuid);
grant all on beta_ids to authenticated;
