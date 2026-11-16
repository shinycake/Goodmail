import { type Arrival, decodeEncodedWords, type NewMail, NONE, newestOf, RETRY, senderName } from "./new-mail";

/** The scopes that let a token list an account's history. */
const HISTORY_SCOPES = new Set([
  "https://mail.google.com/",
  "https://www.googleapis.com/auth/gmail.modify",
  "https://www.googleapis.com/auth/gmail.readonly",
  "https://www.googleapis.com/auth/gmail.metadata",
]);
export const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";
export const GMAIL_API = "https://gmail.googleapis.com/gmail/v1/users/me";

/** Whether a token with `scopes` can list history. */
export function readsHistory(scopes: string[]): boolean {
  return scopes.some((scope) => HISTORY_SCOPES.has(scope));
}

/** Google refused the token (revoked, or expired as Testing-mode grants do after 7 days): forget it. */
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

/** The address the token belongs to, and the mailbox's history ID now. */
export async function profile(token: AccessToken): Promise<{ address: string; historyId: string }> {
  const response = await fetch(`${GMAIL_API}/profile`, { headers: { authorization: `Bearer ${token.value}` } });
  if (!response.ok) throw new Error(`profile failed with ${response.status}`);
  const body = (await response.json()) as { emailAddress?: unknown; historyId?: unknown };
  if (typeof body.emailAddress !== "string") throw new Error("profile has no address");
  const historyId = typeof body.historyId === "number" ? String(body.historyId) : body.historyId;
  if (typeof historyId !== "string" || !/^\d{1,20}$/.test(historyId)) throw new Error("profile has no history ID");
  return { address: body.emailAddress, historyId };
}

/** The most messages a notification's check reads one by one; more than this waits for the next notification. */
const MOST_CHECKED = 20;

/**
 * The mail Gmail's history after `startHistoryId` added to the Inbox that the app alerts for (`alertsFor`), read as
 * it is now: a read, archive, delete or label change, mail sent to oneself, and mail read or deleted before the check
 * are `none`. `retry` when Gmail can't say yet, as when it fails or the history ID is too old.
 */
export async function inboxArrival(token: AccessToken, startHistoryId: string, primaryOnly: boolean): Promise<Arrival> {
  const query = new URLSearchParams({ startHistoryId, historyTypes: "messageAdded", labelId: "INBOX", maxResults: "100" });
  const response = await fetch(`${GMAIL_API}/history?${query}`, { headers: { authorization: `Bearer ${token.value}` } });
  if (response.status === 404) {
    // The history ID is too old to list: nothing can say what arrived, and asking again won't change that.
    console.warn("Gmail history too old to check");
    return NONE;
  }
  if (!response.ok) return RETRY;
  const body = (await response.json()) as {
    history?: { messagesAdded?: { message?: { id?: unknown } }[] }[];
    nextPageToken?: unknown;
  };
  const ids = new Set<string>();
  for (const record of body.history ?? []) {
    for (const added of record.messagesAdded ?? []) {
      if (typeof added.message?.id === "string") ids.add(added.message.id);
    }
  }
  // History lists oldest first, so the newest are at the end.
  const newest = [...ids].slice(-MOST_CHECKED);
  const states = await Promise.all(newest.map((id) => messageState(token, id, primaryOnly)));
  if (states.includes("retry")) return RETRY;
  return newestOf(states.filter((state) => typeof state === "object"));
}

/** The message as the app would alert for it now, `quiet` when it wouldn't (or it is gone), `retry` when unread. */
async function messageState(
  token: AccessToken,
  id: string,
  primaryOnly: boolean,
): Promise<{ mail: NewMail; at: number } | "quiet" | "retry"> {
  const query = new URLSearchParams([["format", "metadata"], ["metadataHeaders", "From"], ["metadataHeaders", "Subject"]]);
  const response = await fetch(`${GMAIL_API}/messages/${encodeURIComponent(id)}?${query}`, {
    headers: { authorization: `Bearer ${token.value}` },
  });
  if (response.status === 404) return "quiet";
  if (!response.ok) return "retry";
  const message = (await response.json()) as {
    labelIds?: unknown;
    internalDate?: unknown;
    payload?: { headers?: { name?: unknown; value?: unknown }[] };
  };
  if (!Array.isArray(message.labelIds)) return "retry";
  if (!alertsFor(message.labelIds, primaryOnly)) return "quiet";
  const header = (name: string) =>
    message.payload?.headers?.find((entry) => typeof entry.name === "string" && entry.name.toLowerCase() === name)
      ?.value;
  const from = header("from");
  if (typeof from !== "string" || from.trim() === "") return "retry";
  const subject = header("subject");
  return {
    mail: { sender: senderName(from), subject: typeof subject === "string" ? decodeEncodedWords(subject) : "" },
    at: Number(message.internalDate) || 0,
  };
}

/** Gmail's categories other than Primary, whose mail a Primary Only account doesn't alert for. */
const OTHER_CATEGORIES = ["CATEGORY_PROMOTIONS", "CATEGORY_SOCIAL", "CATEGORY_UPDATES", "CATEGORY_FORUMS"];

/** The app alerts for unread Inbox mail it didn't send, from the Primary category alone when `primaryOnly`. */
export function alertsFor(labelIds: unknown[], primaryOnly: boolean): boolean {
  const inPrimary = !OTHER_CATEGORIES.some((category) => labelIds.includes(category));
  return labelIds.includes("INBOX") && labelIds.includes("UNREAD") && !labelIds.includes("SENT") && (!primaryOnly || inPrimary);
}
