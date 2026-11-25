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

  /** Stores the token, with the account's history ID now, which the first notification checks from. */
  async store(account: string, refreshToken: string, primaryOnly: boolean, historyId: string, now: number): Promise<void> {
    await this.db
      .prepare(
        `INSERT INTO gmail_grants (account, refresh_token, token_hash, primary_only, history_id, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)
         ON CONFLICT (account) DO UPDATE SET refresh_token = excluded.refresh_token, token_hash = excluded.token_hash,
           primary_only = excluded.primary_only, history_id = excluded.history_id, updated_at = excluded.updated_at`,
      )
      .bind(
        account,
        await this.sealer.seal(refreshToken),
        await this.sealer.hash(refreshToken),
        primaryOnly ? 1 : 0,
        historyId,
        now,
      )
      .run();
  }

  /**
   * The account's sign-in (the hash of its token, which only a new token changes; null without a grant), its Primary
   * Only choice and the history ID its token was stored at, without opening the token.
   */
  async settings(account: string): Promise<{ signIn: string | null; primaryOnly: boolean; historyId: string | null }> {
    const row = await this.db
      .prepare("SELECT token_hash, primary_only, history_id FROM gmail_grants WHERE account = ?1")
      .bind(account)
      .first<{ token_hash: string; primary_only: number; history_id: string | null }>();
    return { signIn: row?.token_hash ?? null, primaryOnly: row?.primary_only === 1, historyId: row?.history_id ?? null };
  }

  /**
   * The account's refresh token, with the sign-in it comes from (its hash, which only a new token changes), or
   * undefined when it has no grant or the stored one can't be opened.
   */
  async grant(account: string): Promise<{ refreshToken: string; signIn: string } | undefined> {
    const row = await this.db
      .prepare("SELECT refresh_token, token_hash FROM gmail_grants WHERE account = ?1")
      .bind(account)
      .first<{ refresh_token: string; token_hash: string }>();
    const refreshToken = row ? await this.sealer.open(row.refresh_token) : undefined;
    return row && refreshToken ? { refreshToken, signIn: row.token_hash } : undefined;
  }

  /**
   * Takes `primaryOnly` for the account this exact refresh token is stored under. `false` when no account holds it,
   * so the token has to prove itself first.
   */
  async update(refreshToken: string, primaryOnly: boolean): Promise<boolean> {
    const result = await this.db
      .prepare("UPDATE gmail_grants SET primary_only = ?2 WHERE token_hash = ?1")
      .bind(await this.sealer.hash(refreshToken), primaryOnly ? 1 : 0)
      .run();
    return result.meta.changes > 0;
  }

  async remove(account: string): Promise<void> {
    await this.db.prepare("DELETE FROM gmail_grants WHERE account = ?1").bind(account).run();
  }

  /** Deletes the account's token Google refused, unless a new sign-in replaced it meanwhile. */
  async revoke(account: string, signIn: string): Promise<void> {
    await this.db.prepare("DELETE FROM gmail_grants WHERE account = ?1 AND token_hash = ?2").bind(account, signIn).run();
  }
}
