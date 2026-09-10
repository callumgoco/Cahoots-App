-- Owner-only hard delete for a group: removes members, rounds, clips, and storage.

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

create or replace function public.delete_group(group_id_input uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  perform private.delete_group(group_id_input);
end;
$$;

revoke all on function private.delete_group(uuid) from public, anon;
grant execute on function private.delete_group(uuid) to authenticated, service_role;

revoke all on function public.delete_group(uuid) from public, anon;
grant execute on function public.delete_group(uuid) to authenticated, service_role;
