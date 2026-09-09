-- Account deletion storage deletes also need storage.allow_delete_query.

create or replace function private.release_user_owned_data(target uuid)
returns void
language plpgsql
security definer
set search_path to 'public', 'storage'
as $function$
declare
  owned record;
  successor uuid;
  doomed_groups uuid[];
  doomed_proposals uuid[];
begin
  perform set_config('storage.allow_delete_query', 'true', true);

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
$function$;
