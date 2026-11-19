import { env } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Env } from "../src/env";
import { HANDLED_GAP_MS, HandledPushes } from "../src/handled";
import { generateApnsKey } from "./keys";

const PHONE = { token: "a".repeat(64), environment: "sandbox" as const };

describe("quiet pushes", () => {
  let sent: unknown[];
  let testEnv: Env;
  let clock: number;
  let waits: number[];

  beforeEach(async () => {
    testEnv = { ...env, APNS_PRIVATE_KEY: (await generateApnsKey()).pem };
    sent = [];
    clock = 1_000_000;
    waits = [];
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
      sent.push(await new Request(input, init).json());
      return new Response(null, { status: 200 });
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  const pushes = () =>
    new HandledPushes(
      () => clock,
      async (ms) => {
        waits.push(ms);
        // Time passes only after the caller let others run, as a real timer's does.
        await Promise.resolve();
        clock += ms;
      },
    );

  it("folds a burst into one push now and one at the end of the gap", async () => {
    const spacing = pushes();
    await spacing.send(testEnv, PHONE, { accountID: "a1" });
    clock += 1_000;
    await Promise.all([
      spacing.send(testEnv, PHONE, { accountID: "a1" }),
      spacing.send(testEnv, PHONE, { accountID: "a1" }),
    ]);
    expect(sent).toHaveLength(2);
    expect(waits).toEqual([HANDLED_GAP_MS - 1_000]);
  });

  it("spaces each account on a device on its own", async () => {
    const spacing = pushes();
    await spacing.send(testEnv, PHONE, { accountID: "a1" });
    await spacing.send(testEnv, PHONE, { account: "me@gmail.com", historyId: "9" });
    expect(sent).toHaveLength(2);
    expect(waits).toEqual([]);
  });
});
