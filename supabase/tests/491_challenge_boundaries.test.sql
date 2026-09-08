begin;
select no_plan();
\ir fixtures/challenge-fixture.inc
select is((app.challenge_window_v1('{"start_date":"2026-11-01","days":1,"timezone":"America/Chicago","amount_cents":100}','2026-10-30T12:00Z')->>'ends_at')::timestamptz-(app.challenge_window_v1('{"start_date":"2026-11-01","days":1,"timezone":"America/Chicago","amount_cents":100}','2026-10-30T12:00Z')->>'starts_at')::timestamptz,interval '25 hours','fall DST is full local day');
select is((app.challenge_window_v1('{"start_date":"2026-03-08","days":1,"timezone":"America/Chicago","amount_cents":100}','2026-03-06T12:00Z')->>'ends_at')::timestamptz-(app.challenge_window_v1('{"start_date":"2026-03-08","days":1,"timezone":"America/Chicago","amount_cents":100}','2026-03-06T12:00Z')->>'starts_at')::timestamptz,interval '23 hours','spring DST is full local day');
select throws_ok($$select app.challenge_window_v1('{"start_date":"2026-10-02","days":1,"timezone":"UTC","amount_cents":100}','2026-10-01T12:00Z')$$,'22023','challenge_invalid_lead','one day lead rejected');
select lives_ok($$select app.challenge_window_v1('{"start_date":"2026-10-31","days":30,"timezone":"UTC","amount_cents":50000}','2026-10-01T12:00Z')$$,'maximum lead and duration accepted');
select throws_ok($$select app.challenge_window_v1('{"start_date":"2026-11-01","days":1,"timezone":"UTC","amount_cents":100}','2026-10-01T12:00Z')$$,'22023','challenge_invalid_lead','31 day lead rejected');
select throws_ok($$select app.challenge_window_v1('{"start_date":"2026-10-03","days":31,"timezone":"UTC","amount_cents":100}','2026-10-01T12:00Z')$$,'22023','challenge_invalid_window','31 day duration rejected');
select throws_ok($$select app.challenge_window_v1('{"start_date":"2026-10-03","days":1,"timezone":"UTC","amount_cents":101}','2026-10-01T12:00Z')$$,'22023','challenge_invalid_window','fractional dollar rejected');
insert into beta_ids values('six',pg_temp.beta_group(1,6));
select pg_temp.login_beta(1);
insert into beta_ids values('overlap',pg_temp.beta_create());
select pg_temp.beta_mutate((select id from beta_ids where name='overlap'),'target','{"target":100}');
select pg_temp.beta_mutate((select id from beta_ids where name='overlap'),'invite','{"username":"BETAFIXTURE0007"}');
select pg_temp.login_beta(7);
select pg_temp.beta_mutate((select id from beta_ids where name='overlap'),'target','{"target":100}');
select pg_temp.login_beta(1);
select pg_temp.beta_mutate((select id from beta_ids where name='overlap'),'select',jsonb_build_object('actor_id',pg_temp.ba(7),'selected',true));
select throws_ok($$select pg_temp.beta_mutate((select id from beta_ids where name='overlap'),'freeze')$$,'23505','challenge_metric_overlap','overlapping friend metric rejected at slot claim');
reset role;
select pg_temp.clock_beta('2026-10-01T12:00Z',false,false);
select pg_temp.login_beta(6);
select pg_temp.beta_mutate((select id from beta_ids where name='six'),'leave');
set constraints app.challenge_exit_reconcile immediate;
reset role;
select is((select status from app.challenge_lobbies_v1 where id=(select id from beta_ids where name='six')),'scheduled','six-person safe exit continues five despite pause');
select pg_temp.clock_beta('2026-10-10T06:00Z',false,true);
select public.challenge_capture_fixture_v1(extensions.gen_random_uuid(),(select id from beta_ids where name='six'),pg_temp.ba(n),case when n<5 then 20000 else 0 end,'complete') from generate_series(1,5) n;
select pg_temp.clock_beta('2026-10-12T06:00Z',false,true);
select public.challenge_process_v1((select id from beta_ids where name='six'));
select pg_temp.clock_beta('2026-10-14T06:00Z',false,true);
select is(public.challenge_process_v1((select id from beta_ids where name='six')),'final','five known plus one exit final');
select is((select result->'participants'->pg_temp.ba(6)::text->>'returned_cents' from app.challenge_finals_v1 where challenge_id=(select id from beta_ids where name='six')),'100','exit refunded');
select is((select result->'participants'->pg_temp.ba(1)::text->>'returned_cents' from app.challenge_finals_v1 where challenge_id=(select id from beta_ids where name='six')),'125','four qualifiers split one miss');
-- Pure allocation covers missing, all miss and integer remainders without DB fixtures.
create function pg_temp.people(qualifiers integer,misses integer,unknowns integer) returns jsonb language sql as $$
 select jsonb_agg(jsonb_build_object('actor_id',pg_temp.ba(n),'target',100,'value',case when n<=qualifiers then 100 else 0 end,'state',case when n<=qualifiers+misses then 'complete' else 'unresolved' end,'excluded',false)) from generate_series(1,qualifiers+misses+unknowns) n
$$;
select is(app.challenge_evaluate_steps_v1(pg_temp.people(3,1,0),100)->>'unallocated_cents','1','integer remainder unallocated');
select is(app.challenge_evaluate_steps_v1(pg_temp.people(0,6,0),100)->>'unallocated_cents','600','all miss unallocated');
select is(app.challenge_evaluate_steps_v1(pg_temp.people(1,0,1),100)->>'outcome','void','fewer than two known void');
select is(app.challenge_evaluate_steps_v1(pg_temp.people(1,1,1),100)->'participants'->pg_temp.ba(3)::text->>'returned_cents','100','unknown refunded with two resolvable');
select is(app.challenge_evaluate_steps_v1(pg_temp.people(1,1,1),100)->'participants'->pg_temp.ba(1)::text->>'returned_cents','200','unknown does not enlarge active pool');
select ok((select bool_and((result->>'entry_cents')::integer=(result->>'unallocated_cents')::integer+(select sum((value->>'returned_cents')::integer) from jsonb_each(result->'participants'))) from app.challenge_finals_v1),'simulation conserves every cent');
select * from finish();
rollback;
