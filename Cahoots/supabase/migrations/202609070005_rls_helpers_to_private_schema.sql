-- 202609070004 restored authenticated EXECUTE on the three helpers that RLS policies call,
-- which fixed authenticated reads but re-exposed them at /rest/v1/rpc/* (security advisor
-- "authenticated_security_definer_function_executable").
--
-- Resolve both concerns the same way 202609070003 handled the client RPCs: move the real
-- SECURITY DEFINER implementations into the unexposed `private` schema. RLS policies bind to
-- a function OID rather than a name, so every policy follows the move with no policy churn
-- and PostgREST can no longer reach them.

alter function public.is_active_group_member(uuid, uuid) set schema private;
alter function public.is_group_admin(uuid, uuid) set schema private;
alter function public.can_reveal_submission(public.submissions) set schema private;

revoke all on function private.is_active_group_member(uuid, uuid) from public, anon;
revoke all on function private.is_group_admin(uuid, uuid) from public, anon;
revoke all on function private.can_reveal_submission(public.submissions) from public, anon;

grant execute on function private.is_active_group_member(uuid, uuid) to authenticated, service_role;
grant execute on function private.is_group_admin(uuid, uuid) to authenticated, service_role;
grant execute on function private.can_reveal_submission(public.submissions) to authenticated, service_role;

-- Routines created by earlier migrations hardcode `public.` for these helpers. Keep resolvable
-- SECURITY INVOKER shims so those bodies stay valid. Every caller is a SECURITY DEFINER routine
-- that runs as its owner, so no client role needs EXECUTE on the shims.

create or replace function public.is_active_group_member(target_group_id uuid, target_user_id uuid default auth.uid())
returns boolean language sql stable security invoker set search_path = public as $$
  select private.is_active_group_member(target_group_id, target_user_id);
$$;

create or replace function public.is_group_admin(target_group_id uuid, target_user_id uuid default auth.uid())
returns boolean language sql stable security invoker set search_path = public as $$
  select private.is_group_admin(target_group_id, target_user_id);
$$;

create or replace function public.can_reveal_submission(submission_row public.submissions)
returns boolean language sql stable security invoker set search_path = public as $$
  select private.can_reveal_submission(submission_row);
$$;

revoke all on function public.is_active_group_member(uuid, uuid) from public, anon, authenticated;
revoke all on function public.is_group_admin(uuid, uuid) from public, anon, authenticated;
revoke all on function public.can_reveal_submission(public.submissions) from public, anon, authenticated;
