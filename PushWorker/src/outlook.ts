import { type Arrival, NONE, newestOf, RETRY } from "./new-mail";
import { Sealer } from "./sealing";

export const MICROSOFT_TOKEN_URL = "https://login.microsoftonline.com/common/oauth2/v2.0/token";
export const GRAPH_API = "https://graph.microsoft.com/v1.0";
/** Everything the app's sign-in was granted; the relay only reads mail with it. */
const SCOPE = "https://graph.microsoft.com/.default offline_access";
/** Access tokens are reused until this close to expiry. */
const TOKEN_MARGIN_MS = 60_000;

/** Microsoft refused the token (revoked, expired, or the password changed): forget it. */
export class OutlookGrantRevoked extends Error {}

interface MicrosoftToken {
  value: string;
  /** Milliseconds since 1970. */
  expiresAt: number;
  /** Microsoft hands out a new refresh token with each refresh. */
  refreshToken: string | undefined;
}

/** Refreshes `refreshToken` with the app's public client, which has no secret. */
export async function refreshOutlookToken(refreshToken: string, clientId: string, now: number): Promise<MicrosoftToken> {
  const response = await fetch(MICROSOFT_TOKEN_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken, client_id: clientId, scope: SCOPE }),
  });
  const body = (await response.json().catch(() => ({}))) as {
    access_token?: unknown;
    expires_in?: unknown;
    refresh_token?: unknown;
    error?: unknown;
  };
  if (response.status === 400 && body.error === "invalid_grant") throw new OutlookGrantRevoked();
  if (!response.ok || typeof body.access_token !== "string") throw new Error(`Outlook refresh failed with ${response.status}`);
  return {
    value: body.access_token,
    expiresAt: now + (typeof body.expires_in === "number" ? body.expires_in : 3600) * 1000,
    refreshToken: typeof body.refresh_token === "string" ? body.refresh_token : undefined,
  };
}

async function graph<T>(token: MicrosoftToken, path: string): Promise<{ status: number; body?: T }> {
  const response = await fetch(`${GRAPH_API}${path}`, { headers: { authorization: `Bearer ${token.value}` } });
  if (!response.ok) return { status: response.status };
  return { status: response.status, body: (await response.json()) as T };
}

/** Each account's Outlook refresh token, sealed. */
export class OutlookGrants {
  private readonly sealer: Sealer;

  constructor(
    private readonly db: D1Database,
    secret: string,
  ) {
    this.sealer = new Sealer(secret, "goodmail outlook grants v1");
  }

  /** Whether the account already holds the token the app sends, so it needs no new check. */
  async holds(account: string, appToken: string): Promise<boolean> {
    const row = await this.db
      .prepare("SELECT 1 FROM graph_grants WHERE account = ?1 AND token_hash = ?2")
      .bind(account, await this.sealer.hash(appToken))
      .first();
    return row !== null;
  }

  /** Stores `refreshToken` for the account, known by `appToken`'s hash when the app sends it again. */
  async store(account: string, appToken: string, refreshToken: string, now: number): Promise<void> {
    await this.db
      .prepare(
        `INSERT INTO graph_grants (account, refresh_token, token_hash, updated_at) VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT (account) DO UPDATE SET refresh_token = excluded.refresh_token, token_hash = excluded.token_hash,
           updated_at = excluded.updated_at`,
      )
      .bind(account, await this.sealer.seal(refreshToken), await this.sealer.hash(appToken), now)
      .run();
  }

  async grant(account: string): Promise<{ refreshToken: string } | undefined> {
    const row = await this.db
      .prepare("SELECT refresh_token FROM graph_grants WHERE account = ?1")
      .bind(account)
      .first<{ refresh_token: string }>();
    const refreshToken = row ? await this.sealer.open(row.refresh_token) : undefined;
    return refreshToken ? { refreshToken } : undefined;
  }

  /** Keeps the refresh token Microsoft handed out last. */
  async rotate(account: string, refreshToken: string): Promise<void> {
    await this.db
      .prepare("UPDATE graph_grants SET refresh_token = ?2 WHERE account = ?1")
      .bind(account, await this.sealer.seal(refreshToken))
      .run();
  }

  async remove(account: string): Promise<void> {
    await this.db.prepare("DELETE FROM graph_grants WHERE account = ?1").bind(account).run();
  }
}

/**
 * Reads the messages a Graph notification batch named for one account and finds the newest the app alerts for:
 * still in the Inbox and unread (`new-mail.ts`). Without a token nothing alerts.
 */
export class OutlookCheck {
  private readonly tokens = new Map<string, MicrosoftToken>();
  private readonly inboxes = new Map<string, string>();

  constructor(private readonly now: () => number = () => Date.now()) {}

  async arrival(grants: OutlookGrants, clientId: string, account: string, messageIds: string[]): Promise<Arrival> {
    try {
      const grant = await grants.grant(account);
      if (!grant) return NONE;
      const token = await this.token(grants, clientId, account, grant.refreshToken);
      const inbox = await this.inbox(token, account);
      const states = await Promise.all(
        messageIds.map(async (id) => {
          const select = "$select=subject,from,isRead,parentFolderId,receivedDateTime,conversationId";
          const message = await graph<{
            subject?: unknown;
            from?: { emailAddress?: { name?: unknown; address?: unknown } };
            isRead?: unknown;
            parentFolderId?: unknown;
            receivedDateTime?: unknown;
            conversationId?: unknown;
          }>(token, `/me/messages/${encodeURIComponent(id)}?${select}`);
          if (message.status === 404) return "quiet" as const;
          if (!message.body) return "retry" as const;
          const { subject, from, isRead, parentFolderId, receivedDateTime, conversationId } = message.body;
          const address = typeof from?.emailAddress?.address === "string" ? from.emailAddress.address : "";
          if (isRead !== false || parentFolderId !== inbox || !address) return "quiet" as const;
          const name = typeof from?.emailAddress?.name === "string" ? from.emailAddress.name.trim() : "";
          return {
            mail: {
              sender: name || address,
              subject: typeof subject === "string" ? subject : "",
              ...(typeof conversationId === "string" && { threadID: conversationId }),
            },
            at: Date.parse(typeof receivedDateTime === "string" ? receivedDateTime : "") || 0,
          };
        }),
      );
      if (states.includes("retry")) return RETRY;
      return newestOf(states.filter((state) => typeof state === "object"));
    } catch (error) {
      this.tokens.delete(account);
      if (error instanceof OutlookGrantRevoked) {
        await grants.remove(account);
        return NONE;
      }
      console.warn(`Outlook check failed: ${String(error)}`);
      return RETRY;
    }
  }

  forget(account: string): void {
    this.tokens.delete(account);
    this.inboxes.delete(account);
  }

  private async token(grants: OutlookGrants, clientId: string, account: string, refreshToken: string): Promise<MicrosoftToken> {
    const cached = this.tokens.get(account);
    if (cached && cached.expiresAt - this.now() > TOKEN_MARGIN_MS) return cached;
    const token = await refreshOutlookToken(refreshToken, clientId, this.now());
    if (token.refreshToken && token.refreshToken !== refreshToken) await grants.rotate(account, token.refreshToken);
    this.tokens.set(account, token);
    return token;
  }

  private async inbox(token: MicrosoftToken, account: string): Promise<string> {
    const cached = this.inboxes.get(account);
    if (cached) return cached;
    const folder = await graph<{ id?: unknown }>(token, "/me/mailFolders/inbox?$select=id");
    if (typeof folder.body?.id !== "string") throw new Error(`Graph inbox failed with ${folder.status}`);
    this.inboxes.set(account, folder.body.id);
    return folder.body.id;
  }
}
