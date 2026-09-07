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
    const challengeID = body.challengeID ?? body.challenge_id;
    const requirementDate = body.requirementDate ?? body.requirement_date;
    const clipID = body.clipID ?? body.clip_id ?? crypto.randomUUID();
    let groupID = body.groupID ?? body.group_id;

    if (!challengeID || !requirementDate) {
      return json({ message: "challengeID and requirementDate are required" }, 422);
    }

    const { data: challenge, error: challengeError } = await client
      .from("challenges")
      .select("id, group_id, status")
      .eq("id", challengeID)
      .maybeSingle();
    if (challengeError || !challenge) return json({ message: "Challenge not found" }, 404);
    groupID = challenge.group_id;
    if (!["active", "completed"].includes(challenge.status)) {
      return json({ message: "Challenge is not accepting uploads" }, 422);
    }

    const dateToken = String(requirementDate).slice(0, 10);
    const storagePath = `${groupID}/${challengeID}/${dateToken}/${userData.user.id}/${clipID}.mov`;

    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!serviceKey) return json({ message: "Server misconfigured" }, 500);
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey);

    const { data: signed, error: signError } = await admin.storage
      .from("workout-proofs")
      .createSignedUploadUrl(storagePath);
    if (signError || !signed) {
      return json({ message: signError?.message ?? "Could not create upload URL" }, 422);
    }

    return json({
      storagePath,
      uploadURL: signed.signedUrl,
      token: signed.token,
      clipID,
      groupID,
    });
  } catch (error) {
    return json({ message: error instanceof Error ? error.message : "Unexpected error" }, 500);
  }
});
