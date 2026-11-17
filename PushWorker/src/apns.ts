import { base64Decode, base64UrlEncode, encodeUtf8 } from "./encoding";
import { type AlertDevice, alertPayload, type NewMail, type Target } from "./new-mail";

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
  /** The .p8 auth key, a PKCS #8 PEM. It signs for every app of the team, so the topic is each send's own. */
  privateKey: string;
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
  /** The paired Apple Watch's own token, for an alert the iPhone doesn't confirm (ADR-023). Same environment. */
  watchToken?: string;
}

/** `delivered`, `gone` (the token should be removed) or `failed` (anything else; keep the token). */
export type PushOutcome = "delivered" | "gone" | "failed";

/** Where an alert goes: the device's app, or its paired watch's app (ADR-023). */
export interface Recipient {
  token: string;
  environment: ApnsEnvironment;
  topic: string;
  device: AlertDevice;
}

/**
 * Sends the alert for `mail` (`alertPayload`), named `alert` and collapsed under it, so the copy a watch gets when the
 * iPhone is silent replaces nothing and shows once: the only way the relay reaches a device, so every alert carries a
 * real email's sender and subject.
 */
export async function sendAlert(
  signer: ApnsSigner,
  recipient: Recipient,
  mail: NewMail,
  target: Target,
  alert: string,
): Promise<PushOutcome> {
  const response = await fetch(`${APNS_ORIGINS[recipient.environment]}/3/device/${recipient.token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await signer.token()}`,
      "apns-push-type": "alert",
      "apns-topic": recipient.topic,
      "apns-priority": "10",
      "apns-collapse-id": alert,
      "content-type": "application/json",
    },
    body: JSON.stringify(alertPayload(mail, target, alert, recipient.device)),
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
