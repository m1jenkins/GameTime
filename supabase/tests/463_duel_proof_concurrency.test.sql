-- Real independent transactions; pg_blocking_pids proves each competing call
-- waited. Only fictional d7/d8 records are committed and then cleaned up.
begin;
select no_plan();
create function pg_temp.actor(n integer) returns uuid language sql immutable as $$
  select ('d7000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid;
$$;
create function pg_temp.req(n integer) returns uuid language sql immutable as $$
  select ('d8000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid;
$$;
select extensions.dblink_connect('proof_setup','host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres');
select extensions.dblink_connect('proof_one','host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres application_name=proof_race_one');
select extensions.dblink_connect('proof_two','host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres application_name=proof_race_two');
select extensions.dblink_exec('proof_setup',$setup$
  insert into auth.users(id) select ('d7000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid from generate_series(1,40) n;
  insert into public.profiles(id,handle,display_name,timezone)
    select id,'proofrace'||right(id::text,4),'Fictional Reviewer Race','UTC' from auth.users where id::text like 'd7000000-%';
  insert into auth.sessions(id,user_id)
    select ('d8000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
      ('d7000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid from generate_series(1,40) n;
  insert into public.friendships(user_a,user_b,requested_by,status)
    select a.id,b.id,a.id,'accepted' from public.profiles a cross join public.profiles b
    where a.id::text like 'd7000000-%' and b.id::text like 'd7000000-%' and a.id<b.id;
  create function pg_temp.prepare(n integer,ends timestamptz,capture_at timestamptz default null) returns void language plpgsql as $fn$
  declare a uuid:=('d7000000-0000-0000-0000-'||lpad((2*n-1)::text,12,'0'))::uuid;
    b uuid:=('d7000000-0000-0000-0000-'||lpad((2*n)::text,12,'0'))::uuid;
    e uuid:=('d8000000-0000-0000-0000-'||lpad((1000+n)::text,12,'0'))::uuid;
    s uuid:=('d8000000-0000-0000-0000-'||lpad((2000+n)::text,12,'0'))::uuid;
    c uuid; reviewer uuid; d jsonb;
  begin
    perform public.curate_duel_fixture_event_v1(e,ends-interval '2 hours',ends,'UTC');
    perform set_config('request.jwt.claim.sub',a::text,true);
    c:=app.create_duel_at_v1(e,b,e,'duel-fixture-5k-v1',true,ends-interval '2 days');
    perform set_config('request.jwt.claim.sub',b::text,true);
    perform app.respond_duel_at_v1('accept_duel_v1',s,c,'duel-fixture-5k-v1',
      (select terms_digest from public.duel_challenges where id=c),ends-interval '1 day');
    for i in 39..40 loop
      reviewer:=('d7000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid;
      perform public.set_duel_proof_reviewer_v1(
        ('d8000000-0000-0000-0000-'||lpad((n*100+i)::text,12,'0'))::uuid,c,reviewer,true);
    end loop;
    d:=jsonb_build_object('eventId',e,'course','fixture_course_5k_v1','wave','fixture_common_wave_v1',
      'distanceMeters',5000,'timingBasis','organizer_chip','precisionSeconds',1,'rows',jsonb_build_array(
        jsonb_build_object('actorId',a,'mappedBib','fictional-bib-11','publishedBib','fictional-bib-11','status','finished','chipSeconds',1200),
        jsonb_build_object('actorId',b,'mappedBib','fictional-bib-22','publishedBib','fictional-bib-22','status','finished','chipSeconds',1250)));
    if capture_at is null then perform public.capture_duel_proof_fixture_v1(s,c,d);
    else perform app.duel_proof_capture_at_v1(s,c,d,capture_at); end if;
  end; $fn$;
  do $do$ begin
    perform public.set_duel_admission_v1(true,array(select id from public.profiles where id::text like 'd7000000-%'));
    perform public.set_duel_proof_enabled_v1(true);
    for n in 1..11 loop perform pg_temp.prepare(n,clock_timestamp()-interval '1 day'); end loop;
  end; $do$;
$setup$);

do $$ declare conn text; begin
  foreach conn in array array['proof_one','proof_two'] loop
    perform extensions.dblink_exec(conn,$install$
      create function pg_temp.action(p jsonb) returns text language plpgsql security definer set search_path='' as $fn$
      declare n integer:=(p->>'pair')::integer;
        a uuid:=('d7000000-0000-0000-0000-'||lpad((2*n-1)::text,12,'0'))::uuid;
        reviewer uuid:=('d7000000-0000-0000-0000-'||lpad(coalesce(p->>'reviewer','39'),12,'0'))::uuid;
        r uuid:=('d8000000-0000-0000-0000-'||lpad(p->>'request',12,'0'))::uuid;
        s uuid:=('d8000000-0000-0000-0000-'||lpad((2000+n)::text,12,'0'))::uuid;
        c public.duel_challenges; verdict jsonb; t timestamptz:=(p->>'at')::timestamptz;
      begin
        select * into c from public.duel_challenges where creator_id=a;
        verdict:=jsonb_build_array(jsonb_build_object('actorId',c.creator_id,'identityConfirmed',true),
          jsonb_build_object('actorId',c.invitee_id,'identityConfirmed',true));
        if p->>'op'='submit' then
          if t is null then return public.submit_duel_proof_v1(r,c.id,s,coalesce((p->>'revision')::integer,0),verdict)::text; end if;
          return app.duel_proof_append_at_v1(r,c.id,s,coalesce((p->>'revision')::integer,0),verdict,t)::text;
        elsif p->>'op'='revoke' then
          perform public.set_duel_proof_reviewer_v1(r,c.id,reviewer,false); return 'revoked';
        elsif p->>'op'='delete' then perform public.delete_account(a); return 'deleted';
        elsif p->>'op'='delete_reviewer' then perform public.delete_account(reviewer); return 'deleted';
        elsif p->>'op'='gate_off' then perform public.set_duel_proof_enabled_v1(false); return 'disabled';
        elsif p->>'op'='read' then perform public.get_duel_proof_source_v1(c.id,s); return 'read';
        elsif p->>'op'='lock' then perform 1 from public.profiles where id=a for update; return 'locked';
        end if;
        raise exception 'unknown race operation';
      exception when others then return sqlstate;
      end; $fn$;
    $install$);
  end loop;
end; $$;
create function pg_temp.query(p jsonb) returns text language sql as $$
  select format('select pg_temp.action(%L::jsonb)',p::text);
$$;
create function pg_temp.start_session(conn text,actor integer,service boolean) returns void language plpgsql as $$
begin
  perform extensions.dblink_exec(conn,format('begin; set local statement_timeout=''8s''; set local role %I;
    set local request.jwt.claim.sub=%L; set local request.jwt.claims=%L',
    case when service then 'service_role' else 'authenticated' end,pg_temp.actor(actor)::text,
    jsonb_build_object('sub',pg_temp.actor(actor),'session_id',pg_temp.req(actor),'role','authenticated')::text));
end; $$;
create function pg_temp.race(first_action jsonb,second_action jsonb,a integer default 39,b integer default 40,
  first_service boolean default false,second_service boolean default false,wait_until timestamptz default null)
returns table(first_result text,second_result text,blocked boolean) language plpgsql as $$
declare deadline timestamptz:=clock_timestamp()+interval '4 seconds';
begin
  perform pg_temp.start_session('proof_one',a,first_service);
  perform pg_temp.start_session('proof_two',b,second_service);
  select x.result into first_result from extensions.dblink('proof_one',pg_temp.query(first_action)) x(result text);
  perform extensions.dblink_send_query('proof_two',pg_temp.query(second_action));
  blocked:=false;
  loop
    perform pg_stat_clear_snapshot();
    select exists(select 1 from pg_stat_activity where application_name='proof_race_two'
      and cardinality(pg_blocking_pids(pid))>0) into blocked;
    exit when blocked or clock_timestamp()>=deadline;
    perform pg_sleep(0.01);
  end loop;
  if wait_until is not null then
    while clock_timestamp()<wait_until loop perform pg_sleep(0.01); end loop;
  end if;
  perform extensions.dblink_exec('proof_one','commit');
  select x.result into second_result from extensions.dblink_get_result('proof_two') x(result text);
  perform * from extensions.dblink_get_result('proof_two') x(result text);
  perform extensions.dblink_exec('proof_two','commit');
  return next;
end; $$;
create temp table outcomes(name text,first_result text,second_result text,blocked boolean);
insert into outcomes select 'competing initial',* from pg_temp.race(
  '{"op":"submit","pair":1,"request":3001}','{"op":"submit","pair":1,"request":3002}');
insert into outcomes select 'same exact request',* from pg_temp.race(
  '{"op":"submit","pair":2,"request":3003}','{"op":"submit","pair":2,"request":3003}',39,39);
insert into outcomes select 'changed request payload',* from pg_temp.race(
  '{"op":"submit","pair":3,"request":3004}','{"op":"submit","pair":3,"request":3004,"revision":1}',39,39);
insert into outcomes select 'competing corrections',* from pg_temp.race(
  '{"op":"submit","pair":1,"request":3005,"revision":1}','{"op":"submit","pair":1,"request":3006,"revision":1}',40,39);
insert into outcomes select 'revoke then submit',* from pg_temp.race(
  '{"op":"revoke","pair":4,"request":3007,"reviewer":39}','{"op":"submit","pair":4,"request":3008}',1,39,true,false);
insert into outcomes select 'submit then revoke',* from pg_temp.race(
  '{"op":"submit","pair":5,"request":3009}','{"op":"revoke","pair":5,"request":3010,"reviewer":39}',39,1,false,true);
insert into outcomes select 'revoke then read',* from pg_temp.race(
  '{"op":"revoke","pair":6,"request":3011,"reviewer":39}','{"op":"read","pair":6}',1,39,true,false);
insert into outcomes select 'delete then submit',* from pg_temp.race(
  '{"op":"delete","pair":7}','{"op":"submit","pair":7,"request":3012}',1,39,true,false);
insert into outcomes select 'submit then delete',* from pg_temp.race(
  '{"op":"submit","pair":8,"request":3013}','{"op":"delete","pair":8}',39,1,false,true);
select is((select second_result from outcomes where name='competing initial'),'40001','one initial revision wins after lock wait');
select is((select second_result from outcomes where name='same exact request'),'1','concurrent retry returns original receipt');
select is((select second_result from outcomes where name='changed request payload'),'22023','same key changed payload rejected after wait');
select is((select second_result from outcomes where name='competing corrections'),'40001','concurrent correction has one authoritative successor');
select is((select second_result from outcomes where name='revoke then submit'),'42501','waiting proof sees fresh server-owned revocation');
select is((select second_result from outcomes where name='submit then revoke'),'revoked','revocation follows committed proof without rewriting it');
select is((select second_result from outcomes where name='revoke then read'),'42501','waiting raw read sees fresh revocation');
select is((select second_result from outcomes where name='delete then submit'),'42501','waiting proof cannot bypass participant deletion');
select is((select second_result from outcomes where name='submit then delete'),'deleted','deletion follows committed proof without deadlock');
select is((select count(*) from app.duel_proof_revisions r join public.duel_challenges c on c.id=r.challenge_id
  where c.creator_id=pg_temp.actor(15)),1::bigint,'proof committed before deletion remains retained');
select is((select count(*) from app.duel_proof_revisions r join public.duel_challenges c on c.id=r.challenge_id
  where c.creator_id=pg_temp.actor(1)),2::bigint,'competing corrections retain exactly revisions one and two');

-- A public call begins before cutoff and waits past it; no injected clock.
select extensions.dblink_exec('proof_setup',$setup$
  do $do$ begin perform pg_temp.prepare(12,clock_timestamp()-interval '72 hours'+interval '2 seconds'); end; $do$;
$setup$);
insert into outcomes select 'wait past cutoff',r.* from public.duel_challenges c cross join lateral pg_temp.race(
  '{"op":"lock","pair":12}','{"op":"submit","pair":12,"request":3014}',1,39,true,false,
  (c.terms->>'results_due_at')::timestamptz+interval '10 milliseconds') r where c.creator_id=pg_temp.actor(23);
select is((select second_result from outcomes where name='wait past cutoff'),'55000','public proof samples time after waiting past cutoff');
select is((select count(*) from app.duel_proof_revisions r join public.duel_challenges c on c.id=r.challenge_id
  where c.creator_id=pg_temp.actor(23)),0::bigint,'capturing earlier does not admit a late review');

-- Initial proof was admitted on time; a public correction waits past hard cap.
select extensions.dblink_exec('proof_setup',$setup$
  do $do$ declare e timestamptz:=clock_timestamp()-interval '720 hours'+interval '2 seconds';
  begin perform pg_temp.prepare(13,e,e+interval '30 minutes'); end; $do$;
$setup$);
select pg_temp.start_session('proof_one',39,false);
select result from public.duel_challenges c cross join lateral extensions.dblink('proof_one',pg_temp.query(
  jsonb_build_object('op','submit','pair',13,'request',3017,'at',(c.terms->'event'->>'ends_at')::timestamptz+interval '1 hour'))) x(result text)
  where c.creator_id=pg_temp.actor(25);
select extensions.dblink_exec('proof_one','commit');
insert into outcomes select 'wait past cap',r.* from public.duel_challenges c cross join lateral pg_temp.race(
  '{"op":"lock","pair":13}','{"op":"submit","pair":13,"request":3018,"revision":1}',1,39,true,false,
  (c.terms->>'finality_due_at')::timestamptz+interval '10 milliseconds') r where c.creator_id=pg_temp.actor(25);
select is((select second_result from outcomes where name='wait past cap'),'55000','public correction samples time after waiting past hard cap');
select is((select count(*) from app.duel_proof_revisions r join public.duel_challenges c on c.id=r.challenge_id
  where c.creator_id=pg_temp.actor(25)),1::bigint,'hard cap preserves only the admitted first revision');

insert into outcomes select 'gate then submit',* from pg_temp.race(
  '{"op":"gate_off","pair":9}','{"op":"submit","pair":9,"request":3015}',1,39,true,false);
select is((select second_result from outcomes where name='gate then submit'),'42501','gate-off blocks a waiting new proof');
select extensions.dblink_exec('proof_setup','do $do$ begin perform public.set_duel_proof_enabled_v1(true); end; $do$;');
insert into outcomes select 'delete reviewer then submit',* from pg_temp.race(
  '{"op":"delete_reviewer","pair":10,"reviewer":40}','{"op":"submit","pair":10,"request":3016}',1,40,true,false);
select is((select second_result from outcomes where name='delete reviewer then submit'),'42501','stale reviewer session loses to deletion');

select ok(blocked,name||': competing session demonstrably waited') from outcomes order by name;
select ok(first_result in ('1','2','revoked','deleted','disabled','locked'),name||': first operation succeeded') from outcomes order by name;
select is((select count(*) from app.duel_proof_revisions r join public.duel_challenges c on c.id=r.challenge_id
  where c.creator_id::text like 'd7000000-%' and jsonb_array_length(r.records)<>2),0::bigint,'every committed revision contains the complete pair');

select extensions.dblink_exec('proof_setup',$cleanup$
  set session_replication_role=replica;
  -- Retain control audit entries: they are actual service gate changes and
  -- must not be confused with unrelated audit history during scoped cleanup.
  delete from app.duel_proof_access_audit where reviewer_id::text like 'd7000000-%';
  delete from app.duel_proof_revisions where reviewer_id::text like 'd7000000-%';
  delete from app.duel_proof_sources where id::text like 'd8000000-%';
  delete from app.duel_proof_grants where reviewer_id::text like 'd7000000-%';
  update app.duel_proof_runtime set enabled=false;
  delete from app.duel_requests where actor_id::text like 'd7000000-%';
  delete from app.duel_enrollments where actor_id::text like 'd7000000-%';
  delete from public.duel_participants where actor_id::text like 'd7000000-%';
  delete from public.duel_challenges where creator_id::text like 'd7000000-%';
  delete from public.duel_event_fixtures where id::text like 'd8000000-%';
  delete from app.duel_beta_allowlist where actor_id::text like 'd7000000-%';
  update app.duel_runtime set admission_enabled=false;
  delete from public.friendships where user_a::text like 'd7000000-%' or user_b::text like 'd7000000-%';
  delete from app.profile_handle_claims where actor_id::text like 'd7000000-%';
  delete from app.active_profile_auth_bindings where actor_id::text like 'd7000000-%';
  delete from public.profiles where id::text like 'd7000000-%';
  delete from auth.sessions where user_id::text like 'd7000000-%';
  delete from auth.users where id::text like 'd7000000-%';
  set session_replication_role=origin;
$cleanup$);
select extensions.dblink_disconnect('proof_one');
select extensions.dblink_disconnect('proof_two');
select extensions.dblink_disconnect('proof_setup');
select * from finish();
rollback;
