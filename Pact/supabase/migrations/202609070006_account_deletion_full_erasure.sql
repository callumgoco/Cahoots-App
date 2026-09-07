-- Account deletion could not complete for anyone who had ever owned a group.
--
-- profiles.id -> auth.users.id cascades, but groups.owner_id, group_invites.created_by and
-- challenge_proposals.proposed_by all reference profiles with NO ACTION over NOT NULL columns,
-- so the cascade was refused: the dashboard reported "Database error deleting user" and
-- delete-account returned 422 after delete_my_account() had already committed, stranding
-- half-deleted accounts.
--
-- Separately, score_events_immutable fired on DELETE, which contradicted the
-- score_events.user_id -> profiles ON DELETE CASCADE it shares a table with. Client deletes
-- are already impossible (score_events exposes only a SELECT policy), so the trigger now
-- guards UPDATE only and legitimate cascades are allowed through.

drop trigger if exists score_events_immutable on public.score_events;
create trigger score_events_immutable
  before update on public.score_events
  for each row execute function public.reject_score_event_mutation();

-- Removes the account and everything belonging to it in one transaction, so a failure can no
-- longer leave the profile anonymised while the credentials survive.
create or replace function private.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  doomed_groups uuid[];
  doomed_proposals uuid[];
begin
  if uid is null then
    raise exception 'not_authenticated';
  end if;

  -- A group that still has other active members has to be handed over first.
  if exists (
    select 1
    from public.groups g
    where g.owner_id = uid
      and exists (
        select 1 from public.group_memberships m
        where m.group_id = g.id and m.status = 'active' and m.user_id <> uid
      )
  ) then
    raise exception 'transfer_ownership_required';
  end if;

  select coalesce(array_agg(id), '{}') into doomed_groups
  from public.groups where owner_id = uid;

  -- Groups this account owns go entirely; the guard above proved nobody else is in them.
  -- Deepest rows first, because score_events -> submissions and challenges -> proposals are
  -- NO ACTION and would otherwise fire part way through a cascade.
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

  -- Artefacts this account created inside groups it does not own. Both columns are NOT NULL,
  -- so the rows have to go, but a challenge that grew out of a proposal is only detached so
  -- the remaining members keep the round they are running.
  delete from public.group_invites where created_by = uid;

  select coalesce(array_agg(id), '{}') into doomed_proposals
  from public.challenge_proposals where proposed_by = uid;

  update public.challenges set proposal_id = null where proposal_id = any(doomed_proposals);
  delete from public.votes where proposal_id = any(doomed_proposals);
  delete from public.proposal_eligible_voters where proposal_id = any(doomed_proposals);
  delete from public.challenge_proposals where id = any(doomed_proposals);

  -- This account's own rows in other people's groups, again deepest first.
  delete from public.score_events where user_id = uid;
  delete from public.workout_clips wc
    using public.submissions s
    where wc.submission_id = s.id and s.user_id = uid;
  delete from public.submissions where user_id = uid;

  -- profiles cascades whatever is left (memberships, votes, recovery days, reports, blocks,
  -- push tokens, notification preferences) and nulls activity_feed_items.actor_id.
  delete from public.profiles where id = uid;
  delete from auth.users where id = uid;
end;
$$;

revoke all on function private.delete_my_account() from public, anon;
grant execute on function private.delete_my_account() to authenticated, service_role;
