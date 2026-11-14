import { createExecutionContext, env, waitOnExecutionContext } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { base64Decode } from "../src/encoding";
import { GOOGLE_JWKS_URL } from "../src/google";
import worker, { type Env } from "../src/index";
import { accountId, BURST_MS } from "../src/store";
import { generateApnsKey, generateGoogleKey, idTokenClaims, jwksResponse, signGoogleToken, type TestGoogleKey } from "./keys";

const EMAIL = "someone@gmail.com";
const DEVICE = "a".repeat(64);
const OTHER_DEVICE = "b".repeat(64);

let google: TestGoogleKey;
let apnsPublicKey: CryptoKey;
let testEnv: Env;

interface ApnsCall {
  url: string;
  headers: Headers;
  body: unknown;
}
let apnsCalls: ApnsCall[];
/** What the fake APNs answers for a device token; 200 unless set. */
let apnsReplies: Map<string, Response>;

beforeAll(async () => {
  google = await generateGoogleKey("worker-test-key");
  const apns = await generateApnsKey();
  apnsPublicKey = apns.publicKey;
  testEnv = { ...env, APNS_PRIVATE_KEY: apns.pem };
});

beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM devices"),
    env.DB.prepare("DELETE FROM deliveries"),
    env.DB.prepare("DELETE FROM graph_subscriptions"),
    env.DB.prepare("DELETE FROM push_times"),
  ]);
  apnsCalls = [];
  apnsReplies = new Map();
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const request = new Request(input, init);
    if (request.url === GOOGLE_JWKS_URL) return jwksResponse([google]);
    if (request.url.includes("push.apple.com")) {
      apnsCalls.push({ url: request.url, headers: request.headers, body: await request.json() });
      const token = request.url.split("/").pop() ?? "";
      return apnsReplies.get(token)?.clone() ?? new Response(null, { status: 200 });
    }
    throw new Error(`unexpected fetch ${request.url}`);
  });
});

afterEach(() => {
  vi.restoreAllMocks();
});

const now = () => Math.floor(Date.now() / 1000);

/** Runs a request through the Worker, including the work it hands to `waitUntil`. */
async function send(request: Request): Promise<Response> {
  const context = createExecutionContext();
  const response = await worker.fetch(request, testEnv, context);
  await waitOnExecutionContext(context);
  return response;
}

async function idToken(email = EMAIL, audience = testEnv.GOOGLE_CLIENT_ID): Promise<string> {
  return signGoogleToken(google, idTokenClaims(email, audience, now()));
}

async function devicesRequest(method: "POST" | "DELETE", body: Record<string, unknown>): Promise<Response> {
  const request = new Request("https://push.example.test/v1/devices", { method, body: JSON.stringify(body) });
  return send(request);
}

async function register(deviceToken = DEVICE, environment = "sandbox", email = EMAIL): Promise<Response> {
  return devicesRequest("POST", { idToken: await idToken(email), deviceToken, environment });
}

async function pubSubPush(historyId: string | number, email = EMAIL, claims: Record<string, unknown> = {}) {
  return send(await pubSubPushRequest(historyId, email, claims));
}

async function pubSubPushRequest(historyId: string | number, email = EMAIL, claims: Record<string, unknown> = {}) {
  const token = await signGoogleToken(google, {
    ...idTokenClaims(testEnv.PUBSUB_SERVICE_ACCOUNT, testEnv.PUBSUB_AUDIENCE, now()),
    ...claims,
  });
  const data = btoa(JSON.stringify({ emailAddress: email, historyId }));
  const body = JSON.stringify({ message: { data, messageId: "1", publishTime: "2026-11-12T00:00:00Z" }, subscription: "s" });
  return new Request(testEnv.PUBSUB_AUDIENCE, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body,
  });
}

/** Lets the next push through, as if the last one went out longer ago than a burst lasts. */
async function endBurst() {
  await env.DB.prepare("UPDATE push_times SET pushed_at = pushed_at - ?1").bind(BURST_MS).run();
}

async function storedDevices() {
  const { results } = await env.DB.prepare("SELECT * FROM devices ORDER BY device_token").all();
  return results;
}

describe("device registration", () => {
  it("stores the HMAC of the address, never the address itself", async () => {
    expect((await register(DEVICE, "sandbox", "Someone@Gmail.com")).status).toBe(204);
    const rows = await storedDevices();
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      account: await accountId(EMAIL, testEnv.EMAIL_HMAC_SECRET),
      device_token: DEVICE,
      environment: "sandbox",
    });
    expect(JSON.stringify(rows).toLowerCase()).not.toContain("someone");
    expect(rows[0]?.account).toMatch(/^[0-9a-f]{64}$/);
  });

  it("updates the environment when the same device registers again", async () => {
    await register(DEVICE, "sandbox");
    await register(DEVICE, "production");
    expect(await storedDevices()).toMatchObject([{ device_token: DEVICE, environment: "production" }]);
  });

  it("unregisters a device", async () => {
    await register(DEVICE);
    await register(OTHER_DEVICE);
    const response = await devicesRequest("DELETE", { idToken: await idToken(), deviceToken: DEVICE });
    expect(response.status).toBe(204);
    expect(await storedDevices()).toMatchObject([{ device_token: OTHER_DEVICE }]);
  });

  it("rejects an ID token for another client", async () => {
    const response = await devicesRequest("POST", {
      idToken: await idToken(EMAIL, "another-client"),
      deviceToken: DEVICE,
      environment: "sandbox",
    });
    expect(response.status).toBe(401);
    expect(await storedDevices()).toHaveLength(0);
  });

  it("rejects a bad device token or environment", async () => {
    expect((await register("not-hex")).status).toBe(400);
    expect((await register(DEVICE, "staging")).status).toBe(400);
    expect(await storedDevices()).toHaveLength(0);
  });
});

describe("Pub/Sub push", () => {
  it("sends a mutable alert to APNs with a signed provider token", async () => {
    await register(DEVICE, "sandbox");
    await register(OTHER_DEVICE, "production");
    expect((await pubSubPush("4242")).status).toBe(204);

    expect(apnsCalls.map((call) => call.url).sort()).toEqual([
      `https://api.push.apple.com/3/device/${OTHER_DEVICE}`,
      `https://api.sandbox.push.apple.com/3/device/${DEVICE}`,
    ]);
    const call = apnsCalls[0] as ApnsCall;
    expect(call.headers.get("apns-push-type")).toBe("alert");
    expect(call.headers.get("apns-topic")).toBe("com.idanbirman.goodmail");
    expect(call.headers.get("apns-priority")).toBe("10");
    expect(call.body).toEqual({
      aps: { alert: { "loc-key": "NEW_MAIL_PUSH" }, sound: "default", "mutable-content": 1 },
      account: EMAIL,
      historyId: "4242",
    });

    const jwt = /^bearer (.+)$/.exec(call.headers.get("authorization") ?? "")?.[1] ?? "";
    const [header, claims, signature] = jwt.split(".") as [string, string, string];
    const decode = (segment: string) => JSON.parse(new TextDecoder().decode(base64Decode(segment)));
    expect(decode(header)).toEqual({ alg: "ES256", kid: testEnv.APNS_KEY_ID });
    expect(decode(claims)).toEqual({ iss: testEnv.APNS_TEAM_ID, iat: expect.any(Number) });
    expect(Math.abs(decode(claims).iat - now())).toBeLessThan(5);
    const valid = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      apnsPublicKey,
      base64Decode(signature),
      new TextEncoder().encode(`${header}.${claims}`),
    );
    expect(valid).toBe(true);
  });

  it("accepts historyId as a JSON number, as Gmail may send it", async () => {
    await register();
    await pubSubPush(4242);
    expect(apnsCalls.map((call) => (call.body as { historyId: string }).historyId)).toEqual(["4242"]);
  });

  it("drops a duplicate delivery and a historyId that isn't newer", async () => {
    await register();
    await pubSubPush("100");
    await endBurst();
    await pubSubPush("100");
    await pubSubPush("99");
    await pubSubPush("101");
    expect(apnsCalls.map((call) => (call.body as { historyId: string }).historyId)).toEqual(["100", "101"]);
  });

  it("compares history IDs numerically, not by string length", async () => {
    await register();
    await pubSubPush("999");
    await endBurst();
    await pubSubPush("1000");
    expect(apnsCalls).toHaveLength(2);
  });

  it("sends one push for a burst of changes, and the next after the burst", async () => {
    await register();
    await pubSubPush("40");
    await pubSubPush("41");
    await pubSubPush("42");
    await endBurst();
    await pubSubPush("43");
    expect(apnsCalls.map((call) => (call.body as { historyId: string }).historyId)).toEqual(["40", "43"]);
  });

  it("sends nothing for an account without devices", async () => {
    await register(DEVICE, "sandbox", "other@gmail.com");
    expect((await pubSubPush("5")).status).toBe(204);
    expect(apnsCalls).toHaveLength(0);
  });

  it("removes a token APNs reports as gone (410)", async () => {
    await register(DEVICE);
    await register(OTHER_DEVICE);
    apnsReplies.set(DEVICE, Response.json({ reason: "Unregistered", timestamp: 1 }, { status: 410 }));
    await pubSubPush("7");
    expect(apnsCalls).toHaveLength(2);
    expect(await storedDevices()).toMatchObject([{ device_token: OTHER_DEVICE }]);
  });

  it("removes a token APNs reports as BadDeviceToken", async () => {
    await register(DEVICE);
    apnsReplies.set(DEVICE, Response.json({ reason: "BadDeviceToken" }, { status: 400 }));
    await pubSubPush("8");
    expect(await storedDevices()).toHaveLength(0);
  });

  it("keeps a token after other APNs failures", async () => {
    await register(DEVICE);
    apnsReplies.set(DEVICE, Response.json({ reason: "TooManyRequests" }, { status: 429 }));
    await pubSubPush("9");
    expect(await storedDevices()).toHaveLength(1);
  });

  it("asks for redelivery when every send fails, and sends the redelivery", async () => {
    await register(DEVICE);
    apnsReplies.set(DEVICE, new Response(null, { status: 503 }));
    expect((await pubSubPush("20")).status).toBe(503);
    apnsReplies.clear();
    expect((await pubSubPush("20")).status).toBe(204);
    expect(apnsCalls.map((call) => (call.body as { historyId: string }).historyId)).toEqual(["20", "20"]);
  });

  it("sends the redelivery after signing or APNs throws", async () => {
    await register(DEVICE);
    const broken = { ...testEnv, APNS_PRIVATE_KEY: "not a key" };
    const push = await pubSubPushRequest("21");
    await expect(worker.fetch(push, broken, createExecutionContext())).rejects.toThrow();
    expect((await pubSubPush("21")).status).toBe(204);
    expect(apnsCalls).toHaveLength(1);
  });

  it("gives back the claim to the one it replaced, so older pushes still drop", async () => {
    await register(DEVICE);
    await pubSubPush("30");
    await endBurst();
    apnsReplies.set(DEVICE, new Response(null, { status: 500 }));
    expect((await pubSubPush("31")).status).toBe(503);
    apnsReplies.clear();
    await pubSubPush("30");
    await pubSubPush("31");
    expect(apnsCalls.map((call) => (call.body as { historyId: string }).historyId)).toEqual(["30", "31", "31"]);
  });

  it("keeps the claim when one device got the alert and another failed", async () => {
    await register(DEVICE);
    await register(OTHER_DEVICE);
    apnsReplies.set(DEVICE, new Response(null, { status: 500 }));
    expect((await pubSubPush("40")).status).toBe(204);
    await pubSubPush("40");
    expect(apnsCalls).toHaveLength(2);
  });

  it("rejects a push from another service account or audience, or without a token", async () => {
    await register();
    expect((await pubSubPush("10", EMAIL, { email: "intruder@example.iam.gserviceaccount.com" })).status).toBe(401);
    expect((await pubSubPush("10", EMAIL, { aud: "https://elsewhere.example.test/" })).status).toBe(401);
    const unsigned = new Request(testEnv.PUBSUB_AUDIENCE, { method: "POST", body: "{}" });
    expect((await send(unsigned)).status).toBe(401);
    expect(apnsCalls).toHaveLength(0);
  });

  it("acknowledges a malformed message without sending", async () => {
    await register();
    const token = await signGoogleToken(google, idTokenClaims(testEnv.PUBSUB_SERVICE_ACCOUNT, testEnv.PUBSUB_AUDIENCE, now()));
    const request = new Request(testEnv.PUBSUB_AUDIENCE, {
      method: "POST",
      headers: { authorization: `Bearer ${token}` },
      body: JSON.stringify({ message: { data: btoa("not json") } }),
    });
    expect((await send(request)).status).toBe(204);
    expect(apnsCalls).toHaveLength(0);
  });
});
