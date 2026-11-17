import { children, DER, type DerElement, DerError, expectElement, objectIdentifier, rawSignature, time } from "./der";

/** The parts of an X.509 certificate App Attest needs: what was signed, how, and the key and extensions it carries. */
export interface Certificate {
  tbs: Uint8Array<ArrayBuffer>;
  signatureHash: "SHA-256" | "SHA-384";
  /** The issuer's DER signature over `tbs`. */
  signature: Uint8Array<ArrayBuffer>;
  issuer: Uint8Array<ArrayBuffer>;
  subject: Uint8Array<ArrayBuffer>;
  notBefore: number;
  notAfter: number;
  /** The whole SubjectPublicKeyInfo, for `importKey("spki")`. */
  spki: Uint8Array<ArrayBuffer>;
  curve: Curve;
  /** The uncompressed EC point, `04 || x || y`. */
  publicKey: Uint8Array<ArrayBuffer>;
  /** Each extension's value (the OCTET STRING's content), by dotted OID. */
  extensions: Map<string, Uint8Array<ArrayBuffer>>;
}

export type Curve = "P-256" | "P-384";

const SIGNATURE_HASHES: Record<string, Certificate["signatureHash"]> = {
  "1.2.840.10045.4.3.2": "SHA-256",
  "1.2.840.10045.4.3.3": "SHA-384",
};
const EC_PUBLIC_KEY = "1.2.840.10045.2.1";
const CURVES: Record<string, Curve> = { "1.2.840.10045.3.1.7": "P-256", "1.3.132.0.34": "P-384" };
/** The bytes of one coordinate, which is also each half of a raw signature. */
const COORDINATE_SIZE: Record<Curve, number> = { "P-256": 32, "P-384": 48 };
const BASIC_CONSTRAINTS = "2.5.29.19";

/** Parses a DER certificate whose key is on P-256 or P-384 and whose signature is ECDSA, the only kind App Attest uses. */
export function parseCertificate(der: Uint8Array<ArrayBuffer>): Certificate {
  const [tbsElement, algorithm, signatureBits] = children(expectElement(der, DER.SEQUENCE));
  if (!tbsElement || !algorithm || signatureBits?.tag !== DER.BIT_STRING) throw new DerError("malformed certificate");
  const signatureHash = SIGNATURE_HASHES[algorithmOid(algorithm)];
  if (!signatureHash) throw new DerError("unsupported signature algorithm");

  const fields = children(tbsElement);
  // An explicit [0] version comes first in v3 certificates.
  const rest = fields[0]?.tag === DER.CONTEXT ? fields.slice(1) : fields;
  const [, , issuer, validity, subject, spki, ...optional] = rest;
  if (!issuer || !validity || !subject || spki?.tag !== DER.SEQUENCE) throw new DerError("malformed certificate");
  const [notBefore, notAfter] = children(validity);
  if (!notBefore || !notAfter) throw new DerError("malformed validity");

  const [keyAlgorithm, keyBits] = children(spki);
  if (!keyAlgorithm || keyBits?.tag !== DER.BIT_STRING) throw new DerError("malformed public key");
  const [keyType, curveOid] = children(keyAlgorithm);
  if (!keyType || objectIdentifier(keyType.content) !== EC_PUBLIC_KEY || !curveOid) throw new DerError("not an EC key");
  const curve = CURVES[objectIdentifier(curveOid.content)];
  if (!curve) throw new DerError("unsupported curve");

  return {
    tbs: tbsElement.encoded,
    signatureHash,
    signature: bitStringBytes(signatureBits),
    issuer: issuer.encoded,
    subject: subject.encoded,
    notBefore: time(notBefore),
    notAfter: time(notAfter),
    spki: spki.encoded,
    curve,
    publicKey: bitStringBytes(keyBits),
    extensions: extensionsOf(optional),
  };
}

/** Whether `child` was issued by `issuer`: the names chain and `issuer`'s key verifies `child`'s signature. */
export async function isIssuedBy(child: Certificate, issuer: Certificate): Promise<boolean> {
  if (!sameBytes(child.issuer, issuer.subject)) return false;
  const key = await importPublicKey(issuer);
  const signature = rawSignature(child.signature, COORDINATE_SIZE[issuer.curve]);
  return crypto.subtle.verify({ name: "ECDSA", hash: child.signatureHash }, key, signature, child.tbs);
}

/** Whether the certificate is a CA's: basic constraints with cA set. */
export function isAuthority(certificate: Certificate): boolean {
  const value = certificate.extensions.get(BASIC_CONSTRAINTS);
  if (!value) return false;
  const [flag] = children(expectElement(value, DER.SEQUENCE));
  return flag?.tag === 0x01 && flag.content[0] === 0xff;
}

export function importPublicKey(certificate: Certificate): Promise<CryptoKey> {
  return crypto.subtle.importKey("spki", certificate.spki, { name: "ECDSA", namedCurve: certificate.curve }, false, [
    "verify",
  ]);
}

export function coordinateSize(curve: Curve): number {
  return COORDINATE_SIZE[curve];
}

/** Decodes a PEM certificate. */
export function pemCertificate(pem: string): Certificate {
  const body = pem.replace(/-----(BEGIN|END) CERTIFICATE-----/g, "").replace(/\s+/g, "");
  const binary = atob(body);
  const der = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) der[i] = binary.charCodeAt(i);
  return parseCertificate(der);
}

export function sameBytes(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a[i]! ^ b[i]!;
  return difference === 0;
}

function algorithmOid(algorithm: DerElement): string {
  const [oid] = children(algorithm);
  if (oid?.tag !== DER.OBJECT_IDENTIFIER) throw new DerError("malformed algorithm");
  return objectIdentifier(oid.content);
}

/** A BIT STRING's bytes, which for keys and signatures always start on a byte boundary. */
function bitStringBytes(element: DerElement): Uint8Array<ArrayBuffer> {
  if (element.content[0] !== 0) throw new DerError("unaligned bit string");
  return element.content.subarray(1);
}

function extensionsOf(optional: DerElement[]): Map<string, Uint8Array<ArrayBuffer>> {
  const extensions = new Map<string, Uint8Array<ArrayBuffer>>();
  const wrapper = optional.find((element) => element.tag === (DER.CONTEXT | 3));
  if (!wrapper) return extensions;
  const [list] = children(wrapper);
  if (list?.tag !== DER.SEQUENCE) throw new DerError("malformed extensions");
  for (const extension of children(list)) {
    const parts = children(extension);
    const oid = parts[0];
    const value = parts[parts.length - 1];
    if (oid?.tag !== DER.OBJECT_IDENTIFIER || value?.tag !== DER.OCTET_STRING) throw new DerError("malformed extension");
    extensions.set(objectIdentifier(oid.content), value.content);
  }
  return extensions;
}
