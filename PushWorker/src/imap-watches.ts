import type { ApnsEnvironment, Device } from "./apns";
import type { ImapLogin, InboxStatus } from "./imap";
import { Sealer } from "./sealing";

/** How long a watch lasts after its device last registered it. The app registers it on every refresh. */
export const WATCH_LIFETIME_MS = 30 * 86_400_000;

/** `watching`, or `refused` once the server refused its login: never tried again until the login changes. */
export type WatchState = "watching" | "refused";

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
  state: WatchState;
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
    state: row.state,
    inbox: { uidValidity: row.uid_validity, uidNext: row.uid_next },
    expiresAt: row.expires_at,
  };
}

export async function findWatch(db: D1Database, watchId: string): Promise<ImapWatch | undefined> {
  const row = await db.prepare("SELECT * FROM imap_watches WHERE watch_id = ?1").bind(watchId).first<Row>();
  return row ? watch(row) : undefined;
}

/**
 * Stores a watch whose login was just checked: one the server took starts from `watch.inbox`, and one it refused
 * keeps the login from being tried again. Returns false, storing nothing, when the watch ID is already registered
 * with another secret: only the device that made it knows the right one.
 */
export async function storeWatch(db: D1Database, watch: ImapWatch): Promise<boolean> {
  const { watchId, secretHash, account, device, login, loginHash, state, inbox, expiresAt } = watch;
  const result = await db
    .prepare(
      `INSERT INTO imap_watches (watch_id, secret_hash, account, device_token, environment, login, login_hash, state,
         uid_validity, uid_next, expires_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?11, ?8, ?9, ?10)
       ON CONFLICT (watch_id) DO UPDATE SET account = excluded.account, device_token = excluded.device_token,
         environment = excluded.environment, login = excluded.login, login_hash = excluded.login_hash,
         state = excluded.state, uid_validity = excluded.uid_validity, uid_next = excluded.uid_next,
         expires_at = excluded.expires_at
       WHERE imap_watches.secret_hash = excluded.secret_hash`,
    )
    .bind(watchId, secretHash, account, device.token, device.environment, login, loginHash, inbox.uidValidity,
      inbox.uidNext, expiresAt, state)
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

/** Drops lapsed watches, then returns the ones to look at now. */
export async function watchesDue(db: D1Database, now: number): Promise<ImapWatch[]> {
  const [, selected] = await db.batch<Row>([
    db.prepare("DELETE FROM imap_watches WHERE expires_at < ?1").bind(now),
    db.prepare("SELECT * FROM imap_watches WHERE state = 'watching'"),
  ]);
  return (selected?.results ?? []).map(watch);
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

/** Whether the server refused this login, for any watch: then it is never tried again. */
export async function isRefused(db: D1Database, loginHash: string): Promise<boolean> {
  const row = await db
    .prepare("SELECT 1 FROM imap_watches WHERE login_hash = ?1 AND state = 'refused'")
    .bind(loginHash)
    .first();
  return row !== null;
}

/** Stops every watch on a login the server refused. */
export async function refuseLogin(db: D1Database, loginHash: string): Promise<void> {
  await db.prepare("UPDATE imap_watches SET state = 'refused' WHERE login_hash = ?1").bind(loginHash).run();
}
