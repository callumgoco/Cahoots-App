-- When a proposal passes, insert the challenge as active if its start date is
-- already due and the group has no other active challenge (mirrors start_round_now).
-- Otherwise keep it scheduled for activate_due_challenges / complete_challenge.

create or replace function public.finalize_vote(proposal_id_input uuid)
returns public.proposal_status
language plpgsql
security definer
set search_path = public
as $$
declare
  p public.challenge_proposals%rowtype;
  eligible integer;
  accepts integer;
  total_votes integer;
  required integer;
  outcome public.proposal_status;
  status_val public.challenge_status := 'scheduled';
  feed_message text;
begin
  select * into p from public.challenge_proposals where id = proposal_id_input for update;
  if p.status <> 'voting' then return p.status; end if;

  select count(*) into eligible from public.proposal_eligible_voters where proposal_id = p.id;
  select count(*) filter (where choice = 'accept'), count(*)
    into accepts, total_votes
  from public.votes where proposal_id = p.id;

  required := floor(eligible / 2.0) + 1;
  if accepts >= greatest(2, required) then
    outcome := 'passed';
  elsif total_votes = eligible or now() >= p.voting_ends_at then
    outcome := 'failed';
  else
    return 'voting';
  end if;

  update public.challenge_proposals set status = outcome where id = p.id;

  if outcome = 'passed' then
    status_val := case
      when p.proposed_start_date <= (now() at time zone p.challenge_timezone)::date
           and not exists (
             select 1 from public.challenges
             where group_id = p.group_id and status = 'active'
           )
        then 'active'::public.challenge_status
      else 'scheduled'::public.challenge_status
    end;

    insert into public.challenges(
      group_id, proposal_id, title, activity_type, measurement_type, minimum_quantity,
      frequency_type, scheduled_weekdays, start_date, end_date, challenge_timezone,
      daily_deadline_minutes, recovery_day_allowance, status
    )
    values (
      p.group_id, p.id, p.title, p.activity_type, p.measurement_type, p.minimum_quantity,
      p.frequency_type, p.scheduled_weekdays, p.proposed_start_date,
      p.proposed_start_date + (p.duration_days - 1), p.challenge_timezone,
      p.daily_deadline_minutes, p.recovery_day_allowance, status_val
    )
    on conflict(proposal_id) do nothing;

    feed_message := case
      when status_val = 'active' then 'The proposal passed and the challenge has started.'
      else 'The proposal passed and is scheduled.'
    end;
  else
    feed_message := 'The proposal did not pass.';
  end if;

  insert into public.activity_feed_items(group_id, actor_id, event_type, message)
  values (p.group_id, null, 'vote_completed', feed_message);

  return outcome;
end;
$$;
