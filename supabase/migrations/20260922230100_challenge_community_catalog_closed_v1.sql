-- D142 build 1: the community catalog follows the per-policy allowlist.
--
-- With the allowlist enforced and community_steps_goal_v1 not on it,
-- challenge_availability_v1 reports community as closed and joining is
-- refused, but the catalog still listed any community published earlier. The
-- app shows whatever the catalog returns, so a person could see a community
-- they can't join. Friends Phase 4 found this over HTTP. The catalog now
-- returns nothing in that case. Its quota and every other rule are unchanged.

do $migration$
declare d text; marker text;
begin
 d := pg_get_functiondef('public.challenge_community_catalog_v1()'::regprocedure);
 marker := $m$ then return '[]'; end if;
$m$;
 if position(marker in d) = 0 then raise exception 'Unexpected community catalog'; end if;
 execute replace(d, marker, marker || $m$ if app.challenge_policy_enforced_v1()
    and not app.challenge_policy_pair_allowed_v1('apple_watch_steps_v1', 'community_steps_goal_v1')
 then return '[]'; end if;
$m$);
end;
$migration$;
