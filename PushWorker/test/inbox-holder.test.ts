import { env, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { BEAT_MS, type Holder, keepInboxesWatched } from "../src/inbox-holder";

describe("the cron run", () => {
  const watch = vi.fn(async () => {});

  beforeEach(() => {
    watch.mockClear();
  });

  it("only wakes the holder while the holder answers", async () => {
    const holder: Holder = { wake: vi.fn(async () => {}) };
    await keepInboxesWatched(env, 0, holder, watch);
    expect(holder.wake).toHaveBeenCalledOnce();
    expect(watch).not.toHaveBeenCalled();
  });

  it("watches the Inboxes itself when the holder can't be reached", async () => {
    const holder: Holder = {
      wake: async () => {
        throw new Error("Exceeded allowed duration in Durable Objects free tier.");
      },
    };
    await keepInboxesWatched(env, 0, holder, watch);
    expect(watch).toHaveBeenCalledOnce();
  });
});

describe("the holder", () => {
  const holder = env.INBOX_HOLDER.getByName("inboxes");
  const nextBeat = () => runInDurableObject(holder, (_, state) => state.storage.getAlarm());

  beforeEach(async () => {
    await env.DB.prepare("DELETE FROM imap_watches").run();
  });

  it("starts beating when it is woken, and keeps its beat when woken again", async () => {
    const before = Date.now();
    await holder.wake();
    const beat = await nextBeat();
    expect(beat).toBeGreaterThanOrEqual(before + BEAT_MS);
    await holder.wake();
    expect(await nextBeat()).toBe(beat);
  });

  it("asks for the next beat on every beat", async () => {
    await holder.wake();
    expect(await runDurableObjectAlarm(holder)).toBe(true);
    expect(await nextBeat()).not.toBeNull();
  });
});
