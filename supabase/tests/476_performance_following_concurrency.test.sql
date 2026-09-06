-- Real independent PostgreSQL transactions; each race must observe a lock wait.
begin;
select no_plan();
select extensions.dblink_connect('pf_setup','host='||host(inet_server_addr())||' port=5432 dbname=postgres user=postgres password=postgres');
select extensions.dblink_connect('pf_one','host='||host(inet_server_addr())||' port=5432 dbname=postgres user=postgres password=postgres application_name=pf_race_one');
select extensions.dblink_connect('pf_two','host='||host(inet_server_addr())||' port=5432 dbname=postgres user=postgres password=postgres application_name=pf_race_two');
create function pg_temp.actor(n integer) returns uuid language sql immutable as $$select ('ea100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.req(n integer) returns uuid language sql immutable as $$select ('ea200000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid$$;
create temp table saved(name text primary key,id uuid);
create function pg_temp.id(n text) returns uuid language sql as $$select id from saved where name=n$$;
select extensions.dblink_exec('pf_setup',$setup$
begin;
insert into auth.users(id) select ('ea100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid from generate_series(1,6) n;
insert into public.profiles(id,handle,display_name,timezone)
 select ('ea100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'pfrace'||n,'Fictional Runner','UTC' from generate_series(1,6) n;
insert into auth.sessions(id,user_id) select ('ea200000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
 ('ea100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid from generate_series(1,6) n;
insert into public.friendships(user_a,user_b,requested_by,status)
 select 'ea100000-0000-0000-0000-000000000001',('ea100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
 'ea100000-0000-0000-0000-000000000001','accepted' from generate_series(2,5) n;
create temp table pf_ids(name text primary key,id uuid);
create function pg_temp.setup() returns void language plpgsql security definer set search_path='' as $fn$
declare c uuid; f uuid; pub uuid; k uuid; s timestamptz:=clock_timestamp()-interval '9 days'; d timestamptz; t jsonb;
begin
 d:=s+interval '60 days';
 t:=app.performance_commitment_terms_v1(auth.uid(),360,s,d,'UTC','performance-commitment-fixture-5k-v1');
 c:=app.create_performance_commitment_at_v1('ea200000-0000-0000-0000-000000000010',360,s,d,'UTC','performance-commitment-fixture-5k-v1',
   encode(extensions.digest(t::text,'sha256'),'hex'),true,s-interval '1 day');
 insert into pg_temp.pf_ids values('main',c);
 perform public.create_commitment_milestone_v1('ea200000-0000-0000-0000-000000000011',c,'Selected plan',s+interval '20 days');
 perform public.record_commitment_progress_v1('ea200000-0000-0000-0000-000000000012',c,'PRIVATE note',s+interval '1 day');
 pub:=(public.publish_commitment_progress_v1('ea200000-0000-0000-0000-000000000013',c,1)->>'publication_id')::uuid;
 insert into pg_temp.pf_ids values('publication',pub);
 pub:=(public.publish_commitment_progress_v1('ea200000-0000-0000-0000-000000000014',c,2)->>'publication_id')::uuid;
 insert into pg_temp.pf_ids values('note',pub);
 f:=(public.invite_commitment_follower_v1('ea200000-0000-0000-0000-000000000015',c,'ea100000-0000-0000-0000-000000000002','goal_and_selected_progress_v1',true)->>'follow_id')::uuid;
 insert into pg_temp.pf_ids values('follow',f);
 perform set_config('request.jwt.claim.sub','ea100000-0000-0000-0000-000000000002',true);
 perform set_config('request.jwt.claims','{"sub":"ea100000-0000-0000-0000-000000000002","role":"authenticated","session_id":"ea200000-0000-0000-0000-000000000002"}',true);
 perform public.respond_commitment_follow_v1('ea200000-0000-0000-0000-000000000016',f,true);
 k:=(public.report_commitment_follow_v1('ea200000-0000-0000-0000-000000000017',f,'privacy','Fictional support request')->>'case_id')::uuid;
 insert into pg_temp.pf_ids values('case',k);
end; $fn$;
do $fn$ begin
 perform public.set_performance_commitment_admission_v1(true,array['ea100000-0000-0000-0000-000000000001'::uuid]);
 perform public.set_commitment_progress_enabled_v1(true);
 perform public.set_commitment_following_enabled_v1(true);
end; $fn$;
set local request.jwt.claim.sub='ea100000-0000-0000-0000-000000000001';
set local request.jwt.claims='{"sub":"ea100000-0000-0000-0000-000000000001","role":"authenticated","session_id":"ea200000-0000-0000-0000-000000000001"}';
set local role authenticated;
do $fn$ begin perform pg_temp.setup(); end; $fn$;
reset role;
do $fn$ begin perform public.set_commitment_follow_support_v1((select id from pf_ids where name='case'),
 'ea100000-0000-0000-0000-000000000006',clock_timestamp()+interval '1 day'); end; $fn$;
commit;
$setup$);
insert into saved select name,id from extensions.dblink('pf_setup','select name,id from pf_ids') x(name text,id uuid);
do $install$ declare connection text; begin
 foreach connection in array array['pf_one','pf_two','pf_setup'] loop
 perform extensions.dblink_exec(connection,$sql$create function pg_temp.action(n integer,q text) returns text language plpgsql as $fn$
 declare r text; begin
  perform set_config('request.jwt.claim.sub',('ea100000-0000-0000-0000-'||lpad(n::text,12,'0')),true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',('ea100000-0000-0000-0000-'||lpad(n::text,12,'0')),
   'session_id',('ea200000-0000-0000-0000-'||lpad(n::text,12,'0')),'role','authenticated')::text,true);
  perform set_config('role','authenticated',true);
  begin execute q into r; exception when others then r:=SQLSTATE; end;
  perform set_config('role','none',true); return r;
 end; $fn$;$sql$);
 end loop;
end; $install$;
create function pg_temp.race(first_sql text,second_sql text,hold_seconds double precision default 0)
returns table(first_result text,second_result text,blocked boolean) language plpgsql as $$
declare deadline timestamptz:=clock_timestamp()+interval '4 seconds';
begin
 perform extensions.dblink_exec('pf_one','begin; set local statement_timeout=''8s''');
 perform extensions.dblink_exec('pf_two','begin; set local statement_timeout=''8s''');
 select x.r into first_result from extensions.dblink('pf_one',first_sql) x(r text);
 perform extensions.dblink_send_query('pf_two',second_sql);
 loop
  perform pg_stat_clear_snapshot();
  select exists(select 1 from pg_stat_activity where application_name='pf_race_two' and cardinality(pg_blocking_pids(pid))>0) into blocked;
  exit when blocked or clock_timestamp()>=deadline;
  perform pg_sleep(0.01);
 end loop;
 perform pg_sleep(hold_seconds);
 perform extensions.dblink_exec('pf_one','commit');
 select x.r into second_result from extensions.dblink_get_result('pf_two') x(r text);
 perform * from extensions.dblink_get_result('pf_two') x(r text);
 perform extensions.dblink_exec('pf_two','commit');
 return next;
end; $$;
create function pg_temp.query(actor integer,q text) returns text language sql as $$select format('select pg_temp.action(%s,%L)',actor,q)$$;
create function pg_temp.invite(q integer,friend integer) returns text language sql as $$
 select pg_temp.query(1,format('select public.invite_commitment_follower_v1(%L,%L,%L,''goal_and_selected_progress_v1'',true)->>''follow_id''',pg_temp.req(q),pg_temp.id('main'),pg_temp.actor(friend))) $$;
create function pg_temp.read_follow(actor integer default 2) returns text language sql as $$
 select pg_temp.query(actor,format('select public.get_commitment_follow_v1(%L)->>''access_allowed''',pg_temp.id('follow'))) $$;
create function pg_temp.end_follow(q integer) returns text language sql as $$
 select pg_temp.query(1,format('select public.end_commitment_follow_v1(%L,%L,''revoke'')->>''status''',pg_temp.req(q),pg_temp.id('follow'))) $$;
create function pg_temp.accept(q integer,actor integer default 2,f uuid default null) returns text language sql as $$
 select pg_temp.query(actor,format('select public.respond_commitment_follow_v1(%L,%L,true)::text',pg_temp.req(q),coalesce(f,pg_temp.id('follow')))) $$;
create function pg_temp.fresh_follow(q integer) returns void language plpgsql as $$ declare f uuid; begin
 select x.r::uuid into f from extensions.dblink('pf_setup',pg_temp.invite(q,2)) x(r text);
 update saved set id=f where name='follow';
 perform * from extensions.dblink('pf_setup',pg_temp.accept(q+1)) x(r text);
end; $$;
create temp table outcomes(name text,first_result text,second_result text,blocked boolean);
insert into outcomes select 'exact invitations',* from pg_temp.race(pg_temp.invite(30,3),pg_temp.invite(30,3));
select is(first_result,second_result,'concurrent invitations return same grant') from outcomes where name='exact invitations';
insert into saved select 'friend3',first_result::uuid from outcomes where name='exact invitations';
insert into outcomes select 'changed invitation payload',* from pg_temp.race(pg_temp.invite(31,4),pg_temp.invite(31,5));
select is((select second_result from outcomes where name='changed invitation payload'),'22023','changed friend loses exact request race');
insert into outcomes select 'exact acceptances',* from pg_temp.race(pg_temp.accept(32,3,pg_temp.id('friend3')),pg_temp.accept(32,3,pg_temp.id('friend3')));
select is(first_result,second_result,'concurrent acceptances return same receipt') from outcomes where name='exact acceptances';
insert into outcomes select 'revocation then read',* from pg_temp.race(pg_temp.end_follow(33),pg_temp.read_follow());
select is((select second_result from outcomes where name='revocation then read'),'false','waiting read loses shared content after revocation');
select pg_temp.fresh_follow(40);
insert into outcomes select 'read then revocation',* from pg_temp.race(pg_temp.read_follow(),pg_temp.end_follow(42));
select is((select first_result from outcomes where name='read then revocation'),'true','read already holding authorization finishes before revocation');
select is((select second_result from outcomes where name='read then revocation'),'revoked','revocation waits for in-flight read then commits');
select pg_temp.fresh_follow(43);
insert into outcomes select 'retraction then old page',* from pg_temp.race(
 pg_temp.query(1,format('select public.retract_commitment_progress_v1(%L,%L)::text',pg_temp.req(45),pg_temp.id('publication'))),
 pg_temp.query(2,format('select public.get_commitment_follow_v1(%L,1,1,2)::text',pg_temp.id('follow'))));
select is((select second_result from outcomes where name='retraction then old page'),'22023','waiting continuation must refresh after retraction');
insert into outcomes select 'shutdown then reaction',* from pg_temp.race('select public.set_commitment_following_enabled_v1(false)::text',
 pg_temp.query(2,format('select public.react_commitment_progress_v1(%L,%L,%L,''cheer'')::text',pg_temp.req(46),pg_temp.id('follow'),pg_temp.id('note'))));
select is((select second_result from outcomes where name='shutdown then reaction'),'42501','waiting reaction observes closed gate');
select x.r from extensions.dblink('pf_setup','select public.set_commitment_following_enabled_v1(true)::text') x(r text);
select extensions.dblink_exec('pf_setup','update auth.sessions set not_after=clock_timestamp()+interval ''0.5 seconds'' where user_id=''ea100000-0000-0000-0000-000000000002''');
insert into outcomes select 'natural session expiry',* from pg_temp.race('select singleton::text from app.performance_following_runtime for update',pg_temp.read_follow(),0.8);
select is((select second_result from outcomes where name='natural session expiry'),'42501','expiry is rechecked after runtime wait');
select extensions.dblink_exec('pf_setup','update auth.sessions set not_after=null where user_id=''ea100000-0000-0000-0000-000000000002''');
insert into outcomes select 'session revocation then recovery',* from pg_temp.race(
 format('with d as (delete from auth.sessions where user_id=%L returning id) select count(*)::text from d',pg_temp.actor(2)),pg_temp.accept(44));
select is((select second_result from outcomes where name='session revocation then recovery'),'42501','session revocation denies exact recovery');
select extensions.dblink_exec('pf_setup','insert into auth.sessions(id,user_id) values(''ea200000-0000-0000-0000-000000000002'',''ea100000-0000-0000-0000-000000000002'')');
insert into outcomes select 'support revoked then read',* from pg_temp.race(
 format('select public.set_commitment_follow_support_v1(%L,%L,null)::text',pg_temp.id('case'),pg_temp.actor(6)),
 pg_temp.query(6,format('select public.read_commitment_follow_support_v1(%L)::text',pg_temp.id('case'))));
select is((select second_result from outcomes where name='support revoked then read'),'42501','waiting operator loses revoked case access');
select x.r from extensions.dblink('pf_setup',format('select public.set_commitment_follow_support_v1(%L,%L,clock_timestamp()+interval ''0.5 seconds'')::text',pg_temp.id('case'),pg_temp.actor(6))) x(r text);
insert into outcomes select 'support natural expiry',* from pg_temp.race(
 format('select case_id::text from app.performance_following_support_grants where case_id=%L for update',pg_temp.id('case')),
 pg_temp.query(6,format('select public.read_commitment_follow_support_v1(%L)::text',pg_temp.id('case'))),0.8);
select is((select second_result from outcomes where name='support natural expiry'),'42501','support expiry rechecked after grant wait');
select x.r from extensions.dblink('pf_setup',format('select public.set_commitment_follow_support_v1(%L,%L,clock_timestamp()+interval ''1 day'')::text',pg_temp.id('case'),pg_temp.actor(6))) x(r text);
insert into outcomes select 'exact support resolution',* from pg_temp.race(
 pg_temp.query(6,format('select public.resolve_commitment_follow_support_v1(%L,%L,''no_action'')::text',pg_temp.req(47),pg_temp.id('case'))),
 pg_temp.query(6,format('select public.resolve_commitment_follow_support_v1(%L,%L,''no_action'')::text',pg_temp.req(47),pg_temp.id('case'))));
select is(first_result,second_result,'exact support resolution appends once') from outcomes where name='exact support resolution';
insert into outcomes select 'block then shared read',* from pg_temp.race(
 pg_temp.query(2,format('select public.block_commitment_follow_v1(%L,%L)::text',pg_temp.req(48),pg_temp.id('follow'))),pg_temp.read_follow(1));
select is((select second_result from outcomes where name='block then shared read'),'false','waiting read sees block');
select extensions.dblink_exec('pf_setup',$unblock$
delete from public.blocks where blocker_id='ea100000-0000-0000-0000-000000000002';
insert into public.friendships(user_a,user_b,requested_by,status) values('ea100000-0000-0000-0000-000000000001','ea100000-0000-0000-0000-000000000002','ea100000-0000-0000-0000-000000000001','accepted');
$unblock$);
select is((select x.r from extensions.dblink('pf_setup',pg_temp.read_follow()) x(r text)),'false','re-friending cannot restore an ended follow');
select pg_temp.fresh_follow(49);
insert into outcomes select 'unfriend then shared read',* from pg_temp.race(
 pg_temp.query(2,format('with d as (delete from public.friendships where user_a=%L and user_b=%L returning user_a) select count(*)::text from d',pg_temp.actor(1),pg_temp.actor(2))),pg_temp.read_follow(1));
select is((select second_result from outcomes where name='unfriend then shared read'),'false','raw legacy unfriend also serializes and revokes follow');
select extensions.dblink_exec('pf_setup',$refriend$
insert into public.friendships(user_a,user_b,requested_by,status) values('ea100000-0000-0000-0000-000000000001','ea100000-0000-0000-0000-000000000002','ea100000-0000-0000-0000-000000000001','accepted');
$refriend$);
select pg_temp.fresh_follow(51);
insert into outcomes select 'follower deletion then read',* from pg_temp.race(format('select public.delete_account(%L)::text',pg_temp.actor(2)),pg_temp.read_follow(1));
select is((select second_result from outcomes where name='follower deletion then read'),'false','follower deletion clears read for both parties');
insert into outcomes select 'owner withdrawal then reaction',* from pg_temp.race(
 pg_temp.query(1,format('select public.close_performance_commitment_v1(%L,%L,''withdrawal'')::text',pg_temp.req(53),pg_temp.id('main'))),
 pg_temp.query(3,format('select public.react_commitment_progress_v1(%L,%L,%L,''cheer'')::text',pg_temp.req(54),pg_temp.id('friend3'),pg_temp.id('note'))));
select is((select second_result from outcomes where name='owner withdrawal then reaction'),'42501','closure rejects waiting social write');
select ok(blocked,name||': observed lock wait') from outcomes order by name;
select is((select x.n from extensions.dblink('pf_setup','select count(*) from app.performance_following_grants where commitment_id=(select id from pf_ids where name=''main'') and status in (''pending'',''active'')') x(n bigint)),0::bigint,'closure leaves no open follows');
select is((select x.n from extensions.dblink('pf_setup','select count(*) from app.performance_following_reactions where follow_id in(select id from app.performance_following_grants where commitment_id=(select id from pf_ids where name=''main''))') x(n bigint)),0::bigint,'no denied race wrote a reaction');
-- Delete only this fictional namespace from this disposable test stack.
select extensions.dblink_exec('pf_setup',$cleanup$
begin;
set local session_replication_role=replica;
delete from app.performance_following_audit where actor_id::text like 'ea100000-%'
 or subject_id in (select id from app.performance_following_cases where follow_id in (select id from app.performance_following_grants where owner_id::text like 'ea100000-%'))
 or subject_id in (select id from app.performance_following_grants where owner_id::text like 'ea100000-%')
 or subject_id=(select id from pf_ids where name='main');
delete from app.performance_following_support_grants where operator_id::text like 'ea100000-%';
delete from app.performance_following_cases where reporter_id::text like 'ea100000-%';
delete from app.performance_following_reactions where follow_id in(select id from app.performance_following_grants where owner_id::text like 'ea100000-%');
delete from app.performance_following_requests where actor_id::text like 'ea100000-%';
delete from app.performance_following_grants where owner_id::text like 'ea100000-%';
delete from app.performance_following_publications where commitment_id=(select id from pf_ids where name='main');
delete from app.performance_following_content where commitment_id=(select id from pf_ids where name='main');
delete from app.performance_following_retention where commitment_id=(select id from pf_ids where name='main');
delete from app.performance_progress_requests where actor_id::text like 'ea100000-%';
delete from app.performance_progress_entries where commitment_id=(select id from pf_ids where name='main');
delete from app.performance_progress_milestones where commitment_id=(select id from pf_ids where name='main');
delete from app.performance_progress_retention where commitment_id=(select id from pf_ids where name='main');
delete from app.performance_commitment_requests where actor_id::text like 'ea100000-%';
delete from app.performance_commitment_enrollments where actor_id::text like 'ea100000-%';
delete from app.performance_commitment_consents where actor_id::text like 'ea100000-%';
delete from app.performance_commitment_agreements where actor_id::text like 'ea100000-%';
delete from app.performance_commitment_beta_allowlist where actor_id::text like 'ea100000-%';
update app.performance_commitment_runtime set admission_enabled=false;
update app.performance_progress_runtime set enabled=false;
update app.performance_following_runtime set enabled=false;
delete from app.profile_handle_claims where actor_id::text like 'ea100000-%';
delete from app.active_profile_auth_bindings where actor_id::text like 'ea100000-%';
delete from public.friendships where user_a::text like 'ea100000-%' or user_b::text like 'ea100000-%';
delete from public.blocks where blocker_id::text like 'ea100000-%' or blocked_id::text like 'ea100000-%';
delete from public.profiles where id::text like 'ea100000-%';
delete from auth.sessions where user_id::text like 'ea100000-%';
delete from auth.users where id::text like 'ea100000-%';
commit;
$cleanup$);
select extensions.dblink_disconnect('pf_one');
select extensions.dblink_disconnect('pf_two');
select extensions.dblink_disconnect('pf_setup');
select * from finish();
rollback;
