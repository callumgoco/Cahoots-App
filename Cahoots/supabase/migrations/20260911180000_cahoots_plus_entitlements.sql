-- Cahoots Plus: profile entitlement columns, membership caps, RPC enforcement.

alter table public.profiles
  add column if not exists entitlement text not null default 'free',
  add column if not exists plus_expires_at timestamptz,
  add column if not exists plus_preview_until timestamptz,
  add column if not exists plus_original_transaction_id text,
  add column if not exists entitlement_updated_at timestamptz;

do $$ begin
  alter table public.profiles drop constraint if exists profiles_entitlement_check;
  alter table public.profiles add constraint profiles_entitlement_check check (entitlement in ('free', 'plus'));
exception when others then null;
end $$;

comment on column public.profiles.entitlement is 'Client/StoreKit mirror: free or plus';
comment on column public.profiles.plus_preview_until is 'Grandfather / promo window granting Plus limits without a live sub';

revoke select on table public.profiles from anon, authenticated;
grant select (
  id,
  display_name,
  avatar_path,
  timezone_identifier,
  shows_exact_totals,
  created_at,
  updated_at,
  deleted_at,
  appearance_preference,
  entitlement,
  plus_expires_at,
  plus_preview_until,
  plus_original_transaction_id,
  entitlement_updated_at
) on table public.profiles to anon, authenticated;

revoke update on table public.profiles from anon, authenticated;
grant update (
  display_name,
  avatar_path,
  timezone_identifier,
  shows_exact_totals,
  updated_at,
  deleted_at,
  appearance_preference
) on table public.profiles to anon, authenticated;

-- Entitlement writes go through service_role / Edge Functions only.
grant select, update (
  entitlement,
  plus_expires_at,
  plus_preview_until,
  plus_original_transaction_id,
  entitlement_updated_at
) on table public.profiles to service_role;

create or replace function private.has_plus_access(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = uid
      and (
        (p.entitlement = 'plus' and (p.plus_expires_at is null or p.plus_expires_at > now()))
        or (p.plus_preview_until is not null and p.plus_preview_until > now())
      )
  );
$$;

revoke all on function private.has_plus_access(uuid) from public, anon;
grant execute on function private.has_plus_access(uuid) to authenticated, service_role;

create or replace function private.crew_membership_limit(uid uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select case when private.has_plus_access(uid) then 10 else 1 end;
$$;

revoke all on function private.crew_membership_limit(uuid) from public, anon;
grant execute on function private.crew_membership_limit(uuid) to authenticated, service_role;

create or replace function private.assert_can_add_crew_membership(uid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  active_count integer;
  limit_count integer;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  select count(*) into active_count
  from public.group_memberships
  where user_id = uid and status = 'active';
  limit_count := private.crew_membership_limit(uid);
  if active_count >= limit_count then
    raise exception 'plus_required';
  end if;
end;
$$;

revoke all on function private.assert_can_add_crew_membership(uuid) from public, anon;
grant execute on function private.assert_can_add_crew_membership(uuid) to authenticated, service_role;

create or replace function private.create_private_group(group_name text, group_emoji text, requested_limit smallint)
returns table(group_id uuid, invite_code text)
language plpgsql
security definer
set search_path = public
as $$
declare
  new_group_id uuid;
  new_code text;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  perform private.assert_can_add_crew_membership(auth.uid());

  insert into public.groups(name, emoji, owner_id, member_limit)
  values (
    trim(group_name),
    coalesce(nullif(trim(group_emoji), ''), '⚡️'),
    auth.uid(),
    least(20, greatest(2, requested_limit))
  )
  returning id into new_group_id;

  insert into public.group_memberships(group_id, user_id, role)
  values (new_group_id, auth.uid(), 'owner');

  loop
    select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', floor(random() * 32 + 1)::integer, 1), '')
    into new_code
    from generate_series(1, 6);
    exit when not exists(select 1 from public.group_invites where code = new_code);
  end loop;

  insert into public.group_invites(group_id, code, created_by, expires_at, maximum_uses, use_count)
  values (
    new_group_id,
    new_code,
    auth.uid(),
    now() + interval '14 days',
    least(20, greatest(2, requested_limit)),
    1
  );

  return query select new_group_id, new_code;
end;
$$;

create or replace function private.redeem_group_invite(invite_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_invite public.group_invites%rowtype;
  active_count integer;
  already_member boolean;
begin
  perform private.consume_rate_limit('invite_redeem', 10, 3600);

  select * into selected_invite from public.group_invites where code = upper(invite_code) for update;
  if not found then raise exception 'invite_not_found'; end if;
  if selected_invite.revoked_at is not null
     or selected_invite.expires_at <= now()
     or selected_invite.use_count >= selected_invite.maximum_uses then
    raise exception 'invite_expired';
  end if;
  if exists(
    select 1
    from public.blocked_users b
    join public.group_memberships m on m.group_id = selected_invite.group_id
    where b.blocker_id = auth.uid()
      and b.blocked_user_id = m.user_id
      and m.role = 'owner'
  ) then
    raise exception 'invite_blocked';
  end if;

  select exists(
    select 1
    from public.group_memberships
    where group_id = selected_invite.group_id
      and user_id = auth.uid()
      and status = 'active'
  ) into already_member;

  -- Re-joining a crew you already belong to does not consume an extra Plus slot.
  if not already_member then
    perform private.assert_can_add_crew_membership(auth.uid());
  end if;

  select count(*) into active_count
  from public.group_memberships
  where group_id = selected_invite.group_id and status = 'active';
  if active_count >= (select member_limit from public.groups where id = selected_invite.group_id)
     and not already_member then
    raise exception 'group_full';
  end if;

  insert into public.group_memberships(group_id, user_id, role, status)
  values (selected_invite.group_id, auth.uid(), 'member', 'active')
  on conflict(group_id, user_id) do update
    set status = 'active', role = 'member', joined_at = now(), left_at = null;

  if not already_member then
    update public.group_invites set use_count = use_count + 1 where id = selected_invite.id;
    insert into public.activity_feed_items(group_id, actor_id, event_type, message)
    values (selected_invite.group_id, auth.uid(), 'member_joined', 'A new member joined the group.');
  end if;

  return selected_invite.group_id;
end;
$$;

-- 90-day Plus preview for anyone already in multiple crews at ship time.
update public.profiles p
set
  plus_preview_until = greatest(coalesce(p.plus_preview_until, now()), now() + interval '90 days'),
  entitlement_updated_at = now()
where p.id in (
  select user_id
  from public.group_memberships
  where status = 'active'
  group by user_id
  having count(*) > 1
);
