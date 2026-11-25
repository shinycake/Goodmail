import { AccessTokens, GrantChanged } from "./access-tokens";
import { type AccessToken, GrantRevoked, inboxArrival, refreshAccessToken } from "./gmail";
import type { GmailGrants } from "./grants";
import { type Arrival, NONE, RETRY } from "./new-mail";

/**
 * Reads what a Gmail notification brought, with the app's own token for the account (`new-mail.ts` decides what
 * alerts). Without a token there is no way to read the mail, so nothing alerts; a token Google stopped honoring is
 * forgotten until the app sends a new one.
 */
export class MailboxCheck {
  /** Access tokens by account, shared by the requests this isolate serves. */
  private readonly tokens: AccessTokens<AccessToken>;

  constructor(private readonly now: () => number = () => Date.now()) {
    this.tokens = new AccessTokens(now);
  }

  /** What arrived since `previousHistoryId`, or since the token was stored when this is the first notification. */
  async arrival(grants: GmailGrants, clientId: string, account: string, previousHistoryId: string | null): Promise<Arrival> {
    try {
      const settings = await grants.settings(account);
      const { signIn } = settings;
      if (signIn === null) return NONE;
      const token = await this.tokens.token(account, signIn, () => this.refresh(grants, clientId, account, signIn));
      const start = previousHistoryId ?? settings.historyId;
      if (start === null) return NONE;
      const arrival = await inboxArrival(token, start.replace(/^0+(?=\d)/, ""), settings.primaryOnly);
      if (arrival.kind === "retry") this.tokens.forget(account);
      return arrival;
    } catch (error) {
      this.tokens.forget(account);
      if (error instanceof GrantRevoked) return NONE;
      console.warn(`Gmail check failed: ${String(error)}`);
      return RETRY;
    }
  }

  forget(account: string): void {
    this.tokens.forget(account);
  }

  /** Refreshes the token of the sign-in `signIn`; one Google refuses is forgotten, unless a new one replaced it. */
  private async refresh(grants: GmailGrants, clientId: string, account: string, signIn: string): Promise<AccessToken> {
    const grant = await grants.grant(account);
    if (grant?.signIn !== signIn) throw new GrantChanged();
    try {
      return await refreshAccessToken(grant.refreshToken, clientId, this.now());
    } catch (error) {
      if (error instanceof GrantRevoked) await grants.revoke(account, signIn);
      throw error;
    }
  }
}
