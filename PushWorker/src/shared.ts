import { GoogleKeys } from "./google";
import { MailboxCheck } from "./mailbox-check";
import { OutlookCheck } from "./outlook";

/** Shared by every request this isolate serves, so the JWKS and Gmail access tokens are fetched rarely. */
export const googleKeys = new GoogleKeys();
export const mailboxCheck = new MailboxCheck();
export const outlookCheck = new OutlookCheck();

/** A request the Worker answers with 400 and the message. */
export class BadRequest extends Error {}

export const nowSeconds = () => Math.floor(Date.now() / 1000);

/** An APNs device token, as hex. */
export const DEVICE_TOKEN = /^[0-9a-f]{64,200}$/i;

/**
 * The paired Apple Watch's token a registration may carry (ADR-023), lowercased; undefined when it carries none, which
 * clears one registered before.
 */
export function watchTokenIn(body: Record<string, unknown>): string | undefined {
  const { watchToken } = body;
  if (watchToken === undefined || watchToken === null) return undefined;
  if (typeof watchToken !== "string" || !DEVICE_TOKEN.test(watchToken)) throw new BadRequest("bad watchToken");
  return watchToken.toLowerCase();
}

export async function readJson(request: Request): Promise<Record<string, unknown>> {
  const body = await request.json().catch(() => undefined);
  if (typeof body !== "object" || body === null) throw new BadRequest("expected a JSON object");
  return body as Record<string, unknown>;
}
