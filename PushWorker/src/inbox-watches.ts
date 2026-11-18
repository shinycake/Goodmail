import type { Env } from "./env";
import type { Alerts } from "./fallback";
import type { Connect } from "./imap";
import { label, MOST_AT_ONCE, watchMailbox } from "./imap-poll";
import { loginsDue, type WatchedLogin } from "./imap-watches";

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

/** A login's latest watch: when it started, and whether it is still under way. */
interface Watch {
  startedAt: number;
  active: boolean;
}

/**
 * The Inboxes being watched over connections that stay open, one per login: what the holder (inbox-holder.ts) keeps
 * in memory. Each watch lasts `pace.watchMs`, then ends, and the next `start` opens a new one.
 */
export class InboxWatches {
  /** Each login's latest watch, by `loginHash`. */
  private readonly watches = new Map<string, Watch>();

  constructor(
    private readonly env: Env,
    private readonly alerts: Alerts,
    private readonly open: Connect,
    private readonly pace: HoldPace,
  ) {}

  /**
   * Starts watching the logins due at `now` that aren't being watched and have rested, up to `MOST_AT_ONCE` at a
   * time; with more, the one whose watch started longest ago goes first, so each gets its turn as watches end.
   * Returns the watches it started, each settling when it ends, never rejecting.
   */
  async start(now: number): Promise<Promise<void>[]> {
    const due = await loginsDue(this.env.DB, now);
    this.forgetAllBut(due);
    const lastStart = (login: WatchedLogin) => this.watches.get(login.loginHash)?.startedAt ?? 0;
    const rested = Date.now() - this.pace.restMs;
    const active = [...this.watches.values()].filter((watch) => watch.active).length;
    return due
      .filter((login) => !this.watches.get(login.loginHash)?.active && lastStart(login) <= rested)
      .sort((a, b) => lastStart(a) - lastStart(b))
      .slice(0, Math.max(0, MOST_AT_ONCE - active))
      .map((login) => this.watch(login, now));
  }

  /** Drops the ended watches of logins that aren't in `due`, as after the last device stopped watching with one. */
  private forgetAllBut(due: WatchedLogin[]): void {
    const kept = new Set(due.map((login) => login.loginHash));
    for (const [loginHash, watch] of this.watches) {
      if (!watch.active && !kept.has(loginHash)) this.watches.delete(loginHash);
    }
  }

  private async watch(login: WatchedLogin, now: number): Promise<void> {
    const startedAt = Date.now();
    this.watches.set(login.loginHash, { startedAt, active: true });
    try {
      await watchMailbox(this.env, this.alerts, login, now, startedAt + this.pace.watchMs, this.open);
    } catch (error) {
      console.warn(`An Inbox watch failed: ${error instanceof Error ? error.message : String(error)}`);
    } finally {
      this.watches.set(login.loginHash, { startedAt, active: false });
      console.log(`Inbox watch with login ${label(login.loginHash)} ended after ${Math.round((Date.now() - startedAt) / 1000)} s`);
    }
  }
}
