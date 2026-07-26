-- D81 participant departures need their own addressable D80 outbox event.
-- PostgreSQL enum additions must commit before a later migration can safely
-- use the new value in function bodies.
alter type public.notification_event_type
  add value if not exists 'contest_participation_changed';
