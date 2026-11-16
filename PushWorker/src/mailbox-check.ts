import { type AccessToken, GrantRevoked, inboxChange, refreshAccessToken } from "./gmail";
import type { GmailGrants } from "./grants";

/** Access tokens are reused until this close to expiry. */
const TOKEN_MARGIN_MS = 60_000;

/**
 * Decides whether a Gmail notification alerts: only when its history shows new Inbox mail. Anything it can't tell
 * (no grant, no earlier history ID, Google unreachable) alerts, as before the check existed, and the device's
 * extension sorts it out.
 */
export class MailboxCheck {
  /** Access tokens by account, shared by the requests this isolate serves. */
  private readonly tokens = new Map<string, AccessToken>();

  constructor(private readonly now: () => number = () => Date.now()) {}

  async verdict(
    grants: GmailGrants,
    clientId: string,
    account: string,
    previousHistoryId: string | null,
  ): Promise<"alert" | "quiet"> {
    if (previousHistoryId === null) return "alert";
    try {
      const token = await this.token(grants, clientId, account);
      if (!token) return "alert";
      const change = await inboxChange(token, previousHistoryId.replace(/^0+(?=\d)/, ""));
      if (change === "unknown") this.tokens.delete(account);
      return change === "none" ? "quiet" : "alert";
    } catch (error) {
      this.tokens.delete(account);
      if (error instanceof GrantRevoked) await grants.remove(account);
      else console.warn(`Gmail check failed: ${String(error)}`);
      return "alert";
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
