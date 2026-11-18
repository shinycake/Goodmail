import type { ApnsEnvironment, Device } from "./apns";
import type { ImapLogin, InboxStatus } from "./imap";
import { Sealer } from "./sealing";

/** How long a watch lasts after its device last registered it. The app registers it on every refresh. */
export const WATCH_LIFETIME_MS = 30 * 86_400_000;

/**
 * `watching`, or `refused` after the server refused the login `refusals` times in a row, the last at `refusedAt` (ms
 * since 1970). A refused login is tried again later (`isDue`), since a server can refuse a good login once.
 */
export type WatchState = { kind: "watching" } | Refused;
export type Refused = { kind: "refused"; refusals: number; refusedAt: number };

export const WATCHING: WatchState = { kind: "watching" };

/**
 * How long after each refusal in a row the login is tried again: the next cron run, then about a quarter of an hour,
 * an hour, and every six hours from then on. Each is a minute short of the round time, so the cron run at that mark
 * takes it. A wrong password is tried a few times a day at most, which locks no account.
 */
const RETRY_AFTER_MS = [4, 14, 59].map((minutes) => minutes * 60_000);
const LAST_RETRY_AFTER_MS = 359 * 60_000;

/** The state after the server refused the login once more, at `now`. */
export function refusedAgain(state: WatchState | undefined, now: number): Refused {
  return { kind: "refused", refusals: (state?.kind === "refused" ? state.refusals : 0) + 1, refusedAt: now };
}

/** Whether a cron run at `now` logs in with a login in this state. */
export function isDue(state: WatchState, now: number): boolean {
  if (state.kind === "watching") return true;
  return now >= state.refusedAt + (RETRY_AFTER_MS[state.refusals - 1] ?? LAST_RETRY_AFTER_MS);
}

/** One device's watch on an account's Inbox, as the relay keeps it. */
export interface ImapWatch {
  watchId: string;
  secretHash: string;
  account: string;
  device: Device;
  /** The sealed login (`loginSealer`). */
  login: string;
  loginHash: string;
  state: WatchState;
  inbox: InboxStatus;
  expiresAt: number;
}

export function loginSealer(secret: string): Sealer {
  return new Sealer(secret, "goodmail imap logins v1");
}

/** The login as one string, with its fields in a fixed order, for sealing and for `login_hash`. */
export function canonicalLogin(login: ImapLogin): string {
  const { host, port, security, username, password } = login;
  return JSON.stringify({ host: host.toLowerCase(), port, security, username, password });
}

interface Row {
  watch_id: string;
  secret_hash: string;
  account: string;
  device_token: string;
  environment: ApnsEnvironment;
  login: string;
  login_hash: string;
  state: "watching" | "refused";
  refusals: number;
  refused_at: number;
  uid_validity: number;
  uid_next: number;
  expires_at: number;
}

function watch(row: Row): ImapWatch {
  return {
    watchId: row.watch_id,
    secretHash: row.secret_hash,
    account: row.account,
    device: { token: row.device_token, environment: row.environment },
    login: row.login,
    loginHash: row.login_hash,
    state: row.state === "watching" ? WATCHING : { kind: "refused", refusals: row.refusals, refusedAt: row.refused_at },
    inbox: { uidValidity: row.uid_validity, uidNext: row.uid_next },
    expiresAt: row.expires_at,
  };
}

export async function findWatch(db: D1Database, watchId: string): Promise<ImapWatch | undefined> {
  const row = await db.prepare("SELECT * FROM imap_watches WHERE watch_id = ?1").bind(watchId).first<Row>();
  return row ? watch(row) : undefined;
}

/** A state's three columns: `state`, `refusals` and `refused_at`. */
function columns(state: WatchState): ["watching" | "refused", number, number] {
  return state.kind === "watching" ? ["watching", 0, 0] : ["refused", state.refusals, state.refusedAt];
}

/**
 * Stores a watch whose login was just checked: one the server took starts from `watch.inbox`, and one it refused
 * waits to be tried again. Returns false, storing nothing, when the watch ID is already registered
 * with another secret: only the device that made it knows the right one.
 */
export async function storeWatch(db: D1Database, watch: ImapWatch): Promise<boolean> {
  const { watchId, secretHash, account, device, login, loginHash, state, inbox, expiresAt } = watch;
  const result = await db
    .prepare(
      `INSERT INTO imap_watches (watch_id, secret_hash, account, device_token, environment, login, login_hash, state,
         refusals, refused_at, uid_validity, uid_next, expires_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?11, ?12, ?13, ?8, ?9, ?10)
       ON CONFLICT (watch_id) DO UPDATE SET account = excluded.account, device_token = excluded.device_token,
         environment = excluded.environment, login = excluded.login, login_hash = excluded.login_hash,
         state = excluded.state, refusals = excluded.refusals, refused_at = excluded.refused_at,
         uid_validity = excluded.uid_validity, uid_next = excluded.uid_next, expires_at = excluded.expires_at
       WHERE imap_watches.secret_hash = excluded.secret_hash`,
    )
    .bind(watchId, secretHash, account, device.token, device.environment, login, loginHash, inbox.uidValidity,
      inbox.uidNext, expiresAt, ...columns(state))
    .run();
  return result.meta.changes === 1;
}

/** A registration with the same login: only the device and the expiry can change. */
export async function renewWatch(
  db: D1Database,
  watchId: string,
  account: string,
  device: Device,
  expiresAt: number,
): Promise<void> {
  await db
    .prepare(
      "UPDATE imap_watches SET account = ?2, device_token = ?3, environment = ?4, expires_at = ?5 WHERE watch_id = ?1",
    )
    .bind(watchId, account, device.token, device.environment, expiresAt)
    .run();
}

export async function removeWatch(db: D1Database, watchId: string, secretHash: string): Promise<void> {
  await db.prepare("DELETE FROM imap_watches WHERE watch_id = ?1 AND secret_hash = ?2").bind(watchId, secretHash).run();
}

/** Drops lapsed watches, then returns the ones to look at now: those watching, and refused ones due another try. */
export async function watchesDue(db: D1Database, now: number): Promise<ImapWatch[]> {
  const [, selected] = await db.batch<Row>([
    db.prepare("DELETE FROM imap_watches WHERE expires_at < ?1").bind(now),
    db.prepare("SELECT * FROM imap_watches"),
  ]);
  return (selected?.results ?? []).map(watch).filter((found) => isDue(found.state, now));
}

/**
 * Moves the watch from `from` to `to`, in one conditional write: false when another check moved it first, so only
 * one of them alerts.
 */
export async function advanceWatch(
  db: D1Database,
  watchId: string,
  from: InboxStatus,
  to: InboxStatus,
): Promise<boolean> {
  const result = await db
    .prepare(
      `UPDATE imap_watches SET uid_validity = ?4, uid_next = ?5
       WHERE watch_id = ?1 AND uid_validity = ?2 AND uid_next = ?3`,
    )
    .bind(watchId, from.uidValidity, from.uidNext, to.uidValidity, to.uidNext)
    .run();
  return result.meta.changes === 1;
}

/** The state of a login the relay holds, under any watch: every watch on a login shares it (`setLoginState`). */
export async function loginState(db: D1Database, loginHash: string): Promise<WatchState | undefined> {
  const row = await db.prepare("SELECT * FROM imap_watches WHERE login_hash = ?1 LIMIT 1").bind(loginHash).first<Row>();
  return row ? watch(row).state : undefined;
}

/**
 * Moves every watch on a login to `state`: the one place a watch changes state after it is stored, since the
 * server's answer to a login holds for every device watching with it.
 */
export async function setLoginState(db: D1Database, loginHash: string, state: WatchState): Promise<void> {
  await db
    .prepare("UPDATE imap_watches SET state = ?2, refusals = ?3, refused_at = ?4 WHERE login_hash = ?1")
    .bind(loginHash, ...columns(state))
    .run();
}
