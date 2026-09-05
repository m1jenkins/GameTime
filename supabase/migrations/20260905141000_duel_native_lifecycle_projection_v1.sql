-- Phase 2(d): additive participant read metadata only. Preserve historical
-- agreements, private proof, independent operator permissions and worker rules.
-- Same pair/challenge locks and active-session boundary as Phase 2(c).
-- Database time is sampled after locks; action flags are hints, never authority.
create or replace function public.get_duel_lifecycle_v1(p_challenge_id uuid) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c public.duel_challenges; a uuid; restricted boolean; t timestamptz; final_exists boolean; closure_exists boolean;
begin
  c:=app.duel_proof_lock_v1(p_challenge_id,auth.uid());
  a:=app.duel_proof_require_session_v1();
  if a not in (c.creator_id,c.invitee_id) then raise exception 'duel_unavailable' using errcode='42501'; end if;
  t:=clock_timestamp();
  final_exists:=exists(select 1 from app.duel_lifecycle_results where challenge_id=c.id);
  closure_exists:=exists(select 1 from app.duel_lifecycle_closures where challenge_id=c.id);
  restricted:=not app.is_active_actor(c.creator_id) or not app.is_active_actor(c.invitee_id)
    or app.is_blocked_either_way(c.creator_id,c.invitee_id);
  return jsonb_build_object('challengeId',c.id,'termsDigest',c.terms_digest,'contactSuppressed',restricted,
    'serverNow',t,
    'canExit',c.closed_at is null and not final_exists and not closure_exists
      and t<(c.terms->>'finality_due_at')::timestamptz
      and (select count(*) from public.duel_participants where challenge_id=c.id and accepted_at is not null)=2,
    'closure',(select jsonb_build_object('kind',kind,'recordedAt',recorded_at,'isOwn',actor_id is not distinct from a)
      from app.duel_lifecycle_closures where challenge_id=c.id and (not restricted or actor_id=a)),
    'activatedAt',(select recorded_at from app.duel_lifecycle_activations where challenge_id=c.id),
    'notices',case when restricted then '[]'::jsonb else (select coalesce(jsonb_agg(jsonb_build_object(
      'proofRevision',proof_revision,'recordedAt',recorded_at,'outcome',outcome,
      'canFileReview',not final_exists and t>=x.recorded_at
        and t<(c.terms->>'finality_due_at')::timestamptz
        and t<(select max(n.recorded_at)+interval '168 hours' from app.duel_lifecycle_notices n
          where n.challenge_id=c.id and n.proof_revision=x.proof_revision)
        and not exists(select 1 from app.duel_lifecycle_cases k where k.challenge_id=c.id
          and k.actor_id=a and k.proof_revision=x.proof_revision),
      'disputeClosesAt',(select max(n.recorded_at)+interval '168 hours' from app.duel_lifecycle_notices n
        where n.challenge_id=c.id and n.proof_revision=x.proof_revision)) order by proof_revision),'[]'::jsonb)
      from app.duel_lifecycle_notices x where challenge_id=c.id and actor_id=a) end,
    'reviews',(select coalesce(jsonb_agg(jsonb_build_object('id',k.id,'proofRevision',k.proof_revision,
      'reason',k.reason,'filedAt',k.recorded_at,'reviewDueAt',k.recorded_at+interval '168 hours',
      'decision',r.decision,'decidedAt',r.recorded_at) order by k.recorded_at,k.id),'[]'::jsonb)
      from app.duel_lifecycle_cases k left join app.duel_lifecycle_resolutions r on r.case_id=k.id
      where k.challenge_id=c.id and k.actor_id=a),
    'finalResult',case when restricted then null else (select result from app.duel_lifecycle_results where challenge_id=c.id) end,
    'simulatedReturnCents',(select case when a=c.creator_id then creator_cents else invitee_cents end
      from app.duel_lifecycle_settlements where challenge_id=c.id));
end; $$;

revoke all on function public.get_duel_lifecycle_v1(uuid) from public,anon,service_role;
grant execute on function public.get_duel_lifecycle_v1(uuid) to authenticated;
