export const PLUS_PRODUCT_IDS = new Set([
  "cahoots_plus_monthly",
  "cahoots_plus_annual",
]);

/** Decode the payload segment of a JWS (StoreKit transaction / ASN) without verifying the signature chain. */
export function decodeJWSPayload(jws: string): Record<string, unknown> {
  const parts = jws.split(".");
  if (parts.length < 2) throw new Error("invalid_jws");
  const padded = parts[1].replace(/-/g, "+").replace(/_/g, "/");
  const json = atob(padded.padEnd(padded.length + (4 - (padded.length % 4)) % 4, "="));
  return JSON.parse(json) as Record<string, unknown>;
}

export function entitlementFromTransaction(tx: Record<string, unknown>, bundleID: string | undefined) {
  if (bundleID && tx.bundleId && String(tx.bundleId) !== bundleID) {
    throw new Error("bundle_mismatch");
  }
  const productId = String(tx.productId ?? "");
  if (!PLUS_PRODUCT_IDS.has(productId)) {
    throw new Error("unknown_product");
  }
  const expiresMs = tx.expiresDate != null ? Number(tx.expiresDate) : null;
  const expiresAt = expiresMs && Number.isFinite(expiresMs)
    ? new Date(expiresMs).toISOString()
    : null;
  const revoked = tx.revocationDate != null;
  const expired = expiresAt ? new Date(expiresAt).getTime() <= Date.now() : false;
  const isPlus = !revoked && !expired;
  return {
    entitlement: isPlus ? "plus" : "free",
    plus_expires_at: isPlus ? expiresAt : null,
    plus_original_transaction_id: String(tx.originalTransactionId ?? tx.transactionId ?? ""),
    productId,
  };
}

export type AdminClient = {
  from: (table: string) => {
    update: (values: Record<string, unknown>) => {
      eq: (column: string, value: string) => Promise<{ error: { message: string } | null }>;
    };
    select: (columns: string) => {
      eq: (column: string, value: string) => {
        maybeSingle: () => Promise<{ data: Record<string, unknown> | null; error: { message: string } | null }>;
        limit: (n: number) => Promise<{ data: Record<string, unknown>[] | null; error: { message: string } | null }>;
      };
    };
  };
};

export async function applyEntitlementToUser(
  admin: AdminClient,
  userID: string,
  fields: {
    entitlement: string;
    plus_expires_at: string | null;
    plus_original_transaction_id: string;
  },
) {
  const { error } = await admin.from("profiles").update({
    entitlement: fields.entitlement,
    plus_expires_at: fields.plus_expires_at,
    plus_original_transaction_id: fields.plus_original_transaction_id || null,
    entitlement_updated_at: new Date().toISOString(),
  }).eq("id", userID);
  if (error) throw new Error(error.message);
}

export async function applyEntitlementByOriginalTransaction(
  admin: AdminClient,
  fields: {
    entitlement: string;
    plus_expires_at: string | null;
    plus_original_transaction_id: string;
  },
) {
  const txn = fields.plus_original_transaction_id;
  if (!txn) throw new Error("missing_transaction");
  const { data, error } = await admin
    .from("profiles")
    .select("id")
    .eq("plus_original_transaction_id", txn)
    .limit(1);
  if (error) throw new Error(error.message);
  const row = data?.[0];
  if (!row?.id) return false;
  await applyEntitlementToUser(admin, String(row.id), fields);
  return true;
}
