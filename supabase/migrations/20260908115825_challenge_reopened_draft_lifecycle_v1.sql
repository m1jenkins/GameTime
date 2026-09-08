-- A reopened friend lobby is a current draft even though its earlier immutable
-- agreement versions remain as history. Reopening has released its slots; an
-- exit trigger or worker must not mistake zero draft slots for an active group
-- below minimum and finalize the old agreement.
-- Preserve all existing tick locks, safety checks, deadlines, ACLs and patches.
do $$
declare definition text; marker text := 'if c.agreement_version=0 then';
begin
 definition := pg_get_functiondef('app.challenge_tick_v1(uuid,boolean)'::regprocedure);
 if (length(definition)-length(replace(definition,marker,'')))/length(marker) <> 1 then
  raise exception 'Unexpected challenge tick definition; review before applying';
 end if;
 execute replace(definition,marker,'if c.status=''lobby_open'' or c.agreement_version=0 then');
end $$;
