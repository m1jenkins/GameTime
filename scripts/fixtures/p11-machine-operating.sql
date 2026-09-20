-- Owned local P11 Cron -> Edge operating seed. Apply once to the disposable
-- primary database. The runner owns credentials, runtime gates, selected cohort
-- and job activation; this file changes only fictional application rows.
--
-- Fixed challenge IDs for the private runner (do not echo in public reports):
--   due friend goal:     be000000-0000-0000-0000-000000052530
--   selected community: be000000-0000-0000-0000-000000052531
--   other community:    be000000-0000-0000-0000-000000052532

begin;
set local app.challenge_write_v1 = 'on';

do $$
declare
  actor_ids uuid[] := array[
    'bf000000-0000-0000-0000-000000052541'::uuid,
    'bf000000-0000-0000-0000-000000052542'::uuid,
    'bf000000-0000-0000-0000-000000052543'::uuid,
    'bf000000-0000-0000-0000-000000052544'::uuid,
    'bf000000-0000-0000-0000-000000052545'::uuid
  ];
  goal_id uuid := 'be000000-0000-0000-0000-000000052530';
  selected_id uuid := 'be000000-0000-0000-0000-000000052531';
  other_id uuid := 'be000000-0000-0000-0000-000000052532';
  wall timestamptz := clock_timestamp();
  goal_start timestamptz;
  goal_end timestamptz;
  community_start timestamptz;
  community_end timestamptz;
  terms_digest text;
  actor uuid;
  community uuid;
  ordinal integer;
begin
  goal_end := wall - interval '72 hours';
  goal_start := goal_end - interval '1 hour';
  community_start := wall + interval '24 hours';
  community_end := wall + interval '48 hours';

  if exists(select 1 from app.challenge_lobbies_v1 where id in (goal_id,selected_id,other_id)) then
    raise exception 'p11_machine_seed_already_applied' using errcode='23505';
  end if;

  for ordinal in 1..5 loop
    actor := actor_ids[ordinal];
    insert into auth.users(id) values(actor);
    insert into public.profiles(id,handle,display_name,timezone)
    values(actor,'machine_operating_'||ordinal,'Local Machine Test','UTC');
  end loop;

  -- Two admitted positive normalized facts qualify the ended friend goal.
  -- The timestamps sit inside its accepted source window; the worker, rather
  -- than this seed, must create any notice, review period or final history.
  insert into app.challenge_lobbies_v1
    (id,creator_id,policy,config,starts_at,ends_at,status,revision,
     agreement_version,created_at,minimum,capacity)
  values(goal_id,actor_ids[1],'friend_steps_goal_v1','{"amount_cents":100}'::jsonb,
    goal_start,goal_end,'active',1,1,goal_start,2,6);
  update app.challenge_lobbies_v1
    set real_source_policy_version='apple_watch_steps_v1' where id=goal_id;
  insert into app.challenge_members_v1(challenge_id,actor_id,selected,target)
  values(goal_id,actor_ids[1],true,100),(goal_id,actor_ids[2],true,100);
  insert into app.challenge_slots_v1(challenge_id,actor_id,mode,metric,starts_at,ends_at)
  values(goal_id,actor_ids[1],'friend','steps',goal_start,goal_end),
        (goal_id,actor_ids[2],'friend','steps',goal_start,goal_end);
  insert into app.challenge_agreements_v1(challenge_id,version,terms,created_at)
  values(goal_id,1,
    '{"metric":"steps","policy":"friend_steps_goal_v1","source_policy_version":"apple_watch_steps_v1"}'::jsonb
      || jsonb_build_object('config',jsonb_build_object('starts_at',goal_start,'ends_at',goal_end)),
    goal_start);
  select digest into terms_digest from app.challenge_agreements_v1
    where challenge_id=goal_id and version=1;
  insert into app.challenge_consents_v1(challenge_id,version,actor_id,digest,recorded_at)
  values(goal_id,1,actor_ids[1],terms_digest,goal_start),
        (goal_id,1,actor_ids[2],terms_digest,goal_start);
  insert into app.challenge_real_health_admissions_v1
    (challenge_id,actor_id,agreement_version,terms_digest,source_policy_version,
     metric,window_starts_at,window_ends_at,admitted_at)
  values(goal_id,actor_ids[1],1,terms_digest,'apple_watch_steps_v1',
    'steps',goal_start,goal_end,goal_start),
        (goal_id,actor_ids[2],1,terms_digest,'apple_watch_steps_v1',
    'steps',goal_start,goal_end,goal_start);
  insert into app.challenge_real_health_facts_v1
    (challenge_id,actor_id,agreement_version,revision,previous_revision,state,
     value,observed_at,queried_through_at,recorded_at,request_id)
  values(goal_id,actor_ids[1],1,1,null,'value',100,
    goal_end-interval '1 minute',goal_end-interval '2 minutes',goal_end,
    'ba000000-0000-0000-0000-000000052541'),
        (goal_id,actor_ids[2],1,1,null,'value',200,
    goal_end-interval '1 minute',goal_end-interval '2 minutes',goal_end,
    'ba000000-0000-0000-0000-000000052542');

  -- Both communities are intentionally published only inside this disposable
  -- database. Their future start keeps them out of the due worker batch while
  -- the snapshot job may capture exactly the runner-selected five-person one.
  foreach community in array array[selected_id,other_id] loop
    insert into app.challenge_lobbies_v1
      (id,creator_id,policy,config,starts_at,ends_at,status,revision,
       agreement_version,created_at,minimum,capacity,real_source_policy_version)
    values(community,actor_ids[1],'community_steps_goal_v1',
      '{"amount_cents":100}'::jsonb,community_start,community_end,
      'published_open',1,1,wall,2,6,'apple_watch_steps_v1');
    insert into app.challenge_community_publications_v1
    values(community,actor_ids[1],'operator',wall);
    foreach actor in array actor_ids loop
      insert into app.challenge_members_v1(challenge_id,actor_id,selected,target)
      values(community,actor,true,100);
    end loop;
  end loop;
end $$;

commit;
