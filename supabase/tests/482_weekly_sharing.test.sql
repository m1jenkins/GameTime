begin;
select no_plan();
\ir fixtures/weekly-fixture.inc
insert into weekly_test_ids values('group',pg_temp.make_friend(1,2));
select pg_temp.login(3);
select is(public.list_shared_weekly_progress_v1(),'[]'::jsonb,'friendship alone never shares progress');
select pg_temp.login(1);
select public.set_weekly_sharing_v1(pg_temp.req(901),(select id from weekly_test_ids where name='group'),pg_temp.actor(3),true);
select is(public.set_weekly_sharing_v1(pg_temp.req(901),(select id from weekly_test_ids where name='group'),pg_temp.actor(3),true),pg_temp.req(901),'exact sharing consent retry');
select throws_ok($$select public.set_weekly_sharing_v1(pg_temp.req(901),(select id from weekly_test_ids where name='group'),pg_temp.actor(4),true)$$,'22023','weekly_request_conflict','changed sharing recipient cannot reuse consent');
select pg_temp.login(3);
select is(public.list_shared_weekly_progress_v1(),'[]'::jsonb,'owner offer alone does not make recipient follow');
select is(jsonb_array_length(public.list_weekly_follow_requests_v1()),1,'recipient sees explicit pending offer');
select public.respond_weekly_follow_v1(pg_temp.req(951),(select id from weekly_test_ids where name='group'),pg_temp.actor(1),pg_temp.req(901),'accept');
select is(jsonb_array_length(public.list_shared_weekly_progress_v1()),1,'accepted selected friend receives display projection');
select is(public.list_shared_weekly_progress_v1()->0->'observed_steps','null'::jsonb,'missing observation is null rather than zero');
select ok(not ((public.list_shared_weekly_progress_v1()->0)?|array['qualification','result','allocation','amount','roster','notices','cases']),'shared display contains no qualification financial or roster fields');
select throws_ok($$select public.get_weekly_v1((select id from weekly_test_ids where name='group'))$$,'42501','weekly_unavailable','sharing does not grant participant agreement access');
select throws_ok($$select public.list_weekly_sharing_v1((select id from weekly_test_ids where name='group'))$$,'42501','weekly_sharing_unavailable','recipient cannot enumerate other viewers');
reset role;
select is((select count(*) from app.weekly_participants where actor_id=pg_temp.actor(3)),0::bigint,'sharing never enrolls recipient');
select public.set_weekly_runtime_v1(false,false,false,'{}');
select pg_temp.login(1);
select public.set_weekly_sharing_v1(pg_temp.req(902),(select id from weekly_test_ids where name='group'),pg_temp.actor(3),false);
select pg_temp.login(3);
select is(public.list_shared_weekly_progress_v1(),'[]'::jsonb,'revocation works gate off');
select pg_temp.login(1);
select public.set_weekly_sharing_v1(pg_temp.req(903),(select id from weekly_test_ids where name='group'),pg_temp.actor(3),true);
select pg_temp.login(3);
select public.respond_weekly_follow_v1(pg_temp.req(953),(select id from weekly_test_ids where name='group'),pg_temp.actor(1),pg_temp.req(903),'accept');
insert into public.blocks(blocker_id,blocked_id) values(pg_temp.actor(3),pg_temp.actor(1));
select is(public.list_shared_weekly_progress_v1(),'[]'::jsonb,'block suppresses shared display immediately at read');
select pg_temp.login(1);
select is(public.list_weekly_sharing_v1((select id from weekly_test_ids where name='group')),'[]'::jsonb,'blocked recipient identity hidden from owner sharing list');
select public.set_weekly_sharing_v1(pg_temp.req(904),(select id from weekly_test_ids where name='group'),pg_temp.actor(3),false);
select pg_temp.login(3);
delete from public.blocks where blocker_id=pg_temp.actor(3) and blocked_id=pg_temp.actor(1);
reset role;
insert into public.friendships(user_a,user_b,requested_by,status) values(pg_temp.actor(1),pg_temp.actor(3),pg_temp.actor(1),'accepted');
select pg_temp.login(3);
select is(public.list_shared_weekly_progress_v1(),'[]'::jsonb,'unblock and new friendship do not revive grant');
select pg_temp.login(1);
select public.set_weekly_sharing_v1(pg_temp.req(906),(select id from weekly_test_ids where name='group'),pg_temp.actor(3),true);
select pg_temp.login(3);
select throws_ok($$select public.respond_weekly_follow_v1(pg_temp.req(956),(select id from weekly_test_ids where name='group'),pg_temp.actor(1),pg_temp.req(903),'accept')$$,'42501','weekly_follow_unavailable','old offer cannot consent to renewed owner grant');
select public.respond_weekly_follow_v1(pg_temp.req(957),(select id from weekly_test_ids where name='group'),pg_temp.actor(1),pg_temp.req(906),'accept');
select public.respond_weekly_follow_v1(pg_temp.req(958),(select id from weekly_test_ids where name='group'),pg_temp.actor(1),pg_temp.req(906),'unfollow');
select is(public.list_shared_weekly_progress_v1(),'[]'::jsonb,'recipient can safely unfollow gate off');
select pg_temp.login(1);
select throws_ok($$select public.set_weekly_sharing_v1(pg_temp.req(907),(select id from weekly_test_ids where name='group'),pg_temp.actor(3),true)$$,'55000','weekly_follow_declined','decline or unfollow prevents repeated invitation for same agreement');

select public.set_weekly_sharing_v1(pg_temp.req(905),(select id from weekly_test_ids where name='group'),pg_temp.actor(4),true);
select pg_temp.login(4);
select public.respond_weekly_follow_v1(pg_temp.req(959),(select id from weekly_test_ids where name='group'),pg_temp.actor(1),pg_temp.req(905),'accept');
reset role;
select public.delete_account(pg_temp.actor(1));
select pg_temp.login(4);
select is(public.list_shared_weekly_progress_v1(),'[]'::jsonb,'deletion revokes display grant');
reset role;
select ok(not exists(select 1 from app.weekly_sharing where owner_id=pg_temp.actor(1) and enabled),'deletion retains disabled consent history only');
select ok(not has_table_privilege('authenticated','app.weekly_sharing','select'),'no sharing base table enumeration');
select ok(not has_function_privilege('anon','public.list_shared_weekly_progress_v1()','execute'),'no anonymous display access');
delete from auth.sessions where id=pg_temp.req(4);
select pg_temp.login(4);
select throws_ok($$select public.list_shared_weekly_progress_v1()$$,'42501','weekly_session_required','revoked session cannot read shared progress');
reset role;
-- Private clock seams prove the selected-week half-open end boundary without
-- granting authenticated callers a client-controlled clock.
create function pg_temp.share_at(r uuid,c uuid,f uuid,e boolean,n timestamptz) returns uuid
language sql security definer set search_path='' as $$select app.weekly_set_sharing_at_v1(r,c,f,e,n)$$;
create function pg_temp.follow_at(r uuid,c uuid,o uuid,f uuid,d text,n timestamptz) returns uuid
language sql security definer set search_path='' as $$select app.weekly_respond_follow_at_v1(r,c,o,f,d,n)$$;
create function pg_temp.shared_at(n timestamptz) returns jsonb
language sql security definer set search_path='' as $$select app.weekly_shared_progress_at_v1(n)$$;
create function pg_temp.offers_at(n timestamptz) returns jsonb
language sql security definer set search_path='' as $$select app.weekly_follow_requests_at_v1(n)$$;
select public.set_weekly_runtime_v1(true,true,true,array[pg_temp.actor(10),pg_temp.actor(11)]);
insert into weekly_test_ids values('expiry',pg_temp.make_friend(10,2));
select public.set_weekly_runtime_v1(false,false,false,'{}');
select pg_temp.login(10);
select lives_ok($$select pg_temp.share_at(pg_temp.req(970),(select id from weekly_test_ids where name='expiry'),pg_temp.actor(12),true,'2026-09-14T04:59:59.999999Z')$$,'owner may offer at final eligible microsecond');
select pg_temp.share_at(pg_temp.req(971),(select id from weekly_test_ids where name='expiry'),pg_temp.actor(13),true,'2026-09-14T04:59:59.999999Z');
select throws_ok($$select pg_temp.share_at(pg_temp.req(972),(select id from weekly_test_ids where name='expiry'),pg_temp.actor(14),true,'2026-09-14T05:00:00Z')$$,'55000','weekly_sharing_expired','owner cannot offer at exact week end');
select throws_ok($$select pg_temp.share_at(pg_temp.req(973),(select id from weekly_test_ids where name='expiry'),pg_temp.actor(14),true,'2026-09-14T05:00:00.000001Z')$$,'55000','weekly_sharing_expired','owner cannot offer one microsecond after week end');
select is(pg_temp.share_at(pg_temp.req(970),(select id from weekly_test_ids where name='expiry'),pg_temp.actor(12),true,'2026-09-14T05:00:00Z'),pg_temp.req(970),'expiry preserves exact committed owner receipt');
select pg_temp.login(12);
select lives_ok($$select pg_temp.follow_at(pg_temp.req(974),(select id from weekly_test_ids where name='expiry'),pg_temp.actor(10),pg_temp.req(970),'accept','2026-09-14T04:59:59.999999Z')$$,'recipient may accept at final eligible microsecond');
select is(jsonb_array_length(pg_temp.shared_at('2026-09-14T04:59:59.999999Z')),1,'shared display readable at final eligible microsecond');
select is(pg_temp.shared_at('2026-09-14T05:00:00Z'),'[]'::jsonb,'shared display hidden at exact week end');
select is(pg_temp.shared_at('2026-09-14T05:00:00.000001Z'),'[]'::jsonb,'shared display hidden one microsecond after week end');
select is(pg_temp.follow_at(pg_temp.req(974),(select id from weekly_test_ids where name='expiry'),pg_temp.actor(10),pg_temp.req(970),'accept','2026-09-14T05:00:00Z'),pg_temp.req(974),'expiry preserves exact committed recipient receipt');
select lives_ok($$select pg_temp.follow_at(pg_temp.req(975),(select id from weekly_test_ids where name='expiry'),pg_temp.actor(10),pg_temp.req(970),'unfollow','2026-09-14T05:00:00.000001Z')$$,'recipient can unfollow after expiry gate off');
select pg_temp.login(13);
select is(jsonb_array_length(pg_temp.offers_at('2026-09-14T04:59:59.999999Z')),1,'pending offer visible at final eligible microsecond');
select is(pg_temp.offers_at('2026-09-14T05:00:00Z'),'[]'::jsonb,'pending offer hidden at exact week end');
select is(pg_temp.offers_at('2026-09-14T05:00:00.000001Z'),'[]'::jsonb,'pending offer hidden one microsecond after week end');
select throws_ok($$select pg_temp.follow_at(pg_temp.req(976),(select id from weekly_test_ids where name='expiry'),pg_temp.actor(10),pg_temp.req(971),'accept','2026-09-14T05:00:00Z')$$,'55000','weekly_sharing_expired','recipient cannot accept at exact week end');
select throws_ok($$select pg_temp.follow_at(pg_temp.req(977),(select id from weekly_test_ids where name='expiry'),pg_temp.actor(10),pg_temp.req(971),'accept','2026-09-14T05:00:00.000001Z')$$,'55000','weekly_sharing_expired','recipient cannot accept one microsecond after week end');
select lives_ok($$select pg_temp.follow_at(pg_temp.req(978),(select id from weekly_test_ids where name='expiry'),pg_temp.actor(10),pg_temp.req(971),'decline','2026-09-14T05:00:00.000001Z')$$,'recipient can decline after expiry');
select pg_temp.login(10);
select lives_ok($$select pg_temp.share_at(pg_temp.req(979),(select id from weekly_test_ids where name='expiry'),pg_temp.actor(12),false,'2026-09-14T05:00:00.000001Z')$$,'owner can revoke after expiry');
reset role;
select ok(not has_function_privilege('authenticated','app.weekly_set_sharing_at_v1(uuid,uuid,uuid,boolean,timestamptz)','execute')
 and not has_function_privilege('authenticated','app.weekly_respond_follow_at_v1(uuid,uuid,uuid,uuid,text,timestamptz)','execute')
 and not has_function_privilege('authenticated','app.weekly_shared_progress_at_v1(timestamptz)','execute')
 and not has_function_privilege('authenticated','app.weekly_follow_requests_at_v1(timestamptz)','execute'),'injected sharing clocks are private and never client authority');
select * from finish();
rollback;
