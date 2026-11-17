import { concat, sha256 } from "../src/app-attest";
import { encodeUtf8 } from "../src/encoding";
import { parseCertificate, type Certificate } from "../src/x509";

/**
 * A stand-in for Apple's App Attest: a root and intermediate CA, and a device that attests P-256 keys and signs
 * assertions the way iOS does, so the relay's checks run against real signatures and real DER.
 */

export const APP_ID = "TEAM123456.com.idanbirman.goodmail";
export const NOW = Date.UTC(2026, 10, 17, 12);
const YEAR = 365 * 24 * 60 * 60_000;

// MARK: - DER and CBOR writers

function length(size: number): number[] {
  if (size < 0x80) return [size];
  const bytes: number[] = [];
  for (let rest = size; rest > 0; rest = Math.floor(rest / 256)) bytes.unshift(rest % 256);
  return [0x80 | bytes.length, ...bytes];
}

export function der(tag: number, ...parts: Uint8Array[]): Uint8Array<ArrayBuffer> {
  const content = concat(...parts);
  return concat(new Uint8Array([tag, ...length(content.length)]), content);
}

export function oid(dotted: string): Uint8Array<ArrayBuffer> {
  const [a, b, ...rest] = dotted.split(".").map(Number) as [number, number, ...number[]];
  const bytes = [40 * a + b];
  for (const arc of rest) {
    const groups = [arc & 0x7f];
    for (let value = Math.floor(arc / 128); value > 0; value = Math.floor(value / 128)) groups.unshift(0x80 | (value & 0x7f));
    bytes.push(...groups);
  }
  return der(0x06, new Uint8Array(bytes));
}

function utcTime(ms: number): Uint8Array<ArrayBuffer> {
  const iso = new Date(ms).toISOString();
  const text = iso.slice(2, 4) + iso.slice(5, 7) + iso.slice(8, 10) + iso.slice(11, 13) + iso.slice(14, 16) + iso.slice(17, 19) + "Z";
  return der(0x17, encodeUtf8(text));
}

function name(commonName: string): Uint8Array<ArrayBuffer> {
  return der(0x30, der(0x31, der(0x30, oid("2.5.4.3"), der(0x0c, encodeUtf8(commonName)))));
}

/** ECDSA's raw `r || s` as DER, the way X.509 and App Attest carry it. */
function derSignature(raw: Uint8Array): Uint8Array<ArrayBuffer> {
  const half = raw.length / 2;
  const integer = (bytes: Uint8Array) => {
    let start = 0;
    while (start < bytes.length - 1 && bytes[start] === 0) start++;
    const trimmed = bytes.subarray(start);
    return der(0x02, trimmed[0]! & 0x80 ? concat(new Uint8Array([0]), trimmed) : trimmed);
  };
  return der(0x30, integer(raw.subarray(0, half)), integer(raw.subarray(half)));
}

type Cbor = number | string | Uint8Array | Cbor[] | Map<string, Cbor>;

export function cbor(value: Cbor): Uint8Array<ArrayBuffer> {
  const head = (major: number, size: number) => {
    if (size < 24) return new Uint8Array([(major << 5) | size]);
    if (size < 256) return new Uint8Array([(major << 5) | 24, size]);
    if (size < 65_536) return new Uint8Array([(major << 5) | 25, size >> 8, size & 0xff]);
    return new Uint8Array([(major << 5) | 26, size >>> 24, (size >> 16) & 0xff, (size >> 8) & 0xff, size & 0xff]);
  };
  if (typeof value === "number") return head(0, value);
  if (typeof value === "string") return concat(head(3, encodeUtf8(value).length), encodeUtf8(value));
  if (value instanceof Uint8Array) return concat(head(2, value.length), value);
  if (Array.isArray(value)) return concat(head(4, value.length), ...value.map(cbor));
  return concat(head(5, value.size), ...[...value].flatMap(([key, item]) => [cbor(key), cbor(item)]));
}

// MARK: - Certificates

interface Authority {
  keys: CryptoKeyPair;
  curve: "P-256" | "P-384";
  name: string;
  certificate: Uint8Array<ArrayBuffer>;
}

const SIGNATURE_OIDS = { "SHA-256": "1.2.840.10045.4.3.2", "SHA-384": "1.2.840.10045.4.3.3" } as const;
const CURVE_HASH = { "P-256": "SHA-256", "P-384": "SHA-384" } as const;

async function certificate(input: {
  subject: string;
  subjectKey: CryptoKey;
  issuer: { name: string; key: CryptoKey; curve: "P-256" | "P-384" };
  authority: boolean;
  extensions?: Uint8Array[];
  notBefore?: number;
  notAfter?: number;
}): Promise<Uint8Array<ArrayBuffer>> {
  const hash = CURVE_HASH[input.issuer.curve];
  const algorithm = der(0x30, oid(SIGNATURE_OIDS[hash]));
  const spki = new Uint8Array((await crypto.subtle.exportKey("spki", input.subjectKey)) as ArrayBuffer);
  const extensions = [...(input.extensions ?? [])];
  if (input.authority) {
    extensions.push(der(0x30, oid("2.5.29.19"), der(0x01, new Uint8Array([0xff])), der(0x04, der(0x30, der(0x01, new Uint8Array([0xff]))))));
  }
  const tbs = der(
    0x30,
    der(0xa0, der(0x02, new Uint8Array([2]))),
    der(0x02, new Uint8Array([1])),
    algorithm,
    name(input.issuer.name),
    der(0x30, utcTime(input.notBefore ?? NOW - YEAR), utcTime(input.notAfter ?? NOW + YEAR)),
    name(input.subject),
    spki,
    ...(extensions.length > 0 ? [der(0xa3, der(0x30, ...extensions))] : []),
  );
  const raw = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash }, input.issuer.key, tbs),
  );
  return der(0x30, tbs, algorithm, der(0x03, new Uint8Array([0]), derSignature(raw)));
}

async function authority(name: string, curve: "P-256" | "P-384", issuer?: Authority): Promise<Authority> {
  const keys = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: curve }, true, ["sign", "verify"])) as CryptoKeyPair;
  const signer = issuer ? { name: issuer.name, key: issuer.keys.privateKey, curve: issuer.curve } : { name, key: keys.privateKey, curve };
  const encoded = await certificate({ subject: name, subjectKey: keys.publicKey, issuer: signer, authority: true });
  return { keys, curve, name, certificate: encoded };
}

// MARK: - Apple

export interface FakeApple {
  root: Certificate;
  intermediate: Authority;
}

export async function fakeApple(): Promise<FakeApple> {
  const root = await authority("Apple App Attestation Root CA", "P-384");
  const intermediate = await authority("Apple App Attestation CA 1", "P-384", root);
  return { root: parseCertificate(root.certificate), intermediate };
}

/** One install's App Attest key. */
export interface FakeKey {
  keys: CryptoKeyPair;
  publicKey: Uint8Array<ArrayBuffer>;
  keyId: Uint8Array<ArrayBuffer>;
  counter: number;
}

export async function fakeKey(): Promise<FakeKey> {
  const keys = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const publicKey = new Uint8Array((await crypto.subtle.exportKey("raw", keys.publicKey)) as ArrayBuffer);
  return { keys, publicKey, keyId: await sha256(publicKey), counter: 0 };
}

export interface AttestationOptions {
  appId?: string;
  aaguid?: Uint8Array;
  counter?: number;
  /** Signs the leaf with this authority instead of Apple's intermediate. */
  issuer?: Authority;
  /** Vouches for another challenge than the one given. */
  nonceChallenge?: Uint8Array<ArrayBuffer>;
  /** Puts another key's ID in the authenticator data. */
  credentialId?: Uint8Array;
}

export const PRODUCTION_AAGUID = new Uint8Array([...encodeUtf8("appattest"), 0, 0, 0, 0, 0, 0, 0]);

/** What `DCAppAttestService.attestKey` returns for `challenge` (whose SHA-256 is the client data hash). */
export async function attest(
  apple: FakeApple,
  key: FakeKey,
  challenge: Uint8Array<ArrayBuffer>,
  options: AttestationOptions = {},
): Promise<Uint8Array<ArrayBuffer>> {
  const credentialId = options.credentialId ?? key.keyId;
  const counter = new Uint8Array(4);
  new DataView(counter.buffer).setUint32(0, options.counter ?? 0);
  const authData = concat(
    await sha256(encodeUtf8(options.appId ?? APP_ID)),
    new Uint8Array([0x40]),
    counter,
    options.aaguid ?? PRODUCTION_AAGUID,
    new Uint8Array([credentialId.length >> 8, credentialId.length & 0xff]),
    credentialId,
  );
  const nonce = await sha256(concat(authData, await sha256(options.nonceChallenge ?? challenge)));
  const issuer = options.issuer ?? apple.intermediate;
  const leaf = await certificate({
    subject: "leaf",
    subjectKey: key.keys.publicKey,
    issuer: { name: issuer.name, key: issuer.keys.privateKey, curve: issuer.curve },
    authority: false,
    extensions: [der(0x30, oid("1.2.840.113635.100.8.2"), der(0x04, der(0x30, der(0xa1, der(0x04, nonce)))))],
  });
  return cbor(
    new Map<string, Cbor>([
      ["fmt", "apple-appattest"],
      ["attStmt", new Map<string, Cbor>([["x5c", [leaf, apple.intermediate.certificate]], ["receipt", new Uint8Array([1])]])],
      ["authData", authData],
    ]),
  );
}

/** What `DCAppAttestService.generateAssertion` returns for `clientDataHash`. */
export async function assert(
  key: FakeKey,
  clientDataHash: Uint8Array<ArrayBuffer>,
  appId = APP_ID,
): Promise<Uint8Array<ArrayBuffer>> {
  key.counter += 1;
  const counter = new Uint8Array(4);
  new DataView(counter.buffer).setUint32(0, key.counter);
  const authenticatorData = concat(await sha256(encodeUtf8(appId)), new Uint8Array([0x40]), counter);
  const nonce = await sha256(concat(authenticatorData, clientDataHash));
  const raw = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key.keys.privateKey, nonce));
  return cbor(new Map<string, Cbor>([["signature", derSignature(raw)], ["authenticatorData", authenticatorData]]));
}

export function base64(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes));
}
