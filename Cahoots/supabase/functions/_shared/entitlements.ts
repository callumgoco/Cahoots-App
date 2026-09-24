import { compactVerify, decodeProtectedHeader, importX509 } from "jsr:@panva/jose@6.2.12";
import * as x509 from "npm:@peculiar/x509@1.12.3";

export const PLUS_PRODUCT_IDS = new Set([
  "cahoots_plus_monthly",
  "cahoots_plus_annual",
]);

/** Apple Root CA - G3 (https://www.apple.com/certificateauthority/AppleRootCA-G3.cer). */
const APPLE_ROOT_CA_G3_PEM = `-----BEGIN CERTIFICATE-----
MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwS
QXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9u
IEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcN
MTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBS
b290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9y
aXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49
AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtf
TjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517
IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySr
MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gA
MGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4
at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM
6BgD56KyKA==
-----END CERTIFICATE-----`;

function pemFromDerBase64(derBase64: string): string {
  const body = derBase64.replace(/\s+/g, "").match(/.{1,64}/g)?.join("\n") ?? derBase64;
  return `-----BEGIN CERTIFICATE-----\n${body}\n-----END CERTIFICATE-----`;
}

function bytesEqual(a: ArrayBuffer, b: ArrayBuffer): boolean {
  if (a.byteLength !== b.byteLength) return false;
  const aa = new Uint8Array(a);
  const bb = new Uint8Array(b);
  let diff = 0;
  for (let i = 0; i < aa.length; i++) diff |= aa[i]! ^ bb[i]!;
  return diff === 0;
}

/** Require APPLE_BUNDLE_ID so forged payloads cannot skip the bundle check. */
export function requireAppleBundleID(): string {
  const id = Deno.env.get("APPLE_BUNDLE_ID")?.trim();
  if (!id) throw new Error("apple_bundle_id_missing");
  return id;
}

/**
 * Verify an Apple-issued JWS (StoreKit transaction or ASN V2 payload) against
 * the embedded x5c chain rooted at Apple Root CA - G3, then return the payload.
 */
export async function verifyAndDecodeAppleJWS(jws: string): Promise<Record<string, unknown>> {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new Error("invalid_jws");

  let header: ReturnType<typeof decodeProtectedHeader>;
  try {
    header = decodeProtectedHeader(jws);
  } catch {
    throw new Error("invalid_jws");
  }

  const x5c = header.x5c;
  if (!Array.isArray(x5c) || x5c.length < 1) throw new Error("jws_missing_x5c");
  if (header.alg !== "ES256") throw new Error("jws_unsupported_alg");

  const appleRoot = new x509.X509Certificate(APPLE_ROOT_CA_G3_PEM);
  const chain = x5c.map((der) => new x509.X509Certificate(pemFromDerBase64(String(der))));

  // Ensure the chain terminates at the pinned Apple Root CA - G3.
  const last = chain[chain.length - 1]!;
  const rooted =
    bytesEqual(last.rawData, appleRoot.rawData)
      ? chain
      : [...chain, appleRoot];

  if (!bytesEqual(rooted[rooted.length - 1]!.rawData, appleRoot.rawData)) {
    throw new Error("jws_untrusted_root");
  }

  const now = new Date();
  for (let i = 0; i < rooted.length - 1; i++) {
    const subject = rooted[i]!;
    const issuer = rooted[i + 1]!;
    if (subject.notBefore > now || subject.notAfter < now) {
      throw new Error("jws_cert_expired");
    }
    const ok = await subject.verify({ publicKey: await issuer.publicKey }, crypto);
    if (!ok) throw new Error("jws_invalid_chain");
  }

  try {
    const leafKey = await importX509(pemFromDerBase64(String(x5c[0])), "ES256");
    const { payload } = await compactVerify(jws, leafKey);
    const text = new TextDecoder().decode(payload);
    return JSON.parse(text) as Record<string, unknown>;
  } catch (error) {
    if (error instanceof Error && error.message.startsWith("jws_")) throw error;
    throw new Error("jws_signature_invalid");
  }
}

export function entitlementFromTransaction(tx: Record<string, unknown>, bundleID: string) {
  if (!bundleID) throw new Error("apple_bundle_id_missing");
  if (!tx.bundleId || String(tx.bundleId) !== bundleID) {
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
