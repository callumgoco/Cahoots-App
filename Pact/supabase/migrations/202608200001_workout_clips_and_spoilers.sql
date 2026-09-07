-- Workout proof clips, redacted peer reads, and retention helpers.
begin;

create type public.workout_clip_kind as enum ('set', 'start', 'finish');

create table public.workout_clips (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.submissions(id) on delete cascade,
  kind public.workout_clip_kind not null,
  duration_seconds numeric(10,2) not null check (duration_seconds >= 2 and duration_seconds <= 600),
  storage_path text not null,
  created_at timestamptz not null default now(),
  unique (submission_id, kind)
);

create index workout_clips_submission_idx on public.workout_clips(submission_id);

alter table public.workout_clips enable row level security;

-- Viewer may see clip metadata only when they completed today, used recovery, own the row, or the deadline has passed.
create or replace function public.can_reveal_submission(submission_row public.submissions)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c public.challenges%rowtype;
  deadline timestamptz;
  viewer_completed boolean;
  viewer_recovered boolean;
begin
  if submission_row.user_id = auth.uid() then
    return true;
  end if;
  select * into c from public.challenges where id = submission_row.challenge_id;
  if not found then
    return false;
  end if;
  deadline := ((submission_row.requirement_date::text || ' 00:00')::timestamp at time zone c.challenge_timezone)
    + make_interval(mins => c.daily_deadline_minutes);
  if now() >= deadline then
    return true;
  end if;
  select exists(
    select 1 from public.submissions s
    where s.challenge_id = submission_row.challenge_id
      and s.user_id = auth.uid()
      and s.requirement_date = submission_row.requirement_date
      and s.sync_state <> 'rejected'
      and s.quantity >= c.minimum_quantity
  ) into viewer_completed;
  if viewer_completed then
    return true;
  end if;
  select exists(
    select 1 from public.recovery_days r
    where r.challenge_id = submission_row.challenge_id
      and r.user_id = auth.uid()
      and r.requirement_date = submission_row.requirement_date
  ) into viewer_recovered;
  return viewer_recovered;
end;
$$;

drop policy if exists submissions_group_read on public.submissions;
create policy submissions_group_read on public.submissions for select using (
  user_id = auth.uid()
  or exists(
    select 1 from public.challenges c
    where c.id = challenge_id and public.is_active_group_member(c.group_id)
  )
);

create policy workout_clips_read on public.workout_clips for select using (
  exists(
    select 1 from public.submissions s
    where s.id = submission_id and public.can_reveal_submission(s)
  )
);

create policy workout_clips_insert_own on public.workout_clips for insert with check (
  exists(
    select 1 from public.submissions s
    where s.id = submission_id and s.user_id = auth.uid()
  )
);

-- Redacted submission projection for clients.
create or replace function public.submission_quantity_for_viewer(submission_row public.submissions)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select case when public.can_reveal_submission(submission_row) then submission_row.quantity else 0 end;
$$;

create or replace function public.accept_submission(
  client_id uuid,
  challenge_id_input uuid,
  requirement_date_input date,
  quantity_input numeric,
  completed_at_input timestamptz,
  clips_input jsonb default '[]'::jsonb
) returns table(submission_id uuid, points integer, verification public.verification_state)
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.challenges%rowtype;
  existing public.submissions%rowtype;
  new_submission_id uuid;
  deadline timestamptz;
  extra_ratio numeric;
  awarded integer;
  already_completed boolean;
  clip_count integer;
  required_count integer;
  clip jsonb;
begin
  select * into existing from public.submissions where client_generated_id = client_id;
  if found then
    return query select existing.id,
      coalesce((select sum(points)::integer from public.score_events where submission_id = existing.id), 0),
      existing.verification_state;
    return;
  end if;

  select * into c from public.challenges where id = challenge_id_input and status in ('active', 'completed') for update;
  if not found or not public.is_active_group_member(c.group_id) then
    raise exception 'not_allowed';
  end if;
  if quantity_input <= 0 or completed_at_input > now() + interval '10 minutes' then
    raise exception 'invalid_submission';
  end if;

  required_count := case when c.measurement_type in ('minutes', 'distance') then 2 else 1 end;
  clip_count := coalesce(jsonb_array_length(clips_input), 0);
  if clip_count < required_count then
    raise exception 'clips_required';
  end if;

  deadline := ((requirement_date_input::text || ' 00:00')::timestamp at time zone c.challenge_timezone)
    + make_interval(mins => c.daily_deadline_minutes);
  if completed_at_input > deadline or now() > deadline + interval '24 hours' then
    insert into public.submissions(
      client_generated_id, challenge_id, user_id, requirement_date, quantity, measurement_type,
      completed_at, verification_state, sync_state
    ) values (
      client_id, c.id, auth.uid(), requirement_date_input, quantity_input, c.measurement_type,
      completed_at_input, 'rejected', 'rejected'
    ) returning id into new_submission_id;
    return query select new_submission_id, 0, 'rejected'::public.verification_state;
    return;
  end if;

  insert into public.submissions(
    client_generated_id, challenge_id, user_id, requirement_date, quantity, measurement_type,
    completed_at, verification_state, sync_state
  ) values (
    client_id, c.id, auth.uid(), requirement_date_input, quantity_input, c.measurement_type,
    completed_at_input, 'accepted', 'synced'
  ) returning id into new_submission_id;

  for clip in select * from jsonb_array_elements(clips_input)
  loop
    if coalesce((clip->>'durationSeconds')::numeric, 0) < 2
       or coalesce((clip->>'durationSeconds')::numeric, 0) > 600
       or coalesce(clip->>'storagePath', '') = '' then
      raise exception 'invalid_clip';
    end if;
    insert into public.workout_clips(id, submission_id, kind, duration_seconds, storage_path)
    values (
      coalesce((clip->>'id')::uuid, gen_random_uuid()),
      new_submission_id,
      (clip->>'kind')::public.workout_clip_kind,
      (clip->>'durationSeconds')::numeric,
      clip->>'storagePath'
    );
  end loop;

  select exists(
    select 1 from public.score_events
    where challenge_id = c.id and user_id = auth.uid() and event_type = 'requirement_completed'
      and (created_at at time zone c.challenge_timezone)::date = requirement_date_input
  ) into already_completed;

  awarded := 0;
  if quantity_input >= c.minimum_quantity and not already_completed then
    extra_ratio := greatest(0, quantity_input - c.minimum_quantity) / c.minimum_quantity;
    awarded := 100 + least(10, floor(extra_ratio * 15)::integer);
    insert into public.score_events(challenge_id, user_id, submission_id, event_type, points, reason, scoring_version)
    values (c.id, auth.uid(), new_submission_id, 'requirement_completed', 100, 'Scheduled requirement completed', c.scoring_version);
    if awarded > 100 then
      insert into public.score_events(challenge_id, user_id, submission_id, event_type, points, reason, scoring_version)
      values (c.id, auth.uid(), new_submission_id, 'bonus', awarded - 100, 'Capped completion bonus', c.scoring_version);
    end if;
    insert into public.activity_feed_items(group_id, actor_id, event_type, message)
    values (c.group_id, auth.uid(), 'completion', 'A member completed today''s challenge.');
  end if;

  return query select new_submission_id, awarded, 'accepted'::public.verification_state;
end;
$$;

grant execute on function public.accept_submission(uuid, uuid, date, numeric, timestamptz, jsonb) to authenticated;

-- Retention: delete clips older than 7 days or belonging to completed challenges.
create or replace function public.purge_expired_workout_clips()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  removed integer := 0;
begin
  with doomed as (
    delete from public.workout_clips wc
    using public.submissions s
    left join public.challenges c on c.id = s.challenge_id
    where wc.submission_id = s.id
      and (
        wc.created_at < now() - interval '7 days'
        or c.status = 'completed'
        or c.status = 'cancelled'
      )
    returning wc.id
  )
  select count(*) into removed from doomed;
  return removed;
end;
$$;

-- Storage bucket note: create `workout-proofs` as private in the Supabase dashboard.
-- Object path: {group_id}/{challenge_id}/{requirement_date}/{user_id}/{clip_id}.mov
-- Upload policy: authenticated users may write only under their own user_id segment.
-- Read policy: use signed URLs issued after can_reveal_submission is true.

commit;
