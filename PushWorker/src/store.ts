import type { ApnsEnvironment, Device } from "./apns";
import { encodeUtf8, toHex } from "./encoding";

/** The account ID stored in D1: HMAC-SHA256 of the lowercased address, so the database never holds emails. */
export async function accountId(email: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", encodeUtf8(secret), { name: "HMAC", hash: "SHA-256" }, false, [
    "sign",
  ]);
  return toHex(await crypto.subtle.sign("HMAC", key, encodeUtf8(email.trim().toLowerCase())));
}

export async function registerDevice(db: D1Database, account: string, device: Device, now: number): Promise<void> {
  await db
    .prepare(
      `INSERT INTO devices (account, device_token, environment, updated_at) VALUES (?1, ?2, ?3, ?4)
       ON CONFLICT (account, device_token) DO UPDATE SET environment = excluded.environment, updated_at = excluded.updated_at`,
    )
    .bind(account, device.token, device.environment, now)
    .run();
}

export async function unregisterDevice(db: D1Database, account: string, token: string): Promise<void> {
  await db.prepare("DELETE FROM devices WHERE account = ?1 AND device_token = ?2").bind(account, token).run();
}

export async function devicesFor(db: D1Database, account: string): Promise<Device[]> {
  const { results } = await db
    .prepare("SELECT device_token, environment FROM devices WHERE account = ?1")
    .bind(account)
    .all<{ device_token: string; environment: ApnsEnvironment }>();
  return results.map((row) => ({ token: row.device_token, environment: row.environment }));
}

/** Removes a token APNs says is no longer valid, from every account it was registered for. */
export async function removeToken(db: D1Database, token: string): Promise<void> {
  await db.prepare("DELETE FROM devices WHERE device_token = ?1").bind(token).run();
}

/** A history ID recorded as the newest pushed for an account, and the one it replaced, so a failed send can undo it. */
export interface HistoryClaim {
  account: string;
  historyId: string;
  previous: string | null;
}

/**
 * Records `historyId` as the newest one pushed for `account`, in a single conditional write. Returns undefined when
 * it is a duplicate delivery or not newer than the last one recorded, so the caller drops it.
 */
export async function claimHistoryId(db: D1Database, account: string, historyId: string): Promise<HistoryClaim | undefined> {
  const padded = historyId.padStart(20, "0");
  const [before, write] = await db.batch<{ history_id: string }>([
    db.prepare("SELECT history_id FROM deliveries WHERE account = ?1").bind(account),
    db
      .prepare(
        `INSERT INTO deliveries (account, history_id) VALUES (?1, ?2)
         ON CONFLICT (account) DO UPDATE SET history_id = excluded.history_id
         WHERE excluded.history_id > deliveries.history_id`,
      )
      .bind(account, padded),
  ]);
  if (write?.meta.changes !== 1) return undefined;
  return { account, historyId: padded, previous: before?.results[0]?.history_id ?? null };
}

/**
 * Undoes a claim whose alert reached no device, so Pub/Sub's redelivery is sent instead of dropped. A newer claim
 * made since is left alone.
 */
export async function releaseHistoryId(db: D1Database, claim: HistoryClaim): Promise<void> {
  const statement =
    claim.previous === null
      ? db.prepare("DELETE FROM deliveries WHERE account = ?1 AND history_id = ?2").bind(claim.account, claim.historyId)
      : db
          .prepare("UPDATE deliveries SET history_id = ?3 WHERE account = ?1 AND history_id = ?2")
          .bind(claim.account, claim.historyId, claim.previous);
  await statement.run();
}
