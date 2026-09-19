-- Fictional saved cases shared by rollback, upgrade and HTTP authorization checks.
\ir challenge-fixture.inc
insert into beta_ids values('review_a',pg_temp.beta_group(1,2)),('review_b',pg_temp.beta_group(3,2));
select pg_temp.clock_beta('2026-10-13T12:00Z');
select public.challenge_process_v1(id) from beta_ids;
select pg_temp.login_beta(1);
select pg_temp.beta_mutate((select id from beta_ids where name='review_a'),'review','{"notice_revision":1,"reason":"wrong_total"}',pg_temp.br(95001));
select pg_temp.login_beta(2);
select pg_temp.beta_mutate((select id from beta_ids where name='review_a'),'review','{"notice_revision":1,"reason":"wrong_total"}',pg_temp.br(95002));
select pg_temp.login_beta(3);
select pg_temp.beta_mutate((select id from beta_ids where name='review_b'),'review','{"notice_revision":1,"reason":"wrong_total"}',pg_temp.br(95003));
reset role;
-- Suspension/appeal records are local fixture facts, not new public APIs.
select set_config('app.challenge_write_v1','on',true);
insert into app.challenge_suspensions_v1 values
 (pg_temp.ba(10),true,pg_temp.ba(30),'unsafe_behavior',app.challenge_now_v1()),
 (pg_temp.ba(11),true,pg_temp.ba(30),'unwanted_contact',app.challenge_now_v1());
insert into app.challenge_appeals_v1 values
 (pg_temp.br(95010),pg_temp.ba(10),app.challenge_now_v1(),app.challenge_now_v1()),
 (pg_temp.br(95011),pg_temp.ba(11),app.challenge_now_v1(),app.challenge_now_v1());
