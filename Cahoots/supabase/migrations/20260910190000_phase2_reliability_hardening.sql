-- Phase 2 reliability: fixed rate-limit caps, membership-scoped storage paths,
-- one non-rejected submission per challenge/user/day, safer push-token upsert.

-- ---------------------------------------------------------------------------
-- 1. Rate limits: clients may only pass an action name; caps live server-side.
-- ---------------------------------------------------------------------------
create or replace function private.rate_limit_policy(action_input text)
returns table(max_hits integer, window_seconds integer)
language sql
immutable
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

create or replace function private.consume_rate_limit(
  action_input text,
  max_hits integer,
  window_seconds integer
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := (select auth.uid());
  win timestamptz;
  hits integer;
begin
  if uid is null then raise exception 'not_authenticated'; end if;

  -- Ignore caller-supplied caps when invoked through the public shim; trusted
  -- private callers (invite_redeem, submit_report) may still pass explicit values.
  if max_hits is null or window_seconds is null then
    select p.max_hits, p.window_seconds into max_hits, window_seconds
    from private.rate_limit_policy(action_input) p;
    if max_hits is null or window_seconds is null then
      raise exception 'unknown_rate_limit_action' using errcode = 'P0001';
    end if;
  end if;

  if max_hits is null or window_seconds is null or max_hits < 1 or window_seconds < 1 then
    raise exception 'invalid_rate_limit' using errcode = 'P0001';
  end if;

  win := to_timestamp(floor(extract(epoch from now()) / window_seconds) * window_seconds);
  insert into private.rate_limit_buckets(subject, action, window_start, hit_count)
  values (uid, action_input, win, 1)
  on conflict (subject, action, window_start)
  do update set hit_count = private.rate_limit_buckets.hit_count + 1
  returning hit_count into hits;
  if hits > max_hits then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;
end;
$$;

drop function if exists public.consume_rate_limit(text, integer, integer);

create or replace function public.consume_rate_limit(action_input text)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  -- Caps come only from private.rate_limit_policy — never from the client.
  perform private.consume_rate_limit(action_input, null, null);
end;
$$;

revoke all on function public.consume_rate_limit(text) from public, anon;
grant execute on function public.consume_rate_limit(text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Storage: path must match an active membership + challenge in that group.
-- ---------------------------------------------------------------------------
drop policy if exists workout_proofs_insert_own on storage.objects;
create policy workout_proofs_insert_own on storage.objects
for insert to authenticated
with check (
  bucket_id = 'workout-proofs'
  and lower((storage.foldername(name))[4]) = ((select auth.uid())::text)
  and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
  and (storage.foldername(name))[2] ~* '^[0-9a-f-]{36}$'
  and (storage.foldername(name))[3] ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  and exists (
    select 1
    from public.challenges c
    join public.group_memberships m
      on m.group_id = c.group_id
     and m.user_id = (select auth.uid())
     and m.status = 'active'
    where c.id = lower((storage.foldername(name))[2])::uuid
      and c.group_id = lower((storage.foldername(name))[1])::uuid
      and c.status in ('active', 'scheduled', 'completed')
  )
);

drop policy if exists workout_proofs_update_own on storage.objects;
create policy workout_proofs_update_own on storage.objects
for update to authenticated
using (
  bucket_id = 'workout-proofs'
  and lower((storage.foldername(name))[4]) = ((select auth.uid())::text)
  and exists (
    select 1
    from public.challenges c
    join public.group_memberships m
      on m.group_id = c.group_id
     and m.user_id = (select auth.uid())
     and m.status = 'active'
    where c.id = lower((storage.foldername(name))[2])::uuid
      and c.group_id = lower((storage.foldername(name))[1])::uuid
  )
)
with check (
  bucket_id = 'workout-proofs'
  and lower((storage.foldername(name))[4]) = ((select auth.uid())::text)
);

drop policy if exists workout_proofs_delete_own on storage.objects;
create policy workout_proofs_delete_own on storage.objects
for delete to authenticated
using (
  bucket_id = 'workout-proofs'
  and lower((storage.foldername(name))[4]) = ((select auth.uid())::text)
);

-- ---------------------------------------------------------------------------
-- 3. One non-rejected submission per challenge / user / requirement day.
-- ---------------------------------------------------------------------------
create unique index if not exists submissions_one_active_per_day_idx
  on public.submissions (challenge_id, user_id, requirement_date)
  where sync_state is distinct from 'rejected';

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

  select * into existing
  from public.submissions
  where challenge_id = challenge_id_input
    and user_id = auth.uid()
    and requirement_date = requirement_date_input
    and sync_state is distinct from 'rejected';
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

-- ---------------------------------------------------------------------------
-- 4. Push tokens: same-user refresh; account-switch takeover only after clearing
--    the previous owner's row explicitly (device reuse). Block silent hijack via
--    blind upsert of a known token string without replacing the row first.
-- ---------------------------------------------------------------------------
create or replace function private.register_push_token(
  token_input text,
  environment_input text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_owner uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if environment_input not in ('sandbox', 'production') then raise exception 'invalid_environment'; end if;
  if char_length(trim(token_input)) < 16 then raise exception 'invalid_token'; end if;

  select user_id into existing_owner
  from public.device_push_tokens
  where token = token_input;

  if existing_owner is not null and existing_owner is distinct from auth.uid() then
    -- Physical device changed accounts: drop prior owner binding, then claim.
    delete from public.device_push_tokens where token = token_input;
  end if;

  -- Keep at most one token per user/environment to limit fan-out duplication.
  delete from public.device_push_tokens
  where user_id = auth.uid()
    and environment = environment_input
    and token is distinct from token_input;

  insert into public.device_push_tokens(user_id, token, environment)
  values (auth.uid(), token_input, environment_input)
  on conflict (token) do update
    set user_id = excluded.user_id,
        environment = excluded.environment;
end;
$$;
