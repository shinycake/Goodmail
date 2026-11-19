import { APP_ATTESTATION_ROOT } from "./apple-root";
import { AttestationRejected, concat, sha256, verifyAssertion, verifyAttestation } from "./app-attest";
import { CborError } from "./cbor";
import { DerError } from "./der";
import { base64Decode, encodeUtf8 } from "./encoding";
import type { Env } from "./env";
import { BadRequest, readJson } from "./shared";
import { type Certificate, pemCertificate } from "./x509";

/**
 * Keeps the relay to the genuine app. The source was public once, so anyone could build it and point it here; only a build
 * signed by the owner's team can attest a key (app-attest.ts), and every request from the app is signed with one.
 *
 * The app attests once per install: `POST /v1/attest/challenges` for a challenge, then `POST /v1/attest/keys` with
 * the key ID, the attestation and the challenge. After that each request to a device route carries three headers:
 * the key ID, the request time, and an assertion over `SHA-256("<method> <path>\n<time>\n" || body)`. The time
 * bounds a replay to `MAX_SKEW_MS`, and a replayed request can only repeat what the genuine app already asked for.
 */

export const KEY_HEADER = "x-goodmail-attest-key";
export const TIME_HEADER = "x-goodmail-attest-time";
export const ASSERTION_HEADER = "x-goodmail-attest-assertion";

const CHALLENGE_LIFETIME_MS = 5 * 60_000;
const MAX_SKEW_MS = 10 * 60_000;
/** A key unused this long belongs to an install that's gone; the app attests again if it ever comes back. */
const KEY_LIFETIME_MS = 180 * 24 * 60 * 60_000;
const KEY_ID = /^[A-Za-z0-9+/]{43}=$/;
const CHALLENGE = /^[A-Za-z0-9_-]{43}$/;
const TIME = /^\d{13}$/;

/** What `APP_ATTEST` in wrangler.toml asks: watch and log only, or refuse requests the genuine app didn't sign. */
export type AttestMode = "observe" | "enforce";

/** What a request proved about where it came from. */
export type DeviceProof =
  | { kind: "attested" }
  /** No key, or one the relay doesn't know (reinstalled app, purged key): the app should attest again. */
  | { kind: "unattested"; reason: "noKey" | "unknownKey" }
  | { kind: "rejected"; reason: string };

let appleRoot: Certificate | undefined;

/** `POST /v1/attest/challenges`: a one-time challenge for an attestation. */
export async function issueChallenge(request: Request, env: Env, now: number): Promise<Response> {
  const client = request.headers.get("cf-connecting-ip") ?? "unknown";
  if (!(await env.ATTEST_CHALLENGES.limit({ key: client })).success) return new Response(null, { status: 429 });
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  const challenge = btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  await env.DB.batch([
    env.DB.prepare("DELETE FROM attest_challenges WHERE expires_at < ?1").bind(now),
    env.DB.prepare("DELETE FROM attest_keys WHERE last_used_at < ?1").bind(now - KEY_LIFETIME_MS),
    env.DB.prepare("INSERT INTO attest_challenges (challenge, expires_at) VALUES (?1, ?2)").bind(
      challenge,
      now + CHALLENGE_LIFETIME_MS,
    ),
  ]);
  return Response.json({ challenge });
}

/** `POST /v1/attest/keys`: checks an attestation and keeps its key. 401 when Apple's chain doesn't vouch for it. */
export async function registerKey(
  request: Request,
  env: Env,
  now: number,
  root: Certificate = (appleRoot ??= pemCertificate(APP_ATTESTATION_ROOT)),
): Promise<Response> {
  const { keyId, attestation, challenge } = await readJson(request);
  if (typeof keyId !== "string" || !KEY_ID.test(keyId)) throw new BadRequest("bad keyId");
  if (typeof challenge !== "string" || !CHALLENGE.test(challenge)) throw new BadRequest("bad challenge");
  if (typeof attestation !== "string" || attestation.length > 16_384) throw new BadRequest("bad attestation");
  // One use only, and only while fresh.
  const issued = await env.DB.prepare("DELETE FROM attest_challenges WHERE challenge = ?1 RETURNING expires_at")
    .bind(challenge)
    .first<{ expires_at: number }>();
  if (!issued || issued.expires_at < now) return new Response(null, { status: 401 });
  try {
    const key = await verifyAttestation({
      attestation: base64Decode(attestation),
      keyId: base64Decode(keyId),
      challenge: encodeUtf8(challenge),
      appId: appId(env),
      root,
      now,
    });
    await env.DB.prepare(
      `INSERT INTO attest_keys (key_id, public_key, environment, counter, created_at, last_used_at)
       VALUES (?1, ?2, ?3, 0, ?4, ?4)
       ON CONFLICT (key_id) DO UPDATE SET last_used_at = excluded.last_used_at`,
    )
      .bind(keyId, key.publicKey, key.environment, now)
      .run();
    return new Response(null, { status: 204 });
  } catch (error) {
    if (!isMalformed(error)) throw error;
    console.warn(`App Attest: attestation refused: ${(error as Error).message}`);
    return new Response(null, { status: 401 });
  }
}

/**
 * Checks a device route's request. Returns the response to send instead when `APP_ATTEST` is `enforce` and the
 * request isn't the genuine app's: 428 asks the app to attest again, 401 refuses it. In `observe` it only logs.
 * The body is read here, so the route gets a copy.
 */
export async function guardDevice(
  request: Request,
  env: Env,
  now: number,
): Promise<{ request: Request } | { refusal: Response }> {
  const body = new Uint8Array(await request.arrayBuffer());
  const proof = await proveDevice(request, body, env, now);
  const copy = new Request(request, { body });
  if (proof.kind !== "attested") console.warn(`App Attest: ${proof.kind}, ${proof.reason}`);
  if (attestMode(env) === "observe") return { request: copy };
  switch (proof.kind) {
    case "attested":
      return { request: copy };
    case "unattested":
      return { refusal: new Response(null, { status: 428 }) };
    case "rejected":
      return { refusal: new Response(null, { status: 401 }) };
  }
}

export async function proveDevice(
  request: Request,
  body: Uint8Array<ArrayBuffer>,
  env: Env,
  now: number,
): Promise<DeviceProof> {
  const keyId = request.headers.get(KEY_HEADER);
  const time = request.headers.get(TIME_HEADER);
  const assertion = request.headers.get(ASSERTION_HEADER);
  if (keyId === null || time === null || assertion === null) return { kind: "unattested", reason: "noKey" };
  if (!KEY_ID.test(keyId) || !TIME.test(time)) return { kind: "rejected", reason: "malformed headers" };
  if (Math.abs(now - Number(time)) > MAX_SKEW_MS) return { kind: "rejected", reason: "stale request" };
  const key = await env.DB.prepare("SELECT public_key, counter FROM attest_keys WHERE key_id = ?1")
    .bind(keyId)
    .first<{ public_key: ArrayBuffer; counter: number }>();
  if (!key) return { kind: "unattested", reason: "unknownKey" };
  const path = new URL(request.url).pathname;
  try {
    const counter = await verifyAssertion({
      assertion: base64Decode(assertion),
      clientDataHash: await sha256(concat(encodeUtf8(`${request.method} ${path}\n${time}\n`), body)),
      publicKey: new Uint8Array(key.public_key),
      appId: appId(env),
    });
    await env.DB.prepare("UPDATE attest_keys SET counter = MAX(counter, ?2), last_used_at = ?3 WHERE key_id = ?1")
      .bind(keyId, counter, now)
      .run();
    return { kind: "attested" };
  } catch (error) {
    if (!isMalformed(error)) throw error;
    return { kind: "rejected", reason: (error as Error).message };
  }
}

/** Anything but an explicit `observe` enforces, so a typo can't open the relay. */
function attestMode(env: Env): AttestMode {
  return env.APP_ATTEST === "observe" ? "observe" : "enforce";
}

/** The App ID App Attest binds keys to: team ID, a dot, bundle ID (the APNs topic is the app's bundle ID). */
function appId(env: Env): string {
  return `${env.APNS_TEAM_ID}.${env.APNS_TOPIC}`;
}

/** Errors that mean the client sent something false or garbled, as opposed to the relay failing. */
function isMalformed(error: unknown): boolean {
  return (
    error instanceof AttestationRejected ||
    error instanceof CborError ||
    error instanceof DerError ||
    error instanceof DOMException ||
    // atob's error in workerd.
    (error instanceof Error && error.name === "InvalidCharacterError")
  );
}
