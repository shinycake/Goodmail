/** Forgets a device token APNs says is no longer valid: its Gmail registrations, Graph subscriptions and IMAP watches. */
export async function forgetDeviceToken(db: D1Database, token: string): Promise<void> {
  await db.batch([
    db.prepare("DELETE FROM devices WHERE device_token = ?1").bind(token),
    db.prepare("DELETE FROM graph_subscriptions WHERE device_token = ?1").bind(token),
    db.prepare("DELETE FROM imap_watches WHERE device_token = ?1").bind(token),
  ]);
}

/** Forgets a watch token APNs says is no longer valid, keeping the iPhone registrations it was paired with. */
export async function forgetWatchToken(db: D1Database, token: string): Promise<void> {
  await db.batch([
    db.prepare("UPDATE devices SET watch_token = NULL WHERE watch_token = ?1").bind(token),
    db.prepare("UPDATE graph_subscriptions SET watch_token = NULL WHERE watch_token = ?1").bind(token),
    db.prepare("UPDATE imap_watches SET watch_token = NULL WHERE watch_token = ?1").bind(token),
  ]);
}
