import type { Env } from "./env";
import { GrantRevoked, METADATA_SCOPE, profileAddress, refreshAccessToken, revokeGrant } from "./gmail";
import { verifyIdToken } from "./google";
import { GmailGrants } from "./grants";
import { BadRequest, googleKeys, mailboxCheck, nowSeconds, readJson } from "./shared";
import { accountId } from "./store";

export function grantsFor(env: Env): GmailGrants {
  return new GmailGrants(env.DB, env.EMAIL_HMAC_SECRET);
}

/** The account an ID token in the body proves. */
async function authenticateAccount(body: Record<string, unknown>, env: Env): Promise<string> {
  if (typeof body.idToken !== "string") throw new BadRequest("idToken is required");
  const email = await verifyIdToken(body.idToken, env.GOOGLE_CLIENT_ID, googleKeys, nowSeconds());
  return accountId(email, env.EMAIL_HMAC_SECRET);
}

/**
 * Stores a Gmail metadata grant. The refresh token proves itself: it must refresh, hold exactly the metadata scope
 * (a broader one is refused and never stored), and its profile names the account.
 */
export async function storeGrant(request: Request, env: Env): Promise<Response> {
  const { refreshToken } = await readJson(request);
  if (typeof refreshToken !== "string" || refreshToken.length === 0 || refreshToken.length > 512) {
    throw new BadRequest("bad refreshToken");
  }
  let account: string;
  try {
    const token = await refreshAccessToken(refreshToken, env.GOOGLE_CLIENT_ID, Date.now());
    if (token.scopes.length !== 1 || token.scopes[0] !== METADATA_SCOPE) {
      throw new BadRequest("the grant must hold only the gmail.metadata scope");
    }
    account = await accountId(await profileAddress(token), env.EMAIL_HMAC_SECRET);
  } catch (error) {
    if (error instanceof GrantRevoked) return new Response(null, { status: 401 });
    throw error;
  }
  await grantsFor(env).store(account, refreshToken, Date.now());
  mailboxCheck.forget(account);
  return new Response(null, { status: 204 });
}

export async function removeGrant(request: Request, env: Env): Promise<Response> {
  await forgetGrant(env, await authenticateAccount(await readJson(request), env));
  return new Response(null, { status: 204 });
}

/** Deletes the account's grant and revokes it at Google, so nothing can use it again. */
export async function forgetGrant(env: Env, account: string): Promise<void> {
  const grants = grantsFor(env);
  const refreshToken = await grants.refreshToken(account);
  await grants.remove(account);
  mailboxCheck.forget(account);
  if (refreshToken) await revokeGrant(refreshToken);
}

/** Whether the relay holds a grant for the account, so the app can offer one when it doesn't. */
export async function grantStatus(request: Request, env: Env): Promise<Response> {
  const account = await authenticateAccount(await readJson(request), env);
  return Response.json({ active: await grantsFor(env).has(account) });
}
