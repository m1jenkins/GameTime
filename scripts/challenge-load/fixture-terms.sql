-- Fixture-only constructor in an unexposed schema. Product functions/migrations are untouched.
-- Matches final freeze/personal/publication shapes; independently checked by contracts.py.
create function challenge_load_fixture.terms(cid uuid,ver integer) returns jsonb language sql stable as $$
 select case when c.policy='community_steps_goal_v1' then
   jsonb_build_object('policy',c.policy,'source','fictional_steps_v1','mode','community','competition','goal','metric','steps','unit','whole_counts','config',c.config,
    'common_target',100,'minimum',c.minimum,'capacity',c.capacity,'settings_status','unapproved_fixture_only','simulation','nonredeemable','review_hours',48,'resolution_hours',72,
    'missing_rule','exclude_refund_minimum','exit_rule','exclude_refund_minimum','allocation_rule','return_qualifiers_split_misses_remainder_unallocated')
 else jsonb_build_object('policy',c.policy,'source',p->>'source','mode',p->>'mode','competition',p->>'competition','metric',p->>'metric','unit',p->>'unit','comparator',p->>'comparator',
    'config',c.config,'version',ver,'participants',(select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('actor_id',m.actor_id,'target',m.target)) order by m.actor_id) from app.challenge_members_v1 m where m.challenge_id=c.id),
    'simulation','nonredeemable','review_hours',48,'resolution_hours',72,
    'missing_rule',case when p->>'competition'='leaderboard' then 'void_if_any_unresolved' else 'exclude_refund_minimum' end,
    'exit_rule','exclude_refund_minimum','minimum',c.minimum,
    'allocation_rule',case when p->>'competition'='leaderboard' then 'co_winners_split_active_pool_remainder_unallocated' else 'return_qualifiers_split_misses_remainder_unallocated' end)
 end
 from app.challenge_lobbies_v1 c cross join lateral app.challenge_policy_v1(c.policy) p where c.id=cid
$$;
revoke all on function challenge_load_fixture.terms(uuid,integer) from public,anon,authenticated,service_role;
