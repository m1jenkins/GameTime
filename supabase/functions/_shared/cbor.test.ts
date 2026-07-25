import { assertEquals, assertThrows } from "@std/assert";
import { fromHex } from "./bytes.ts";
import {
  asCborBytes,
  asCborBytesArray,
  asCborKeyMap,
  asCborMap,
  asCborText,
  CborError,
  decodeCbor,
  decodeCborSequence,
  encodeCbor,
} from "./cbor.ts";

/** Hex to bytes, for spelling out wire encodings literally. */
function hex(s: string): ReturnType<typeof fromHex> {
  return fromHex(s.replace(/\s+/g, ""));
}

// ---------------------------------------------------------------------------
// The subset that is accepted
// ---------------------------------------------------------------------------
// Vectors from RFC 8949 appendix A, so this is checked against the standard
// rather than against its own encoder.
Deno.test("decodes the RFC 8949 unsigned integer vectors", () => {
  assertEquals(decodeCbor(hex("00")), 0);
  assertEquals(decodeCbor(hex("17")), 23);
  assertEquals(decodeCbor(hex("1818")), 24);
  assertEquals(decodeCbor(hex("1903e8")), 1000);
  assertEquals(decodeCbor(hex("1a000f4240")), 1000000);
  assertEquals(decodeCbor(hex("1b000000e8d4a51000")), 1000000000000);
});

Deno.test("decodes text, bytes, arrays and maps", () => {
  assertEquals(decodeCbor(hex("63666d74")), "fmt");
  assertEquals(decodeCbor(hex("4401020304")), new Uint8Array([1, 2, 3, 4]));
  assertEquals(decodeCbor(hex("83010203")), [1, 2, 3]);
  assertEquals(decodeCbor(hex("a26161016162820203")), { a: 1, b: [2, 3] });
  assertEquals(decodeCbor(hex("f4")), false);
  assertEquals(decodeCbor(hex("f5")), true);
  assertEquals(decodeCbor(hex("f6")), null);
});

Deno.test("round-trips a document shaped like an attestation object", () => {
  const original = {
    fmt: "apple-appattest",
    attStmt: {
      x5c: [new Uint8Array([1, 2, 3]), new Uint8Array([4, 5, 6])],
      receipt: new Uint8Array([7, 8]),
    },
    authData: new Uint8Array(87).fill(9),
  };
  assertEquals(decodeCbor(encodeCbor(original)), original);
});

Deno.test("encoding is byte-stable regardless of key insertion order", () => {
  const a = encodeCbor({ fmt: "x", authData: new Uint8Array([1]) });
  const b = encodeCbor({ authData: new Uint8Array([1]), fmt: "x" });
  assertEquals(a, b);
});

// App Attest's authenticator-data suffix is a CBOR sequence rather than one
// document. Its COSE key uses integer labels, including negative ones.
Deno.test("decodes a deterministic COSE-key and extensions sequence", () => {
  const [keyValue, extensionValue] = decodeCborSequence(hex(
    "a5 01 02 03 26 20 01 21 42aabb 22 42ccdd a1 61 78 01",
  ));
  const key = asCborKeyMap(keyValue, "COSE key");
  const extensions = asCborKeyMap(extensionValue, "extensions");

  assertEquals(key.size, 5);
  assertEquals(key.get(1), 2);
  assertEquals(key.get(3), -7);
  assertEquals(key.get(-1), 1);
  assertEquals(key.get(-2), hex("aabb"));
  assertEquals(key.get(-3), hex("ccdd"));
  assertEquals(extensions.get("x"), 1);
});

Deno.test("the sequence codec requires deterministic map-key order", () => {
  // Integer key 1 must sort before key 3.
  assertThrows(
    () => decodeCborSequence(hex("a2 03 26 01 02")),
    CborError,
    "deterministic order",
  );

  // A shorter text key must sort before a longer one.
  assertThrows(
    () => decodeCborSequence(hex("a2 62 6161 01 61 62 02")),
    CborError,
    "deterministic order",
  );
});

Deno.test("the sequence codec refuses duplicate and non-minimal integer keys", () => {
  assertThrows(
    () => decodeCborSequence(hex("a2 01 01 01 02")),
    CborError,
    "duplicate map key",
  );
  assertThrows(
    () => decodeCborSequence(hex("a1 38 00 01")),
    CborError,
    "non-minimal",
  );
});

// ---------------------------------------------------------------------------
// The refusals, which are the reason this module exists
// ---------------------------------------------------------------------------
// Each of these is a way for two implementations to disagree about what one
// document says. A parser that accepts them is a parser whose output depends on
// which library the other side used.
Deno.test("refuses a non-minimal integer encoding", () => {
  // 0 written in the two-byte form instead of the one-byte form.
  assertThrows(() => decodeCbor(hex("1800")), CborError, "non-minimal");
  assertThrows(() => decodeCbor(hex("190000")), CborError, "non-minimal");
  assertThrows(() => decodeCbor(hex("1a00000000")), CborError, "non-minimal");
  assertThrows(
    () => decodeCbor(hex("1b0000000000000000")),
    CborError,
    "non-minimal",
  );
});

Deno.test("refuses a non-minimal length on a byte string", () => {
  // A one-byte string whose length is written in the 16-bit form.
  assertThrows(() => decodeCbor(hex("590001ff")), CborError, "non-minimal");
});

Deno.test("refuses indefinite lengths", () => {
  assertThrows(() => decodeCbor(hex("5f41ff")), CborError, "indefinite");
  assertThrows(() => decodeCbor(hex("9f01ff")), CborError, "indefinite");
  assertThrows(() => decodeCbor(hex("bf6161 01 ff")), CborError, "indefinite");
});

Deno.test("refuses duplicate map keys", () => {
  // {"a": 1, "a": 2} — the second value silently wins in a lenient parser, so
  // whichever side reads which is a coin flip.
  assertThrows(
    () => decodeCbor(hex("a2616101616102")),
    CborError,
    "duplicate map key",
  );
});

Deno.test("refuses a map key that is not text", () => {
  // {1: 2}. App Attest's maps are all text-keyed, and accepting integer keys
  // would mean the shape checks below could be bypassed with a different type.
  assertThrows(() => decodeCbor(hex("a10102")), CborError, "text strings");
});

Deno.test("refuses tags, floats and negative integers", () => {
  assertThrows(() => decodeCbor(hex("c11a514b67b0")), CborError, "major type 6");
  assertThrows(() => decodeCbor(hex("f93c00")), CborError, "simple value");
  assertThrows(() => decodeCbor(hex("20")), CborError, "major type 1");
});

Deno.test("refuses trailing bytes after a complete value", () => {
  // The shape of a length-confusion attack: a valid document with a second one
  // stapled on, where the two sides disagree about which was sent.
  assertThrows(() => decodeCbor(hex("0000")), CborError, "trailing");
});

Deno.test("refuses a truncated document", () => {
  // A 4-byte string with one byte of content.
  assertThrows(() => decodeCbor(hex("4404")), CborError, "truncated");
  // A 3-element array carrying two elements.
  assertThrows(() => decodeCbor(hex("830102")), CborError, "truncated");
});

Deno.test("refuses malformed UTF-8 in a text string rather than substituting", () => {
  // 0xff is not valid UTF-8. A lenient decoder yields U+FFFD, which maps two
  // different byte strings onto one key.
  assertThrows(() => decodeCbor(hex("61ff")), Error);
});

Deno.test("bounds nesting depth", () => {
  // Twenty nested single-element arrays.
  let bytes = hex("00");
  for (let i = 0; i < 20; i++) {
    bytes = new Uint8Array([0x81, ...bytes]);
  }
  assertThrows(() => decodeCbor(bytes), CborError, "too deep");
});

// ---------------------------------------------------------------------------
// Decoded values are independent of the input buffer
// ---------------------------------------------------------------------------
// A subarray would alias the request body, so mutating the body after a check
// would change a value already validated. This is the kind of aliasing bug that
// turns a verified payload into an unverified one between two lines of code.
Deno.test("a decoded byte string does not alias the input", () => {
  const input = hex("43010203");
  const decoded = decodeCbor(input) as Uint8Array;
  input[1] = 0xff;
  assertEquals(decoded, new Uint8Array([1, 2, 3]));
});

// ---------------------------------------------------------------------------
// The narrowing helpers
// ---------------------------------------------------------------------------
Deno.test("narrowing helpers accept the right shapes and reject the rest", () => {
  const map = asCborMap(decodeCbor(encodeCbor({ a: new Uint8Array([1]) })), "doc");
  assertEquals(asCborBytes(map["a"], "a"), new Uint8Array([1]));

  assertThrows(() => asCborMap(1, "doc"), CborError, "not a CBOR map");
  assertThrows(() => asCborMap(new Uint8Array([1]), "doc"), CborError);
  assertThrows(() => asCborMap([1], "doc"), CborError);
  assertThrows(
    () => asCborMap(decodeCborSequence(hex("a0"))[0], "doc"),
    CborError,
  );
  assertThrows(() => asCborKeyMap(map, "key"), CborError);
  assertThrows(() => asCborBytes("x", "a"), CborError, "byte string");
  assertThrows(() => asCborBytes(undefined, "missing"), CborError, "missing");
  assertThrows(() => asCborText(new Uint8Array([1]), "a"), CborError, "text");
  assertThrows(() => asCborBytesArray("x", "x5c"), CborError, "array");
  assertThrows(
    () => asCborBytesArray(["not-bytes"], "x5c"),
    CborError,
    "x5c[0]",
  );
});

Deno.test("encoding refuses values outside the subset", () => {
  assertThrows(() => encodeCbor(-1), CborError, "non-negative");
  assertThrows(() => encodeCbor(1.5), CborError, "non-negative");
});
