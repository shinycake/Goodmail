import { DurableObject } from "cloudflare:workers";
import { signerFor } from "./apns";
import type { Env } from "./env";
import { connectToServer } from "./imap";
import { pollWatches } from "./imap-poll";
import { InboxWatches } from "./inbox-watches";

/** How often the holder looks for Inboxes to start watching. */
export const BEAT_MS = 60_000;

/**
 * How long one connection is held before the holder logs in again: 48 logins a day for each mailbox. A connection
 * stayed open for 46 minutes in a trial on the free plan (2026-11-18), until the trial ended it. Ten seconds short
 * of 30 beats, so a watch has logged out by the beat that starts the next one, whose first STATUS catches mail that
 * arrived in between.
 */
export const HOLD_MS = 30 * BEAT_MS - 10_000;

/** A mailbox whose watch ended early is logged in to again this long after that watch started, as a cron run would. */
const REST_MS = 5 * BEAT_MS;

/** What the cron run needs of the holder. */
export interface Holder {
  wake(): Promise<void>;
}

/**
 * Keeps a connection open to every watched IMAP Inbox, so mail alerts within seconds at any time. There is one
 * holder, and it stays in memory: its alarm goes off every `BEAT_MS`, starting a watch on each Inbox that is due and
 * has none (`InboxWatches`). What is being watched lives in memory only. When the object is restarted, the alarm
 * wakes the new one within a beat and it logs in again, and the first STATUS of each watch alerts for mail that
 * arrived meanwhile.
 */
export class InboxHolder extends DurableObject<Env> implements Holder {
  private readonly watches = new InboxWatches(this.env, signerFor(this.env), connectToServer, { watchMs: HOLD_MS, restMs: REST_MS });

  /** Starts the beat when it isn't running: the first time ever, and after an alarm was lost. */
  async wake(): Promise<void> {
    if ((await this.ctx.storage.getAlarm()) === null) await this.beat();
  }

  override async alarm(): Promise<void> {
    await this.beat();
  }

  /** Asks for the next beat first, so a failure here costs one beat and never the beat itself. */
  private async beat(): Promise<void> {
    const now = Date.now();
    await this.ctx.storage.setAlarm(now + BEAT_MS);
    try {
      await this.watches.start(now);
    } catch (error) {
      console.warn(`The holder couldn't start watching: ${error instanceof Error ? error.message : String(error)}`);
    }
  }
}

/**
 * The cron run's work: wakes the holder, which does the watching. When the holder can't be reached, as on a day the
 * account's free Durable Object time ran out, this run watches the Inboxes itself until the next one (`pollWatches`).
 */
export async function keepInboxesWatched(
  env: Env,
  now: number,
  holder: Holder = env.INBOX_HOLDER.getByName("inboxes"),
  watch: () => Promise<void> = () => pollWatches(env, signerFor(env), now),
): Promise<void> {
  try {
    await holder.wake();
  } catch (error) {
    console.warn(`The Inbox holder can't be reached: ${error instanceof Error ? error.message : String(error)}`);
    await watch();
  }
}
