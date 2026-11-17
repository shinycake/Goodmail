import type { Env } from "./env";
import type { Alerts } from "./fallback";
import {
  type Connect,
  connectToServer,
  type FreshMail,
  type ImapLogin,
  type InboxStatus,
  LoginRefused,
  watchInbox,
} from "./imap";
import { advanceWatch, type ImapWatch, loginSealer, refuseLogin, watchesDue } from "./imap-watches";

/** Mailboxes watched at once. A Worker may hold six connections, and APNs needs one too. */
const CONCURRENCY = 4;

/**
 * How long each run watches: the cron starts one every 5 minutes (wrangler.toml), and each holds IDLE until just
 * before the next, so a mailbox costs one login per 5 minutes and alerts within seconds.
 */
export const WATCH_MS = 290_000;

/**
 * The cron trigger's work: logs in to every watched Inbox once, alerts for mail that arrived since the last run, then
 * watches each with IDLE until `now + watchMs`, alerting as mail arrives. Each watching device is alerted when its
 * Inbox's UIDNEXT grew, as only new mail makes it (a read, flag, archive or delete never does). A changed UIDVALIDITY
 * renumbers the Inbox, so it is taken as the new start without alerting. Mailboxes beyond `CONCURRENCY` wait their
 * turn and are only checked once, if the time is up by then.
 */
export async function pollWatches(
  env: Env,
  alerts: Alerts,
  now: number,
  open: Connect = connectToServer,
  watchMs = WATCH_MS,
) {
  const until = Date.now() + watchMs;
  const byLogin = new Map<string, ImapWatch[]>();
  for (const watch of await watchesDue(env.DB, now)) {
    byLogin.set(watch.loginHash, [...(byLogin.get(watch.loginHash) ?? []), watch]);
  }
  const groups = [...byLogin.values()];
  const workers = Array.from({ length: Math.min(CONCURRENCY, groups.length) }, async () => {
    for (let group = groups.shift(); group; group = groups.shift()) await watchMailbox(env, alerts, group, until, open);
  });
  await Promise.all(workers);
}

/** Watches one mailbox, which every watch in `watches` shares the login of. */
async function watchMailbox(env: Env, alerts: Alerts, watches: ImapWatch[], until: number, open: Connect) {
  const first = watches[0]!;
  const sealed = await loginSealer(env.EMAIL_HMAC_SECRET).open(first.login);
  if (sealed === undefined) return console.warn("An IMAP login couldn't be opened");
  try {
    const onStatus = async (inbox: InboxStatus, fresh: FreshMail) => {
      // One at a time: the new-mail check talks over the one connection.
      for (const watch of watches) await alert(env, alerts, watch, inbox, fresh);
    };
    await watchInbox(JSON.parse(sealed) as ImapLogin, until, onStatus, open);
  } catch (error) {
    if (error instanceof LoginRefused) return refuseLogin(env.DB, first.loginHash);
    return console.warn(`IMAP check failed: ${error instanceof Error ? error.message : String(error)}`);
  }
}

/** Mail this far below UIDNEXT and older is left alone: after a long gap, only the newest is worth an alert. */
const MOST_CHECKED = 50;

/**
 * Moves `watch` to `inbox`, alerting its device with the newest mail that arrived and that the app alerts for
 * (`FreshMail`): mail read or deleted before the check stays quiet. Mail the server couldn't be
 * asked about, or an alert APNs didn't take, moves the watch back, so the next STATUS or run tries again. Keeps
 * `watch.inbox` as the stored baseline.
 */
async function alert(env: Env, alerts: Alerts, watch: ImapWatch, inbox: InboxStatus, fresh: FreshMail) {
  const before = watch.inbox;
  if (before.uidValidity === inbox.uidValidity && before.uidNext === inbox.uidNext) return;
  if (!(await advanceWatch(env.DB, watch.watchId, before, inbox))) return;
  watch.inbox = inbox;
  const arrived = before.uidValidity === inbox.uidValidity && inbox.uidNext > before.uidNext;
  if (!arrived) return;
  const arrival = await fresh(Math.max(before.uidNext, inbox.uidNext - MOST_CHECKED));
  if (arrival.kind === "none") return;
  const outcome =
    arrival.kind === "mail" ? await alerts.send(watch.device, arrival.newest, { accountID: watch.account }) : "failed";
  if (outcome === "failed" && (await advanceWatch(env.DB, watch.watchId, inbox, before))) watch.inbox = before;
}
