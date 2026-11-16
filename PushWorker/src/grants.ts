import { base64Decode, base64UrlEncode, encodeUtf8, toHex } from "./encoding";

/**
 * Each account's Gmail refresh token, stored encrypted. The key comes from EMAIL_HMAC_SECRET through HKDF, so a
 * copy of the database alone reveals no token.
 */
export class GmailGrants {
  private key: Promise<CryptoKey> | undefined;

  constructor(
    private readonly db: D1Database,
    private readonly secret: string,
  ) {}

  async store(account: string, refreshToken: string, now: number): Promise<void> {
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const sealed = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, await this.cipherKey(), encodeUtf8(refreshToken));
    await this.db
      .prepare(
        `INSERT INTO gmail_grants (account, refresh_token, token_hash, updated_at) VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT (account) DO UPDATE SET refresh_token = excluded.refresh_token,
           token_hash = excluded.token_hash, updated_at = excluded.updated_at`,
      )
      .bind(account, `${base64UrlEncode(iv)}.${base64UrlEncode(sealed)}`, await this.hash(refreshToken), now)
      .run();
  }

  /** The account's refresh token, or undefined when it has no grant or the stored one can't be opened. */
  async refreshToken(account: string): Promise<string | undefined> {
    const row = await this.db
      .prepare("SELECT refresh_token FROM gmail_grants WHERE account = ?1")
      .bind(account)
      .first<{ refresh_token: string }>();
    if (!row) return undefined;
    const [iv, sealed] = row.refresh_token.split(".");
    if (!iv || !sealed) return undefined;
    try {
      const plain = await crypto.subtle.decrypt(
        { name: "AES-GCM", iv: base64Decode(iv) },
        await this.cipherKey(),
        base64Decode(sealed),
      );
      return new TextDecoder().decode(plain);
    } catch {
      return undefined;
    }
  }

  /** Whether this exact refresh token is already stored, for any account. */
  async holds(refreshToken: string): Promise<boolean> {
    const row = await this.db
      .prepare("SELECT 1 FROM gmail_grants WHERE token_hash = ?1")
      .bind(await this.hash(refreshToken))
      .first();
    return row !== null;
  }

  async remove(account: string): Promise<void> {
    await this.db.prepare("DELETE FROM gmail_grants WHERE account = ?1").bind(account).run();
  }

  /** HMAC-SHA256 of the token, exactly as sent, under EMAIL_HMAC_SECRET. */
  private async hash(refreshToken: string): Promise<string> {
    const key = await crypto.subtle.importKey("raw", encodeUtf8(this.secret), { name: "HMAC", hash: "SHA-256" }, false, [
      "sign",
    ]);
    return toHex(await crypto.subtle.sign("HMAC", key, encodeUtf8(refreshToken)));
  }

  private cipherKey(): Promise<CryptoKey> {
    this.key ??= (async () => {
      const material = await crypto.subtle.importKey("raw", encodeUtf8(this.secret), "HKDF", false, ["deriveKey"]);
      return crypto.subtle.deriveKey(
        { name: "HKDF", hash: "SHA-256", salt: new Uint8Array(0), info: encodeUtf8("goodmail gmail grants v1") },
        material,
        { name: "AES-GCM", length: 256 },
        false,
        ["encrypt", "decrypt"],
      );
    })();
    return this.key;
  }
}
