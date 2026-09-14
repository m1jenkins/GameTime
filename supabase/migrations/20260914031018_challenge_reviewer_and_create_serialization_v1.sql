-- Privacy1 / S1: restore the existing P4/P6 authorization boundaries.
-- No grants, policies, historical rows, agreement bytes or retry rules change.
begin;

do $$
declare definition text; marker text;
begin
 -- P6's replacement missed the actor-unavailable prefix on this reader.
 -- Lock the exact review grant, then evaluate current authorization/expiry.
 -- An authorized reader holds SHARE until commit; a revoker which won first
 -- completes before the reader rechecks, just like moderator report reads.
 definition := pg_get_functiondef('public.challenge_operator_cases_v1(uuid)'::regprocedure);
 marker := 'if app.challenge_actor_unavailable_v1(a) or not exists(select 1 from app.challenge_operator_grants_v1';
 if cardinality(string_to_array(definition,marker)) <> 2 then
  raise exception 'Unexpected reviewer authorization guard';
 end if;
 execute replace(definition,marker,
  'perform 1 from app.challenge_operator_grants_v1 where actor_id=a and challenge_id=p_id and capability=''review'' for share; '||marker);

 -- Existing-object mutations already lock profiles before rechecking admission.
 -- New friend drafts need the creator profile too: their FK's later KEY SHARE
 -- wait proves existence only, and cannot validate a concurrent suspension.
 -- Exact saved requests return before this branch and remain recoverable.
 definition := pg_get_functiondef('app.challenge_mutate_unmetered_v1(uuid,jsonb)'::regprocedure);
 marker := E'if op=''create'' then\n  perform app.challenge_admit_v1(a);';
 if cardinality(string_to_array(definition,marker)) <> 2 then
  raise exception 'Unexpected friend creation admission guard';
 end if;
 execute replace(definition,marker,E'if op=''create'' then\n  perform id from public.profiles where id=a for update;\n  perform app.challenge_session_v1();\n  perform app.challenge_admit_v1(a);\n  n:=app.challenge_now_v1();');
end $$;

commit;
