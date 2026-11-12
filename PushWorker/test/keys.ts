import { base64UrlEncode } from "../src/encoding";

/** A stand-in for one of Google's RS256 signing keys. */
export interface TestGoogleKey {
  kid: string;
  privateKey: CryptoKey;
  jwk: JsonWebKey & { kid: string };
}

export async function generateGoogleKey(kid: string): Promise<TestGoogleKey> {
  const pair = (await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  )) as CryptoKeyPair;
  const jwk = (await crypto.subtle.exportKey("jwk", pair.publicKey)) as JsonWebKey;
  return { kid, privateKey: pair.privateKey, jwk: { ...jwk, kid, alg: "RS256", use: "sig" } };
}

export function jwksResponse(keys: TestGoogleKey[], maxAge = 3600): Response {
  return Response.json(
    { keys: keys.map((key) => key.jwk) },
    { headers: { "cache-control": `public, max-age=${maxAge}, must-revalidate` } },
  );
}

export async function signGoogleToken(key: TestGoogleKey, claims: Record<string, unknown>): Promise<string> {
  const header = base64UrlEncode(JSON.stringify({ alg: "RS256", kid: key.kid, typ: "JWT" }));
  const payload = base64UrlEncode(JSON.stringify(claims));
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key.privateKey,
    new TextEncoder().encode(`${header}.${payload}`),
  );
  return `${header}.${payload}.${base64UrlEncode(signature)}`;
}

/** Claims shaped like a Google ID token for `email`, valid for an hour from `now` (seconds). */
export function idTokenClaims(email: string, audience: string, now: number): Record<string, unknown> {
  return {
    iss: "https://accounts.google.com",
    aud: audience,
    azp: audience,
    sub: "1234567890",
    email,
    email_verified: true,
    iat: now,
    exp: now + 3600,
  };
}

/** A P-256 key like an APNs .p8 auth key: the PEM the Worker gets as a secret, and the public half to verify with. */
export async function generateApnsKey(): Promise<{ pem: string; publicKey: CryptoKey }> {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, [
    "sign",
    "verify",
  ])) as CryptoKeyPair;
  const pkcs8 = (await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer;
  const base64 = btoa(String.fromCharCode(...new Uint8Array(pkcs8)));
  const lines = base64.match(/.{1,64}/g) ?? [];
  return { pem: `-----BEGIN PRIVATE KEY-----\n${lines.join("\n")}\n-----END PRIVATE KEY-----\n`, publicKey: pair.publicKey };
}
