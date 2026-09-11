begin;
select no_plan();
\ir fixtures/challenge-fixture.inc

select ok(not has_function_privilege(role_name,'app.challenge_lock_v1(text,uuid)','execute'),role_name||' cannot invoke scoped locks')
from unnest(array['anon','authenticated','service_role']) role_name;
select ok(not has_function_privilege(role_name,'app.challenge_claim_work_v1(integer)','execute'),role_name||' cannot claim worker rows')
from unnest(array['anon','authenticated','service_role']) role_name;
select is(proconfig,array['search_path=""'],'session helper keeps an empty search path')
from pg_proc where oid='app.challenge_session_v1()'::regprocedure;
select ok(pg_get_functiondef('app.challenge_session_v1()'::regprocedure) not like '%challenge_runtime_v1 where singleton for update%','session no longer takes the singleton row mutex');
select ok(pg_get_functiondef('app.challenge_tick_v1(uuid,boolean)'::regprocedure) not like '%challenge_runtime_v1 where singleton for update%','worker tick no longer takes the singleton row mutex');
select ok(pg_get_functiondef('public.challenge_run_batch_v1(uuid,integer)'::regprocedure) not like '%challenge_runtime_v1 where singleton for update%','worker batch no longer takes the singleton row mutex');
select is((select pg_get_constraintdef(oid) from pg_constraint where conrelid='app.challenge_lobbies_v1'::regclass and conname='challenge_lobbies_v1_capacity_check'),'CHECK ((((capacity >= 1) AND (capacity <= 250)) AND (capacity >= minimum)))','community fixture schema admits the 250-person planning boundary');

-- Two due challenges are claimed one at a time and complete independently.
insert into beta_ids values('claim_a',pg_temp.beta_group(1,2));
insert into beta_ids values('claim_b',pg_temp.beta_group(3,2));
select pg_temp.clock_beta('2026-10-10T12:00Z');
select public.challenge_capture_fixture_v1(extensions.gen_random_uuid(),challenge_id,actor_id,20000,'complete')
from app.challenge_slots_v1 where challenge_id in(select id from beta_ids where name in('claim_a','claim_b'));
select pg_temp.clock_beta('2026-10-20T12:00Z',false,true);
create temp table first_claim(value jsonb);
insert into first_claim select public.challenge_run_batch_v1(pg_temp.br(51001),1);
select is(jsonb_array_length((select value->'processed' from first_claim)),1,'bounded worker claims exactly its requested limit');
select is(public.challenge_run_batch_v1(pg_temp.br(51001),1),(select value from first_claim),'worker run exact retry is idempotent');
select throws_ok($$select public.challenge_run_batch_v1(pg_temp.br(51001),2)$$,'22023','challenge_request_conflict','worker run ID rejects a changed claim limit');
create temp table second_claim(value jsonb);
insert into second_claim select public.challenge_run_batch_v1(pg_temp.br(51002),1);
select is(jsonb_array_length((select value->'processed' from second_claim)),1,'an independent worker run claims the other challenge');
select isnt((select value->'processed'->0->>'id' from first_claim),(select value->'processed'->0->>'id' from second_claim),'independent worker runs do not process the same challenge');

-- A cancelled draft has no agreement/final row, but is terminal work and must
-- never be reclaimed on every scheduler pass.
select pg_temp.clock_beta('2026-10-01T12:00Z');
select pg_temp.login_beta(10);
insert into beta_ids values('cancelled_draft',pg_temp.beta_create());
select pg_temp.beta_mutate((select id from beta_ids where name='cancelled_draft'),'cancel');
reset role;
select ok(not exists(select 1 from app.challenge_work_v1() where id=(select id from beta_ids where name='cancelled_draft')),'cancelled terminal draft is absent from worker discovery');

-- Rollback-only fictional actors exercise the exact 249/250/251 join boundary.
insert into auth.users(id)
select ('bc000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid from generate_series(1,251)n;
insert into public.profiles(id,handle,display_name,timezone)
select id,'capacity'||right(id::text,6),'Fictional capacity','UTC' from auth.users where id::text like 'bc000000-%';
insert into auth.sessions(id,user_id)
select ('bd000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,('bc000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid from generate_series(1,251)n;
select set_config('app.challenge_write_v1','on',true);
insert into app.challenge_age_v1(actor_id,policy,confirmed_at)
select id,'age_21_v1','2026-10-01T12:00Z' from public.profiles where id::text like 'bc000000-%';
insert into app.challenge_access_v1(actor_id,granted_at)
select id,'2026-10-01T12:00Z' from public.profiles where id::text like 'bc000000-%';
insert into app.challenge_readiness_v1(actor_id,recorded_at,source,metric)
select id,'2026-10-01T12:00Z','fictional_steps_v1','steps' from public.profiles where id::text like 'bc000000-%';
insert into beta_ids values('capacity_250',public.challenge_publish_community_fixture_v1(
 pg_temp.br(52000),pg_temp.ba(40),'{"start_date":"2026-10-03","days":1,"timezone":"UTC","amount_cents":100}',100,2,250,true));

create function pg_temp.capacity_actor(n integer) returns uuid language sql immutable as
$$select ('bc000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.capacity_session(n integer) returns uuid language sql immutable as
$$select ('bd000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.capacity_request(n integer) returns uuid language sql immutable as
$$select ('be000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.join_capacity(n integer,c uuid,d text) returns jsonb language plpgsql as $$
declare response jsonb;
begin
 perform set_config('request.jwt.claim.sub',pg_temp.capacity_actor(n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.capacity_actor(n),'session_id',pg_temp.capacity_session(n))::text,true);
 perform set_config('role','authenticated',true);
 response:=public.challenge_join_community_v1(pg_temp.capacity_request(n),jsonb_build_object('op','join_community','id',c,'digest',d,'consent',true));
 perform set_config('role','none',true);
 return response;
exception when others then
 perform set_config('role','none',true);
 raise;
end
$$;
create temp table capacity_terms as
select c.id,a.digest from app.challenge_lobbies_v1 c join app.challenge_agreements_v1 a on a.challenge_id=c.id and a.version=c.agreement_version
where c.id=(select id from beta_ids where name='capacity_250');
select lives_ok($$select pg_temp.join_capacity(n,(select id from capacity_terms),(select digest from capacity_terms)) from generate_series(1,248)n$$,'first 248 community joins succeed');
select is(pg_temp.join_capacity(249,(select id from capacity_terms),(select digest from capacity_terms))->>'status','published_open','249th community join succeeds');
select is(pg_temp.join_capacity(250,(select id from capacity_terms),(select digest from capacity_terms))->>'status','published_open','250th community join succeeds');
select is((select count(*) from app.challenge_members_v1 where challenge_id=(select id from capacity_terms) and exited_at is null),250::bigint,'community retains exactly 250 joined actors');
select throws_ok($$select pg_temp.join_capacity(251,(select id from capacity_terms),(select digest from capacity_terms))$$,'23505','challenge_capacity','251st community join is rejected');
select is((select count(*) from app.challenge_members_v1 where challenge_id=(select id from capacity_terms) and exited_at is null),250::bigint,'251st rejection does not overfill capacity');

select * from finish();
rollback;
