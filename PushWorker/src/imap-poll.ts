import { accountMailPayload, type ApnsSigner, sendPush } from "./apns";
import type { Env } from "./env";
import { type Connect, connectToServer, type ImapLogin, inboxStatus, LoginRefused } from "./imap";
import { advanceWatch, type ImapWatch, loginSealer, refuseLogin, watchesDue } from "./imap-watches";
import { forgetDeviceToken } from "./tokens";

/** Mailboxes looked at at once. A Worker may hold six connections, and APNs needs one too. */
const CONCURRENCY = 4;

/**
 * The cron trigger's work: looks at every watched Inbox once, and alerts each watching device when its UIDNEXT grew,
 * as only new mail makes it (a read, flag, archive or delete never does). A changed UIDVALIDITY renumbers the Inbox,
 * so it is taken as the new start without alerting.
 */
export async function pollWatches(env: Env, signer: ApnsSigner, now: number, open: Connect = connectToServer) {
  const byLogin = new Map<string, ImapWatch[]>();
  for (const watch of await watchesDue(env.DB, now)) {
    byLogin.set(watch.loginHash, [...(byLogin.get(watch.loginHash) ?? []), watch]);
  }
  const groups = [...byLogin.values()];
  const workers = Array.from({ length: Math.min(CONCURRENCY, groups.length) }, async () => {
    for (let group = groups.shift(); group; group = groups.shift()) await pollMailbox(env, signer, group, open);
  });
  await Promise.all(workers);
}

/** Looks at one mailbox, which every watch in `watches` shares the login of. */
async function pollMailbox(env: Env, signer: ApnsSigner, watches: ImapWatch[], open: Connect) {
  const first = watches[0]!;
  const sealed = await loginSealer(env.EMAIL_HMAC_SECRET).open(first.login);
  if (sealed === undefined) return console.warn("An IMAP login couldn't be opened");
  let inbox;
  try {
    inbox = await inboxStatus(JSON.parse(sealed) as ImapLogin, open);
  } catch (error) {
    if (error instanceof LoginRefused) return refuseLogin(env.DB, first.loginHash);
    return console.warn(`IMAP check failed: ${error instanceof Error ? error.message : String(error)}`);
  }
  await Promise.all(
    watches.map(async (watch) => {
      const before = watch.inbox;
      if (before.uidValidity === inbox.uidValidity && before.uidNext === inbox.uidNext) return;
      if (!(await advanceWatch(env.DB, watch.watchId, before, inbox))) return;
      const arrived = before.uidValidity === inbox.uidValidity && inbox.uidNext > before.uidNext;
      if (!arrived) return;
      const outcome = await sendPush(signer, watch.device, accountMailPayload(watch.account));
      if (outcome === "gone") await forgetDeviceToken(env.DB, watch.device.token);
      // The next check alerts for it instead.
      if (outcome === "failed") await advanceWatch(env.DB, watch.watchId, inbox, before);
    }),
  );
}
