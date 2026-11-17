import { createExecutionContext, env, waitOnExecutionContext } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { ApnsSigner, type Device } from "../src/apns";
import { Alerts, FALLBACK_MS, pruneAlerts } from "../src/fallback";
import worker, { type Env } from "../src/index";
import { generateApnsKey } from "./keys";

const PHONE = "a".repeat(64);
const WATCH = "b".repeat(64);
const TOPICS = { app: "com.idanbirman.goodmail", watch: "com.idanbirman.goodmail.watchkitapp" };
const MAIL = { sender: "Dana Levi", subject: "Lunch?", threadID: "t1" };

let testEnv: Env;
let signer: ApnsSigner;
let pushes: { token: string; topic: string | null; collapse: string | null; body: { alert?: string } }[];
/** APNs' status for each token; 200 when not set. */
let statuses: Map<string, number>;

beforeAll(async () => {
  const key = await generateApnsKey();
  testEnv = { ...env, APNS_PRIVATE_KEY: key.pem };
  signer = new ApnsSigner({ keyId: "KEY1234567", teamId: "TEAM123456", privateKey: key.pem });
});

beforeEach(async () => {
  await env.DB.prepare("DELETE FROM acks").run();
  await env.DB.prepare("DELETE FROM devices").run();
  pushes = [];
  statuses = new Map();
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const request = new Request(input, init);
    const token = new URL(request.url).pathname.split("/").pop() ?? "";
    pushes.push({
      token,
      topic: request.headers.get("apns-topic"),
      collapse: request.headers.get("apns-collapse-id"),
      body: await request.json(),
    });
    const status = statuses.get(token) ?? 200;
    return new Response(status === 410 ? JSON.stringify({ reason: "Unregistered" }) : null, { status });
  });
});

afterEach(() => {
  vi.restoreAllMocks();
});

/**
 * Alerts whose fallback waits until `elapse` is called, as if the 8 seconds passed then, and whose kept-alive work
 * `settled` waits for.
 */
function clocked() {
  let elapse = () => {};
  const elapsed = new Promise<void>((resolve) => (elapse = resolve));
  const work: Promise<unknown>[] = [];
  const waits: number[] = [];
  const alerts = new Alerts(
    env.DB,
    signer,
    TOPICS,
    (promise) => work.push(promise),
    (ms) => {
      waits.push(ms);
      return elapsed;
    },
  );
  return { alerts, elapse, waits, settled: () => Promise.all(work) };
}

const withWatch: Device = { token: PHONE, environment: "sandbox", watchToken: WATCH };

async function acknowledge(alert: unknown): Promise<Response> {
  const context = createExecutionContext();
  const request = new Request("https://push.example.test/v1/acks", { method: "POST", body: JSON.stringify({ alert }) });
  const response = await worker.fetch(request, testEnv, context);
  await waitOnExecutionContext(context);
  return response;
}

async function delivery(alert: string) {
  return (await env.DB.prepare("SELECT delivery FROM acks WHERE alert_id = ?1").bind(alert).first<{ delivery: string }>())
    ?.delivery;
}

describe("falling back to the watch", () => {
  it("sends nothing to the watch when the iPhone confirms in time", async () => {
    const { alerts, elapse, settled, waits } = clocked();
    expect(await alerts.send(withWatch, MAIL, { accountID: "a1" })).toBe("delivered");
    const alert = pushes[0]!.body.alert!;

    expect((await acknowledge(alert)).status).toBe(204);
    elapse();
    await settled();

    expect(waits).toEqual([FALLBACK_MS]);
    expect(pushes.map((push) => push.token)).toEqual([PHONE]);
    expect(await delivery(alert)).toBe("confirmed");
  });

  it("sends the same alert once to the watch, with the watch's topic, when the iPhone stays silent", async () => {
    const { alerts, elapse, settled } = clocked();
    await alerts.send(withWatch, MAIL, { accountID: "a1" });
    elapse();
    await settled();

    expect(pushes).toHaveLength(2);
    const [phone, watch] = pushes;
    expect(phone).toMatchObject({ token: PHONE, topic: TOPICS.app });
    expect(watch).toMatchObject({ token: WATCH, topic: TOPICS.watch, collapse: phone!.collapse });
    expect(watch!.body).toEqual(phone!.body);
    expect(watch!.body).toMatchObject({ alert: phone!.collapse, threadID: "t1" });
    expect(await delivery(phone!.body.alert!)).toBe("fellBack");
  });

  it("sends nothing more, and keeps nothing, for a device without a watch", async () => {
    const { alerts, elapse, settled, waits } = clocked();
    await alerts.send({ token: PHONE, environment: "sandbox" }, MAIL, { accountID: "a1" });
    elapse();
    await settled();

    expect(pushes.map((push) => push.token)).toEqual([PHONE]);
    expect(waits).toEqual([]);
    expect((await env.DB.prepare("SELECT COUNT(*) AS count FROM acks").first<{ count: number }>())?.count).toBe(0);
  });

  it("takes a confirmation that comes after the fallback, and changes nothing", async () => {
    const { alerts, elapse, settled } = clocked();
    await alerts.send(withWatch, MAIL, { accountID: "a1" });
    elapse();
    await settled();
    const alert = pushes[0]!.body.alert!;

    expect((await acknowledge(alert)).status).toBe(204);
    expect(await delivery(alert)).toBe("fellBack");
    expect(pushes).toHaveLength(2);
  });

  it("forgets a watch token APNs calls gone, keeping the iPhone's registration", async () => {
    await env.DB.prepare(
      "INSERT INTO devices (account, device_token, environment, updated_at, watch_token) VALUES ('acc', ?1, 'sandbox', 0, ?2)",
    )
      .bind(PHONE, WATCH)
      .run();
    statuses.set(WATCH, 410);
    const { alerts, elapse, settled } = clocked();
    await alerts.send(withWatch, MAIL, { accountID: "a1" });
    elapse();
    await settled();

    expect(await env.DB.prepare("SELECT device_token, watch_token FROM devices").all()).toMatchObject({
      results: [{ device_token: PHONE, watch_token: null }],
    });
  });

  it("sends nothing to the watch when the iPhone's app is gone", async () => {
    statuses.set(PHONE, 410);
    const { alerts, elapse, settled, waits } = clocked();
    expect(await alerts.send(withWatch, MAIL, { accountID: "a1" })).toBe("gone");
    elapse();
    await settled();

    expect(pushes.map((push) => push.token)).toEqual([PHONE]);
    expect(waits).toEqual([]);
  });
});

describe("confirmations", () => {
  it("answers an unknown alert the same as a known one", async () => {
    expect((await acknowledge(crypto.randomUUID())).status).toBe(204);
  });

  it("refuses what isn't an alert ID", async () => {
    expect((await acknowledge("not-an-id")).status).toBe(400);
    expect((await acknowledge(42)).status).toBe(400);
  });

  it("are pruned after a day", async () => {
    const now = Date.now();
    await env.DB.batch([
      env.DB.prepare("INSERT INTO acks (alert_id, sent_at, delivery) VALUES ('old', ?1, 'sent')").bind(now - 86_400_001),
      env.DB.prepare("INSERT INTO acks (alert_id, sent_at, delivery) VALUES ('new', ?1, 'sent')").bind(now - 60_000),
    ]);

    await pruneAlerts(env.DB, now);

    const { results } = await env.DB.prepare("SELECT alert_id FROM acks").all<{ alert_id: string }>();
    expect(results.map((row) => row.alert_id)).toEqual(["new"]);
  });
});
