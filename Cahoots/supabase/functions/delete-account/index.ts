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

    // delete_my_account removes the profile, the groups this account owned and the auth user
    // in a single transaction. Splitting that across an RPC and an admin deleteUser call is
    // what used to strand half-deleted accounts when the second step failed.
    const { error: rpcError } = await client.rpc("delete_my_account");
    if (rpcError) return json({ message: rpcError.message }, 422);

    return json({ ok: true });
  } catch (error) {
    return json({ message: error instanceof Error ? error.message : "Unexpected error" }, 500);
  }
});
