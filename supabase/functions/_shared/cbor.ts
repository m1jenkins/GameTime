/**
 * A deliberately small, strict CBOR codec.
 *
 * App Attest hands the server two CBOR documents — the attestation object and
 * the assertion — and both use a tiny subset of the format: text-keyed maps,
 * arrays, byte strings, and small unsigned integers. Nothing else is needed,
 * and this module refuses everything else rather than tolerating it.
 *
 * Refusing is the point. A general CBOR parser accepts many encodings of the
 * same logical value — indefinite-length strings, non-minimal integers,
 * duplicate map keys — and each of those is a way for two parties to disagree
 * about what a document says while both believe they parsed it correctly. That
 * class of bug is why CBOR has a canonical form, and the cheapest way to stay
 * inside it is to reject anything outside it at the door. The alternative is a
 * dependency whose strictness is a configuration flag and whose failure mode on
 * hostile input is somebody else's decision.
 *
 * What is supported:
 *   - major 0: unsigned integers, minimally encoded, up to 2^53-1
 *   - major 2: definite-length byte strings
 *   - major 3: definite-length UTF-8 text strings
 *   - major 4: definite-length arrays
 *   - major 5: definite-length maps with text keys, no duplicates
 *   - major 7: false, true, null
 *
 * What is refused, always: indefinite lengths, tags, floats, negative
 * integers, non-minimal length encodings, non-text map keys, duplicate map
 * keys, and trailing bytes after a complete value.
 */

import type { Bytes } from "./bytes.ts";

export class CborError extends Error {
  override readonly name = "CborError";
}

/** Every value this codec can represent. */
export type CborValue =
  | number
  | boolean
  | null
  | string
  | Bytes
  | CborValue[]
  | { [key: string]: CborValue };

const MAJOR_UNSIGNED = 0;
const MAJOR_BYTES = 2;
const MAJOR_TEXT = 3;
const MAJOR_ARRAY = 4;
const MAJOR_MAP = 5;
const MAJOR_SIMPLE = 7;

class Reader {
  #bytes: Bytes;
  #offset = 0;

  constructor(bytes: Bytes) {
    this.#bytes = bytes;
  }

  get offset(): number {
    return this.#offset;
  }

  get remaining(): number {
    return this.#bytes.length - this.#offset;
  }

  byte(): number {
    if (this.#offset >= this.#bytes.length) {
      throw new CborError("truncated: expected another byte");
    }
    return this.#bytes[this.#offset++]!;
  }

  slice(length: number): Bytes {
    if (length > this.remaining) {
      throw new CborError(
        `truncated: wanted ${length} bytes, ${this.remaining} remain`,
      );
    }
    // A copy rather than a subarray. A subarray keeps the whole document
    // alive and, worse, lets a later mutation of the input change a value a
    // caller has already checked.
    const out = this.#bytes.slice(this.#offset, this.#offset + length);
    this.#offset += length;
    return out;
  }
}

/**
 * Reads the argument that follows a major type, enforcing minimal encoding.
 *
 * Minimality is what makes the encoding of a value unique. Without it, 1 can be
 * written five ways, and any protocol that compares serialised forms — or
 * signs them — has five representations of one document.
 */
function readArgument(reader: Reader, additional: number): number {
  if (additional < 24) return additional;

  if (additional === 24) {
    const value = reader.byte();
    if (value < 24) {
      throw new CborError(`non-minimal encoding: ${value} fits in the head`);
    }
    return value;
  }

  if (additional === 25) {
    const value = (reader.byte() << 8) | reader.byte();
    if (value < 256) {
      throw new CborError(`non-minimal encoding: ${value} fits in one byte`);
    }
    return value;
  }

  if (additional === 26) {
    const value = (reader.byte() * 0x1000000) +
      (reader.byte() << 16) + (reader.byte() << 8) + reader.byte();
    if (value < 65536) {
      throw new CborError(`non-minimal encoding: ${value} fits in two bytes`);
    }
    return value;
  }

  if (additional === 27) {
    const high = (reader.byte() * 0x1000000) +
      (reader.byte() << 16) + (reader.byte() << 8) + reader.byte();
    const low = (reader.byte() * 0x1000000) +
      (reader.byte() << 16) + (reader.byte() << 8) + reader.byte();
    const value = high * 0x100000000 + low;
    if (value < 4294967296) {
      throw new CborError(`non-minimal encoding: ${value} fits in four bytes`);
    }
    if (!Number.isSafeInteger(value)) {
      throw new CborError("integer exceeds the safe integer range");
    }
    return value;
  }

  if (additional === 31) {
    throw new CborError("indefinite lengths are not accepted");
  }

  throw new CborError(`reserved additional information ${additional}`);
}

function decodeValue(reader: Reader, depth: number): CborValue {
  // App Attest documents nest three deep. A bound stops a hostile document
  // from turning recursion into a stack overflow.
  if (depth > 16) {
    throw new CborError("nesting is too deep");
  }

  const head = reader.byte();
  const major = head >> 5;
  const additional = head & 0x1f;

  switch (major) {
    case MAJOR_UNSIGNED:
      return readArgument(reader, additional);

    case MAJOR_BYTES:
      return reader.slice(readArgument(reader, additional));

    case MAJOR_TEXT: {
      const raw = reader.slice(readArgument(reader, additional));
      // fatal: true rejects malformed UTF-8 rather than substituting U+FFFD,
      // which would let two different byte strings decode to one key.
      return new TextDecoder("utf-8", { fatal: true }).decode(raw);
    }

    case MAJOR_ARRAY: {
      const length = readArgument(reader, additional);
      const items: CborValue[] = [];
      for (let i = 0; i < length; i++) {
        items.push(decodeValue(reader, depth + 1));
      }
      return items;
    }

    case MAJOR_MAP: {
      const length = readArgument(reader, additional);
      const map: { [key: string]: CborValue } = {};
      for (let i = 0; i < length; i++) {
        const key = decodeValue(reader, depth + 1);
        if (typeof key !== "string") {
          throw new CborError("map keys must be text strings");
        }
        if (Object.hasOwn(map, key)) {
          throw new CborError(`duplicate map key ${JSON.stringify(key)}`);
        }
        map[key] = decodeValue(reader, depth + 1);
      }
      return map;
    }

    case MAJOR_SIMPLE:
      if (additional === 20) return false;
      if (additional === 21) return true;
      if (additional === 22) return null;
      throw new CborError(`unsupported simple value ${additional}`);

    default:
      throw new CborError(`unsupported major type ${major}`);
  }
}

/** Decodes exactly one CBOR value. Trailing bytes are an error. */
export function decodeCbor(bytes: Bytes): CborValue {
  const reader = new Reader(bytes);
  const value = decodeValue(reader, 0);
  if (reader.remaining !== 0) {
    throw new CborError(
      `${reader.remaining} trailing byte(s) after a complete value`,
    );
  }
  return value;
}

function encodeHead(major: number, argument: number): number[] {
  if (!Number.isSafeInteger(argument) || argument < 0) {
    throw new CborError(`cannot encode ${argument} as a length or integer`);
  }
  const head = major << 5;
  if (argument < 24) return [head | argument];
  if (argument < 0x100) return [head | 24, argument];
  if (argument < 0x10000) return [head | 25, argument >> 8, argument & 0xff];
  if (argument < 0x100000000) {
    return [
      head | 26,
      (argument >>> 24) & 0xff,
      (argument >>> 16) & 0xff,
      (argument >>> 8) & 0xff,
      argument & 0xff,
    ];
  }
  const high = Math.floor(argument / 0x100000000);
  const low = argument % 0x100000000;
  return [
    head | 27,
    (high >>> 24) & 0xff,
    (high >>> 16) & 0xff,
    (high >>> 8) & 0xff,
    high & 0xff,
    (low >>> 24) & 0xff,
    (low >>> 16) & 0xff,
    (low >>> 8) & 0xff,
    low & 0xff,
  ];
}

function encodeValue(value: CborValue, out: number[], depth: number): void {
  if (depth > 16) throw new CborError("nesting is too deep");

  if (value === null) {
    out.push((MAJOR_SIMPLE << 5) | 22);
    return;
  }
  if (typeof value === "boolean") {
    out.push((MAJOR_SIMPLE << 5) | (value ? 21 : 20));
    return;
  }
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value) || value < 0) {
      throw new CborError(`only non-negative safe integers encode: got ${value}`);
    }
    out.push(...encodeHead(MAJOR_UNSIGNED, value));
    return;
  }
  if (typeof value === "string") {
    const bytes = new TextEncoder().encode(value);
    out.push(...encodeHead(MAJOR_TEXT, bytes.length), ...bytes);
    return;
  }
  if (value instanceof Uint8Array) {
    out.push(...encodeHead(MAJOR_BYTES, value.length), ...value);
    return;
  }
  if (Array.isArray(value)) {
    out.push(...encodeHead(MAJOR_ARRAY, value.length));
    for (const item of value) encodeValue(item, out, depth + 1);
    return;
  }

  // Keys are sorted so that one logical map has one encoding. That is what
  // makes a round trip byte-stable, which is the property a test comparing
  // encoded forms depends on.
  const keys = Object.keys(value).sort();
  out.push(...encodeHead(MAJOR_MAP, keys.length));
  for (const key of keys) {
    encodeValue(key, out, depth + 1);
    encodeValue(value[key]!, out, depth + 1);
  }
}

/**
 * Encodes a value in the same subset the decoder accepts.
 *
 * This exists mainly so the App Attest suites can build attestation objects
 * and assertions to verify against, which is what lets those code paths be
 * tested at all without a physical Apple device.
 */
export function encodeCbor(value: CborValue): Bytes {
  const out: number[] = [];
  encodeValue(value, out, 0);
  return new Uint8Array(out);
}

/** Narrows a decoded value to a map, or throws with a useful message. */
export function asCborMap(
  value: CborValue | undefined,
  what: string,
): { [key: string]: CborValue } {
  if (
    value === undefined || value === null || typeof value !== "object" ||
    value instanceof Uint8Array || Array.isArray(value)
  ) {
    throw new CborError(`${what} is not a CBOR map`);
  }
  return value;
}

/** Narrows a decoded map entry to a byte string. */
export function asCborBytes(
  value: CborValue | undefined,
  what: string,
): Bytes {
  if (!(value instanceof Uint8Array)) {
    throw new CborError(`${what} is not a CBOR byte string`);
  }
  return value;
}

/** Narrows a decoded map entry to a text string. */
export function asCborText(
  value: CborValue | undefined,
  what: string,
): string {
  if (typeof value !== "string") {
    throw new CborError(`${what} is not a CBOR text string`);
  }
  return value;
}

/** Narrows a decoded map entry to an array of byte strings. */
export function asCborBytesArray(
  value: CborValue | undefined,
  what: string,
): Bytes[] {
  if (!Array.isArray(value)) {
    throw new CborError(`${what} is not a CBOR array`);
  }
  return value.map((item, index) => asCborBytes(item, `${what}[${index}]`));
}
