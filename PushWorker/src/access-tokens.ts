/** Access tokens are reused until this close to expiry. */
const TOKEN_MARGIN_MS = 60_000;

/** An access token that lapses at `expiresAt` (ms since 1970). */
export interface Expiring {
  expiresAt: number;
}

/**
 * One account's access token in this isolate, for the sign-in `signIn` names: being refreshed, or ready. An account
 * without one has no slot.
 */
type Slot<T> = { kind: "refreshing"; signIn: string; token: Promise<T> } | { kind: "ready"; signIn: string; token: T };

/**
 * The access tokens this isolate holds, by account. Requests that need an account's token at once share one refresh,
 * and a token is only ever reused for the sign-in it was refreshed from: once the app signs in again, a refresh still
 * under way for the old sign-in is used by the request that made it and kept by none.
 */
export class AccessTokens<T extends Expiring> {
  private readonly slots = new Map<string, Slot<T>>();

  constructor(private readonly now: () => number) {}

  /** The account's token for `signIn`: the one held while it is good, or the one `refresh` gets, once for everyone. */
  async token(account: string, signIn: string, refresh: () => Promise<T>): Promise<T> {
    const slot = this.slots.get(account);
    if (slot?.signIn === signIn) {
      if (slot.kind === "refreshing") return slot.token;
      if (slot.token.expiresAt - this.now() > TOKEN_MARGIN_MS) return slot.token;
    }
    const mine: Slot<T> = { kind: "refreshing", signIn, token: refresh() };
    this.slots.set(account, mine);
    try {
      const token = await mine.token;
      if (this.slots.get(account) === mine) this.slots.set(account, { kind: "ready", signIn, token });
      return token;
    } catch (error) {
      if (this.slots.get(account) === mine) this.slots.delete(account);
      throw error;
    }
  }

  forget(account: string): void {
    this.slots.delete(account);
  }
}

/** The account's grant moved on to another sign-in while its token was being refreshed: the caller tries again. */
export class GrantChanged extends Error {}
