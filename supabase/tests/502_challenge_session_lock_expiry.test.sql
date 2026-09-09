begin;
select no_plan();
\ir fixtures/challenge-fixture.inc

-- The forward replacement must not widen access to the internal helper or
-- change the privileged public boundary. Lock-wait expiry is exercised by
-- scripts/beta-session-expiry.py with separate real database transactions.
select ok(not prosecdef, 'session helper remains security invoker')
 from pg_proc where oid='app.challenge_session_v1()'::regprocedure;
select is(proconfig, array['search_path=""'], 'session helper keeps an empty search path')
 from pg_proc where oid='app.challenge_session_v1()'::regprocedure;
select ok(not has_function_privilege(role_name, 'app.challenge_session_v1()', 'execute'), role_name || ' cannot invoke the internal session helper')
 from unnest(array['anon','authenticated','service_role']) role_name;
select ok(prosecdef and proconfig=array['search_path=""'], 'public detail remains a fixed-path definer')
 from pg_proc where oid='public.challenge_detail_v1(uuid)'::regprocedure;
select ok(has_function_privilege('authenticated','public.challenge_detail_v1(uuid)','execute'), 'authenticated detail entry point remains granted');
select ok(not has_function_privilege('anon','public.challenge_detail_v1(uuid)','execute'), 'anonymous detail remains denied');

select pg_temp.login_beta(1);
insert into beta_ids values('own',pg_temp.beta_create());
select lives_ok($$select public.challenge_detail_v1((select id from beta_ids where name='own'))$$, 'an unbounded active session remains valid');
reset role;
update auth.sessions set not_after=clock_timestamp()+interval '1 minute' where id=pg_temp.br(1);
select pg_temp.login_beta(1);
select lives_ok($$select public.challenge_detail_v1((select id from beta_ids where name='own'))$$, 'an unexpired finite session remains valid');
reset role;
update auth.sessions set not_after=clock_timestamp() where id=pg_temp.br(1);
select pg_temp.login_beta(1);
select throws_ok($$select public.challenge_detail_v1((select id from beta_ids where name='own'))$$, '42501', 'challenge_session_required', 'expiry at the current clock denies private detail');
reset role;
update auth.sessions set not_after=null where id=pg_temp.br(1);
select pg_temp.login_beta(1);
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.ba(1),'session_id',pg_temp.br(2))::text,true);
select throws_ok($$select public.challenge_detail_v1((select id from beta_ids where name='own'))$$, '42501', 'challenge_session_required', 'another actor session never grants detail');
reset role;
insert into auth.users(id) values(pg_temp.ba(41));
insert into auth.sessions(id,user_id) values(pg_temp.br(41),pg_temp.ba(41));
select pg_temp.login_beta(41);
select throws_ok($$select public.challenge_detail_v1((select id from beta_ids where name='own'))$$, '42501', 'challenge_session_required', 'a session without an active profile binding grants no detail');
reset role;
select * from finish();
rollback;
