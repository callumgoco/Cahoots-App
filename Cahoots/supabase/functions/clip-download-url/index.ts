import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";

const SIGNED_URL_TTL_SECONDS = 120;

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

    const { error: limitError } = await client.rpc("consume_rate_limit", {
      action_input: "clip_download_url",
      max_hits: 60,
      window_seconds: 60,
    });
    if (limitError) return json({ message: "rate_limited" }, 429);

    const body = await request.json();
    const clipID = body.clipID ?? body.clip_id;
    const storagePathInput = body.storagePath ?? body.storage_path;

    let clipQuery = client.from("workout_clips").select("id, submission_id, storage_path");
    if (clipID) {
      clipQuery = clipQuery.eq("id", clipID);
    } else if (storagePathInput) {
      clipQuery = clipQuery.eq("storage_path", storagePathInput);
    } else {
      return json({ message: "clipID or storagePath is required" }, 422);
    }

    const { data: clip, error: clipError } = await clipQuery.maybeSingle();
    if (clipError || !clip) return json({ message: "Clip not found" }, 404);

    const { data: canReveal, error: revealError } = await client.rpc("can_reveal_submission_id", {
      submission_id_input: clip.submission_id,
    });
    if (revealError) return json({ message: revealError.message }, 422);
    if (canReveal !== true) return json({ message: "Clip is not available yet" }, 403);

    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!serviceKey) return json({ message: "Server misconfigured" }, 500);
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey);

    const { data: signed, error: signError } = await admin.storage
      .from("workout-proofs")
      .createSignedUrl(clip.storage_path, SIGNED_URL_TTL_SECONDS);
    if (signError || !signed?.signedUrl) {
      return json({ message: signError?.message ?? "Could not create download URL" }, 422);
    }

    return json({
      downloadURL: signed.signedUrl,
      storagePath: clip.storage_path,
      clipID: clip.id,
      expiresIn: SIGNED_URL_TTL_SECONDS,
    });
  } catch (error) {
    return json({ message: error instanceof Error ? error.message : "Unexpected error" }, 500);
  }
});
