/** The one scope a stored grant may hold: labels, history and headers, never bodies, and nothing that changes mail. */
export const METADATA_SCOPE = "https://www.googleapis.com/auth/gmail.metadata";
export const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";
export const GOOGLE_REVOKE_URL = "https://oauth2.googleapis.com/revoke";
export const GMAIL_API = "https://gmail.googleapis.com/gmail/v1/users/me";

/** Google refused the grant (revoked, or expired as Testing-mode grants do after 7 days): forget it. */
export class GrantRevoked extends Error {}

export interface AccessToken {
  value: string;
  /** Milliseconds since 1970. */
  expiresAt: number;
  scopes: string[];
}

/** Refreshes `refreshToken` with the iOS client, which has no secret. */
export async function refreshAccessToken(refreshToken: string, clientId: string, now: number): Promise<AccessToken> {
  const response = await fetch(GOOGLE_TOKEN_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken, client_id: clientId }),
  });
  const body = (await response.json().catch(() => ({}))) as {
    access_token?: unknown;
    expires_in?: unknown;
    scope?: unknown;
    error?: unknown;
  };
  if (response.status === 400 && body.error === "invalid_grant") throw new GrantRevoked();
  if (!response.ok || typeof body.access_token !== "string") {
    throw new Error(`token refresh failed with ${response.status}`);
  }
  const expiresIn = typeof body.expires_in === "number" ? body.expires_in : 3600;
  return {
    value: body.access_token,
    expiresAt: now + expiresIn * 1000,
    scopes: typeof body.scope === "string" ? body.scope.split(" ").filter(Boolean) : [],
  };
}

/** The address the token belongs to. */
export async function profileAddress(token: AccessToken): Promise<string> {
  const response = await fetch(`${GMAIL_API}/profile`, { headers: { authorization: `Bearer ${token.value}` } });
  if (!response.ok) throw new Error(`profile failed with ${response.status}`);
  const body = (await response.json()) as { emailAddress?: unknown };
  if (typeof body.emailAddress !== "string") throw new Error("profile has no address");
  return body.emailAddress;
}

/**
 * What Gmail's history after `startHistoryId` holds: `added` when a message reached the Inbox, `none` when it holds
 * only changes to mail already there (a read, an archive, a delete, a label), and `unknown` when Gmail can't say,
 * as when the history ID is too old.
 */
export async function inboxChange(token: AccessToken, startHistoryId: string): Promise<"added" | "none" | "unknown"> {
  const query = new URLSearchParams({ startHistoryId, historyTypes: "messageAdded", labelId: "INBOX", maxResults: "100" });
  const response = await fetch(`${GMAIL_API}/history?${query}`, { headers: { authorization: `Bearer ${token.value}` } });
  if (!response.ok) return "unknown";
  const body = (await response.json()) as { history?: { messagesAdded?: unknown[] }[]; nextPageToken?: unknown };
  if ((body.history ?? []).some((record) => (record.messagesAdded?.length ?? 0) > 0)) return "added";
  // A page that ran out before the end could hide one.
  return body.nextPageToken === undefined ? "none" : "unknown";
}

/** Tells Google the grant is no longer wanted. Best effort: the stored copy is gone either way. */
export async function revokeGrant(refreshToken: string): Promise<void> {
  await fetch(GOOGLE_REVOKE_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ token: refreshToken }),
  }).catch(() => undefined);
}
