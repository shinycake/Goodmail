import { createExecutionContext, env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import { concat, sha256 } from "../src/app-attest";
import { ASSERTION_HEADER, KEY_HEADER, registerKey, TIME_HEADER } from "../src/attest-routes";
import { encodeUtf8 } from "../src/encoding";
import worker, { type Env } from "../src/index";
import { assert, attest, base64, type FakeApple, fakeApple, type FakeKey, fakeKey, NOW } from "./attest-fixtures";

const RELAY = "https://push.example.test";

let apple: FakeApple;
let enforcing: Env;

beforeAll(async () => {
  apple = await fakeApple();
  enforcing = { ...env, APP_ATTEST: "enforce" };
});

beforeEach(async () => {
  await env.DB.batch([env.DB.prepare("DELETE FROM attest_keys"), env.DB.prepare("DELETE FROM attest_challenges")]);
});

function challengeRequest(address: string): Request {
  return new Request(`${RELAY}/v1/attest/challenges`, { method: "POST", headers: { "cf-connecting-ip": address } });
}

let addresses = 0;

/** A challenge, asked from an address of its own so the per-address limit stays out of the way. */
async function challenge(): Promise<string> {
  addresses += 1;
  const response = await worker.fetch(challengeRequest(`192.0.2.${addresses}`), env, createExecutionContext());
  expect(response.status).toBe(200);
  return ((await response.json()) as { challenge: string }).challenge;
}

function keyRequest(key: FakeKey, attestation: Uint8Array, challenge: string): Request {
  return new Request(`${RELAY}/v1/attest/keys`, {
    method: "POST",
    body: JSON.stringify({ keyId: base64(key.keyId), attestation: base64(attestation), challenge }),
  });
}

/** Attests `key` through the routes, as the app does once per install. */
async function attested(key: FakeKey): Promise<void> {
  const issued = await challenge();
  const response = await registerKey(keyRequest(key, await attest(apple, key, encodeUtf8(issued)), issued), env, Date.now(), apple.root);
  expect(response.status).toBe(204);
}

/** A device route's request, signed by `key` as the app signs it. */
async function signed(key: FakeKey, body: string, time = Date.now(), method = "POST", path = "/v1/devices"): Promise<Request> {
  const clientDataHash = await sha256(concat(encodeUtf8(`${method} ${path}\n${time}\n`), encodeUtf8(body)));
  return new Request(`${RELAY}${path}`, {
    method,
    body,
    headers: {
      [KEY_HEADER]: base64(key.keyId),
      [TIME_HEADER]: String(time),
      [ASSERTION_HEADER]: base64(await assert(key, clientDataHash)),
    },
  });
}

describe("attesting a key", () => {
  it("keeps a key attested for a challenge the relay issued", async () => {
    const key = await fakeKey();
    await attested(key);
    const row = await env.DB.prepare("SELECT environment, counter FROM attest_keys").first();
    expect(row).toEqual({ environment: "production", counter: 0 });
  });

  it("uses a challenge once", async () => {
    const key = await fakeKey();
    const issued = await challenge();
    const attestation = await attest(apple, key, encodeUtf8(issued));
    expect((await registerKey(keyRequest(key, attestation, issued), env, Date.now(), apple.root)).status).toBe(204);
    expect((await registerKey(keyRequest(key, attestation, issued), env, Date.now(), apple.root)).status).toBe(401);
  });

  it("refuses a challenge the relay never issued", async () => {
    const key = await fakeKey();
    const made = "a".repeat(43);
    const response = await registerKey(keyRequest(key, await attest(apple, key, encodeUtf8(made)), made), env, Date.now(), apple.root);
    expect(response.status).toBe(401);
  });

  it("refuses an expired challenge", async () => {
    const key = await fakeKey();
    const issued = await challenge();
    const later = Date.now() + 6 * 60_000;
    const response = await registerKey(keyRequest(key, await attest(apple, key, encodeUtf8(issued)), issued), env, later, apple.root);
    expect(response.status).toBe(401);
  });

  it("refuses a key a fork's chain vouches for", async () => {
    const fork = await fakeApple();
    const key = await fakeKey();
    const issued = await challenge();
    const response = await registerKey(keyRequest(key, await attest(fork, key, encodeUtf8(issued)), issued), env, Date.now(), apple.root);
    expect(response.status).toBe(401);
    expect(await env.DB.prepare("SELECT COUNT(*) AS keys FROM attest_keys").first("keys")).toBe(0);
  });

  it("refuses garbage instead of failing", async () => {
    const key = await fakeKey();
    const issued = await challenge();
    const response = await registerKey(keyRequest(key, encodeUtf8("not cbor at all"), issued), env, Date.now(), apple.root);
    expect(response.status).toBe(401);
  });
});

describe("device routes when enforcing", () => {
  // Past the guard, an empty body is a 400 from the route itself.
  const PASSED = 400;

  it("let through a request the attested app signed", async () => {
    const key = await fakeKey();
    await attested(key);
    const response = await worker.fetch(await signed(key, "{}"), enforcing, createExecutionContext());
    expect(response.status).toBe(PASSED);
    expect(await env.DB.prepare("SELECT counter FROM attest_keys").first("counter")).toBe(1);
  });

  it("ask a request with no signature to attest", async () => {
    const response = await worker.fetch(new Request(`${RELAY}/v1/devices`, { method: "POST", body: "{}" }), enforcing, createExecutionContext());
    expect(response.status).toBe(428);
  });

  it("ask a key the relay doesn't know to attest again", async () => {
    const response = await worker.fetch(await signed(await fakeKey(), "{}"), enforcing, createExecutionContext());
    expect(response.status).toBe(428);
  });

  it("refuse a body other than the one signed", async () => {
    const key = await fakeKey();
    await attested(key);
    const request = await signed(key, "{}");
    const swapped = new Request(request, { body: '{"deviceToken":"evil"}' });
    expect((await worker.fetch(swapped, enforcing, createExecutionContext())).status).toBe(401);
  });

  it("refuse a signature made for another route", async () => {
    const key = await fakeKey();
    await attested(key);
    const request = await signed(key, "{}", Date.now(), "POST", "/v1/imap/watches");
    const moved = new Request(`${RELAY}/v1/devices`, request);
    expect((await worker.fetch(moved, enforcing, createExecutionContext())).status).toBe(401);
  });

  it("refuse a request replayed after ten minutes", async () => {
    const key = await fakeKey();
    await attested(key);
    const request = await signed(key, "{}", Date.now() - 11 * 60_000);
    expect((await worker.fetch(request, enforcing, createExecutionContext())).status).toBe(401);
  });

  it("guard every route only the app calls", async () => {
    const routes = [
      ["POST", "/v1/devices"],
      ["DELETE", "/v1/devices"],
      ["POST", "/v1/gmail/grants"],
      ["POST", "/v1/graph/subscriptions"],
      ["DELETE", "/v1/graph/subscriptions"],
      ["POST", "/v1/graph/grants"],
      ["POST", "/v1/imap/watches"],
      ["DELETE", "/v1/imap/watches"],
    ];
    for (const [method, path] of routes) {
      const response = await worker.fetch(new Request(`${RELAY}${path}`, { method, body: "{}" }), enforcing, createExecutionContext());
      expect(response.status, `${method} ${path}`).toBe(428);
    }
  });
});

describe("device routes when observing", () => {
  it("let unsigned requests through, for builds made before attestation", async () => {
    const observing = { ...env, APP_ATTEST: "observe" };
    const response = await worker.fetch(new Request(`${RELAY}/v1/devices`, { method: "POST", body: "{}" }), observing, createExecutionContext());
    expect(response.status).toBe(400);
  });

  it("enforce when the mode is anything else", async () => {
    const mistyped = { ...env, APP_ATTEST: "Observe" };
    const response = await worker.fetch(new Request(`${RELAY}/v1/devices`, { method: "POST", body: "{}" }), mistyped, createExecutionContext());
    expect(response.status).toBe(428);
  });
});

describe("challenges", () => {
  it("are 32 random bytes in URL-safe base64", async () => {
    const first = await challenge();
    expect(first).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(await challenge()).not.toBe(first);
  });

  it("are limited per client address", async () => {
    const statuses = [];
    for (let i = 0; i < 11; i++) statuses.push((await worker.fetch(challengeRequest("198.51.100.7"), env, createExecutionContext())).status);
    expect(statuses.slice(0, 10).every((status) => status === 200)).toBe(true);
    expect(statuses[10]).toBe(429);
  });

  it("clear out expired ones and keys unused for half a year", async () => {
    await env.DB.batch([
      env.DB.prepare("INSERT INTO attest_challenges (challenge, expires_at) VALUES ('old', 1)"),
      env.DB.prepare(
        "INSERT INTO attest_keys (key_id, public_key, environment, counter, created_at, last_used_at) VALUES ('gone', x'00', 'production', 0, 1, 1)",
      ),
    ]);
    await challenge();
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM attest_challenges WHERE challenge = 'old'").first("n")).toBe(0);
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM attest_keys").first("n")).toBe(0);
  });
});

// NOW keeps the fixtures' certificates valid; the routes use the real clock, which is inside that window.
void NOW;
