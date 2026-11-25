import { base64Decode, decodeJsonSegment, encodeUtf8 } from "./encoding";

export const GOOGLE_JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs";
const GOOGLE_ISSUERS = ["https://accounts.google.com", "accounts.google.com"];
/** Allowed clock skew between Google and the Worker. */
const LEEWAY_SECONDS = 60;
const DEFAULT_MAX_AGE_SECONDS = 3600;
/**
 * A token with an unknown `kid` triggers a refetch (Google rotated keys), at most this often; so does a fetch that
 * failed.
 */
const MIN_REFETCH_MS = 30_000;
/** While Google can't be reached, the keys it published last are trusted for this long past their max-age. */
const MAX_STALE_MS = 86_400_000;

export class TokenError extends Error {}

/** No keys to check a token with: Google can't be reached and none it published lately are held. */
export class KeysUnavailable extends Error {}

export interface GoogleClaims {
  iss: string;
  aud: string;
  sub: string;
  exp: number;
  iat: number;
  email?: string;
  email_verified?: boolean | string;
}

/** The keys one JWKS response published: fetched at `fetchedAt`, and good until `until` by its max-age. */
interface Published {
  keys: Map<string, CryptoKey>;
  fetchedAt: number;
  until: number;
}

/**
 * Where the cache stands: no keys yet, the keys of the last fetch that worked, a fetch under way, or a fetch that
 * failed and is tried again at `retryAt`. The last two keep the keys from before (`previous`), trusted while they are
 * at most `MAX_STALE_MS` past their max-age.
 */
type KeySet =
  | { kind: "empty" }
  | { kind: "held"; published: Published }
  | { kind: "refreshing"; previous: Published | undefined; done: Promise<void> }
  | { kind: "failed"; previous: Published | undefined; retryAt: number };

/** Google's signing keys, cached for as long as the JWKS response's `Cache-Control: max-age` allows. */
export class GoogleKeys {
  private set: KeySet = { kind: "empty" };

  constructor(
    private readonly now: () => number = () => Date.now(),
    private readonly fetcher: (url: string) => Promise<Response> = (url) => fetch(url),
  ) {}

  /**
   * The key named `kid`, or undefined when Google doesn't publish it. Throws `KeysUnavailable` when the keys can't be
   * had, so a good token is never called bad because Google couldn't be reached.
   */
  async key(kid: string): Promise<CryptoKey | undefined> {
    const set = this.set;
    const now = this.now();
    switch (set.kind) {
      case "refreshing":
        await set.done;
        return this.lookup(kid);
      case "failed":
        if (now < set.retryAt) return this.lookup(kid);
        break;
      case "held": {
        const { keys, fetchedAt, until } = set.published;
        if (now < until && (keys.has(kid) || now - fetchedAt < MIN_REFETCH_MS)) return keys.get(kid);
        break;
      }
      case "empty":
        break;
    }
    await this.refresh();
    return this.lookup(kid);
  }

  /** The key as the cache stands: the last fetch's answer, or, after a failure, the keys from before while trusted. */
  private lookup(kid: string): CryptoKey | undefined {
    const set = this.set;
    if (set.kind === "held") return set.published.keys.get(kid);
    const previous = set.kind === "empty" ? undefined : set.previous;
    const key = previous && this.now() < previous.until + MAX_STALE_MS ? previous.keys.get(kid) : undefined;
    if (!key) throw new KeysUnavailable("Google's signing keys can't be fetched");
    return key;
  }

  /** Fetches the keys once however many requests ask at a time: the one place the cache moves. Never rejects. */
  private refresh(): Promise<void> {
    const set = this.set;
    if (set.kind === "refreshing") return set.done;
    const previous = set.kind === "held" ? set.published : set.kind === "failed" ? set.previous : undefined;
    const done = this.load().then(
      (published) => {
        this.set = { kind: "held", published };
      },
      (error: unknown) => {
        console.warn(`JWKS fetch failed: ${error instanceof Error ? error.message : String(error)}`);
        this.set = { kind: "failed", previous, retryAt: this.now() + MIN_REFETCH_MS };
      },
    );
    this.set = { kind: "refreshing", previous, done };
    return done;
  }

  private async load(): Promise<Published> {
    const fetchedAt = this.now();
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
    return { keys, fetchedAt, until: this.now() + Number(maxAge ?? DEFAULT_MAX_AGE_SECONDS) * 1000 };
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
