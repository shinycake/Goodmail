import type { Env } from "./env";
import { GrantRevoked, profile, readsHistory, refreshAccessToken } from "./gmail";
import { GmailGrants } from "./grants";
import { BadRequest, mailboxCheck, readJson } from "./shared";
import { accountId } from "./store";

export function grantsFor(env: Env): GmailGrants {
  return new GmailGrants(env.DB, env.EMAIL_HMAC_SECRET);
}

/**
 * Stores the app's Gmail refresh token for an account, with whether it alerts for Primary mail only. The app sends
 * both each time it brings push up to date, so a token already held only takes the choice and answers at once. A new one proves itself: it must refresh, its scopes must let it read history,
 * and its profile names the account it is stored under.
 */
export async function storeGrant(request: Request, env: Env): Promise<Response> {
  const { refreshToken, primaryOnly = false } = await readJson(request);
  if (typeof refreshToken !== "string" || refreshToken.length === 0 || refreshToken.length > 512) {
    throw new BadRequest("bad refreshToken");
  }
  if (typeof primaryOnly !== "boolean") throw new BadRequest("primaryOnly must be a boolean");
  const grants = grantsFor(env);
  if (await grants.update(refreshToken, primaryOnly)) return new Response(null, { status: 204 });
  let account: string;
  let historyId: string;
  try {
    const token = await refreshAccessToken(refreshToken, env.GOOGLE_CLIENT_ID, Date.now());
    if (!readsHistory(token.scopes)) throw new BadRequest("the token can't read Gmail history");
    const found = await profile(token);
    account = await accountId(found.address, env.EMAIL_HMAC_SECRET);
    historyId = found.historyId;
  } catch (error) {
    if (error instanceof GrantRevoked) return new Response(null, { status: 401 });
    throw error;
  }
  await grants.store(account, refreshToken, primaryOnly, historyId, Date.now());
  mailboxCheck.forget(account);
  return new Response(null, { status: 204 });
}

/**
 * Deletes the account's token. It is the app's own sign-in, so it is never revoked at Google: that would sign the app
 * out.
 */
export async function forgetGrant(env: Env, account: string): Promise<void> {
  await grantsFor(env).remove(account);
  mailboxCheck.forget(account);
}
