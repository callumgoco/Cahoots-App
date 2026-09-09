-- Development-only seed. Create matching auth.users in the local dashboard first,
-- then replace these UUIDs if you want to exercise the live client locally.
insert into public.profiles(id, display_name, timezone_identifier) values
  ('00000000-0000-0000-0000-000000000001', 'You', 'Europe/London'),
  ('00000000-0000-0000-0000-000000000002', 'Jennifer Hale', 'Europe/London'),
  ('00000000-0000-0000-0000-000000000003', 'Marcus Lee', 'Europe/London')
on conflict do nothing;

