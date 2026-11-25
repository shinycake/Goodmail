import type { Env } from "./env";
import type { Alerts } from "./fallback";
import { sendHandled } from "./handled";
import {
  type Connect,
  connectToServer,
  type FreshMail,
  type ImapLogin,
  type InboxStatus,
  LoginRefused,
  watchInbox,
} from "./imap";
import { recordRefusal, recordTaken } from "./imap-logins";
import { advanceWatch, type ImapWatch, loginsDue, loginSealer, type WatchedLogin, watchesOn } from "./imap-watches";

/** Mailboxes watched at once. A Worker may hold six connections, and APNs needs one too. */
export const MOST_AT_ONCE = 4;

/**
 * How long each run watches: the cron starts one every 5 minutes (wrangler.toml), and each holds IDLE until just
 * before the next, so a mailbox costs one login per 5 minutes and alerts within seconds.
 */
export const WATCH_MS = 290_000;

/**
 * A cron run that watches the Inboxes itself, as every run did before the holder (inbox-holder.ts) and as one still
 * does when the holder can't be reached: logs in to every watched Inbox once, then watches each (`watchMailbox`)
 * until `now + watchMs`. Mailboxes beyond `MOST_AT_ONCE` wait their turn and are only checked once, if the time is up
 * by then.
 */
export async function pollWatches(
  env: Env,
  alerts: Alerts,
  now: number,
  open: Connect = connectToServer,
  watchMs = WATCH_MS,
) {
  const until = Date.now() + watchMs;
  const logins = await loginsDue(env.DB, now);
  const mailboxes = logins.length;
  const workers = Array.from({ length: Math.min(MOST_AT_ONCE, logins.length) }, async () => {
    for (let login = logins.shift(); login; login = logins.shift()) {
      await watchMailbox(env, alerts, login, now, until, open);
    }
  });
  await Promise.all(workers);
  console.log(`IMAP run ended: ${mailboxes} mailboxes`);
}

/**
 * Logs in to one Inbox, alerts for mail that arrived since the last check, then watches it with IDLE until `until`,
 * alerting as mail arrives. Each device watching with the login is alerted when its Inbox's UIDNEXT grew, as only new
 * mail makes it (a read, flag, archive or delete never does). A changed UIDVALIDITY renumbers the Inbox, so it is
 * taken as the new start without alerting. A login the server refuses is tried again later (`isDue`), and watches
 * again as soon as the server takes it. `now` is when the check started.
 */
export async function watchMailbox(
  env: Env,
  alerts: Alerts,
  login: WatchedLogin,
  now: number,
  until: number,
  open: Connect,
) {
  const sealed = await loginSealer(env.EMAIL_HMAC_SECRET).open(login.login);
  if (sealed === undefined) return console.warn("An IMAP login couldn't be opened");
  try {
    const onStatus = async (inbox: InboxStatus, fresh: FreshMail) => {
      // The server took the login: one it refused before watches again.
      if (await recordTaken(env.DB, login.loginHash)) console.log(`IMAP login ${label(login.loginHash)} taken again`);
      // Read each time: devices start and stop watching while the connection is held, and another check may have
      // moved a watch. One at a time: the new-mail check talks over the one connection.
      for (const watch of await watchesOn(env.DB, login.loginHash)) await alert(env, alerts, watch, inbox, fresh);
    };
    // Mail read, moved or deleted in another app: each watching device takes down the alerts it no longer needs.
    // Best effort: a failure here must never end the watch that finds new mail.
    const onHandled = async () => {
      try {
        const watches = await watchesOn(env.DB, login.loginHash);
        await Promise.all(watches.map((watch) => sendHandled(env, watch.device, { accountID: watch.account })));
      } catch (error) {
        console.warn(`IMAP handled push failed: ${error instanceof Error ? error.message : String(error)}`);
      }
    };
    await watchInbox(JSON.parse(sealed) as ImapLogin, until, onStatus, open, {}, onHandled);
  } catch (error) {
    if (error instanceof LoginRefused) {
      const refused = await recordRefusal(env.DB, login.loginHash, now);
      // None when no watch uses the login any more.
      const inARow = refused ? ` (${refused.refusals} in a row)` : "";
      return console.warn(`IMAP login ${label(login.loginHash)} refused${inARow}: ${error.message}`);
    }
    return console.warn(`IMAP check failed: ${error instanceof Error ? error.message : String(error)}`);
  }
}

/** The start of a watch's ID or a login's hash: enough to find its rows from a log line, and no secret. */
export function label(id: string): string {
  return id.slice(0, 8);
}

/** Mail this far below UIDNEXT and older is left alone: after a long gap, only the newest is worth an alert. */
const MOST_CHECKED = 50;

/**
 * Moves `watch` to `inbox`, alerting its device with the newest mail that arrived and that the app alerts for
 * (`FreshMail`): mail read or deleted before the check stays quiet. A watch without a position yet takes this one
 * as its start. Mail the server couldn't be asked about, or an alert APNs didn't take, moves the watch back, so the
 * next STATUS or check tries again.
 */
async function alert(env: Env, alerts: Alerts, watch: ImapWatch, inbox: InboxStatus, fresh: FreshMail) {
  const before = watch.inbox;
  if (before?.uidValidity === inbox.uidValidity && before.uidNext === inbox.uidNext) return;
  if (!(await advanceWatch(env.DB, watch.watchId, before, inbox))) return;
  if (before === null || before.uidValidity !== inbox.uidValidity || inbox.uidNext <= before.uidNext) return;
  const arrival = await fresh(Math.max(before.uidNext, inbox.uidNext - MOST_CHECKED));
  if (arrival.kind === "none") return;
  const outcome =
    arrival.kind === "mail" ? await alerts.send(watch.device, arrival.newest, { accountID: watch.account }) : "failed";
  console.log(`IMAP alert for watch ${label(watch.watchId)}: ${arrival.kind === "mail" ? outcome : "couldn't read the mail"}`);
  if (outcome === "failed") await advanceWatch(env.DB, watch.watchId, inbox, before);
}
