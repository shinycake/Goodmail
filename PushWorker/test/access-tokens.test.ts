import { describe, expect, it } from "vitest";
import { AccessTokens } from "../src/access-tokens";

const NOW = 1_800_000_000_000;

/** A cache whose refreshes are counted, each answering a token good for an hour once `answer` is called. */
function counted() {
  const tokens = new AccessTokens<{ value: string; expiresAt: number }>(() => NOW);
  const pending: ((value: string) => void)[] = [];
  const refresh = () =>
    new Promise<{ value: string; expiresAt: number }>((resolve) => {
      pending.push((value) => resolve({ value, expiresAt: NOW + 3_600_000 }));
    });
  return { tokens, pending, refresh };
}

describe("access tokens", () => {
  it("refreshes once for requests that need an account's token at the same time, then reuses it", async () => {
    const { tokens, pending, refresh } = counted();
    const both = Promise.all([tokens.token("a1", "sign-in-1", refresh), tokens.token("a1", "sign-in-1", refresh)]);
    expect(pending).toHaveLength(1);
    pending[0]!("t1");
    expect((await both).map((token) => token.value)).toEqual(["t1", "t1"]);
    expect((await tokens.token("a1", "sign-in-1", refresh)).value).toBe("t1");
    expect(pending).toHaveLength(1);
  });

  it("refreshes for a new sign-in, and keeps none from a refresh the new sign-in overtook", async () => {
    const { tokens, pending, refresh } = counted();
    const old = tokens.token("a1", "sign-in-1", refresh);
    const fresh = tokens.token("a1", "sign-in-2", refresh);
    expect(pending).toHaveLength(2);
    pending[1]!("t2");
    pending[0]!("t1");
    expect((await old).value).toBe("t1");
    expect((await fresh).value).toBe("t2");
    expect((await tokens.token("a1", "sign-in-2", refresh)).value).toBe("t2");
    expect(pending).toHaveLength(2);
  });

  it("keeps nothing from a refresh under way when the account is forgotten", async () => {
    const { tokens, pending, refresh } = counted();
    const old = tokens.token("a1", "sign-in-1", refresh);
    tokens.forget("a1");
    pending[0]!("t1");
    await old;
    void tokens.token("a1", "sign-in-1", refresh);
    expect(pending).toHaveLength(2);
  });

  it("refreshes again after a refresh failed", async () => {
    const tokens = new AccessTokens<{ expiresAt: number }>(() => NOW);
    await expect(tokens.token("a1", "s", () => Promise.reject(new Error("down")))).rejects.toThrow("down");
    await expect(tokens.token("a1", "s", async () => ({ expiresAt: NOW + 3_600_000 }))).resolves.toEqual({
      expiresAt: NOW + 3_600_000,
    });
  });

  it("fails every request sharing a refresh that failed, then refreshes again", async () => {
    const tokens = new AccessTokens<{ expiresAt: number }>(() => NOW);
    let refreshes = 0;
    const failing = () => {
      refreshes++;
      return Promise.reject(new Error("down"));
    };
    const waiting = [1, 2, 3].map(() => tokens.token("a1", "s", failing));
    const outcomes = await Promise.allSettled(waiting);
    expect(outcomes.map((outcome) => outcome.status)).toEqual(["rejected", "rejected", "rejected"]);
    expect(refreshes).toBe(1);
    await tokens.token("a1", "s", async () => {
      refreshes++;
      return { expiresAt: NOW + 3_600_000 };
    });
    expect(refreshes).toBe(2);
  });

  it("refreshes a token about to expire", async () => {
    const tokens = new AccessTokens<{ expiresAt: number }>(() => NOW);
    let refreshes = 0;
    const refresh = async () => ({ expiresAt: NOW + 30_000 + refreshes++ });
    await tokens.token("a1", "s", refresh);
    await tokens.token("a1", "s", refresh);
    expect(refreshes).toBe(2);
  });
});
