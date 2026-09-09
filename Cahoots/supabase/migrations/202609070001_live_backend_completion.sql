-- Live backend completion: profile bootstrap, missing RPCs, storage, realtime, cron.
begin;

-- ---------------------------------------------------------------------------
-- Profile bootstrap on auth.users insert
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  chosen_name text;
  apple_sub text;
begin
  chosen_name := coalesce(
    nullif(trim(new.raw_user_meta_data->>'display_name'), ''),
    nullif(trim(split_part(coalesce(new.email, ''), '@', 1)), ''),
    'New member'
  );
  if char_length(chosen_name) < 2 then
    chosen_name := 'New member';
  end if;
  if char_length(chosen_name) > 40 then
    chosen_name := left(chosen_name, 40);
  end if;

  apple_sub := nullif(trim(new.raw_user_meta_data->>'provider_id'), '');
  if apple_sub is null and new.raw_app_meta_data->>'provider' = 'apple' then
    apple_sub := nullif(trim(new.raw_user_meta_data->>'sub'), '');
  end if;

  insert into public.profiles(id, display_name, apple_subject_id, timezone_identifier)
  values (
    new.id,
    chosen_name,
    apple_sub,
    coalesce(nullif(trim(new.raw_user_meta_data->>'timezone'), ''), 'UTC')
  )
  on conflict (id) do nothing;

  insert into public.notification_preferences(user_id, group_id)
  values (new.id, null)
  on conflict do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create policy profiles_insert_self on public.profiles
  for insert with check (id = auth.uid());

-- ---------------------------------------------------------------------------
-- Columns for client-decoded fields
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists appearance_preference text not null default 'system'
    check (appearance_preference in ('system', 'light', 'dark'));

alter table public.notification_preferences
  add column if not exists primer_dismissed boolean not null default false;

alter table public.notification_preferences
  add column if not exists default_reminder_minutes smallint not null default 1080
    check (default_reminder_minutes between 0 and 1439);

-- ---------------------------------------------------------------------------
-- Challenge results (previousRound / roundResults wire fields)
-- ---------------------------------------------------------------------------
create table if not exists public.round_results (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  challenge_id uuid not null unique references public.challenges(id) on delete cascade,
  title text not null,
  winner_name text not null,
  top_three jsonb not null default '[]'::jsonb,
  members jsonb not null default '[]'::jsonb,
  total_completions integer not null default 0,
  personal_best integer not null default 0,
  completed_at timestamptz not null default now()
);

alter table public.round_results enable row level security;

create policy round_results_member_read on public.round_results
  for select using (public.is_active_group_member(group_id));

create or replace function public.complete_challenge(challenge_id_input uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.challenges%rowtype;
  result_id uuid;
  winner text := 'Nobody';
  top_three jsonb := '[]'::jsonb;
  members jsonb := '[]'::jsonb;
  total_completions integer := 0;
begin
  select * into c from public.challenges where id = challenge_id_input for update;
  if not found then raise exception 'not_found'; end if;
  if c.status = 'completed' then
    select id into result_id from public.round_results where challenge_id = c.id;
    return result_id;
  end if;

  update public.challenges set status = 'completed' where id = c.id;

  with ranked as (
    select p.display_name, p.id as user_id,
           coalesce(sum(se.points), 0)::integer as points,
           count(distinct se.submission_id) filter (where se.event_type = 'requirement_completed')::integer as completions
    from public.group_memberships gm
    join public.profiles p on p.id = gm.user_id
    left join public.score_events se on se.challenge_id = c.id and se.user_id = p.id
    where gm.group_id = c.group_id and gm.status = 'active'
    group by p.id, p.display_name
    order by points desc, completions desc, p.display_name
  )
  select
    coalesce((select display_name from ranked order by points desc limit 1), 'Nobody'),
    coalesce((select jsonb_agg(jsonb_build_object('displayName', display_name, 'points', points, 'completions', completions)) from (select * from ranked limit 3) t), '[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object('userID', user_id, 'displayName', display_name, 'points', points, 'completions', completions)) from ranked), '[]'::jsonb),
    coalesce((select sum(completions)::integer from ranked), 0)
  into winner, top_three, members, total_completions
  from (select 1) _;

  insert into public.round_results(group_id, challenge_id, title, winner_name, top_three, members, total_completions, personal_best, completed_at)
  values (c.group_id, c.id, c.title, winner, top_three, members, total_completions, 0, now())
  on conflict (challenge_id) do update set completed_at = excluded.completed_at
  returning id into result_id;

  insert into public.activity_feed_items(group_id, actor_id, event_type, message)
  values (c.group_id, null, 'round_finished', c.title || ' finished. Winner: ' || winner || '.');

  -- Activate any scheduled successor whose start date has arrived.
  update public.challenges
  set status = 'active'
  where group_id = c.group_id and status = 'scheduled' and start_date <= (now() at time zone challenge_timezone)::date;

  return result_id;
end;
$$;

-- Activate scheduled challenges whose start date has arrived.
create or replace function public.activate_due_challenges()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare activated integer := 0;
begin
  with due as (
    update public.challenges
    set status = 'active'
    where status = 'scheduled'
      and start_date <= (now() at time zone challenge_timezone)::date
      and not exists (
        select 1 from public.challenges active
        where active.group_id = challenges.group_id and active.status = 'active'
      )
    returning id
  )
  select count(*) into activated from due;
  return activated;
end;
$$;

create or replace function public.finalize_expired_votes()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare done integer := 0; proposal_row record;
begin
  for proposal_row in
    select id from public.challenge_proposals
    where status = 'voting' and voting_ends_at <= now()
  loop
    perform public.finalize_vote(proposal_row.id);
    done := done + 1;
  end loop;
  return done;
end;
$$;

create or replace function public.complete_due_challenges()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare done integer := 0; challenge_row record;
begin
  for challenge_row in
    select id from public.challenges
    where status = 'active'
      and end_date < (now() at time zone challenge_timezone)::date
  loop
    perform public.complete_challenge(challenge_row.id);
    done := done + 1;
  end loop;
  return done;
end;
$$;

-- ---------------------------------------------------------------------------
-- Missing mutation RPCs
-- ---------------------------------------------------------------------------
create or replace function public.update_my_profile(
  display_name_input text default null,
  appearance_input text default null,
  shows_exact_totals_input boolean default null,
  timezone_input text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  update public.profiles set
    display_name = coalesce(nullif(trim(display_name_input), ''), display_name),
    appearance_preference = case
      when appearance_input in ('system', 'light', 'dark') then appearance_input
      else appearance_preference
    end,
    shows_exact_totals = coalesce(shows_exact_totals_input, shows_exact_totals),
    timezone_identifier = coalesce(nullif(trim(timezone_input), ''), timezone_identifier),
    updated_at = now()
  where id = auth.uid();
end;
$$;

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
      coalesce((group_row->>'friendActivityMode')::public.notification_level, 'digest'),
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

create or replace function public.create_and_open_proposal(
  group_id_input uuid,
  title_input text,
  activity_type_input text,
  measurement_type_input public.measurement_type,
  minimum_quantity_input numeric,
  frequency_type_input public.frequency_type,
  scheduled_weekdays_input smallint[],
  duration_days_input smallint,
  proposed_start_date_input date,
  challenge_timezone_input text,
  daily_deadline_minutes_input smallint,
  recovery_day_allowance_input smallint
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
  starts_at timestamptz := now();
begin
  if not public.is_active_group_member(group_id_input) then raise exception 'not_allowed'; end if;
  if exists(select 1 from public.challenge_proposals where group_id = group_id_input and status = 'voting') then
    raise exception 'vote_already_open';
  end if;
  if exists(select 1 from public.challenges where group_id = group_id_input and status = 'scheduled') then
    raise exception 'successor_already_scheduled';
  end if;

  insert into public.challenge_proposals(
    group_id, proposed_by, title, activity_type, measurement_type, minimum_quantity,
    frequency_type, scheduled_weekdays, duration_days, proposed_start_date,
    challenge_timezone, daily_deadline_minutes, recovery_day_allowance,
    voting_starts_at, voting_ends_at, status
  ) values (
    group_id_input, auth.uid(), trim(title_input), trim(activity_type_input),
    measurement_type_input, minimum_quantity_input, frequency_type_input,
    coalesce(scheduled_weekdays_input, '{}'), duration_days_input, proposed_start_date_input,
    challenge_timezone_input, daily_deadline_minutes_input, recovery_day_allowance_input,
    starts_at, starts_at + interval '48 hours', 'voting'
  ) returning id into new_id;

  insert into public.proposal_eligible_voters(proposal_id, user_id)
  select new_id, user_id from public.group_memberships
  where group_id = group_id_input and status = 'active';

  insert into public.activity_feed_items(group_id, actor_id, event_type, message)
  values (group_id_input, auth.uid(), 'proposal', 'A new challenge proposal is open for voting.');

  return new_id;
end;
$$;

create or replace function public.start_round_now(
  group_id_input uuid,
  title_input text,
  activity_type_input text,
  measurement_type_input public.measurement_type,
  minimum_quantity_input numeric,
  frequency_type_input public.frequency_type,
  scheduled_weekdays_input smallint[],
  duration_days_input smallint,
  start_date_input date,
  challenge_timezone_input text,
  daily_deadline_minutes_input smallint,
  recovery_day_allowance_input smallint
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
  end_date_val date;
  status_val public.challenge_status;
begin
  if not public.is_active_group_member(group_id_input) then raise exception 'not_allowed'; end if;
  if exists(select 1 from public.challenge_proposals where group_id = group_id_input and status = 'voting') then
    raise exception 'vote_already_open';
  end if;
  if exists(select 1 from public.challenges where group_id = group_id_input and status = 'scheduled') then
    raise exception 'successor_already_scheduled';
  end if;
  if exists(select 1 from public.challenges where group_id = group_id_input and status = 'active')
     and start_date_input <= (select end_date from public.challenges where group_id = group_id_input and status = 'active') then
    raise exception 'overlaps_active_round';
  end if;

  end_date_val := start_date_input + (duration_days_input - 1);
  status_val := case
    when start_date_input <= (now() at time zone challenge_timezone_input)::date then 'active'::public.challenge_status
    else 'scheduled'::public.challenge_status
  end;

  if status_val = 'active' and exists(select 1 from public.challenges where group_id = group_id_input and status = 'active') then
    raise exception 'active_round_exists';
  end if;

  insert into public.challenges(
    group_id, title, activity_type, measurement_type, minimum_quantity, frequency_type,
    scheduled_weekdays, start_date, end_date, challenge_timezone, daily_deadline_minutes,
    recovery_day_allowance, status
  ) values (
    group_id_input, trim(title_input), trim(activity_type_input), measurement_type_input,
    minimum_quantity_input, frequency_type_input, coalesce(scheduled_weekdays_input, '{}'),
    start_date_input, end_date_val, challenge_timezone_input, daily_deadline_minutes_input,
    recovery_day_allowance_input, status_val
  ) returning id into new_id;

  insert into public.activity_feed_items(group_id, actor_id, event_type, message)
  values (group_id_input, auth.uid(), 'challenge_started', 'A new round was started: ' || trim(title_input) || '.');

  return new_id;
end;
$$;

create or replace function public.update_group_settings(
  group_id_input uuid,
  name_input text,
  emoji_input text,
  member_limit_input smallint
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare active_count integer;
begin
  if not public.is_group_admin(group_id_input) then raise exception 'not_allowed'; end if;
  select count(*) into active_count from public.group_memberships where group_id = group_id_input and status = 'active';
  if member_limit_input < active_count or member_limit_input < 2 or member_limit_input > 20 then
    raise exception 'invalid_member_limit';
  end if;
  update public.groups set
    name = trim(name_input),
    emoji = coalesce(nullif(trim(emoji_input), ''), '⚡️'),
    member_limit = member_limit_input,
    updated_at = now()
  where id = group_id_input;
end;
$$;

create or replace function public.set_member_role(
  group_id_input uuid,
  user_id_input uuid,
  role_input public.group_role
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if role_input = 'owner' then raise exception 'use_transfer_ownership'; end if;
  if not public.is_group_admin(group_id_input) then raise exception 'not_allowed'; end if;
  if user_id_input = auth.uid() then raise exception 'not_allowed'; end if;
  if user_id_input = (select owner_id from public.groups where id = group_id_input) then
    raise exception 'cannot_change_owner_role';
  end if;
  update public.group_memberships
  set role = role_input
  where group_id = group_id_input and user_id = user_id_input and status = 'active';
end;
$$;

create or replace function public.transfer_group_ownership(
  group_id_input uuid,
  new_owner_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if (select owner_id from public.groups where id = group_id_input) <> auth.uid() then
    raise exception 'not_allowed';
  end if;
  if new_owner_id = auth.uid() then raise exception 'not_allowed'; end if;
  if not exists(
    select 1 from public.group_memberships
    where group_id = group_id_input and user_id = new_owner_id and status = 'active'
  ) then raise exception 'not_a_member'; end if;

  update public.group_memberships set role = 'admin'
  where group_id = group_id_input and user_id = auth.uid();
  update public.group_memberships set role = 'owner'
  where group_id = group_id_input and user_id = new_owner_id;
  update public.groups set owner_id = new_owner_id, updated_at = now()
  where id = group_id_input;
end;
$$;

create or replace function public.leave_group(group_id_input uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  membership public.group_memberships%rowtype;
  active_count integer;
begin
  select * into membership from public.group_memberships
  where group_id = group_id_input and user_id = auth.uid() and status = 'active';
  if not found then raise exception 'not_a_member'; end if;

  select count(*) into active_count from public.group_memberships
  where group_id = group_id_input and status = 'active';

  if membership.role = 'owner' and active_count > 1 then
    raise exception 'transfer_ownership_required';
  end if;

  update public.group_memberships
  set status = 'left', left_at = now()
  where id = membership.id;

  if membership.role = 'owner' and active_count = 1 then
    update public.groups set archived_at = now(), updated_at = now() where id = group_id_input;
    update public.group_invites set revoked_at = now()
    where group_id = group_id_input and revoked_at is null;
  end if;
end;
$$;

create or replace function public.revoke_group_invites(group_id_input uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_group_admin(group_id_input) then raise exception 'not_allowed'; end if;
  update public.group_invites set revoked_at = now()
  where group_id = group_id_input and revoked_at is null;
end;
$$;

create or replace function public.regenerate_group_invite(group_id_input uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  new_code text;
  limit_val smallint;
begin
  if not public.is_group_admin(group_id_input) then raise exception 'not_allowed'; end if;
  select member_limit into limit_val from public.groups where id = group_id_input;
  update public.group_invites set revoked_at = now()
  where group_id = group_id_input and revoked_at is null;

  loop
    select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', floor(random() * 32 + 1)::integer, 1), '')
    into new_code from generate_series(1, 6);
    exit when not exists(select 1 from public.group_invites where code = new_code);
  end loop;

  insert into public.group_invites(group_id, code, created_by, expires_at, maximum_uses, use_count)
  values (group_id_input, new_code, auth.uid(), now() + interval '14 days', limit_val, 0);
  return new_code;
end;
$$;

create or replace function public.block_user(blocked_user_id_input uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or blocked_user_id_input = auth.uid() then raise exception 'not_allowed'; end if;
  insert into public.blocked_users(blocker_id, blocked_user_id)
  values (auth.uid(), blocked_user_id_input)
  on conflict (blocker_id, blocked_user_id) do nothing;
end;
$$;

create or replace function public.unblock_user(blocked_user_id_input uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.blocked_users
  where blocker_id = auth.uid() and blocked_user_id = blocked_user_id_input;
end;
$$;

create or replace function public.submit_report(
  reported_user_id_input uuid,
  group_id_input uuid,
  reason_input text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare new_id uuid;
begin
  if not public.is_active_group_member(group_id_input) then raise exception 'not_allowed'; end if;
  if char_length(trim(reason_input)) < 2 then raise exception 'invalid_reason'; end if;
  insert into public.reports(reporter_id, reported_user_id, group_id, reason)
  values (auth.uid(), reported_user_id_input, group_id_input, left(trim(reason_input), 280))
  returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.register_push_token(
  token_input text,
  environment_input text
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if environment_input not in ('sandbox', 'production') then raise exception 'invalid_environment'; end if;
  insert into public.device_push_tokens(user_id, token, environment)
  values (auth.uid(), token_input, environment_input)
  on conflict (token) do update set user_id = excluded.user_id, environment = excluded.environment;
end;
$$;

-- ---------------------------------------------------------------------------
-- Leaderboard view: security invoker so RLS applies
-- ---------------------------------------------------------------------------
drop view if exists public.leaderboard;
create view public.leaderboard
with (security_invoker = on)
as
select c.id challenge_id, c.group_id, p.id user_id, p.display_name,
       coalesce(sum(se.points), 0)::integer points,
       count(distinct se.submission_id) filter (where se.event_type = 'requirement_completed')::integer completed_requirements,
       max(se.created_at) final_score_achieved_at
from public.challenges c
join public.group_memberships gm on gm.group_id = c.group_id and gm.status = 'active'
join public.profiles p on p.id = gm.user_id
left join public.score_events se on se.challenge_id = c.id and se.user_id = p.id
group by c.id, c.group_id, p.id, p.display_name;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
grant execute on function public.update_my_profile(text, text, boolean, text) to authenticated;
grant execute on function public.upsert_notification_settings(jsonb) to authenticated;
grant execute on function public.create_and_open_proposal(uuid, text, text, public.measurement_type, numeric, public.frequency_type, smallint[], smallint, date, text, smallint, smallint) to authenticated;
grant execute on function public.start_round_now(uuid, text, text, public.measurement_type, numeric, public.frequency_type, smallint[], smallint, date, text, smallint, smallint) to authenticated;
grant execute on function public.update_group_settings(uuid, text, text, smallint) to authenticated;
grant execute on function public.set_member_role(uuid, uuid, public.group_role) to authenticated;
grant execute on function public.transfer_group_ownership(uuid, uuid) to authenticated;
grant execute on function public.leave_group(uuid) to authenticated;
grant execute on function public.revoke_group_invites(uuid) to authenticated;
grant execute on function public.regenerate_group_invite(uuid) to authenticated;
grant execute on function public.block_user(uuid) to authenticated;
grant execute on function public.unblock_user(uuid) to authenticated;
grant execute on function public.submit_report(uuid, uuid, text) to authenticated;
grant execute on function public.register_push_token(text, text) to authenticated;
grant execute on function public.complete_challenge(uuid) to authenticated;
grant execute on function public.finalize_vote(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Realtime publication
-- ---------------------------------------------------------------------------
do $$
begin
  begin
    alter publication supabase_realtime add table public.challenge_proposals;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.votes;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.challenges;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.activity_feed_items;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.score_events;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.submissions;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.group_memberships;
  exception when duplicate_object then null;
  end;
end;
$$;

-- ---------------------------------------------------------------------------
-- Storage: private workout-proofs bucket
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'workout-proofs',
  'workout-proofs',
  false,
  52428800,
  array['video/quicktime', 'video/mp4', 'video/x-m4v']
)
on conflict (id) do nothing;

-- Path: {group_id}/{challenge_id}/{requirement_date}/{user_id}/{clip_id}.mov
-- Segment 4 (1-indexed) is the owner user_id.
create policy workout_proofs_insert_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'workout-proofs'
    and (storage.foldername(name))[4] = auth.uid()::text
  );

create policy workout_proofs_update_own on storage.objects
  for update to authenticated
  using (
    bucket_id = 'workout-proofs'
    and (storage.foldername(name))[4] = auth.uid()::text
  );

create policy workout_proofs_delete_own on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'workout-proofs'
    and (storage.foldername(name))[4] = auth.uid()::text
  );

-- No direct select policy — clients use signed URLs after can_reveal_submission.

-- ---------------------------------------------------------------------------
-- Cron jobs (pg_cron + pg_net when available)
-- ---------------------------------------------------------------------------
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

-- Direct SQL jobs for vote finalisation, challenge lifecycle, and clip purge.
do $$
begin
  if not exists (select 1 from cron.job where jobname = 'finalize-expired-votes') then
    perform cron.schedule('finalize-expired-votes', '*/5 * * * *', 'select public.finalize_expired_votes();');
  end if;
  if not exists (select 1 from cron.job where jobname = 'activate-due-challenges') then
    perform cron.schedule('activate-due-challenges', '*/15 * * * *', 'select public.activate_due_challenges();');
  end if;
  if not exists (select 1 from cron.job where jobname = 'complete-due-challenges') then
    perform cron.schedule('complete-due-challenges', '*/15 * * * *', 'select public.complete_due_challenges();');
  end if;
  if not exists (select 1 from cron.job where jobname = 'purge-expired-workout-clips') then
    perform cron.schedule('purge-expired-workout-clips', '0 3 * * *', 'select public.purge_expired_workout_clips();');
  end if;
end;
$$;

commit;
