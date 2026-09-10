-- Product default: friend-posted alerts are immediate on first load.
-- Digest remains available in Settings for users who prefer a daily summary.

alter table public.group_memberships
  alter column notification_level set default 'immediate';

alter table public.notification_preferences
  alter column friend_activity_mode set default 'immediate';

update public.notification_preferences
set friend_activity_mode = 'immediate'
where friend_activity_mode = 'digest';

update public.group_memberships
set notification_level = 'immediate'
where notification_level = 'digest';

create or replace function public.upsert_notification_settings(settings_input jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  group_row jsonb;
  group_id_val uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;

  insert into public.notification_preferences(
    user_id, group_id, quiet_hours_start, quiet_hours_end,
    default_reminder_minutes, primer_dismissed, reminder_minutes
  ) values (
    auth.uid(), null,
    coalesce((settings_input->>'quietHoursStart')::smallint, 1320),
    coalesce((settings_input->>'quietHoursEnd')::smallint, 420),
    coalesce((settings_input->>'defaultReminderMinutes')::smallint, 1080),
    coalesce((settings_input->>'primerDismissed')::boolean, false),
    coalesce((settings_input->>'defaultReminderMinutes')::smallint, 1080)
  )
  on conflict (user_id, group_id) do update set
    quiet_hours_start = excluded.quiet_hours_start,
    quiet_hours_end = excluded.quiet_hours_end,
    default_reminder_minutes = excluded.default_reminder_minutes,
    primer_dismissed = excluded.primer_dismissed,
    reminder_minutes = excluded.reminder_minutes;

  for group_row in select * from jsonb_array_elements(coalesce(settings_input->'groups', '[]'::jsonb))
  loop
    group_id_val := (group_row->>'groupID')::uuid;
    if group_id_val is null or not public.is_active_group_member(group_id_val) then
      continue;
    end if;
    insert into public.notification_preferences(
      user_id, group_id, personal_reminders_enabled, friend_activity_mode,
      challenge_updates_enabled, reminder_minutes
    ) values (
      auth.uid(), group_id_val,
      coalesce((group_row->>'personalRemindersEnabled')::boolean, true),
      coalesce((group_row->>'friendActivityMode')::public.notification_level, 'immediate'),
      coalesce((group_row->>'challengeUpdatesEnabled')::boolean, true),
      nullif(group_row->>'reminderMinutes', '')::smallint
    )
    on conflict (user_id, group_id) do update set
      personal_reminders_enabled = excluded.personal_reminders_enabled,
      friend_activity_mode = excluded.friend_activity_mode,
      challenge_updates_enabled = excluded.challenge_updates_enabled,
      reminder_minutes = excluded.reminder_minutes;
  end loop;
end;
$$;
