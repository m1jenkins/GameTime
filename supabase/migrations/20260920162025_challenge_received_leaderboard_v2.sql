-- D141: only NEW friend leaderboard v2 agreements rank received activity.
-- No existing row, source registry, consent, signed request or gate changes.
begin;

create function app.challenge_received_leaderboard_v2(p text)
returns boolean language sql immutable set search_path='' as $$
 select coalesce(p in ('friend_steps_leaderboard_v2','friend_exercise_leaderboard_v2',
  'friend_distance_leaderboard_v2','friend_timed_leaderboard_v2'),false)
$$;
create function app.challenge_received_leaderboard_terms_v2(p text)
returns jsonb language sql immutable set search_path='' as $$
 select case when app.challenge_received_leaderboard_v2(p) then jsonb_build_object(
  'score_rule','received_by_correction_cutoff_v2',
  'history_completeness_required',false,
  'score_deadline','config.corrections_by_inclusive',
  'initial_submission_rule','through_correction_cutoff',
  'missing_rule','unranked_return_entry_minimum_two',
  'partial_rule','rank_saved_total_or_best_saved_whole_run',
  'failure_rule','exact_recovery_or_review') else '{}'::jsonb end
$$;
revoke all on function app.challenge_received_leaderboard_v2(text),
 app.challenge_received_leaderboard_terms_v2(text) from public,anon,authenticated,service_role;

-- Extend the finite policy registry, keeping the original thirteen identities.
do $$
declare d text; marker text;
begin
 d:=pg_get_functiondef('app.challenge_policy_v1(text)'::regprocedure);
 marker:='p<>mode||''_''||metric||''_''||competition||''_v1''';
 if position(marker in d)=0 then raise exception 'Unexpected policy registry'; end if;
 execute replace(d,marker,'('||marker||' and not app.challenge_received_leaderboard_v2(p))');

 d:=pg_get_functiondef('app.challenge_mutate_unmetered_v1(uuid,jsonb)'::regprocedure);
 marker:='if real_source is not null and pol->>''competition''=''leaderboard'' then';
 if position(marker in d)=0 then raise exception 'Unexpected leaderboard admission'; end if;
 d:=replace(d,marker,'if (real_source is not null and pol->>''competition''=''leaderboard'' and not app.challenge_received_leaderboard_v2(policy_name)) or (real_source is null and app.challenge_received_leaderboard_v2(policy_name)) then');
 marker:='||app.challenge_exercise_credit_terms_v2(c.real_source_policy_version)';
 if position(marker in d)=0 then raise exception 'Unexpected frozen source terms'; end if;
 execute replace(d,marker,marker||'||app.challenge_received_leaderboard_terms_v2(c.policy)');

 -- Every v2 upload, including its first score, may arrive through end +48h.
 -- Old agreements retain the end +24h initial submission gate.
 d:=pg_get_functiondef('public.challenge_real_health_ingest_v1(uuid,jsonb,uuid,timestamptz,bytea,bigint,bytea,boolean)'::regprocedure);
 marker:='case when v_revision = 1 then interval ''24 hours'' else interval ''48 hours'' end';
 if position(marker in d)=0 then raise exception 'Unexpected ingestion cutoff'; end if;
 d:=replace(d,marker,'case when v_revision = 1 and not app.challenge_received_leaderboard_v2(lobby.policy) then interval ''24 hours'' else interval ''48 hours'' end');
 marker:='or lobby.agreement_version <> v_agreement_version';
 if position(marker in d)=0 then raise exception 'Unexpected frozen binding'; end if;
 execute replace(d,marker,marker||' or (app.challenge_received_leaderboard_v2(lobby.policy) and (agreement.terms->>''score_rule'') is distinct from ''received_by_correction_cutoff_v2'')');

 -- Reuse normalization, ties, exclusions and nonredeemable allocation. Only
 -- v2 may rank a group with missing scores; each unranked entry returns.
 d:=pg_get_functiondef('app.challenge_evaluate_policy_v1(text,jsonb,integer,integer,boolean)'::regprocedure);
 marker:='pol->>''competition''=''leaderboard'' and active<>known';
 if position(marker in d)=0 then raise exception 'Unexpected leaderboard minimum'; end if;
 d:=replace(d,marker,marker||' and not app.challenge_received_leaderboard_v2(p_policy)');
 d:=replace(d,'p_force_void or known<p_minimum','p_force_void or known<p_minimum or (app.challenge_received_leaderboard_v2(p_policy) and known<2)');
 marker:='status:=''excluded''; amount:=p_amount;';
 if position(marker in d)=0 then raise exception 'Unexpected excluded allocation'; end if;
 d:=replace(d,marker,'status:=case when app.challenge_received_leaderboard_v2(p_policy) and not (x->>''excluded'')::boolean then ''unranked'' else ''excluded'' end; amount:=p_amount;');
 execute d;

 d:=pg_get_functiondef('app.challenge_real_health_evaluate_v1(uuid,boolean)'::regprocedure);
 marker:='people jsonb;';
 if position(marker in d)=0 then raise exception 'Unexpected real evaluator'; end if;
 d:=replace(d,marker,marker||' received_scores boolean;');
 marker:='-- A value is a lower bound.';
 if position(marker in d)=0 then raise exception 'Unexpected real evaluator source'; end if;
 d:=replace(d,marker,'received_scores := app.challenge_received_leaderboard_v2(challenge.policy)
    and app.challenge_real_health_policy_available_v1(challenge.real_source_policy_version)
    and exists (select 1 from app.challenge_agreements_v1 a where a.challenge_id=challenge.id
      and a.version=challenge.agreement_version and a.terms->>''score_rule''=''received_by_correction_cutoff_v2'');
  -- For historical agreements only: a value is a lower bound.');
 marker:='''state'', case';
 if position(marker in d)=0 then raise exception 'Unexpected real score state'; end if;
 d:=replace(d,marker,marker||' when received_scores and fact.state=''value'' then ''complete''');
 marker:='''value'', case';
 if position(marker in d)=0 then raise exception 'Unexpected real score value'; end if;
 d:=replace(d,marker,marker||' when received_scores and fact.state=''value'' then fact.value');
 marker:='and admission.agreement_version = challenge.agreement_version';
 if position(marker in d)=0 then raise exception 'Unexpected real score admission'; end if;
 d:=replace(d,marker,marker||' and (not received_scores or f.recorded_at <= challenge.ends_at + interval ''48 hours'')');
 execute d;
end $$;
commit;
