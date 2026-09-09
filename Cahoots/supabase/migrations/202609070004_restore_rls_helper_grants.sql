-- 202609070002 revoked authenticated execute on every public SECURITY DEFINER helper,
-- including three that RLS policies call directly. Policy expressions run as the
-- invoking role, so authenticated reads failed with
-- "permission denied for function is_active_group_member".
-- Re-grant only the helpers referenced by pg_policies; anon and public stay revoked.

grant execute on function public.is_active_group_member(uuid, uuid) to authenticated;
grant execute on function public.is_group_admin(uuid, uuid) to authenticated;
grant execute on function public.can_reveal_submission(public.submissions) to authenticated;

revoke all on function public.is_active_group_member(uuid, uuid) from public, anon;
revoke all on function public.is_group_admin(uuid, uuid) from public, anon;
revoke all on function public.can_reveal_submission(public.submissions) from public, anon;
