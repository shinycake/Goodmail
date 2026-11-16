import { base64Decode, base64UrlEncode, encodeUtf8, toHex } from "./encoding";

/**
 * Encrypts secrets the relay keeps (Gmail refresh tokens, IMAP logins) with AES-GCM under a key derived from
 * EMAIL_HMAC_SECRET through HKDF, so a copy of the database alone reveals none of them. Each kind of secret gets its
 * own key, named by `info`.
 */
export class Sealer {
  private key: Promise<CryptoKey> | undefined;

  constructor(
    private readonly secret: string,
    private readonly info: string,
  ) {}

  /** `iv.ciphertext`, both base64url. */
  async seal(plain: string): Promise<string> {
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const sealed = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, await this.cipherKey(), encodeUtf8(plain));
    return `${base64UrlEncode(iv)}.${base64UrlEncode(sealed)}`;
  }

  /** The plain text, or undefined when `sealed` is malformed or wasn't sealed under this key. */
  async open(sealed: string): Promise<string | undefined> {
    const [iv, ciphertext] = sealed.split(".");
    if (!iv || !ciphertext) return undefined;
    try {
      const plain = await crypto.subtle.decrypt(
        { name: "AES-GCM", iv: base64Decode(iv) },
        await this.cipherKey(),
        base64Decode(ciphertext),
      );
      return new TextDecoder().decode(plain);
    } catch {
      return undefined;
    }
  }

  /** HMAC-SHA256 of `text`, exactly as given, under EMAIL_HMAC_SECRET: matches a secret without opening it. */
  async hash(text: string): Promise<string> {
    const key = await crypto.subtle.importKey("raw", encodeUtf8(this.secret), { name: "HMAC", hash: "SHA-256" }, false, [
      "sign",
    ]);
    return toHex(await crypto.subtle.sign("HMAC", key, encodeUtf8(text)));
  }

  private cipherKey(): Promise<CryptoKey> {
    this.key ??= (async () => {
      const material = await crypto.subtle.importKey("raw", encodeUtf8(this.secret), "HKDF", false, ["deriveKey"]);
      return crypto.subtle.deriveKey(
        { name: "HKDF", hash: "SHA-256", salt: new Uint8Array(0), info: encodeUtf8(this.info) },
        material,
        { name: "AES-GCM", length: 256 },
        false,
        ["encrypt", "decrypt"],
      );
    })();
    return this.key;
  }
}
