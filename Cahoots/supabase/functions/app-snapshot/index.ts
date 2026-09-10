import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";

// Column grants intentionally omit apple_subject_id; select("*") fails with
// "permission denied for table profiles" for authenticated/anon roles.
const PROFILE_COLUMNS =
  "id, display_name, avatar_path, timezone_identifier, shows_exact_totals, created_at, updated_at, deleted_at, appearance_preference";

const nowISO = () => new Date().toISOString();
const iso = (value: string | null | undefined) => value ? new Date(value).toISOString() : null;
const frequency = (value: string) => ({ selected_weekdays: "selectedWeekdays", times_per_week: "timesPerWeek" }[value] ?? value);
const proposalStatus = (value: string) => value;
const activityEvent = (value: string) => ({
  vote_completed: "voteCompleted", challenge_started: "challengeStarted",
  round_finished: "roundFinished", member_joined: "memberJoined",
}[value] ?? value);
const scoreEvent = (value: string) => ({ requirement_completed: "requirementCompleted" }[value] ?? value);
const verification = (value: string) => ({ honour_system: "honourSystem" }[value] ?? value);

/** Encode a Postgres `date` as start-of-day in the challenge timezone (matches client ScheduleEngine). */
function calendarDateInTimeZoneISO(dateYYYYMMDD: string, timeZone: string): string {
  try {
    // Temporal is available on Deno Deploy; produces the same instant the iOS client writes locally.
    const zoned = (Temporal as unknown as {
      ZonedDateTime: { from: (input: string) => { toInstant: () => { toString: () => string } } };
    }).ZonedDateTime.from(`${dateYYYYMMDD}T00:00:00[${timeZone}]`);
    return zoned.toInstant().toString().replace(/\+00:00$/, "Z");
  } catch {
    // Noon UTC keeps the calendar date stable across common zones if Temporal is unavailable.
    return new Date(`${dateYYYYMMDD}T12:00:00.000Z`).toISOString();
  }
}

function mapUser(row: Record<string, unknown>) {
  return {
    id: row.id,
    appleSubjectID: null,
    displayName: row.display_name, avatarPath: row.avatar_path ?? null,
    timezoneIdentifier: row.timezone_identifier,
    createdAt: iso(row.created_at as string), updatedAt: iso(row.updated_at as string),
    deletedAt: iso(row.deleted_at as string | null), showsExactTotals: row.shows_exact_totals ?? false,
  };
}

function scheduledRequirementsFor(challenge: { startDate: string; endDate: string }): number {
  const start = new Date(challenge.startDate).getTime();
  const end = new Date(challenge.endDate).getTime();
  const total = Math.floor((end - start) / 86_400_000) + 1;
  const elapsed = Math.floor((Date.now() - start) / 86_400_000) + 1;
  return Math.max(1, Math.min(elapsed, total));
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const authorization = request.headers.get("Authorization");
  if (!authorization) return json({ message: "Authentication required" }, 401);

  const client = createClient(
    Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authorization } } },
  );
  const { data: authData, error: authError } = await client.auth.getUser();
  if (authError || !authData.user) return json({ message: "Invalid session" }, 401);

  const { error: limitError } = await client.rpc("consume_rate_limit", {
    action_input: "app_snapshot",
  });
  if (limitError) return json({ message: "rate_limited" }, 429);

  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (serviceKey) {
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey);
    // Align DB challenge status with client reconcile before reading the snapshot.
    await admin.rpc("activate_due_challenges");
  }

  const userID = authData.user.id;
  const [profileResult, ownMembershipsResult, preferenceRowsResult] = await Promise.all([
    client.from("profiles").select(PROFILE_COLUMNS).eq("id", userID).single(),
    client.from("group_memberships").select("*").eq("user_id", userID).eq("status", "active"),
    client.from("notification_preferences").select("*").eq("user_id", userID),
  ]);
  const firstError = profileResult.error ?? ownMembershipsResult.error ?? preferenceRowsResult.error;
  if (firstError) return json({ message: firstError.message }, 422);

  const groupIDs = (ownMembershipsResult.data ?? []).map((row) => row.group_id);
  const empty = groupIDs.length === 0;
  const filter = <T>(query: T, column: string, values: string[]): T => empty ? (query as any).limit(0) : (query as any).in(column, values);

  const [groupsResult, membershipsResult, invitesResult, proposalsResult, challengesResult, activityResult, roundResultsResult] = await Promise.all([
    filter(client.from("groups").select("*"), "id", groupIDs),
    filter(client.from("group_memberships").select("*"), "group_id", groupIDs),
    filter(client.from("group_invites").select("*"), "group_id", groupIDs),
    filter(client.from("challenge_proposals").select("*"), "group_id", groupIDs),
    filter(client.from("challenges").select("*"), "group_id", groupIDs),
    filter(client.from("activity_feed_items").select("*").order("created_at", { ascending: false }).limit(100), "group_id", groupIDs),
    filter(client.from("round_results").select("*").order("completed_at", { ascending: false }), "group_id", groupIDs),
  ]);
  const groupError = groupsResult.error ?? membershipsResult.error ?? invitesResult.error ?? proposalsResult.error ?? challengesResult.error ?? activityResult.error ?? roundResultsResult.error;
  if (groupError) return json({ message: groupError.message }, 422);

  const proposalIDs = (proposalsResult.data ?? []).map((row) => row.id);
  const challengeIDs = (challengesResult.data ?? []).map((row) => row.id);
  const peerIDs = [...new Set((membershipsResult.data ?? []).map((row) => row.user_id))];
  const [usersResult, eligibilityResult, votesResult, submissionsResult, scoreResult, recoveryResult, reportsResult, blocksResult, clipsResult] = await Promise.all([
    peerIDs.length ? client.from("profiles").select(PROFILE_COLUMNS).in("id", peerIDs) : client.from("profiles").select(PROFILE_COLUMNS).limit(0),
    proposalIDs.length ? client.from("proposal_eligible_voters").select("*").in("proposal_id", proposalIDs) : client.from("proposal_eligible_voters").select("*").limit(0),
    proposalIDs.length ? client.from("votes").select("*").in("proposal_id", proposalIDs) : client.from("votes").select("*").limit(0),
    challengeIDs.length ? client.from("submissions").select("*").in("challenge_id", challengeIDs) : client.from("submissions").select("*").limit(0),
    challengeIDs.length ? client.from("score_events").select("*").in("challenge_id", challengeIDs) : client.from("score_events").select("*").limit(0),
    challengeIDs.length ? client.from("recovery_days").select("*").in("challenge_id", challengeIDs) : client.from("recovery_days").select("*").limit(0),
    client.from("reports").select("*").eq("reporter_id", userID),
    client.from("blocked_users").select("*").eq("blocker_id", userID),
    challengeIDs.length ? client.from("workout_clips").select("*") : client.from("workout_clips").select("*").limit(0),
  ]);
  const detailError = usersResult.error ?? eligibilityResult.error ?? votesResult.error ?? submissionsResult.error ?? scoreResult.error ?? recoveryResult.error ?? reportsResult.error ?? blocksResult.error ?? clipsResult.error;
  if (detailError) return json({ message: detailError.message }, 422);

  const users = (usersResult.data ?? []).map(mapUser);
  const userByID = new Map(users.map((user) => [user.id, user]));
  const challenges = (challengesResult.data ?? []).map((row) => ({
    id: row.id, groupID: row.group_id, proposalID: row.proposal_id,
    title: row.title, activityType: row.activity_type, measurementType: row.measurement_type,
    minimumQuantity: Number(row.minimum_quantity), frequencyType: frequency(row.frequency_type),
    scheduledWeekdays: row.scheduled_weekdays ?? [], timesPerWeek: row.times_per_week,
    startDate: new Date(`${row.start_date}T00:00:00Z`).toISOString(), endDate: new Date(`${row.end_date}T00:00:00Z`).toISOString(),
    challengeTimezone: row.challenge_timezone, dailyDeadlineMinutes: row.daily_deadline_minutes,
    recoveryDayAllowance: row.recovery_day_allowance, status: row.status,
    scoringVersion: row.scoring_version, createdAt: iso(row.created_at),
  }));
  const challengeTimezoneByID = new Map(challenges.map((challenge) => [challenge.id as string, challenge.challengeTimezone as string]));
  const scoreRows = scoreResult.data ?? [];
  const submissionRows = submissionsResult.data ?? [];
  const clipRows = clipsResult.data ?? [];
  const recoveryRows = recoveryResult.data ?? [];

  // Authoritative spoiler gating via batched SQL helper (challenge timezone + deadline).
  const revealBySubmissionID = new Map<string, boolean>();
  const peerSubmissionIDs = submissionRows
    .filter((row) => row.user_id !== userID)
    .map((row) => row.id as string);
  for (const row of submissionRows) {
    if (row.user_id === userID) revealBySubmissionID.set(row.id, true);
  }
  if (peerSubmissionIDs.length > 0) {
    const { data: revealRows } = await client.rpc("can_reveal_submission_ids", {
      ids: peerSubmissionIDs,
    });
    for (const row of revealRows ?? []) {
      revealBySubmissionID.set(row.submission_id, row.can_reveal === true);
    }
  }

  const canRevealForChallengeDay = (challengeID: string, requirementDate: string) => {
    const own = submissionRows.find((row) =>
      row.challenge_id === challengeID && row.user_id === userID && row.requirement_date === requirementDate
    );
    if (own && revealBySubmissionID.get(own.id)) return true;
    const peer = submissionRows.find((row) =>
      row.challenge_id === challengeID && row.requirement_date === requirementDate && revealBySubmissionID.get(row.id) === true
    );
    if (peer) return true;
    return recoveryRows.some((row) =>
      row.challenge_id === challengeID && row.user_id === userID && row.requirement_date === requirementDate
    );
  };

  // Per group+challenge leaderboard entries with groupID and challengeID set.
  const leaderboard: Array<Record<string, unknown>> = [];
  for (const groupID of groupIDs) {
    const groupChallenges = challenges.filter((c) => c.groupID === groupID);
    const primary = groupChallenges.find((c) => c.status === "active")
      ?? groupChallenges.find((c) => c.status === "scheduled")
      ?? groupChallenges[0];
    if (!primary) continue;
    const scheduledRequirements = scheduledRequirementsFor(primary);
    const memberIDs = (membershipsResult.data ?? [])
      .filter((row) => row.group_id === groupID && row.status === "active")
      .map((row) => row.user_id);
    for (const memberID of memberIDs) {
      const user = userByID.get(memberID);
      if (!user) continue;
      const events = scoreRows.filter((row) => row.user_id === memberID && row.challenge_id === primary.id);
      let points = events.reduce((sum, row) => sum + row.points, 0);
      if (memberID !== userID) {
        const todayISO = new Date().toISOString().slice(0, 10);
        if (!canRevealForChallengeDay(primary.id, todayISO)) {
          const todayEvents = events.filter((row) => String(row.created_at).slice(0, 10) === todayISO);
          points -= todayEvents.reduce((sum, row) => sum + row.points, 0);
        }
      }
      const completions = events.filter((row) => row.event_type === "requirement_completed");
      leaderboard.push({
        user, points: Math.max(0, points),
        completedRequirements: completions.length, scheduledRequirements,
        currentStreak: 0, longestStreak: 0,
        finalScoreAchievedAt: iso(events.map((row) => row.created_at).sort().at(-1)) ?? nowISO(),
        previousRank: null, groupID, challengeID: primary.id,
      });
    }
  }

  const preferenceRows = preferenceRowsResult.data ?? [];
  const globalPref = preferenceRows.find((row) => row.group_id == null) ?? {
    id: crypto.randomUUID(), user_id: userID, group_id: null,
    personal_reminders_enabled: true, friend_activity_mode: "immediate", challenge_updates_enabled: true,
    quiet_hours_start: 1320, quiet_hours_end: 420, reminder_minutes: 1080,
    primer_dismissed: false, default_reminder_minutes: 1080,
  };
  const groupPrefs = preferenceRows.filter((row) => row.group_id != null);
  const notificationSettings = {
    quietHoursStart: globalPref.quiet_hours_start,
    quietHoursEnd: globalPref.quiet_hours_end,
    defaultReminderMinutes: globalPref.default_reminder_minutes ?? globalPref.reminder_minutes ?? 1080,
    primerDismissed: globalPref.primer_dismissed ?? false,
    groups: (groupPrefs.length
      ? groupPrefs
      : groupIDs.map((id) => ({
        group_id: id,
        personal_reminders_enabled: true,
        friend_activity_mode: "immediate",
        challenge_updates_enabled: true,
        reminder_minutes: null,
      }))
    ).map((row) => ({
      groupID: row.group_id,
      personalRemindersEnabled: row.personal_reminders_enabled ?? true,
      friendActivityMode: row.friend_activity_mode ?? "immediate",
      challengeUpdatesEnabled: row.challenge_updates_enabled ?? true,
      reminderMinutes: row.reminder_minutes ?? null,
    })),
  };

  const roundResults = (roundResultsResult.data ?? []).map((row) => {
    const topThreeRaw = Array.isArray(row.top_three) ? row.top_three : [];
    const membersRaw = Array.isArray(row.members) ? row.members : [];
    return {
      id: row.id,
      groupID: row.group_id,
      challengeID: row.challenge_id,
      title: row.title,
      winnerName: row.winner_name,
      topThree: topThreeRaw.map((entry: Record<string, unknown>) => ({
        user: {
          id: entry.userID ?? crypto.randomUUID(),
          appleSubjectID: null,
          displayName: entry.displayName ?? "Member",
          avatarPath: null,
          timezoneIdentifier: "UTC",
          createdAt: nowISO(),
          updatedAt: nowISO(),
          deletedAt: null,
          showsExactTotals: false,
        },
        points: Number(entry.points ?? 0),
        completedRequirements: Number(entry.completions ?? 0),
        scheduledRequirements: 0,
        currentStreak: 0,
        longestStreak: 0,
        finalScoreAchievedAt: iso(row.completed_at) ?? nowISO(),
        previousRank: null,
        groupID: row.group_id,
        challengeID: row.challenge_id,
      })),
      members: membersRaw.map((entry: Record<string, unknown>) => ({
        user: {
          id: entry.userID ?? crypto.randomUUID(),
          appleSubjectID: null,
          displayName: entry.displayName ?? "Member",
          avatarPath: null,
          timezoneIdentifier: "UTC",
          createdAt: nowISO(),
          updatedAt: nowISO(),
          deletedAt: null,
          showsExactTotals: false,
        },
        completionRate: 0,
        points: Number(entry.points ?? 0),
        longestStreak: 0,
      })),
      totalCompletions: row.total_completions,
      personalBest: row.personal_best,
      completedAt: iso(row.completed_at),
    };
  });

  const previousRound = roundResults[0]
    ? {
      id: roundResults[0].id,
      title: roundResults[0].title,
      winnerName: roundResults[0].winnerName,
      topThree: roundResults[0].topThree,
      totalCompletions: roundResults[0].totalCompletions,
      personalBest: roundResults[0].personalBest,
    }
    : null;

  const appearance = (profileResult.data as Record<string, unknown>)?.appearance_preference ?? "system";

  return json({
    schemaVersion: 3,
    currentUser: mapUser(profileResult.data), users,
    groups: (groupsResult.data ?? []).map((row) => ({ id: row.id, name: row.name, emoji: row.emoji, ownerID: row.owner_id, memberLimit: row.member_limit, createdAt: iso(row.created_at), updatedAt: iso(row.updated_at), archivedAt: iso(row.archived_at) })),
    memberships: (membershipsResult.data ?? []).map((row) => ({ id: row.id, groupID: row.group_id, userID: row.user_id, role: row.role, status: row.status, joinedAt: iso(row.joined_at), leftAt: iso(row.left_at), notificationLevel: row.notification_level })),
    invites: (invitesResult.data ?? []).map((row) => ({ id: row.id, groupID: row.group_id, code: row.code, createdBy: row.created_by, expiresAt: iso(row.expires_at), maximumUses: row.maximum_uses, useCount: row.use_count, revokedAt: iso(row.revoked_at) })),
    challenges,
    proposals: (proposalsResult.data ?? []).map((row) => ({
      id: row.id, groupID: row.group_id, proposedBy: row.proposed_by, title: row.title,
      activityType: row.activity_type, measurementType: row.measurement_type, minimumQuantity: Number(row.minimum_quantity),
      frequencyType: frequency(row.frequency_type), scheduledWeekdays: row.scheduled_weekdays ?? [], durationDays: row.duration_days,
      proposedStartDate: new Date(`${row.proposed_start_date}T00:00:00Z`).toISOString(), challengeTimezone: row.challenge_timezone,
      dailyDeadlineMinutes: row.daily_deadline_minutes, recoveryDayAllowance: row.recovery_day_allowance,
      votingStartsAt: iso(row.voting_starts_at), votingEndsAt: iso(row.voting_ends_at),
      eligibleVoterIDs: (eligibilityResult.data ?? []).filter((eligible) => eligible.proposal_id === row.id).map((eligible) => eligible.user_id),
      status: proposalStatus(row.status), createdAt: iso(row.created_at),
    })),
    votes: (votesResult.data ?? []).map((row) => ({ id: row.id, proposalID: row.proposal_id, userID: row.user_id, choice: row.choice, createdAt: iso(row.created_at), updatedAt: iso(row.updated_at) })),
    submissions: submissionRows.map((row) => {
      const reveal = revealBySubmissionID.get(row.id) === true;
      const clips = clipRows
        .filter((clip) => clip.submission_id === row.id)
        .map((clip) => ({
          id: clip.id,
          kind: clip.kind,
          durationSeconds: Number(clip.duration_seconds),
          localFilename: null,
          remotePath: reveal ? clip.storage_path : null,
          createdAt: iso(clip.created_at),
        }));
      const timezone = challengeTimezoneByID.get(row.challenge_id) ?? "UTC";
      return {
        id: row.id, clientGeneratedID: row.client_generated_id, challengeID: row.challenge_id, userID: row.user_id,
        requirementDate: calendarDateInTimeZoneISO(row.requirement_date, timezone),
        quantity: reveal ? Number(row.quantity) : 0,
        measurementType: row.measurement_type,
        completedAt: iso(row.completed_at), submittedAt: iso(row.submitted_at), syncState: row.sync_state,
        verificationState: verification(row.verification_state), createdAt: iso(row.created_at), updatedAt: iso(row.updated_at),
        clips,
      };
    }),
    scoreEvents: scoreRows.map((row) => ({ id: row.id, challengeID: row.challenge_id, userID: row.user_id, submissionID: row.submission_id, eventType: scoreEvent(row.event_type), points: row.points, reason: row.reason, scoringVersion: row.scoring_version, createdAt: iso(row.created_at) })),
    leaderboard, allTimeLeaderboard: leaderboard,
    activity: (activityResult.data ?? []).map((row) => ({ id: row.id, groupID: row.group_id, actorID: row.actor_id, actorName: row.actor_id ? (userByID.get(row.actor_id)?.displayName ?? "A member") : "Cahoots", eventType: activityEvent(row.event_type), message: row.message, createdAt: iso(row.created_at) })),
    notificationPreference: { id: globalPref.id, userID: globalPref.user_id, groupID: globalPref.group_id, personalRemindersEnabled: globalPref.personal_reminders_enabled, friendActivityMode: globalPref.friend_activity_mode, challengeUpdatesEnabled: globalPref.challenge_updates_enabled, quietHoursStart: globalPref.quiet_hours_start, quietHoursEnd: globalPref.quiet_hours_end, reminderMinutes: globalPref.reminder_minutes },
    notificationSettings,
    pendingOperations: submissionRows.filter((row) => row.sync_state === "waiting" && row.user_id === userID).map((row) => ({ id: crypto.randomUUID(), clientGeneratedID: row.client_generated_id, kind: "submission", retryCount: 0, nextRetryAt: nowISO(), createdAt: iso(row.created_at), lastError: null })),
    recoveryDays: recoveryRows.map((row) => {
      const timezone = challengeTimezoneByID.get(row.challenge_id) ?? "UTC";
      return {
        id: row.id, challengeID: row.challenge_id, userID: row.user_id,
        requirementDate: calendarDateInTimeZoneISO(row.requirement_date, timezone),
        createdAt: iso(row.created_at),
      };
    }),
    previousRound,
    roundResults,
    appearance,
    reports: (reportsResult.data ?? []).map((row) => ({ id: row.id, reporterID: row.reporter_id, reportedUserID: row.reported_user_id, groupID: row.group_id, reason: row.reason, createdAt: iso(row.created_at) })),
    blockedUsers: (blocksResult.data ?? []).map((row) => ({ id: row.id, blockerID: row.blocker_id, blockedUserID: row.blocked_user_id, createdAt: iso(row.created_at) })),
  });
});
