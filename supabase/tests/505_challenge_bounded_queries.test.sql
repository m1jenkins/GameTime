begin;
select no_plan();
\ir fixtures/challenge-fixture.inc
-- More than two full pages, with ties in BOTH timestamp keys.
select set_config('app.challenge_write_v1','on',true);
insert into app.challenge_lobbies_v1(id,creator_id,policy,config,starts_at,ends_at,status,created_at)
select md5('p5-page:'||n)::uuid,pg_temp.ba(1),'friend_steps_goal_v1','{}',
 '2026-09-01'::timestamptz+(n%3)*interval '1 hour',
 '2026-09-02'::timestamptz+(n%2)*interval '1 hour','cancelled','2026-08-28'
from generate_series(1,105) n;
insert into app.challenge_members_v1(challenge_id,actor_id,selected)
select id,pg_temp.ba(1),true from app.challenge_lobbies_v1 where creator_id=pg_temp.ba(1);
create temp table expected as select c.id,row_number() over(order by coalesce(f.recorded_at,c.ends_at) desc,c.starts_at,c.id) rank
from app.challenge_lobbies_v1 c join app.challenge_members_v1 m on m.challenge_id=c.id left join app.challenge_finals_v1 f on f.challenge_id=c.id
where m.actor_id=pg_temp.ba(1) and (m.exited_at is not null or c.status in ('final','void','cancelled'));
create temp table pages(n integer,value jsonb);grant all on pages,expected to authenticated;
select pg_temp.login_beta(1);
insert into pages values(1,public.challenge_section_v1('history',null,50));
insert into pages values(2,public.challenge_section_v1('history',(select value->'next_cursor' from pages where n=1),50));
insert into pages values(3,public.challenge_section_v1('history',(select value->'next_cursor' from pages where n=2),50));
select is(jsonb_array_length((select value->'rows' from pages where n=1)),50,'first history page bounded');
select is(jsonb_array_length((select value->'rows' from pages where n=2)),50,'second history page bounded');
select is(jsonb_array_length((select value->'rows' from pages where n=3)),5,'last partial page');
select is((select value->'next_cursor' from pages where n=3),'null'::jsonb,'terminal page explicit');
select is((select count(distinct value->>'projection_revision')::integer from pages),1,'one ordering identity across keyset pages');
select is((select jsonb_agg(item->>'id' order by p.n,ordinality) from pages p cross join lateral jsonb_array_elements(p.value->'rows') with ordinality r(item,ordinality)),
 (select jsonb_agg(id::text order by rank) from expected),'all 105 agreements exactly once in original mixed-direction order');
select is(public.challenge_section_v1('history',(select value->'next_cursor' from pages where n=1),50)->'rows',(select value->'rows' from pages where n=2),'same cursor retry returns current same rows');
select is(public.challenge_section_v1('history',(select value->'next_cursor' from pages where n=1),1)->'rows'->0->>'id',(select id::text from expected where rank=51),'page size can change at cursor boundary');
select throws_ok($$select public.challenge_section_v1('history',null,0)$$,'22023','challenge_invalid_page','zero limit denied');
select throws_ok($$select public.challenge_section_v1('history',null,51)$$,'22023','challenge_invalid_page','large limit denied');
select throws_ok($$select public.challenge_section_v1('history','{"after":[]}',10)$$,'22023','challenge_invalid_page','malformed cursor denied');
select throws_ok($$select public.challenge_section_v1('history',(select jsonb_set(value->'next_cursor','{after,2}','null') from pages where n=1),10)$$,'22023','challenge_invalid_page','null tie-breaker denied');
select throws_ok($$select public.challenge_section_v1('history',(select jsonb_set(value->'next_cursor','{after,2}',to_jsonb(pg_temp.ba(2)::text)) from pages where n=1),10)$$,'22023','challenge_invalid_page','invented boundary denied');
select throws_ok($$select public.challenge_section_v1('history',(select jsonb_build_object('snapshot_id',value->>'projection_revision','offset',0) from pages where n=1),10)$$,'22023','challenge_invalid_page','keyset cursor cannot downgrade to offset');
select pg_temp.login_beta(2);
select throws_ok($$select public.challenge_section_v1('history',(select value->'next_cursor' from pages where n=1),50)$$,'55000','challenge_page_expired','cursor cannot cross accounts');
select is(public.challenge_section_v1('history',null,50)->'rows','[]'::jsonb,'other actor has no leaked history');
select throws_ok($$select public.challenge_detail_v1((select id from expected where rank=1))$$,'42501','challenge_unavailable','direct detail still denies other account');
select pg_temp.login_beta(1);
select throws_ok($$select public.challenge_section_v1('active',(select value->'next_cursor' from pages where n=1),50)$$,'22023','challenge_invalid_page','keyset cursor cannot cross sections');
reset role;
select is((select max(cardinality(ids)) from app.challenge_pages_v1 where history_revision is not null),0,'new pages store zero history IDs');
select ok(not has_table_privilege('authenticated','app.challenge_history_v1','select'),'history projection private');
select ok(not has_table_privilege('authenticated','app.challenge_history_revisions_v1','select'),'history revisions private');
select ok(not has_function_privilege('authenticated','app.challenge_detail_for_actor_v1(uuid,uuid)','execute'),'caller cannot supply another actor to private projector');
select ok(not has_function_privilege('authenticated','app.challenge_section_snapshot_v1(text,jsonb,integer)','execute'),'legacy adapter is private');
select ok(not has_function_privilege('anon','public.challenge_section_v1(text,jsonb,integer)','execute'),'no anonymous pages');
-- A late final changes the original sort order. Explicit expiry prevents a
-- duplicate or missing row, without changing the agreement or retaining IDs.
insert into app.challenge_finals_v1 values((select id from expected where rank=105),'{}','2026-10-01',1);
select pg_temp.login_beta(1);
select throws_ok($$select public.challenge_section_v1('history',(select value->'next_cursor' from pages where n=1),50)$$,'55000','challenge_page_expired','order-changing final expires stale cursor');
select is(public.challenge_section_v1('history',null,1)->'rows'->0->>'id',(select id::text from expected where rank=105),'fresh cursor reflects late final at top');
-- Privacy changes do not invalidate ordering; continuation reprojects live.
reset role;
insert into app.challenge_members_v1(challenge_id,actor_id,selected) values((select id from expected where rank=1),pg_temp.ba(2),true);
select pg_temp.login_beta(1);
insert into pages values(4,public.challenge_section_v1('history',null,1));
select is(public.challenge_section_v1('history',(select value->'next_cursor' from pages where n=4),1)->'rows'->0->>'social_hidden','false','visible counterpart before block');
select public.challenge_block_v1(extensions.gen_random_uuid(),pg_temp.ba(2));
select is(public.challenge_section_v1('history',(select value->'next_cursor' from pages where n=4),1)->'rows'->0->>'social_hidden','true','same cursor reauthorizes after block');
select is(jsonb_array_length(public.challenge_section_v1('history',(select value->'next_cursor' from pages where n=4),1)->'rows'->0->'members'),1,'continuation reveals only own member after block');
reset role;
-- Wall expiry and session revocation remain independent of ordering revisions.
insert into app.challenge_pages_v1(id,actor_id,section,ids,created_at,expires_at,history_revision)
values('50500000-0000-0000-0000-000000000001',pg_temp.ba(1),'history','{}',clock_timestamp()-interval '3 minutes',clock_timestamp()-interval '1 minute',1);
select pg_temp.login_beta(1);
select throws_ok($$select public.challenge_section_v1('history',jsonb_set((select value->'next_cursor' from pages where n=4),'{snapshot_id}','"50500000-0000-0000-0000-000000000001"'),1)$$,'55000','challenge_page_expired','wall-expired keyset rejected');
reset role;
delete from auth.sessions where id=pg_temp.br(1);
select pg_temp.login_beta(1);
select throws_ok($$select public.challenge_section_v1('history',(select value->'next_cursor' from pages where n=4),1)$$,'42501','challenge_session_required','revoked session cannot resume history');
reset role;
-- Compare set-based discovery to the unchanged single-item oracle across safety
-- states, including future work, nonselected/exited people and directed blocks.
select pg_temp.login_beta(4);
insert into beta_ids values('future',pg_temp.beta_create());
select pg_temp.beta_mutate((select id from beta_ids where name='future'),'invite','{"username":"betafixture0005"}');
reset role;
create function pg_temp.same_work() returns boolean language sql as $$
 select not exists((select * from app.challenge_work_v1() except select * from app.challenge_work_item_v1(null)) union all
 (select * from app.challenge_work_item_v1(null) except select * from app.challenge_work_v1()))
$$;
select ok(pg_temp.same_work(),'set discovery equals original for healthy future work');
insert into public.blocks(blocker_id,blocked_id) values(pg_temp.ba(5),pg_temp.ba(4));
select ok(pg_temp.same_work(),'pending blocked member does not change discovery');
update app.challenge_members_v1 set selected=true where challenge_id=(select id from beta_ids where name='future') and actor_id=pg_temp.ba(5);
select ok(pg_temp.same_work(),'selected directed block matches original immediate due');
select is((select due_at from app.challenge_work_v1() where id=(select id from beta_ids where name='future')),app.challenge_now_v1(),'blocked selected pair due now');
update app.challenge_members_v1 set exited_at=app.challenge_now_v1() where challenge_id=(select id from beta_ids where name='future') and actor_id=pg_temp.ba(5);
select ok(pg_temp.same_work(),'exited blocked member ignored by both discoveries');
insert into app.challenge_suspensions_v1 values(pg_temp.ba(4),true,pg_temp.ba(3),'fixture',app.challenge_now_v1());
select ok(pg_temp.same_work(),'suspended selected member matches original discovery');
select is((select due_at from app.challenge_work_v1() where id=(select id from beta_ids where name='future')),app.challenge_now_v1(),'suspended selected member due now');
select ok(not exists(select 1 from app.challenge_work_v1() where status in ('final','void','cancelled')),'terminal history excluded');
select pg_temp.clock_beta('2026-10-01T12:00Z',false,false);
select ok(pg_temp.same_work(),'paused discovery retains safe-work visibility');
select * from finish();rollback;
