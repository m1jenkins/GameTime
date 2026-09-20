begin;
select no_plan();

select is((select count(*) from cron.job where jobname in ('challenge-worker-v1','challenge-snapshot-v1','challenge-monitor-v1') and not active),3::bigint,'all new schedules are inactive on a fresh migration');
select ok((select not worker_enabled and not snapshot_enabled and not monitor_enabled and edge_base_url is null and community_id is null and worker_secret_id is null and monitor_secret_id is null from app.challenge_schedule_config_v1),'private configuration has no defaults that operate or select a cohort');
select is(public.challenge_machine_monitor_v1()->>'state','unconfigured','missing configuration is explicit');
select lives_ok($$select app.challenge_cron_tick_v1('worker')$$,'unconfigured tick does no work');
select is((select count(*) from app.challenge_machine_runs_v1),0::bigint,'unconfigured tick saves no invocation');
select ok(not has_function_privilege('service_role','app.challenge_cron_tick_v1(text)','execute'),'Edge cannot queue, prepare or configure a schedule');
select ok(not has_function_privilege('anon','public.challenge_machine_monitor_v1()','execute'),'public key cannot monitor');
select ok(not has_function_privilege('authenticated','public.challenge_machine_worker_dispatch_v1(uuid,uuid)','execute'),'user cannot dispatch work');
select ok(not has_function_privilege('authenticated','public.challenge_machine_snapshot_dispatch_v1(uuid)','execute'),'user cannot capture snapshots');
select ok(not has_function_privilege('authenticated','public.challenge_machine_complete_v1(uuid,uuid,uuid,uuid)','execute'),'user cannot complete work');
select ok(not has_function_privilege('authenticated','public.challenge_machine_finish_v1(uuid,uuid)','execute'),'user cannot finish an invocation');
select ok((select bool_and(relrowsecurity) from pg_class where oid in ('app.challenge_schedule_config_v1'::regclass,'app.challenge_schedule_ticks_v1'::regclass,'app.challenge_machine_runs_v1'::regclass)),'private scheduler records also have RLS');
select ok(not has_table_privilege('service_role','app.challenge_schedule_config_v1','select,insert,update,delete'),'service key has no direct scheduler configuration access');
select ok(not has_table_privilege('service_role','app.challenge_machine_runs_v1','select,insert,update,delete'),'service key cannot edit durable machine runs directly');

-- Only rollback-owned fixture rows and dummy credentials. Nothing in this test
-- commits, so pg_net never sends an HTTP request or installs a real secret.
\ir fixtures/challenge-fixture.inc
insert into beta_ids values('first',pg_temp.beta_group(1,2));
insert into beta_ids values('second',pg_temp.beta_group(3,2));
select pg_temp.clock_beta('2026-10-20T12:00Z');
update app.challenge_schedule_config_v1 set edge_base_url='http://127.0.0.1:65534/functions/v1',
 worker_secret_id=vault.create_secret(repeat('w',32),'p11-test-worker'),
 monitor_secret_id=vault.create_secret(repeat('m',32),'p11-test-monitor'),
 worker_enabled=true,monitor_enabled=true;

select app.challenge_cron_tick_v1('worker');
select is((select count(*) from app.challenge_machine_runs_v1),1::bigint,'one durable invocation precedes HTTP dispatch');
select is((select limit_count from app.challenge_worker_invocations_v1 where id=(select invocation_id from app.challenge_machine_runs_v1)),20,'server prepares fixed batch 20');
select is((select scope from app.challenge_worker_invocations_v1 where id=(select invocation_id from app.challenge_machine_runs_v1)),'{"version":"challenge_worker_scope_v1","kind":"due"}'::jsonb,'request cannot pick scope');
select is((select convert_from(body,'UTF8')::jsonb from net.http_request_queue where id=(select last_request_id from app.challenge_schedule_ticks_v1 where kind='worker')),jsonb_build_object('invocation_id',(select invocation_id from app.challenge_machine_runs_v1)),'HTTP carries only durable invocation identity');
select app.challenge_cron_tick_v1('worker');
select is((select queued_count from app.challenge_schedule_ticks_v1 where kind='worker'),1::bigint,'duplicate tick does not overlap or queue twice');
delete from net.http_request_queue where id=(select last_request_id from app.challenge_schedule_ticks_v1 where kind='worker');
update app.challenge_schedule_ticks_v1 set last_queued_at=clock_timestamp()-interval '61 seconds' where kind='worker';
select app.challenge_cron_tick_v1('worker');
select is((select count(*) from app.challenge_machine_runs_v1),1::bigint,'lost unlogged queue entry reuses durable prepared invocation');
select is((select queue_attempts from app.challenge_machine_runs_v1),2,'queue recovery is recorded separately from claim attempts');
create temp table dispatch(value jsonb);
insert into dispatch select public.challenge_machine_worker_dispatch_v1((select invocation_id from app.challenge_machine_runs_v1),pg_temp.br(95001));
select is((select value->>'status' from dispatch),'running','server-prepared invocation dispatches');
select is(jsonb_array_length((select value->'claims' from dispatch)),2,'fixed due scope claims eligible work');
select is(public.challenge_machine_worker_dispatch_v1((select invocation_id from app.challenge_machine_runs_v1),pg_temp.br(95002))->>'status','busy','overlapping request cannot acquire a live run');
select is(public.challenge_machine_worker_dispatch_v1((select invocation_id from app.challenge_machine_runs_v1),pg_temp.br(95001))->'claims',(select value->'claims' from dispatch),'lost dispatch response replays exact saved claims');
select is((select dispatch_attempts from app.challenge_worker_invocations_v1 where id=(select invocation_id from app.challenge_machine_runs_v1)),1,'duplicate dispatch does not claim twice');
select throws_ok($$select public.challenge_machine_complete_v1((select invocation_id from app.challenge_machine_runs_v1),pg_temp.br(95001),pg_temp.br(99998),pg_temp.br(99999))$$,'42501','challenge_unselected_claim','even server adapter cannot substitute another claim');
create temp table completion(value jsonb);
insert into completion select public.challenge_machine_complete_v1((select invocation_id from app.challenge_machine_runs_v1),pg_temp.br(95001),
 ((select value->'claims'->0->>'id' from dispatch)::uuid),((select value->'claims'->0->>'claim_token' from dispatch)::uuid));
select is(public.challenge_machine_complete_v1((select invocation_id from app.challenge_machine_runs_v1),pg_temp.br(95001),
 ((select value->'claims'->0->>'id' from dispatch)::uuid),((select value->'claims'->0->>'claim_token' from dispatch)::uuid)),
 (select value from completion),'lost completion response recovers exact original receipt');
select is(public.challenge_machine_finish_v1((select invocation_id from app.challenge_machine_runs_v1),pg_temp.br(95001))->>'status','pending','unfinished claims remain resumable');
update app.challenge_machine_runs_v1 set lease_expires_at=clock_timestamp()-interval '1 second';
select is(public.challenge_machine_worker_dispatch_v1((select invocation_id from app.challenge_machine_runs_v1),pg_temp.br(95002))->'claims',(select value->'claims' from dispatch),'process restart resumes saved claims under a fresh run fence');
select throws_ok($$select public.challenge_machine_complete_v1((select invocation_id from app.challenge_machine_runs_v1),pg_temp.br(95001),((select value->'claims'->1->>'id' from dispatch)::uuid),((select value->'claims'->1->>'claim_token' from dispatch)::uuid))$$,'55000','challenge_stale_machine_run','stale process cannot complete after takeover');
select public.challenge_machine_complete_v1((select invocation_id from app.challenge_machine_runs_v1),pg_temp.br(95002),
 ((select value->'claims'->1->>'id' from dispatch)::uuid),((select value->'claims'->1->>'claim_token' from dispatch)::uuid));
create temp table final_result(value jsonb);
insert into final_result select public.challenge_machine_finish_v1((select invocation_id from app.challenge_machine_runs_v1),pg_temp.br(95002));
select is((select value->>'status' from final_result),'completed','both separate item transactions are accounted for');
select is((select value->>'completed_count' from final_result),'2','summary counts receipts');
select is(public.challenge_machine_finish_v1((select invocation_id from app.challenge_machine_runs_v1),pg_temp.br(95002)),(select value from final_result),'lost finish response returns saved summary');
select is(public.challenge_machine_worker_dispatch_v1((select invocation_id from app.challenge_machine_runs_v1),pg_temp.br(95003))->'result',(select value from final_result),'duplicate completed HTTP request returns saved aggregate result');
select ok(not ((select value from final_result)::text ~ '(claim_token|invocation_id|challenge_id|bf000000|ba000000)'),'machine summary contains no identifiers or tokens');

-- Monitor reads are read-only and preserve paused, disabled and unavailable.
create temp table monitor_before as select (select count(*) from app.challenge_worker_audit_v1) audits,(select count(*) from app.challenge_worker_heartbeats_v1) heartbeats;
select public.challenge_machine_monitor_v1();
select is(public.challenge_machine_monitor_v1()->>'state','disabled','inactive monitor Cron job is not reported as healthy');
select is((select count(*) from app.challenge_worker_audit_v1),(select audits from monitor_before),'monitor adds no audit writes');
select is((select count(*) from app.challenge_worker_heartbeats_v1),(select heartbeats from monitor_before),'monitor cannot manufacture a heartbeat');
update app.challenge_schedule_config_v1 set worker_enabled=false;
select is(public.challenge_machine_monitor_v1()->'worker'->>'processing_state','disabled','disabled worker schedule never reports healthy empty');
update app.challenge_schedule_config_v1 set worker_enabled=true;
select pg_temp.clock_beta('2026-10-20T12:00Z',false,false);
select is(app.challenge_machine_processing_state_v1(),'paused','processing pause is distinct from an empty queue');
select ok(public.challenge_machine_monitor_v1()::text !~ '(actor_id|challenge_id|invocation_id|claim_token|joined|participant|payload|betafixture)','monitor contains no people counts, payloads or identities');
select is(public.challenge_machine_monitor_v1()->'snapshot'->>'capture_state','unconfigured','no cohort is inferred from recency');

-- Snapshot authorization and privacy reuse the existing capture boundary.
select pg_temp.clock_beta('2026-10-01T12:00Z',true,true);
insert into beta_ids values('cohort',public.challenge_publish_community_fixture_v1(pg_temp.br(95300),pg_temp.ba(40),'{"start_date":"2026-10-03","days":1,"timezone":"UTC","amount_cents":100}',100,2,250,true));
select public.challenge_discovery_fixture_v1(true);
update app.challenge_schedule_config_v1 set community_id=(select id from beta_ids where name='cohort'),snapshot_enabled=true;
select app.challenge_cron_tick_v1('snapshot');
select is((select count(*) from app.challenge_machine_runs_v1 where kind='snapshot'),1::bigint,'only the configured cohort gets a prepared snapshot');
create temp table snapshot_result(value jsonb);
insert into snapshot_result select public.challenge_machine_snapshot_dispatch_v1((select invocation_id from app.challenge_machine_runs_v1 where kind='snapshot'));
select is((select value->>'status' from snapshot_result),'checked','snapshot invocation succeeded');
select ok((select value->>'last_capture_at' is not null from snapshot_result),'successful capture timestamp is separately reported');
select is(public.challenge_machine_snapshot_dispatch_v1((select invocation_id from app.challenge_machine_runs_v1 where kind='snapshot')),(select value from snapshot_result),'snapshot response loss recovers exact saved result');
select is((select count(*) from app.challenge_community_snapshots_v1 where challenge_id=(select id from beta_ids where name='cohort')),1::bigint,'snapshot retry does not capture twice');
select is((select joined from app.challenge_community_snapshots_v1 where challenge_id=(select id from beta_ids where name='cohort')),null::integer,'below five remains private');
update app.challenge_schedule_ticks_v1 set last_queued_at=clock_timestamp()-interval '901 seconds' where kind='snapshot';
select app.challenge_cron_tick_v1('snapshot');
select public.challenge_machine_snapshot_dispatch_v1((select invocation_id from app.challenge_machine_runs_v1 where kind='snapshot' and state='pending'));
select is((select count(*) from app.challenge_community_snapshots_v1 where challenge_id=(select id from beta_ids where name='cohort')),1::bigint,'a later successful invocation does not imply a fresh capture');
update app.challenge_schedule_config_v1 set community_id=(select id from beta_ids where name='first');
select is(public.challenge_machine_snapshot_dispatch_v1((select invocation_id from app.challenge_machine_runs_v1 where kind='snapshot' order by prepared_at limit 1))->>'status','unavailable','cohort switch fences even saved snapshot results');
select is(public.challenge_machine_snapshot_dispatch_v1(pg_temp.br(95600))->>'status','unavailable','caller cannot invent a snapshot invocation');
select is(public.challenge_machine_worker_dispatch_v1(pg_temp.br(95600),pg_temp.br(95601))->>'status','unavailable','caller cannot create a worker invocation');

-- A selection change before dispatch must free the unique unfinished snapshot
-- slot. The public fixture API intentionally permits just one community, so
-- create this rollback-owned second publication directly as in the real-source
-- snapshot fixture; no product publication setting is changed.
insert into beta_ids values('other_cohort','be000000-0000-0000-0000-000000095301');
select set_config('app.challenge_write_v1','on',true);
insert into app.challenge_lobbies_v1
 (id,creator_id,policy,config,starts_at,ends_at,status,revision,agreement_version,created_at,minimum,capacity)
values((select id from beta_ids where name='other_cohort'),pg_temp.ba(39),'community_steps_goal_v1',
 '{"amount_cents":100}'::jsonb,'2026-10-03T00:00Z','2026-10-04T00:00Z','published_open',1,1,
 '2026-10-01T12:00Z',2,6);
insert into app.challenge_community_publications_v1
values((select id from beta_ids where name='other_cohort'),pg_temp.ba(39),'operator','2026-10-01T12:00Z');
insert into app.challenge_members_v1(challenge_id,actor_id,selected,target)
values((select id from beta_ids where name='other_cohort'),pg_temp.ba(39),true,100),
 ((select id from beta_ids where name='other_cohort'),pg_temp.ba(38),true,100);
update app.challenge_schedule_config_v1 set community_id=(select id from beta_ids where name='cohort');
update app.challenge_schedule_ticks_v1 set last_queued_at=clock_timestamp()-interval '901 seconds' where kind='snapshot';
select app.challenge_cron_tick_v1('snapshot');
create temp table old_pending_snapshot as
 select invocation_id from app.challenge_machine_runs_v1 where kind='snapshot' and state='pending';
select is((select challenge_id from app.challenge_snapshot_invocations_v1 where id=(select invocation_id from old_pending_snapshot)),
 (select id from beta_ids where name='cohort'),'old selected cohort had a durable prepared invocation');
update app.challenge_schedule_config_v1 set community_id=(select id from beta_ids where name='other_cohort');
update app.challenge_schedule_ticks_v1 set last_queued_at=clock_timestamp()-interval '901 seconds' where kind='snapshot';
select app.challenge_cron_tick_v1('snapshot');
select is((select state from app.challenge_machine_runs_v1 where invocation_id=(select invocation_id from old_pending_snapshot)),
 'finished','cohort switch retires the old pending machine run');
select is((select result->>'error_category' from app.challenge_machine_runs_v1 where invocation_id=(select invocation_id from old_pending_snapshot)),
 'selection_changed','retired snapshot records a bounded, identifier-free category');
select is((select challenge_id from app.challenge_snapshot_invocations_v1 where id=(select invocation_id from app.challenge_machine_runs_v1 where kind='snapshot' and state='pending')),
 (select id from beta_ids where name='other_cohort'),'same tick prepares the new selected cohort');
select is(public.challenge_machine_snapshot_dispatch_v1((select invocation_id from old_pending_snapshot))->>'status',
 'unavailable','old pending invocation remains fenced after the selection change');
create temp table other_pending_snapshot as
 select invocation_id from app.challenge_machine_runs_v1 where kind='snapshot' and state='pending';
update app.challenge_schedule_config_v1 set community_id=(select id from beta_ids where name='cohort');
update app.challenge_schedule_ticks_v1 set last_queued_at=clock_timestamp()-interval '901 seconds' where kind='snapshot';
select app.challenge_cron_tick_v1('snapshot');
select is((select state from app.challenge_machine_runs_v1 where invocation_id=(select invocation_id from other_pending_snapshot)),
 'finished','switching back retires the other pending snapshot');
select is((select invocation_id from app.challenge_machine_runs_v1 where kind='snapshot' and state='pending'),
 (select invocation_id from old_pending_snapshot),'switch-back reactivates the exact original prepared invocation');
select is((select count(*) from app.challenge_machine_runs_v1 where invocation_id=(select invocation_id from old_pending_snapshot)),
 1::bigint,'reactivation does not create a duplicate machine record');
select is(public.challenge_machine_snapshot_dispatch_v1((select invocation_id from old_pending_snapshot))->>'status',
 'checked','reactivated selected invocation can dispatch once');
select is(public.challenge_machine_snapshot_dispatch_v1((select invocation_id from old_pending_snapshot)),
 (select result from app.challenge_machine_runs_v1 where invocation_id=(select invocation_id from old_pending_snapshot)),
 'checked snapshot response replays exactly after switch-back');
update app.challenge_schedule_config_v1 set community_id=(select id from beta_ids where name='other_cohort');
update app.challenge_schedule_ticks_v1 set last_queued_at=clock_timestamp()-interval '901 seconds' where kind='snapshot';
select app.challenge_cron_tick_v1('snapshot');
select is((select invocation_id from app.challenge_machine_runs_v1 where kind='snapshot' and state='pending'),
 (select invocation_id from other_pending_snapshot),'other prepared cohort reactivates its exact invocation');
select is(public.challenge_machine_snapshot_dispatch_v1((select invocation_id from other_pending_snapshot))->>'status',
 'checked','new selected cohort can capture after both switches');
select is((select count(*) from app.challenge_community_snapshots_v1 where challenge_id=(select id from beta_ids where name='other_cohort')),
 1::bigint,'new cohort alone receives its first capture');
select is((select count(*) from app.challenge_community_snapshots_v1 where challenge_id=(select id from beta_ids where name='cohort')),
 1::bigint,'undispatched old cohort invocation creates no extra capture');

select * from finish();
rollback;
