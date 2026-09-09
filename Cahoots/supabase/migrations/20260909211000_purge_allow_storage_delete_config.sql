-- Allow SQL storage.object deletes inside purge_expired_workout_clips (protect_delete GUC).

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
