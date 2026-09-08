begin;
select no_plan();
\ir fixtures/challenge-fixture.inc
-- Build a consented two-person roster while retaining one unselected invitee.
create function pg_temp.with_outsider(first_actor integer) returns uuid language plpgsql as $$
declare c uuid;i integer;begin
 c:=pg_temp.beta_group(first_actor,2);perform pg_temp.login_beta(first_actor);
 perform pg_temp.beta_mutate(c,'reopen');
 perform pg_temp.beta_mutate(c,'invite',jsonb_build_object('username','betafixture'||lpad((first_actor+2)::text,4,'0')));
 perform pg_temp.beta_mutate(c,'freeze');
 for i in first_actor..first_actor+1 loop
  perform pg_temp.login_beta(i);perform pg_temp.beta_mutate(c,'consent',jsonb_build_object('consent',true,'digest',public.challenge_detail_v1(c)->'agreement'->>'digest'));
 end loop;
 perform set_config('role','none',true);return c;
end $$;
insert into beta_ids values('outsider',pg_temp.with_outsider(1)),('departure',pg_temp.beta_group(4,3));
create temp table before_agreements as select challenge_id,jsonb_agg(to_jsonb(a) order by version) value from app.challenge_agreements_v1 a where challenge_id in(select id from beta_ids) group by challenge_id;
select pg_temp.login_beta(3);
select public.challenge_command_v1(pg_temp.br(20001),jsonb_build_object('op','block','subject',pg_temp.ba(2)));
reset role;
select is((select status from app.challenge_lobbies_v1 where id=(select id from beta_ids where name='outsider')),'scheduled','an unselected outsider cannot void the two selected participants');
select ok(not exists(select 1 from app.challenge_members_v1 where challenge_id=(select id from beta_ids where name='outsider') and selected and exited_at is not null),'outsider block does not end a selected participant agreement');
select ok(app.is_blocked_either_way(pg_temp.ba(3),pg_temp.ba(2)),'the outsider account block is still honored');
select pg_temp.login_beta(2);
select is(public.challenge_detail_v1((select id from beta_ids where name='outsider'))->>'social_hidden','false','selected participant retains permitted shared roster');
select ok(not exists(select 1 from jsonb_array_elements(public.challenge_detail_v1((select id from beta_ids where name='outsider'))->'members') p where p->>'username'='betafixture0003'),'blocked outsider identity is absent from selected projection');
reset role;
-- The third selected participant leaves an active goal; the other two continue.
select pg_temp.clock_beta('2026-10-05T12:00Z');
select public.challenge_process_v1((select id from beta_ids where name='departure'));
select public.challenge_capture_fixture_v1(extensions.gen_random_uuid(),(select id from beta_ids where name='departure'),pg_temp.ba(6),12345,'complete');
select pg_temp.login_beta(4);
select is((select p->'fact'->>'value' from jsonb_array_elements(public.challenge_detail_v1((select id from beta_ids where name='departure'))->'members') p where p->>'actor_id'=pg_temp.ba(6)::text),'12345','selected counterpart can see shared fictional activity before withdrawal');
select pg_temp.login_beta(6);
select pg_temp.beta_mutate((select id from beta_ids where name='departure'),'leave');
set constraints all immediate;
set constraints all deferred;
select is(public.challenge_detail_v1((select id from beta_ids where name='departure'))->>'social_hidden','true','the person who leaves has an own-only projection');
select is((select p->'fact'->>'value' from jsonb_array_elements(public.challenge_detail_v1((select id from beta_ids where name='departure'))->'members') p where p->>'actor_id'=pg_temp.ba(6)::text),'12345','withdrawal preserves the departing person’s own fictional activity receipt');
select pg_temp.login_beta(4);
select is(public.challenge_detail_v1((select id from beta_ids where name='departure'))->>'status','active','two remaining selected participants continue');
select ok(not exists(select 1 from jsonb_array_elements(public.challenge_detail_v1((select id from beta_ids where name='departure'))->'members') p where p->>'actor_id'=pg_temp.ba(6)::text and p->'fact'<>'null'::jsonb),'counterpart no longer receives departed activity');
select ok(not exists(select 1 from jsonb_array_elements(public.challenge_detail_v1((select id from beta_ids where name='departure'))->'members') p where p->>'username'='betafixture0006'),'counterpart no longer receives departed username');
select ok(not exists(select 1 from jsonb_array_elements(public.challenge_detail_v1((select id from beta_ids where name='departure'))->'members') p where p->>'actor_id'=pg_temp.ba(6)::text and p->'target'<>'null'::jsonb),'counterpart receives no current departed target');
reset role;
select ok(not exists(select 1 from before_agreements b where b.value is distinct from(select jsonb_agg(to_jsonb(a) order by version) from app.challenge_agreements_v1 a where challenge_id=b.challenge_id)),'block and withdrawal leave immutable agreements byte-identical');
select is((select count(*)::integer from app.challenge_facts_v1 where challenge_id=(select id from beta_ids where name='departure') and actor_id=pg_temp.ba(6)),1,'display privacy does not delete retained fictional facts');
select * from finish();
rollback;
