import { createExecutionContext, env, waitOnExecutionContext } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { GMAIL_API, GOOGLE_REVOKE_URL, GOOGLE_TOKEN_URL, METADATA_SCOPE } from "../src/gmail";
import { GOOGLE_JWKS_URL } from "../src/google";
import worker, { type Env } from "../src/index";
import { accountId } from "../src/store";
import { generateApnsKey, generateGoogleKey, idTokenClaims, jwksResponse, signGoogleToken, type TestGoogleKey } from "./keys";

const EMAIL = "someone@gmail.com";
const DEVICE = "a".repeat(64);
const GRANT = "1//metadata-refresh-token";

let google: TestGoogleKey;
let testEnv: Env;
let apnsPushes: number;
/** What the fake token endpoint answers for GRANT. */
let tokenReply: () => Response;
/** What the fake history endpoint answers, and the start IDs it was asked for. */
let historyReply: () => Response;
let historyStarts: string[];
let revoked: string[];

beforeAll(async () => {
  google = await generateGoogleKey("grant-test-key");
  testEnv = { ...env, APNS_PRIVATE_KEY: (await generateApnsKey()).pem };
});

beforeEach(async () => {
  await env.DB.batch(
    ["devices", "deliveries", "push_times", "gmail_grants"].map((table) => env.DB.prepare(`DELETE FROM ${table}`)),
  );
  apnsPushes = 0;
  historyStarts = [];
  revoked = [];
  tokenReply = () => Response.json({ access_token: "ya29.metadata", expires_in: 3599, scope: METADATA_SCOPE });
  historyReply = () => Response.json({ history: [{ id: "12", messagesAdded: [{ message: { id: "m1" } }] }] });
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const request = new Request(input, init);
    const url = new URL(request.url);
    if (request.url === GOOGLE_JWKS_URL) return jwksResponse([google]);
    if (request.url.includes("push.apple.com")) {
      apnsPushes += 1;
      return new Response(null, { status: 200 });
    }
    if (request.url === GOOGLE_TOKEN_URL) {
      const form = await request.formData();
      if (form.get("refresh_token") !== GRANT) return Response.json({ error: "invalid_grant" }, { status: 400 });
      return tokenReply();
    }
    if (request.url === GOOGLE_REVOKE_URL) {
      revoked.push(String((await request.formData()).get("token")));
      return new Response(null, { status: 200 });
    }
    if (request.url === `${GMAIL_API}/profile`) return Response.json({ emailAddress: EMAIL, historyId: "10" });
    if (url.pathname.endsWith("/users/me/history")) {
      historyStarts.push(url.searchParams.get("startHistoryId") ?? "");
      expect(url.searchParams.get("labelId")).toBe("INBOX");
      expect(url.searchParams.get("historyTypes")).toBe("messageAdded");
      return historyReply();
    }
    throw new Error(`unexpected fetch ${request.url}`);
  });
});

afterEach(() => {
  vi.restoreAllMocks();
});

const now = () => Math.floor(Date.now() / 1000);

async function send(path: string, method: string, body: unknown, headers: Record<string, string> = {}) {
  const context = createExecutionContext();
  const request = new Request(`https://push.example.test${path}`, { method, headers, body: JSON.stringify(body) });
  const response = await worker.fetch(request, testEnv, context);
  await waitOnExecutionContext(context);
  return response;
}

async function idToken(email = EMAIL): Promise<string> {
  return signGoogleToken(google, idTokenClaims(email, testEnv.GOOGLE_CLIENT_ID, now()));
}

async function registerDevice() {
  expect((await send("/v1/devices", "POST", { idToken: await idToken(), deviceToken: DEVICE, environment: "sandbox" })).status).toBe(204);
}

async function pubSub(historyId: number) {
  const token = await signGoogleToken(google, idTokenClaims(testEnv.PUBSUB_SERVICE_ACCOUNT, testEnv.PUBSUB_AUDIENCE, now()));
  const data = btoa(JSON.stringify({ emailAddress: EMAIL, historyId }));
  return send("/v1/pubsub", "POST", { message: { data } }, { authorization: `Bearer ${token}` });
}

async function storedGrant() {
  return env.DB.prepare("SELECT * FROM gmail_grants").first<{ account: string; refresh_token: string }>();
}

async function status(): Promise<boolean> {
  const response = await send("/v1/gmail/grants/status", "POST", { idToken: await idToken() });
  return ((await response.json()) as { active: boolean }).active;
}

/** A device, a grant, and a first notification, so later ones have a history ID to check from. */
async function primed() {
  await registerDevice();
  expect((await send("/v1/gmail/grants", "POST", { refreshToken: GRANT })).status).toBe(204);
  await pubSub(10);
  await env.DB.prepare("UPDATE push_times SET pushed_at = 0").run();
  apnsPushes = 0;
}

describe("Gmail grants", () => {
  it("stores a metadata grant encrypted, under the account its profile names", async () => {
    expect(await status()).toBe(false);
    expect((await send("/v1/gmail/grants", "POST", { refreshToken: GRANT })).status).toBe(204);
    const row = await storedGrant();
    expect(row?.account).toBe(await accountId(EMAIL, testEnv.EMAIL_HMAC_SECRET));
    expect(row?.refresh_token).not.toContain(GRANT);
    expect(await status()).toBe(true);
  });

  it("refuses a grant broader than the metadata scope, and never stores it", async () => {
    tokenReply = () =>
      Response.json({ access_token: "ya29.full", expires_in: 3599, scope: `${METADATA_SCOPE} https://mail.google.com/` });
    expect((await send("/v1/gmail/grants", "POST", { refreshToken: GRANT })).status).toBe(400);
    expect(await storedGrant()).toBeNull();
  });

  it("refuses a refresh token Google doesn't accept", async () => {
    expect((await send("/v1/gmail/grants", "POST", { refreshToken: "1//not-real" })).status).toBe(401);
    expect(await storedGrant()).toBeNull();
  });

  it("removes and revokes the grant on request, and when the account's last device leaves", async () => {
    await primed();
    expect((await send("/v1/gmail/grants", "DELETE", { idToken: await idToken() })).status).toBe(204);
    expect(await storedGrant()).toBeNull();

    expect((await send("/v1/gmail/grants", "POST", { refreshToken: GRANT })).status).toBe(204);
    expect((await send("/v1/devices", "DELETE", { idToken: await idToken(), deviceToken: DEVICE })).status).toBe(204);
    expect(await storedGrant()).toBeNull();
    expect(revoked).toEqual([GRANT, GRANT]);
  });
});

describe("Pub/Sub push with a grant", () => {
  it("alerts when the history shows a message added to the Inbox, checking from the last history ID", async () => {
    await primed();
    expect((await pubSub(12)).status).toBe(204);
    expect(apnsPushes).toBe(1);
    expect(historyStarts).toEqual(["10"]);
  });

  it("sends nothing for a read, archive, delete or label change", async () => {
    await primed();
    historyReply = () => Response.json({ historyId: "13" });
    expect((await pubSub(13)).status).toBe(204);
    expect(apnsPushes).toBe(0);
  });

  it("alerts when Gmail can't say, as for a history ID too old to list", async () => {
    await primed();
    historyReply = () => new Response(null, { status: 404 });
    await pubSub(14);
    expect(apnsPushes).toBe(1);
  });

  it("alerts and forgets the grant once Google stops honoring it", async () => {
    await registerDevice();
    expect((await send("/v1/gmail/grants", "POST", { refreshToken: GRANT })).status).toBe(204);
    await env.DB.prepare("INSERT INTO deliveries (account, history_id) VALUES (?1, ?2)")
      .bind(await accountId(EMAIL, testEnv.EMAIL_HMAC_SECRET), "10".padStart(20, "0"))
      .run();
    tokenReply = () => Response.json({ error: "invalid_grant" }, { status: 400 });
    await pubSub(15);
    expect(apnsPushes).toBe(1);
    expect(await storedGrant()).toBeNull();
  });

  it("alerts for the first notification, which has no history ID to check from", async () => {
    await registerDevice();
    expect((await send("/v1/gmail/grants", "POST", { refreshToken: GRANT })).status).toBe(204);
    await pubSub(10);
    expect(apnsPushes).toBe(1);
    expect(historyStarts).toEqual([]);
  });
});
