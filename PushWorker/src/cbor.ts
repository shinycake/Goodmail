/** A decoded CBOR value, limited to what App Attest sends: unsigned integers, byte and text strings, arrays and maps. */
export type CborValue = number | Uint8Array<ArrayBuffer> | string | CborValue[] | Map<CborValue, CborValue>;

export class CborError extends Error {}

/** Decodes `bytes` as exactly one CBOR item (RFC 8949), with definite lengths only. */
export function decodeCbor(bytes: Uint8Array<ArrayBuffer>): CborValue {
  const reader = new Reader(bytes);
  const value = reader.item(0);
  if (reader.offset !== bytes.length) throw new CborError("trailing bytes after CBOR item");
  return value;
}

/** A map's value for a text key, or undefined. */
export function field(value: CborValue, key: string): CborValue | undefined {
  return value instanceof Map ? value.get(key) : undefined;
}

export function bytesField(value: CborValue, key: string): Uint8Array<ArrayBuffer> {
  const found = field(value, key);
  if (!(found instanceof Uint8Array)) throw new CborError(`${key} must be a byte string`);
  return found;
}

/** Nesting deeper than this is malformed for App Attest and could only be an attack on the stack. */
const MAX_DEPTH = 8;

class Reader {
  offset = 0;

  constructor(private readonly bytes: Uint8Array<ArrayBuffer>) {}

  item(depth: number): CborValue {
    if (depth > MAX_DEPTH) throw new CborError("CBOR nested too deeply");
    const initial = this.byte();
    const major = initial >> 5;
    const length = this.argument(initial & 0x1f);
    switch (major) {
      case 0:
        return length;
      case 2:
        return this.take(length).slice();
      case 3:
        return new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(this.take(length));
      case 4:
        return Array.from({ length: this.count(length) }, () => this.item(depth + 1));
      case 5: {
        const map = new Map<CborValue, CborValue>();
        for (let i = this.count(length); i > 0; i--) {
          const key = this.item(depth + 1);
          map.set(key, this.item(depth + 1));
        }
        return map;
      }
      default:
        throw new CborError(`unsupported CBOR major type ${major}`);
    }
  }

  private byte(): number {
    const value = this.bytes[this.offset];
    if (value === undefined) throw new CborError("truncated CBOR");
    this.offset += 1;
    return value;
  }

  private argument(info: number): number {
    if (info < 24) return info;
    const size = { 24: 1, 25: 2, 26: 4 }[info];
    if (size === undefined) throw new CborError("unsupported CBOR length");
    let value = 0;
    for (let i = 0; i < size; i++) value = value * 256 + this.byte();
    return value;
  }

  /** An array or map's item count, which can't exceed the bytes left, since each item takes at least one. */
  private count(length: number): number {
    if (length > this.bytes.length - this.offset) throw new CborError("truncated CBOR");
    return length;
  }

  private take(length: number): Uint8Array<ArrayBuffer> {
    if (this.offset + length > this.bytes.length) throw new CborError("truncated CBOR");
    const slice = this.bytes.subarray(this.offset, this.offset + length);
    this.offset += length;
    return slice;
  }
}
