import { base64Decode, decodeJsonSegment, encodeUtf8 } from "./encoding";

export const GOOGLE_JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs";
const GOOGLE_ISSUERS = ["https://accounts.google.com", "accounts.google.com"];
/** Allowed clock skew between Google and the Worker. */
const LEEWAY_SECONDS = 60;
const DEFAULT_MAX_AGE_SECONDS = 3600;
/** A token with an unknown `kid` triggers a refetch (Google rotated keys), at most this often. */
const MIN_REFETCH_MS = 30_000;

export class TokenError extends Error {}

export interface GoogleClaims {
  iss: string;
  aud: string;
  sub: string;
  exp: number;
  iat: number;
  email?: string;
  email_verified?: boolean | string;
}

/** Google's signing keys, cached for as long as the JWKS response's `Cache-Control: max-age` allows. */
export class GoogleKeys {
  private keys = new Map<string, CryptoKey>();
  private expiresAt = 0;
  private lastFetchAt = Number.NEGATIVE_INFINITY;
  private inFlight: Promise<void> | undefined;

  constructor(
    private readonly now: () => number = () => Date.now(),
    private readonly fetcher: (url: string) => Promise<Response> = (url) => fetch(url),
  ) {}

  async key(kid: string): Promise<CryptoKey | undefined> {
    const now = this.now();
    const stale = now >= this.expiresAt;
    const unknownKid = !this.keys.has(kid) && now - this.lastFetchAt >= MIN_REFETCH_MS;
    if (stale || unknownKid) await this.refresh();
    return this.keys.get(kid);
  }

  private refresh(): Promise<void> {
    this.inFlight ??= this.load().finally(() => (this.inFlight = undefined));
    return this.inFlight;
  }

  private async load(): Promise<void> {
    this.lastFetchAt = this.now();
    const response = await this.fetcher(GOOGLE_JWKS_URL);
    if (!response.ok) throw new Error(`JWKS fetch failed with ${response.status}`);
    const body = (await response.json()) as { keys?: JsonWebKey[] };
    const keys = new Map<string, CryptoKey>();
    for (const jwk of body.keys ?? []) {
      const kid = (jwk as { kid?: unknown }).kid;
      if (jwk.kty !== "RSA" || typeof kid !== "string") continue;
      const algorithm = { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" };
      keys.set(kid, await crypto.subtle.importKey("jwk", jwk, algorithm, false, ["verify"]));
    }
    const maxAge = /max-age=(\d+)/.exec(response.headers.get("cache-control") ?? "")?.[1];
    this.keys = keys;
    this.expiresAt = this.now() + Number(maxAge ?? DEFAULT_MAX_AGE_SECONDS) * 1000;
  }
}

interface Expectations {
  audience: string;
  nowSeconds: number;
}

/** Verifies a Google-signed RS256 JWT: signature, issuer, audience, expiry and a verified email. */
export async function verifyGoogleToken(token: string, keys: GoogleKeys, expected: Expectations): Promise<GoogleClaims> {
  const parts = token.split(".");
  if (parts.length !== 3) throw new TokenError("malformed token");
  const [headerSegment, payloadSegment, signatureSegment] = parts as [string, string, string];
  let header: { alg?: unknown; kid?: unknown };
  let claims: GoogleClaims;
  let signature: Uint8Array<ArrayBuffer>;
  try {
    header = decodeJsonSegment(headerSegment) as typeof header;
    claims = decodeJsonSegment(payloadSegment) as GoogleClaims;
    signature = base64Decode(signatureSegment);
  } catch {
    throw new TokenError("malformed token");
  }
  if (header.alg !== "RS256" || typeof header.kid !== "string") throw new TokenError("unsupported header");

  const key = await keys.key(header.kid);
  if (!key) throw new TokenError("unknown signing key");
  const signed = encodeUtf8(`${headerSegment}.${payloadSegment}`);
  if (!(await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, signature, signed))) {
    throw new TokenError("bad signature");
  }

  if (!GOOGLE_ISSUERS.includes(claims.iss)) throw new TokenError("wrong issuer");
  if (claims.aud !== expected.audience) throw new TokenError("wrong audience");
  if (typeof claims.exp !== "number" || claims.exp + LEEWAY_SECONDS < expected.nowSeconds) {
    throw new TokenError("expired");
  }
  if (typeof claims.iat === "number" && claims.iat - LEEWAY_SECONDS > expected.nowSeconds) {
    throw new TokenError("issued in the future");
  }
  if (typeof claims.email !== "string" || !(claims.email_verified === true || claims.email_verified === "true")) {
    throw new TokenError("email not verified");
  }
  return claims;
}

/** Checks the ID token the app sends at registration and returns the signed-in email address. */
export async function verifyIdToken(token: string, clientId: string, keys: GoogleKeys, nowSeconds: number): Promise<string> {
  const claims = await verifyGoogleToken(token, keys, { audience: clientId, nowSeconds });
  return claims.email as string;
}

/** Checks the OIDC token Pub/Sub attaches to each push, which must come from the configured service account. */
export async function verifyPubSubToken(
  token: string,
  audience: string,
  serviceAccount: string,
  keys: GoogleKeys,
  nowSeconds: number,
): Promise<void> {
  const claims = await verifyGoogleToken(token, keys, { audience, nowSeconds });
  if (claims.email !== serviceAccount) throw new TokenError("wrong service account");
}
