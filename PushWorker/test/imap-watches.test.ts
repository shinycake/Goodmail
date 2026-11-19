import { env } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { ApnsSigner } from "../src/apns";
import { handledPushes } from "../src/handled";
import { Alerts } from "../src/fallback";
import type { Env } from "../src/index";
import { InboxWatches } from "../src/inbox-watches";
import { MOST_AT_ONCE, pollWatches } from "../src/imap-poll";
import { findWatch, WATCH_LIFETIME_MS } from "../src/imap-watches";
import { RECHECK_AFTER_MS, registerWatch, unregisterWatch } from "../src/imap-routes";
import { fakeImap, inboxServer, type Reply } from "./fake-imap";
import { generateApnsKey } from "./keys";

const WATCH_ID = "0f8fad5b-d9cb-469f-a165-70867728950e";
const OTHER_WATCH_ID = "7c9e6679-7425-40de-944b-e07fc1f90ae7";
const SECRET = "5".repeat(64);
const DEVICE = "a".repeat(64);
const OTHER_DEVICE = "b".repeat(64);
const NOW = 1_800_000_000_000;

let testEnv: Env;
let signer: ApnsSigner;
let apnsCalls: { url: string; body: unknown }[];
let apnsReplies: Map<string, Response>;
/** What the fake server answers on the next connections. */
let server: Reply;
/** Each test checks logins from its own address, so the rate limit doesn't carry over between tests. */
let testAddress = 0;

beforeAll(async () => {
  const apns = await generateApnsKey();
  testEnv = { ...env, APNS_PRIVATE_KEY: apns.pem };
  signer = new ApnsSigner({ keyId: "KEY1234567", teamId: "TEAM123456", privateKey: apns.pem });
});

/** Alerts as the cron run sends them; a watch's fallback isn't waited for here. */
const alerts = () =>
  new Alerts(env.DB, signer, { app: "com.idanbirman.goodmail", watch: "com.idanbirman.goodmail.watchkitapp" }, () => {});

beforeEach(async () => {
  handledPushes.clear();
  await env.DB.prepare("DELETE FROM imap_watches").run();
  await env.DB.prepare("DELETE FROM devices").run();
  apnsCalls = [];
  apnsReplies = new Map();
  server = inboxServer({ uidValidity: 7, uidNext: 100 });
  testAddress++;
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const request = new Request(input, init);
    if (!request.url.includes("push.apple.com")) throw new Error(`unexpected fetch ${request.url}`);
    apnsCalls.push({ url: request.url, body: await request.json() });
    return apnsReplies.get(request.url.split("/").pop() ?? "")?.clone() ?? new Response(null, { status: 200 });
  });
});

afterEach(() => {
  vi.restoreAllMocks();
});

const imap = fakeImap(() => server);

function watchBody(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    watchId: WATCH_ID,
    secret: SECRET,
    account: "account-1",
    deviceToken: DEVICE,
    environment: "sandbox",
    host: "imap.mail.me.com",
    port: 993,
    security: "tls",
    username: "someone@icloud.com",
    password: "abcd-efgh-ijkl-mnop",
    ...overrides,
  };
}

function request(method: "POST" | "DELETE", body: Record<string, unknown>, address = `203.0.113.${testAddress}`): Request {
  return new Request("https://push.example.test/v1/imap/watches", {
    method,
    body: JSON.stringify(body),
    headers: { "cf-connecting-ip": address },
  });
}

async function register(overrides: Record<string, unknown> = {}, address?: string): Promise<Response> {
  return registerWatch(request("POST", watchBody(overrides), address), testEnv, NOW, imap.connect);
}

/** The same registration, sent at `now`. */
async function registerAt(now: number): Promise<Response> {
  return registerWatch(request("POST", watchBody()), testEnv, now, imap.connect);
}

const poll = (now = NOW) => pollWatches(testEnv, alerts(), now, imap.connect, 0);

describe("registering a watch", () => {
  it("checks a new login and starts from the Inbox's UIDs, keeping the password sealed", async () => {
    imap.sessions.length = 0;
    expect((await register()).status).toBe(204);
    expect(imap.sessions).toHaveLength(1);
    const watch = await findWatch(env.DB, WATCH_ID);
    expect(watch).toMatchObject({
      account: "account-1",
      device: { token: DEVICE, environment: "sandbox" },
      state: { kind: "watching" },
      inbox: { uidValidity: 7, uidNext: 100 },
      expiresAt: NOW + WATCH_LIFETIME_MS,
    });
    expect(watch?.login).not.toContain("abcd");
    expect(watch?.secretHash).not.toContain(SECRET);
  });

  it("renews the same login without logging in again", async () => {
    await register();
    imap.sessions.length = 0;
    expect((await register({ deviceToken: OTHER_DEVICE })).status).toBe(204);
    expect(imap.sessions).toHaveLength(0);
    expect((await findWatch(env.DB, WATCH_ID))?.device.token).toBe(OTHER_DEVICE);
  });

  it("checks a changed password", async () => {
    await register();
    imap.sessions.length = 0;
    expect((await register({ password: "new-password" })).status).toBe(204);
    expect(imap.sessions).toHaveLength(1);
  });

  it("refuses a login the server refuses, and answers the same for a minute without logging in again", async () => {
    server = inboxServer({ uidValidity: 7, uidNext: 100 }, "refused");
    imap.sessions.length = 0;
    expect((await register()).status).toBe(424);
    expect((await findWatch(env.DB, WATCH_ID))?.state).toEqual({ kind: "refused", refusals: 1, refusedAt: NOW });
    expect((await register({ watchId: OTHER_WATCH_ID })).status).toBe(424);
    expect(imap.sessions).toHaveLength(1);
  });

  it("checks a refused login again when the app registers it a minute later, and watches once the server takes it", async () => {
    server = inboxServer({ uidValidity: 7, uidNext: 100 }, "refused");
    await register();
    imap.sessions.length = 0;
    expect((await registerAt(NOW + RECHECK_AFTER_MS)).status).toBe(424);
    expect(imap.sessions).toHaveLength(1);
    expect((await findWatch(env.DB, WATCH_ID))?.state).toMatchObject({ kind: "refused", refusals: 2 });
    server = inboxServer({ uidValidity: 7, uidNext: 104 });
    expect((await registerAt(NOW + 2 * RECHECK_AFTER_MS)).status).toBe(204);
    expect(await findWatch(env.DB, WATCH_ID)).toMatchObject({ state: { kind: "watching" }, inbox: { uidNext: 104 } });
  });

  it("answers 503 when the server can't be reached, so the app tries again", async () => {
    server = (tag) => [`${tag} NO [UNAVAILABLE] later`];
    expect((await register()).status).toBe(503);
  });

  it("won't let another secret take over a watch", async () => {
    await register();
    expect((await register({ secret: "6".repeat(64), password: "other" })).status).toBe(403);
    expect((await register({ secret: "6".repeat(64) })).status).toBe(403);
  });

  it("rejects logins that can't be sent safely", async () => {
    await expect(register({ password: "pässword" })).rejects.toThrow("bad password");
    await expect(register({ host: "imap.example.com/x" })).rejects.toThrow("bad host");
    await expect(register({ security: "none" })).rejects.toThrow("security");
  });

  it("limits login checks from one address", async () => {
    const address = "198.51.100.9";
    const statuses = [];
    for (let attempt = 0; attempt < 7; attempt++) {
      statuses.push((await register({ password: `password-${attempt}` }, address)).status);
    }
    expect(statuses).toContain(429);
  });

  it("removes a watch only with its secret", async () => {
    await register();
    const remove = (secret: string) =>
      unregisterWatch(request("DELETE", { watchId: WATCH_ID, secret }), testEnv);
    expect((await remove("6".repeat(64))).status).toBe(204);
    expect(await findWatch(env.DB, WATCH_ID)).toBeDefined();
    await remove(SECRET);
    expect(await findWatch(env.DB, WATCH_ID)).toBeUndefined();
  });
});

describe("an IMAP watch's watch token", () => {
  const WATCH = "c".repeat(64);

  it("is stored with a new watch and with a renewal, and cleared by a renewal without it", async () => {
    expect((await register({ watchToken: WATCH })).status).toBe(204);
    expect((await findWatch(env.DB, WATCH_ID))?.device).toEqual({ token: DEVICE, environment: "sandbox", watchToken: WATCH });

    expect((await register()).status).toBe(204);
    expect((await findWatch(env.DB, WATCH_ID))?.device).toEqual({ token: DEVICE, environment: "sandbox" });

    expect((await register({ watchToken: WATCH })).status).toBe(204);
    expect((await findWatch(env.DB, WATCH_ID))?.device.watchToken).toBe(WATCH);
  });
});

describe("polling", () => {
  it("alerts the device by account ID when new mail grows UIDNEXT, once", async () => {
    await register();
    server = inboxServer({ uidValidity: 7, uidNext: 102 });
    await poll();
    expect(apnsCalls).toHaveLength(1);
    expect(apnsCalls[0]?.url).toBe(`https://api.sandbox.push.apple.com/3/device/${DEVICE}`);
    expect(apnsCalls[0]?.body).toEqual({
      aps: { alert: { title: "Dana Levi", body: "Lunch?" }, sound: "default", "mutable-content": 1 },
      accountID: "account-1",
      alert: expect.stringMatching(/^[0-9a-f-]{36}$/),
    });
    await poll();
    expect(apnsCalls).toHaveLength(1);
  });

  it("alerts within the run while it idles, as soon as the server announces mail", async () => {
    await register();
    const inbox = { uidValidity: 7, uidNext: 100 };
    server = inboxServer(inbox);
    imap.sessions.length = 0;
    const run = pollWatches(testEnv, alerts(), NOW, imap.connect, 4_500);
    await vi.waitUntil(() => imap.sessions[0]?.lines.some((line) => line.endsWith(" IDLE")));
    expect(apnsCalls).toHaveLength(0);
    inbox.uidNext = 101;
    imap.announce("* 4 EXISTS");
    await vi.waitUntil(() => apnsCalls.length === 1);
    await run;
    expect(imap.sessions).toHaveLength(1);
    expect((await findWatch(env.DB, WATCH_ID))?.inbox.uidNext).toBe(101);
  });

  it("tells the device to take down alerts when mail is read or deleted in another app, without alerting", async () => {
    await register();
    server = inboxServer({ uidValidity: 7, uidNext: 100 });
    imap.sessions.length = 0;
    const run = pollWatches(testEnv, alerts(), NOW, imap.connect, 6_500);
    await vi.waitUntil(() => imap.sessions[0]?.lines.some((line) => line.endsWith(" IDLE")));
    imap.announce("* 2 FETCH (FLAGS (\\Seen))");
    imap.announce("* 1 EXPUNGE");
    await vi.waitUntil(() => apnsCalls.length === 1, { timeout: 4_000 });
    await run;
    expect(apnsCalls).toEqual([
      {
        url: `https://api.sandbox.push.apple.com/3/device/${DEVICE}`,
        body: { aps: { "content-available": 1 }, accountID: "account-1", handled: 1 },
      },
    ]);
  });

  it("alerts for mail sent to oneself that lands unread in the Inbox, as Apple Mail does", async () => {
    await register();
    server = inboxServer({ uidValidity: 7, uidNext: 101 }, "ok", () => [
      { uid: 100, from: "Me <Someone@iCloud.com>", subject: "Note to self" },
    ]);
    await poll();
    expect(apnsCalls[0]?.body).toMatchObject({ aps: { alert: { title: "Me", body: "Note to self" } } });
  });

  it("stays quiet for mail already read or deleted, reading only what arrived", async () => {
    await register();
    server = inboxServer({ uidValidity: 7, uidNext: 104 }, "ok", () => [
      // `100:*` also matches the newest message below 100, which must not count.
      { uid: 99, from: "Dana <dana@example.com>", subject: "Old" },
      { uid: 101, flags: ["\\Seen"], from: "Dana <dana@example.com>", subject: "Read" },
      { uid: 102, flags: ["\\Deleted"], from: "Dana <dana@example.com>", subject: "Deleted" },
    ]);
    imap.sessions.length = 0;
    await poll();
    expect(apnsCalls).toHaveLength(0);
    expect(imap.sessions[0]?.lines).toContain("g4 UID FETCH 100:* (UID FLAGS BODY.PEEK[HEADER.FIELDS (FROM SUBJECT)])");
    expect((await findWatch(env.DB, WATCH_ID))?.inbox.uidNext).toBe(104);
  });

  it("alerts with the newest email's decoded sender and subject", async () => {
    await register();
    server = inboxServer({ uidValidity: 7, uidNext: 102 }, "ok", () => [
      { uid: 100, from: "Dana <dana@example.com>", subject: "First" },
      { uid: 101, from: "=?UTF-8?B?16DXldei?= <noa@example.com>", subject: "=?UTF-8?Q?=D7=A9=D7=9C=D7=95=D7=9D?=" },
    ]);
    await poll();
    expect(apnsCalls[0]?.body).toMatchObject({ aps: { alert: { title: "נוע", body: "שלום" } } });
  });

  it("tries again on the next check when the server can't answer the new-mail check", async () => {
    await register();
    const plain = inboxServer({ uidValidity: 7, uidNext: 102 });
    server = (tag, command) => (command.startsWith("UID FETCH") ? [`${tag} BAD no`] : plain(tag, command));
    await poll();
    expect(apnsCalls).toHaveLength(0);
    expect((await findWatch(env.DB, WATCH_ID))?.inbox.uidNext).toBe(100);
    server = plain;
    await poll();
    expect(apnsCalls).toHaveLength(1);
  });

  it("stays quiet when nothing arrived", async () => {
    await register();
    await poll();
    expect(apnsCalls).toHaveLength(0);
  });

  it("starts again without alerting when UIDVALIDITY changes", async () => {
    await register();
    server = inboxServer({ uidValidity: 8, uidNext: 5 });
    await poll();
    expect(apnsCalls).toHaveLength(0);
    expect((await findWatch(env.DB, WATCH_ID))?.inbox).toEqual({ uidValidity: 8, uidNext: 5 });
  });

  it("looks at a mailbox once for every device watching it", async () => {
    await register();
    await register({ watchId: OTHER_WATCH_ID, deviceToken: OTHER_DEVICE });
    server = inboxServer({ uidValidity: 7, uidNext: 101 });
    imap.sessions.length = 0;
    await poll();
    expect(imap.sessions).toHaveLength(1);
    expect(apnsCalls.map((call) => call.url.split("/").pop()).sort()).toEqual([DEVICE, OTHER_DEVICE]);
  });

  it("tries a refused login again later, waiting longer each time", async () => {
    await register();
    server = inboxServer({ uidValidity: 7, uidNext: 100 }, "refused");
    await poll();
    expect((await findWatch(env.DB, WATCH_ID))?.state).toEqual({ kind: "refused", refusals: 1, refusedAt: NOW });
    imap.sessions.length = 0;
    await poll(NOW + 60_000);
    expect(imap.sessions).toHaveLength(0);
    await poll(NOW + 5 * 60_000);
    expect(imap.sessions).toHaveLength(1);
    expect((await findWatch(env.DB, WATCH_ID))?.state).toMatchObject({ kind: "refused", refusals: 2 });
    await poll(NOW + 10 * 60_000);
    expect(imap.sessions).toHaveLength(1);
    await poll(NOW + 20 * 60_000);
    expect(imap.sessions).toHaveLength(2);
  });

  it("watches again once the server takes a refused login, alerting for mail that arrived meanwhile", async () => {
    await register();
    server = inboxServer({ uidValidity: 7, uidNext: 100 }, "refused");
    await poll();
    server = inboxServer({ uidValidity: 7, uidNext: 102 });
    await poll(NOW + 5 * 60_000);
    expect(await findWatch(env.DB, WATCH_ID)).toMatchObject({ state: { kind: "watching" }, inbox: { uidNext: 102 } });
    expect(apnsCalls).toHaveLength(1);
  });

  it("puts every device's watch on a mailbox back to watching together", async () => {
    await register();
    await register({ watchId: OTHER_WATCH_ID, deviceToken: OTHER_DEVICE });
    server = inboxServer({ uidValidity: 7, uidNext: 100 }, "refused");
    await poll();
    expect((await findWatch(env.DB, OTHER_WATCH_ID))?.state.kind).toBe("refused");
    server = inboxServer({ uidValidity: 7, uidNext: 100 });
    await poll(NOW + 5 * 60_000);
    expect((await findWatch(env.DB, WATCH_ID))?.state.kind).toBe("watching");
    expect((await findWatch(env.DB, OTHER_WATCH_ID))?.state.kind).toBe("watching");
  });

  it("alerts on the next check when APNs failed", async () => {
    await register();
    server = inboxServer({ uidValidity: 7, uidNext: 101 });
    apnsReplies.set(DEVICE, new Response(JSON.stringify({ reason: "InternalServerError" }), { status: 500 }));
    await poll();
    expect((await findWatch(env.DB, WATCH_ID))?.inbox.uidNext).toBe(100);
    apnsReplies.clear();
    await poll();
    expect(apnsCalls).toHaveLength(2);
    expect((await findWatch(env.DB, WATCH_ID))?.inbox.uidNext).toBe(101);
  });

  it("forgets a device APNs says is gone", async () => {
    await register();
    server = inboxServer({ uidValidity: 7, uidNext: 101 });
    apnsReplies.set(DEVICE, new Response(JSON.stringify({ reason: "Unregistered" }), { status: 410 }));
    await poll();
    expect(await findWatch(env.DB, WATCH_ID)).toBeUndefined();
  });

  it("drops watches whose device stopped renewing them", async () => {
    await register();
    await poll(NOW + WATCH_LIFETIME_MS + 1);
    expect(await findWatch(env.DB, WATCH_ID)).toBeUndefined();
  });
});

describe("holding the Inboxes", () => {
  const idling = (session: number) => () => imap.sessions[session]?.lines.some((line) => line.endsWith(" IDLE"));
  const holding = (watchMs: number, restMs = 0) => new InboxWatches(testEnv, alerts(), imap.connect, { watchMs, restMs });

  it("watches a due mailbox on one connection, alerting as soon as the server announces mail", async () => {
    await register();
    const inbox = { uidValidity: 7, uidNext: 100 };
    server = inboxServer(inbox);
    imap.sessions.length = 0;
    const started = await holding(4_500).start(NOW);
    await vi.waitUntil(idling(0));
    inbox.uidNext = 101;
    imap.announce("* 4 EXISTS");
    await vi.waitUntil(() => apnsCalls.length === 1);
    await Promise.all(started);
    expect(imap.sessions).toHaveLength(1);
  });

  it("leaves a mailbox it is watching alone, and watches it again once that watch has ended", async () => {
    await register();
    imap.sessions.length = 0;
    const watches = holding(4_500);
    const started = await watches.start(NOW);
    expect(await watches.start(NOW)).toHaveLength(0);
    await Promise.all(started);
    await Promise.all(await watches.start(NOW));
    expect(imap.sessions).toHaveLength(2);
  });

  it("alerts a device that started watching the mailbox after the connection was opened", async () => {
    await register();
    const inbox = { uidValidity: 7, uidNext: 100 };
    server = inboxServer(inbox);
    imap.sessions.length = 0;
    const started = await holding(4_500).start(NOW);
    await vi.waitUntil(idling(0));
    await register({ watchId: OTHER_WATCH_ID, deviceToken: OTHER_DEVICE });
    inbox.uidNext = 101;
    imap.announce("* 4 EXISTS");
    await Promise.all(started);
    expect(apnsCalls.map((call) => call.url.split("/").pop()).sort()).toEqual([DEVICE, OTHER_DEVICE]);
  });

  it("gives every mailbox a turn when there are more than it watches at once", async () => {
    const logins = Array.from({ length: MOST_AT_ONCE + 1 }, (_, index) => `someone${index}@icloud.com`);
    for (const [index, username] of logins.entries()) {
      const watchId = `${index}${WATCH_ID.slice(1)}`;
      expect((await register({ watchId, username }, `198.51.100.${index}`)).status).toBe(204);
    }
    imap.sessions.length = 0;
    const watches = holding(0);
    await Promise.all(await watches.start(NOW));
    await Promise.all(await watches.start(NOW));
    const watched = imap.sessions.map((session) => session.login.username);
    expect(watched).toHaveLength(2 * MOST_AT_ONCE);
    expect(new Set(watched)).toEqual(new Set(logins));
  });

  it("lets a mailbox rest before logging in again when its watch ended early", async () => {
    await register();
    imap.sessions.length = 0;
    const watches = holding(0, 60_000);
    await Promise.all(await watches.start(NOW));
    expect(await watches.start(NOW)).toHaveLength(0);
    expect(imap.sessions).toHaveLength(1);
  });

  it("waits out a refused login as the cron run does", async () => {
    await register();
    server = inboxServer({ uidValidity: 7, uidNext: 100 }, "refused");
    const watches = holding(0);
    await Promise.all(await watches.start(NOW));
    expect((await findWatch(env.DB, WATCH_ID))?.state).toEqual({ kind: "refused", refusals: 1, refusedAt: NOW });
    expect(await watches.start(NOW + 60_000)).toHaveLength(0);
    const again = await watches.start(NOW + 5 * 60_000);
    expect(again).toHaveLength(1);
    await Promise.all(again);
  });
});
