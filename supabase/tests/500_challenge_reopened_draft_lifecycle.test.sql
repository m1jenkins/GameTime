-- Actual command/exit-trigger/processing paths; fictional actors, rollback only.
begin;
select no_plan();
\ir fixtures/challenge-fixture.inc
create function pg_temp.beta_command(c uuid, op text, extra jsonb default '{}') returns jsonb
language sql security definer set search_path='' as $$
 select public.challenge_command_v1(extensions.gen_random_uuid(),jsonb_build_object('id',c,'op',op,'revision',(select revision from app.challenge_lobbies_v1 where id=c))||extra)
$$;
-- Two selected consenting participants and one unselected pending entrant.
create function pg_temp.redraft(first_actor integer, reopen boolean default true) returns uuid language plpgsql as $$
declare c uuid; i integer;begin
 perform pg_temp.login_beta(first_actor); c:=pg_temp.beta_create();
 perform pg_temp.beta_command(c,'target','{"target":10000}');
 for i in first_actor+1..first_actor+2 loop
  perform pg_temp.beta_command(c,'invite',jsonb_build_object('username','betafixture'||lpad(i::text,4,'0')));
 end loop;
 perform pg_temp.login_beta(first_actor+1);perform pg_temp.beta_command(c,'target','{"target":10001}');
 perform pg_temp.login_beta(first_actor);perform pg_temp.beta_command(c,'select',jsonb_build_object('actor_id',pg_temp.ba(first_actor+1),'selected',true));
 if reopen then
  perform pg_temp.beta_command(c,'freeze');
  for i in first_actor..first_actor+1 loop
   perform pg_temp.login_beta(i);perform pg_temp.beta_command(c,'consent',jsonb_build_object('consent',true,'digest',public.challenge_detail_v1(c)->'agreement'->>'digest'));
  end loop;
  perform pg_temp.login_beta(first_actor);perform pg_temp.beta_command(c,'reopen');
 end if;
 perform set_config('role','none',true);return c;
end $$;
insert into beta_ids values('initial',pg_temp.redraft(1,false)),('direct',pg_temp.redraft(4)),('reject',pg_temp.redraft(7)),('leave',pg_temp.redraft(10)),('process',pg_temp.redraft(13));
create temp table prior_history as
 select b.id,(select jsonb_agg(to_jsonb(a) order by version) from app.challenge_agreements_v1 a where challenge_id=b.id) agreements,
 (select jsonb_agg(to_jsonb(c) order by actor_id) from app.challenge_consents_v1 c where challenge_id=b.id) consents
 from beta_ids b;
-- Baseline: an initial unagreed draft survives a pending rejection and process.
select pg_temp.login_beta(1);
select pg_temp.beta_command((select id from beta_ids where name='initial'),'reject',jsonb_build_object('actor_id',pg_temp.ba(3)));
set constraints all immediate;
set constraints all deferred;
select is(public.challenge_detail_v1((select id from beta_ids where name='initial'))->>'status','lobby_open','initial draft remains open after pending rejection');
reset role;
select is(public.challenge_process_v1((select id from beta_ids where name='initial')),'lobby_open','initial draft remains open after processing');
-- Reopened draft: reject the pending third account through the native command.
select pg_temp.login_beta(7);
select pg_temp.beta_command((select id from beta_ids where name='reject'),'reject',jsonb_build_object('actor_id',pg_temp.ba(9)));
set constraints all immediate;
set constraints all deferred;
select is(public.challenge_detail_v1((select id from beta_ids where name='reject'))->>'status','lobby_open','reopened draft remains visibly open after pending rejection');
reset role;
-- Reopened draft: the unselected noncreator may leave without finalizing it.
select pg_temp.login_beta(12);
select pg_temp.beta_command((select id from beta_ids where name='leave'),'leave');
set constraints all immediate;
set constraints all deferred;
select pg_temp.login_beta(10);
select is(public.challenge_detail_v1((select id from beta_ids where name='leave'))->>'status','lobby_open','reopened draft remains visibly open after pending participant leaves');
reset role;
select is(public.challenge_process_v1((select id from beta_ids where name='process')),'lobby_open','processing a reopened draft does not finalize an earlier agreement');
select is((select count(*)::integer from app.challenge_finals_v1 where challenge_id in(select id from beta_ids)),0,'all five drafts have no final');
select is((select count(*)::integer from app.challenge_slots_v1 where challenge_id in(select id from beta_ids)),0,'open and reopened drafts claim no admission slots');
select ok(not exists(select 1 from prior_history p where
 p.agreements is distinct from (select jsonb_agg(to_jsonb(a) order by version) from app.challenge_agreements_v1 a where challenge_id=p.id)
 or p.consents is distinct from (select jsonb_agg(to_jsonb(c) order by actor_id) from app.challenge_consents_v1 c where challenge_id=p.id)),
 'rejection, exit and processing preserve every historical agreement and consent byte');
-- Direct reconsent is the previously covered control; the other three must also
-- permit edited targets, a new agreement and two distinct fresh consents.
create function pg_temp.refreeze(c uuid,first_actor integer) returns void language plpgsql as $$begin
 perform pg_temp.login_beta(first_actor);perform pg_temp.beta_command(c,'target','{"target":10002}');
 perform pg_temp.beta_command(c,'freeze');perform set_config('role','none',true);
end $$;
create function pg_temp.reconsent(c uuid,actor integer) returns void language plpgsql as $$begin
 perform pg_temp.login_beta(actor);perform pg_temp.beta_command(c,'consent',jsonb_build_object('consent',true,'digest',public.challenge_detail_v1(c)->'agreement'->>'digest'));
 perform set_config('role','none',true);
end $$;
select lives_ok($$select pg_temp.refreeze((select id from beta_ids where name='direct'),4)$$,'direct: can change own target and freeze a new roster');
select lives_ok($$select pg_temp.reconsent((select id from beta_ids where name='direct'),4)$$,'direct: creator may consent to new terms');
select is((select status from app.challenge_lobbies_v1 where id=(select id from beta_ids where name='direct')),'consent_pending','direct: old second-person consent is never inherited');
select lives_ok($$select pg_temp.reconsent((select id from beta_ids where name='direct'),5)$$,'direct: second participant may consent to new terms');
select is((select status from app.challenge_lobbies_v1 where id=(select id from beta_ids where name='direct')),'scheduled','direct: both fresh consents schedule the challenge');
select lives_ok($$select pg_temp.refreeze((select id from beta_ids where name='reject'),7)$$,'reject: can change own target and freeze a new roster');
select lives_ok($$select pg_temp.reconsent((select id from beta_ids where name='reject'),7)$$,'reject: creator may consent to new terms');
select is((select status from app.challenge_lobbies_v1 where id=(select id from beta_ids where name='reject')),'consent_pending','reject: old second-person consent is never inherited');
select lives_ok($$select pg_temp.reconsent((select id from beta_ids where name='reject'),8)$$,'reject: second participant may consent to new terms');
select is((select status from app.challenge_lobbies_v1 where id=(select id from beta_ids where name='reject')),'scheduled','reject: both fresh consents schedule the challenge');
select lives_ok($$select pg_temp.refreeze((select id from beta_ids where name='leave'),10)$$,'leave: can change own target and freeze a new roster');
select lives_ok($$select pg_temp.reconsent((select id from beta_ids where name='leave'),10)$$,'leave: creator may consent to new terms');
select is((select status from app.challenge_lobbies_v1 where id=(select id from beta_ids where name='leave')),'consent_pending','leave: old second-person consent is never inherited');
select lives_ok($$select pg_temp.reconsent((select id from beta_ids where name='leave'),11)$$,'leave: second participant may consent to new terms');
select is((select status from app.challenge_lobbies_v1 where id=(select id from beta_ids where name='leave')),'scheduled','leave: both fresh consents schedule the challenge');
select lives_ok($$select pg_temp.refreeze((select id from beta_ids where name='process'),13)$$,'process: can change own target and freeze a new roster');
select lives_ok($$select pg_temp.reconsent((select id from beta_ids where name='process'),13)$$,'process: creator may consent to new terms');
select is((select status from app.challenge_lobbies_v1 where id=(select id from beta_ids where name='process')),'consent_pending','process: old second-person consent is never inherited');
select lives_ok($$select pg_temp.reconsent((select id from beta_ids where name='process'),14)$$,'process: second participant may consent to new terms');
select is((select status from app.challenge_lobbies_v1 where id=(select id from beta_ids where name='process')),'scheduled','process: both fresh consents schedule the challenge');
select * from finish();
rollback;
