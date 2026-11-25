import type { ApnsEnvironment, Device } from "./apns";
import type { ImapLogin, InboxStatus } from "./imap";
import {
  isDue,
  type LoginCheck,
  type LoginRow,
  type LoginState,
  loginStateOf,
  mirrorLoginState,
  recordCheck,
} from "./imap-logins";
import { Sealer } from "./sealing";
import { device as storedDevice } from "./store";

/** How long a watch lasts after its device last registered it. The app registers it on every refresh. */
export const WATCH_LIFETIME_MS = 30 * 86_400_000;

/** One device's watch on an account's Inbox, as the relay keeps it. Its login's state is the login's (imap-logins.ts). */
export interface ImapWatch {
  watchId: string;
  secretHash: string;
  account: string;
  device: Device;
  /** The sealed login (`loginSealer`). */
  login: string;
  loginHash: string;
  /** Where the watch is in the Inbox, or null until a server that refused the login at registration first takes it. */
  inbox: InboxStatus | null;
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
  watch_token: string | null;
  login: string;
  login_hash: string;
  uid_validity: number;
  uid_next: number;
  expires_at: number;
}

/**
 * A position's two columns. IMAP's UIDVALIDITY and UIDNEXT are never 0 (RFC 3501 §9, nz-number), so 0 and 0 store
 * "no position yet".
 */
function positionColumns(inbox: InboxStatus | null): [number, number] {
  return inbox ? [inbox.uidValidity, inbox.uidNext] : [0, 0];
}

function watch(row: Row): ImapWatch {
  return {
    watchId: row.watch_id,
    secretHash: row.secret_hash,
    account: row.account,
    device: storedDevice(row.device_token, row.environment, row.watch_token),
    login: row.login,
    loginHash: row.login_hash,
    inbox: row.uid_validity === 0 && row.uid_next === 0 ? null : { uidValidity: row.uid_validity, uidNext: row.uid_next },
    expiresAt: row.expires_at,
  };
}

export async function findWatch(db: D1Database, watchId: string): Promise<ImapWatch | undefined> {
  const row = await db.prepare("SELECT * FROM imap_watches WHERE watch_id = ?1").bind(watchId).first<Row>();
  return row ? watch(row) : undefined;
}

/** What `storeWatch` did: stored the watch, leaving its login in `state`, or nothing, for a watch that isn't the caller's. */
export type Stored = { kind: "stored"; state: LoginState } | { kind: "notYours" };

/**
 * Stores a watch whose login was just checked, with the check's answer for the login, in one transaction: one the
 * server took starts from `watch.inbox`, and one it refused waits to be tried again. Stores nothing when the watch ID
 * is already registered with another secret: only the device that made it knows the right one.
 */
export async function storeWatch(db: D1Database, watch: ImapWatch, check: LoginCheck, now: number): Promise<Stored> {
  const { watchId, secretHash, account, device, login, loginHash, inbox, expiresAt } = watch;
  // `state`, `refusals` and `refused_at` are the login's now (imap_logins); these columns only mirror it, for the build
  // before it (`mirrorLoginState`), until a later migration drops them.
  const [, recorded] = await db.batch<LoginRow>([
    db
      .prepare(
        `INSERT INTO imap_watches (watch_id, secret_hash, account, device_token, environment, login, login_hash, state,
           refusals, refused_at, uid_validity, uid_next, expires_at, watch_token)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 'watching', 0, 0, ?8, ?9, ?10, ?11)
         ON CONFLICT (watch_id) DO UPDATE SET account = excluded.account, device_token = excluded.device_token,
           environment = excluded.environment, watch_token = excluded.watch_token, login = excluded.login,
           login_hash = excluded.login_hash, uid_validity = excluded.uid_validity, uid_next = excluded.uid_next,
           expires_at = excluded.expires_at
         WHERE imap_watches.secret_hash = excluded.secret_hash`,
      )
      .bind(watchId, secretHash, account, device.token, device.environment, login, loginHash, ...positionColumns(inbox),
        expiresAt, device.watchToken ?? null),
    recordCheck(db, loginHash, check, now, { watchId, secretHash }),
    mirrorLoginState(db, loginHash),
  ]);
  const row = recorded?.results[0];
  return row ? { kind: "stored", state: loginStateOf(row) } : { kind: "notYours" };
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
      `UPDATE imap_watches SET account = ?2, device_token = ?3, environment = ?4, expires_at = ?5, watch_token = ?6
       WHERE watch_id = ?1`,
    )
    .bind(watchId, account, device.token, device.environment, expiresAt, device.watchToken ?? null)
    .run();
}

export async function removeWatch(db: D1Database, watchId: string, secretHash: string): Promise<void> {
  await db.prepare("DELETE FROM imap_watches WHERE watch_id = ?1 AND secret_hash = ?2").bind(watchId, secretHash).run();
}

/** A login the relay watches an Inbox with, sealed, and its hash. */
export type WatchedLogin = Pick<ImapWatch, "login" | "loginHash">;

/**
 * Drops lapsed watches and the states of logins no watch uses any more, then returns the logins to look at now, each
 * once however many devices watch with it: those watching, and refused ones due another try.
 */
export async function loginsDue(db: D1Database, now: number): Promise<WatchedLogin[]> {
  const [, , selected] = await db.batch<LoginRow & { login: string; login_hash: string }>([
    db.prepare("DELETE FROM imap_watches WHERE expires_at < ?1").bind(now),
    db.prepare("DELETE FROM imap_logins WHERE login_hash NOT IN (SELECT login_hash FROM imap_watches)"),
    db.prepare(
      `SELECT w.login_hash, MIN(w.login) AS login, l.state, l.refusals, l.refused_at
       FROM imap_watches w LEFT JOIN imap_logins l ON l.login_hash = w.login_hash
       GROUP BY w.login_hash`,
    ),
  ]);
  return (selected?.results ?? [])
    .filter((row) => isDue(loginStateOf(row), now))
    .map((row) => ({ login: row.login, loginHash: row.login_hash }));
}

/** Every device's watch on the Inbox of one login. */
export async function watchesOn(db: D1Database, loginHash: string): Promise<ImapWatch[]> {
  const { results } = await db.prepare("SELECT * FROM imap_watches WHERE login_hash = ?1").bind(loginHash).all<Row>();
  return results.map(watch);
}

/**
 * Moves the watch from `from` to `to`, in one conditional write: false when another check moved it first, so only
 * one of them alerts.
 */
export async function advanceWatch(
  db: D1Database,
  watchId: string,
  from: InboxStatus | null,
  to: InboxStatus | null,
): Promise<boolean> {
  const result = await db
    .prepare(
      `UPDATE imap_watches SET uid_validity = ?4, uid_next = ?5
       WHERE watch_id = ?1 AND uid_validity = ?2 AND uid_next = ?3`,
    )
    .bind(watchId, ...positionColumns(from), ...positionColumns(to))
    .run();
  return result.meta.changes === 1;
}
