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
    const proposalID = body.proposal_id ?? body.proposalID;
    const choice = body.choice ?? body.selected_choice;
    if (!proposalID || typeof proposalID !== "string") {
      return json({ message: "proposal_id is required" }, 422);
    }
    if (choice !== "yes" && choice !== "no") {
      return json({ message: "choice must be yes or no" }, 422);
    }

    const { data, error } = await client.rpc("cast_vote", {
      proposal_id_input: proposalID,
      selected_choice: choice,
    });
    if (error) return json({ message: error.message }, 422);
    return json({ status: data });
  } catch (error) {
    return json({ message: error instanceof Error ? error.message : "Unexpected error" }, 500);
  }
});
