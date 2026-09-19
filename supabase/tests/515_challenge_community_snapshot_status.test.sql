begin;
select no_plan();
\ir fixtures/challenge-fixture.inc

select ok(not has_function_privilege('anon','public.challenge_community_snapshot_status_v1(uuid)','execute'),'anonymous cannot read snapshot status');
select ok(not has_function_privilege('authenticated','public.challenge_community_snapshot_status_v1(uuid)','execute'),'participants cannot read snapshot status');
select ok(has_function_privilege('service_role','public.challenge_community_snapshot_status_v1(uuid)','execute'),'service can read snapshot status');
select ok((select prosecdef and provolatile='s' and proconfig=array['search_path=""'] from pg_proc where oid='public.challenge_community_snapshot_status_v1(uuid)'::regprocedure),'projection is stable with a fixed definer path');
select throws_ok($$select public.challenge_community_snapshot_status_v1(null)$$,'22023','challenge_invalid_snapshot','selection is required');
select throws_ok($$select public.challenge_community_snapshot_status_v1(pg_temp.br(99999))$$,'42501','challenge_snapshot_unavailable','unknown selection is unavailable');
insert into beta_ids values('friend',pg_temp.beta_group(6,2));
select throws_ok($$select public.challenge_community_snapshot_status_v1((select id from beta_ids where name='friend'))$$,'42501','challenge_snapshot_unavailable','unpublished friend challenge cannot be selected');
insert into beta_ids values('community',public.challenge_publish_community_fixture_v1(pg_temp.br(92000),pg_temp.ba(40),'{"start_date":"2026-10-03","days":1,"timezone":"UTC","amount_cents":100}',100,2,250,true));
select public.challenge_discovery_fixture_v1(true);
create function pg_temp.community() returns uuid language sql as $$select id from beta_ids where name='community'$$;

-- Fingerprint every existing application/Auth row and sequence. Read failures
-- or side effects fail the test without printing the underlying private rows.
\ir fixtures/community-status-digest.inc
create function pg_temp.observe() returns jsonb language plpgsql as $$
declare before_read text:=pg_temp.data_digest(); response jsonb; begin
 response:=public.challenge_community_snapshot_status_v1(pg_temp.community());
 if before_read<>pg_temp.data_digest() then raise exception 'status changed existing rows or sequences'; end if;
 if (select array_agg(k order by k) from jsonb_object_keys(response) k) <> array[
  'capture_age_seconds','capture_authorization','capture_status','last_attempt_at','last_attempt_error_code',
  'last_attempt_status','last_capture_at','last_successful_invocation_at','pending_invocation_prepared_at',
  'server_time','snapshot_age_clock','snapshot_clock_now'] then raise exception 'unexpected status fields'; end if;
 return response;
end $$;
select is(pg_temp.observe()->>'capture_status','missing','no capture is missing, never fresh');
select is(pg_temp.observe()->>'capture_age_seconds',null::text,'missing capture has no age');
select is(pg_temp.observe()->>'last_attempt_status','none','no dispatch attempt is distinct from capture absence');
select is(pg_temp.observe()->>'snapshot_age_clock','fixture','fixture age is explicitly labeled');
select isnt(pg_temp.observe()->>'server_time',pg_temp.observe()->>'snapshot_clock_now','wall and fixture timestamps remain distinct');
select public.challenge_prepare_community_snapshot_invocation_v1(pg_temp.br(92001),pg_temp.community());
select ok(pg_temp.observe()->>'pending_invocation_prepared_at' is not null,'prepared work remains visible');
select is(pg_temp.observe()->>'last_attempt_at',null::text,'preparation is not a dispatch attempt');

-- Four real fixture joins exercise privacy below the disclosure threshold.
do $$declare i integer;begin
 for i in 1..4 loop
  perform pg_temp.login_beta(i);
  perform public.challenge_join_community_v1(pg_temp.br(92100+i),jsonb_build_object('op','join_community','id',pg_temp.community(),'digest',public.challenge_community_catalog_v1()->0->>'digest','consent',true));
 end loop;
 perform set_config('role','none',true);
end $$;
select public.challenge_dispatch_community_snapshot_invocation_v1(pg_temp.br(92001));
select is(pg_temp.observe()->>'capture_status','recorded','first actual capture is present');
select is(pg_temp.observe()->>'capture_age_seconds','0','first capture has zero fixture age');
select is(pg_temp.observe()->>'last_attempt_status','checked','successful dispatch is checked, not fresh');
select is(pg_temp.observe()->>'pending_invocation_prepared_at',null::text,'dispatched preparation is no longer pending');
select ok((select joined is null from app.challenge_community_snapshots_v1 where challenge_id=pg_temp.community()),'under-five capture stores no exact count');
select is(app.challenge_community_counts_v1(pg_temp.community()),'{"joined":null,"state":"threshold","as_of":null}'::jsonb,'under-five disclosure stays private');
create temp table first_status as select pg_temp.observe() value;
select pg_temp.clock_beta('2026-10-01T12:01Z');
select public.challenge_prepare_community_snapshot_invocation_v1(pg_temp.br(92002),pg_temp.community());
select public.challenge_dispatch_community_snapshot_invocation_v1(pg_temp.br(92002));
select is(pg_temp.observe()->>'last_capture_at',(select value->>'last_capture_at' from first_status),'throttled success cannot advance capture');
select is(pg_temp.observe()->>'capture_age_seconds','60','throttled capture keeps its actual age');
select ok((pg_temp.observe()->>'last_successful_invocation_at')::timestamptz>(select (value->>'last_successful_invocation_at')::timestamptz from first_status),'throttled invocation has its own later wall time');
create temp table throttled_status as select pg_temp.observe() value;
select pg_temp.clock_beta('2026-10-01T14:00Z');
select public.challenge_dispatch_community_snapshot_invocation_v1(pg_temp.br(92002));
select is(pg_temp.observe()->>'capture_age_seconds','7200','late replay leaves a two-hour-old capture old');
select is(pg_temp.observe()->>'last_attempt_at',(select value->>'last_attempt_at' from throttled_status),'replay is not a new durable attempt');
select is(pg_temp.observe()->>'last_successful_invocation_at',(select value->>'last_successful_invocation_at' from throttled_status),'replay cannot advance success timestamp');

-- Both processing and admission may be paused while capture remains authorized.
select pg_temp.clock_beta('2026-10-01T14:00Z',false,false);
select is(pg_temp.observe()->>'capture_authorization','enabled','worker/admission pause does not disable capture');
create function pg_temp.fail_snapshot() returns trigger language plpgsql as $$begin raise exception 'PRIVATE raw response and Health sentinel' using errcode='23514';end $$;
create trigger snapshot_test_failure before insert on app.challenge_community_snapshots_v1 for each row execute function pg_temp.fail_snapshot();
select public.challenge_prepare_community_snapshot_invocation_v1(pg_temp.br(92003),pg_temp.community());
select public.challenge_dispatch_community_snapshot_invocation_v1(pg_temp.br(92003));
select is(pg_temp.observe()->>'last_attempt_status','failed','failed capture is reported');
select is(pg_temp.observe()->>'last_attempt_error_code','23514','failure exposes only bounded SQLSTATE');
select is(pg_temp.observe()->>'capture_age_seconds','7200','failure does not advance capture');
select is(pg_temp.observe()->>'last_successful_invocation_at',(select value->>'last_successful_invocation_at' from throttled_status),'failure preserves separate prior success');
drop trigger snapshot_test_failure on app.challenge_community_snapshots_v1;
select public.challenge_discovery_fixture_v1(false);
select is(pg_temp.observe()->>'capture_authorization','discovery_disabled','disabled discovery is reported');
select public.challenge_prepare_community_snapshot_invocation_v1(pg_temp.br(92004),pg_temp.community());
select public.challenge_dispatch_community_snapshot_invocation_v1(pg_temp.br(92004));
select is(pg_temp.observe()->>'last_attempt_status','disabled','gate rejection is a disabled attempt');
select is(pg_temp.observe()->>'last_attempt_error_code','42501','gate rejection reports SQLSTATE only');
select public.challenge_runtime_v1(false,false,false,'{}',null);
select is(pg_temp.observe()->>'capture_authorization','fixtures_disabled','fixture shutdown is disabled even with history');
select is(pg_temp.observe()->>'snapshot_age_clock','server','current clock without fixture override is explicit');
select pg_temp.clock_beta('2026-10-01T11:59Z');
select is(pg_temp.observe()->>'capture_status','ahead_of_clock','capture ahead of a rewound fixture clock is not fresh');
select is(pg_temp.observe()->>'capture_age_seconds',null::text,'clock rewind never clamps a future capture to age zero');

-- A missing singleton is unavailable, not healthy/disabled via null logic.
-- Fault injection only in this rollback-only test; runtime deletion is guarded.
alter table app.challenge_runtime_v1 disable trigger challenge_guard;
delete from app.challenge_runtime_v1;
alter table app.challenge_runtime_v1 enable trigger challenge_guard;
select is(pg_temp.observe()->>'capture_authorization','runtime_unavailable','missing runtime is unavailable');
select is(pg_temp.observe()->>'capture_status','clock_unavailable','known capture survives missing runtime');
select is(pg_temp.observe()->>'snapshot_clock_now',null::text,'missing runtime cannot silently substitute wall time');
select is(pg_temp.observe()->>'capture_age_seconds',null::text,'missing runtime cannot compute age');
select is(pg_temp.observe()->>'last_capture_at',(select value->>'last_capture_at' from first_status),'shutdown preserves actual capture timestamp');
select ok(pg_temp.observe()::text !~ 'PRIVATE|joined|actor|challenge_id|Health|response|count','all tested reads have only timestamp/age/status fields');

grant select on beta_ids to service_role;
set local role service_role;
select is(public.challenge_community_snapshot_status_v1(pg_temp.community())->>'capture_authorization','runtime_unavailable','actual service role can read while unavailable');
reset role;
set local role anon;
select throws_ok($$select public.challenge_community_snapshot_status_v1(pg_temp.community())$$,'42501',null,'actual anonymous role is denied');
reset role;
select pg_temp.login_beta(1);
select throws_ok($$select public.challenge_community_snapshot_status_v1(pg_temp.community())$$,'42501',null,'actual participant is denied');
reset role;
select * from finish();
rollback;
