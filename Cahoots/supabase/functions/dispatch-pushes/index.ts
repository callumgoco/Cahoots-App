import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";
import { loadApnsConfig, sendApnsAlert } from "../_shared/apns.ts";

type OutboxRow = {
  id: string;
  user_id: string;
  token: string;
  environment: "sandbox" | "production";
  title: string;
  body: string;
  deep_link: string | null;
  attempts: number;
};

type DigestRow = {
  id: string;
  user_id: string;
  group_id: string;
  actor_name: string;
  group_name: string;
  created_at: string;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const secret = request.headers.get("x-cron-secret");
  if (!secret || secret !== Deno.env.get("CRON_SECRET")) {
    return json({ message: "Unauthorized" }, 401);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const apns = loadApnsConfig();
  const outboxResult = await drainOutbox(admin, apns);
  const digestResult = await flushDigests(admin, apns);

  return json({
    apnsConfigured: apns != null,
    outbox: outboxResult,
    digests: digestResult,
  });
});

async function drainOutbox(
  admin: ReturnType<typeof createClient>,
  apns: ReturnType<typeof loadApnsConfig>,
) {
  const { data: rows, error } = await admin
    .from("push_outbox")
    .select("id, user_id, token, environment, title, body, deep_link, attempts")
    .is("sent_at", null)
    .lte("send_after", new Date().toISOString())
    .lt("attempts", 5)
    .order("created_at", { ascending: true })
    .limit(100);

  if (error) return { error: error.message, sent: 0, failed: 0 };
  const pending = (rows ?? []) as OutboxRow[];
  let sent = 0;
  let failed = 0;

  for (const row of pending) {
    if (!apns) {
      await admin.from("push_outbox").update({
        attempts: row.attempts + 1,
        last_error: "apns_not_configured",
        send_after: new Date(Date.now() + 15 * 60_000).toISOString(),
      }).eq("id", row.id);
      failed += 1;
      continue;
    }

    const result = await sendApnsAlert(apns, {
      token: row.token,
      environment: row.environment,
      title: row.title,
      body: row.body,
      deepLink: row.deep_link,
    });

    if (result.ok) {
      await admin.from("push_outbox").update({
        sent_at: new Date().toISOString(),
        attempts: row.attempts + 1,
        last_error: null,
      }).eq("id", row.id);
      sent += 1;
      continue;
    }

    if (result.shouldInvalidateToken) {
      await admin.from("device_push_tokens").delete().eq("token", row.token);
      await admin.from("push_outbox").update({
        attempts: row.attempts + 1,
        last_error: result.reason ?? `http_${result.status}`,
        sent_at: new Date().toISOString(),
      }).eq("id", row.id);
    } else {
      await admin.from("push_outbox").update({
        attempts: row.attempts + 1,
        last_error: result.reason ?? `http_${result.status}`,
        send_after: new Date(Date.now() + Math.min(60, 2 ** row.attempts) * 60_000).toISOString(),
      }).eq("id", row.id);
    }
    failed += 1;
  }

  return { sent, failed, scanned: pending.length };
}

async function flushDigests(
  admin: ReturnType<typeof createClient>,
  apns: ReturnType<typeof loadApnsConfig>,
) {
  const { data: events, error } = await admin
    .from("push_digest_events")
    .select("id, user_id, group_id, actor_name, group_name, created_at")
    .is("digested_at", null)
    .order("created_at", { ascending: true })
    .limit(500);

  if (error) return { error: error.message, sent: 0 };
  const pending = (events ?? []) as DigestRow[];
  if (pending.length === 0) return { sent: 0, users: 0 };

  const byUser = new Map<string, DigestRow[]>();
  for (const event of pending) {
    const list = byUser.get(event.user_id) ?? [];
    list.push(event);
    byUser.set(event.user_id, list);
  }

  const userIDs = [...byUser.keys()];
  const [{ data: profiles }, { data: preferences }, { data: tokens }] = await Promise.all([
    admin.from("profiles").select("id, timezone_identifier").in("id", userIDs),
    admin.from("notification_preferences").select("*").in("user_id", userIDs),
    admin.from("device_push_tokens").select("user_id, token, environment").in("user_id", userIDs),
  ]);

  const profileByUser = new Map((profiles ?? []).map((row) => [row.id, row]));
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

  let sent = 0;
  let usersReady = 0;

  for (const [userID, userEvents] of byUser) {
    const globalPref = (prefsByUser.get(userID) ?? []).find((row) => row.group_id == null) ?? {
      quiet_hours_end: 7 * 60,
      friend_activity_mode: "digest",
    };
    if (globalPref.friend_activity_mode === "off") {
      await markDigested(admin, userEvents.map((event) => event.id));
      continue;
    }

    const timezone = profileByUser.get(userID)?.timezone_identifier ?? "UTC";
    const localMinutes = localMinutesNow(timezone);
    const quietEnd = Number(globalPref.quiet_hours_end ?? 7 * 60);
    const inDigestWindow = isDigestWindow(localMinutes, quietEnd);
    const oldestAgeMs = Date.now() - new Date(userEvents[0]!.created_at).getTime();
    const forceFlush = oldestAgeMs > 20 * 60 * 60 * 1000;
    if (!inDigestWindow && !forceFlush) continue;

    usersReady += 1;
    const groupNames = [...new Set(userEvents.map((event) => event.group_name))];
    const actorNames = [...new Set(userEvents.map((event) => event.actor_name))];
    const title = groupNames.length === 1 ? groupNames[0]! : "Cahoots";
    const body = digestBody(actorNames, groupNames, userEvents.length);
    const deepLink = `cahoots://log/${userEvents[0]!.group_id}`;

    const userTokens = tokensByUser.get(userID) ?? [];
    if (userTokens.length === 0 || !apns) {
      await markDigested(admin, userEvents.map((event) => event.id));
      continue;
    }

    let anySent = false;
    for (const tokenRow of userTokens) {
      if (apns) {
        const result = await sendApnsAlert(apns, {
          token: tokenRow.token,
          environment: tokenRow.environment === "production" ? "production" : "sandbox",
          title,
          body,
          deepLink,
        });
        if (result.ok) {
          anySent = true;
          sent += 1;
        } else if (result.shouldInvalidateToken) {
          await admin.from("device_push_tokens").delete().eq("token", tokenRow.token);
        } else {
          await admin.from("push_outbox").insert({
            user_id: userID,
            token: tokenRow.token,
            environment: tokenRow.environment === "production" ? "production" : "sandbox",
            title,
            body,
            deep_link: deepLink,
          });
        }
      }
    }

    if (anySent || userTokens.length > 0) {
      await markDigested(admin, userEvents.map((event) => event.id));
    }
  }

  return { sent, users: usersReady };
}

async function markDigested(admin: ReturnType<typeof createClient>, ids: string[]) {
  if (ids.length === 0) return;
  await admin.from("push_digest_events").update({
    digested_at: new Date().toISOString(),
  }).in("id", ids);
}

function digestBody(actorNames: string[], groupNames: string[], count: number): string {
  if (count === 1) {
    return `${actorNames[0] ?? "A member"} posted in ${groupNames[0] ?? "your group"}.`;
  }
  if (groupNames.length === 1) {
    return `${count} friends posted in ${groupNames[0]}.`;
  }
  return `${count} friend posts across ${groupNames.length} groups.`;
}

function localMinutesNow(timeZone: string): number {
  try {
    const parts = new Intl.DateTimeFormat("en-GB", {
      timeZone,
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    }).formatToParts(new Date());
    const hour = Number(parts.find((part) => part.type === "hour")?.value ?? "0");
    const minute = Number(parts.find((part) => part.type === "minute")?.value ?? "0");
    return hour * 60 + minute;
  } catch {
    const now = new Date();
    return now.getUTCHours() * 60 + now.getUTCMinutes();
  }
}

/** Digest fires in a 45-minute window starting at quiet-hours end (local). */
function isDigestWindow(localMinutes: number, quietEnd: number): boolean {
  const start = ((quietEnd % (24 * 60)) + 24 * 60) % (24 * 60);
  const end = (start + 45) % (24 * 60);
  if (start <= end) return localMinutes >= start && localMinutes < end;
  return localMinutes >= start || localMinutes < end;
}
