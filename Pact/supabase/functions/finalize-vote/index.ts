import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const authorization = request.headers.get("Authorization");
  if (!authorization) return json({ message: "Authentication required" }, 401);
  const client = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authorization } } },
  );
  const { proposal_id, choice } = await request.json();
  const { data, error } = await client.rpc("cast_vote", { proposal_id_input: proposal_id, selected_choice: choice });
  if (error) return json({ message: error.message }, 422);
  return json({ status: data });
});

