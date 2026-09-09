import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";
import { loadApnsConfig, sendApnsAlert } from "../_shared/apns.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const authorization = request.headers.get("Authorization");
    if (!authorization) return json({ message: "Authentication required" }, 401);

    const client = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authorization } } },
    );
    const { data: userData, error: userError } = await client.auth.getUser();
    if (userError || !userData.user) return json({ message: "Invalid session" }, 401);

    const body = await request.json();
    const clips = (body.clips ?? []).map((clip: Record<string, unknown>) => ({
      id: clip.id ?? clip.clipID,
      kind: clip.kind,
      durationSeconds: clip.durationSeconds ?? clip.duration_seconds,
      storagePath: clip.remotePath ?? clip.storagePath ?? clip.storage_path ?? clip.localFilename,
    }));

    const { data, error } = await client.rpc("accept_submission", {
      client_id: body.clientGeneratedID ?? body.client_generated_id,
      challenge_id_input: body.challengeID ?? body.challenge_id,
      requirement_date_input: body.requirementDate ?? body.requirement_date,
      quantity_input: body.quantity,
      completed_at_input: body.completedAt ?? body.completed_at,
      clips_input: clips,
    });
    if (error) return json({ message: error.message }, 422);

    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (serviceKey) {
      const admin = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey);
      await fanOutFriendPosted(admin, {
        actorID: userData.user.id,
        challengeID: body.challengeID ?? body.challenge_id,
        requirementDate: body.requirementDate ?? body.requirement_date,
      });
    }

    return json(data?.[0] ?? data);
  } catch (error) {
    return json({ message: error instanceof Error ? error.message : "Unexpected error" }, 500);
  }
});

async function fanOutFriendPosted(
  admin: ReturnType<typeof createClient>,
  input: { actorID: string; challengeID: string; requirementDate: string },
) {
  const { data: challenge } = await admin.from("challenges").select("*").eq("id", input.challengeID).maybeSingle();
  if (!challenge) return;
  const { data: actor } = await admin.from("profiles").select("display_name").eq("id", input.actorID).maybeSingle();
  const { data: group } = await admin.from("groups").select("name").eq("id", challenge.group_id).maybeSingle();
  const actorName = actor?.display_name ?? "A member";
  const groupName = group?.name ?? "your group";

  const { data: memberships } = await admin
    .from("group_memberships")
    .select("user_id")
    .eq("group_id", challenge.group_id)
    .eq("status", "active");
  const memberIDs = (memberships ?? []).map((row) => row.user_id).filter((id) => id !== input.actorID);
  if (memberIDs.length === 0) return;

  const { data: preferences } = await admin
    .from("notification_preferences")
    .select("*")
    .in("user_id", memberIDs);

  const { data: completions } = await admin
    .from("submissions")
    .select("user_id, quantity")
    .eq("challenge_id", input.challengeID)
    .eq("requirement_date", input.requirementDate)
    .neq("sync_state", "rejected");

  const completedIDs = new Set(
    (completions ?? [])
      .filter((row) => Number(row.quantity) >= Number(challenge.minimum_quantity))
      .map((row) => row.user_id),
  );

  const { data: tokens } = await admin
    .from("device_push_tokens")
    .select("user_id, token, environment")
    .in("user_id", memberIDs);

  const prefsByUser = new Map<string, Array<Record<string, unknown>>>();
  for (const pref of preferences ?? []) {
    const list = prefsByUser.get(pref.user_id) ?? [];
    list.push(pref);
    prefsByUser.set(pref.user_id, list);
  }

  const tokensByUser = new Map<string, Array<{ token: string; environment: string }>>();
  for (const token of tokens ?? []) {
    const list = tokensByUser.get(token.user_id) ?? [];
    list.push(token);
    tokensByUser.set(token.user_id, list);
  }

  await admin.from("activity_feed_items").insert({
    group_id: challenge.group_id,
    actor_id: input.actorID,
    event_type: "completion",
    message: "A member completed today's challenge.",
  });

  const apns = loadApnsConfig();
  const deepLink = `cahoots://log/${challenge.group_id}`;

  for (const memberID of memberIDs) {
    const prefs = prefsByUser.get(memberID) ?? [];
    const groupPref = prefs.find((row) => row.group_id === challenge.group_id);
    const globalPref = prefs.find((row) => row.group_id == null);
    const mode = (groupPref?.friend_activity_mode ?? globalPref?.friend_activity_mode ?? "digest") as string;
    if (mode === "off") continue;

    const quietStart = Number(groupPref?.quiet_hours_start ?? globalPref?.quiet_hours_start ?? 22 * 60);
    const quietEnd = Number(groupPref?.quiet_hours_end ?? globalPref?.quiet_hours_end ?? 7 * 60);

    const viewerHasCompleted = completedIDs.has(memberID);
    const body = viewerHasCompleted
      ? `${actorName} just posted in ${groupName}.`
      : `${actorName} posted in ${groupName} — log yours to see it.`;

    if (mode === "digest") {
      await admin.from("push_digest_events").insert({
        user_id: memberID,
        group_id: challenge.group_id,
        actor_id: input.actorID,
        actor_name: actorName,
        group_name: groupName,
      });
      continue;
    }

    if (isInQuietHours(quietStart, quietEnd)) {
      await admin.from("push_digest_events").insert({
        user_id: memberID,
        group_id: challenge.group_id,
        actor_id: input.actorID,
        actor_name: actorName,
        group_name: groupName,
      });
      continue;
    }

    const memberTokens = tokensByUser.get(memberID) ?? [];
    for (const tokenRow of memberTokens) {
      const environment = tokenRow.environment === "production" ? "production" : "sandbox";
      let delivered = false;
      if (apns) {
        const result = await sendApnsAlert(apns, {
          token: tokenRow.token,
          environment,
          title: groupName,
          body,
          deepLink,
        });
        if (result.ok) {
          delivered = true;
        } else if (result.shouldInvalidateToken) {
          await admin.from("device_push_tokens").delete().eq("token", tokenRow.token);
          continue;
        }
      }

      if (!delivered) {
        await admin.from("push_outbox").insert({
          user_id: memberID,
          token: tokenRow.token,
          environment,
          title: groupName,
          body,
          deep_link: deepLink,
        });
      }
    }
  }
}

function isInQuietHours(startMinutes: number, endMinutes: number): boolean {
  const now = new Date();
  const minutes = now.getUTCHours() * 60 + now.getUTCMinutes();
  if (startMinutes === endMinutes) return false;
  if (startMinutes < endMinutes) return minutes >= startMinutes && minutes < endMinutes;
  return minutes >= startMinutes || minutes < endMinutes;
}
