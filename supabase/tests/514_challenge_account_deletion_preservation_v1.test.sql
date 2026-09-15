-- Local-only preservation coverage for account deletion. Every participant,
-- Apple subject, receipt, and result is fictional; this transaction rolls
-- back. It deliberately exercises active two/six-person, Personal, and
-- fixture-only community exits rather than manufacturing finals.
begin;
select plan(19);
\ir fixtures/challenge-fixture.inc
\ir fixtures/challenge-matrix-fixture.inc

create temp table deletion_preservation(
  name text primary key,
  actor_id uuid not null,
  request_id uuid not null,
  receipt text not null,
  apple_subject text not null
);

-- A two-person challenge safely voids when deleting one active member. The
-- resulting final must be created by the normal lifecycle and never rewritten.
insert into beta_ids values ('pair', pg_temp.beta_group(1, 2));
insert into deletion_preservation values
  ('pair', pg_temp.ba(1), 'd1400000-0000-4000-8000-000000000001',
   'local_pair_deletion_receipt_012345678901234567890123456789',
   'fictional-apple-preservation-pair');
select public.challenge_begin_account_deletion_v1(
  actor_id, request_id, receipt, apple_subject
) from deletion_preservation where name = 'pair';
select ok(exists(
  select 1 from app.challenge_finals_v1
  where challenge_id = (select id from beta_ids where name = 'pair')
), 'two-person deletion reaches a normal safe final');
select is((
  select status from app.challenge_lobbies_v1
  where id = (select id from beta_ids where name = 'pair')
), 'void', 'two-person deletion safely returns an insufficient roster');
select ok(exists(
  select 1 from app.challenge_consents_v1
  where challenge_id = (select id from beta_ids where name = 'pair')
    and actor_id = pg_temp.ba(1)
), 'accepted deletion retains the deleted member consent during the 180-day window');
create temp table immutable_finals as
select challenge_id, result, revision
from app.challenge_finals_v1
where challenge_id = (select id from beta_ids where name = 'pair');
select public.challenge_process_v1((select id from beta_ids where name = 'pair'));
select is((
  select row(result, revision)::text from app.challenge_finals_v1
  where challenge_id = (select id from beta_ids where name = 'pair')
), (
  select row(result, revision)::text from immutable_finals
  where challenge_id = (select id from beta_ids where name = 'pair')
), 'a post-deletion lifecycle retry cannot rewrite the two-person final');

-- A six-person active group continues with the five remaining fictional
-- participants, preserving both agreement text/digest and the deleted
-- participant's consent while the separate retention period is active.
insert into beta_ids values ('six', pg_temp.beta_group(3, 6));
create temp table agreement_before as
select challenge_id, digest, terms
from app.challenge_agreements_v1
where challenge_id = (select id from beta_ids where name = 'six');
insert into deletion_preservation values
  ('six', pg_temp.ba(8), 'd1400000-0000-4000-8000-000000000002',
   'local_six_deletion_receipt_012345678901234567890123456789',
   'fictional-apple-preservation-six');
select public.challenge_begin_account_deletion_v1(
  actor_id, request_id, receipt, apple_subject
) from deletion_preservation where name = 'six';
select is((
  select count(*) from app.challenge_members_v1
  where challenge_id = (select id from beta_ids where name = 'six')
    and exited_at is null
), 5::bigint, 'six-person deletion leaves five active fictional participants');
select is((
  select status from app.challenge_lobbies_v1
  where id = (select id from beta_ids where name = 'six')
), 'scheduled', 'six-person deletion does not prematurely cancel the remaining group');
select pg_temp.clock_beta('2026-10-10T06:00Z', false, true);
select public.challenge_capture_fixture_v1(
  extensions.gen_random_uuid(), (select id from beta_ids where name = 'six'),
  pg_temp.ba(n), case when n < 7 then 20000 else 0 end, 'complete'
) from generate_series(3, 7) n;
select pg_temp.clock_beta('2026-10-12T06:00Z', false, true);
select public.challenge_process_v1((select id from beta_ids where name = 'six'));
select pg_temp.clock_beta('2026-10-14T06:00Z', false, true);
select is(public.challenge_process_v1((select id from beta_ids where name = 'six')),
  'final', 'five remaining members can reach a normal six-person final');
select ok((
  select result->'participants'->pg_temp.ba(8)::text->>'returned_cents' = '100'
  from app.challenge_finals_v1
  where challenge_id = (select id from beta_ids where name = 'six')
), 'the deleted sixth member receives the normal non-punitive simulated return');
select is((
  select row(digest, terms)::text from app.challenge_agreements_v1
  where challenge_id = (select id from beta_ids where name = 'six')
), (
  select row(digest, terms)::text from agreement_before
), 'deletion preserves the historical agreement meaning for the other members');
select ok(exists(
  select 1 from app.challenge_consents_v1
  where challenge_id = (select id from beta_ids where name = 'six')
    and actor_id = pg_temp.ba(8)
), 'deletion preserves the sixth member consent until its approved cleanup date');
insert into immutable_finals
select challenge_id, result, revision from app.challenge_finals_v1
where challenge_id = (select id from beta_ids where name = 'six');
select public.challenge_process_v1((select id from beta_ids where name = 'six'));
select is((
  select row(result, revision)::text from app.challenge_finals_v1
  where challenge_id = (select id from beta_ids where name = 'six')
), (
  select row(result, revision)::text from immutable_finals
  where challenge_id = (select id from beta_ids where name = 'six')
), 'a deletion-safe six-person final remains immutable on retry');

-- Personal remains its own product meaning. The safe exit makes a normal void
-- final but does not delete its agreement or consent during the minimum window.
insert into beta_ids values ('personal', pg_temp.matrix_create('personal_steps_goal_v1', 9));
create temp table personal_before as
select agreement.challenge_id, agreement.digest, agreement.terms
from app.challenge_agreements_v1 agreement
where agreement.challenge_id = (select id from beta_ids where name = 'personal');
insert into deletion_preservation values
  ('personal', pg_temp.ba(9), 'd1400000-0000-4000-8000-000000000003',
   'local_personal_deletion_receipt_012345678901234567890123456789',
   'fictional-apple-preservation-personal');
select public.challenge_begin_account_deletion_v1(
  actor_id, request_id, receipt, apple_subject
) from deletion_preservation where name = 'personal';
select ok(exists(
  select 1 from app.challenge_finals_v1
  where challenge_id = (select id from beta_ids where name = 'personal')
), 'Personal deletion uses the normal safe-final path');
select is((
  select row(digest, terms)::text from app.challenge_agreements_v1
  where challenge_id = (select id from beta_ids where name = 'personal')
), (
  select row(digest, terms)::text from personal_before
), 'Personal agreement language is preserved without reinterpretation');
select ok(exists(
  select 1 from app.challenge_consents_v1
  where challenge_id = (select id from beta_ids where name = 'personal')
    and actor_id = pg_temp.ba(9)
), 'Personal consent remains during the approved pseudonymous retention period');

-- Community remains explicitly fixture-only. Deleting one of two joined
-- members safely returns the remaining roster and retains its agreement.
insert into beta_ids values ('community', public.challenge_publish_community_fixture_v1(
  pg_temp.br(14001), pg_temp.ba(40),
  '{"start_date":"2026-10-16","days":1,"timezone":"UTC","amount_cents":100}',
  100, 2, 6, true
));
select public.challenge_discovery_fixture_v1(true);
select pg_temp.login_beta(10);
select public.challenge_join_community_v1(pg_temp.br(14010), jsonb_build_object(
  'op', 'join_community', 'id', (select id from beta_ids where name = 'community'),
  'digest', public.challenge_community_catalog_v1()->0->>'digest', 'consent', true
));
select pg_temp.login_beta(11);
select public.challenge_join_community_v1(pg_temp.br(14011), jsonb_build_object(
  'op', 'join_community', 'id', (select id from beta_ids where name = 'community'),
  'digest', public.challenge_community_catalog_v1()->0->>'digest', 'consent', true
));
reset role;
select pg_temp.clock_beta('2026-10-16T12:00Z', false, true);
select is(public.challenge_process_v1((select id from beta_ids where name = 'community')),
  'active', 'the fixture community is active before the deletion-safe exit');
create temp table community_before as
select agreement.challenge_id, agreement.digest, agreement.terms
from app.challenge_agreements_v1 agreement
where agreement.challenge_id = (select id from beta_ids where name = 'community');
insert into deletion_preservation values
  ('community', pg_temp.ba(10), 'd1400000-0000-4000-8000-000000000004',
   'local_community_deletion_receipt_012345678901234567890123456789',
   'fictional-apple-preservation-community');
select public.challenge_begin_account_deletion_v1(
  actor_id, request_id, receipt, apple_subject
) from deletion_preservation where name = 'community';
select is((
  select status from app.challenge_lobbies_v1
  where id = (select id from beta_ids where name = 'community')
), 'void', 'community deletion safely finalizes an insufficient active roster');
select is((
  select row(digest, terms)::text from app.challenge_agreements_v1
  where challenge_id = (select id from beta_ids where name = 'community')
), (
  select row(digest, terms)::text from community_before
), 'fixture community agreement remains immutable after member deletion');
select ok(exists(
  select 1 from app.challenge_consents_v1
  where challenge_id = (select id from beta_ids where name = 'community')
    and actor_id = pg_temp.ba(10)
), 'community consent remains until the minimum retention stage');
select public.challenge_process_v1((select id from beta_ids where name = 'community'));
select ok(exists(
  select 1 from app.challenge_finals_v1
  where challenge_id = (select id from beta_ids where name = 'community')
), 'community final stays present after a lifecycle retry');

select * from finish();
rollback;
