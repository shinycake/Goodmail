import type { ApnsEnvironment, Device } from "./apns";
import { encodeUtf8, toHex } from "./encoding";

/** A device's Graph subscription, as the relay keeps it. */
export interface GraphSubscription {
  subscriptionId: string;
  account: string;
  device: Device;
  /** Milliseconds since 1970. Graph stops notifying after this unless the device renews it. */
  expiresAt: number;
}

/** Rows are kept a day past expiry, so a renewal that races the expiry still finds its row. */
const EXPIRED_GRACE_MS = 86_400_000;

export async function clientStateHash(clientState: string): Promise<string> {
  return toHex(await crypto.subtle.digest("SHA-256", encodeUtf8(clientState)));
}

/** Whether two hex hashes match, in constant time. */
function sameHash(a: string, b: string): boolean {
  const left = encodeUtf8(a);
  const right = encodeUtf8(b);
  return left.byteLength === right.byteLength && crypto.subtle.timingSafeEqual(left, right);
}

/**
 * Stores or renews a subscription. Returns false, storing nothing, when the subscription is already registered
 * with another clientState: only the device that made it knows the right one.
 */
export async function registerGraphSubscription(
  db: D1Database,
  subscription: GraphSubscription,
  clientState: string,
  now: number,
): Promise<boolean> {
  const hash = await clientStateHash(clientState);
  const { subscriptionId, account, device, expiresAt } = subscription;
  const [, write] = await db.batch([
    db.prepare("DELETE FROM graph_subscriptions WHERE expires_at < ?1").bind(now - EXPIRED_GRACE_MS),
    db
      .prepare(
        `INSERT INTO graph_subscriptions (subscription_id, client_state_hash, account, device_token, environment, expires_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)
         ON CONFLICT (subscription_id) DO UPDATE SET account = excluded.account, device_token = excluded.device_token,
           environment = excluded.environment, expires_at = excluded.expires_at
         WHERE graph_subscriptions.client_state_hash = excluded.client_state_hash`,
      )
      .bind(subscriptionId, hash, account, device.token, device.environment, expiresAt),
  ]);
  return write?.meta.changes === 1;
}

/** Removes a subscription, when `clientState` is its own. */
export async function unregisterGraphSubscription(
  db: D1Database,
  subscriptionId: string,
  clientState: string,
): Promise<void> {
  await db
    .prepare("DELETE FROM graph_subscriptions WHERE subscription_id = ?1 AND client_state_hash = ?2")
    .bind(subscriptionId, await clientStateHash(clientState))
    .run();
}

/** The subscription a notification names, when its clientState is the registered one. */
export async function verifiedSubscription(
  db: D1Database,
  subscriptionId: string,
  clientState: string,
): Promise<GraphSubscription | undefined> {
  const row = await db
    .prepare(
      "SELECT client_state_hash, account, device_token, environment, expires_at FROM graph_subscriptions WHERE subscription_id = ?1",
    )
    .bind(subscriptionId)
    .first<{
      client_state_hash: string;
      account: string;
      device_token: string;
      environment: ApnsEnvironment;
      expires_at: number;
    }>();
  if (!row || !sameHash(row.client_state_hash, await clientStateHash(clientState))) return undefined;
  return {
    subscriptionId,
    account: row.account,
    device: { token: row.device_token, environment: row.environment },
    expiresAt: row.expires_at,
  };
}

/** Removes every subscription of a token APNs says is no longer valid. */
export async function removeGraphToken(db: D1Database, token: string): Promise<void> {
  await db.prepare("DELETE FROM graph_subscriptions WHERE device_token = ?1").bind(token).run();
}
