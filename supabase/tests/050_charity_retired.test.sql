-- D143: charity is retired. The curated list, the per-participant nomination
-- and donation obligations are gone, and the legacy model no longer names a
-- charity. The rest of the legacy contest lifecycle is covered where it lives.

begin;
select plan(8);

select hasnt_table('public', 'charities', 'the charity list is gone');
select hasnt_table('public', 'donation_obligations', 'donation obligations are gone');
select hasnt_type('public', 'donation_obligation_kind', 'the obligation kind type is gone');
select hasnt_column(
  'public', 'contest_participants', 'charity_id',
  'a participant no longer nominates a charity'
);

select has_function(
  'public',
  'create_contest',
  array['text', 'contest_metric', 'contest_cadence', 'numeric', 'integer',
        'timestamp with time zone', 'timestamp with time zone', 'text',
        'smallint', 'contest_tie_break', 'uuid'],
  'contest creation takes no charity'
);

select has_function(
  'public',
  'create_contest_with_invites_v1',
  array['uuid', 'text', 'contest_metric', 'contest_cadence', 'numeric',
        'integer', 'timestamp with time zone', 'timestamp with time zone',
        'text', 'uuid[]', 'smallint', 'contest_tie_break', 'uuid'],
  'contest creation with invitations takes no charity'
);

select is(
  (select array_agg(enumlabel::text order by enumsortorder)
   from pg_enum
   where enumtypid = 'public.challenge_model'::regtype),
  array['legacy_social_contest', 'personal_accountability', 'social_accountability'],
  'the legacy model no longer names a charity'
);

select is(
  (select count(*)
   from pg_proc procedure
   join pg_namespace namespace on namespace.oid = procedure.pronamespace
   where namespace.nspname in ('public', 'app')
     and procedure.prosrc ~* 'charit|donation_obligation'),
  0::bigint,
  'no public or app function reads or writes a charity'
);

select * from finish();
rollback;
