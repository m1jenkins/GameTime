-- P9 adds only the source identity already frozen on the lobby. Membership,
-- redaction, delayed community counts and all historical terms stay unchanged.
begin;
do $$
declare definition text; marker text := '''policy'',c.policy,''config'',c.config';
begin
  definition := pg_get_functiondef('app.challenge_detail_for_actor_v1(uuid,uuid)'::regprocedure);
  if position(marker in definition) = 0 then raise exception 'Unexpected challenge detail source projection'; end if;
  execute replace(definition, marker,
    '''policy'',c.policy,''source_policy_version'',c.real_source_policy_version,''config'',c.config');
end;
$$;
commit;
