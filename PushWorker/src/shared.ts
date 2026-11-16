import { GoogleKeys } from "./google";
import { MailboxCheck } from "./mailbox-check";

/** Shared by every request this isolate serves, so the JWKS and Gmail access tokens are fetched rarely. */
export const googleKeys = new GoogleKeys();
export const mailboxCheck = new MailboxCheck();

/** A request the Worker answers with 400 and the message. */
export class BadRequest extends Error {}

export const nowSeconds = () => Math.floor(Date.now() / 1000);

export async function readJson(request: Request): Promise<Record<string, unknown>> {
  const body = await request.json().catch(() => undefined);
  if (typeof body !== "object" || body === null) throw new BadRequest("expected a JSON object");
  return body as Record<string, unknown>;
}
