/** One DER element: its tag byte, its content, and the whole encoding (header and content). */
export interface DerElement {
  tag: number;
  content: Uint8Array<ArrayBuffer>;
  encoded: Uint8Array<ArrayBuffer>;
}

export class DerError extends Error {}

export const DER = {
  SEQUENCE: 0x30,
  SET: 0x31,
  INTEGER: 0x02,
  BIT_STRING: 0x03,
  OCTET_STRING: 0x04,
  OBJECT_IDENTIFIER: 0x06,
  UTC_TIME: 0x17,
  GENERALIZED_TIME: 0x18,
  /** `[n]`, constructed and context-specific: `CONTEXT | n`. */
  CONTEXT: 0xa0,
} as const;

/** Reads the element at `offset` in `bytes`. Only the definite lengths DER allows; no tag above 30. */
export function readElement(bytes: Uint8Array<ArrayBuffer>, offset = 0): DerElement {
  if (offset + 2 > bytes.length) throw new DerError("truncated DER header");
  const tag = bytes[offset]!;
  if ((tag & 0x1f) === 0x1f) throw new DerError("high tag numbers aren't used here");
  let length = bytes[offset + 1]!;
  let header = 2;
  if (length & 0x80) {
    const count = length & 0x7f;
    if (count === 0 || count > 4) throw new DerError("unsupported DER length");
    if (offset + 2 + count > bytes.length) throw new DerError("truncated DER length");
    length = 0;
    for (let i = 0; i < count; i++) length = length * 256 + bytes[offset + 2 + i]!;
    header += count;
  }
  const end = offset + header + length;
  if (end > bytes.length) throw new DerError("truncated DER content");
  return { tag, content: bytes.subarray(offset + header, end), encoded: bytes.subarray(offset, end) };
}

/** The elements inside a constructed element (a SEQUENCE, a SET or an explicit tag). */
export function children(element: DerElement): DerElement[] {
  const found: DerElement[] = [];
  for (let offset = 0; offset < element.content.length; ) {
    const child = readElement(element.content, offset);
    found.push(child);
    offset += child.encoded.length;
  }
  return found;
}

/** Reads `bytes` as exactly one element of `tag`. */
export function expectElement(bytes: Uint8Array<ArrayBuffer>, tag: number): DerElement {
  const element = readElement(bytes);
  if (element.tag !== tag) throw new DerError(`expected tag ${tag}, found ${element.tag}`);
  if (element.encoded.length !== bytes.length) throw new DerError("trailing bytes after DER element");
  return element;
}

/** The dotted form of an OBJECT IDENTIFIER's content, such as `1.2.840.10045.2.1`. */
export function objectIdentifier(content: Uint8Array): string {
  const subidentifiers: number[] = [];
  let value = 0;
  for (const byte of content) {
    value = value * 128 + (byte & 0x7f);
    if (!(byte & 0x80)) {
      subidentifiers.push(value);
      value = 0;
    }
  }
  const [first, ...rest] = subidentifiers;
  if (first === undefined || value !== 0) throw new DerError("malformed OID");
  // The first subidentifier packs the first two arcs: 40 * arc1 + arc2, where arc1 is 0, 1 or 2.
  const arc = Math.min(2, Math.floor(first / 40));
  return [arc, first - arc * 40, ...rest].join(".");
}

/** A UTCTime or GeneralizedTime in its `Z` form, as milliseconds since 1970. */
export function time(element: DerElement): number {
  const text = new TextDecoder().decode(element.content);
  const match =
    element.tag === DER.UTC_TIME
      ? /^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(text)
      : /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(text);
  if (!match) throw new DerError("unsupported time");
  const [, y, mo, d, h, mi, s] = match.map(Number) as [number, number, number, number, number, number, number];
  // RFC 5280: a two-digit year below 50 is 20xx.
  const year = element.tag === DER.UTC_TIME ? (y < 50 ? 2000 + y : 1900 + y) : y;
  return Date.UTC(year, mo - 1, d, h, mi, s);
}

/**
 * An ECDSA signature as WebCrypto wants it, `r || s` with each half `size` bytes, from the DER
 * `SEQUENCE { INTEGER r, INTEGER s }` that X.509 and App Attest use.
 */
export function rawSignature(der: Uint8Array<ArrayBuffer>, size: number): Uint8Array<ArrayBuffer> {
  const [r, s] = children(expectElement(der, DER.SEQUENCE));
  if (!r || !s || r.tag !== DER.INTEGER || s.tag !== DER.INTEGER) throw new DerError("bad ECDSA signature");
  const raw = new Uint8Array(size * 2);
  for (const [index, integer] of [r, s].entries()) {
    let value = integer.content;
    while (value.length > size && value[0] === 0) value = value.subarray(1);
    if (value.length > size) throw new DerError("ECDSA integer too long");
    raw.set(value, index * size + size - value.length);
  }
  return raw;
}
