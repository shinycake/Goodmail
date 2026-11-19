import { createExecutionContext, env, waitOnExecutionContext } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { GMAIL_API, GOOGLE_TOKEN_URL } from "../src/gmail";
import { GOOGLE_JWKS_URL } from "../src/google";
import { handledPushes as spacing } from "../src/handled";
import worker, { type Env } from "../src/index";
import { accountId } from "../src/store";
import { generateApnsKey, generateGoogleKey, idTokenClaims, jwksResponse, signGoogleToken, type TestGoogleKey } from "./keys";

const EMAIL = "someone@gmail.com";
const DEVICE = "a".repeat(64);
const GRANT = "1//app-refresh-token";
const FULL_SCOPE = "openid https://www.googleapis.com/auth/userinfo.email https://mail.google.com/";

let google: TestGoogleKey;
let testEnv: Env;
let apnsPushes: number;
/** What the fake token endpoint answers for GRANT, and how often it was asked. */
let tokenReply: () => Response;
let refreshes: number;
/** What the fake history endpoint answers, and the start IDs it was asked for. */
let historyReply: () => Response;
let historyStarts: string[];
/** The fake mailbox's messages by ID, as Gmail answers `format=metadata`. */
let messages: Map<string, Record<string, unknown>>;
/** The last alert APNs was sent. */
let lastAlert: unknown;
/** The quiet pushes that say mail was dealt with (handled.ts), which are no alerts. */
let quietPushes: unknown[];

function gmailMessage(labelIds: string[], from = '"Dana Levi" <dana@example.com>', subject = "Lunch?", at = "1800000000000") {
  return {
    labelIds,
    internalDate: at,
    payload: { headers: [{ name: "From", value: from }, { name: "Subject", value: subject }] },
  };
}

beforeAll(async () => {
  google = await generateGoogleKey("grant-test-key");
  testEnv = { ...env, APNS_PRIVATE_KEY: (await generateApnsKey()).pem };
});

beforeEach(async () => {
  spacing.clear();
  await env.DB.batch(
    ["devices", "deliveries", "push_times", "gmail_grants"].map((table) => env.DB.prepare(`DELETE FROM ${table}`)),
  );
  apnsPushes = 0;
  historyStarts = [];
  messages = new Map([["m1", gmailMessage(["INBOX", "UNREAD"])]]);
  lastAlert = undefined;
  quietPushes = [];
  refreshes = 0;
  tokenReply = () => Response.json({ access_token: "ya29.app", expires_in: 3599, scope: FULL_SCOPE });
  historyReply = () => Response.json({ history: [{ id: "12", messagesAdded: [{ message: { id: "m1" } }] }] });
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const request = new Request(input, init);
    const url = new URL(request.url);
    if (request.url === GOOGLE_JWKS_URL) return jwksResponse([google]);
    if (request.url.includes("push.apple.com") && request.headers.get("apns-push-type") === "background") {
      expect(request.headers.get("apns-priority")).toBe("5");
      quietPushes.push(await request.json());
      return new Response(null, { status: 200 });
    }
    if (request.url.includes("push.apple.com")) {
      apnsPushes += 1;
      lastAlert = await request.json();
      return new Response(null, { status: 200 });
    }
    if (request.url === GOOGLE_TOKEN_URL) {
      const form = await request.formData();
      if (form.get("refresh_token") !== GRANT) return Response.json({ error: "invalid_grant" }, { status: 400 });
      refreshes += 1;
      return tokenReply();
    }
    if (request.url === `${GMAIL_API}/profile`) return Response.json({ emailAddress: EMAIL, historyId: "10" });
    if (url.pathname.endsWith("/users/me/history")) {
      historyStarts.push(url.searchParams.get("startHistoryId") ?? "");
      expect(url.searchParams.get("labelId")).toBe("INBOX");
      expect(url.searchParams.get("historyTypes")).toBe("messageAdded");
      return historyReply();
    }
    if (url.pathname.includes("/users/me/messages/")) {
      expect(url.searchParams.get("format")).toBe("metadata");
      const found = messages.get(decodeURIComponent(url.pathname.split("/").pop() ?? ""));
      return found ? Response.json(found) : new Response(null, { status: 404 });
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

/** A device, a grant, and a first notification, so later ones have a history ID to check from. */
async function primed() {
  await registerDevice();
  expect((await send("/v1/gmail/grants", "POST", { refreshToken: GRANT })).status).toBe(204);
  await pubSub(10);
  await env.DB.prepare("UPDATE push_times SET pushed_at = 0").run();
  apnsPushes = 0;
  quietPushes = [];
  spacing.clear();
}

describe("Gmail grants", () => {
  it("stores the app's token encrypted, under the account its profile names", async () => {
    expect((await send("/v1/gmail/grants", "POST", { refreshToken: GRANT })).status).toBe(204);
    const row = await storedGrant();
    expect(row?.account).toBe(await accountId(EMAIL, testEnv.EMAIL_HMAC_SECRET));
    expect(row?.refresh_token).not.toContain(GRANT);
  });

  it("answers a token it already holds without asking Google again", async () => {
    expect((await send("/v1/gmail/grants", "POST", { refreshToken: GRANT })).status).toBe(204);
    expect((await send("/v1/gmail/grants", "POST", { refreshToken: GRANT })).status).toBe(204);
    expect(refreshes).toBe(1);
  });

  it("refuses a token that can't read Gmail history, and never stores it", async () => {
    tokenReply = () => Response.json({ access_token: "ya29.profile", expires_in: 3599, scope: "openid email" });
    expect((await send("/v1/gmail/grants", "POST", { refreshToken: GRANT })).status).toBe(400);
    expect(await storedGrant()).toBeNull();
  });

  it("refuses a refresh token Google doesn't accept", async () => {
    expect((await send("/v1/gmail/grants", "POST", { refreshToken: "1//not-real" })).status).toBe(401);
    expect(await storedGrant()).toBeNull();
  });

  it("forgets the token, without revoking the app's sign-in, when the account's last device leaves", async () => {
    await primed();
    expect((await send("/v1/devices", "DELETE", { idToken: await idToken(), deviceToken: DEVICE })).status).toBe(204);
    expect(await storedGrant()).toBeNull();
  });
});

describe("Pub/Sub push with a grant", () => {
  it("alerts with the new email's sender and subject, checking from the last history ID", async () => {
    await primed();
    expect((await pubSub(12)).status).toBe(204);
    expect(apnsPushes).toBe(1);
    expect(historyStarts.at(-1)).toBe("10");
    expect(lastAlert).toEqual({
      aps: { alert: { title: "Dana Levi", body: "Lunch?" }, sound: "default", "mutable-content": 1 },
      account: EMAIL,
      historyId: "12",
      alert: expect.stringMatching(/^[0-9a-f-]{36}$/),
    });
  });

  it("alerts for the newest of several new emails", async () => {
    await primed();
    messages.set("m2", gmailMessage(["INBOX", "UNREAD"], "Noa <noa@example.com>", "Later", "1800000005000"));
    historyReply = () =>
      Response.json({ history: [{ id: "12", messagesAdded: [{ message: { id: "m1" } }, { message: { id: "m2" } }] }] });
    await pubSub(12);
    expect(lastAlert).toMatchObject({ aps: { alert: { title: "Noa", body: "Later" } } });
  });

  it("alerts for no read, archive, delete or label change, and tells the device to take down what it no longer needs", async () => {
    await primed();
    historyReply = () => Response.json({ historyId: "13" });
    expect((await pubSub(13)).status).toBe(204);
    expect(apnsPushes).toBe(0);
    expect(quietPushes).toEqual([{ aps: { "content-available": 1 }, account: EMAIL, historyId: "13", handled: 1 }]);
  });

  it("sends no quiet push beside an alert, whose own catch-up takes down what was dealt with", async () => {
    await primed();
    historyReply = () => Response.json({ history: [{ id: "13", messagesAdded: [{ message: { id: "m1" } }] }] });
    expect((await pubSub(13)).status).toBe(204);
    expect(apnsPushes).toBe(1);
    expect(quietPushes).toEqual([]);
  });

  it("alerts for mail sent to oneself that lands unread in the Inbox, as Apple Mail does", async () => {
    await primed();
    messages.set("own", gmailMessage(["INBOX", "UNREAD", "SENT"]));
    historyReply = () => Response.json({ history: [{ id: "13", messagesAdded: [{ message: { id: "own" } }] }] });
    expect((await pubSub(13)).status).toBe(204);
    expect(apnsPushes).toBe(1);
  });

  it("sends nothing for mail read or archived already, or gone", async () => {
    await primed();
    messages.set("read", gmailMessage(["INBOX"]));
    messages.set("archived", gmailMessage(["UNREAD"]));
    historyReply = () =>
      Response.json({
        history: [{ id: "13", messagesAdded: ["read", "archived", "gone"].map((id) => ({ message: { id } })) }],
      });
    expect((await pubSub(13)).status).toBe(204);
    expect(apnsPushes).toBe(0);
  });

  it("skips other categories when the app alerts for Primary only", async () => {
    await registerDevice();
    expect((await send("/v1/gmail/grants", "POST", { refreshToken: GRANT, primaryOnly: true })).status).toBe(204);
    messages.set("m1", gmailMessage(["INBOX", "UNREAD", "CATEGORY_PROMOTIONS"]));
    await pubSub(12);
    expect(apnsPushes).toBe(0);
  });

  it("asks Pub/Sub to deliver again when Gmail can't answer, and alerts then", async () => {
    await primed();
    historyReply = () => new Response(null, { status: 500 });
    expect((await pubSub(14)).status).toBe(503);
    expect(apnsPushes).toBe(0);
    historyReply = () => Response.json({ history: [{ id: "14", messagesAdded: [{ message: { id: "m1" } }] }] });
    expect((await pubSub(14)).status).toBe(204);
    expect(apnsPushes).toBe(1);
  });

  it("sends nothing when the history is too old to list, as nothing can say what arrived", async () => {
    await primed();
    historyReply = () => new Response(null, { status: 404 });
    expect((await pubSub(14)).status).toBe(204);
    expect(apnsPushes).toBe(0);
  });

  it("sends nothing and forgets the token once Google stops honoring it", async () => {
    await registerDevice();
    expect((await send("/v1/gmail/grants", "POST", { refreshToken: GRANT })).status).toBe(204);
    await env.DB.prepare("INSERT INTO deliveries (account, history_id) VALUES (?1, ?2)")
      .bind(await accountId(EMAIL, testEnv.EMAIL_HMAC_SECRET), "10".padStart(20, "0"))
      .run();
    tokenReply = () => Response.json({ error: "invalid_grant" }, { status: 400 });
    await pubSub(15);
    expect(apnsPushes).toBe(0);
    expect(await storedGrant()).toBeNull();
  });

  it("checks the first notification from the history ID the token was stored at", async () => {
    await registerDevice();
    expect((await send("/v1/gmail/grants", "POST", { refreshToken: GRANT })).status).toBe(204);
    await pubSub(11);
    expect(apnsPushes).toBe(1);
    expect(historyStarts).toEqual(["10"]);
  });

  it("sends nothing for an account without a token, since it can't read the mail", async () => {
    await registerDevice();
    await pubSub(11);
    expect(apnsPushes).toBe(0);
  });
});
