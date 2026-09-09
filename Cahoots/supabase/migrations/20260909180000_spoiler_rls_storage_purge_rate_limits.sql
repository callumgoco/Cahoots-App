-- Spoiler RLS, can_reveal helper backfill, storage purge on delete, rate limits,
-- RLS initplan fixes, and covering indexes for unindexed foreign keys.

-- 1. Ensure can_reveal_submission_id exists in git + live (idempotent).
create or replace function private.can_reveal_submission_id(submission_id_input uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select private.can_reveal_submission(s) from public.submissions s where s.id = submission_id_input),
    false
  );
$$;

revoke all on function private.can_reveal_submission_id(uuid) from public, anon;
grant execute on function private.can_reveal_submission_id(uuid) to authenticated, service_role;

create or replace function public.can_reveal_submission_id(submission_id_input uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select private.can_reveal_submission_id(submission_id_input);
$$;

revoke all on function public.can_reveal_submission_id(uuid) from public, anon;
grant execute on function public.can_reveal_submission_id(uuid) to authenticated, service_role;

-- 2. Spoiler-gated SELECT on submissions and score_events.
drop policy if exists submissions_group_read on public.submissions;
create policy submissions_group_read on public.submissions
for select using (
  user_id = (select auth.uid())
  or (
    exists (
      select 1 from public.challenges c
      where c.id = challenge_id
        and private.is_active_group_member(c.group_id)
    )
    and private.can_reveal_submission(submissions)
  )
);

drop policy if exists score_events_group_read on public.score_events;
create policy score_events_group_read on public.score_events
for select using (
  user_id = (select auth.uid())
  or (
    exists (
      select 1 from public.challenges c
      where c.id = challenge_id
        and private.is_active_group_member(c.group_id)
    )
    and (
      submission_id is null
      or private.can_reveal_submission_id(submission_id)
    )
  )
);

-- 3. RLS initplan: wrap auth.uid() in (select auth.uid()).
drop policy if exists profiles_self_or_group_peers on public.profiles;
create policy profiles_self_or_group_peers on public.profiles
for select using (
  id = (select auth.uid())
  or exists (
    select 1
    from public.group_memberships mine
    join public.group_memberships theirs on theirs.group_id = mine.group_id
    where mine.user_id = (select auth.uid())
      and mine.status = 'active'
      and theirs.user_id = profiles.id
      and theirs.status = 'active'
  )
);

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
for update using (id = (select auth.uid()))
with check (id = (select auth.uid()));

drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self on public.profiles
for insert with check (id = (select auth.uid()));

drop policy if exists proposals_member_insert on public.challenge_proposals;
create policy proposals_member_insert on public.challenge_proposals
for insert with check (
  proposed_by = (select auth.uid())
  and private.is_active_group_member(group_id)
);

drop policy if exists preferences_self_all on public.notification_preferences;
create policy preferences_self_all on public.notification_preferences
for all using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists recovery_group_read on public.recovery_days;
create policy recovery_group_read on public.recovery_days
for select using (
  user_id = (select auth.uid())
  or exists (
    select 1 from public.challenges c
    where c.id = challenge_id and private.is_active_group_member(c.group_id)
  )
);

drop policy if exists tokens_self_all on public.device_push_tokens;
create policy tokens_self_all on public.device_push_tokens
for all using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists reports_self_insert on public.reports;
create policy reports_self_insert on public.reports
for insert with check (
  reporter_id = (select auth.uid())
  and private.is_active_group_member(group_id)
);

drop policy if exists reports_self_read on public.reports;
create policy reports_self_read on public.reports
for select using (reporter_id = (select auth.uid()));

drop policy if exists blocks_self_all on public.blocked_users;
create policy blocks_self_all on public.blocked_users
for all using (blocker_id = (select auth.uid()))
with check (blocker_id = (select auth.uid()));

drop policy if exists workout_clips_insert_own on public.workout_clips;
create policy workout_clips_insert_own on public.workout_clips
for insert with check (
  exists (
    select 1 from public.submissions s
    where s.id = submission_id and s.user_id = (select auth.uid())
  )
);

drop policy if exists workout_proofs_insert_own on storage.objects;
create policy workout_proofs_insert_own on storage.objects
for insert to authenticated
with check (
  bucket_id = 'workout-proofs'
  and (storage.foldername(name))[4] = ((select auth.uid())::text)
);

drop policy if exists workout_proofs_update_own on storage.objects;
create policy workout_proofs_update_own on storage.objects
for update to authenticated
using (
  bucket_id = 'workout-proofs'
  and (storage.foldername(name))[4] = ((select auth.uid())::text)
);

drop policy if exists workout_proofs_delete_own on storage.objects;
create policy workout_proofs_delete_own on storage.objects
for delete to authenticated
using (
  bucket_id = 'workout-proofs'
  and (storage.foldername(name))[4] = ((select auth.uid())::text)
);

-- 4. Purge storage objects with expired clip rows.
create or replace function public.purge_expired_workout_clips()
returns integer
language plpgsql
security definer
set search_path = public, storage
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
        or c.status in ('completed', 'cancelled')
      )
    returning wc.storage_path
  ),
  deleted_objects as (
    delete from storage.objects o
    using doomed d
    where o.bucket_id = 'workout-proofs'
      and o.name = d.storage_path
    returning o.id
  )
  select count(*) into removed from doomed;
  return removed;
end;
$$;

revoke all on function public.purge_expired_workout_clips() from public, anon, authenticated;
grant execute on function public.purge_expired_workout_clips() to service_role;

-- 5. Account deletion also removes storage objects.
create or replace function private.release_user_owned_data(target uuid)
returns void
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  owned record;
  successor uuid;
  doomed_groups uuid[];
  doomed_proposals uuid[];
begin
  for owned in select id from public.groups where owner_id = target loop
    successor := null;
    select m.user_id into successor
    from public.group_memberships m
    where m.group_id = owned.id and m.status = 'active' and m.user_id <> target
    order by (m.role = 'admin') desc, m.joined_at
    limit 1;

    if successor is not null then
      update public.group_memberships set role = 'owner'
      where group_id = owned.id and user_id = successor;
      update public.groups set owner_id = successor, updated_at = now()
      where id = owned.id;
    end if;
  end loop;

  select coalesce(array_agg(id), '{}') into doomed_groups
  from public.groups where owner_id = target;

  delete from storage.objects o
  using public.workout_clips wc
  join public.submissions s on s.id = wc.submission_id
  join public.challenges c on c.id = s.challenge_id
  where o.bucket_id = 'workout-proofs'
    and o.name = wc.storage_path
    and c.group_id = any(doomed_groups);

  delete from public.workout_clips wc
    using public.submissions s, public.challenges c
    where wc.submission_id = s.id and s.challenge_id = c.id and c.group_id = any(doomed_groups);
  delete from public.score_events se
    using public.challenges c
    where se.challenge_id = c.id and c.group_id = any(doomed_groups);
  delete from public.submissions s
    using public.challenges c
    where s.challenge_id = c.id and c.group_id = any(doomed_groups);
  delete from public.recovery_days rd
    using public.challenges c
    where rd.challenge_id = c.id and c.group_id = any(doomed_groups);
  delete from public.round_results where group_id = any(doomed_groups);
  delete from public.votes v
    using public.challenge_proposals p
    where v.proposal_id = p.id and p.group_id = any(doomed_groups);
  delete from public.proposal_eligible_voters ev
    using public.challenge_proposals p
    where ev.proposal_id = p.id and p.group_id = any(doomed_groups);
  delete from public.challenges where group_id = any(doomed_groups);
  delete from public.challenge_proposals where group_id = any(doomed_groups);
  delete from public.group_invites where group_id = any(doomed_groups);
  delete from public.activity_feed_items where group_id = any(doomed_groups);
  delete from public.reports where group_id = any(doomed_groups);
  delete from public.notification_preferences where group_id = any(doomed_groups);
  delete from public.group_memberships where group_id = any(doomed_groups);
  delete from public.groups where id = any(doomed_groups);

  delete from public.group_invites where created_by = target;

  select coalesce(array_agg(id), '{}') into doomed_proposals
  from public.challenge_proposals where proposed_by = target;

  update public.challenges set proposal_id = null where proposal_id = any(doomed_proposals);
  delete from public.votes where proposal_id = any(doomed_proposals);
  delete from public.proposal_eligible_voters where proposal_id = any(doomed_proposals);
  delete from public.challenge_proposals where id = any(doomed_proposals);

  delete from storage.objects o
  using public.workout_clips wc
  join public.submissions s on s.id = wc.submission_id
  where o.bucket_id = 'workout-proofs'
    and o.name = wc.storage_path
    and s.user_id = target;

  delete from public.score_events where user_id = target;
  delete from public.workout_clips wc
    using public.submissions s
    where wc.submission_id = s.id and s.user_id = target;
  delete from public.submissions where user_id = target;
end;
$$;

revoke all on function private.release_user_owned_data(uuid) from public, anon, authenticated;
grant execute on function private.release_user_owned_data(uuid) to service_role;

-- 6. Rate limits.
create table if not exists private.rate_limit_buckets (
  subject uuid not null,
  action text not null,
  window_start timestamptz not null,
  hit_count integer not null default 0,
  primary key (subject, action, window_start)
);

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

revoke all on function private.consume_rate_limit(text, integer, integer) from public, anon;
grant execute on function private.consume_rate_limit(text, integer, integer) to authenticated, service_role;

create or replace function public.consume_rate_limit(
  action_input text,
  max_hits integer,
  window_seconds integer
) returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  perform private.consume_rate_limit(action_input, max_hits, window_seconds);
end;
$$;

revoke all on function public.consume_rate_limit(text, integer, integer) from public, anon;
grant execute on function public.consume_rate_limit(text, integer, integer) to authenticated, service_role;

create or replace function private.redeem_group_invite(invite_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_invite public.group_invites%rowtype;
  active_count integer;
begin
  perform private.consume_rate_limit('invite_redeem', 10, 3600);

  select * into selected_invite from public.group_invites where code = upper(invite_code) for update;
  if not found then raise exception 'invite_not_found'; end if;
  if selected_invite.revoked_at is not null or selected_invite.expires_at <= now() or selected_invite.use_count >= selected_invite.maximum_uses then raise exception 'invite_expired'; end if;
  if exists(select 1 from public.blocked_users b join public.group_memberships m on m.group_id = selected_invite.group_id where b.blocker_id = auth.uid() and b.blocked_user_id = m.user_id and m.role = 'owner') then raise exception 'invite_blocked'; end if;
  select count(*) into active_count from public.group_memberships where group_id = selected_invite.group_id and status = 'active';
  if active_count >= (select member_limit from public.groups where id = selected_invite.group_id) then raise exception 'group_full'; end if;
  insert into public.group_memberships(group_id, user_id, role, status) values (selected_invite.group_id, auth.uid(), 'member', 'active')
  on conflict(group_id, user_id) do update set status = 'active', role = 'member', joined_at = now(), left_at = null;
  update public.group_invites set use_count = use_count + 1 where id = selected_invite.id;
  insert into public.activity_feed_items(group_id, actor_id, event_type, message) values (selected_invite.group_id, auth.uid(), 'member_joined', 'A new member joined the group.');
  return selected_invite.group_id;
end;
$$;

create or replace function private.submit_report(reported_user_id_input uuid, group_id_input uuid, reason_input text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
begin
  perform private.consume_rate_limit('submit_report', 5, 3600);

  if not private.is_active_group_member(group_id_input) then raise exception 'not_allowed'; end if;
  if char_length(trim(reason_input)) < 2 then raise exception 'invalid_reason'; end if;
  insert into public.reports(reporter_id, reported_user_id, group_id, reason)
  values (auth.uid(), reported_user_id_input, group_id_input, left(trim(reason_input), 280))
  returning id into new_id;
  return new_id;
end;
$$;

-- 7. Covering indexes for unindexed foreign keys.
create index if not exists activity_feed_items_actor_id_idx on public.activity_feed_items (actor_id);
create index if not exists blocked_users_blocked_user_id_idx on public.blocked_users (blocked_user_id);
create index if not exists challenge_proposals_proposed_by_idx on public.challenge_proposals (proposed_by);
create index if not exists device_push_tokens_user_id_idx on public.device_push_tokens (user_id);
create index if not exists group_invites_created_by_idx on public.group_invites (created_by);
create index if not exists group_invites_group_id_idx on public.group_invites (group_id);
create index if not exists groups_owner_id_idx on public.groups (owner_id);
create index if not exists notification_preferences_group_id_idx on public.notification_preferences (group_id);
create index if not exists proposal_eligible_voters_user_id_idx on public.proposal_eligible_voters (user_id);
create index if not exists recovery_days_user_id_idx on public.recovery_days (user_id);
create index if not exists reports_group_id_idx on public.reports (group_id);
create index if not exists reports_reported_user_id_idx on public.reports (reported_user_id);
create index if not exists reports_reporter_id_idx on public.reports (reporter_id);
create index if not exists round_results_group_id_idx on public.round_results (group_id);
create index if not exists score_events_submission_id_idx on public.score_events (submission_id);
create index if not exists score_events_user_id_idx on public.score_events (user_id);
create index if not exists submissions_user_id_idx on public.submissions (user_id);
create index if not exists votes_user_id_idx on public.votes (user_id);
