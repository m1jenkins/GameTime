-- Rollback-only SQL-to-evaluator smoke. All people, bibs and sources are fictional.
-- Auth rows below are SQL fixtures, not a claim of hosted or HTTP authentication.
\set ON_ERROR_STOP on
begin;
set local timezone='UTC';
create temp table proof_smoke_samples(name text,input jsonb,receipt jsonb,expected_winner uuid);
do $$
declare a uuid:=extensions.gen_random_uuid(); b uuid:=extensions.gen_random_uuid();
  reviewer uuid:=extensions.gen_random_uuid(); sid uuid:=extensions.gen_random_uuid();
  participant_sid uuid:=extensions.gen_random_uuid(); e uuid:=extensions.gen_random_uuid();
  source_id uuid:=extensions.gen_random_uuid(); correction_id uuid:=extensions.gen_random_uuid();
  c uuid; epoch timestamptz:=clock_timestamp(); d jsonb; verdict jsonb; agreement jsonb; receipt jsonb;
begin
  insert into auth.users(id) values(a),(b),(reviewer);
  insert into public.profiles(id,handle,display_name,timezone)
    select id,'proofsmoke'||left(replace(id::text,'-',''),12),'Fictional Runner','UTC'
    from auth.users where id in (a,b,reviewer);
  insert into auth.sessions(id,user_id) values(sid,reviewer),(participant_sid,a);
  insert into public.friendships(user_a,user_b,requested_by,status) values(least(a,b),greatest(a,b),a,'accepted');
  perform public.set_duel_admission_v1(true,array[a,b]);
  perform public.curate_duel_fixture_event_v1(e,epoch-interval '4 hours',epoch-interval '2 hours','UTC');
  perform set_config('request.jwt.claim.sub',a::text,true);
  c:=app.create_duel_at_v1(extensions.gen_random_uuid(),b,e,'duel-fixture-5k-v1',true,epoch-interval '2 days');
  perform set_config('request.jwt.claim.sub',b::text,true);
  perform app.respond_duel_at_v1('accept_duel_v1',extensions.gen_random_uuid(),c,'duel-fixture-5k-v1',
    (select terms_digest from public.duel_challenges where id=c),epoch-interval '1 day');
  perform public.set_duel_proof_enabled_v1(true);
  perform public.set_duel_proof_reviewer_v1(extensions.gen_random_uuid(),c,reviewer,true);
  d:=jsonb_build_object('eventId',e,'course','fixture_course_5k_v1','wave','fixture_common_wave_v1',
    'distanceMeters',5000,'timingBasis','organizer_chip','precisionSeconds',1,'rows',jsonb_build_array(
      jsonb_build_object('actorId',a,'mappedBib','fictional-bib-11','publishedBib','fictional-bib-11','status','finished','chipSeconds',1200),
      jsonb_build_object('actorId',b,'mappedBib','fictional-bib-22','publishedBib','fictional-bib-22','status','finished','chipSeconds',1250)));
  perform public.capture_duel_proof_fixture_v1(source_id,c,d);
  verdict:=jsonb_build_array(jsonb_build_object('actorId',a,'identityConfirmed',true),jsonb_build_object('actorId',b,'identityConfirmed',true));
  perform set_config('request.jwt.claim.sub',reviewer::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',reviewer,'session_id',sid)::text,true);
  perform set_config('role','authenticated',true);
  perform public.get_duel_proof_source_v1(c,source_id);
  perform public.submit_duel_proof_v1(extensions.gen_random_uuid(),c,source_id,0,verdict);
  perform set_config('request.jwt.claim.sub',a::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'session_id',participant_sid)::text,true);
  agreement:=public.get_duel_v1(c);
  receipt:=public.get_duel_proof_status_v1(c);
  perform set_config('role','none',true);
  insert into proof_smoke_samples values('initial',jsonb_build_object('agreement',agreement,'now',clock_timestamp(),
    'proofRevisions',app.duel_proof_history_v1(c),'notices','[]'::jsonb,'reviews','[]'::jsonb,
    'closure',null,'finalResult',null),receipt,a);
  -- Official correction changes runner B's captured time, not an existing row.
  perform public.capture_duel_proof_fixture_v1(correction_id,c,jsonb_set(d,'{rows,1,chipSeconds}','1150'));
  perform set_config('request.jwt.claim.sub',reviewer::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',reviewer,'session_id',sid)::text,true);
  perform set_config('role','authenticated',true);
  perform public.get_duel_proof_source_v1(c,correction_id);
  perform public.submit_duel_proof_v1(extensions.gen_random_uuid(),c,correction_id,1,verdict);
  perform set_config('request.jwt.claim.sub',a::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'session_id',participant_sid)::text,true);
  receipt:=public.get_duel_proof_status_v1(c);
  perform set_config('role','none',true);
  insert into proof_smoke_samples values('correction',jsonb_build_object('agreement',agreement,'now',clock_timestamp(),
    'proofRevisions',app.duel_proof_history_v1(c),'notices','[]'::jsonb,'reviews','[]'::jsonb,
    'closure',null,'finalResult',null),receipt,b);
end; $$;
set constraints all immediate;
select jsonb_agg(to_jsonb(s) order by name) from proof_smoke_samples s;
rollback;
