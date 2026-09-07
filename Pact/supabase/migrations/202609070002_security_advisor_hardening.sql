-- Harden SECURITY DEFINER grants and fix mutable search_path.
-- Clears anon/public execute on all public SECURITY DEFINER functions,
-- revokes authenticated execute on internal/cron/trigger helpers,
-- and re-grants only intentional client RPCs to authenticated.

create or replace function public.reject_score_event_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'score events are immutable';
end;
$$;

do $$
declare
  r record;
begin
  for r in
    select n.nspname as schema_name,
           p.proname as func_name,
           pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef = true
  loop
    execute format(
      'revoke all on function %I.%I(%s) from public, anon',
      r.schema_name, r.func_name, r.args
    );
  end loop;
end;
$$;

revoke all on function public.reject_score_event_mutation() from authenticated;
revoke all on function public.handle_new_user() from authenticated;
revoke all on function public.activate_due_challenges() from authenticated;
revoke all on function public.finalize_expired_votes() from authenticated;
revoke all on function public.complete_due_challenges() from authenticated;
revoke all on function public.purge_expired_workout_clips() from authenticated;
revoke all on function public.is_active_group_member(uuid, uuid) from authenticated;
revoke all on function public.is_group_admin(uuid, uuid) from authenticated;
revoke all on function public.can_reveal_submission(public.submissions) from authenticated;
revoke all on function public.submission_quantity_for_viewer(public.submissions) from authenticated;
revoke all on function public.finalize_vote(uuid) from authenticated;
revoke all on function public.complete_challenge(uuid) from authenticated;
revoke all on function public.begin_proposal_vote(uuid) from authenticated;

grant execute on function public.create_private_group(text, text, smallint) to authenticated;
grant execute on function public.redeem_group_invite(text) to authenticated;
grant execute on function public.cast_vote(uuid, public.vote_choice) to authenticated;
grant execute on function public.accept_submission(uuid, uuid, date, numeric, timestamptz) to authenticated;
grant execute on function public.accept_submission(uuid, uuid, date, numeric, timestamptz, jsonb) to authenticated;
grant execute on function public.use_recovery_day(uuid) to authenticated;
grant execute on function public.remove_group_member(uuid, uuid) to authenticated;
grant execute on function public.delete_my_account() to authenticated;
grant execute on function public.update_my_profile(text, text, boolean, text) to authenticated;
grant execute on function public.upsert_notification_settings(jsonb) to authenticated;
grant execute on function public.create_and_open_proposal(uuid, text, text, public.measurement_type, numeric, public.frequency_type, smallint[], smallint, date, text, smallint, smallint) to authenticated;
grant execute on function public.start_round_now(uuid, text, text, public.measurement_type, numeric, public.frequency_type, smallint[], smallint, date, text, smallint, smallint) to authenticated;
grant execute on function public.update_group_settings(uuid, text, text, smallint) to authenticated;
grant execute on function public.set_member_role(uuid, uuid, public.group_role) to authenticated;
grant execute on function public.transfer_group_ownership(uuid, uuid) to authenticated;
grant execute on function public.leave_group(uuid) to authenticated;
grant execute on function public.revoke_group_invites(uuid) to authenticated;
grant execute on function public.regenerate_group_invite(uuid) to authenticated;
grant execute on function public.block_user(uuid) to authenticated;
grant execute on function public.unblock_user(uuid) to authenticated;
grant execute on function public.submit_report(uuid, uuid, text) to authenticated;
grant execute on function public.register_push_token(text, text) to authenticated;
grant execute on function public.can_reveal_submission_id(uuid) to authenticated;
