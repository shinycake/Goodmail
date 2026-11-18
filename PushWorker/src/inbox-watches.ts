import type { ApnsSigner } from "./apns";
import type { Env } from "./env";
import type { Connect } from "./imap";
import { label, MOST_AT_ONCE, watchMailbox } from "./imap-poll";
import { loginsDue, type WatchedLogin } from "./imap-watches";

export { MOST_AT_ONCE };

/** How the holder paces its watches. Tests pass shorter times. */
export interface HoldPace {
  /** How long one watch holds its connection. */
  watchMs: number;
  /**
   * The least time between two logins to one mailbox, as far apart as the cron runs were. A watch can end early, on
   * a server without IDLE or one that drops the connection, and logging in again every beat could get the account
   * locked.
   */
  restMs: number;
}

/**
 * The Inboxes being watched over connections that stay open, one per login: what the holder (inbox-holder.ts) keeps
 * in memory. Each watch lasts `pace.watchMs`, then ends, and the next `start` opens a new one.
 */
export class InboxWatches {
  /** The logins being watched now, by `loginHash`. */
  private readonly watching = new Set<string>();
  /** When each login's latest watch started, so the one that waited longest goes first. */
  private readonly startedAt = new Map<string, number>();

  constructor(
    private readonly env: Env,
    private readonly signer: ApnsSigner,
    private readonly open: Connect,
    private readonly pace: HoldPace,
  ) {}

  /**
   * Starts watching the logins due at `now` that aren't being watched and have rested, up to `MOST_AT_ONCE` at a
   * time; with more, each gets its turn as watches end. Returns the watches it started, each settling when it ends,
   * never rejecting.
   */
  async start(now: number): Promise<Promise<void>[]> {
    const lastStart = (login: WatchedLogin) => this.startedAt.get(login.loginHash) ?? 0;
    const rested = Date.now() - this.pace.restMs;
    const waiting = (await loginsDue(this.env.DB, now))
      .filter((login) => !this.watching.has(login.loginHash) && lastStart(login) <= rested)
      .sort((a, b) => lastStart(a) - lastStart(b));
    return waiting.slice(0, MOST_AT_ONCE - this.watching.size).map((login) => this.watch(login, now));
  }

  private async watch(login: WatchedLogin, now: number): Promise<void> {
    const started = Date.now();
    this.watching.add(login.loginHash);
    this.startedAt.set(login.loginHash, started);
    try {
      await watchMailbox(this.env, this.signer, login, now, started + this.pace.watchMs, this.open);
    } catch (error) {
      console.warn(`An Inbox watch failed: ${error instanceof Error ? error.message : String(error)}`);
    } finally {
      this.watching.delete(login.loginHash);
      console.log(`Inbox watch with login ${label(login.loginHash)} ended after ${Math.round((Date.now() - started) / 1000)} s`);
    }
  }
}
