-- Reopening invalidates displayed consent immediately while retaining every
-- historical agreement and consent. A subsequent freeze creates the next version.
do $$ declare definition text; revised text;begin
 definition:=pg_get_functiondef('public.challenge_detail_v1(uuid)'::regprocedure);
 revised:=replace(definition,'''agreement'',(select jsonb_build_object(','''agreement'',case when c.status=''lobby_open'' then null else (select jsonb_build_object(');
 revised:=replace(revised,'where challenge_id=p_id and version=c.agreement_version),','where challenge_id=p_id and version=c.agreement_version) end,');
 revised:=replace(revised,'''consented'',exists(','''consented'',c.status<>''lobby_open'' and exists(');
 if revised=definition or position('''agreement'',case when c.status=''lobby_open''' in revised)=0 or position('''consented'',c.status<>''lobby_open''' in revised)=0 then raise exception 'challenge_projection_patch_mismatch';end if;
 execute revised;
end $$;
