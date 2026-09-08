-- Exact server clock and review version for native consent/review presentation.
do $$ declare definition text;begin
 definition:=pg_get_functiondef('public.challenge_access_status_v1()'::regprocedure);
 definition:=replace(definition,'''age_confirmed'',','''server_time'',app.challenge_now_v1(),''age_confirmed'',');execute definition;
 definition:=pg_get_functiondef('public.challenge_detail_v1(uuid)'::regprocedure);
 definition:=replace(definition,'''id'',r.id,''reason'',','''id'',r.id,''notice_revision'',r.notice_revision,''reason'',');execute definition;
end $$;
-- Hidden social context still includes the person's own provisional allocation.
do $$ declare definition text;begin
 definition:=pg_get_functiondef('public.challenge_detail_v1(uuid)'::regprocedure);
 definition:=replace(definition,'case when not hidden then result end','case when not hidden then result else jsonb_build_object(''own'',result->''participants''->a::text) end');execute definition;
end $$;
