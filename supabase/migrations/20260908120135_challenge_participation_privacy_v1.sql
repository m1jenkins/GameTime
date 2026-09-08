-- Pending entrants have no participation agreement. Their blocks end contact,
-- but cannot withdraw somebody from the selected roster. A block between current
-- selected participants retains the existing mutual safe-exit behavior.
-- Departed people retain their own receipts; counterpart projections keep only
-- a pseudonymous membership/result reference, not identity, goal or activity.
-- Stored agreements, consents, activity facts and final results remain immutable.
do $$
declare definition text; revised text; marker text;
begin
 definition:=pg_get_functiondef('app.challenge_tick_v1(uuid,boolean)'::regprocedure);
 marker:='other.challenge_id=p_id and app.is_blocked_either_way(m.actor_id,other.actor_id)';
 if position(marker in definition)=0 then raise exception 'Unexpected challenge tick block predicate';end if;
 revised:=replace(definition,marker,'other.challenge_id=p_id and other.exited_at is null and (not m.selected or other.selected) and app.is_blocked_either_way(m.actor_id,other.actor_id)');
 execute revised;
 definition:=pg_get_functiondef('public.challenge_detail_v1(uuid)'::regprocedure);
 marker:='where challenge_id=p_id and actor_id<>a and (';
 if position(marker in definition)=0 then raise exception 'Unexpected challenge visibility predicate';end if;
 revised:=replace(definition,marker,'where challenge_id=p_id and actor_id<>a and selected and exited_at is null and (');
 marker:='''username'',p.handle,''target'',m.target';
 if position(marker in revised)=0 then raise exception 'Unexpected challenge member projection';end if;
 revised:=replace(revised,marker,'''username'',case when m.exited_at is null or m.actor_id=a then p.handle else '''' end,''target'',case when m.exited_at is null or m.actor_id=a then m.target end');
 marker:='where challenge_id=p_id and actor_id=m.actor_id order by revision desc limit 1';
 if position(marker in revised)=0 then raise exception 'Unexpected challenge fact projection';end if;
 revised:=replace(revised,marker,'where challenge_id=p_id and actor_id=m.actor_id and (m.exited_at is null or m.actor_id=a) order by revision desc limit 1');
 execute revised;
end $$;
