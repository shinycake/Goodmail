import { beforeAll, describe, expect, it } from "vitest";
import { AttestationRejected, concat, sha256, verifyAssertion, verifyAttestation } from "../src/app-attest";
import { encodeUtf8 } from "../src/encoding";
import {
  APP_ID,
  assert,
  attest,
  type AttestationOptions,
  type FakeApple,
  fakeApple,
  fakeKey,
  NOW,
} from "./attest-fixtures";

const CHALLENGE = encodeUtf8("a-one-time-challenge-from-the-relay-xxxxxxx");

let apple: FakeApple;

beforeAll(async () => {
  apple = await fakeApple();
});

async function verify(options: AttestationOptions = {}, overrides: { appId?: string; now?: number } = {}) {
  const key = await fakeKey();
  const attestation = await attest(apple, key, CHALLENGE, options);
  const verified = verifyAttestation({
    attestation,
    keyId: key.keyId,
    challenge: CHALLENGE,
    appId: overrides.appId ?? APP_ID,
    root: apple.root,
    now: overrides.now ?? NOW,
  });
  return { key, verified };
}

describe("attestation", () => {
  it("accepts a key Apple's chain vouches for, made for this app and challenge", async () => {
    const { key, verified } = await verify();
    expect(await verified).toEqual({ publicKey: key.publicKey, environment: "production" });
  });

  it("tells development keys from production ones", async () => {
    const { verified } = await verify({ aaguid: encodeUtf8("appattestdevelop") });
    expect((await verified).environment).toBe("development");
  });

  it.each<[string, AttestationOptions, { appId?: string; now?: number }]>([
    ["another team's build of the app", { appId: "OTHERTEAM1.com.idanbirman.goodmail" }, {}],
    ["a key that has already signed", { counter: 1 }, {}],
    ["an unknown environment", { aaguid: new Uint8Array(16) }, {}],
    ["another challenge", { nonceChallenge: encodeUtf8("someone else's challenge") }, {}],
    ["another key's ID in the authenticator data", { credentialId: new Uint8Array(32).fill(7) }, {}],
    ["certificates that have expired", {}, { now: NOW + 2 * 365 * 24 * 60 * 60_000 }],
  ])("refuses %s", async (_, options, overrides) => {
    const { verified } = await verify(options, overrides);
    await expect(verified).rejects.toBeInstanceOf(AttestationRejected);
  });

  it("refuses a leaf that a look-alike CA signed instead of Apple's", async () => {
    const impostor = await fakeApple();
    const { verified } = await verify({ issuer: impostor.intermediate });
    await expect(verified).rejects.toBeInstanceOf(AttestationRejected);
  });

  it("refuses an attestation that names another key", async () => {
    const key = await fakeKey();
    const other = await fakeKey();
    const attestation = await attest(apple, key, CHALLENGE);
    const verified = verifyAttestation({ attestation, keyId: other.keyId, challenge: CHALLENGE, appId: APP_ID, root: apple.root, now: NOW });
    await expect(verified).rejects.toBeInstanceOf(AttestationRejected);
  });
});

describe("assertion", () => {
  const request = encodeUtf8("POST /v1/devices\n1763380800000\n{}");

  it("returns the counter of a signature by the attested key", async () => {
    const key = await fakeKey();
    const clientDataHash = await sha256(request);
    await assert(key, clientDataHash);
    const assertion = await assert(key, clientDataHash);
    expect(await verifyAssertion({ assertion, clientDataHash, publicKey: key.publicKey, appId: APP_ID })).toBe(2);
  });

  it("refuses a signature over another request", async () => {
    const key = await fakeKey();
    const assertion = await assert(key, await sha256(request));
    const tampered = await sha256(concat(request, encodeUtf8(" ")));
    await expect(
      verifyAssertion({ assertion, clientDataHash: tampered, publicKey: key.publicKey, appId: APP_ID }),
    ).rejects.toBeInstanceOf(AttestationRejected);
  });

  it("refuses a signature by another key", async () => {
    const key = await fakeKey();
    const other = await fakeKey();
    const clientDataHash = await sha256(request);
    const assertion = await assert(other, clientDataHash);
    await expect(
      verifyAssertion({ assertion, clientDataHash, publicKey: key.publicKey, appId: APP_ID }),
    ).rejects.toBeInstanceOf(AttestationRejected);
  });

  it("refuses another app's assertion", async () => {
    const key = await fakeKey();
    const clientDataHash = await sha256(request);
    const assertion = await assert(key, clientDataHash, "OTHERTEAM1.com.idanbirman.goodmail");
    await expect(
      verifyAssertion({ assertion, clientDataHash, publicKey: key.publicKey, appId: APP_ID }),
    ).rejects.toBeInstanceOf(AttestationRejected);
  });
});
