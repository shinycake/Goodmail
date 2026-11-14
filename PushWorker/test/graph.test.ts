import { createExecutionContext, env, waitOnExecutionContext } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import worker, { type Env } from "../src/index";
import { generateApnsKey } from "./keys";

const SUBSCRIPTION = "0f8fad5b-d9cb-469f-a165-70867728950e";
const OTHER_SUBSCRIPTION = "7c9e6679-7425-40de-944b-e07fc1f90ae7";
const CLIENT_STATE = "c".repeat(64);
const ACCOUNT = "3F2504E0-4F89-11D3-9A0C-0305E82C3301";
const DEVICE = "a".repeat(64);

let testEnv: Env;
let apnsCalls: { url: string; body: unknown }[];
let apnsStatus: number;

beforeAll(async () => {
  testEnv = { ...env, APNS_PRIVATE_KEY: (await generateApnsKey()).pem };
});

beforeEach(async () => {
  await env.DB.prepare("DELETE FROM graph_subscriptions").run();
  apnsCalls = [];
  apnsStatus = 200;
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const request = new Request(input, init);
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

describe("Graph notifications", () => {
  it("sends one mutable alert naming the account per subscription in a batch", async () => {
    await subscriptions("POST", registration());
    const notification = { subscriptionId: SUBSCRIPTION, clientState: CLIENT_STATE, changeType: "created" };
    expect((await notify(notification, notification)).status).toBe(202);
    expect(apnsCalls).toHaveLength(1);
    expect(apnsCalls[0]?.url).toBe(`https://api.sandbox.push.apple.com/3/device/${DEVICE}`);
    expect(apnsCalls[0]?.body).toEqual({
      aps: { alert: { "loc-key": "NEW_MAIL_PUSH" }, sound: "default", "mutable-content": 1 },
      accountID: ACCOUNT,
    });
  });

  it("ignores a notification with the wrong clientState or an unknown subscription", async () => {
    await subscriptions("POST", registration());
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
    await subscriptions("POST", registration());
    apnsStatus = 410;
    await notify({ subscriptionId: SUBSCRIPTION, clientState: CLIENT_STATE });
    expect(await stored()).toHaveLength(0);
  });
});
