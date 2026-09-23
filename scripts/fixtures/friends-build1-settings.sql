-- Settings proposed for hosted gametime-p11b in friends Phase 5, applied by an
-- operator. Used only on disposable local stacks by scripts/friends-local-http.ts
-- and scripts/friends-native-smoke.py. Idempotent. The real-activity runtime
-- (admission, ingestion, processing) is turned on separately through its
-- service RPC.
update app.friend_runtime_v1 set commands_only = true;
update app.challenge_policy_runtime_v1
  set allowlist_enforced = true, account_mode = true, links_enabled = false;
insert into app.challenge_policy_allowlist_v1 values
  ('friend_steps_goal_v1', 'apple_watch_steps_v1'),
  ('friend_exercise_goal_v1', 'apple_watch_exercise_credit_v2'),
  ('friend_distance_goal_v1', 'apple_workout_outdoor_distance_v1'),
  ('friend_timed_goal_v1', 'apple_workout_outdoor_timed_v1')
on conflict do nothing;
