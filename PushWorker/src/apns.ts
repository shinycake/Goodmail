import { base64Decode, base64UrlEncode, encodeUtf8 } from "./encoding";

export type ApnsEnvironment = "sandbox" | "production";

export const APNS_ORIGINS: Record<ApnsEnvironment, string> = {
  sandbox: "https://api.sandbox.push.apple.com",
  production: "https://api.push.apple.com",
};

/** Apple rejects tokens older than an hour and throttles ones refreshed more often than every 20 minutes. */
const TOKEN_LIFETIME_MS = 50 * 60 * 1000;

export interface ApnsConfig {
  keyId: string;
  teamId: string;
  /** The .p8 auth key, a PKCS #8 PEM. */
  privateKey: string;
  topic: string;
}

/** Signs and caches the ES256 provider token APNs expects in `authorization: bearer`. */
export class ApnsSigner {
  private key: Promise<CryptoKey> | undefined;
  private cached: { token: string; issuedAt: number } | undefined;

  constructor(
    readonly config: ApnsConfig,
    private readonly now: () => number = () => Date.now(),
  ) {}

  async token(): Promise<string> {
    const now = this.now();
    if (this.cached && now - this.cached.issuedAt < TOKEN_LIFETIME_MS) return this.cached.token;
    this.key ??= importPrivateKey(this.config.privateKey);
    const header = base64UrlEncode(JSON.stringify({ alg: "ES256", kid: this.config.keyId }));
    const claims = base64UrlEncode(JSON.stringify({ iss: this.config.teamId, iat: Math.floor(now / 1000) }));
    const signature = await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      await this.key,
      encodeUtf8(`${header}.${claims}`),
    );
    // WebCrypto already returns the raw r‖s form that JWS uses for ES256.
    const token = `${header}.${claims}.${base64UrlEncode(signature)}`;
    this.cached = { token, issuedAt: now };
    return token;
  }
}

function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  return crypto.subtle.importKey("pkcs8", base64Decode(body), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}

export interface Device {
  token: string;
  environment: ApnsEnvironment;
}

/** `delivered`, `gone` (the token should be removed) or `failed` (anything else; keep the token). */
export type PushOutcome = "delivered" | "gone" | "failed";

/**
 * The new-mail push: a mutable alert whose NSE fetches the change for `account` from `historyId` on. The text is a
 * key in the app's string catalog, so the alert shown when the NSE can't fetch is in the reader's language.
 */
export function newMailPayload(account: string, historyId: string): object {
  return {
    aps: { alert: { "loc-key": "NEW_MAIL_PUSH" }, sound: "default", "mutable-content": 1 },
    account,
    historyId,
  };
}

/**
 * The Outlook new-mail push. Graph's notification names a subscription, which the relay knows by the app's own
 * account ID, so the NSE finds the account by that rather than by address.
 */
export function graphMailPayload(accountID: string): object {
  return {
    aps: { alert: { "loc-key": "NEW_MAIL_PUSH" }, sound: "default", "mutable-content": 1 },
    accountID,
  };
}

export async function sendPush(signer: ApnsSigner, device: Device, payload: object): Promise<PushOutcome> {
  const response = await fetch(`${APNS_ORIGINS[device.environment]}/3/device/${device.token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await signer.token()}`,
      "apns-push-type": "alert",
      "apns-topic": signer.config.topic,
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  if (response.ok) return "delivered";
  const reason = await response
    .json<{ reason?: string }>()
    .then((body) => body.reason)
    .catch(() => undefined);
  if (response.status === 410 || reason === "BadDeviceToken") return "gone";
  console.warn(`APNs ${response.status} ${reason ?? ""}`.trim());
  return "failed";
}
