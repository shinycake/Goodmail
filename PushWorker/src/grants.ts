import { Sealer } from "./sealing";

/** Each account's Gmail refresh token, sealed (`Sealer`), so a copy of the database alone reveals no token. */
export class GmailGrants {
  private readonly sealer: Sealer;

  constructor(
    private readonly db: D1Database,
    secret: string,
  ) {
    this.sealer = new Sealer(secret, "goodmail gmail grants v1");
  }

  async store(account: string, refreshToken: string, now: number): Promise<void> {
    await this.db
      .prepare(
        `INSERT INTO gmail_grants (account, refresh_token, token_hash, updated_at) VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT (account) DO UPDATE SET refresh_token = excluded.refresh_token,
           token_hash = excluded.token_hash, updated_at = excluded.updated_at`,
      )
      .bind(account, await this.sealer.seal(refreshToken), await this.sealer.hash(refreshToken), now)
      .run();
  }

  /** The account's refresh token, or undefined when it has no grant or the stored one can't be opened. */
  async refreshToken(account: string): Promise<string | undefined> {
    const row = await this.db
      .prepare("SELECT refresh_token FROM gmail_grants WHERE account = ?1")
      .bind(account)
      .first<{ refresh_token: string }>();
    return row ? this.sealer.open(row.refresh_token) : undefined;
  }

  /** Whether this exact refresh token is already stored, for any account. */
  async holds(refreshToken: string): Promise<boolean> {
    const row = await this.db
      .prepare("SELECT 1 FROM gmail_grants WHERE token_hash = ?1")
      .bind(await this.sealer.hash(refreshToken))
      .first();
    return row !== null;
  }

  async remove(account: string): Promise<void> {
    await this.db.prepare("DELETE FROM gmail_grants WHERE account = ?1").bind(account).run();
  }
}
