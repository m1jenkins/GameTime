-- 20260726070000 is already deployed and must remain immutable. Its BEFORE
-- UPDATE guard compares the full OLD and NEW rows after removing only the two
-- scrubbed source columns. PostgreSQL presents stored generated columns as NULL
-- in NEW until after a BEFORE trigger returns, so visit_range and workout_range
-- also have to be excluded. Their base timestamp columns remain protected by
-- the comparison.
create or replace function app.guard_geofence_checkin_update()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_owner name;
begin
  select role.rolname
    into v_owner
  from pg_catalog.pg_class relation
  join pg_catalog.pg_roles role on role.oid = relation.relowner
  where relation.oid = tg_relid;

  if current_user = v_owner
     and coalesce(
       pg_catalog.current_setting('app.raw_retention_worker', true),
       ''
     ) = 'on'
     and (
       old.workout_id is not null
       or old.workout_source_bundle_id is not null
     )
     and new.workout_id is null
     and new.workout_source_bundle_id is null
     and (
       to_jsonb(new) - array[
         'visit_range',
         'workout_id',
         'workout_range',
         'workout_source_bundle_id'
       ]
       is not distinct from
       to_jsonb(old) - array[
         'visit_range',
         'workout_id',
         'workout_range',
         'workout_source_bundle_id'
       ]
     )
  then
    return new;
  end if;

  raise exception 'geofence check-ins are immutable outside the guarded source-identifier scrub'
    using errcode = 'restrict_violation';
end;
$$;

comment on function app.guard_geofence_checkin_update() is
  'Allows only the retention worker to null check-in source identifiers while preserving every adjudicated/base field; generated ranges are recomputed after the BEFORE trigger.';

revoke all on function app.guard_geofence_checkin_update()
  from public, anon, authenticated, service_role;
