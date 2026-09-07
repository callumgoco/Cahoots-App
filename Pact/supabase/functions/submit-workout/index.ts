import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";

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
    .select("user_id, token")
    .in("user_id", memberIDs);

  const preferenceByUser = new Map((preferences ?? []).map((row) => [row.user_id, row]));
  for (const tokenRow of tokens ?? []) {
    const preference = preferenceByUser.get(tokenRow.user_id);
    const mode = preference?.friend_activity_mode ?? "digest";
    if (mode === "off") continue;
    if (mode === "digest") continue; // digest job aggregates later

    const quietStart = preference?.quiet_hours_start ?? 22 * 60;
    const quietEnd = preference?.quiet_hours_end ?? 7 * 60;
    if (isInQuietHours(quietStart, quietEnd)) continue;

    const viewerHasCompleted = completedIDs.has(tokenRow.user_id);
    const body = viewerHasCompleted
      ? `${actorName} just posted in ${groupName}.`
      : `${actorName} posted in ${groupName} — log yours to see it.`;

    // APNs delivery is environment-specific; record intent for the push worker.
    await admin.from("activity_feed_items").insert({
      group_id: challenge.group_id,
      actor_id: input.actorID,
      event_type: "completion",
      message: body,
    }).select().maybeSingle();

    // Token is available for an external APNs worker; never embed quantities.
    console.log(JSON.stringify({
      type: "friend_posted",
      token: tokenRow.token,
      title: groupName,
      body,
      deepLink: `round://log/${challenge.group_id}`,
    }));
  }
}

function isInQuietHours(startMinutes: number, endMinutes: number): boolean {
  const now = new Date();
  const minutes = now.getHours() * 60 + now.getMinutes();
  if (startMinutes === endMinutes) return false;
  if (startMinutes < endMinutes) return minutes >= startMinutes && minutes < endMinutes;
  return minutes >= startMinutes || minutes < endMinutes;
}
