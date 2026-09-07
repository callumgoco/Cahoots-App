-- Move intentional client SECURITY DEFINER RPCs out of the exposed public schema.
-- Public keeps thin SECURITY INVOKER wrappers so PostgREST paths stay the same.

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;

alter function public.accept_submission(uuid, uuid, date, numeric, timestamptz) set schema private;
alter function public.accept_submission(uuid, uuid, date, numeric, timestamptz, jsonb) set schema private;
alter function public.block_user(uuid) set schema private;
alter function public.can_reveal_submission_id(uuid) set schema private;
alter function public.cast_vote(uuid, public.vote_choice) set schema private;
alter function public.create_and_open_proposal(uuid, text, text, public.measurement_type, numeric, public.frequency_type, smallint[], smallint, date, text, smallint, smallint) set schema private;
alter function public.create_private_group(text, text, smallint) set schema private;
alter function public.delete_my_account() set schema private;
alter function public.leave_group(uuid) set schema private;
alter function public.redeem_group_invite(text) set schema private;
alter function public.regenerate_group_invite(uuid) set schema private;
alter function public.register_push_token(text, text) set schema private;
alter function public.remove_group_member(uuid, uuid) set schema private;
alter function public.revoke_group_invites(uuid) set schema private;
alter function public.set_member_role(uuid, uuid, public.group_role) set schema private;
alter function public.start_round_now(uuid, text, text, public.measurement_type, numeric, public.frequency_type, smallint[], smallint, date, text, smallint, smallint) set schema private;
alter function public.submit_report(uuid, uuid, text) set schema private;
alter function public.transfer_group_ownership(uuid, uuid) set schema private;
alter function public.unblock_user(uuid) set schema private;
alter function public.update_group_settings(uuid, text, text, smallint) set schema private;
alter function public.update_my_profile(text, text, boolean, text) set schema private;
alter function public.upsert_notification_settings(jsonb) set schema private;
alter function public.use_recovery_day(uuid) set schema private;

create or replace function public.accept_submission(
  client_id uuid,
  challenge_id_input uuid,
  requirement_date_input date,
  quantity_input numeric,
  completed_at_input timestamptz
)
returns table(submission_id uuid, points integer, verification public.verification_state)
language plpgsql
security invoker
set search_path = public
as $$
begin
  return query
  select *
  from private.accept_submission(
    client_id, challenge_id_input, requirement_date_input, quantity_input, completed_at_input
  );
end;
$$;

create or replace function public.accept_submission(
  client_id uuid,
  challenge_id_input uuid,
  requirement_date_input date,
  quantity_input numeric,
  completed_at_input timestamptz,
  clips_input jsonb default '[]'::jsonb
)
returns table(submission_id uuid, points integer, verification public.verification_state)
language plpgsql
security invoker
set search_path = public
as $$
begin
  return query
  select *
  from private.accept_submission(
    client_id, challenge_id_input, requirement_date_input, quantity_input, completed_at_input, clips_input
  );
end;
$$;

create or replace function public.block_user(blocked_user_id_input uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  perform private.block_user(blocked_user_id_input);
end;
$$;

create or replace function public.can_reveal_submission_id(submission_id_input uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select private.can_reveal_submission_id(submission_id_input);
$$;

create or replace function public.cast_vote(proposal_id_input uuid, selected_choice public.vote_choice)
returns public.proposal_status
language plpgsql
security invoker
set search_path = public
as $$
begin
  return private.cast_vote(proposal_id_input, selected_choice);
end;
$$;

create or replace function public.create_and_open_proposal(
  group_id_input uuid,
  title_input text,
  activity_type_input text,
  measurement_type_input public.measurement_type,
  minimum_quantity_input numeric,
  frequency_type_input public.frequency_type,
  scheduled_weekdays_input smallint[],
  duration_days_input smallint,
  proposed_start_date_input date,
  challenge_timezone_input text,
  daily_deadline_minutes_input smallint,
  recovery_day_allowance_input smallint
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
begin
  return private.create_and_open_proposal(
    group_id_input, title_input, activity_type_input, measurement_type_input,
    minimum_quantity_input, frequency_type_input, scheduled_weekdays_input,
    duration_days_input, proposed_start_date_input, challenge_timezone_input,
    daily_deadline_minutes_input, recovery_day_allowance_input
  );
end;
$$;

create or replace function public.create_private_group(group_name text, group_emoji text, requested_limit smallint)
returns table(group_id uuid, invite_code text)
language plpgsql
security invoker
set search_path = public
as $$
begin
  return query
  select * from private.create_private_group(group_name, group_emoji, requested_limit);
end;
$$;

create or replace function public.delete_my_account()
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  perform private.delete_my_account();
end;
$$;

create or replace function public.leave_group(group_id_input uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  perform private.leave_group(group_id_input);
end;
$$;

create or replace function public.redeem_group_invite(invite_code text)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
begin
  return private.redeem_group_invite(invite_code);
end;
$$;

create or replace function public.regenerate_group_invite(group_id_input uuid)
returns text
language plpgsql
security invoker
set search_path = public
as $$
begin
  return private.regenerate_group_invite(group_id_input);
end;
$$;

create or replace function public.register_push_token(token_input text, environment_input text)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  perform private.register_push_token(token_input, environment_input);
end;
$$;

create or replace function public.remove_group_member(group_id_input uuid, user_id_input uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  perform private.remove_group_member(group_id_input, user_id_input);
end;
$$;

create or replace function public.revoke_group_invites(group_id_input uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  perform private.revoke_group_invites(group_id_input);
end;
$$;

create or replace function public.set_member_role(group_id_input uuid, user_id_input uuid, role_input public.group_role)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  perform private.set_member_role(group_id_input, user_id_input, role_input);
end;
$$;

create or replace function public.start_round_now(
  group_id_input uuid,
  title_input text,
  activity_type_input text,
  measurement_type_input public.measurement_type,
  minimum_quantity_input numeric,
  frequency_type_input public.frequency_type,
  scheduled_weekdays_input smallint[],
  duration_days_input smallint,
  start_date_input date,
  challenge_timezone_input text,
  daily_deadline_minutes_input smallint,
  recovery_day_allowance_input smallint
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
begin
  return private.start_round_now(
    group_id_input, title_input, activity_type_input, measurement_type_input,
    minimum_quantity_input, frequency_type_input, scheduled_weekdays_input,
    duration_days_input, start_date_input, challenge_timezone_input,
    daily_deadline_minutes_input, recovery_day_allowance_input
  );
end;
$$;

create or replace function public.submit_report(reported_user_id_input uuid, group_id_input uuid, reason_input text)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
begin
  return private.submit_report(reported_user_id_input, group_id_input, reason_input);
end;
$$;

create or replace function public.transfer_group_ownership(group_id_input uuid, new_owner_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  perform private.transfer_group_ownership(group_id_input, new_owner_id);
end;
$$;

create or replace function public.unblock_user(blocked_user_id_input uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  perform private.unblock_user(blocked_user_id_input);
end;
$$;

create or replace function public.update_group_settings(group_id_input uuid, name_input text, emoji_input text, member_limit_input smallint)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  perform private.update_group_settings(group_id_input, name_input, emoji_input, member_limit_input);
end;
$$;

create or replace function public.update_my_profile(
  display_name_input text default null,
  appearance_input text default null,
  shows_exact_totals_input boolean default null,
  timezone_input text default null
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  perform private.update_my_profile(
    display_name_input, appearance_input, shows_exact_totals_input, timezone_input
  );
end;
$$;

create or replace function public.upsert_notification_settings(settings_input jsonb)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  perform private.upsert_notification_settings(settings_input);
end;
$$;

create or replace function public.use_recovery_day(challenge_id_input uuid)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
begin
  return private.use_recovery_day(challenge_id_input);
end;
$$;

do $$
declare
  r record;
begin
  for r in
    select p.proname as func_name, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
  loop
    execute format('revoke all on function private.%I(%s) from public, anon', r.func_name, r.args);
    execute format('grant execute on function private.%I(%s) to authenticated, service_role', r.func_name, r.args);
  end loop;

  for r in
    select p.proname as func_name, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = any(array[
        'accept_submission','block_user','can_reveal_submission_id','cast_vote',
        'create_and_open_proposal','create_private_group','delete_my_account','leave_group',
        'redeem_group_invite','regenerate_group_invite','register_push_token','remove_group_member',
        'revoke_group_invites','set_member_role','start_round_now','submit_report',
        'transfer_group_ownership','unblock_user','update_group_settings','update_my_profile',
        'upsert_notification_settings','use_recovery_day'
      ])
  loop
    execute format('revoke all on function public.%I(%s) from public, anon', r.func_name, r.args);
    execute format('grant execute on function public.%I(%s) to authenticated, service_role', r.func_name, r.args);
  end loop;
end;
$$;
