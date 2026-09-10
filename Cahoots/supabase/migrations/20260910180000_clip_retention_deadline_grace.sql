-- Tighten clip retention:
--   1) purge after the requirement day's deadline + 48h, or when the round ends
--   2) when a newer day's check-in is accepted, drop that user's older-day clips
-- Orphan objects without a workout_clips row still clear after 24h.

create or replace function private.delete_workout_proof_paths(paths text[])
returns integer
language plpgsql
security definer
set search_path to 'public', 'storage'
as $$
declare
  removed integer := 0;
begin
  if paths is null or cardinality(paths) = 0 then
    return 0;
  end if;

  perform set_config('storage.allow_delete_query', 'true', true);

  with deleted_objects as (
    delete from storage.objects o
    where o.bucket_id = 'workout-proofs'
      and o.name = any (paths)
    returning o.id
  )
  select count(*) into removed from deleted_objects;

  return removed;
end;
$$;

revoke all on function private.delete_workout_proof_paths(text[]) from public, anon, authenticated;
grant execute on function private.delete_workout_proof_paths(text[]) to service_role;

-- Drop older requirement-day clips for one user when they check in for a newer day.
create or replace function private.purge_superseded_requirement_clips(
  challenge_id_input uuid,
  user_id_input uuid,
  keep_requirement_date date
)
returns integer
language plpgsql
security definer
set search_path to 'public', 'storage'
as $$
declare
  removed integer := 0;
  paths text[];
begin
  with doomed as (
    delete from public.workout_clips wc
    using public.submissions s
    where wc.submission_id = s.id
      and s.challenge_id = challenge_id_input
      and s.user_id = user_id_input
      and s.requirement_date < keep_requirement_date
    returning wc.storage_path
  )
  select coalesce(array_agg(storage_path), '{}'::text[]) into paths from doomed;

  removed := private.delete_workout_proof_paths(paths);
  return coalesce(removed, 0);
end;
$$;

revoke all on function private.purge_superseded_requirement_clips(uuid, uuid, date) from public, anon, authenticated;
grant execute on function private.purge_superseded_requirement_clips(uuid, uuid, date) to service_role;

create or replace function public.purge_expired_workout_clips()
returns integer
language plpgsql
security definer
set search_path to 'public', 'storage'
as $$
declare
  removed integer := 0;
  orphan_removed integer := 0;
  paths text[];
begin
  perform set_config('storage.allow_delete_query', 'true', true);

  with doomed as (
    delete from public.workout_clips wc
    using public.submissions s
    left join public.challenges c on c.id = s.challenge_id
    where wc.submission_id = s.id
      and (
        c.id is null
        or c.status in ('completed', 'cancelled')
        or now() > (
          ((s.requirement_date::text || ' 00:00')::timestamp at time zone coalesce(c.challenge_timezone, 'UTC'))
          + make_interval(mins => coalesce(c.daily_deadline_minutes, 23 * 60))
          + interval '48 hours'
        )
        -- Absolute backstop if challenge metadata is missing/odd.
        or wc.created_at < now() - interval '5 days'
      )
    returning wc.storage_path
  )
  select coalesce(array_agg(storage_path), '{}'::text[]) into paths from doomed;

  removed := private.delete_workout_proof_paths(paths);

  with orphans as (
    delete from storage.objects o
    where o.bucket_id = 'workout-proofs'
      and o.created_at < now() - interval '24 hours'
      and not exists (
        select 1 from public.workout_clips wc where wc.storage_path = o.name
      )
    returning o.id
  )
  select count(*) into orphan_removed from orphans;

  return removed + orphan_removed;
end;
$$;

revoke all on function public.purge_expired_workout_clips() from public, anon, authenticated;
grant execute on function public.purge_expired_workout_clips() to service_role;

-- After accepting today's clips, drop this member's earlier-day proofs for the same challenge.
create or replace function private.accept_submission(
  client_id uuid,
  challenge_id_input uuid,
  requirement_date_input date,
  quantity_input numeric,
  completed_at_input timestamp with time zone,
  clips_input jsonb default '[]'::jsonb
)
returns table(submission_id uuid, points integer, verification verification_state)
language plpgsql
security definer
set search_path to 'public'
as $function$
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
  storage_path text;
  resolved_path text;
  expected_prefix text;
  date_token text;
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

  date_token := requirement_date_input::text;
  expected_prefix := c.group_id::text || '/' || c.id::text || '/' || date_token || '/' || auth.uid()::text || '/';

  for clip in select * from jsonb_array_elements(clips_input)
  loop
    storage_path := coalesce(clip->>'storagePath', '');
    resolved_path := null;
    if storage_path <> ''
       and lower(storage_path) ~ ('^' || expected_prefix || '[^/]+\.mov$')
       and coalesce((clip->>'durationSeconds')::numeric, 0) >= 2
       and coalesce((clip->>'durationSeconds')::numeric, 0) <= 600 then
      select o.name into resolved_path
      from storage.objects o
      where o.bucket_id = 'workout-proofs'
        and lower(o.name) = lower(storage_path)
      limit 1;
    end if;

    if resolved_path is null then
      raise exception 'invalid_clip';
    end if;

    insert into public.workout_clips(id, submission_id, kind, duration_seconds, storage_path)
    values (
      coalesce((clip->>'id')::uuid, gen_random_uuid()),
      new_submission_id,
      (clip->>'kind')::public.workout_clip_kind,
      (clip->>'durationSeconds')::numeric,
      resolved_path
    );
  end loop;

  perform private.purge_superseded_requirement_clips(c.id, auth.uid(), requirement_date_input);

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
$function$;
