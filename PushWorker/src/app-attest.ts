import { bytesField, decodeCbor, field } from "./cbor";
import { children, DER, expectElement, rawSignature } from "./der";
import { encodeUtf8 } from "./encoding";
import { type Certificate, isAuthority, isIssuedBy, parseCertificate, sameBytes } from "./x509";

/**
 * Apple's App Attest checks (https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server).
 * An attestation proves a key lives in the Secure Enclave of a genuine Apple device, inside the app whose App ID is
 * `appId` (team ID, a dot, bundle ID), so a build of the public source under another team can't make one. Each later
 * request carries an assertion: that key's signature over the request.
 */

/** Which App Attest environment made the key: Xcode builds use development, TestFlight and the App Store production. */
export type AttestEnvironment = "development" | "production";

/** A key whose attestation checked out, to keep for verifying its assertions. */
export interface AttestedKey {
  /** The uncompressed P-256 point, whose SHA-256 is the key ID. */
  publicKey: Uint8Array<ArrayBuffer>;
  environment: AttestEnvironment;
}

export class AttestationRejected extends Error {}

const NONCE_EXTENSION = "1.2.840.113635.100.8.2";
const AAGUIDS: [Uint8Array, AttestEnvironment][] = [
  [encodeUtf8("appattestdevelop"), "development"],
  [new Uint8Array([...encodeUtf8("appattest"), 0, 0, 0, 0, 0, 0, 0]), "production"],
];

/** Verifies an attestation of `keyId` made for `challenge`, against Apple's App Attestation root. */
export async function verifyAttestation(input: {
  attestation: Uint8Array<ArrayBuffer>;
  keyId: Uint8Array<ArrayBuffer>;
  challenge: Uint8Array<ArrayBuffer>;
  appId: string;
  root: Certificate;
  now: number;
}): Promise<AttestedKey> {
  const { attestation, keyId, challenge, appId, root, now } = input;
  const object = decodeCbor(attestation);
  if (field(object, "fmt") !== "apple-appattest") throw new AttestationRejected("not an App Attest attestation");
  const statement = field(object, "attStmt");
  const chain = statement === undefined ? undefined : field(statement, "x5c");
  if (!Array.isArray(chain) || chain.length !== 2) throw new AttestationRejected("expected a leaf and an intermediate");
  const [leaf, intermediate] = chain.map((der) => {
    if (!(der instanceof Uint8Array)) throw new AttestationRejected("certificates must be byte strings");
    return parseCertificate(der);
  }) as [Certificate, Certificate];

  // 1. The leaf chains to Apple's root through a CA, and each is valid now.
  for (const certificate of [leaf, intermediate, root]) {
    if (now < certificate.notBefore || now > certificate.notAfter) throw new AttestationRejected("certificate not valid now");
  }
  if (!isAuthority(intermediate) || !(await isIssuedBy(intermediate, root)) || !(await isIssuedBy(leaf, intermediate))) {
    throw new AttestationRejected("the chain doesn't lead to Apple's App Attestation root");
  }

  // 2–4. The leaf vouches for this authenticator data and this challenge.
  const authData = bytesField(object, "authData");
  const nonce = await sha256(concat(authData, await sha256(challenge)));
  if (!sameBytes(certificateNonce(leaf), nonce)) throw new AttestationRejected("nonce mismatch");

  // 5. The key is the one the app named.
  if (!sameBytes(await sha256(leaf.publicKey), keyId)) throw new AttestationRejected("key ID mismatch");

  // 6–9. Made for this App ID, never used, with a known environment, and for this key.
  const data = authenticatorData(authData);
  if (!sameBytes(data.rpIdHash, await sha256(encodeUtf8(appId)))) throw new AttestationRejected("another app's key");
  if (data.counter !== 0) throw new AttestationRejected("a fresh key's counter is 0");
  const environment = AAGUIDS.find(([aaguid]) => sameBytes(aaguid, data.aaguid))?.[1];
  if (!environment) throw new AttestationRejected("unknown App Attest environment");
  if (!sameBytes(data.credentialId, keyId)) throw new AttestationRejected("credential ID mismatch");

  return { publicKey: leaf.publicKey, environment };
}

/**
 * Verifies an assertion of `clientDataHash` by a key attested earlier, and returns its counter. The counter goes up
 * by one with each assertion the device makes.
 */
export async function verifyAssertion(input: {
  assertion: Uint8Array<ArrayBuffer>;
  clientDataHash: Uint8Array<ArrayBuffer>;
  publicKey: Uint8Array<ArrayBuffer>;
  appId: string;
}): Promise<number> {
  const { assertion, clientDataHash, publicKey, appId } = input;
  const object = decodeCbor(assertion);
  const authenticator = bytesField(object, "authenticatorData");
  const key = await crypto.subtle.importKey("raw", publicKey, { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
  const signature = rawSignature(bytesField(object, "signature"), 32);
  // The device signs SHA-256(authenticatorData || clientDataHash), which ECDSA-SHA-256 hashes once more.
  const nonce = await sha256(concat(authenticator, clientDataHash));
  if (!(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, signature, nonce))) {
    throw new AttestationRejected("bad assertion signature");
  }
  if (authenticator.length < 37) throw new AttestationRejected("short authenticator data");
  if (!sameBytes(authenticator.subarray(0, 32), await sha256(encodeUtf8(appId)))) {
    throw new AttestationRejected("another app's assertion");
  }
  return new DataView(authenticator.buffer, authenticator.byteOffset).getUint32(33);
}

export async function sha256(data: Uint8Array<ArrayBuffer>): Promise<Uint8Array<ArrayBuffer>> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", data));
}

export function concat(...parts: Uint8Array[]): Uint8Array<ArrayBuffer> {
  const joined = new Uint8Array(parts.reduce((total, part) => total + part.length, 0));
  let offset = 0;
  for (const part of parts) {
    joined.set(part, offset);
    offset += part.length;
  }
  return joined;
}

/** The nonce in the leaf's Apple extension: `SEQUENCE { [1] EXPLICIT OCTET STRING }`. */
function certificateNonce(leaf: Certificate): Uint8Array<ArrayBuffer> {
  const value = leaf.extensions.get(NONCE_EXTENSION);
  if (!value) throw new AttestationRejected("no nonce in the certificate");
  const tagged = children(expectElement(value, DER.SEQUENCE)).find((element) => element.tag === (DER.CONTEXT | 1));
  const [octets] = tagged ? children(tagged) : [];
  if (octets?.tag !== DER.OCTET_STRING) throw new AttestationRejected("malformed nonce");
  return octets.content;
}

/** WebAuthn authenticator data as App Attest lays it out. */
function authenticatorData(data: Uint8Array<ArrayBuffer>) {
  if (data.length < 55) throw new AttestationRejected("short authenticator data");
  const view = new DataView(data.buffer, data.byteOffset, data.length);
  const idLength = view.getUint16(53);
  if (data.length < 55 + idLength) throw new AttestationRejected("short credential ID");
  return {
    rpIdHash: data.subarray(0, 32),
    counter: view.getUint32(33),
    aaguid: data.subarray(37, 53),
    credentialId: data.subarray(55, 55 + idLength),
  };
}
