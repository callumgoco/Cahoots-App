-- Phase 4: consolidate group_invites RLS.
-- Invite create/revoke/regenerate/redeem go through security-definer RPCs.
-- Clients only need SELECT for app-snapshot; the old FOR ALL admin policy
-- overlapped SELECT and triggered multiple_permissive_policies WARN.

drop policy if exists invites_member_read on public.group_invites;
drop policy if exists invites_admin_write on public.group_invites;

create policy invites_member_read on public.group_invites
  for select
  using (private.is_active_group_member(group_id));
