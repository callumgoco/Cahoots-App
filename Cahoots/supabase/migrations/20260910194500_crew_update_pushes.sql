-- Fan out remote pushes for vote opened / round scheduled / round started.
-- Gated by challenge_updates_enabled (Votes & round updates). Delivered via push_outbox → dispatch-pushes.

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
      -- Defer until quiet hours end in the member's local timezone.
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

  return inserted;
end;
$$;

revoke all on function private.enqueue_crew_update_pushes(uuid, uuid, text, text, text) from public, anon, authenticated;
grant execute on function private.enqueue_crew_update_pushes(uuid, uuid, text, text, text) to service_role;

create or replace function private.create_and_open_proposal(
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
  group_name text;
  actor_name text;
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

  select name into group_name from public.groups where id = group_id_input;
  select coalesce(display_name, 'A member') into actor_name from public.profiles where id = auth.uid();

  perform private.enqueue_crew_update_pushes(
    group_id_input,
    auth.uid(),
    coalesce(group_name, 'Cahoots'),
    coalesce(actor_name, 'A member') || ' opened a group vote. Review it before it closes.',
    'cahoots://vote/' || group_id_input::text || '/' || new_id::text
  );

  return new_id;
end;
$$;

create or replace function private.start_round_now(
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
  group_name text;
  body_text text;
begin
  if not public.is_active_group_member(group_id_input) then raise exception 'not_allowed'; end if;
  if exists(select 1 from public.challenge_proposals where group_id = group_id_input and status = 'voting') then
    raise exception 'vote_already_open';
  end if;
  if exists(select 1 from public.challenges where group_id = group_id_input and status = 'scheduled') then
    raise exception 'successor_already_scheduled';
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

  select name into group_name from public.groups where id = group_id_input;
  body_text := case
    when status_val = 'active' then trim(title_input) || ' has started. Check in on Today when you''re ready.'
    else trim(title_input) || ' is scheduled to start ' || to_char(start_date_input, 'Mon DD') || '.'
  end;

  perform private.enqueue_crew_update_pushes(
    group_id_input,
    auth.uid(),
    coalesce(group_name, 'Cahoots'),
    body_text,
    'cahoots://log/' || group_id_input::text
  );

  return new_id;
end;
$$;

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

    select name into group_name from public.groups where id = p.group_id;
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
  end if;

  insert into public.activity_feed_items(group_id, actor_id, event_type, message)
  values (p.group_id, null, 'vote_completed', feed_message);

  return outcome;
end;
$$;

create or replace function public.activate_due_challenges()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  activated integer := 0;
  due_row record;
  group_name text;
begin
  for due_row in
    select c.id, c.group_id, c.title
    from public.challenges c
    where c.status = 'scheduled'
      and c.start_date <= (now() at time zone c.challenge_timezone)::date
      and not exists (
        select 1 from public.challenges active
        where active.group_id = c.group_id and active.status = 'active'
      )
    for update of c skip locked
  loop
    update public.challenges set status = 'active' where id = due_row.id;
    activated := activated + 1;

    select name into group_name from public.groups where id = due_row.group_id;
    perform private.enqueue_crew_update_pushes(
      due_row.group_id,
      null,
      coalesce(group_name, 'Cahoots'),
      due_row.title || ' has started. Check in on Today when you''re ready.',
      'cahoots://log/' || due_row.group_id::text
    );
  end loop;

  return activated;
end;
$$;
