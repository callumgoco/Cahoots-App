-- Group-scoped notification rows treat reminder_minutes as optional:
-- NULL means inherit the user's default reminder time. The iOS client
-- omits reminderMinutes in that case, and upsert_notification_settings
-- writes NULL. A NOT NULL column made saving settings fail.

alter table public.notification_preferences
  alter column reminder_minutes drop not null;

alter table public.notification_preferences
  drop constraint if exists notification_preferences_global_reminder_required;

alter table public.notification_preferences
  add constraint notification_preferences_global_reminder_required
  check (group_id is not null or reminder_minutes is not null);

comment on column public.notification_preferences.reminder_minutes is
  'Minutes from local midnight. NULL on group-scoped rows means inherit the user default.';
