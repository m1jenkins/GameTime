-- Rollback-only fictional integration fixtures, consumed by the local smoke.
begin;
set local timezone='UTC';
create temp table lifecycle_pairs(n integer primary key,c uuid,a uuid,b uuid,reviewer uuid,sid uuid,asess uuid,bsess uuid);
create function pg_temp.prepare(n integer,accepted boolean default true,ends timestamptz default '2026-08-01 17:00Z') returns uuid language plpgsql as $$
declare a uuid:=extensions.gen_random_uuid(); b uuid:=extensions.gen_random_uuid(); reviewer uuid:=extensions.gen_random_uuid();
 e uuid:=extensions.gen_random_uuid(); c uuid; sid uuid:=extensions.gen_random_uuid();
 asess uuid:=extensions.gen_random_uuid(); bsess uuid:=extensions.gen_random_uuid();
begin
 insert into auth.users(id) values(a),(b),(reviewer);
 insert into public.profiles(id,handle,display_name,timezone)
 select id,'life'||left(replace(id::text,'-',''),16),'Fictional Runner','UTC' from auth.users where id in (a,b,reviewer);
 insert into auth.sessions(id,user_id) values(sid,reviewer),(asess,a),(bsess,b);
 insert into public.friendships(user_a,user_b,requested_by,status) values(least(a,b),greatest(a,b),a,'accepted');
 perform public.set_duel_admission_v1(true,array[a,b]);
 perform public.curate_duel_fixture_event_v1(e,ends-interval '2 hours',ends,'UTC');
 perform set_config('request.jwt.claim.sub',a::text,true);
 c:=app.create_duel_at_v1(extensions.gen_random_uuid(),b,e,'duel-fixture-5k-v1',true,ends-interval '29 hours');
 if accepted then
   perform set_config('request.jwt.claim.sub',b::text,true);
   perform app.respond_duel_at_v1('accept_duel_v1',extensions.gen_random_uuid(),c,'duel-fixture-5k-v1',
    (select terms_digest from public.duel_challenges where id=c),ends-interval '28 hours');
   perform public.set_duel_proof_reviewer_v1(extensions.gen_random_uuid(),c,reviewer,true);
 end if;
 insert into lifecycle_pairs values(n,c,a,b,reviewer,sid,asess,bsess);
 return c;
end; $$;
create function pg_temp.login(n integer,who text) returns void language plpgsql as $$
declare p lifecycle_pairs; actor uuid; sess uuid;
begin
 select * into strict p from lifecycle_pairs where lifecycle_pairs.n=login.n;
 actor:=case who when 'a' then p.a when 'b' then p.b else p.reviewer end;
 sess:=case who when 'a' then p.asess when 'b' then p.bsess else p.sid end;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'session_id',sess,'role','authenticated')::text,true);
 perform set_config('role','authenticated',true);
end; $$;
create function pg_temp.document(n integer,kind text default 'winner') returns jsonb language sql as $$
 select jsonb_build_object('eventId',c.event_id,'course','fixture_course_5k_v1','wave','fixture_common_wave_v1',
 'distanceMeters',5000,'timingBasis','organizer_chip','precisionSeconds',1,'rows',jsonb_build_array(
 jsonb_build_object('actorId',p.a,'mappedBib','fictional-bib-11','publishedBib','fictional-bib-11',
 'status',case when kind='both_nonfinish' then 'dnf' else 'finished' end,
 'chipSeconds',case when kind='both_nonfinish' then null else 1200 end),
 jsonb_build_object('actorId',p.b,'mappedBib','fictional-bib-22','publishedBib',case when kind='wrong_bib' then 'fictional-bib-99' else 'fictional-bib-22' end,
 'status',case when kind='missing' then 'missing' when kind in ('only_finisher','both_nonfinish') then 'dnf' else 'finished' end,
 'chipSeconds',case when kind in ('missing','only_finisher','both_nonfinish') then null when kind='tie' then 1200 when kind='corrected' then 1150 else 1250 end)))
 from lifecycle_pairs p join public.duel_challenges c on c.id=p.c where p.n=document.n
$$;
create function pg_temp.append(req uuid,c uuid,source uuid,rev integer,v jsonb,t timestamptz) returns integer language sql security definer set search_path='' as $$select app.duel_proof_append_at_v1(req,c,source,rev,v,t)$$;
create function pg_temp.file_inner(req uuid,c uuid,rev integer,t timestamptz) returns uuid language sql security definer set search_path='' as $$select app.duel_lifecycle_case_at_v1(req,c,rev,'wrong_result',t)$$;
create function pg_temp.resolve_inner(req uuid,k uuid,d text,t timestamptz) returns uuid language sql security definer set search_path='' as $$select app.duel_lifecycle_resolve_at_v1(req,k,d,t)$$;
create function pg_temp.exit_inner(req uuid,c uuid,k text,t timestamptz) returns uuid language sql security definer set search_path='' as $$select app.duel_lifecycle_exit_at_v1(req,c,k,t)$$;
create function pg_temp.proof(n integer,rev integer,kind text,t timestamptz) returns integer language plpgsql as $$
declare p lifecycle_pairs; source_id uuid:=extensions.gen_random_uuid(); result integer;
begin
 select * into strict p from lifecycle_pairs where lifecycle_pairs.n=proof.n;
 perform app.duel_proof_capture_at_v1(source_id,p.c,pg_temp.document(n,kind),t);
 perform pg_temp.login(n,'reviewer');
 result:=pg_temp.append(extensions.gen_random_uuid(),p.c,source_id,rev,
 jsonb_build_array(jsonb_build_object('actorId',p.a,'identityConfirmed',true),
 jsonb_build_object('actorId',p.b,'identityConfirmed',kind not in ('missing','wrong_bib'))),t);
 perform set_config('role','none',true);
 return result;
end; $$;
create function pg_temp.file(n integer,rev integer,t timestamptz) returns uuid language plpgsql as $$
declare p lifecycle_pairs; result uuid;
begin
 select * into strict p from lifecycle_pairs where lifecycle_pairs.n=file.n;
 perform pg_temp.login(n,'a');
 result:=pg_temp.file_inner(extensions.gen_random_uuid(),p.c,rev,t);
 perform set_config('role','none',true); return result;
end; $$;
create function pg_temp.resolve(n integer,k uuid,decision text,t timestamptz) returns uuid language plpgsql as $$
declare result uuid;
begin
 perform pg_temp.login(n,'reviewer');
 result:=pg_temp.resolve_inner(extensions.gen_random_uuid(),k,decision,t);
 perform set_config('role','none',true); return result;
end; $$;
create function pg_temp.exit(n integer,kind text,t timestamptz) returns uuid language plpgsql as $$
declare p lifecycle_pairs; result uuid;
begin
 select * into strict p from lifecycle_pairs where lifecycle_pairs.n=exit.n;
 if kind<>'event_cancelled' then perform pg_temp.login(n,'a'); end if;
 result:=pg_temp.exit_inner(extensions.gen_random_uuid(),p.c,kind,t);
 perform set_config('role','none',true); return result;
end; $$;
create function pg_temp.attempt(sql text) returns text language plpgsql as $$
begin execute sql; return 'ok'; exception when others then return sqlstate; end; $$;
do $$begin perform public.set_duel_lifecycle_enabled_v1(true); perform public.set_duel_proof_enabled_v1(true); end$$;

create function pg_temp.read_result(n integer,who text default 'a') returns jsonb language plpgsql as $$
declare p lifecycle_pairs; result jsonb;
begin
 select * into strict p from lifecycle_pairs where lifecycle_pairs.n=read_result.n;
 perform pg_temp.login(n,who);
 result:=public.get_duel_lifecycle_v1(p.c);
 perform set_config('role','none',true); return result;
end; $$;
create function pg_temp.support(n integer,req uuid) returns uuid language plpgsql as $$
declare p lifecycle_pairs; d jsonb; result uuid;
begin
 select * into strict p from lifecycle_pairs where lifecycle_pairs.n=support.n;
 d:=pg_temp.document(n,'corrected');
 perform pg_temp.login(n,'reviewer');
 result:=public.submit_duel_support_correction_v1(req,p.c,d);
 perform set_config('role','none',true); return result;
end; $$;
create function pg_temp.block_pair(n integer) returns void language plpgsql as $$
declare p lifecycle_pairs;
begin
 select * into strict p from lifecycle_pairs where lifecycle_pairs.n=block_pair.n;
 perform pg_temp.login(n,'a');
 insert into public.blocks(blocker_id,blocked_id) values(p.a,p.b);
 perform set_config('role','none',true);
end; $$;
