import { type ApnsSigner, type Device, type PushOutcome, sendAlert } from "./apns";
import type { NewMail, Target } from "./new-mail";
import { forgetDeviceToken, forgetWatchToken } from "./tokens";

/** How long the iPhone has to confirm an alert before its watch gets it (ADR-023). */
export const FALLBACK_MS = 8_000;

/** Confirmations are kept this long; an alert is long settled by then. */
const ACK_LIFETIME_MS = 86_400_000;

/** An alert ID as the relay makes them, and as the iPhone sends one back. */
export const ALERT_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * How one alert to an iPhone with a watch stands, in the `acks` table: `sent`, then `confirmed` when the iPhone says it
 * arrived, or `fellBack` when it didn't in time and the watch got it. Each move is one conditional write from `sent`,
 * so a late confirmation and the fallback can't both win.
 */
export type Delivery = "sent" | "confirmed" | "fellBack";

/** The apps alerts go to: the iPhone app's bundle ID, and the watch app's. */
export interface Topics {
  app: string;
  watch: string;
}

/**
 * Sends alerts, the iPhone first and its watch if the iPhone is silent. The wait runs in `later`, which keeps the
 * Worker alive for it (`ExecutionContext.waitUntil`).
 */
export class Alerts {
  constructor(
    private readonly db: D1Database,
    private readonly signer: ApnsSigner,
    private readonly topics: Topics,
    private readonly later: (work: Promise<unknown>) => void,
    private readonly wait: (ms: number) => Promise<void> = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
    private readonly now: () => number = () => Date.now(),
  ) {}

  /**
   * Sends the alert for `mail` to `device`, and, when it has a watch, to the watch as well if the iPhone doesn't
   * confirm it within `FALLBACK_MS`. Returns how the iPhone's send went; a token APNs calls gone is forgotten.
   */
  async send(device: Device, mail: NewMail, target: Target): Promise<PushOutcome> {
    const alert = crypto.randomUUID();
    const { watchToken } = device;
    if (watchToken) {
      await this.db
        .prepare("INSERT INTO acks (alert_id, sent_at, delivery) VALUES (?1, ?2, 'sent')")
        .bind(alert, this.now())
        .run();
    }
    const recipient = { token: device.token, environment: device.environment, topic: this.topics.app, device: "phone" as const };
    const outcome = await sendAlert(this.signer, recipient, mail, target, alert);
    if (outcome === "gone") {
      // The app is gone from the iPhone, so the watch, which needs it, gets nothing either.
      await forgetDeviceToken(this.db, device.token);
      return outcome;
    }
    if (watchToken) this.later(this.fallBack({ ...device, watchToken }, mail, target, alert));
    return outcome;
  }

  /** Waits for the iPhone, then sends the alert to the watch unless the iPhone confirmed it meanwhile. */
  private async fallBack(device: Device & { watchToken: string }, mail: NewMail, target: Target, alert: string) {
    await this.wait(FALLBACK_MS);
    if (!(await move(this.db, alert, "fellBack"))) return;
    const recipient = { token: device.watchToken, environment: device.environment, topic: this.topics.watch, device: "watch" as const };
    if ((await sendAlert(this.signer, recipient, mail, target, alert)) === "gone") {
      await forgetWatchToken(this.db, device.watchToken);
    }
  }
}

/** Forgets alerts older than a day, in the cron run. */
export async function pruneAlerts(db: D1Database, now: number): Promise<void> {
  await db.prepare("DELETE FROM acks WHERE sent_at < ?1").bind(now - ACK_LIFETIME_MS).run();
}

/** Moves a `sent` alert to `to`. Returns whether this call moved it. */
export async function move(db: D1Database, alert: string, to: Exclude<Delivery, "sent">): Promise<boolean> {
  const result = await db
    .prepare("UPDATE acks SET delivery = ?2 WHERE alert_id = ?1 AND delivery = 'sent'")
    .bind(alert, to)
    .run();
  return result.meta.changes === 1;
}
