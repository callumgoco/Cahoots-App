/** APNs provider-token (JWT) + send helpers for Edge Functions. */

const TOKEN_MAX_AGE_MS = 50 * 60 * 1000;

type ApnsConfig = {
  keyId: string;
  teamId: string;
  bundleId: string;
  keyP8: string;
};

let cached: { token: string; issuedAtMs: number } | null = null;
let keyPromise: Promise<CryptoKey> | null = null;

function base64UrlEncode(bytes: ArrayBuffer | Uint8Array): string {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let binary = "";
  for (let i = 0; i < view.length; i++) binary += String.fromCharCode(view[i]!);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function base64UrlEncodeJson(value: unknown): string {
  return base64UrlEncode(new TextEncoder().encode(JSON.stringify(value)));
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const cleaned = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\\n/g, "\n")
    .replace(/\s+/g, "");
  const binary = atob(cleaned);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

async function importApnsKey(keyP8: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(keyP8),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

async function signApnsJwt(key: CryptoKey, config: ApnsConfig, issuedAtMs: number): Promise<string> {
  const header = base64UrlEncodeJson({ alg: "ES256", kid: config.keyId });
  const claims = base64UrlEncodeJson({
    iss: config.teamId,
    iat: Math.floor(issuedAtMs / 1000),
  });
  const signingInput = `${header}.${claims}`;
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: { name: "SHA-256" } },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64UrlEncode(signature)}`;
}

export function loadApnsConfig(): ApnsConfig | null {
  const keyId = Deno.env.get("APNS_KEY_ID")?.trim();
  const teamId = Deno.env.get("APNS_TEAM_ID")?.trim();
  const bundleId = Deno.env.get("APNS_BUNDLE_ID")?.trim() ?? "com.callumoconnor.cahoots";
  const keyP8 = Deno.env.get("APNS_PRIVATE_KEY")?.trim();
  if (!keyId || !teamId || !keyP8) return null;
  return { keyId, teamId, bundleId, keyP8 };
}

export async function getApnsProviderToken(config: ApnsConfig, now = Date.now()): Promise<string> {
  if (cached && now - cached.issuedAtMs < TOKEN_MAX_AGE_MS && now >= cached.issuedAtMs) {
    return cached.token;
  }
  if (!keyPromise) {
    keyPromise = importApnsKey(config.keyP8).catch((error) => {
      keyPromise = null;
      throw error;
    });
  }
  const key = await keyPromise;
  const token = await signApnsJwt(key, config, now);
  cached = { token, issuedAtMs: now };
  return token;
}

export type PushPayload = {
  token: string;
  environment: "sandbox" | "production";
  title: string;
  body: string;
  deepLink?: string | null;
};

export type PushSendResult = {
  ok: boolean;
  status: number;
  reason?: string;
  shouldInvalidateToken?: boolean;
};

export async function sendApnsAlert(
  config: ApnsConfig,
  payload: PushPayload,
): Promise<PushSendResult> {
  const providerToken = await getApnsProviderToken(config);
  const host = payload.environment === "production"
    ? "api.push.apple.com"
    : "api.development.push.apple.com";
  const response = await fetch(`https://${host}/3/device/${payload.token}`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${providerToken}`,
      "apns-topic": config.bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      aps: {
        alert: {
          title: payload.title,
          body: payload.body,
        },
        sound: "default",
      },
      deepLink: payload.deepLink ?? undefined,
    }),
  });

  if (response.ok) return { ok: true, status: response.status };

  let reason: string | undefined;
  try {
    const json = await response.json() as { reason?: string };
    reason = json.reason;
  } catch {
    reason = await response.text();
  }

  const shouldInvalidateToken = response.status === 410 ||
    reason === "BadDeviceToken" ||
    reason === "Unregistered";

  return { ok: false, status: response.status, reason, shouldInvalidateToken };
}
