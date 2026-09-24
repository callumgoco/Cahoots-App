-- Production notifications: immediate crew-update dispatch, failed-proposal pushes,
-- and server-side time-based reminders (so they fire without a recent app launch).

-- ---------------------------------------------------------------------------
-- Idempotency for scheduled reminders
-- ---------------------------------------------------------------------------
create table if not exists public.push_reminder_sends (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('daily', 'evening', 'deadline', 'vote', 'roundStarting')),
  subject_id uuid not null,
  requirement_day date not null,
  created_at timestamptz not null default now(),
  unique (user_id, kind, subject_id, requirement_day)
);

create index if not exists push_reminder_sends_created_idx
  on public.push_reminder_sends (created_at);

alter table public.push_reminder_sends enable row level security;
revoke all on table public.push_reminder_sends from public, anon, authenticated;
grant all on table public.push_reminder_sends to service_role;

-- ---------------------------------------------------------------------------
-- Quiet-hours aware single-user outbox insert
-- ---------------------------------------------------------------------------
create or replace function private.enqueue_push_for_user(
  user_id_input uuid,
  title_input text,
  body_input text,
  deep_link_input text,
  quiet_start_input integer,
  quiet_end_input integer,
  member_tz_input text
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted integer := 0;
  token_row record;
  member_tz text := coalesce(nullif(member_tz_input, ''), 'UTC');
  quiet_start integer := coalesce(quiet_start_input, 22 * 60);
  quiet_end integer := coalesce(quiet_end_input, 7 * 60);
  local_minute integer;
  in_quiet boolean;
  send_at timestamptz;
begin
  begin
    local_minute := (
      extract(hour from (now() at time zone member_tz))::integer * 60
      + extract(minute from (now() at time zone member_tz))::integer
    );
  exception when others then
    local_minute := extract(hour from now())::integer * 60 + extract(minute from now())::integer;
    member_tz := 'UTC';
  end;

  if quiet_start <= quiet_end then
    in_quiet := local_minute >= quiet_start and local_minute < quiet_end;
  else
    in_quiet := local_minute >= quiet_start or local_minute < quiet_end;
  end if;

  if in_quiet then
    send_at := (
      date_trunc('day', now() at time zone member_tz)
      + make_interval(mins => quiet_end)
    ) at time zone member_tz;
    if send_at <= now() then
      send_at := send_at + interval '1 day';
    end if;
  else
    send_at := now();
  end if;

  for token_row in
    select token, environment
    from public.device_push_tokens
    where user_id = user_id_input
  loop
    insert into public.push_outbox(
      user_id, token, environment, title, body, deep_link, send_after
    ) values (
      user_id_input,
      token_row.token,
      case when token_row.environment = 'production' then 'production' else 'sandbox' end,
      title_input,
      body_input,
      deep_link_input,
      send_at
    );
    inserted := inserted + 1;
  end loop;

  return inserted;
end;
$$;

revoke all on function private.enqueue_push_for_user(uuid, text, text, text, integer, integer, text)
  from public, anon, authenticated;
grant execute on function private.enqueue_push_for_user(uuid, text, text, text, integer, integer, text)
  to service_role;

-- Claim a reminder slot; returns true when this caller owns the first send.
create or replace function private.claim_reminder_send(
  user_id_input uuid,
  kind_input text,
  subject_id_input uuid,
  requirement_day_input date
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.push_reminder_sends(user_id, kind, subject_id, requirement_day)
  values (user_id_input, kind_input, subject_id_input, requirement_day_input)
  on conflict (user_id, kind, subject_id, requirement_day) do nothing;
  return found;
end;
$$;

revoke all on function private.claim_reminder_send(uuid, text, uuid, date)
  from public, anon, authenticated;
grant execute on function private.claim_reminder_send(uuid, text, uuid, date)
  to service_role;

-- ---------------------------------------------------------------------------
-- Crew updates: enqueue then kick dispatch immediately
-- ---------------------------------------------------------------------------
create or replace function private.enqueue_crew_update_pushes(
  group_id_input uuid,
  actor_id_input uuid,
  title_input text,
  body_input text,
  deep_link_input text
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted integer := 0;
  member record;
  token_row record;
  group_pref public.notification_preferences%rowtype;
  global_pref public.notification_preferences%rowtype;
  updates_enabled boolean;
  quiet_start integer;
  quiet_end integer;
  member_tz text;
  local_minute integer;
  in_quiet boolean;
  send_at timestamptz;
begin
  for member in
    select gm.user_id
    from public.group_memberships gm
    where gm.group_id = group_id_input
      and gm.status = 'active'
      and (actor_id_input is null or gm.user_id <> actor_id_input)
  loop
    select * into group_pref
    from public.notification_preferences
    where user_id = member.user_id and group_id = group_id_input
    limit 1;

    select * into global_pref
    from public.notification_preferences
    where user_id = member.user_id and group_id is null
    limit 1;

    updates_enabled := coalesce(group_pref.challenge_updates_enabled, global_pref.challenge_updates_enabled, true);
    if not updates_enabled then
      continue;
    end if;

    quiet_start := coalesce(group_pref.quiet_hours_start, global_pref.quiet_hours_start, 22 * 60);
    quiet_end := coalesce(group_pref.quiet_hours_end, global_pref.quiet_hours_end, 7 * 60);

    select coalesce(nullif(timezone_identifier, ''), 'UTC') into member_tz
    from public.profiles where id = member.user_id;

    begin
      local_minute := (
        extract(hour from (now() at time zone member_tz))::integer * 60
        + extract(minute from (now() at time zone member_tz))::integer
      );
    exception when others then
      local_minute := extract(hour from now())::integer * 60 + extract(minute from now())::integer;
      member_tz := 'UTC';
    end;

    if quiet_start <= quiet_end then
      in_quiet := local_minute >= quiet_start and local_minute < quiet_end;
    else
      in_quiet := local_minute >= quiet_start or local_minute < quiet_end;
    end if;

    if in_quiet then
      send_at := (
        date_trunc('day', now() at time zone member_tz)
        + make_interval(mins => quiet_end)
      ) at time zone member_tz;
      if send_at <= now() then
        send_at := send_at + interval '1 day';
      end if;
    else
      send_at := now();
    end if;

    for token_row in
      select token, environment
      from public.device_push_tokens
      where user_id = member.user_id
    loop
      insert into public.push_outbox(
        user_id, token, environment, title, body, deep_link, send_after
      ) values (
        member.user_id,
        token_row.token,
        case when token_row.environment = 'production' then 'production' else 'sandbox' end,
        title_input,
        body_input,
        deep_link_input,
        send_at
      );
      inserted := inserted + 1;
    end loop;
  end loop;

  -- Kick dispatch once so ready rows leave without waiting for the minute cron.
  -- pg_net runs after commit, so the new outbox rows are visible to the Edge Function.
  if inserted > 0 then
    perform private.invoke_dispatch_pushes();
  end if;

  return inserted;
end;
$$;

revoke all on function private.enqueue_crew_update_pushes(uuid, uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function private.enqueue_crew_update_pushes(uuid, uuid, text, text, text)
  to service_role;

-- ---------------------------------------------------------------------------
-- Failed proposal: notify every member (including the proposer)
-- ---------------------------------------------------------------------------
create or replace function public.finalize_vote(proposal_id_input uuid)
returns public.proposal_status
language plpgsql
security definer
set search_path = public
as $$
declare
  p public.challenge_proposals%rowtype;
  eligible integer;
  accepts integer;
  total_votes integer;
  required integer;
  outcome public.proposal_status;
  status_val public.challenge_status := 'scheduled';
  feed_message text;
  group_name text;
  push_body text;
begin
  select * into p from public.challenge_proposals where id = proposal_id_input for update;
  if p.status <> 'voting' then return p.status; end if;

  select count(*) into eligible from public.proposal_eligible_voters where proposal_id = p.id;
  select count(*) filter (where choice = 'accept'), count(*)
    into accepts, total_votes
  from public.votes where proposal_id = p.id;

  required := floor(eligible / 2.0) + 1;
  if accepts >= greatest(2, required) then
    outcome := 'passed';
  elsif total_votes = eligible or now() >= p.voting_ends_at then
    outcome := 'failed';
  else
    return 'voting';
  end if;

  update public.challenge_proposals set status = outcome where id = p.id;

  select name into group_name from public.groups where id = p.group_id;

  if outcome = 'passed' then
    status_val := case
      when p.proposed_start_date <= (now() at time zone p.challenge_timezone)::date
           and not exists (
             select 1 from public.challenges
             where group_id = p.group_id and status = 'active'
           )
        then 'active'::public.challenge_status
      else 'scheduled'::public.challenge_status
    end;

    insert into public.challenges(
      group_id, proposal_id, title, activity_type, measurement_type, minimum_quantity,
      frequency_type, scheduled_weekdays, start_date, end_date, challenge_timezone,
      daily_deadline_minutes, recovery_day_allowance, status
    )
    values (
      p.group_id, p.id, p.title, p.activity_type, p.measurement_type, p.minimum_quantity,
      p.frequency_type, p.scheduled_weekdays, p.proposed_start_date,
      p.proposed_start_date + (p.duration_days - 1), p.challenge_timezone,
      p.daily_deadline_minutes, p.recovery_day_allowance, status_val
    )
    on conflict(proposal_id) do nothing;

    feed_message := case
      when status_val = 'active' then 'The proposal passed and the challenge has started.'
      else 'The proposal passed and is scheduled.'
    end;

    push_body := case
      when status_val = 'active' then 'The crew accepted ' || p.title || '. The round is live.'
      else 'The crew accepted ' || p.title || '. It starts ' || to_char(p.proposed_start_date, 'Mon DD') || '.'
    end;
    perform private.enqueue_crew_update_pushes(
      p.group_id,
      null,
      coalesce(group_name, 'Cahoots'),
      push_body,
      'cahoots://log/' || p.group_id::text
    );
  else
    feed_message := 'The proposal did not pass.';
    perform private.enqueue_crew_update_pushes(
      p.group_id,
      null,
      coalesce(group_name, 'Cahoots'),
      'The proposal did not pass.',
      'cahoots://log/' || p.group_id::text
    );
  end if;

  insert into public.activity_feed_items(group_id, actor_id, event_type, message)
  values (p.group_id, null, 'vote_completed', feed_message);

  return outcome;
end;
$$;

-- ---------------------------------------------------------------------------
-- Server reminders (personal + vote closing + round starting)
-- ---------------------------------------------------------------------------
create or replace function private.enqueue_due_reminders()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted integer := 0;
  challenge_row record;
  member_row record;
  proposal_row record;
  group_pref public.notification_preferences%rowtype;
  global_pref public.notification_preferences%rowtype;
  reminders_enabled boolean;
  updates_enabled boolean;
  quiet_start integer;
  quiet_end integer;
  reminder_mins integer;
  member_tz text;
  challenge_tz text;
  local_day date;
  weekday_swift integer;
  is_scheduled boolean;
  deadline_at timestamptz;
  fire_at timestamptz;
  completed boolean;
  recovered boolean;
  pending_others integer;
  evening_body text;
  group_name text;
  deep_link text;
  notify_mins integer;
  day_end timestamptz;
  preferred timestamptz;
begin
  -- Active challenges: daily / evening / deadline personal reminders
  for challenge_row in
    select c.*, g.name as group_name
    from public.challenges c
    join public.groups g on g.id = c.group_id
    where c.status = 'active'
  loop
    challenge_tz := coalesce(nullif(challenge_row.challenge_timezone, ''), 'UTC');
    begin
      local_day := (now() at time zone challenge_tz)::date;
    exception when others then
      challenge_tz := 'UTC';
      local_day := (now() at time zone 'UTC')::date;
    end;

    if local_day < challenge_row.start_date or local_day > challenge_row.end_date then
      continue;
    end if;

    -- Swift Calendar weekday: Sunday=1 … Saturday=7. Postgres dow: Sunday=0 … Saturday=6.
    weekday_swift := extract(dow from local_day)::integer + 1;
    is_scheduled := case challenge_row.frequency_type
      when 'daily' then true
      when 'selected_weekdays' then weekday_swift = any (challenge_row.scheduled_weekdays)
      else true
    end;
    if not is_scheduled then
      continue;
    end if;

    deadline_at := (
      local_day::timestamp + make_interval(mins => challenge_row.daily_deadline_minutes)
    ) at time zone challenge_tz;
    if deadline_at <= now() then
      continue;
    end if;

    group_name := challenge_row.group_name;
    deep_link := 'cahoots://log/' || challenge_row.group_id::text;

    for member_row in
      select gm.user_id, coalesce(nullif(p.timezone_identifier, ''), 'UTC') as timezone_identifier
      from public.group_memberships gm
      join public.profiles p on p.id = gm.user_id
      where gm.group_id = challenge_row.group_id
        and gm.status = 'active'
    loop
      select * into group_pref
      from public.notification_preferences
      where user_id = member_row.user_id and group_id = challenge_row.group_id
      limit 1;

      select * into global_pref
      from public.notification_preferences
      where user_id = member_row.user_id and group_id is null
      limit 1;

      reminders_enabled := coalesce(group_pref.personal_reminders_enabled, global_pref.personal_reminders_enabled, true);
      if not reminders_enabled then
        continue;
      end if;

      quiet_start := coalesce(group_pref.quiet_hours_start, global_pref.quiet_hours_start, 22 * 60);
      quiet_end := coalesce(group_pref.quiet_hours_end, global_pref.quiet_hours_end, 7 * 60);
      reminder_mins := coalesce(group_pref.reminder_minutes, global_pref.reminder_minutes, 18 * 60);
      member_tz := member_row.timezone_identifier;

      select exists(
        select 1 from public.submissions s
        where s.challenge_id = challenge_row.id
          and s.user_id = member_row.user_id
          and s.requirement_date = local_day
          and s.sync_state <> 'rejected'
          and s.verification_state <> 'rejected'
          and s.quantity >= challenge_row.minimum_quantity
      ) into completed;

      select exists(
        select 1 from public.recovery_days rd
        where rd.challenge_id = challenge_row.id
          and rd.user_id = member_row.user_id
          and rd.requirement_date = local_day
      ) into recovered;

      -- Daily reminder at reminder_mins after challenge-local midnight
      fire_at := (local_day::timestamp + make_interval(mins => reminder_mins)) at time zone challenge_tz;
      if fire_at <= now() and fire_at < deadline_at
         and private.claim_reminder_send(member_row.user_id, 'daily', challenge_row.id, local_day) then
        inserted := inserted + private.enqueue_push_for_user(
          member_row.user_id,
          'Your Cahoots check-in',
          'A scheduled requirement is ready when you are.',
          deep_link,
          quiet_start,
          quiet_end,
          member_tz
        );
      end if;

      if completed or recovered then
        continue;
      end if;

      -- Evening incomplete (deadline - 2h)
      fire_at := deadline_at - interval '2 hours';
      if fire_at <= now() and fire_at < deadline_at
         and private.claim_reminder_send(member_row.user_id, 'evening', challenge_row.id, local_day) then
        select count(*)::integer into pending_others
        from public.group_memberships gm2
        where gm2.group_id = challenge_row.group_id
          and gm2.status = 'active'
          and gm2.user_id <> member_row.user_id
          and not exists (
            select 1 from public.submissions s
            where s.challenge_id = challenge_row.id
              and s.user_id = gm2.user_id
              and s.requirement_date = local_day
              and s.sync_state <> 'rejected'
              and s.verification_state <> 'rejected'
              and s.quantity >= challenge_row.minimum_quantity
          )
          and not exists (
            select 1 from public.recovery_days rd
            where rd.challenge_id = challenge_row.id
              and rd.user_id = gm2.user_id
              and rd.requirement_date = local_day
          );

        evening_body := case
          when pending_others <= 0 then 'There is still time to check in today.'
          when pending_others = 1 then 'You and 1 other still need to check in.'
          else 'You and ' || pending_others::text || ' others still need to check in.'
        end;

        inserted := inserted + private.enqueue_push_for_user(
          member_row.user_id,
          'A check-in is still open',
          evening_body,
          deep_link,
          quiet_start,
          quiet_end,
          member_tz
        );
      end if;

      -- Deadline warning (deadline - 30m)
      fire_at := deadline_at - interval '30 minutes';
      if fire_at <= now() and fire_at < deadline_at
         and private.claim_reminder_send(member_row.user_id, 'deadline', challenge_row.id, local_day) then
        inserted := inserted + private.enqueue_push_for_user(
          member_row.user_id,
          'Today''s challenge closes soon',
          'Your scheduled check-in window closes in 30 minutes.',
          deep_link,
          quiet_start,
          quiet_end,
          member_tz
        );
      end if;
    end loop;
  end loop;

  -- Open votes: closing-soon for eligible voters who have not voted
  for proposal_row in
    select p.*, g.name as group_name
    from public.challenge_proposals p
    join public.groups g on g.id = p.group_id
    where p.status = 'voting'
      and p.voting_ends_at > now() + interval '10 minutes'
  loop
    preferred := proposal_row.voting_ends_at - interval '4 hours';
    if preferred > now() then
      continue;
    end if;

    group_name := proposal_row.group_name;
    deep_link := 'cahoots://vote/' || proposal_row.group_id::text || '/' || proposal_row.id::text;

    for member_row in
      select ev.user_id, coalesce(nullif(pr.timezone_identifier, ''), 'UTC') as timezone_identifier
      from public.proposal_eligible_voters ev
      join public.profiles pr on pr.id = ev.user_id
      where ev.proposal_id = proposal_row.id
        and not exists (
          select 1 from public.votes v
          where v.proposal_id = proposal_row.id and v.user_id = ev.user_id
        )
        and exists (
          select 1 from public.group_memberships gm
          where gm.group_id = proposal_row.group_id
            and gm.user_id = ev.user_id
            and gm.status = 'active'
        )
    loop
      select * into group_pref
      from public.notification_preferences
      where user_id = member_row.user_id and group_id = proposal_row.group_id
      limit 1;

      select * into global_pref
      from public.notification_preferences
      where user_id = member_row.user_id and group_id is null
      limit 1;

      updates_enabled := coalesce(group_pref.challenge_updates_enabled, global_pref.challenge_updates_enabled, true);
      if not updates_enabled then
        continue;
      end if;

      quiet_start := coalesce(group_pref.quiet_hours_start, global_pref.quiet_hours_start, 22 * 60);
      quiet_end := coalesce(group_pref.quiet_hours_end, global_pref.quiet_hours_end, 7 * 60);
      member_tz := member_row.timezone_identifier;

      if private.claim_reminder_send(
        member_row.user_id,
        'vote',
        proposal_row.id,
        (proposal_row.voting_ends_at at time zone 'UTC')::date
      ) then
        inserted := inserted + private.enqueue_push_for_user(
          member_row.user_id,
          'Voting closes soon',
          'Review the group proposal before voting closes.',
          deep_link,
          quiet_start,
          quiet_end,
          member_tz
        );
      end if;
    end loop;
  end loop;

  -- Scheduled rounds: morning-of start nudge
  for challenge_row in
    select c.*, g.name as group_name
    from public.challenges c
    join public.groups g on g.id = c.group_id
    where c.status = 'scheduled'
  loop
    challenge_tz := coalesce(nullif(challenge_row.challenge_timezone, ''), 'UTC');
    begin
      local_day := (now() at time zone challenge_tz)::date;
    exception when others then
      challenge_tz := 'UTC';
      local_day := (now() at time zone 'UTC')::date;
    end;

    if local_day <> challenge_row.start_date then
      continue;
    end if;

    group_name := challenge_row.group_name;
    deep_link := 'cahoots://log/' || challenge_row.group_id::text;
    day_end := ((local_day + 1)::timestamp) at time zone challenge_tz;

    for member_row in
      select gm.user_id, coalesce(nullif(p.timezone_identifier, ''), 'UTC') as timezone_identifier
      from public.group_memberships gm
      join public.profiles p on p.id = gm.user_id
      where gm.group_id = challenge_row.group_id
        and gm.status = 'active'
    loop
      select * into group_pref
      from public.notification_preferences
      where user_id = member_row.user_id and group_id = challenge_row.group_id
      limit 1;

      select * into global_pref
      from public.notification_preferences
      where user_id = member_row.user_id and group_id is null
      limit 1;

      updates_enabled := coalesce(group_pref.challenge_updates_enabled, global_pref.challenge_updates_enabled, true);
      if not updates_enabled then
        continue;
      end if;

      quiet_start := coalesce(group_pref.quiet_hours_start, global_pref.quiet_hours_start, 22 * 60);
      quiet_end := coalesce(group_pref.quiet_hours_end, global_pref.quiet_hours_end, 7 * 60);
      reminder_mins := coalesce(group_pref.reminder_minutes, global_pref.reminder_minutes, 18 * 60);
      notify_mins := least(greatest(reminder_mins, 0), 9 * 60);
      member_tz := member_row.timezone_identifier;

      fire_at := (local_day::timestamp + make_interval(mins => notify_mins)) at time zone challenge_tz;
      if fire_at > now() or fire_at >= day_end then
        continue;
      end if;

      if private.claim_reminder_send(member_row.user_id, 'roundStarting', challenge_row.id, local_day) then
        inserted := inserted + private.enqueue_push_for_user(
          member_row.user_id,
          'Your next round starts soon',
          'A scheduled round begins today. Open Today to get ready.',
          deep_link,
          quiet_start,
          quiet_end,
          member_tz
        );
      end if;
    end loop;
  end loop;

  if inserted > 0 then
    perform private.invoke_dispatch_pushes();
  end if;

  return inserted;
end;
$$;

revoke all on function private.enqueue_due_reminders() from public, anon, authenticated;
grant execute on function private.enqueue_due_reminders() to service_role;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'enqueue-due-reminders') then
    perform cron.unschedule((select jobid from cron.job where jobname = 'enqueue-due-reminders'));
  end if;
  perform cron.schedule(
    'enqueue-due-reminders',
    '*/5 * * * *',
    'select private.enqueue_due_reminders();'
  );
exception when others then
  raise notice 'cron.schedule unavailable; skip enqueue-due-reminders schedule';
end;
$$;

-- Keep reminder idempotency rows tidy when a group is deleted.
create or replace function private.delete_group(group_id_input uuid)
returns void
language plpgsql
security definer
set search_path = public, storage
as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if (select owner_id from public.groups where id = group_id_input) is distinct from auth.uid() then
    raise exception 'not_allowed';
  end if;

  perform set_config('storage.allow_delete_query', 'true', true);

  delete from storage.objects o
  using public.workout_clips wc
  join public.submissions s on s.id = wc.submission_id
  join public.challenges c on c.id = s.challenge_id
  where o.bucket_id = 'workout-proofs'
    and o.name = wc.storage_path
    and c.group_id = group_id_input;

  delete from public.workout_clips wc
    using public.submissions s, public.challenges c
    where wc.submission_id = s.id and s.challenge_id = c.id and c.group_id = group_id_input;
  delete from public.score_events se
    using public.challenges c
    where se.challenge_id = c.id and c.group_id = group_id_input;
  delete from public.submissions s
    using public.challenges c
    where s.challenge_id = c.id and c.group_id = group_id_input;
  delete from public.recovery_days rd
    using public.challenges c
    where rd.challenge_id = c.id and c.group_id = group_id_input;
  delete from public.round_results where group_id = group_id_input;
  delete from public.votes v
    using public.challenge_proposals p
    where v.proposal_id = p.id and p.group_id = group_id_input;
  delete from public.proposal_eligible_voters ev
    using public.challenge_proposals p
    where ev.proposal_id = p.id and p.group_id = group_id_input;

  delete from public.push_reminder_sends prs
    using public.challenges c
    where prs.subject_id = c.id and c.group_id = group_id_input;
  delete from public.push_reminder_sends prs
    using public.challenge_proposals p
    where prs.subject_id = p.id and p.group_id = group_id_input;

  delete from public.challenges where group_id = group_id_input;
  delete from public.challenge_proposals where group_id = group_id_input;
  delete from public.group_invites where group_id = group_id_input;
  delete from public.activity_feed_items where group_id = group_id_input;
  delete from public.reports where group_id = group_id_input;
  delete from public.notification_preferences where group_id = group_id_input;
  delete from public.push_digest_events where group_id = group_id_input;
  delete from public.group_memberships where group_id = group_id_input;
  delete from public.groups where id = group_id_input;
end;
$$;
