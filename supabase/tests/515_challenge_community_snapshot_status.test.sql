begin;
select no_plan();
\ir fixtures/challenge-fixture.inc

select ok(not has_function_privilege('anon','public.challenge_community_snapshot_status_v1(uuid)','execute'),'anon has no status grant');
select ok(not has_function_privilege('authenticated','public.challenge_community_snapshot_status_v1(uuid)','execute'),'authenticated has no status grant');
select ok(has_function_privilege('service_role','public.challenge_community_snapshot_status_v1(uuid)','execute'),'service has status grant');
select ok((select prosecdef and provolatile='s' and proconfig=array['search_path=""'] from pg_proc where oid='public.challenge_community_snapshot_status_v1(uuid)'::regprocedure),'stable definer with fixed empty path');
select throws_ok($$select public.challenge_community_snapshot_status_v1(null)$$,'22023','challenge_snapshot_selection_required','explicit selection required');
select is(public.challenge_community_snapshot_status_v1(pg_temp.br(80000))->>'capture_state','cohort_unavailable','unknown selection is unavailable');
insert into beta_ids values('friend',pg_temp.beta_group(30,2));
select is(public.challenge_community_snapshot_status_v1((select id from beta_ids where name='friend'))->>'capture_state','cohort_unavailable','unpublished friend is unavailable');
insert into beta_ids values('community',public.challenge_publish_community_fixture_v1(pg_temp.br(80100),pg_temp.ba(40),'{"start_date":"2026-10-03","days":1,"timezone":"UTC","amount_cents":100}',100,2,250,true));
create function pg_temp.community() returns uuid language sql as $$select id from beta_ids where name='community'$$;
create function pg_temp.status() returns jsonb language sql as $$select public.challenge_community_snapshot_status_v1(pg_temp.community())$$;
select is(pg_temp.status()->>'capture_state','discovery_disabled','publication alone does not authorize capture');
select public.challenge_discovery_fixture_v1(true);
-- These joins are fictional supported operations; the monitor never reads them.
do $$declare n integer;begin
 for n in 1..4 loop
  perform pg_temp.login_beta(n);
  perform public.challenge_join_community_v1(pg_temp.br(80700+n),jsonb_build_object('op','join_community','id',pg_temp.community(),'digest',public.challenge_community_catalog_v1()->0->>'digest','consent',true));
 end loop;perform set_config('role','none',true);
end$$;
savepoint wall_capture;
select public.challenge_runtime_v1(false,true,false,'{}',null);
select public.challenge_capture_community_snapshot_v1(pg_temp.community());
select is(pg_temp.status()->>'reference_clock','wall','actual wall-reference capture explicitly labeled');
select is(pg_temp.status()->>'snapshot_state','recorded','wall capture is recorded');
select is(pg_temp.status()->>'capture_age_seconds','0','wall-reference capture age starts at zero');
rollback to wall_capture;
select is(pg_temp.status()->>'snapshot_state','missing','no capture is missing');
select is(pg_temp.status()->>'capture_age_seconds',null::text,'missing capture has no age');
select is(pg_temp.status()->>'last_attempt_state','none','no invocation is not a success');
select is(pg_temp.status()->>'reference_clock','fixture','fixture reference is explicit');
select ok((pg_temp.status()->>'observed_wall_at')::timestamptz <> (pg_temp.status()->>'snapshot_reference_at')::timestamptz,'wall observation differs from fixture reference');

savepoint missing_failure;
select public.challenge_discovery_fixture_v1(false);
select public.challenge_prepare_community_snapshot_invocation_v1(pg_temp.br(80199),pg_temp.community());
select public.challenge_dispatch_community_snapshot_invocation_v1(pg_temp.br(80199));
select is(pg_temp.status()->>'snapshot_state','missing','failed first dispatch does not manufacture a capture');
select is(pg_temp.status()->>'last_attempt_state','failed','missing capture can coexist with a failed attempt');
select is(pg_temp.status()->>'last_successful_invocation_wall_at',null::text,'failed first dispatch has no successful invocation');
rollback to missing_failure;

select public.challenge_prepare_community_snapshot_invocation_v1(pg_temp.br(80200),pg_temp.community());
select ok(pg_temp.status()->>'last_prepared_wall_at' is not null and pg_temp.status()->>'last_attempt_wall_at' is null,'prepare is not a dispatch attempt');
select public.challenge_dispatch_community_snapshot_invocation_v1(pg_temp.br(80200));
select is(pg_temp.status()->>'snapshot_state','recorded','first capture exists even below five');
select is((pg_temp.status()->>'last_capture_at')::timestamptz,'2026-10-01T12:00Z'::timestamptz,'actual first capture timestamp');
select is(pg_temp.status()->>'capture_age_seconds','0','first capture age is zero in fixture clock');
select is(pg_temp.status()->>'last_attempt_state','checked','successful invocation is only checked');
select ok((select joined is null from app.challenge_community_snapshots_v1 where challenge_id=pg_temp.community()),'under-five capture retains no count');

create temp table before_replay as select pg_temp.status() value;
select pg_temp.login_beta(5);
select public.challenge_join_community_v1(pg_temp.br(80705),jsonb_build_object('op','join_community','id',pg_temp.community(),'digest',public.challenge_community_catalog_v1()->0->>'digest','consent',true));
reset role;
select is(pg_temp.status()-'observed_wall_at',(select value-'observed_wall_at' from before_replay),'fifth join cannot change any monitoring field');

select pg_temp.clock_beta('2026-10-01T14:00Z');
select public.challenge_dispatch_community_snapshot_invocation_v1(pg_temp.br(80200));
select is(pg_temp.status()->>'capture_age_seconds','7200','old replay does not refresh stale capture');
select is(pg_temp.status()->'last_attempt_wall_at',(select value->'last_attempt_wall_at' from before_replay),'replay does not move attempt wall time');
select is(pg_temp.status()->'last_successful_invocation_wall_at',(select value->'last_successful_invocation_wall_at' from before_replay),'replay does not move success wall time');

-- A fresh invocation inside the existing capture throttle succeeds without capture.
select pg_temp.clock_beta('2026-10-01T12:14:59Z');
select public.challenge_prepare_community_snapshot_invocation_v1(pg_temp.br(80201),pg_temp.community());
select public.challenge_dispatch_community_snapshot_invocation_v1(pg_temp.br(80201));
select is(pg_temp.status()->>'capture_age_seconds','899','throttled invocation leaves original capture age');
select ok((pg_temp.status()->>'last_attempt_wall_at')::timestamptz>(select (value->>'last_attempt_wall_at')::timestamptz from before_replay),'throttle records a later wall attempt');
select is((select count(*) from app.challenge_community_snapshots_v1 where challenge_id=pg_temp.community()),1::bigint,'throttle inserts no snapshot');
select pg_temp.clock_beta('2026-10-01T12:15Z',false,false);
select is(pg_temp.status()->>'capture_state','enabled','admission and processing pauses do not disable capture');
select public.challenge_prepare_community_snapshot_invocation_v1(pg_temp.br(80202),pg_temp.community());
select public.challenge_dispatch_community_snapshot_invocation_v1(pg_temp.br(80202));
select is((pg_temp.status()->>'last_capture_at')::timestamptz,'2026-10-01T12:15Z'::timestamptz,'capture works at throttle boundary with processing off');

-- Preserve a closed published cohort's observations when a newer cohort exists.
savepoint selected_scope;
select pg_temp.clock_beta('2026-10-01T14:00Z');
create temp table before_other_cohort as select pg_temp.status() value;
select public.challenge_grant_operator_v1(pg_temp.ba(39),pg_temp.community(),'moderate','2026-10-02T00:00Z');
select pg_temp.login_beta(39);
select public.challenge_operator_close_v1(pg_temp.br(80800),pg_temp.community());
reset role;
insert into beta_ids values('other_community',public.challenge_publish_community_fixture_v1(pg_temp.br(80801),pg_temp.ba(40),'{"start_date":"2026-10-03","days":1,"timezone":"UTC","amount_cents":100}',100,2,250,true));
select public.challenge_prepare_community_snapshot_invocation_v1(pg_temp.br(80802),(select id from beta_ids where name='other_community'));
select public.challenge_dispatch_community_snapshot_invocation_v1(pg_temp.br(80802));
select is(pg_temp.status()-'observed_wall_at',(select value-'observed_wall_at' from before_other_cohort),'newer published cohort cannot refresh selected capture or invocation');
rollback to selected_scope;

create function pg_temp.fail_capture() returns trigger language plpgsql as $$begin raise exception 'private raw Health and identity detail' using errcode='23514'; end$$;
create trigger test_snapshot_failure before insert on app.challenge_community_snapshots_v1 for each row execute function pg_temp.fail_capture();
select pg_temp.clock_beta('2026-10-01T14:00Z');
create temp table before_failure as select pg_temp.status() value;
select public.challenge_prepare_community_snapshot_invocation_v1(pg_temp.br(80203),pg_temp.community());
select public.challenge_dispatch_community_snapshot_invocation_v1(pg_temp.br(80203));
select is(pg_temp.status()->>'last_attempt_state','failed','capture exception reports failed attempt');
select is(pg_temp.status()->>'last_attempt_error_code','23514','failure exposes only SQLSTATE');
select is(pg_temp.status()->>'capture_age_seconds','6300','failure keeps old capture age');
select is(pg_temp.status()->'last_successful_invocation_wall_at',(select value->'last_successful_invocation_wall_at' from before_failure),'failure does not advance successful invocation');
drop trigger test_snapshot_failure on app.challenge_community_snapshots_v1;
select public.challenge_prepare_community_snapshot_invocation_v1(pg_temp.br(80204),pg_temp.community());
select is(pg_temp.status()->>'last_attempt_state','failed','new prepared invocation does not hide preceding failure');
select public.challenge_discovery_fixture_v1(false);
select is(pg_temp.status()->>'capture_state','discovery_disabled','discovery off is accurately disabled');
select public.challenge_dispatch_community_snapshot_invocation_v1(pg_temp.br(80204));
select is(pg_temp.status()->>'last_attempt_error_code','42501','disabled dispatch records bounded authorization error');
select pg_temp.clock_beta('2026-10-01T11:00Z');
select is(pg_temp.status()->>'snapshot_state','clock_ahead','backward fixture clock never makes an old capture fresh');
select is(pg_temp.status()->>'capture_age_seconds',null::text,'clock ahead never clamps to a fresh zero');
select public.challenge_runtime_v1(false,false,false,'{}',null);
select is(pg_temp.status()->>'capture_state','fixtures_disabled','fixtures off is accurately disabled');
select is(pg_temp.status()->>'reference_clock','wall','reference clock follows current runtime, not historical capture origin');
select is(pg_temp.status()->'snapshot_reference_at',pg_temp.status()->'observed_wall_at','wall reference uses the actual observation, not the fixture timestamp');

savepoint runtime_present;
select set_config('app.challenge_write_v1','on',true);
-- Fault injection only, rolled back with this savepoint.
alter table app.challenge_runtime_v1 disable trigger challenge_guard;
delete from app.challenge_runtime_v1;
alter table app.challenge_runtime_v1 enable trigger challenge_guard;
select is(pg_temp.status()->>'capture_state','runtime_unavailable','missing runtime is unavailable');
select is(pg_temp.status()->>'reference_clock','unavailable','missing runtime has no clock');
select is(pg_temp.status()->>'snapshot_state','clock_unavailable','retained capture lacks an age reference');
select is(pg_temp.status()->>'capture_age_seconds',null::text,'missing runtime has no age');
select is(pg_temp.status()->'last_capture_at',(select value->'last_capture_at' from before_failure),'missing runtime preserves last capture observation');
rollback to runtime_present;

-- Exact output allowlist, including under-five: no identities, raw receipts,
-- member counts, Health values or participant/disclosure state is projected.
select is((select array_agg(k order by k) from jsonb_object_keys(pg_temp.status()) k),
 array['capture_age_seconds','capture_state','last_attempt_error_code','last_attempt_state','last_attempt_wall_at','last_capture_at','last_prepared_wall_at','last_successful_invocation_wall_at','observed_wall_at','reference_clock','snapshot_reference_at','snapshot_state'], 'only bounded states, clocks and timestamps leave the service projection');
set local role anon;
select throws_ok($$select public.challenge_community_snapshot_status_v1(null)$$,'42501',null,'actual anonymous call denied before selection');
reset role;
select pg_temp.login_beta(1);
select throws_ok($$select public.challenge_community_snapshot_status_v1(pg_temp.community())$$,'42501',null,'actual participant call denied');
reset role;
-- Defense in depth even if the execute grant regresses.
grant execute on function public.challenge_community_snapshot_status_v1(uuid) to authenticated;
select pg_temp.login_beta(1);
select throws_ok($$select public.challenge_community_snapshot_status_v1(pg_temp.community())$$,'42501','duel_service_required','service guard survives accidental execute grant');
reset role;
revoke execute on function public.challenge_community_snapshot_status_v1(uuid) from authenticated;
grant select on beta_ids to service_role;
set local role service_role;
select lives_ok($$select public.challenge_community_snapshot_status_v1(pg_temp.community())$$,'actual service role can read');
reset role;

-- Hash every existing challenge table, including snapshots, runtime, journals,
-- agreements, disclosure projections, worker/audit records and request receipts.
create function pg_temp.challenge_digest() returns jsonb language plpgsql as $$
declare t record; digest text; result jsonb:='{}';begin
 for t in select tablename from pg_tables where schemaname='app' and tablename like 'challenge\_%' escape '\' order by tablename loop
  execute format('select md5(coalesce(string_agg(row_to_json(r)::text,'''' order by row_to_json(r)::text),'''')) from app.%I r',t.tablename) into digest;
  result:=result||jsonb_build_object(t.tablename,digest);
 end loop;
 return result;
end$$;
create temp table before_reads as select pg_temp.challenge_digest() value;
select set_config('app.challenge_write_v1','off',true);
select pg_temp.status() from generate_series(1,3);
select is(current_setting('app.challenge_write_v1'),'off','read never enables write guard');
select is(pg_temp.challenge_digest(),(select value from before_reads),'repeated reads leave all challenge table contents unchanged');
select * from finish();
rollback;
