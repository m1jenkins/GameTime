-- Fictional, rollback-only callers. Suspension is an operation restriction;
-- deletion and invalid sessions remain authentication fences, even for replay.
begin;
select no_plan();
\ir fixtures/challenge-fixture.inc

insert into beta_ids values ('own',pg_temp.beta_group(1,3)),('review',pg_temp.beta_group(10,3));
insert into beta_ids values ('community',public.challenge_publish_community_fixture_v1(
 pg_temp.br(80000),pg_temp.ba(40),'{"start_date":"2026-10-03","days":1,"timezone":"UTC","amount_cents":100}',100,2,250,true));
select public.challenge_discovery_fixture_v1(true);
create temp table suspension_requests(name text primary key,request_id uuid,payload jsonb,response jsonb);
grant all on suspension_requests to authenticated;
select pg_temp.login_beta(1);
insert into suspension_requests values ('create',pg_temp.br(80001),
 '{"op":"create","config":{"start_date":"2026-10-03","days":7,"timezone":"America/Chicago","amount_cents":100}}',null);
update suspension_requests set response=public.challenge_command_v1(request_id,payload) where name='create';
insert into beta_ids select 'draft',(response->>'id')::uuid from suspension_requests where name='create';
insert into suspension_requests values ('link',pg_temp.br(80002),null,
 public.challenge_issue_link_v1(pg_temp.br(80002),(select id from beta_ids where name='draft')));
select pg_temp.login_beta(20);
insert into beta_ids values ('invitation',pg_temp.beta_create());
insert into suspension_requests values ('invitation',pg_temp.br(80014),null,
 public.challenge_issue_link_v1(pg_temp.br(80014),(select id from beta_ids where name='invitation')));
select pg_temp.login_beta(21);
select is(public.challenge_redeem_link_v1(pg_temp.br(80015),(select response->>'token' from suspension_requests where name='invitation'))->>'status','pending_request','active actor can redeem the same valid invitation used by the denial test');
reset role;
select public.challenge_grant_support_v1(pg_temp.ba(40),'2026-10-05T12:00Z');
select pg_temp.login_beta(40);
select public.challenge_support_suspend_v1(pg_temp.br(80003),pg_temp.ba(1),'unsafe_behavior');
reset role;
select ok(app.is_active_actor(pg_temp.ba(1)),'suspension preserves the active identity');
select ok(app.challenge_actor_unavailable_v1(pg_temp.ba(1)),'suspension still denies participation and operator availability');
select pg_temp.login_beta(1);
select is(public.challenge_access_status_v1()->>'suspended','true','suspended caller can read explicit access status');
select is(public.challenge_detail_v1((select id from beta_ids where name='own'))->>'social_hidden','true','suspended own detail stays redacted');
select is(jsonb_array_length(public.challenge_detail_v1((select id from beta_ids where name='own'))->'members'),1,'suspended own detail exposes only one member');
select is(public.challenge_detail_v1((select id from beta_ids where name='own'))->'members'->0->>'actor_id',pg_temp.ba(1)::text,'the exposed member is the caller');
select is(public.challenge_detail_v1((select id from beta_ids where name='own'))->'agreement'->'terms','null'::jsonb,'friend roster terms stay hidden');
select throws_ok($$select public.challenge_detail_v1((select id from beta_ids where name='review'))$$,'42501','challenge_unavailable','suspension grants no other challenge access');
select lives_ok($$select public.challenge_list_v1()$$,'suspended caller can list own records');
select lives_ok($$select public.challenge_section_v1('history')$$,'suspended caller can page own history');
select lives_ok($$select public.challenge_section_v1('action')$$,'suspended caller can read own action section');
select is(public.challenge_command_v1(request_id,payload),response,'suspended exact create retry returns the saved receipt') from suspension_requests where name='create';
select is(public.challenge_mutate_v1(request_id,payload),response,'direct exact retry also preserves the receipt') from suspension_requests where name='create';
select is(public.challenge_stop_command_v1(request_id,payload),response,'stop recovers a committed request without repeating admission') from suspension_requests where name='create';
select throws_ok($$select public.challenge_command_v1(request_id,payload||'{"policy":"friend_steps_goal_v1"}') from suspension_requests where name='create'$$,'22023','challenge_request_conflict','suspension does not weaken exact payload matching');
select throws_ok($$select pg_temp.beta_create()$$,'42501','challenge_admission_paused','new friend admission remains denied');
select throws_ok($$select public.challenge_command_v1(pg_temp.br(80004),'{"op":"personal_commit"}')$$,'42501','challenge_admission_paused','new personal admission remains denied');
select throws_ok($$select pg_temp.beta_mutate((select id from beta_ids where name='own'),'target','{"target":42}')$$,'42501','challenge_admission_paused','fresh participant changes remain denied');
select throws_ok($$select public.challenge_issue_link_v1(pg_temp.br(80005),(select id from beta_ids where name='draft'))$$,'42501','challenge_admission_paused','new invitation issuance remains denied');
select is(public.challenge_redeem_link_v1(pg_temp.br(80016),(select response->>'token' from suspension_requests where name='invitation'))->>'message','challenge_link_unavailable','suspended actor cannot redeem a valid invitation from an active issuer');
select is(public.challenge_community_catalog_v1(),'[]'::jsonb,'suspension hides discovery');
select throws_ok($$select public.challenge_join_community_v1(pg_temp.br(80006),jsonb_build_object('op','join_community','id',(select id from beta_ids where name='community'),'digest','known','consent',true))$$,'42501','challenge_admission_paused','known community ID cannot bypass suspended admission');
select lives_ok($$select public.challenge_revoke_link_v1(pg_temp.br(80007),(select (response->>'id')::uuid from suspension_requests where name='link'))$$,'suspended issuer can revoke an existing invitation');
select lives_ok($$select public.challenge_report_v1(pg_temp.br(80008),pg_temp.ba(2),'username')$$,'suspended member retains safe reporting');
select lives_ok($$select public.challenge_report_scoped_v1(pg_temp.br(80009),(select id from beta_ids where name='own'),pg_temp.ba(2),'username')$$,'suspended member retains scoped reporting');
select lives_ok($$select public.challenge_command_v1(pg_temp.br(80010),jsonb_build_object('op','cancel','id',(select id from beta_ids where name='own'),'revision',(public.challenge_detail_v1((select id from beta_ids where name='own'))->>'revision')::bigint))$$,'suspended creator can safely cancel before start');
select lives_ok($$select public.challenge_block_v1(pg_temp.br(80011),pg_temp.ba(2))$$,'suspended member retains blocking');
select is(public.challenge_stop_command_v1(pg_temp.br(80012),'{"op":"create"}')->>'status','cancelled_request','suspended caller can fence an uncommitted request');
select is(public.challenge_command_v1(pg_temp.br(80012),'{"op":"create"}')->>'status','cancelled_request','late dispatch cannot bypass the stop');
select is(public.challenge_appeal_v1(pg_temp.br(80013)),'{"saved":true}'::jsonb,'suspended caller can file an appeal');
select is(public.challenge_appeal_v1(pg_temp.br(80013)),'{"saved":true}'::jsonb,'appeal replay is exact');
select is(jsonb_array_length(public.challenge_own_appeals_v1()),1,'own appeal history excludes other actors');
select is(public.challenge_access_status_v1()->>'appeal_filed','true','access status identifies the current appeal');
reset role;
select is((select count(*) from app.challenge_appeals_v1 where actor_id=pg_temp.ba(1)),1::bigint,'exact appeal replay does not duplicate filing');
select ok(not exists(select 1 from app.challenge_members_v1 where challenge_id=(select id from beta_ids where name='invitation') and actor_id=pg_temp.ba(1)),'denied invitation creates no suspended membership');

-- A three-person review remains open when one actor is suspended. That actor
-- can still contest their own result and leave, with no peer Health disclosure.
select pg_temp.clock_beta('2026-10-10T12:00Z');
select public.challenge_capture_fixture_v1(extensions.gen_random_uuid(),(select id from beta_ids where name='review'),pg_temp.ba(n),20000,'complete') from generate_series(10,12) n;
select pg_temp.clock_beta('2026-10-12T12:00Z');
select public.challenge_process_v1((select id from beta_ids where name='review'));
select public.challenge_grant_support_v1(pg_temp.ba(40),'2026-10-15T12:00Z');
select public.challenge_grant_support_v1(pg_temp.ba(39),'2026-10-15T12:00Z');
select public.challenge_grant_support_v1(pg_temp.ba(38),'2026-10-15T12:00Z');
select public.challenge_grant_operator_v1(pg_temp.ba(39),(select id from beta_ids where name='review'),'review','2026-10-15T12:00Z');
select public.challenge_grant_operator_v1(pg_temp.ba(39),(select id from beta_ids where name='review'),'moderate','2026-10-15T12:00Z');
select public.challenge_grant_operator_v1(pg_temp.ba(39),(select id from beta_ids where name='community'),'moderate','2026-10-15T12:00Z');
select pg_temp.login_beta(39);
select public.challenge_support_suspend_v1(pg_temp.br(80100),pg_temp.ba(30),'username');
select pg_temp.login_beta(40);
select public.challenge_support_suspend_v1(pg_temp.br(80101),pg_temp.ba(12),'unsafe_behavior');
select public.challenge_support_suspend_v1(pg_temp.br(80102),pg_temp.ba(39),'unsafe_behavior');
select pg_temp.login_beta(12);
select lives_ok($$select pg_temp.beta_mutate((select id from beta_ids where name='review'),'review','{"notice_revision":1,"reason":"wrong_total"}',pg_temp.br(80103))$$,'suspended participant can request review within the existing window');
select is(public.challenge_detail_v1((select id from beta_ids where name='review'))->'notice'->'result'->'participants',null::jsonb,'suspended review hides peer result map');
select ok(public.challenge_detail_v1((select id from beta_ids where name='review'))->'notice'->'result' ? 'own','suspended review retains own result');
select is(jsonb_array_length(public.challenge_detail_v1((select id from beta_ids where name='review'))->'reviews'),1,'suspended participant can read own review');
select lives_ok($$select pg_temp.beta_mutate((select id from beta_ids where name='review'),'leave','{}',pg_temp.br(80104))$$,'suspended participant can safely leave an unsettled agreement');
select pg_temp.login_beta(39);
select is(public.challenge_support_suspend_v1(pg_temp.br(80100),pg_temp.ba(30),'username'),'{"saved":true}'::jsonb,'suspended operator can recover an already committed receipt');
select throws_ok($$select public.challenge_support_suspend_v1(pg_temp.br(80100),pg_temp.ba(30),'unsafe_behavior')$$,'22023','challenge_request_conflict','operator receipt still rejects changed parameters');
select throws_ok($$select public.challenge_operator_cases_v1((select id from beta_ids where name='review'))$$,'42501','challenge_operator_required','suspended reviewer cannot read cases despite live grant');
select throws_ok($$select public.challenge_operator_reports_v1((select id from beta_ids where name='review'))$$,'42501','challenge_operator_required','suspended moderator cannot read reports despite live grant');
select throws_ok($$select public.challenge_operator_action_v1(pg_temp.br(80105),jsonb_build_object('op','resolve','id',(select id from beta_ids where name='review'),'review_id',pg_temp.br(80103),'decision','upheld'))$$,'42501','challenge_operator_required','suspended reviewer cannot make a fresh decision');
select throws_ok($$select public.challenge_command_v1(pg_temp.br(80106),jsonb_build_object('op','remove','id',(select id from beta_ids where name='review'),'actor_id',pg_temp.ba(10),'reason','username'))$$,'42501','challenge_operator_required','dispatcher cannot bypass suspended moderation restriction');
select throws_ok($$select public.challenge_operator_close_v1(pg_temp.br(80107),(select id from beta_ids where name='community'))$$,'42501','challenge_operator_required','suspended moderator cannot close community');
select throws_ok($$select public.challenge_support_reports_v1()$$,'42501','challenge_support_required','suspended support cannot read reports');
select throws_ok($$select public.challenge_support_appeals_v1()$$,'42501','challenge_support_required','suspended support cannot read others appeals');
select throws_ok($$select public.challenge_support_suspend_v1(pg_temp.br(80108),pg_temp.ba(31),'username')$$,'42501','challenge_support_required','suspended support cannot suspend another actor');
select throws_ok($$select public.challenge_resolve_appeal_v1(pg_temp.br(80109),pg_temp.br(80013),'reinstate')$$,'42501','challenge_support_required','suspended support cannot decide an appeal');
reset role;
select throws_ok($$select public.challenge_grant_support_v1(pg_temp.ba(39),'2026-10-15T12:00Z')$$,'22023','challenge_invalid_grant','service cannot newly grant support to a suspended actor');
select throws_ok($$select public.challenge_grant_operator_v1(pg_temp.ba(39),(select id from beta_ids where name='review'),'review','2026-10-15T12:00Z')$$,'22023','challenge_invalid_grant','service cannot newly grant reviewer authority to a suspended actor');
select pg_temp.login_beta(40);
select throws_ok($$select public.challenge_resolve_appeal_v1(pg_temp.br(80110),pg_temp.br(80013),'reinstate')$$,'42501','challenge_independent_support_required','original suspender cannot decide the appeal');
select pg_temp.login_beta(1);
select throws_ok($$select public.challenge_resolve_appeal_v1(pg_temp.br(80111),pg_temp.br(80013),'reinstate')$$,'42501','challenge_support_required','appellant cannot decide own appeal');
select pg_temp.login_beta(38);
select is(public.challenge_resolve_appeal_v1(pg_temp.br(80112),pg_temp.br(80013),'reinstate'),'{"saved":true}'::jsonb,'independent active support can reinstate');
select pg_temp.login_beta(1);
select is(public.challenge_own_appeals_v1()->0->>'decision','reinstate','own appeal history exposes the independent decision');
reset role;
select ok((select exited_at is not null from app.challenge_members_v1 where challenge_id=(select id from beta_ids where name='own') and actor_id=pg_temp.ba(1)),'reinstatement does not undo safe exit');

-- All ordinary endpoints (including saved receipts) still require a live
-- actor-bound session. Use a suspended actor so the positive path is exercised.
select pg_temp.login_beta(39);
select lives_ok($$select public.challenge_access_status_v1()$$,'suspended actor with live session remains authenticated');
reset role;
update auth.sessions set not_after=clock_timestamp() where id=pg_temp.br(39);
select pg_temp.login_beta(39);
select throws_ok($$select public.challenge_access_status_v1()$$,'42501','challenge_session_required','expired suspended session cannot read status');
select throws_ok($$select public.challenge_support_suspend_v1(pg_temp.br(80100),pg_temp.ba(30),'username')$$,'42501','challenge_session_required','expired session cannot replay a saved receipt');
reset role;
update auth.sessions set not_after=null where id=pg_temp.br(39);
select pg_temp.login_beta(39);
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.ba(39),'session_id',pg_temp.br(38))::text,true);
select throws_ok($$select public.challenge_own_appeals_v1()$$,'42501','challenge_session_required','another actor session cannot authenticate a suspended caller');
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.ba(39))::text,true);
select throws_ok($$select public.challenge_access_status_v1()$$,'42501','challenge_session_required','JWT without session binding remains denied');
reset role;
delete from auth.sessions where id=pg_temp.br(39);
select pg_temp.login_beta(39);
select throws_ok($$select public.challenge_access_status_v1()$$,'42501','challenge_session_required','revoked session rejects its stale JWT');
select throws_ok($$select public.challenge_support_suspend_v1(pg_temp.br(80100),pg_temp.ba(30),'username')$$,'42501','challenge_session_required','revoked session cannot replay a receipt');
reset role;

-- An accepted tombstone alone must fence even an otherwise intact identity
-- and pre-existing session (e.g. an older restored snapshot before cleanup).
insert into app.challenge_account_deletions_v1(actor_id,request_id,receipt_hash,apple_subject_hash,accepted_at,required_steps_finished_at,identity_cleanup_after)
select pg_temp.ba(30),pg_temp.br(80200),extensions.digest('fictional suspension tombstone','sha256'),extensions.digest('fictional apple subject','sha256'),n,n,n+interval '7 days' from (select clock_timestamp() n) clock;
select ok(exists(select 1 from auth.users where id=pg_temp.ba(30)) and exists(select 1 from auth.sessions where id=pg_temp.br(30)) and exists(select 1 from public.profiles where id=pg_temp.ba(30) and deleted_at is null),'tombstone test retains Auth, profile and pre-existing session');
select pg_temp.login_beta(30);
select throws_ok($$select public.challenge_access_status_v1()$$,'42501','challenge_session_required','accepted tombstone immediately rejects an intact stale session');
select throws_ok($$select public.challenge_appeal_v1(pg_temp.br(80201))$$,'42501','challenge_session_required','accepted deletion cannot use ordinary suspension appeals');
reset role;
select public.challenge_begin_account_deletion_v1(pg_temp.ba(12),pg_temp.br(80202),'fictional_suspension_deletion_receipt_01234567890123456789','fictional_apple_suspension_12');
select pg_temp.login_beta(12);
select throws_ok($$select public.challenge_detail_v1((select id from beta_ids where name='review'))$$,'42501','challenge_session_required','deleted suspended account loses ordinary own detail immediately');
select throws_ok($$select public.challenge_command_v1(pg_temp.br(80103),jsonb_build_object('op','review','id',(select id from beta_ids where name='review'),'revision',1,'notice_revision',1,'reason','wrong_total'))$$,'42501','challenge_session_required','deleted caller cannot reach exact-retry lookup');
reset role;
select * from finish();
rollback;
