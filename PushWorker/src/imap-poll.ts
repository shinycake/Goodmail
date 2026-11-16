import { accountMailPayload, type ApnsSigner, sendPush } from "./apns";
import type { Env } from "./env";
import { type Connect, connectToServer, type ImapLogin, type InboxStatus, LoginRefused, watchInbox } from "./imap";
import { advanceWatch, type ImapWatch, loginSealer, refuseLogin, watchesDue } from "./imap-watches";
import { forgetDeviceToken } from "./tokens";

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
  signer: ApnsSigner,
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
    for (let group = groups.shift(); group; group = groups.shift()) await watchMailbox(env, signer, group, until, open);
  });
  await Promise.all(workers);
}

/** Watches one mailbox, which every watch in `watches` shares the login of. */
async function watchMailbox(env: Env, signer: ApnsSigner, watches: ImapWatch[], until: number, open: Connect) {
  const first = watches[0]!;
  const sealed = await loginSealer(env.EMAIL_HMAC_SECRET).open(first.login);
  if (sealed === undefined) return console.warn("An IMAP login couldn't be opened");
  try {
    const onStatus = async (inbox: InboxStatus) => {
      await Promise.all(watches.map((watch) => alert(env, signer, watch, inbox)));
    };
    await watchInbox(JSON.parse(sealed) as ImapLogin, until, onStatus, open);
  } catch (error) {
    if (error instanceof LoginRefused) return refuseLogin(env.DB, first.loginHash);
    return console.warn(`IMAP check failed: ${error instanceof Error ? error.message : String(error)}`);
  }
}

/** Moves `watch` to `inbox`, alerting its device when new mail arrived. Keeps `watch.inbox` as the stored baseline. */
async function alert(env: Env, signer: ApnsSigner, watch: ImapWatch, inbox: InboxStatus) {
  const before = watch.inbox;
  if (before.uidValidity === inbox.uidValidity && before.uidNext === inbox.uidNext) return;
  if (!(await advanceWatch(env.DB, watch.watchId, before, inbox))) return;
  watch.inbox = inbox;
  const arrived = before.uidValidity === inbox.uidValidity && inbox.uidNext > before.uidNext;
  if (!arrived) return;
  const outcome = await sendPush(signer, watch.device, accountMailPayload(watch.account));
  if (outcome === "gone") await forgetDeviceToken(env.DB, watch.device.token);
  // The next STATUS or run alerts for it instead.
  if (outcome === "failed" && (await advanceWatch(env.DB, watch.watchId, inbox, before))) watch.inbox = before;
}
