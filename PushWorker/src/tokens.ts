/** Forgets a device token APNs says is no longer valid: its Gmail registrations, Graph subscriptions and IMAP watches. */
export async function forgetDeviceToken(db: D1Database, token: string): Promise<void> {
  await db.batch([
    db.prepare("DELETE FROM devices WHERE device_token = ?1").bind(token),
    db.prepare("DELETE FROM graph_subscriptions WHERE device_token = ?1").bind(token),
    db.prepare("DELETE FROM imap_watches WHERE device_token = ?1").bind(token),
  ]);
}
