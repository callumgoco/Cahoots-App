-- 202609070006 fixed account deletion inside the app, but the Supabase dashboard (and any
-- admin API caller) deletes straight from auth.users, which never runs that cleanup and so
-- still failed with "Database error deleting user" for anyone who owned a group.
--
-- The cleanup now lives in one function behind a BEFORE DELETE trigger on auth.users, so every
-- route into a deletion clears the NOT NULL / NO ACTION references before the profiles cascade
-- runs. delete_my_account() becomes a guard plus a plain delete.
--
-- The two routes differ only in how they treat a group other people are still active in. In
-- the app the owner has to nominate a successor, so the guard stands. An admin deleting an
-- account from the dashboard has nobody to ask, so ownership is handed to the longest-serving
-- remaining admin instead of destroying everyone else's group.

create or replace function private.release_user_owned_data(target uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  owned record;
  successor uuid;
  doomed_groups uuid[];
  doomed_proposals uuid[];
begin
  -- Hand over any group that still has other active members, mirroring
  -- transfer_group_ownership: longest-serving admin first, then longest-serving member.
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

  -- Whatever is still owned has nobody left in it, so it goes entirely. Deepest rows first,
  -- because score_events -> submissions and challenges -> proposals are NO ACTION and would
  -- otherwise fire part way through a cascade.
  select coalesce(array_agg(id), '{}') into doomed_groups
  from public.groups where owner_id = target;

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
  delete from public.group_invites where created_by = target;

  select coalesce(array_agg(id), '{}') into doomed_proposals
  from public.challenge_proposals where proposed_by = target;

  update public.challenges set proposal_id = null where proposal_id = any(doomed_proposals);
  delete from public.votes where proposal_id = any(doomed_proposals);
  delete from public.proposal_eligible_voters where proposal_id = any(doomed_proposals);
  delete from public.challenge_proposals where id = any(doomed_proposals);

  -- This account's own rows in other people's groups, again deepest first.
  delete from public.score_events where user_id = target;
  delete from public.workout_clips wc
    using public.submissions s
    where wc.submission_id = s.id and s.user_id = target;
  delete from public.submissions where user_id = target;
end;
$$;

revoke all on function private.release_user_owned_data(uuid) from public, anon, authenticated;
grant execute on function private.release_user_owned_data(uuid) to service_role;

create or replace function private.release_user_data_on_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.release_user_owned_data(old.id);
  return old;
end;
$$;

-- supabase_auth_admin owns the delete that fires this, so it needs to be able to run it.
grant execute on function private.release_user_data_on_delete() to supabase_auth_admin, service_role;

drop trigger if exists on_auth_user_deleted on auth.users;
create trigger on_auth_user_deleted
  before delete on auth.users
  for each row execute function private.release_user_data_on_delete();

-- With the trigger in place this only has to enforce the product rule and remove the row;
-- the trigger clears the blockers and the profiles cascade takes the rest.
create or replace function private.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not_authenticated';
  end if;

  -- In the app the owner has to nominate a successor before they can go.
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

  delete from auth.users where id = uid;
end;
$$;

revoke all on function private.delete_my_account() from public, anon;
grant execute on function private.delete_my_account() to authenticated, service_role;
