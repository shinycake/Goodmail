import { APNS_ORIGINS, type ApnsSigner, type Device, type PushOutcome, signerFor } from "./apns";
import type { Env } from "./env";
import type { Target } from "./new-mail";
import { forgetDeviceToken } from "./tokens";

/**
 * The quiet push that tells the app mail in an account was dealt with somewhere else: read, filed or deleted on
 * another device, in another app, or by the app itself. It shows nothing and plays nothing, so it is no alert and
 * passes no gate (`new-mail.ts`): the app wakes in the background, syncs the account it names, and takes down the
 * alerts whose mail no longer needs them. It names the account as alerts do, and nothing about the mail.
 */
export function handledPayload(target: Target): object {
  return { aps: { "content-available": 1 }, ...target, handled: 1 };
}

/**
 * Sends the quiet push to `device`'s iPhone at once, never its watch, whose alerts clear with the iPhone's or with what the
 * watch reads itself. Background pushes go at the lowest priority, which APNs and iOS hold and coalesce as they see
 * fit, so a burst of changes costs the device one wake. A token APNs calls gone is forgotten.
 */
async function send(env: Env, device: Device, target: Target, signer: ApnsSigner): Promise<PushOutcome> {
  try {
    const response = await fetch(`${APNS_ORIGINS[device.environment]}/3/device/${device.token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${await signer.token()}`,
        "apns-push-type": "background",
        "apns-topic": env.APNS_TOPIC,
        "apns-priority": "5",
        "content-type": "application/json",
      },
      body: JSON.stringify(handledPayload(target)),
    });
    if (response.ok) return "delivered";
    const reason = await response
      .json<{ reason?: string }>()
      .then((body) => body.reason)
      .catch(() => undefined);
    if (response.status === 410 || reason === "BadDeviceToken") {
      await forgetDeviceToken(env.DB, device.token);
      return "gone";
    }
    console.warn(`APNs ${response.status} ${reason ?? ""} for a handled push`.trim());
    return "failed";
  } catch (error) {
    // Best effort: the app catches up on its next sync either way.
    console.warn(`Handled push failed: ${error instanceof Error ? error.message : String(error)}`);
    return "failed";
  }
}

/** A device gets at most one quiet push this often; iOS allows an app only a few background wakes an hour. */
export const HANDLED_GAP_MS = 20_000;

/**
 * Spaces the quiet pushes to each device about each account, within this isolate: the first goes at once, and the changes in the next
 * `HANDLED_GAP_MS` go as one push at the end of it, so a burst of reads costs the device two wakes and the last change
 * is never left out. Another isolate may send its own; that only costs a wake.
 */
export class HandledPushes {
  /** When each device last got one for each account, and whether one is waiting to go after it. */
  private readonly devices = new Map<string, { sentAt: number; waiting: boolean }>();

  constructor(
    private readonly now: () => number = () => Date.now(),
    private readonly wait: (ms: number) => Promise<void> = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  ) {}

  /** Sends now, or once the gap since the last is up; resolves once the push went or was folded into a waiting one. */
  async send(env: Env, device: Device, target: Target, signer: ApnsSigner = signerFor(env)): Promise<void> {
    const key = `${device.token} ${"accountID" in target ? target.accountID : target.account}`;
    const last = this.devices.get(key);
    const now = this.now();
    if (last && now - last.sentAt < HANDLED_GAP_MS) {
      if (last.waiting) return;
      last.waiting = true;
      await this.wait(last.sentAt + HANDLED_GAP_MS - now);
    }
    this.devices.set(key, { sentAt: this.now(), waiting: false });
    if (this.devices.size > 1_000) this.forgetOld();
    await send(env, device, target, signer);
  }

  /** Forgets every device, as a test does between cases. */
  clear(): void {
    this.devices.clear();
  }

  private forgetOld(): void {
    const now = this.now();
    for (const [key, entry] of this.devices) {
      if (!entry.waiting && now - entry.sentAt >= HANDLED_GAP_MS) this.devices.delete(key);
    }
  }
}

/** Shared by everything this isolate does. */
export const handledPushes = new HandledPushes();

/** Sends `device` the quiet push for `target`, spaced by `handledPushes`. */
export function sendHandled(env: Env, device: Device, target: Target): Promise<void> {
  return handledPushes.send(env, device, target);
}
