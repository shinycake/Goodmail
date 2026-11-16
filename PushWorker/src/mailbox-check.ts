import { type AccessToken, GrantRevoked, inboxArrival, refreshAccessToken } from "./gmail";
import type { GmailGrants } from "./grants";
import { type Arrival, NONE, RETRY } from "./new-mail";

/** Access tokens are reused until this close to expiry. */
const TOKEN_MARGIN_MS = 60_000;

/**
 * Reads what a Gmail notification brought, with the app's own token for the account (`new-mail.ts` decides what
 * alerts). Without a token there is no way to read the mail, so nothing alerts; a token Google stopped honoring is
 * forgotten until the app sends a new one.
 */
export class MailboxCheck {
  /** Access tokens by account, shared by the requests this isolate serves. */
  private readonly tokens = new Map<string, AccessToken>();

  constructor(private readonly now: () => number = () => Date.now()) {}

  /** What arrived since `previousHistoryId`, or since the token was stored when this is the first notification. */
  async arrival(grants: GmailGrants, clientId: string, account: string, previousHistoryId: string | null): Promise<Arrival> {
    try {
      const token = await this.token(grants, clientId, account);
      if (!token) return NONE;
      const settings = await grants.settings(account);
      const start = previousHistoryId ?? settings.historyId;
      if (start === null) return NONE;
      const arrival = await inboxArrival(token, start.replace(/^0+(?=\d)/, ""), settings.primaryOnly);
      if (arrival.kind === "retry") this.tokens.delete(account);
      return arrival;
    } catch (error) {
      this.tokens.delete(account);
      if (error instanceof GrantRevoked) {
        await grants.remove(account);
        return NONE;
      }
      console.warn(`Gmail check failed: ${String(error)}`);
      return RETRY;
    }
  }

  forget(account: string): void {
    this.tokens.delete(account);
  }

  private async token(grants: GmailGrants, clientId: string, account: string): Promise<AccessToken | undefined> {
    const cached = this.tokens.get(account);
    if (cached && cached.expiresAt - this.now() > TOKEN_MARGIN_MS) return cached;
    const refreshToken = await grants.refreshToken(account);
    if (!refreshToken) return undefined;
    const token = await refreshAccessToken(refreshToken, clientId, this.now());
    this.tokens.set(account, token);
    return token;
  }
}
