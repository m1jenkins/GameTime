begin;
select no_plan();
\ir fixtures/challenge-fixture.inc
select pg_temp.login_beta(1);
insert into beta_ids(name,id) select 'lobby'||i,pg_temp.beta_create() from generate_series(1,3) i;
create temp table beta_pages(value jsonb);grant all on beta_pages to authenticated;
insert into beta_pages select public.challenge_section_v1('upcoming',null,1);
select is(jsonb_array_length((select value->'rows' from beta_pages)),1,'first page respects requested bound');
select ok((select value->'next_cursor'<>'null' from beta_pages),'stable opaque cursor returned');
select is(public.challenge_section_v1('history',null,10)->'rows','[]'::jsonb,'independent empty history is an explicit success');
select pg_temp.login_beta(2);
select throws_ok($$select public.challenge_section_v1('upcoming',(select value->'next_cursor' from beta_pages),1)$$,'55000','challenge_page_expired','cursor cannot cross actors');
select pg_temp.login_beta(1);
select throws_ok($$select public.challenge_section_v1('history',(select value->'next_cursor' from beta_pages),1)$$,'55000','challenge_page_expired','cursor cannot cross sections');
select throws_ok($$select public.challenge_section_v1('upcoming',null,51)$$,'22023','challenge_invalid_page','page payload bounded at fifty');
-- A concurrent membership/status change cannot reorder the ID cursor or serve
-- cached social details. Membership is rechecked on every projected row.
insert into beta_ids values('newer',pg_temp.beta_create());
create temp table beta_next(value jsonb);grant all on beta_next to authenticated;
insert into beta_next select public.challenge_section_v1('upcoming',(select value->'next_cursor' from beta_pages),2);
select is(jsonb_array_length((select value->'rows' from beta_next)),2,'original ordering retains the next two rows');
select is((select value->>'projection_revision' from beta_next),(select value->>'projection_revision' from beta_pages),'same ordering revision across pages');
select ok(not exists(select 1 from beta_next cross join lateral jsonb_array_elements(value->'rows') item where item->>'id'=(select id::text from beta_ids where name='newer')),'new rows enter only a fresh ordering snapshot');
select is((select value->'next_cursor' from beta_next),'null'::jsonb,'last page ends explicitly');
select is(jsonb_array_length(public.challenge_section_v1('upcoming',null,10)->'rows'),4,'fresh first page includes new lobby');
select pg_temp.beta_mutate((select id from beta_ids where name='newer'),'cancel');
select is(jsonb_array_length(public.challenge_section_v1('history',null,10)->'rows'),1,'safe cancellation immediately enters own history');
reset role;
select ok(not has_table_privilege('authenticated','app.challenge_pages_v1','select'),'cursor storage private');
select ok(not has_function_privilege('anon','public.challenge_section_v1(text,jsonb,integer)','execute'),'no anonymous section access');
select * from finish();rollback;
