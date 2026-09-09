-- Phase 2: push outbox, digest events, orphan storage purge, batch can_reveal.
-- Outbox tables live in public with zero client grants so Edge Functions can use them via service role.

create table if not exists public.push_outbox (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  token text not null,
  environment text not null check (environment in ('sandbox', 'production')),
  title text not null,
  body text not null,
  deep_link text,
  created_at timestamptz not null default now(),
  send_after timestamptz not null default now(),
  attempts integer not null default 0,
  last_error text,
  sent_at timestamptz
);

create index if not exists push_outbox_pending_idx
  on public.push_outbox (send_after, created_at)
  where sent_at is null;

create table if not exists public.push_digest_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  group_id uuid not null,
  actor_id uuid,
  actor_name text not null,
  group_name text not null,
  created_at timestamptz not null default now(),
  digested_at timestamptz
);

create index if not exists push_digest_pending_idx
  on public.push_digest_events (user_id, created_at)
  where digested_at is null;

alter table public.push_outbox enable row level security;
alter table public.push_digest_events enable row level security;

revoke all on table public.push_outbox from public, anon, authenticated;
revoke all on table public.push_digest_events from public, anon, authenticated;
grant all on table public.push_outbox to service_role;
grant all on table public.push_digest_events to service_role;

-- Batch spoiler reveal for app-snapshot (avoids N+1 RPC).
create or replace function private.can_reveal_submission_ids(ids uuid[])
returns table(submission_id uuid, can_reveal boolean)
language sql
stable
security definer
set search_path to 'public'
as $$
  select s.id, private.can_reveal_submission(s)
  from public.submissions s
  where s.id = any(ids);
$$;

revoke all on function private.can_reveal_submission_ids(uuid[]) from public, anon;
grant execute on function private.can_reveal_submission_ids(uuid[]) to authenticated, service_role;

create or replace function public.can_reveal_submission_ids(ids uuid[])
returns table(submission_id uuid, can_reveal boolean)
language sql
stable
set search_path to 'public'
as $$
  select * from private.can_reveal_submission_ids(ids);
$$;

revoke all on function public.can_reveal_submission_ids(uuid[]) from public, anon;
grant execute on function public.can_reveal_submission_ids(uuid[]) to authenticated, service_role;

-- Purge expired clip rows + orphan storage objects with no workout_clips row.
create or replace function public.purge_expired_workout_clips()
returns integer
language plpgsql
security definer
set search_path to 'public', 'storage'
as $$
declare
  removed integer := 0;
  orphan_removed integer := 0;
begin
  -- Supabase storage.protect_delete requires this GUC for SQL deletes.
  perform set_config('storage.allow_delete_query', 'true', true);

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

-- Invoke dispatch-pushes Edge Function via pg_net when vault secret cron_secret is set.
create or replace function private.invoke_dispatch_pushes()
returns bigint
language plpgsql
security definer
set search_path to 'public', 'net', 'vault'
as $$
declare
  secret text;
  request_id bigint;
begin
  select ds.decrypted_secret into secret
  from vault.decrypted_secrets ds
  where ds.name = 'cron_secret'
  limit 1;

  if secret is null or length(secret) = 0 then
    return null;
  end if;

  select net.http_post(
    url := 'https://wfxmguwfowvtkngqiqfr.supabase.co/functions/v1/dispatch-pushes',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', secret
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 15000
  ) into request_id;

  return request_id;
end;
$$;

revoke all on function private.invoke_dispatch_pushes() from public, anon, authenticated;
grant execute on function private.invoke_dispatch_pushes() to service_role;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'dispatch-pushes') then
    perform cron.unschedule((select jobid from cron.job where jobname = 'dispatch-pushes'));
  end if;
  perform cron.schedule('dispatch-pushes', '* * * * *', 'select private.invoke_dispatch_pushes();');
end;
$$;
