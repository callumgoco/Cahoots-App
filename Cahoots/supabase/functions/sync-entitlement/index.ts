import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";
import {
  applyEntitlementToUser,
  decodeJWSPayload,
  entitlementFromTransaction,
} from "../_shared/entitlements.ts";

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
    const signedTransaction = String(body.signedTransaction ?? body.signed_transaction ?? "");
    if (!signedTransaction) return json({ message: "signedTransaction is required" }, 422);

    const tx = decodeJWSPayload(signedTransaction);
    const fields = entitlementFromTransaction(tx, Deno.env.get("APPLE_BUNDLE_ID") ?? undefined);

    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!serviceKey) return json({ message: "Server misconfigured" }, 500);
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey);

    await applyEntitlementToUser(admin, userData.user.id, {
      entitlement: fields.entitlement,
      plus_expires_at: fields.plus_expires_at,
      plus_original_transaction_id: fields.plus_original_transaction_id,
    });

    const { data: profile } = await admin
      .from("profiles")
      .select("entitlement, plus_expires_at, plus_preview_until, plus_original_transaction_id, entitlement_updated_at")
      .eq("id", userData.user.id)
      .maybeSingle();

    return json({
      entitlement: profile?.entitlement ?? fields.entitlement,
      plusExpiresAt: profile?.plus_expires_at ?? fields.plus_expires_at,
      plusPreviewUntil: profile?.plus_preview_until ?? null,
      productId: fields.productId,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unexpected error";
    const status = ["invalid_jws", "bundle_mismatch", "unknown_product"].includes(message) ? 422 : 500;
    return json({ message }, status);
  }
});
