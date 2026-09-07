begin;

create extension if not exists pgcrypto;

create type public.group_role as enum ('owner', 'admin', 'member');
create type public.membership_status as enum ('active', 'removed', 'left');
create type public.notification_level as enum ('immediate', 'digest', 'off');
create type public.measurement_type as enum ('repetitions', 'seconds', 'minutes', 'distance');
create type public.frequency_type as enum ('daily', 'selected_weekdays', 'times_per_week');
create type public.proposal_status as enum ('draft', 'voting', 'passed', 'failed', 'cancelled');
create type public.vote_choice as enum ('accept', 'reject');
create type public.challenge_status as enum ('scheduled', 'active', 'completed', 'cancelled');
create type public.sync_state as enum ('synced', 'waiting', 'failed', 'rejected');
create type public.verification_state as enum ('honour_system', 'accepted', 'rejected');
create type public.score_event_type as enum ('requirement_completed', 'bonus', 'adjustment');
create type public.activity_event_type as enum ('completion', 'recovery', 'proposal', 'vote_completed', 'challenge_started', 'round_finished', 'member_joined');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  apple_subject_id text unique,
  display_name text not null check (char_length(display_name) between 2 and 40),
  avatar_path text,
  timezone_identifier text not null default 'UTC',
  shows_exact_totals boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 36),
  emoji text not null default '⚡️',
  owner_id uuid not null references public.profiles(id),
  member_limit smallint not null default 20 check (member_limit between 2 and 20),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz
);

create table public.group_memberships (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.group_role not null default 'member',
  status public.membership_status not null default 'active',
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  notification_level public.notification_level not null default 'digest',
  unique(group_id, user_id)
);

create table public.group_invites (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  code text not null unique check (code ~ '^[A-Z2-9]{6}$'),
  created_by uuid not null references public.profiles(id),
  expires_at timestamptz not null,
  maximum_uses smallint not null check (maximum_uses between 1 and 20),
  use_count smallint not null default 0 check (use_count >= 0),
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.challenge_proposals (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  proposed_by uuid not null references public.profiles(id),
  title text not null check (char_length(title) between 2 and 52),
  activity_type text not null check (char_length(activity_type) between 2 and 60),
  measurement_type public.measurement_type not null,
  minimum_quantity numeric(12,2) not null check (minimum_quantity > 0),
  frequency_type public.frequency_type not null,
  scheduled_weekdays smallint[] not null default '{}',
  duration_days smallint not null check (duration_days between 7 and 90),
  proposed_start_date date not null,
  challenge_timezone text not null,
  daily_deadline_minutes smallint not null check (daily_deadline_minutes between 0 and 1439),
  recovery_day_allowance smallint not null default 0 check (recovery_day_allowance between 0 and 4),
  voting_starts_at timestamptz not null,
  voting_ends_at timestamptz not null,
  status public.proposal_status not null default 'draft',
  created_at timestamptz not null default now(),
  check (voting_ends_at = voting_starts_at + interval '48 hours')
);

create table public.proposal_eligible_voters (
  proposal_id uuid not null references public.challenge_proposals(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  primary key (proposal_id, user_id)
);

create table public.votes (
  id uuid primary key default gen_random_uuid(),
  proposal_id uuid not null references public.challenge_proposals(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  choice public.vote_choice not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(proposal_id, user_id)
);

create table public.challenges (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  proposal_id uuid unique references public.challenge_proposals(id),
  title text not null,
  activity_type text not null,
  measurement_type public.measurement_type not null,
  minimum_quantity numeric(12,2) not null check (minimum_quantity > 0),
  frequency_type public.frequency_type not null,
  scheduled_weekdays smallint[] not null default '{}',
  times_per_week smallint check (times_per_week between 1 and 7),
  start_date date not null,
  end_date date not null,
  challenge_timezone text not null,
  daily_deadline_minutes smallint not null check (daily_deadline_minutes between 0 and 1439),
  recovery_day_allowance smallint not null default 0 check (recovery_day_allowance between 0 and 4),
  status public.challenge_status not null default 'scheduled',
  scoring_version integer not null default 1,
  created_at timestamptz not null default now(),
  check (end_date >= start_date)
);

create unique index one_active_challenge_per_group on public.challenges(group_id) where status = 'active';
create unique index one_scheduled_challenge_per_group on public.challenges(group_id) where status = 'scheduled';

create table public.submissions (
  id uuid primary key default gen_random_uuid(),
  client_generated_id uuid not null unique,
  challenge_id uuid not null references public.challenges(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  requirement_date date not null,
  quantity numeric(12,2) not null check (quantity > 0),
  measurement_type public.measurement_type not null,
  completed_at timestamptz not null,
  submitted_at timestamptz not null default now(),
  sync_state public.sync_state not null default 'synced',
  verification_state public.verification_state not null default 'honour_system',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.score_events (
  id uuid primary key default gen_random_uuid(),
  challenge_id uuid not null references public.challenges(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  submission_id uuid references public.submissions(id),
  event_type public.score_event_type not null,
  points integer not null check (points between -110 and 110),
  reason text not null,
  scoring_version integer not null,
  created_at timestamptz not null default now()
);

create table public.recovery_days (
  id uuid primary key default gen_random_uuid(),
  challenge_id uuid not null references public.challenges(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  requirement_date date not null,
  created_at timestamptz not null default now(),
  unique(challenge_id, user_id, requirement_date)
);

create table public.activity_feed_items (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  event_type public.activity_event_type not null,
  message text not null,
  created_at timestamptz not null default now()
);

create table public.notification_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  group_id uuid references public.groups(id) on delete cascade,
  personal_reminders_enabled boolean not null default true,
  friend_activity_mode public.notification_level not null default 'digest',
  challenge_updates_enabled boolean not null default true,
  quiet_hours_start smallint not null default 1320 check (quiet_hours_start between 0 and 1439),
  quiet_hours_end smallint not null default 420 check (quiet_hours_end between 0 and 1439),
  reminder_minutes smallint not null default 1080 check (reminder_minutes between 0 and 1439),
  unique nulls not distinct (user_id, group_id)
);

create table public.device_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  token text not null unique,
  environment text not null check (environment in ('sandbox', 'production')),
  created_at timestamptz not null default now()
);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reported_user_id uuid not null references public.profiles(id) on delete cascade,
  group_id uuid not null references public.groups(id) on delete cascade,
  reason text not null check (char_length(reason) between 2 and 280),
  created_at timestamptz not null default now()
);

create table public.blocked_users (
  id uuid primary key default gen_random_uuid(),
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(blocker_id, blocked_user_id),
  check (blocker_id <> blocked_user_id)
);

create index memberships_user_status_idx on public.group_memberships(user_id, status, group_id);
create index memberships_group_status_idx on public.group_memberships(group_id, status);
create index proposals_group_status_idx on public.challenge_proposals(group_id, status, voting_ends_at);
create index votes_proposal_idx on public.votes(proposal_id, choice);
create index challenges_group_dates_idx on public.challenges(group_id, start_date, end_date);
create index submissions_challenge_user_date_idx on public.submissions(challenge_id, user_id, requirement_date);
create index score_events_challenge_user_idx on public.score_events(challenge_id, user_id, created_at);
create index activity_group_created_idx on public.activity_feed_items(group_id, created_at desc);

create or replace function public.is_active_group_member(target_group_id uuid, target_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.group_memberships where group_id = target_group_id and user_id = target_user_id and status = 'active');
$$;

create or replace function public.is_group_admin(target_group_id uuid, target_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.group_memberships where group_id = target_group_id and user_id = target_user_id and status = 'active' and role in ('owner', 'admin'));
$$;

create or replace function public.reject_score_event_mutation() returns trigger language plpgsql as $$
begin raise exception 'score events are immutable'; end;
$$;
create trigger score_events_immutable before update or delete on public.score_events for each row execute function public.reject_score_event_mutation();

create or replace function public.create_private_group(group_name text, group_emoji text, requested_limit smallint)
returns table(group_id uuid, invite_code text) language plpgsql security definer set search_path = public as $$
declare new_group_id uuid; new_code text;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  insert into public.groups(name, emoji, owner_id, member_limit)
  values (trim(group_name), coalesce(nullif(trim(group_emoji), ''), '⚡️'), auth.uid(), least(20, greatest(2, requested_limit))) returning id into new_group_id;
  insert into public.group_memberships(group_id, user_id, role) values (new_group_id, auth.uid(), 'owner');
  loop
    select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', floor(random() * 32 + 1)::integer, 1), '') into new_code from generate_series(1, 6);
    exit when not exists(select 1 from public.group_invites where code = new_code);
  end loop;
  insert into public.group_invites(group_id, code, created_by, expires_at, maximum_uses, use_count)
  values (new_group_id, new_code, auth.uid(), now() + interval '14 days', least(20, greatest(2, requested_limit)), 1);
  return query select new_group_id, new_code;
end;
$$;

create or replace function public.redeem_group_invite(invite_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare selected_invite public.group_invites%rowtype; active_count integer;
begin
  select * into selected_invite from public.group_invites where code = upper(invite_code) for update;
  if not found then raise exception 'invite_not_found'; end if;
  if selected_invite.revoked_at is not null or selected_invite.expires_at <= now() or selected_invite.use_count >= selected_invite.maximum_uses then raise exception 'invite_expired'; end if;
  if exists(select 1 from public.blocked_users b join public.group_memberships m on m.group_id = selected_invite.group_id where b.blocker_id = auth.uid() and b.blocked_user_id = m.user_id and m.role = 'owner') then raise exception 'invite_blocked'; end if;
  select count(*) into active_count from public.group_memberships where group_id = selected_invite.group_id and status = 'active';
  if active_count >= (select member_limit from public.groups where id = selected_invite.group_id) then raise exception 'group_full'; end if;
  insert into public.group_memberships(group_id, user_id, role, status) values (selected_invite.group_id, auth.uid(), 'member', 'active')
  on conflict(group_id, user_id) do update set status = 'active', role = 'member', joined_at = now(), left_at = null;
  update public.group_invites set use_count = use_count + 1 where id = selected_invite.id;
  insert into public.activity_feed_items(group_id, actor_id, event_type, message) values (selected_invite.group_id, auth.uid(), 'member_joined', 'A new member joined the group.');
  return selected_invite.group_id;
end;
$$;

create or replace function public.begin_proposal_vote(proposal_id_input uuid)
returns void language plpgsql security definer set search_path = public as $$
declare target_group uuid;
begin
  select group_id into target_group from public.challenge_proposals where id = proposal_id_input and proposed_by = auth.uid() and status = 'draft' for update;
  if target_group is null or not public.is_active_group_member(target_group) then raise exception 'not_allowed'; end if;
  if exists(select 1 from public.challenge_proposals where group_id = target_group and status = 'voting') then raise exception 'vote_already_open'; end if;
  insert into public.proposal_eligible_voters(proposal_id, user_id)
    select proposal_id_input, user_id from public.group_memberships where group_id = target_group and status = 'active';
  update public.challenge_proposals set status = 'voting', voting_starts_at = now(), voting_ends_at = now() + interval '48 hours' where id = proposal_id_input;
end;
$$;

create or replace function public.finalize_vote(proposal_id_input uuid)
returns public.proposal_status language plpgsql security definer set search_path = public as $$
declare p public.challenge_proposals%rowtype; eligible integer; accepts integer; total_votes integer; required integer; outcome public.proposal_status;
begin
  select * into p from public.challenge_proposals where id = proposal_id_input for update;
  if p.status <> 'voting' then return p.status; end if;
  select count(*) into eligible from public.proposal_eligible_voters where proposal_id = p.id;
  select count(*) filter (where choice = 'accept'), count(*) into accepts, total_votes from public.votes where proposal_id = p.id;
  required := floor(eligible / 2.0) + 1;
  if accepts >= greatest(2, required) then outcome := 'passed';
  elsif total_votes = eligible or now() >= p.voting_ends_at then outcome := 'failed';
  else return 'voting'; end if;
  update public.challenge_proposals set status = outcome where id = p.id;
  if outcome = 'passed' then
    insert into public.challenges(group_id, proposal_id, title, activity_type, measurement_type, minimum_quantity, frequency_type, scheduled_weekdays, start_date, end_date, challenge_timezone, daily_deadline_minutes, recovery_day_allowance, status)
    values (p.group_id, p.id, p.title, p.activity_type, p.measurement_type, p.minimum_quantity, p.frequency_type, p.scheduled_weekdays, p.proposed_start_date, p.proposed_start_date + (p.duration_days - 1), p.challenge_timezone, p.daily_deadline_minutes, p.recovery_day_allowance, 'scheduled')
    on conflict(proposal_id) do nothing;
  end if;
  insert into public.activity_feed_items(group_id, actor_id, event_type, message) values (p.group_id, null, 'vote_completed', case when outcome = 'passed' then 'The proposal passed and is scheduled.' else 'The proposal did not pass.' end);
  return outcome;
end;
$$;

create or replace function public.cast_vote(proposal_id_input uuid, selected_choice public.vote_choice)
returns public.proposal_status language plpgsql security definer set search_path = public as $$
begin
  if not exists(select 1 from public.proposal_eligible_voters where proposal_id = proposal_id_input and user_id = auth.uid()) then raise exception 'not_eligible'; end if;
  if not exists(select 1 from public.challenge_proposals where id = proposal_id_input and status = 'voting' and voting_ends_at > now()) then raise exception 'vote_closed'; end if;
  insert into public.votes(proposal_id, user_id, choice) values (proposal_id_input, auth.uid(), selected_choice)
  on conflict(proposal_id, user_id) do update set choice = excluded.choice, updated_at = now();
  return public.finalize_vote(proposal_id_input);
end;
$$;

create or replace function public.accept_submission(
  client_id uuid, challenge_id_input uuid, requirement_date_input date, quantity_input numeric, completed_at_input timestamptz
) returns table(submission_id uuid, points integer, verification public.verification_state) language plpgsql security definer set search_path = public as $$
declare c public.challenges%rowtype; existing public.submissions%rowtype; new_submission_id uuid; deadline timestamptz; extra_ratio numeric; awarded integer; already_completed boolean;
begin
  select * into existing from public.submissions where client_generated_id = client_id;
  if found then
    return query select existing.id, coalesce((select sum(points)::integer from public.score_events where submission_id = existing.id), 0), existing.verification_state; return;
  end if;
  select * into c from public.challenges where id = challenge_id_input and status in ('active', 'completed') for update;
  if not found or not public.is_active_group_member(c.group_id) then raise exception 'not_allowed'; end if;
  if quantity_input <= 0 or completed_at_input > now() + interval '10 minutes' then raise exception 'invalid_submission'; end if;
  deadline := ((requirement_date_input::text || ' 00:00')::timestamp at time zone c.challenge_timezone) + make_interval(mins => c.daily_deadline_minutes);
  if completed_at_input > deadline or now() > deadline + interval '24 hours' then
    insert into public.submissions(client_generated_id, challenge_id, user_id, requirement_date, quantity, measurement_type, completed_at, verification_state, sync_state)
    values(client_id, c.id, auth.uid(), requirement_date_input, quantity_input, c.measurement_type, completed_at_input, 'rejected', 'rejected') returning id into new_submission_id;
    return query select new_submission_id, 0, 'rejected'::public.verification_state; return;
  end if;
  insert into public.submissions(client_generated_id, challenge_id, user_id, requirement_date, quantity, measurement_type, completed_at, verification_state, sync_state)
  values(client_id, c.id, auth.uid(), requirement_date_input, quantity_input, c.measurement_type, completed_at_input, 'accepted', 'synced') returning id into new_submission_id;
  select exists(select 1 from public.score_events where challenge_id = c.id and user_id = auth.uid() and event_type = 'requirement_completed' and (created_at at time zone c.challenge_timezone)::date = requirement_date_input) into already_completed;
  awarded := 0;
  if quantity_input >= c.minimum_quantity and not already_completed then
    extra_ratio := greatest(0, quantity_input - c.minimum_quantity) / c.minimum_quantity;
    awarded := 100 + least(10, floor(extra_ratio * 15)::integer);
    insert into public.score_events(challenge_id, user_id, submission_id, event_type, points, reason, scoring_version)
    values(c.id, auth.uid(), new_submission_id, 'requirement_completed', 100, 'Scheduled requirement completed', c.scoring_version);
    if awarded > 100 then insert into public.score_events(challenge_id, user_id, submission_id, event_type, points, reason, scoring_version)
      values(c.id, auth.uid(), new_submission_id, 'bonus', awarded - 100, 'Capped completion bonus', c.scoring_version); end if;
    insert into public.activity_feed_items(group_id, actor_id, event_type, message) values(c.group_id, auth.uid(), 'completion', 'A member completed today''s challenge.');
  end if;
  return query select new_submission_id, awarded, 'accepted'::public.verification_state;
end;
$$;

create or replace view public.leaderboard as
select c.id challenge_id, p.id user_id, p.display_name,
       coalesce(sum(se.points), 0)::integer points,
       count(distinct se.submission_id) filter (where se.event_type = 'requirement_completed')::integer completed_requirements,
       max(se.created_at) final_score_achieved_at
from public.challenges c
join public.group_memberships gm on gm.group_id = c.group_id and gm.status = 'active'
join public.profiles p on p.id = gm.user_id
left join public.score_events se on se.challenge_id = c.id and se.user_id = p.id
group by c.id, p.id, p.display_name;

create or replace function public.use_recovery_day(challenge_id_input uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare c public.challenges%rowtype; requirement_day date; used integer; usage_id uuid; weekday_number integer;
begin
  select * into c from public.challenges where id = challenge_id_input and status = 'active' for update;
  if not found or not public.is_active_group_member(c.group_id) then raise exception 'not_allowed'; end if;
  requirement_day := (now() at time zone c.challenge_timezone)::date;
  if requirement_day < c.start_date or requirement_day > c.end_date then raise exception 'challenge_not_active_today'; end if;
  weekday_number := extract(dow from requirement_day)::integer + 1;
  if c.frequency_type = 'selected_weekdays' and not (weekday_number = any(c.scheduled_weekdays)) then raise exception 'not_scheduled_today'; end if;
  select count(*) into used from public.recovery_days where challenge_id = c.id and user_id = auth.uid();
  if used >= c.recovery_day_allowance then raise exception 'no_recovery_days_remaining'; end if;
  insert into public.recovery_days(challenge_id, user_id, requirement_date) values(c.id, auth.uid(), requirement_day)
  on conflict(challenge_id, user_id, requirement_date) do update set created_at = public.recovery_days.created_at returning id into usage_id;
  insert into public.activity_feed_items(group_id, actor_id, event_type, message) values(c.group_id, auth.uid(), 'recovery', 'A member used a recovery day.');
  return usage_id;
end;
$$;

create or replace function public.remove_group_member(group_id_input uuid, user_id_input uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_group_admin(group_id_input) then raise exception 'not_allowed'; end if;
  if user_id_input = (select owner_id from public.groups where id = group_id_input) then raise exception 'cannot_remove_owner'; end if;
  update public.group_memberships set status = 'removed', left_at = now() where group_id = group_id_input and user_id = user_id_input and status = 'active';
end;
$$;

create or replace function public.delete_my_account() returns void language plpgsql security definer set search_path = public as $$
begin
  if exists(select 1 from public.groups g join public.group_memberships m on m.group_id = g.id where g.owner_id = auth.uid() and m.status = 'active' and (select count(*) from public.group_memberships x where x.group_id = g.id and x.status = 'active') > 1) then raise exception 'transfer_ownership_required'; end if;
  update public.profiles set deleted_at = now(), display_name = 'Deleted member', avatar_path = null, apple_subject_id = null where id = auth.uid();
  update public.group_memberships set status = 'left', left_at = now() where user_id = auth.uid() and status = 'active';
end;
$$;

alter table public.profiles enable row level security;
alter table public.groups enable row level security;
alter table public.group_memberships enable row level security;
alter table public.group_invites enable row level security;
alter table public.challenge_proposals enable row level security;
alter table public.proposal_eligible_voters enable row level security;
alter table public.votes enable row level security;
alter table public.challenges enable row level security;
alter table public.submissions enable row level security;
alter table public.score_events enable row level security;
alter table public.recovery_days enable row level security;
alter table public.activity_feed_items enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.device_push_tokens enable row level security;
alter table public.reports enable row level security;
alter table public.blocked_users enable row level security;

create policy profiles_self_or_group_peers on public.profiles for select using (id = auth.uid() or exists(select 1 from public.group_memberships mine join public.group_memberships theirs on theirs.group_id = mine.group_id where mine.user_id = auth.uid() and mine.status = 'active' and theirs.user_id = profiles.id and theirs.status = 'active'));
create policy profiles_update_self on public.profiles for update using(id = auth.uid()) with check(id = auth.uid());
create policy groups_member_read on public.groups for select using(public.is_active_group_member(id));
create policy groups_admin_update on public.groups for update using(public.is_group_admin(id)) with check(public.is_group_admin(id));
create policy memberships_member_read on public.group_memberships for select using(public.is_active_group_member(group_id));
create policy invites_member_read on public.group_invites for select using(public.is_active_group_member(group_id));
create policy invites_admin_write on public.group_invites for all using(public.is_group_admin(group_id)) with check(public.is_group_admin(group_id));
create policy proposals_member_read on public.challenge_proposals for select using(public.is_active_group_member(group_id));
create policy proposals_member_insert on public.challenge_proposals for insert with check(proposed_by = auth.uid() and public.is_active_group_member(group_id));
create policy eligibility_member_read on public.proposal_eligible_voters for select using(exists(select 1 from public.challenge_proposals p where p.id = proposal_id and public.is_active_group_member(p.group_id)));
create policy votes_group_read on public.votes for select using(exists(select 1 from public.challenge_proposals p where p.id = proposal_id and public.is_active_group_member(p.group_id)));
create policy challenges_member_read on public.challenges for select using(public.is_active_group_member(group_id));
create policy submissions_group_read on public.submissions for select using(user_id = auth.uid() or exists(select 1 from public.challenges c where c.id = challenge_id and public.is_active_group_member(c.group_id)));
create policy score_events_group_read on public.score_events for select using(exists(select 1 from public.challenges c where c.id = challenge_id and public.is_active_group_member(c.group_id)));
create policy recovery_group_read on public.recovery_days for select using(user_id = auth.uid() or exists(select 1 from public.challenges c where c.id = challenge_id and public.is_active_group_member(c.group_id)));
create policy activity_member_read on public.activity_feed_items for select using(public.is_active_group_member(group_id));
create policy preferences_self_all on public.notification_preferences for all using(user_id = auth.uid()) with check(user_id = auth.uid());
create policy tokens_self_all on public.device_push_tokens for all using(user_id = auth.uid()) with check(user_id = auth.uid());
create policy reports_self_insert on public.reports for insert with check(reporter_id = auth.uid() and public.is_active_group_member(group_id));
create policy reports_self_read on public.reports for select using(reporter_id = auth.uid());
create policy blocks_self_all on public.blocked_users for all using(blocker_id = auth.uid()) with check(blocker_id = auth.uid());

grant execute on function public.create_private_group(text, text, smallint) to authenticated;
grant execute on function public.redeem_group_invite(text) to authenticated;
grant execute on function public.begin_proposal_vote(uuid) to authenticated;
grant execute on function public.cast_vote(uuid, public.vote_choice) to authenticated;
grant execute on function public.accept_submission(uuid, uuid, date, numeric, timestamptz) to authenticated;
grant execute on function public.use_recovery_day(uuid) to authenticated;
grant execute on function public.remove_group_member(uuid, uuid) to authenticated;
grant execute on function public.delete_my_account() to authenticated;

commit;
