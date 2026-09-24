import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";
import {
  applyEntitlementByOriginalTransaction,
  entitlementFromTransaction,
  requireAppleBundleID,
  verifyAndDecodeAppleJWS,
} from "../_shared/entitlements.ts";

/**
 * App Store Server Notifications V2 endpoint.
 * Configure ASC → Server Notifications URL to this function.
 * Verifies Apple's JWS signature chain before mutating entitlements.
 */
Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    if (request.method !== "POST") return json({ message: "Method not allowed" }, 405);

    const body = await request.json();
    const signedPayload = String(body.signedPayload ?? "");
    if (!signedPayload) return json({ message: "signedPayload is required" }, 422);

    const payload = await verifyAndDecodeAppleJWS(signedPayload);
    const data = (payload.data ?? {}) as Record<string, unknown>;
    const signedTransactionInfo = String(data.signedTransactionInfo ?? "");
    if (!signedTransactionInfo) return json({ message: "missing transaction" }, 422);

    const bundleID = requireAppleBundleID();
    const tx = await verifyAndDecodeAppleJWS(signedTransactionInfo);
    const notificationType = String(payload.notificationType ?? "");
    const subtype = String(payload.subtype ?? "");

    let fields = entitlementFromTransaction(tx, bundleID);

    // Explicit revoke / expire / refund always clears Plus even if expiry parsing is soft.
    if (
      notificationType === "EXPIRED"
      || notificationType === "REVOKE"
      || notificationType === "REFUND"
      || (notificationType === "DID_FAIL_TO_RENEW" && subtype === "GRACE_PERIOD_EXPIRED")
    ) {
      fields = {
        ...fields,
        entitlement: "free",
        plus_expires_at: null,
      };
    }

    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!serviceKey) return json({ message: "Server misconfigured" }, 500);
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey);

    const updated = await applyEntitlementByOriginalTransaction(admin, {
      entitlement: fields.entitlement,
      plus_expires_at: fields.plus_expires_at,
      plus_original_transaction_id: fields.plus_original_transaction_id,
    });

    return json({ ok: true, updated, notificationType, entitlement: fields.entitlement });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unexpected error";
    return json({ message }, 500);
  }
});
