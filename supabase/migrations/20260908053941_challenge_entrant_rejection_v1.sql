-- Declining a pending request ends lobby contact without revoking Beta access.
do $$ declare definition text;begin
 definition:=pg_get_functiondef('public.challenge_mutate_v1(uuid,jsonb)'::regprocedure);
 definition:=replace(definition,' when ''select'' then array', E' when ''reject'' then array[''op'',''id'',''revision'',''actor_id'']\n when ''select'' then array');
 definition:=replace(definition,'(''invite'',''select'',''configure''','(''invite'',''select'',''reject'',''configure''');
 definition:=replace(definition,'(''configure'',''invite'',''target'',''select'',''freeze'')','(''configure'',''invite'',''target'',''select'',''reject'',''freeze'')');
 definition:=replace(definition,'(''configure'',''invite'',''select'',''freeze''','(''configure'',''invite'',''select'',''reject'',''freeze''');
 definition:=replace(definition,'  elsif op=''select'' then', E'  elsif op=''reject'' then\n   target_actor:=(p_payload->>''actor_id'')::uuid;\n   if target_actor=a then raise exception ''challenge_invalid_selection'' using errcode=''22023'';end if;\n   update app.challenge_members_v1 set exited_at=n where challenge_id=cid and actor_id=target_actor and not selected and exited_at is null;\n   if not found then raise exception ''challenge_entrant_unavailable'' using errcode=''22023'';end if;\n   insert into app.challenge_exits_v1 values(p_request_id,cid,target_actor,''request_declined'',n);\n  elsif op=''select'' then');
 execute definition;
end $$;
