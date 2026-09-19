begin;
select no_plan();
\ir fixtures/challenge-fixture.inc

create function pg_temp.admin(o text,a uuid,c uuid default null,k text default null,e text default null)
returns jsonb language sql as $$
 select jsonb_build_object('version','challenge_admin_request_v2','operation',o,'actor_id',a)
  || case when c is null then '{}'::jsonb else jsonb_build_object('challenge_id',c,'capability',k) end
  || case when e is null then '{}'::jsonb else jsonb_build_object('expires_at',e) end
$$;
insert into beta_ids values('duel',pg_temp.beta_group(1,2));
-- Disposable unavailable actors: an accepted deletion tombstone and a suspension.
insert into app.challenge_account_deletions_v1
 (actor_id,request_id,receipt_hash,apple_subject_hash,accepted_at,required_steps_finished_at,identity_cleanup_after)
values (pg_temp.ba(37),pg_temp.br(51700),decode(repeat('a1',32),'hex'),decode(repeat('b1',32),'hex'),
 '2026-10-01T12:00Z','2026-10-01T12:00Z','2026-10-08T12:00Z');
select set_config('app.challenge_write_v1','on',true);
insert into app.challenge_suspensions_v1 values(pg_temp.ba(39),true,pg_temp.ba(40),'username',app.challenge_now_v1());
create temp table admin_baseline as
 select (select count(*) from app.challenge_admin_requests_v2) receipts,
        (select count(*) from app.challenge_operator_audit_v1) audit;

select ok(has_function_privilege('service_role','public.challenge_admin_request_v2(uuid,jsonb)','execute'),'service can invoke v2');
select ok(not has_function_privilege('authenticated','public.challenge_admin_request_v2(uuid,jsonb)','execute'),'human cannot invoke v2');
select ok(not has_function_privilege('anon','public.challenge_admin_request_v2(uuid,jsonb)','execute'),'anonymous cannot invoke v2');
select ok(not has_table_privilege('service_role','app.challenge_admin_requests_v2','select'),'service cannot read raw receipts');
select ok(not has_table_privilege('authenticated','app.challenge_admin_requests_v2','select'),'human cannot read raw receipts');
select ok(not has_table_privilege('anon','app.challenge_admin_requests_v2','select'),'anonymous cannot read raw receipts');
set local role authenticated;
select throws_ok($$select public.challenge_admin_request_v2('ba000000-0000-0000-0000-000000051600','{}')$$,
 '42501','permission denied for function challenge_admin_request_v2','authenticated call denied before receipt lookup');
reset role;
set local role anon;
select throws_ok($$select public.challenge_admin_request_v2('ba000000-0000-0000-0000-000000051600','{}')$$,
 '42501','permission denied for function challenge_admin_request_v2','anonymous call denied before receipt lookup');
reset role;

select throws_ok($$select public.challenge_admin_request_v2(null,pg_temp.admin('grant_support',pg_temp.ba(38),null,null,'2026-10-02T12:00Z'))$$,
 '22023','challenge_invalid_admin_request','null request identity denied');
select throws_ok(format('select public.challenge_admin_request_v2(%L::uuid,%L::jsonb)',pg_temp.br(51600+n),body::text),
 '22023','challenge_invalid_admin_request',label)
from (values
 (1,'null payload',null::jsonb),
 (2,'array payload','[]'::jsonb),
 (3,'wrong version',pg_temp.admin('grant_support',pg_temp.ba(38),null,null,'2026-10-02T12:00Z')||'{"version":"old"}'::jsonb),
 (4,'missing operation',pg_temp.admin('grant_support',pg_temp.ba(38),null,null,'2026-10-02T12:00Z')-'operation'),
 (5,'unknown operation',pg_temp.admin('grant_support',pg_temp.ba(38),null,null,'2026-10-02T12:00Z')||'{"operation":"renew_support"}'::jsonb),
 (6,'extra field',pg_temp.admin('grant_support',pg_temp.ba(38),null,null,'2026-10-02T12:00Z')||'{"extra":true}'::jsonb),
 (7,'numeric actor',pg_temp.admin('grant_support',pg_temp.ba(38),null,null,'2026-10-02T12:00Z')||'{"actor_id":7}'::jsonb),
 (8,'null actor',pg_temp.admin('grant_support',pg_temp.ba(38),null,null,'2026-10-02T12:00Z')||'{"actor_id":null}'::jsonb),
 (9,'numeric expiry',pg_temp.admin('grant_support',pg_temp.ba(38),null,null,'2026-10-02T12:00Z')||'{"expires_at":7}'::jsonb),
 (10,'missing scope',pg_temp.admin('grant_operator',pg_temp.ba(40),(select id from beta_ids where name='duel'),'review','2026-10-02T12:00Z')-'challenge_id'),
 (11,'numeric capability',pg_temp.admin('grant_operator',pg_temp.ba(40),(select id from beta_ids where name='duel'),'review','2026-10-02T12:00Z')||'{"capability":7}'::jsonb),
 (12,'null expiry',pg_temp.admin('grant_support',pg_temp.ba(38),null,null,'2026-10-02T12:00Z')||'{"expires_at":null}'::jsonb),
 (13,'null capability',pg_temp.admin('grant_operator',pg_temp.ba(40),(select id from beta_ids where name='duel'),'review','2026-10-02T12:00Z')||'{"capability":null}'::jsonb),
 (14,'missing actor',pg_temp.admin('grant_support',pg_temp.ba(38),null,null,'2026-10-02T12:00Z')-'actor_id')
) bad(n,label,body);
select throws_ok($$select public.challenge_admin_request_v2(pg_temp.br(51615),pg_temp.admin('grant_operator',pg_temp.ba(40),(select id from beta_ids where name='duel'),'owner','2026-10-02T12:00Z'))$$,
 '22023','challenge_invalid_admin_request','invalid scoped capability denied');
select is((select count(*) from app.challenge_admin_requests_v2),(select receipts from admin_baseline),'malformed calls save no receipt');
select is((select count(*) from app.challenge_operator_audit_v1),(select audit from admin_baseline),'malformed calls write no audit');

select throws_ok($$select public.challenge_admin_request_v2(pg_temp.br(51620),pg_temp.admin('grant_support',pg_temp.ba(38),null,null,'2026-10-01T12:00Z'))$$,
 '22023','challenge_invalid_grant','expiry equal to server now denied');
select throws_ok($$select public.challenge_admin_request_v2(pg_temp.br(51621),pg_temp.admin('grant_support',pg_temp.ba(38),null,null,'2026-10-08T12:00:01Z'))$$,
 '22023','challenge_invalid_grant','expiry beyond seven days denied');
select throws_ok($$select public.challenge_admin_request_v2(pg_temp.br(51622),pg_temp.admin('grant_support','bf000000-0000-0000-0000-999999999999',null,null,'2026-10-02T12:00Z'))$$,
 '22023','challenge_invalid_grant','missing actor denied');
select throws_ok($$select public.challenge_admin_request_v2(pg_temp.br(51623),pg_temp.admin('grant_support',pg_temp.ba(37),null,null,'2026-10-02T12:00Z'))$$,
 '22023','challenge_invalid_grant','accepted deletion denies new grant');
select throws_ok($$select public.challenge_admin_request_v2(pg_temp.br(51624),pg_temp.admin('grant_support',pg_temp.ba(39),null,null,'2026-10-02T12:00Z'))$$,
 '22023','challenge_invalid_grant','suspended actor denied');
select throws_ok($$select public.challenge_admin_request_v2(pg_temp.br(51625),pg_temp.admin('grant_operator',pg_temp.ba(1),(select id from beta_ids where name='duel'),'review','2026-10-02T12:00Z'))$$,
 '22023','challenge_invalid_grant','challenge participant cannot review it');
select is((select count(*) from app.challenge_admin_requests_v2),(select receipts from admin_baseline),'failed grants save no receipt');
select is((select count(*) from app.challenge_operator_audit_v1),(select audit from admin_baseline),'failed grants write no audit');

create temp table saved_receipt(value jsonb);
insert into saved_receipt select public.challenge_admin_request_v2(pg_temp.br(51630),
 pg_temp.admin('grant_operator',pg_temp.ba(40),(select id from beta_ids where name='duel'),'review','2026-10-08T12:00Z'));
select is((select value->>'version' from saved_receipt),'challenge_admin_receipt_v2','new receipt version');
select is((select value->>'request_id' from saved_receipt),pg_temp.br(51630)::text,'receipt binds request UUID');
select is((select expires_at from app.challenge_operator_grants_v1 where actor_id=pg_temp.ba(40) and capability='review'),
 '2026-10-08T12:00Z'::timestamptz,'seven-day upper boundary accepted');
select is((select count(*) from app.challenge_operator_audit_v1),(select audit+1 from admin_baseline),'new grant writes one legacy audit action');
select throws_ok($$select public.challenge_admin_request_v2(pg_temp.br(51630),pg_temp.admin('revoke_operator',pg_temp.ba(40),(select id from beta_ids where name='duel'),'review'))$$,
 '22023','challenge_request_conflict','one UUID cannot change operation');
select throws_ok($$select public.challenge_admin_request_v2(pg_temp.br(51630),pg_temp.admin('grant_operator',pg_temp.ba(38),(select id from beta_ids where name='duel'),'review','2026-10-08T12:00Z'))$$,
 '22023','challenge_request_conflict','one UUID cannot change subject');
select throws_ok($$select public.challenge_admin_request_v2(pg_temp.br(51630),pg_temp.admin('grant_operator',pg_temp.ba(40),(select id from beta_ids where name='duel'),'moderate','2026-10-08T12:00Z'))$$,
 '22023','challenge_request_conflict','one UUID cannot change scope');
select throws_ok($$select public.challenge_admin_request_v2(pg_temp.br(51630),pg_temp.admin('grant_operator',pg_temp.ba(40),(select id from beta_ids where name='duel'),'review','2026-10-07T12:00Z'))$$,
 '22023','challenge_request_conflict','one UUID cannot change expiry');
select is((select count(*) from app.challenge_operator_audit_v1),(select audit+1 from admin_baseline),'conflicts write no audit');

select set_config('app.challenge_write_v1','on',true);
select throws_ok($$update app.challenge_admin_requests_v2 set response='{}' where request_id=pg_temp.br(51630)$$,
 '23001','challenge_immutable','receipt update forbidden');
select throws_ok($$delete from app.challenge_admin_requests_v2 where request_id=pg_temp.br(51630)$$,
 '23001','challenge_immutable','receipt deletion forbidden');
select throws_ok($$truncate app.challenge_admin_requests_v2$$,'23001','challenge_immutable','receipt truncate forbidden');
select is((select count(*) from app.challenge_admin_requests_v2),(select receipts+1 from admin_baseline),'immutable receipt retained');

set local role service_role;
select lives_ok($$select public.challenge_admin_request_v2(pg_temp.br(51631),pg_temp.admin('grant_support',pg_temp.ba(36),null,null,'2026-10-02T12:00Z'))$$,
 'actual service role can grant through v2');
reset role;
select pg_temp.clock_beta('2026-10-09T12:00Z',false,false);
select is(public.challenge_admin_request_v2(pg_temp.br(51630),
 pg_temp.admin('grant_operator',pg_temp.ba(40),(select id from beta_ids where name='duel'),'review','2026-10-08T12:00Z')),
 (select value from saved_receipt),'expired grant returns original receipt during runtime pause');
select is(public.challenge_admin_request_v2(pg_temp.br(51631),
 pg_temp.admin('grant_support',pg_temp.ba(36),null,null,'2026-10-02T12:00Z')),
 (select response from app.challenge_admin_requests_v2 where request_id=pg_temp.br(51631)),
 'support receipt recovers after expiry and runtime pause');
select is((select count(*) from app.challenge_operator_audit_v1),(select audit+2 from admin_baseline),'recovery writes no second audit action');
select is((select expires_at from app.challenge_operator_grants_v1 where actor_id=pg_temp.ba(40) and capability='review'),
 '2026-10-08T12:00Z'::timestamptz,'recovery does not extend expired authority');

select pg_temp.clock_beta('2026-10-01T12:00Z');
select is(pg_get_function_result('public.challenge_grant_support_v1(uuid,timestamptz)'::regprocedure),'void','legacy grant signature remains void');
select is(pg_get_function_result('public.challenge_revoke_support_v1(uuid)'::regprocedure),'void','legacy revoke signature remains void');
select is(pg_get_function_result('public.challenge_grant_operator_v1(uuid,uuid,text,timestamptz)'::regprocedure),'void','legacy scoped grant remains void');
select is(pg_get_function_result('public.challenge_revoke_operator_v1(uuid,uuid,text)'::regprocedure),'void','legacy scoped revoke remains void');
select public.challenge_grant_support_v1(pg_temp.ba(35),'2026-10-02T12:00Z');
select public.challenge_revoke_support_v1(pg_temp.ba(35));
select is((select count(*) from app.challenge_admin_requests_v2),(select receipts+2 from admin_baseline),'v1 calls gain no retroactive v2 receipt');
select is((select count(*) from app.challenge_operator_audit_v1),(select audit+4 from admin_baseline),'v1 calls retain separate audit events');
select * from finish();rollback;
