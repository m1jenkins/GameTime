begin;
select no_plan();
set local timezone='UTC';
create function pg_temp.actor(n integer) returns uuid language sql immutable as $$
 select ('e9100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.req(n integer) returns uuid language sql immutable as $$
 select ('e9200000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.login(n integer) returns void language plpgsql as $$ begin
 perform set_config('request.jwt.claim.sub',pg_temp.actor(n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.actor(n),'role','authenticated','session_id',pg_temp.req(n))::text,true);
end; $$;
insert into auth.users(id) select pg_temp.actor(n) from generate_series(1,6) n;
insert into public.profiles(id,handle,display_name,timezone)
 select pg_temp.actor(n),'followingfixture'||n,'Fictional Runner','UTC' from generate_series(1,6) n;
insert into auth.sessions(id,user_id) select pg_temp.req(n),pg_temp.actor(n) from generate_series(1,6) n;
insert into public.friendships(user_a,user_b,requested_by,status)
 select pg_temp.actor(1),pg_temp.actor(n),pg_temp.actor(1),'accepted' from generate_series(2,3) n;
insert into public.friendships(user_a,user_b,requested_by,status) values(pg_temp.actor(1),pg_temp.actor(6),pg_temp.actor(1),'pending');
select public.set_performance_commitment_admission_v1(true,array[pg_temp.actor(1)]);
select public.set_commitment_progress_enabled_v1(true);
create temp table saved(name text primary key,value jsonb);
grant select,insert,update on saved to authenticated;
create function pg_temp.id(n text) returns uuid language sql as $$ select (value->>0)::uuid from saved where name=n $$;
create function pg_temp.setup() returns uuid language plpgsql security definer set search_path='' as $$
 declare s timestamptz:=clock_timestamp()-interval '9 days'; d timestamptz; t jsonb; c uuid;
 begin
 d:=s+interval '60 days';
 t:=app.performance_commitment_terms_v1(auth.uid(),360,s,d,'America/Chicago','performance-commitment-fixture-5k-v1');
 c:=app.create_performance_commitment_at_v1(pg_temp.req(10),360,s,d,'America/Chicago','performance-commitment-fixture-5k-v1',
   encode(extensions.digest(t::text,'sha256'),'hex'),true,s-interval '1 day');
 perform public.create_commitment_milestone_v1(pg_temp.req(11),c,'Choose a race',s+interval '20 days');
 perform public.record_commitment_progress_v1(pg_temp.req(12),c,'PRIVATE: ran 5K in 5:59; medical detail',s+interval '1 day');
 perform public.create_commitment_milestone_v1(pg_temp.req(13),c,'PRIVATE unshared milestone',s+interval '30 days');
 return c;
end; $$;
select pg_temp.login(1);
set local role authenticated;
insert into saved values('main',jsonb_build_array(pg_temp.setup()));
reset role;
select is((select enabled from app.performance_following_runtime),false,'following defaults off');
select is((select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='app'
  and c.relname like 'performance_following_%' and c.relkind='r' and c.relrowsecurity),10::bigint,'all ten tables private with RLS');
select ok(not has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'),r||' cannot access '||c.relname)
 from pg_class c join pg_namespace n on n.oid=c.relnamespace cross join unnest(array['anon','authenticated','service_role']) r
 where n.nspname='app' and c.relname like 'performance_following_%' and c.relkind='r';
select ok(not has_function_privilege(r,p.oid,'EXECUTE'),r||' cannot call private '||p.proname)
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace cross join unnest(array['anon','authenticated','service_role']) r
 where n.nspname='app' and p.proname like '%performance_following%v1';
create function pg_temp.invite(q integer,friend integer default 2,scope text default 'goal_and_selected_progress_v1',consent boolean default true)
 returns jsonb language sql as $$ select public.invite_commitment_follower_v1(pg_temp.req(q),pg_temp.id('main'),pg_temp.actor(friend),scope,consent) $$;
set local role authenticated;
select throws_ok('select pg_temp.invite(20)','42501',null,'gate-off denies invitation');
select throws_ok('select public.set_commitment_following_enabled_v1(true)','42501',null,'owner cannot open following gate');
select lives_ok('select public.get_commitment_publications_v1(pg_temp.id(''main''))','owner can inspect empty publications gate-off');
reset role;
set local role anon;
select throws_ok('select public.list_commitment_follows_v1()','42501',null,'anonymous discovery denied');
select throws_ok('select public.get_commitment_follow_v1(null)','42501',null,'anonymous detail denied');
reset role;
set local role service_role;
select throws_ok('select public.get_commitment_publications_v1(null)','42501',null,'service cannot impersonate owner');
reset role;
select public.set_commitment_following_enabled_v1(true);
select public.set_commitment_attempts_enabled_v1(true);
insert into saved values('snapshot',public.get_commitment_attempt_snapshot_v1(pg_temp.id('main')) #- '{agreement,server_now}');
select public.set_commitment_attempts_enabled_v1(false);
set local role authenticated;
select throws_ok('select pg_temp.invite(20,2,null)','22023',null,'explicit versioned sharing scope required');
select throws_ok('select pg_temp.invite(20,2,''goal_and_selected_progress_v1'',false)','22023',null,'explicit owner consent required');
select throws_ok('select pg_temp.invite(20,1)','42501',null,'self following denied');
select throws_ok('select pg_temp.invite(20,4)','42501',null,'nonfriend denied');
select throws_ok('select pg_temp.invite(20,6)','42501',null,'pending friendship denied');
insert into saved values('invite',pg_temp.invite(20));
insert into saved values('follow',jsonb_build_array((select value->>'follow_id' from saved where name='invite')));
select is(pg_temp.invite(20),(select value from saved where name='invite'),'exact invitation recovery');
select throws_ok('select pg_temp.invite(20,3)','22023',null,'request binds exact friend');
select throws_ok('select pg_temp.invite(21)','22023',null,'duplicate open pair denied');
select is(public.get_commitment_follow_v1(pg_temp.id('follow'))->'access_allowed','false'::jsonb,'invitation alone grants no progress access');
select pg_temp.login(4);
select throws_ok('select public.get_commitment_follow_v1(pg_temp.id(''follow''))','42501',null,'unrelated user denied');
select throws_ok('select public.respond_commitment_follow_v1(pg_temp.req(21),pg_temp.id(''follow''),true)','42501',null,'unrelated acceptance denied');
select pg_temp.login(2);
select is(jsonb_array_length(public.list_commitment_follows_v1()->'follows'),1,'named friend discovers locator');
select ok(not(public.list_commitment_follows_v1()::text ~ 'target_seconds|PRIVATE|note|owner_id'),'locator list contains no shared content');
select ok(not(public.get_commitment_follow_v1(pg_temp.id('follow')) ? 'goal'),'pending follower cannot see goal');
select throws_ok('select public.get_commitment_progress_v1(pg_temp.id(''main''))','42501',null,'friend has no private progress access');
select throws_ok('select public.get_commitment_publications_v1(pg_temp.id(''main''))','42501',null,'follower cannot use owner endpoint');
select throws_ok('select public.respond_commitment_follow_v1(pg_temp.req(21),pg_temp.id(''follow''),null)','22023',null,'follower explicit consent required');
insert into saved values('accept',public.respond_commitment_follow_v1(pg_temp.req(21),pg_temp.id('follow'),true));
select is(public.respond_commitment_follow_v1(pg_temp.req(21),pg_temp.id('follow'),true),(select value from saved where name='accept'),'exact acceptance receipt');
select throws_ok('select public.respond_commitment_follow_v1(pg_temp.req(21),pg_temp.id(''follow''),false)','22023',null,'accept request cannot become decline');
select is(public.get_commitment_follow_v1(pg_temp.id('follow'))->'goal'->'target_seconds','360'::jsonb,'accepted follow shows selected goal facts');
select is(public.get_commitment_follow_v1(pg_temp.id('follow'))->'cards','[]'::jsonb,'existing private progress never auto-publishes');
select is(public.get_commitment_follow_v1(pg_temp.id('follow'))->'reminder_due','false'::jsonb,'reminders default off');
select throws_ok('select public.end_commitment_follow_v1(pg_temp.req(22),pg_temp.id(''follow''),''revoke'')','42501',null,'follower cannot act as owner');
select pg_temp.login(1);
select throws_ok('select public.publish_commitment_progress_v1(pg_temp.req(22),pg_temp.id(''main''),999)','42501',null,'cannot publish nonexistent entry');
insert into saved values('published',public.publish_commitment_progress_v1(pg_temp.req(22),pg_temp.id('main'),1));
insert into saved values('publication',jsonb_build_array((select value->>'publication_id' from saved where name='published')));
select is(public.publish_commitment_progress_v1(pg_temp.req(22),pg_temp.id('main'),1),(select value from saved where name='published'),'exact publication recovery');
select throws_ok('select public.publish_commitment_progress_v1(pg_temp.req(22),pg_temp.id(''main''),2)','22023',null,'publication request binds exact entry');
select throws_ok('select public.publish_commitment_progress_v1(pg_temp.req(23),pg_temp.id(''main''),1)','22023',null,'new request cannot duplicate visible entry');
insert into saved values('note_publication',public.publish_commitment_progress_v1(pg_temp.req(23),pg_temp.id('main'),2));
select pg_temp.login(2);
insert into saved values('page',public.get_commitment_follow_v1(pg_temp.id('follow'),1));
select is((select value->'has_more' from saved where name='page'),'true'::jsonb,'bounded selected-progress page');
select is((select value->'cards'->0->>'milestone_title' from saved where name='page'),'Choose a race','only selected milestone name published');
select ok(not(public.get_commitment_follow_v1(pg_temp.id('follow'))::text ~ 'PRIVATE|note|terms|amount|recipient|bib|source_document|request_id'),'shared projection excludes private notes, amounts and proof');
select is(public.get_commitment_follow_v1(pg_temp.id('follow'),1,1,2)->'cards'->0->>'kind','check_in','next page includes selected note occurrence only');
select is(public.get_commitment_follow_v1(pg_temp.id('follow'),1,1,2)->'cards'->0->'counts_as_proof','false'::jsonb,'check-in cannot become proof');
select throws_ok('select public.get_commitment_follow_v1(pg_temp.id(''follow''),51)','22023',null,'page limit capped');
select throws_ok('select public.get_commitment_follow_v1(pg_temp.id(''follow''),1,1)','22023',null,'continuation requires content revision');
select throws_ok('select public.react_commitment_progress_v1(pg_temp.req(24),pg_temp.id(''follow''),pg_temp.id(''publication''),''custom text'')','22023',null,'no freeform social comments');
insert into saved values('reaction',public.react_commitment_progress_v1(pg_temp.req(24),pg_temp.id('follow'),pg_temp.id('publication'),'cheer'));
select is(public.react_commitment_progress_v1(pg_temp.req(24),pg_temp.id('follow'),pg_temp.id('publication'),'cheer'),(select value from saved where name='reaction'),'exact structured reaction recovery');
select is(public.get_commitment_follow_v1(pg_temp.id('follow'))->'cards'->0->>'your_reaction','cheer','follower sees own reaction');
select pg_temp.login(1);
select is(public.get_commitment_publications_v1(pg_temp.id('main'))->'cards'->0->'reaction_counts'->>'cheer','1','owner receives bounded aggregate reactions');
select lives_ok('select public.retract_commitment_progress_v1(pg_temp.req(25),pg_temp.id(''publication''))','owner retracts selected milestone');
select pg_temp.login(2);
select throws_ok('select public.get_commitment_follow_v1(pg_temp.id(''follow''),1,1,2)','22023',null,'retraction invalidates old page revision');
select ok(not(public.get_commitment_follow_v1(pg_temp.id('follow'))::text ~ 'Choose a race'),'fresh page omits retracted content');
select throws_ok('select public.react_commitment_progress_v1(pg_temp.req(26),pg_temp.id(''follow''),pg_temp.id(''publication''),''well_done'')','42501',null,'cannot react to retracted card');
select lives_ok('select public.react_commitment_progress_v1(pg_temp.req(26),pg_temp.id(''follow''),pg_temp.id(''publication''),null)','own reaction can be removed after retraction');
select throws_ok('select public.set_commitment_follow_reminder_v1(pg_temp.req(27),pg_temp.id(''follow''),''infinity'')','22023',null,'infinite reminder rejected');
select throws_ok('select public.set_commitment_follow_reminder_v1(pg_temp.req(27),pg_temp.id(''follow''),now()-interval ''1 second'')','22023',null,'past reminder rejected');
select throws_ok('select public.set_commitment_follow_reminder_v1(pg_temp.req(27),pg_temp.id(''follow''),now()+interval ''31 days'')','22023',null,'reminder horizon bounded');
insert into saved values('reminder_time',to_jsonb(clock_timestamp()+interval '1 day'));
select lives_ok('select public.set_commitment_follow_reminder_v1(pg_temp.req(27),pg_temp.id(''follow''),(select (value#>>''{}'')::timestamptz from saved where name=''reminder_time''))','follower explicitly schedules own in-app reminder');
select is(public.get_commitment_follow_v1(pg_temp.id('follow'))->'reminder_due','false'::jsonb,'future reminder is not due');
reset role;
-- Simulate passage solely for the reminder; no worker or external dispatch.
update app.performance_following_grants set reminder_at=clock_timestamp()-interval '1 second',revision=revision+1 where id=pg_temp.id('follow');
set local role authenticated;
select is(public.get_commitment_follow_v1(pg_temp.id('follow'))->'reminder_due','true'::jsonb,'explicitly scheduled reminder becomes due on read');
reset role;
select public.set_commitment_following_enabled_v1(false);
set local role authenticated;
select is(public.get_commitment_follow_v1(pg_temp.id('follow'))->'reminder_due','false'::jsonb,'gate-off suppresses reminders');
select lives_ok('select public.set_commitment_follow_reminder_v1(pg_temp.req(28),pg_temp.id(''follow''),null)','gate-off reminder cancellation');
select throws_ok('select public.set_commitment_follow_reminder_v1(pg_temp.req(29),pg_temp.id(''follow''),now()+interval ''1 day'')','42501',null,'gate-off new reminder denied');
insert into saved values('report',public.report_commitment_follow_v1(pg_temp.req(29),pg_temp.id('follow'),'pressure','PRIVATE report: please help'));
insert into saved values('case',jsonb_build_array((select value->>'case_id' from saved where name='report')));
select is(public.report_commitment_follow_v1(pg_temp.req(29),pg_temp.id('follow'),'pressure','PRIVATE report: please help'),(select value from saved where name='report'),'gate-off report exact recovery');
select is(public.get_commitment_follow_report_v1(pg_temp.id('case'))->>'note','PRIVATE report: please help','reporter retains private report');
select is(public.list_commitment_follow_reports_v1()->'cases'->0->>'case_id',pg_temp.id('case')::text,'reporter can rediscover case after losing local receipt');
select throws_ok('select public.list_commitment_follow_reports_v1(51)','22023',null,'report discovery is bounded');
select pg_temp.login(1);
select throws_ok('select public.get_commitment_follow_report_v1(pg_temp.id(''case''))','42501',null,'reported peer cannot read case');
select is(public.list_commitment_follow_reports_v1()->'cases','[]'::jsonb,'reported peer cannot discover private cases');
select is(pg_temp.invite(20),(select value from saved where name='invite'),'gate-off invite recovery');
select lives_ok('select public.end_commitment_follow_v1(pg_temp.req(30),pg_temp.id(''follow''),''revoke'')','gate-off owner revocation');
select pg_temp.login(2);
select is(public.get_commitment_follow_v1(pg_temp.id('follow'))->'access_allowed','false'::jsonb,'revocation clears shared projection');
select is(public.get_commitment_follow_v1(pg_temp.id('follow'))->'cards','[]'::jsonb,'revoked read contains no cached cards');
select ok(not(public.get_commitment_follow_v1(pg_temp.id('follow')) ? 'goal'),'revoked read contains no goal');
select is(public.respond_commitment_follow_v1(pg_temp.req(21),pg_temp.id('follow'),true),(select value from saved where name='accept'),'post-revocation exact receipt is only own past action');
select is(public.get_commitment_follow_v1(pg_temp.id('follow'))->'access_allowed','false'::jsonb,'exact acceptance never reactivates grant');
reset role;
select public.set_commitment_following_enabled_v1(true);
select throws_ok('select public.set_commitment_follow_support_v1(pg_temp.id(''case''),pg_temp.actor(1),now()+interval ''1 day'')','42501',null,'owner cannot be support operator');
select throws_ok('select public.set_commitment_follow_support_v1(pg_temp.id(''case''),pg_temp.actor(2),now()+interval ''1 day'')','42501',null,'reporter cannot be support operator');
select public.set_commitment_follow_support_v1(pg_temp.id('case'),pg_temp.actor(5),now()+interval '1 day');
select pg_temp.login(4);
set local role authenticated;
select throws_ok('select public.read_commitment_follow_support_v1(pg_temp.id(''case''))','42501',null,'unassigned operator denied');
select pg_temp.login(5);
insert into saved values('support',public.read_commitment_follow_support_v1(pg_temp.id('case')));
select is((select value->>'note' from saved where name='support'),'PRIVATE report: please help','assigned operator sees only submitted report');
select ok(not((select value::text from saved where name='support') ~ 'target_seconds|5:59|owner_id|follower_id|terms|proof'),'support assignment exposes no commitment or proof');
select throws_ok('select public.get_commitment_progress_v1(pg_temp.id(''main''))','42501',null,'support assignment confers no progress access');
insert into saved values('resolution',public.resolve_commitment_follow_support_v1(pg_temp.req(31),pg_temp.id('case'),'guidance_recorded'));
select is(public.resolve_commitment_follow_support_v1(pg_temp.req(31),pg_temp.id('case'),'guidance_recorded'),(select value from saved where name='resolution'),'support exact resolution recovery');
select throws_ok('select public.resolve_commitment_follow_support_v1(pg_temp.req(32),pg_temp.id(''case''),''no_action'')','22023',null,'recorded resolution immutable');
reset role;
select is((select count(*) from app.performance_following_audit where kind='support_read' and subject_id=pg_temp.id('case')),1::bigint,'support read audited');
select public.set_commitment_follow_support_v1(pg_temp.id('case'),pg_temp.actor(5),null);
set local role authenticated;
select throws_ok('select public.read_commitment_follow_support_v1(pg_temp.id(''case''))','42501',null,'revoked support assignment denied');
select pg_temp.login(2);
select is(public.get_commitment_follow_report_v1(pg_temp.id('case'))->>'resolution','guidance_recorded','reporter sees resolution without other case data');
select pg_temp.login(1);
insert into saved values('new_follow',jsonb_build_array(pg_temp.invite(33)->>'follow_id'));
select pg_temp.login(2);
select lives_ok('select public.respond_commitment_follow_v1(pg_temp.req(34),pg_temp.id(''new_follow''),true)','regrant needs fresh follower consent');
select lives_ok('select public.block_commitment_follow_v1(pg_temp.req(35),pg_temp.id(''new_follow''))','dedicated exact block works');
select is(public.get_commitment_follow_v1(pg_temp.id('new_follow'))->'access_allowed','false'::jsonb,'block removes follower access');
select lives_ok('select public.report_commitment_follow_v1(pg_temp.req(36),pg_temp.id(''new_follow''),''support'',''Help after blocking'')','reporting available after block');
delete from public.blocks where blocker_id=pg_temp.actor(2) and blocked_id=pg_temp.actor(1);
reset role;
insert into public.friendships(user_a,user_b,requested_by,status) values(pg_temp.actor(1),pg_temp.actor(2),pg_temp.actor(1),'accepted');
set local role authenticated;
select is(public.get_commitment_follow_v1(pg_temp.id('new_follow'))->'access_allowed','false'::jsonb,'unblock and renewed friendship cannot restore old permission');
select pg_temp.login(1);
insert into saved values('third_follow',jsonb_build_array(pg_temp.invite(37,3)->>'follow_id'));
select pg_temp.login(3);
select lives_ok('select public.respond_commitment_follow_v1(pg_temp.req(38),pg_temp.id(''third_follow''),false)','follower can decline');
select pg_temp.login(1);
insert into saved values('fourth_follow',jsonb_build_array(pg_temp.invite(39,3)->>'follow_id'));
select pg_temp.login(3);
select lives_ok('select public.respond_commitment_follow_v1(pg_temp.req(40),pg_temp.id(''fourth_follow''),true)','fresh invitation accepted');
select lives_ok('select public.end_commitment_follow_v1(pg_temp.req(41),pg_temp.id(''fourth_follow''),''unfollow'')','follower independently unfollows');
select pg_temp.login(1);
insert into saved values('fifth_follow',jsonb_build_array(pg_temp.invite(42,3)->>'follow_id'));
reset role;
update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id=pg_temp.req(1);
set local role authenticated;
select throws_ok('select public.get_commitment_publications_v1(pg_temp.id(''main''))','42501',null,'expired session cannot read');
select throws_ok('select pg_temp.invite(20)','42501',null,'expired session cannot recover');
reset role;
update auth.sessions set not_after=null where id=pg_temp.req(1);
select public.set_commitment_attempts_enabled_v1(true);
select is(public.get_commitment_attempt_snapshot_v1(pg_temp.id('main')) #- '{agreement,server_now}',(select value from saved where name='snapshot'),'all social actions leave complete evaluator snapshot unchanged');
select is((select count(*) from app.performance_commitment_enrollments where commitment_id=pg_temp.id('main') and released_at is null),1::bigint,'following and support never release commitment slot');
select throws_ok('update app.performance_following_publications set card=''{}''','23001',null,'published snapshots immutable');
select throws_ok('update app.performance_following_grants set scope=''changed''','23001',null,'sharing consent immutable');
select throws_ok('delete from app.performance_following_requests','23001',null,'exact receipts retained');
select throws_ok('truncate app.performance_following_cases','0A000',null,'report retention cannot truncate through foreign keys');
select throws_ok('truncate app.performance_following_retention','23001',null,'following hold cannot truncate');
select lives_ok('select * from app.run_raw_evidence_retention(''2030-01-01Z'',500)','legacy purge remains separate');
select is((select count(*) from app.performance_following_cases),2::bigint,'legacy purge preserves reports');
-- Expired invitations cannot be accepted or revived by a read. This direct
-- fictional fixture exercises the public boundary without sleeping seven days.
insert into app.performance_following_grants(commitment_id,owner_id,follower_id,scope,status,created_at,expires_at)
 values(pg_temp.id('main'),pg_temp.actor(1),pg_temp.actor(2),'goal_and_selected_progress_v1','pending',
 clock_timestamp()-interval '8 days',clock_timestamp()-interval '1 microsecond') returning id as expired_id \gset
insert into saved values('expired',jsonb_build_array(:'expired_id'::uuid));
select pg_temp.login(2);
set local role authenticated;
select is(public.get_commitment_follow_v1(pg_temp.id('expired'))->'access_allowed','false'::jsonb,'expired invitation read has no content');
select throws_ok('select public.respond_commitment_follow_v1(pg_temp.req(60),pg_temp.id(''expired''),true)','22023',null,'expired invitation cannot be accepted');
reset role;
select pg_temp.login(1);
set local role authenticated;
insert into saved values('sixth_follow',jsonb_build_array(pg_temp.invite(61,2)->>'follow_id'));
select is((select value->>0 is not null from saved where name='sixth_follow'),true,'new request expires old pending invite and issues fresh consent');
reset role;
-- Admission bounds do not prevent revocation, reporting or existing recovery.
insert into auth.users(id) select pg_temp.actor(n) from generate_series(10,40) n;
insert into public.profiles(id,handle,display_name,timezone)
 select pg_temp.actor(n),'followingcapacity'||n,'Fictional Runner','UTC' from generate_series(10,40) n;
insert into public.friendships(user_a,user_b,requested_by,status)
 select pg_temp.actor(1),pg_temp.actor(n),pg_temp.actor(1),'accepted' from generate_series(10,40) n;
set local role authenticated;
select public.end_commitment_follow_v1(pg_temp.req(62),pg_temp.id('sixth_follow'),'revoke');
select pg_temp.invite(100+n,n) from generate_series(10,40) n;
select throws_ok('select pg_temp.invite(200,2)','54000',null,'33rd open following invitation rejected');
select is(pg_temp.invite(20),(select value from saved where name='invite'),'capacity never prevents exact recovery');
reset role;
update app.performance_following_grants set status='revoked',ended_at=clock_timestamp(),revision=revision+1
 where status in ('pending','active') and id<>pg_temp.id('fifth_follow');
select throws_ok('update app.performance_following_grants set status=''pending'',ended_at=null,revision=revision+1 where id=pg_temp.id(''follow'')',
 '23001',null,'even privileged mutation cannot revive ended consent');
insert into app.performance_following_grants(commitment_id,owner_id,follower_id,scope,status,created_at,expires_at,ended_at)
 select pg_temp.id('main'),pg_temp.actor(1),pg_temp.actor(2),'goal_and_selected_progress_v1','declined',
 clock_timestamp()-interval '1 day',clock_timestamp()+interval '6 days',clock_timestamp()
 from generate_series(1,128-(select count(*)::integer from app.performance_following_grants where commitment_id=pg_temp.id('main')));
set local role authenticated;
select throws_ok('select pg_temp.invite(201,2)','54000',null,'129th historical invitation rejected');
select lives_ok('select public.end_commitment_follow_v1(pg_temp.req(202),pg_temp.id(''follow''),''revoke'')','full invitation history allows safe revocation');
reset role;
select public.delete_account(pg_temp.actor(3));
select is((select status from app.performance_following_grants where id=pg_temp.id('fifth_follow')),'revoked','follower deletion ends pending follow');
set local role authenticated;
select lives_ok('select public.report_commitment_follow_v1(pg_temp.req(43),pg_temp.id(''fifth_follow''),''support'',''Help after peer deletion'')','active owner can report after peer deletion');
select lives_ok('select public.close_performance_commitment_v1(pg_temp.req(44),pg_temp.id(''main''),''withdrawal'')','safe closure remains available');
select lives_ok('select public.get_commitment_publications_v1(pg_temp.id(''main''))','owner retains own publications after closure');
reset role;
select public.delete_account(pg_temp.actor(1));
select pg_temp.login(2);
set local role authenticated;
select is(public.get_commitment_follow_v1(pg_temp.id('new_follow'))->'access_allowed','false'::jsonb,'owner deletion leaves no follower content');
select lives_ok('select public.get_commitment_follow_report_v1(pg_temp.id(''case''))','reporter retains own receipt after owner deletion');
select pg_temp.login(1);
select throws_ok('select pg_temp.invite(20)','42501',null,'deleted owner loses exact recovery');
reset role;
select is((select count(*) from app.performance_following_retention where commitment_id=pg_temp.id('main')),1::bigint,'separate following hold survives closure and deletion');
select is((select count(*) from app.performance_following_publications where commitment_id=pg_temp.id('main')),2::bigint,'selected snapshots retained privately after deletion');
select * from finish();
rollback;
