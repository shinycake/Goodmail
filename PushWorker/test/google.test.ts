import { beforeAll, describe, expect, it } from "vitest";
import { GOOGLE_JWKS_URL, GoogleKeys, TokenError, verifyIdToken, verifyPubSubToken } from "../src/google";
import { generateGoogleKey, idTokenClaims, jwksResponse, signGoogleToken, type TestGoogleKey } from "./keys";

const CLIENT_ID = "ios-client.apps.googleusercontent.com";
const AUDIENCE = "https://push.example.test/v1/pubsub";
const SERVICE_ACCOUNT = "pubsub-invoker@goodmail-ios.iam.gserviceaccount.com";
const NOW = 1_800_000_000;

let key: TestGoogleKey;
let otherKey: TestGoogleKey;

beforeAll(async () => {
  key = await generateGoogleKey("google-key-1");
  otherKey = await generateGoogleKey("google-key-2");
});

/** A key cache over a fake JWKS endpoint that serves `served()` and counts fetches. */
function keysServing(served: () => TestGoogleKey[], clock = { ms: NOW * 1000 }) {
  const fetched: string[] = [];
  const keys = new GoogleKeys(
    () => clock.ms,
    async (url) => {
      fetched.push(url);
      return jwksResponse(served(), 600);
    },
  );
  return { keys, fetched, clock };
}

async function expectRejected(promise: Promise<unknown>, reason: string) {
  const error = await promise.then(
    () => undefined,
    (thrown: unknown) => thrown,
  );
  expect(error).toBeInstanceOf(TokenError);
  expect((error as Error).message).toBe(reason);
}

describe("ID token verification", () => {
  it("accepts a good token and returns its email", async () => {
    const { keys, fetched } = keysServing(() => [key]);
    const token = await signGoogleToken(key, idTokenClaims("Someone@Gmail.com", CLIENT_ID, NOW));
    await expect(verifyIdToken(token, CLIENT_ID, keys, NOW)).resolves.toBe("Someone@Gmail.com");
    expect(fetched).toEqual([GOOGLE_JWKS_URL]);
  });

  it("accepts the issuer without a scheme, which Google also uses", async () => {
    const { keys } = keysServing(() => [key]);
    const token = await signGoogleToken(key, { ...idTokenClaims("a@gmail.com", CLIENT_ID, NOW), iss: "accounts.google.com" });
    await expect(verifyIdToken(token, CLIENT_ID, keys, NOW)).resolves.toBe("a@gmail.com");
  });

  it("rejects an expired token", async () => {
    const { keys } = keysServing(() => [key]);
    const token = await signGoogleToken(key, idTokenClaims("a@gmail.com", CLIENT_ID, NOW - 7200));
    await expectRejected(verifyIdToken(token, CLIENT_ID, keys, NOW), "expired");
  });

  it("rejects a token for another client", async () => {
    const { keys } = keysServing(() => [key]);
    const token = await signGoogleToken(key, idTokenClaims("a@gmail.com", "someone-else", NOW));
    await expectRejected(verifyIdToken(token, CLIENT_ID, keys, NOW), "wrong audience");
  });

  it("rejects a token from another issuer", async () => {
    const { keys } = keysServing(() => [key]);
    const claims = { ...idTokenClaims("a@gmail.com", CLIENT_ID, NOW), iss: "https://evil.example.com" };
    await expectRejected(verifyIdToken(await signGoogleToken(key, claims), CLIENT_ID, keys, NOW), "wrong issuer");
  });

  it("rejects an unverified email", async () => {
    const { keys } = keysServing(() => [key]);
    const claims = { ...idTokenClaims("a@gmail.com", CLIENT_ID, NOW), email_verified: false };
    await expectRejected(verifyIdToken(await signGoogleToken(key, claims), CLIENT_ID, keys, NOW), "email not verified");
  });

  it("rejects a token signed by a key Google doesn't publish", async () => {
    const { keys } = keysServing(() => [key]);
    const forged = await signGoogleToken({ ...otherKey, kid: key.kid }, idTokenClaims("a@gmail.com", CLIENT_ID, NOW));
    await expectRejected(verifyIdToken(forged, CLIENT_ID, keys, NOW), "bad signature");
  });

  it("rejects a tampered payload", async () => {
    const { keys } = keysServing(() => [key]);
    const [header, , signature] = (await signGoogleToken(key, idTokenClaims("a@gmail.com", CLIENT_ID, NOW))).split(".");
    const payload = btoa(JSON.stringify(idTokenClaims("victim@gmail.com", CLIENT_ID, NOW))).replace(/=+$/, "");
    await expectRejected(verifyIdToken(`${header}.${payload}.${signature}`, CLIENT_ID, keys, NOW), "bad signature");
  });
});

describe("Pub/Sub OIDC verification", () => {
  const pubSubClaims = (overrides: Record<string, unknown> = {}) => ({
    ...idTokenClaims(SERVICE_ACCOUNT, AUDIENCE, NOW),
    ...overrides,
  });

  it("accepts a token from the configured service account", async () => {
    const { keys } = keysServing(() => [key]);
    const token = await signGoogleToken(key, pubSubClaims());
    await expect(verifyPubSubToken(token, AUDIENCE, SERVICE_ACCOUNT, keys, NOW)).resolves.toBeUndefined();
  });

  it("rejects another service account", async () => {
    const { keys } = keysServing(() => [key]);
    const token = await signGoogleToken(key, pubSubClaims({ email: "intruder@other.iam.gserviceaccount.com" }));
    await expectRejected(verifyPubSubToken(token, AUDIENCE, SERVICE_ACCOUNT, keys, NOW), "wrong service account");
  });

  it("rejects another audience", async () => {
    const { keys } = keysServing(() => [key]);
    const token = await signGoogleToken(key, pubSubClaims({ aud: "https://other.example.test/" }));
    await expectRejected(verifyPubSubToken(token, AUDIENCE, SERVICE_ACCOUNT, keys, NOW), "wrong audience");
  });

  it("rejects an expired token", async () => {
    const { keys } = keysServing(() => [key]);
    const token = await signGoogleToken(key, pubSubClaims({ exp: NOW - 120 }));
    await expectRejected(verifyPubSubToken(token, AUDIENCE, SERVICE_ACCOUNT, keys, NOW), "expired");
  });

  it("rejects another issuer", async () => {
    const { keys } = keysServing(() => [key]);
    const token = await signGoogleToken(key, pubSubClaims({ iss: "https://sts.example.com" }));
    await expectRejected(verifyPubSubToken(token, AUDIENCE, SERVICE_ACCOUNT, keys, NOW), "wrong issuer");
  });
});

describe("JWKS cache", () => {
  it("fetches once while the keys are fresh, then again after max-age", async () => {
    const { keys, fetched, clock } = keysServing(() => [key]);
    const token = await signGoogleToken(key, idTokenClaims("a@gmail.com", CLIENT_ID, NOW));
    await verifyIdToken(token, CLIENT_ID, keys, NOW);
    await verifyIdToken(token, CLIENT_ID, keys, NOW);
    expect(fetched).toHaveLength(1);
    clock.ms += 601_000;
    await verifyIdToken(token, CLIENT_ID, keys, NOW);
    expect(fetched).toHaveLength(2);
  });

  it("refetches when Google rotates in a key it hasn't seen", async () => {
    let served = [key];
    const { keys, fetched, clock } = keysServing(() => served);
    await verifyIdToken(await signGoogleToken(key, idTokenClaims("a@gmail.com", CLIENT_ID, NOW)), CLIENT_ID, keys, NOW);
    served = [key, otherKey];
    clock.ms += 31_000;
    const rotated = await signGoogleToken(otherKey, idTokenClaims("a@gmail.com", CLIENT_ID, NOW));
    await expect(verifyIdToken(rotated, CLIENT_ID, keys, NOW)).resolves.toBe("a@gmail.com");
    expect(fetched).toHaveLength(2);
  });

  it("doesn't refetch on every unknown key ID", async () => {
    const { keys, fetched } = keysServing(() => [key]);
    await verifyIdToken(await signGoogleToken(key, idTokenClaims("a@gmail.com", CLIENT_ID, NOW)), CLIENT_ID, keys, NOW);
    const unknown = await signGoogleToken(otherKey, idTokenClaims("a@gmail.com", CLIENT_ID, NOW));
    await expectRejected(verifyIdToken(unknown, CLIENT_ID, keys, NOW), "unknown signing key");
    await expectRejected(verifyIdToken(unknown, CLIENT_ID, keys, NOW), "unknown signing key");
    expect(fetched).toHaveLength(1);
  });
});
