import { createExecutionContext, env, waitOnExecutionContext } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import worker, { type Env } from "../src/index";
import { GRAPH_API, MICROSOFT_TOKEN_URL } from "../src/outlook";
import { generateApnsKey } from "./keys";

const SUBSCRIPTION = "0f8fad5b-d9cb-469f-a165-70867728950e";
const OTHER_SUBSCRIPTION = "7c9e6679-7425-40de-944b-e07fc1f90ae7";
const CLIENT_STATE = "c".repeat(64);
const ACCOUNT = "3F2504E0-4F89-11D3-9A0C-0305E82C3301";
const DEVICE = "a".repeat(64);

let testEnv: Env;
let apnsCalls: { url: string; body: unknown }[];
let apnsStatus: number;
/** The fake mailbox's messages by ID, as Graph answers `$select=subject,from,isRead,parentFolderId,receivedDateTime`. */
let messages: Map<string, Record<string, unknown>>;
let refreshes: string[];

const APP_TOKEN = "M.app-refresh-token";

function message(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    subject: "Lunch?",
    from: { emailAddress: { name: "Dana Levi", address: "dana@example.com" } },
    isRead: false,
    parentFolderId: "inbox-id",
    receivedDateTime: "2026-11-16T18:00:00Z",
    ...overrides,
  };
}

beforeAll(async () => {
  testEnv = { ...env, APNS_PRIVATE_KEY: (await generateApnsKey()).pem };
});

beforeEach(async () => {
  await env.DB.prepare("DELETE FROM graph_subscriptions").run();
  await env.DB.prepare("DELETE FROM graph_grants").run();
  apnsCalls = [];
  apnsStatus = 200;
  messages = new Map([["m1", message()]]);
  refreshes = [];
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const request = new Request(input, init);
    if (request.url === MICROSOFT_TOKEN_URL) {
      const token = String((await request.formData()).get("refresh_token"));
      refreshes.push(token);
      if (!token.startsWith("M.")) return Response.json({ error: "invalid_grant" }, { status: 400 });
      return Response.json({ access_token: "eyJ.access", expires_in: 3599, refresh_token: "M.rotated" });
    }
    if (request.url.startsWith(`${GRAPH_API}/me?`)) return Response.json({ mail: "Me@Outlook.com" });
    if (request.url.startsWith(`${GRAPH_API}/me/mailFolders/inbox`)) return Response.json({ id: "inbox-id" });
    if (request.url.startsWith(`${GRAPH_API}/me/messages/`)) {
      const id = decodeURIComponent(new URL(request.url).pathname.split("/").pop() ?? "");
      const found = messages.get(id);
      return found ? Response.json(found) : Response.json({ error: { code: "ErrorItemNotFound" } }, { status: 404 });
    }
    if (!request.url.includes("push.apple.com")) throw new Error(`unexpected fetch ${request.url}`);
    apnsCalls.push({ url: request.url, body: await request.json() });
    return new Response(apnsStatus === 410 ? JSON.stringify({ reason: "Unregistered" }) : null, { status: apnsStatus });
  });
});

afterEach(() => {
  vi.restoreAllMocks();
});

async function send(request: Request): Promise<Response> {
  const context = createExecutionContext();
  const response = await worker.fetch(request, testEnv, context);
  await waitOnExecutionContext(context);
  return response;
}

function subscriptions(method: "POST" | "DELETE", body: Record<string, unknown>): Promise<Response> {
  return send(new Request("https://push.example.test/v1/graph/subscriptions", { method, body: JSON.stringify(body) }));
}

function registration(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    subscriptionId: SUBSCRIPTION,
    clientState: CLIENT_STATE,
    account: ACCOUNT,
    deviceToken: DEVICE,
    environment: "sandbox",
    expiresAt: Date.now() + 3_600_000,
    ...overrides,
  };
}

function notify(...notifications: Record<string, unknown>[]): Promise<Response> {
  return send(
    new Request("https://push.example.test/v1/graph", { method: "POST", body: JSON.stringify({ value: notifications }) }),
  );
}

function grant(refreshToken = APP_TOKEN, clientState = CLIENT_STATE): Promise<Response> {
  return send(
    new Request("https://push.example.test/v1/graph/grants", {
      method: "POST",
      body: JSON.stringify({ subscriptionId: SUBSCRIPTION, clientState, refreshToken }),
    }),
  );
}

/** A subscription with the app's token, ready for notifications. */
async function subscribed() {
  await subscriptions("POST", registration());
  expect((await grant()).status).toBe(204);
  refreshes = [];
}

function created(id: string, clientState = CLIENT_STATE): Record<string, unknown> {
  return { subscriptionId: SUBSCRIPTION, clientState, changeType: "created", resourceData: { id } };
}

async function stored() {
  const { results } = await env.DB.prepare("SELECT * FROM graph_subscriptions ORDER BY subscription_id").all();
  return results;
}

describe("Graph validation", () => {
  it("echoes the validation token as plain text", async () => {
    const response = await send(
      new Request("https://push.example.test/v1/graph?validationToken=Validation%3A%20Testing", { method: "POST" }),
    );
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("text/plain");
    expect(await response.text()).toBe("Validation: Testing");
  });
});

describe("Graph subscription registration", () => {
  it("stores the hash of the clientState, never the clientState", async () => {
    expect((await subscriptions("POST", registration())).status).toBe(204);
    const rows = await stored();
    expect(rows).toMatchObject([{ subscription_id: SUBSCRIPTION, account: ACCOUNT, device_token: DEVICE }]);
    expect(JSON.stringify(rows)).not.toContain(CLIENT_STATE);
  });

  it("renews with the same clientState, and refuses another", async () => {
    await subscriptions("POST", registration());
    const later = Date.now() + 7_200_000;
    expect((await subscriptions("POST", registration({ expiresAt: later }))).status).toBe(204);
    const stolen = registration({ clientState: "d".repeat(64), deviceToken: "b".repeat(64) });
    expect((await subscriptions("POST", stolen)).status).toBe(403);
    expect(await stored()).toMatchObject([{ device_token: DEVICE, expires_at: later }]);
  });

  it("drops subscriptions more than a day past expiry", async () => {
    await subscriptions("POST", registration({ subscriptionId: OTHER_SUBSCRIPTION, expiresAt: Date.now() - 2 * 86_400_000 }));
    await subscriptions("POST", registration());
    expect(await stored()).toMatchObject([{ subscription_id: SUBSCRIPTION }]);
  });

  it("unregisters only with the right clientState", async () => {
    await subscriptions("POST", registration());
    await subscriptions("DELETE", { subscriptionId: SUBSCRIPTION, clientState: "d".repeat(64) });
    expect(await stored()).toHaveLength(1);
    expect((await subscriptions("DELETE", { subscriptionId: SUBSCRIPTION, clientState: CLIENT_STATE })).status).toBe(204);
    expect(await stored()).toHaveLength(0);
  });

  it("rejects malformed registrations", async () => {
    for (const bad of [
      { subscriptionId: "not-a-guid" },
      { clientState: "short" },
      { account: "has spaces" },
      { deviceToken: "xyz" },
      { environment: "staging" },
      { expiresAt: "tomorrow" },
    ]) {
      expect((await subscriptions("POST", registration(bad))).status).toBe(400);
    }
    expect(await stored()).toHaveLength(0);
  });
});

describe("Outlook grants", () => {
  it("stores the app's token sealed, for the account of the subscription its clientState proves", async () => {
    await subscriptions("POST", registration());
    expect((await grant()).status).toBe(204);
    const row = await env.DB.prepare("SELECT * FROM graph_grants").first<Record<string, string>>();
    expect(row?.account).toBe(ACCOUNT);
    expect(JSON.stringify(row)).not.toContain("M.");
    expect(JSON.stringify(row).toLowerCase()).not.toContain("outlook.com");
  });

  it("answers a token it already holds without asking Microsoft", async () => {
    await subscribed();
    expect((await grant()).status).toBe(204);
    expect(refreshes).toEqual([]);
  });

  it("refuses a token for a subscription that isn't the caller's, or one Microsoft refuses", async () => {
    await subscriptions("POST", registration());
    expect((await grant(APP_TOKEN, "d".repeat(64))).status).toBe(403);
    expect((await grant("not-a-token")).status).toBe(401);
    expect(await env.DB.prepare("SELECT * FROM graph_grants").first()).toBeNull();
  });

  it("forgets the token when the account's last subscription goes", async () => {
    await subscribed();
    await subscriptions("DELETE", { subscriptionId: SUBSCRIPTION, clientState: CLIENT_STATE });
    expect(await env.DB.prepare("SELECT * FROM graph_grants").first()).toBeNull();
  });
});

describe("Graph notifications", () => {
  it("sends one alert per subscription in a batch, with the newest email's sender and subject", async () => {
    await subscribed();
    messages.set("m2", message({ subject: "Earlier", receivedDateTime: "2026-11-16T17:00:00Z" }));
    expect((await notify(created("m1"), created("m2"))).status).toBe(202);
    expect(apnsCalls).toHaveLength(1);
    expect(apnsCalls[0]?.url).toBe(`https://api.sandbox.push.apple.com/3/device/${DEVICE}`);
    expect(apnsCalls[0]?.body).toEqual({
      aps: { alert: { title: "Dana Levi", body: "Lunch?" }, sound: "default", "mutable-content": 1 },
      accountID: ACCOUNT,
    });
  });

  it("stays quiet for mail sent to oneself, already read, moved out of the Inbox, or gone", async () => {
    await subscribed();
    messages.set("own", message({ from: { emailAddress: { name: "Me", address: "me@outlook.com" } } }));
    messages.set("read", message({ isRead: true }));
    messages.set("moved", message({ parentFolderId: "archive-id" }));
    await notify(created("own"), created("read"), created("moved"), created("gone"));
    expect(apnsCalls).toHaveLength(0);
  });

  it("sends nothing for an account whose token it doesn't hold, since it can't read the mail", async () => {
    await subscriptions("POST", registration());
    await notify(created("m1"));
    expect(apnsCalls).toHaveLength(0);
  });

  it("keeps the newest refresh token Microsoft hands out", async () => {
    await subscribed();
    await notify(created("m1"));
    // The grant's own refresh already handed out a newer one, which the notification used.
    expect(refreshes).toEqual(["M.rotated"]);
    const { OutlookGrants } = await import("../src/outlook");
    expect((await new OutlookGrants(env.DB, testEnv.EMAIL_HMAC_SECRET).grant(ACCOUNT))?.refreshToken).toBe("M.rotated");
  });

  it("ignores a notification with the wrong clientState or an unknown subscription", async () => {
    await subscribed();
    await notify(
      { subscriptionId: SUBSCRIPTION, clientState: "d".repeat(64) },
      { subscriptionId: OTHER_SUBSCRIPTION, clientState: CLIENT_STATE },
    );
    expect(apnsCalls).toHaveLength(0);
  });

  it("acknowledges a malformed body without sending", async () => {
    await subscriptions("POST", registration());
    const response = await send(new Request("https://push.example.test/v1/graph", { method: "POST", body: "nope" }));
    expect(response.status).toBe(202);
    expect(apnsCalls).toHaveLength(0);
  });

  it("removes a token APNs reports as gone", async () => {
    await subscribed();
    apnsStatus = 410;
    await notify(created("m1"));
    expect(await stored()).toHaveLength(0);
  });
});
