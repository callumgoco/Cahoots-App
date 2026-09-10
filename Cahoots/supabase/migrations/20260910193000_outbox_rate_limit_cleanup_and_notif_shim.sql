-- Cleanup sent push outbox / stale rate-limit buckets; restore notification settings
-- private DEFINER + public invoker shim; fix rate_limit_policy search_path.

-- ---------------------------------------------------------------------------
-- 1. rate_limit_policy search_path (Advisor WARN)
-- ---------------------------------------------------------------------------
create or replace function private.rate_limit_policy(action_input text)
returns table(max_hits integer, window_seconds integer)
language sql
immutable
set search_path = public
as $$
  select caps.max_hits, caps.window_seconds
  from (
    values
      ('app_snapshot', 60, 60),
      ('clip_upload_url', 20, 3600),
      ('clip_download_url', 60, 60),
      ('invite_redeem', 10, 3600),
      ('submit_report', 5, 3600)
  ) as caps(action, max_hits, window_seconds)
  where caps.action = action_input;
$$;

revoke all on function private.rate_limit_policy(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Cleanup push_outbox + rate_limit_buckets
-- ---------------------------------------------------------------------------
create or replace function private.cleanup_push_and_rate_limits()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.push_outbox
  where sent_at is not null
    and sent_at < now() - interval '7 days';

  delete from public.push_outbox
  where sent_at is null
    and created_at < now() - interval '14 days';

  delete from private.rate_limit_buckets
  where window_start < now() - interval '2 days';
end;
$$;

revoke all on function private.cleanup_push_and_rate_limits() from public, anon, authenticated;
grant execute on function private.cleanup_push_and_rate_limits() to service_role;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'cleanup-push-and-rate-limits') then
    perform cron.unschedule('cleanup-push-and-rate-limits');
  end if;
  perform cron.schedule(
    'cleanup-push-and-rate-limits',
    '15 3 * * *',
    $cron$select private.cleanup_push_and_rate_limits();$cron$
  );
exception
  when undefined_table then
    raise notice 'pg_cron unavailable; skip cleanup schedule';
  when undefined_function then
    raise notice 'cron.schedule unavailable; skip cleanup schedule';
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. upsert_notification_settings: private DEFINER + public INVOKER shim
-- ---------------------------------------------------------------------------
create or replace function private.upsert_notification_settings(settings_input jsonb)
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

create or replace function public.upsert_notification_settings(settings_input jsonb)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  perform private.upsert_notification_settings(settings_input);
end;
$$;

revoke all on function private.upsert_notification_settings(jsonb) from public, anon;
grant execute on function private.upsert_notification_settings(jsonb) to authenticated, service_role;

revoke all on function public.upsert_notification_settings(jsonb) from public, anon;
grant execute on function public.upsert_notification_settings(jsonb) to authenticated, service_role;
