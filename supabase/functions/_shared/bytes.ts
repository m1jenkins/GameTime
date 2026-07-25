/**
 * Byte primitives shared by the CBOR codec, App Attest verification, and the
 * ingest handlers.
 *
 * The `Bytes` alias is the load-bearing part. Web Crypto's `BufferSource`
 * excludes SharedArrayBuffer-backed views, and TypeScript now tracks that in
 * `Uint8Array`'s type parameter — so a bare `Uint8Array` will not pass to
 * `digest`, `sign`, `verify`, or `importKey`. Naming the narrower type once and
 * using it everywhere bytes cross a crypto boundary keeps that in the
 * signatures rather than in a cast at each call site, which is where a cast
 * would eventually hide a real mistake.
 */

/** A byte string known to be backed by a plain ArrayBuffer. */
export type Bytes = Uint8Array<ArrayBuffer>;

const ENCODER = new TextEncoder();

/** UTF-8 encodes a string. */
export function utf8(value: string): Bytes {
  return Uint8Array.from(ENCODER.encode(value));
}

/** Concatenates byte strings into one. */
export function concatBytes(...parts: Bytes[]): Bytes {
  let total = 0;
  for (const part of parts) total += part.length;
  const out = new Uint8Array(total);
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
}

/** SHA-256 over the concatenation of its arguments. */
export async function sha256(...parts: Bytes[]): Promise<Bytes> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", concatBytes(...parts)));
}

/**
 * Equality that does not short circuit.
 *
 * Nothing compared with this is a secret a caller could learn by timing — these
 * are digests of public data — but a loop that always runs to the end costs
 * nothing and removes the need to reason about which of these comparisons might
 * become sensitive later.
 */
export function bytesEqual(a: Bytes, b: Bytes): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i]! ^ b[i]!;
  return diff === 0;
}

/** Lowercase hex, for error messages and for the database's bytea literals. */
export function toHex(bytes: Bytes): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * Parses lowercase or uppercase hex, refusing anything that is not exactly hex.
 *
 * Strict because this parses values that arrive from the database as `\x…`
 * literals, and a lenient parse would silently produce a different key.
 */
export function fromHex(value: string): Bytes {
  const clean = value.startsWith("\\x") ? value.slice(2) : value;
  if (clean.length % 2 !== 0 || !/^[0-9a-fA-F]*$/.test(clean)) {
    throw new TypeError(`not a hex string: ${JSON.stringify(value)}`);
  }
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

/**
 * A Postgres bytea hex literal, which is how bytes travel through PostgREST.
 *
 * PostgREST takes JSON, so a bytea argument has to arrive as text in a form
 * Postgres will cast. `\x…` is that form.
 */
export function toByteaLiteral(bytes: Bytes): string {
  return `\\x${toHex(bytes)}`;
}
