/**
 * App Attest verification: anti-cheat rule 9, in the one place it can live.
 *
 * Two operations, once and often:
 *
 *   verifyAttestation  runs once per device install. Proves that a key was
 *                      generated inside a real Secure Enclave, in a genuine
 *                      build of *this* app, and yields the public key to store.
 *   verifyAssertion    runs on every ingest request. Proves that this exact
 *                      payload was signed by that key.
 *
 * The division of labour with the database is D6's line. Everything here needs
 * crypto and none of it is an invariant; everything the SQL side checks — the
 * counter has advanced, the key belongs to this user, the batch is not a replay
 * — is an invariant and needs no crypto. In particular the counter is
 * *recorded* by the database rather than here, because comparing it in
 * application code is a read followed by a write and two copies of a captured
 * request would both pass.
 *
 * ---------------------------------------------------------------------------
 * What these tests can and cannot establish
 * ---------------------------------------------------------------------------
 * The suite mints its own certificate chain and P-256 keys to exercise every
 * rejection path with real cryptography. It also consumes Apple's public 2026
 * attestation vector and App Attestation root to pin a COSE-key-and-extensions
 * suffix against data this repository did not produce. A physical staging
 * device supplied a one-value suffix; the parser now accepts that shape only
 * when the value is a strict COSE key. It also retains the compatibility form
 * that ends after the credential id.
 *
 * Apple's published vector is internally inconsistent with its prose: its
 * certificate nonce incorporates the raw example challenge where the
 * documented protocol incorporates SHA-256(challenge), and one printed public
 * key digest does not match the vector's certificate. The regression therefore
 * checks the official chain, key binding, suffix, and extension nonce as
 * separate components without weakening the documented nonce construction.
 *
 * Assertions accept both the original 37-byte form and the current form Apple
 * documents: that same prefix followed by the exact validation-category and
 * bundle-version extensions map. The map goes through the same strict parser
 * as attestation extensions; it is not an excuse to ignore arbitrary signed
 * trailing bytes.
 */

import * as x509 from "@peculiar/x509";
import { decodeBase64 } from "@std/encoding/base64";
import { type Bytes, bytesEqual, sha256, toHex, utf8 } from "./bytes.ts";
import {
  asCborBytes,
  asCborKeyMap,
  asCborText,
  CborError,
  type CborKeyMap,
  type CborMapKey,
  decodeCborSequence,
} from "./cbor.ts";
import {
  certificateSignatureParts,
  isUnsupportedSubtleError,
  verifyCertificateSignatureEcdsa,
} from "./ecdsa_verify.ts";

export class AttestationError extends Error {
  override readonly name = "AttestationError";
}

/** Apple's App Attest environments, distinguished by the AAGUID. */
export type AttestEnvironment = "development" | "production";

/**
 * The AAGUID a development attestation carries: the ASCII of
 * "appattestdevelop", which is exactly sixteen bytes.
 */
const AAGUID_DEVELOPMENT: Bytes = utf8("appattestdevelop");

/**
 * And a production one: "appattest" followed by seven zero bytes.
 */
const AAGUID_PRODUCTION: Bytes = new Uint8Array(16);
AAGUID_PRODUCTION.set(utf8("appattest"));

/** Apple's OID for the credCert extension carrying the attestation nonce. */
const OID_APPLE_NONCE = "1.2.840.113635.100.8.2";

const ECDSA_P256 = { name: "ECDSA", namedCurve: "P-256" } as const;
const ECDSA_SHA256 = { name: "ECDSA", hash: { name: "SHA-256" } } as const;

/** Strict base64 decode that rejects anything not decoding cleanly. */
export function base64ToBytes(value: string, what: string): Bytes {
  try {
    // A copy, which also settles the buffer type: decodeBase64's return is a
    // bare Uint8Array and every use of these bytes is a crypto call.
    return Uint8Array.from(decodeBase64(value));
  } catch {
    throw new AttestationError(`${what} is not valid base64`);
  }
}

// ---------------------------------------------------------------------------
// Authenticator data
// ---------------------------------------------------------------------------

/** The parsed authenticator data both operations start from. */
export interface AuthenticatorData {
  /** SHA-256 of the app id. Binds the attestation to one app. */
  readonly rpIdHash: Bytes;
  readonly flags: number;
  /** Apple's assertion counter. Zero in an attestation. */
  readonly signCount: number;
  /** Present only when the attested-credential-data flag is set. */
  readonly aaguid?: Bytes;
  /** The key id, as carried inside the authenticator data. */
  readonly credentialId?: Bytes;
  /** Present when Apple supplied a COSE EC2 key; converted to an X9.62 point. */
  readonly credentialPublicKey?: Bytes;
  /** Present when Apple supplied its launch-validation extension. */
  readonly validationCategory?: AppleValidationCategory;
  /** Present when Apple supplied the attested app's CFBundleVersion extension. */
  readonly bundleVersion?: string;
}

const FLAG_ATTESTED_CREDENTIAL_DATA = 0x40;

const COSE_KEY_TYPE = 1;
const COSE_ALGORITHM = 3;
const COSE_CURVE = -1;
const COSE_X = -2;
const COSE_Y = -3;

const COSE_KEY_TYPE_EC2 = 2;
const COSE_ALGORITHM_ES256 = -7;
const COSE_CURVE_P256 = 1;

const EXTENSION_VALIDATION_CATEGORY = "apple_validation_category_01";
const EXTENSION_BUNDLE_VERSION = "apple_bundle_version_01";

/**
 * Launch-validation categories Apple documents as usable app signals.
 *
 * Category 0 is invalid and 7–9 are restricted system-only categories. They
 * fail parsing rather than being surfaced as application policy choices.
 */
export type AppleValidationCategory = 1 | 2 | 3 | 4 | 5 | 6 | 10;

const USABLE_VALIDATION_CATEGORIES = new Set<number>([1, 2, 3, 4, 5, 6, 10]);
const BUNDLE_VERSION_PATTERN = /^\d+(?:\.\d+){0,2}$/;

function requireExactMapKeys(
  map: CborKeyMap,
  expected: readonly CborMapKey[],
  what: string,
): void {
  if (map.size !== expected.length || expected.some((key) => !map.has(key))) {
    throw new AttestationError(
      `${what} must contain exactly ${expected.map(String).join(", ")}`,
    );
  }
}

function requireCborInteger(value: unknown, what: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value)) {
    throw new AttestationError(`${what} is not a CBOR integer`);
  }
  return value;
}

interface ParsedAppleExtensions {
  readonly validationCategory: AppleValidationCategory;
  readonly bundleVersion: string;
}

function parseAppleExtensions(
  value: ReturnType<typeof decodeCborSequence>[number] | undefined,
): ParsedAppleExtensions {
  let extensions: CborKeyMap;
  try {
    extensions = asCborKeyMap(value, "authenticator extensions");
  } catch (cause) {
    if (cause instanceof CborError) {
      throw new AttestationError(`authenticator-data suffix has the wrong shape: ${cause.message}`);
    }
    throw cause;
  }

  requireExactMapKeys(
    extensions,
    [EXTENSION_BUNDLE_VERSION, EXTENSION_VALIDATION_CATEGORY],
    "the authenticator extensions map",
  );

  let categoryBytes: Bytes;
  let bundleVersion: string;
  try {
    categoryBytes = asCborBytes(
      extensions.get(EXTENSION_VALIDATION_CATEGORY),
      EXTENSION_VALIDATION_CATEGORY,
    );
    bundleVersion = asCborText(
      extensions.get(EXTENSION_BUNDLE_VERSION),
      EXTENSION_BUNDLE_VERSION,
    );
  } catch (cause) {
    if (cause instanceof CborError) {
      throw new AttestationError(`an Apple authenticator extension is malformed: ${cause.message}`);
    }
    throw cause;
  }

  // Apple's UInt32 extension is carried as a four-byte little-endian CBOR byte
  // string in the official vector, rather than as CBOR major type 0.
  if (categoryBytes.length !== 4) {
    throw new AttestationError(
      `${EXTENSION_VALIDATION_CATEGORY} must be a four-byte UInt32`,
    );
  }
  const validationCategory = new DataView(
    categoryBytes.buffer,
    categoryBytes.byteOffset,
    categoryBytes.byteLength,
  ).getUint32(0, true);
  if (!USABLE_VALIDATION_CATEGORIES.has(validationCategory)) {
    throw new AttestationError(
      `${EXTENSION_VALIDATION_CATEGORY} ${validationCategory} is not an app category`,
    );
  }

  // CFBundleVersion is one to three dot-separated non-negative integers. Keep
  // its original spelling: policy may deliberately distinguish build "1" from
  // build "1.0", even though the platform interprets missing components as 0.
  if (!BUNDLE_VERSION_PATTERN.test(bundleVersion)) {
    throw new AttestationError(
      `${EXTENSION_BUNDLE_VERSION} is not a valid bundle version`,
    );
  }

  return {
    validationCategory: validationCategory as AppleValidationCategory,
    bundleVersion,
  };
}

function decodeAuthenticatorDataSuffix(bytes: Bytes): ReturnType<typeof decodeCborSequence> {
  try {
    return decodeCborSequence(bytes);
  } catch (cause) {
    if (cause instanceof CborError) {
      throw new AttestationError(`authenticator-data suffix is invalid CBOR: ${cause.message}`);
    }
    throw cause;
  }
}

function parseAttestationSuffix(bytes: Bytes): {
  credentialPublicKey: Bytes;
  validationCategory?: AppleValidationCategory;
  bundleVersion?: string;
} {
  const sequence = decodeAuthenticatorDataSuffix(bytes);

  if (sequence.length < 1 || sequence.length > 2) {
    throw new AttestationError(
      `authenticator-data suffix contains ${sequence.length} CBOR values; ` +
        "one COSE key and at most one extensions map are allowed",
    );
  }

  let cose: CborKeyMap;
  try {
    cose = asCborKeyMap(sequence[0], "credential public key");
  } catch (cause) {
    if (cause instanceof CborError) {
      throw new AttestationError(`authenticator-data suffix has the wrong shape: ${cause.message}`);
    }
    throw cause;
  }

  requireExactMapKeys(
    cose,
    [COSE_KEY_TYPE, COSE_ALGORITHM, COSE_CURVE, COSE_X, COSE_Y],
    "the COSE credential public key",
  );
  if (requireCborInteger(cose.get(COSE_KEY_TYPE), "COSE key type") !== COSE_KEY_TYPE_EC2) {
    throw new AttestationError("the COSE credential public key is not an EC2 key");
  }
  if (
    requireCborInteger(cose.get(COSE_ALGORITHM), "COSE algorithm") !==
      COSE_ALGORITHM_ES256
  ) {
    throw new AttestationError("the COSE credential public key does not use ES256");
  }
  if (requireCborInteger(cose.get(COSE_CURVE), "COSE curve") !== COSE_CURVE_P256) {
    throw new AttestationError("the COSE credential public key is not on P-256");
  }

  let x: Bytes;
  let y: Bytes;
  try {
    x = asCborBytes(cose.get(COSE_X), "COSE x coordinate");
    y = asCborBytes(cose.get(COSE_Y), "COSE y coordinate");
  } catch (cause) {
    if (cause instanceof CborError) {
      throw new AttestationError(`the COSE credential public key is malformed: ${cause.message}`);
    }
    throw cause;
  }
  if (x.length !== 32 || y.length !== 32) {
    throw new AttestationError("the COSE P-256 coordinates must each be 32 bytes");
  }
  const credentialPublicKey = new Uint8Array(65);
  credentialPublicKey[0] = 0x04;
  credentialPublicKey.set(x, 1);
  credentialPublicKey.set(y, 33);

  if (sequence.length === 1) {
    return { credentialPublicKey };
  }

  return {
    credentialPublicKey,
    ...parseAppleExtensions(sequence[1]),
  };
}

function parseAssertionSuffix(bytes: Bytes): ParsedAppleExtensions {
  const sequence = decodeAuthenticatorDataSuffix(bytes);
  if (sequence.length !== 1) {
    throw new AttestationError(
      `assertion authenticator-data suffix contains ${sequence.length} CBOR values; ` +
        "exactly one extensions map is allowed",
    );
  }
  return parseAppleExtensions(sequence[0]);
}

/**
 * Parses WebAuthn-shaped authenticator data.
 *
 * Layout: rpIdHash(32) || flags(1) || signCount(4, big endian), then, if the
 * attested-credential-data flag is set, aaguid(16) || credentialIdLength(2, big
 * endian) || credentialId and, when supplied, COSE_Key followed optionally by
 * an extensions map.
 *
 * An assertion carries none of the credential half. Its legacy form is exactly
 * 37 bytes; Apple's current form may append exactly one validation-category and
 * bundle-version extensions map. Anything else is refused rather than ignored:
 * trailing bytes in a signed structure are a place for two implementations to
 * disagree about what was signed.
 */
export function parseAuthenticatorData(bytes: Bytes): AuthenticatorData {
  if (bytes.length < 37) {
    throw new AttestationError(
      `authenticator data is ${bytes.length} bytes; at least 37 are required`,
    );
  }

  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const rpIdHash = bytes.slice(0, 32);
  const flags = bytes[32]!;
  const signCount = view.getUint32(33, false);

  if ((flags & FLAG_ATTESTED_CREDENTIAL_DATA) === 0) {
    if (bytes.length === 37) {
      return { rpIdHash, flags, signCount };
    }
    return {
      rpIdHash,
      flags,
      signCount,
      ...parseAssertionSuffix(bytes.slice(37)),
    };
  }

  if (bytes.length < 55) {
    throw new AttestationError(
      "authenticator data claims credential data but is too short to hold it",
    );
  }

  const aaguid = bytes.slice(37, 53);
  const credentialIdLength = view.getUint16(53, false);
  const credentialIdEnd = 55 + credentialIdLength;

  if (bytes.length < credentialIdEnd) {
    throw new AttestationError(
      `credential id length ${credentialIdLength} exceeds ` +
        `${bytes.length - 55} remaining bytes`,
    );
  }
  if (bytes.length === credentialIdEnd) {
    return {
      rpIdHash,
      flags,
      signCount,
      aaguid,
      credentialId: bytes.slice(55, credentialIdEnd),
    };
  }

  const suffix = parseAttestationSuffix(bytes.slice(credentialIdEnd));

  return {
    rpIdHash,
    flags,
    signCount,
    aaguid,
    credentialId: bytes.slice(55, credentialIdEnd),
    ...suffix,
  };
}

/** Maps an AAGUID onto the environment that produced it. */
export function environmentFromAaguid(aaguid: Bytes): AttestEnvironment {
  if (bytesEqual(aaguid, AAGUID_PRODUCTION)) return "production";
  if (bytesEqual(aaguid, AAGUID_DEVELOPMENT)) return "development";
  throw new AttestationError(
    `unrecognised AAGUID ${toHex(aaguid)}; not an App Attest attestation`,
  );
}

// ---------------------------------------------------------------------------
// ECDSA signature encoding
// ---------------------------------------------------------------------------

/**
 * Converts a DER-encoded ECDSA signature to the fixed-width r||s form.
 *
 * Apple hands over a DER SEQUENCE of two INTEGERs; Web Crypto's `verify` wants
 * 64 raw bytes. DER INTEGERs are minimally encoded and signed, so each half
 * arrives with a leading zero when its top bit is set, and shorter than 32
 * bytes when it has leading zero bytes — both have to be normalised rather than
 * copied.
 *
 * Every structural surprise is an error rather than a best-effort read. A
 * signature is not a place to be forgiving: the only thing a malformed one can
 * mean is that this did not come from where it claims to.
 */
export function derToRawEcdsaSignature(der: Bytes): Bytes {
  let offset = 0;

  const expect = (byte: number, what: string) => {
    if (der[offset] !== byte) {
      throw new AttestationError(
        `signature is not DER: expected ${what} at offset ${offset}`,
      );
    }
    offset += 1;
  };

  expect(0x30, "a SEQUENCE tag");

  const sequenceLength = der[offset++];
  if (sequenceLength === undefined || sequenceLength > 0x7f) {
    throw new AttestationError(
      "signature is not DER: long-form or missing sequence length",
    );
  }
  if (offset + sequenceLength !== der.length) {
    throw new AttestationError(
      `signature is not DER: sequence length ${sequenceLength} does not ` +
        `match ${der.length - offset} remaining bytes`,
    );
  }

  const readInteger = (): Bytes => {
    expect(0x02, "an INTEGER tag");
    const length = der[offset++];
    if (length === undefined || length === 0 || length > 33) {
      throw new AttestationError(
        `signature is not DER: implausible INTEGER length ${length}`,
      );
    }
    const raw = der.slice(offset, offset + length);
    if (raw.length !== length) {
      throw new AttestationError("signature is not DER: truncated INTEGER");
    }
    offset += length;

    // A single leading zero is the sign byte. Two is non-minimal, which DER
    // forbids, and a negative value is not a coordinate.
    if (raw[0] === 0x00) {
      if (raw.length === 1) {
        throw new AttestationError("signature is not DER: zero-valued INTEGER");
      }
      if ((raw[1]! & 0x80) === 0) {
        throw new AttestationError(
          "signature is not DER: non-minimal INTEGER encoding",
        );
      }
    } else if ((raw[0]! & 0x80) !== 0) {
      throw new AttestationError("signature is not DER: negative INTEGER");
    }

    const stripped = raw[0] === 0x00 ? raw.slice(1) : raw;
    if (stripped.length > 32) {
      throw new AttestationError(
        `signature is not P-256: a ${stripped.length}-byte scalar`,
      );
    }

    const padded = new Uint8Array(32);
    padded.set(stripped, 32 - stripped.length);
    return padded;
  };

  const r = readInteger();
  const s = readInteger();

  if (offset !== der.length) {
    throw new AttestationError("signature is not DER: trailing bytes");
  }

  const raw = new Uint8Array(64);
  raw.set(r, 0);
  raw.set(s, 32);
  return raw;
}

/** The inverse, used by the suites to produce Apple-shaped signatures. */
export function rawToDerEcdsaSignature(raw: Bytes): Bytes {
  if (raw.length !== 64) {
    throw new AttestationError(`a raw P-256 signature is 64 bytes, got ${raw.length}`);
  }

  const encodeInteger = (scalar: Bytes): number[] => {
    let start = 0;
    while (start < scalar.length - 1 && scalar[start] === 0x00) start++;
    const trimmed = Array.from(scalar.slice(start));
    if ((trimmed[0]! & 0x80) !== 0) trimmed.unshift(0x00);
    return [0x02, trimmed.length, ...trimmed];
  };

  const body = [
    ...encodeInteger(raw.slice(0, 32)),
    ...encodeInteger(raw.slice(32, 64)),
  ];
  return new Uint8Array([0x30, body.length, ...body]);
}

// ---------------------------------------------------------------------------
// The nonce, and how it is carried
// ---------------------------------------------------------------------------

/**
 * The value both operations bind a signature to.
 *
 * SHA-256 over the authenticator data followed by the client data hash. Naming
 * it once means the attestation path and the assertion path cannot drift into
 * computing it two different ways, which would make one of them unverifiable
 * without either being obviously broken.
 */
export async function attestationNonce(
  authenticatorData: Bytes,
  clientDataHash: Bytes,
): Promise<Bytes> {
  return await sha256(authenticatorData, clientDataHash);
}

/**
 * Decodes the credCert nonce extension and extracts its single octet string.
 *
 * Apple specifies a DER SEQUENCE containing context-specific [1], which in
 * turn contains one OCTET STRING. Parse that structure instead of comparing a
 * hardcoded wrapper: the digest is the extension's semantic value, while DER
 * length validation still refuses truncation, trailing data, and non-minimal
 * encodings.
 */
export function nonceFromExtension(der: Bytes): Bytes {
  let offset = 0;

  const expectTag = (tag: number, what: string) => {
    if (der[offset] !== tag) {
      throw new AttestationError(
        `Apple nonce extension is not DER: expected ${what} at offset ${offset}`,
      );
    }
    offset += 1;
  };

  const readLength = (): number => {
    const first = der[offset++];
    if (first === undefined) {
      throw new AttestationError("Apple nonce extension is truncated before a length");
    }
    if (first < 0x80) return first;

    const lengthBytes = first & 0x7f;
    if (lengthBytes === 0) {
      throw new AttestationError("Apple nonce extension uses an indefinite DER length");
    }
    if (lengthBytes > 4 || der[offset] === 0x00) {
      throw new AttestationError("Apple nonce extension has a non-minimal DER length");
    }

    let length = 0;
    for (let i = 0; i < lengthBytes; i++) {
      const byte = der[offset++];
      if (byte === undefined) {
        throw new AttestationError("Apple nonce extension is truncated inside a length");
      }
      length = length * 0x100 + byte;
    }
    if (length < 0x80) {
      throw new AttestationError("Apple nonce extension has a non-minimal DER length");
    }
    return length;
  };

  expectTag(0x30, "a SEQUENCE");
  const sequenceLength = readLength();
  const sequenceEnd = offset + sequenceLength;
  if (sequenceEnd !== der.length) {
    throw new AttestationError(
      "Apple nonce extension SEQUENCE length does not account for the value",
    );
  }

  expectTag(0xa1, "context-specific [1]");
  const contextLength = readLength();
  const contextEnd = offset + contextLength;
  if (contextEnd !== sequenceEnd) {
    throw new AttestationError(
      "Apple nonce extension [1] length does not account for the SEQUENCE",
    );
  }

  expectTag(0x04, "an OCTET STRING");
  const nonceLength = readLength();
  const nonceEnd = offset + nonceLength;
  if (nonceEnd !== contextEnd) {
    throw new AttestationError(
      "Apple nonce extension OCTET STRING length does not account for [1]",
    );
  }
  if (nonceLength !== 32) {
    throw new AttestationError(
      `Apple nonce extension contains a ${nonceLength}-byte value, not a digest`,
    );
  }

  return der.slice(offset, nonceEnd);
}

// ---------------------------------------------------------------------------
// Certificate chain
// ---------------------------------------------------------------------------

/**
 * Verifies that `chain` runs from its leaf up to `root`, and returns the leaf.
 *
 * Each certificate must be signed by the next, the last must be signed by the
 * configured root, and every certificate must be inside its validity window.
 * The root is supplied by configuration rather than compiled in, because a
 * wrong pinned root either rejects everything or — much worse — accepts a chain
 * Apple did not issue, and its bytes are not something to reproduce from
 * memory. See DECISIONS.md.
 */
async function verifyCertificateChain(
  chain: Bytes[],
  root: x509.X509Certificate,
  at: Date,
): Promise<x509.X509Certificate> {
  if (chain.length === 0) {
    throw new AttestationError("the attestation carries no certificates");
  }
  if (chain.length > 4) {
    throw new AttestationError(
      `the attestation carries ${chain.length} certificates; at most 4 are plausible`,
    );
  }

  let certs: x509.X509Certificate[];
  try {
    certs = chain.map((der) => new x509.X509Certificate(der));
  } catch (cause) {
    throw new AttestationError(`a certificate in the chain is not valid DER: ${cause}`);
  }

  const withRoot = [...certs, root];

  for (let i = 0; i < withRoot.length; i++) {
    const cert = withRoot[i]!;
    if (at < cert.notBefore || at > cert.notAfter) {
      throw new AttestationError(
        `certificate "${cert.subject}" is outside its validity window`,
      );
    }
  }

  for (let i = 0; i < withRoot.length - 1; i++) {
    const subject = withRoot[i]!;
    const issuer = withRoot[i + 1]!;

    if (subject.issuer !== issuer.subject) {
      throw new AttestationError(
        `certificate "${subject.subject}" names issuer "${subject.issuer}", ` +
          `which is not "${issuer.subject}"`,
      );
    }

    let ok: boolean;
    try {
      ok = await subject.verify({ publicKey: issuer.publicKey, date: at });
    } catch (cause) {
      if (!isUnsupportedSubtleError(cause)) {
        throw new AttestationError(
          `could not check the signature on "${subject.subject}": ${cause}`,
        );
      }
      // The hosted Edge Runtime implements ECDSA verify only for the matched
      // (curve, digest) pairs, and Apple's chain signs the P-256 leaf with
      // SHA-256 under the P-384 intermediate. That cross pair is verified
      // without WebCrypto (see ecdsa_verify.ts, M6.5 live finding).
      ok = await verifyCertificateSignatureOffline(subject, issuer);
    }
    if (!ok) {
      throw new AttestationError(
        `certificate "${subject.subject}" is not signed by "${issuer.subject}"`,
      );
    }
  }

  return certs[0]!;
}

/**
 * One certificate's signature against its issuer's key, computed without
 * WebCrypto. Only reached when the runtime refuses the (curve, digest) pair
 * natively, so any failure here still surfaces as the same AttestationError
 * the native path would have produced.
 */
async function verifyCertificateSignatureOffline(
  subject: x509.X509Certificate,
  issuer: x509.X509Certificate,
): Promise<boolean> {
  const algorithm = subject.signatureAlgorithm;
  if (algorithm.name?.toUpperCase() !== "ECDSA") {
    throw new AttestationError(
      `certificate "${subject.subject}" does not use an ECDSA signature`,
    );
  }
  const hashName = typeof algorithm.hash === "string" ? algorithm.hash : algorithm.hash?.name;
  if (hashName !== "SHA-256" && hashName !== "SHA-384") {
    throw new AttestationError(
      `certificate "${subject.subject}" is signed with ${
        hashName ?? "an unknown digest"
      }, not SHA-256/SHA-384`,
    );
  }
  try {
    const parts = certificateSignatureParts(new Uint8Array(subject.rawData));
    return await verifyCertificateSignatureEcdsa({
      tbs: parts.tbs,
      signatureDer: parts.signatureDer,
      hash: hashName,
      issuerSpki: new Uint8Array(issuer.publicKey.rawData),
    });
  } catch (cause) {
    if (cause instanceof AttestationError) throw cause;
    throw new AttestationError(
      `could not check the signature on "${subject.subject}": ${cause}`,
    );
  }
}

// ---------------------------------------------------------------------------
// Attestation
// ---------------------------------------------------------------------------

/** Everything needed to check one attestation. */
export interface AttestationRequest {
  /** The decoded CBOR attestation object, already narrowed. */
  readonly fmt: string;
  readonly x5c: Bytes[];
  readonly authenticatorData: Bytes;
  /** The key id the client claims, raw bytes. */
  readonly keyId: Bytes;
  /** The bytes the client hashed into the attestation's client data. */
  readonly clientData: Bytes;
  /** "<teamId>.<bundleId>". */
  readonly appId: string;
  /** Apple's App Attest root, PEM. */
  readonly rootCertificatePem: string;
  /** Which environments this deployment will accept. */
  readonly allowedEnvironments: readonly AttestEnvironment[];
  /** Optional deployment policy for Apple's launch-validation signal. */
  readonly allowedValidationCategories?: readonly AppleValidationCategory[];
  /** Optional deployment policy for accepted CFBundleVersion strings. */
  readonly allowedBundleVersions?: readonly string[];
  /** Injectable for tests; defaults to now. */
  readonly at?: Date;
}

/** What a verified attestation yields. */
export interface VerifiedAttestation {
  /** The uncompressed P-256 point, 0x04 || X || Y. What the database stores. */
  readonly publicKey: Bytes;
  readonly environment: AttestEnvironment;
  /** Present when Apple supplied its launch-validation extension. */
  readonly validationCategory?: AppleValidationCategory;
  /** Present when Apple supplied its CFBundleVersion extension. */
  readonly bundleVersion?: string;
}

/**
 * Verifies an attestation object and returns the key to store.
 *
 * The order of the checks is roughly cheapest-first, but every one of them has
 * to pass, so the ordering is for legibility rather than for security.
 */
export async function verifyAttestation(
  request: AttestationRequest,
): Promise<VerifiedAttestation> {
  const at = request.at ?? new Date();

  if (request.fmt !== "apple-appattest") {
    throw new AttestationError(
      `attestation format is "${request.fmt}", not "apple-appattest"`,
    );
  }

  if (request.keyId.length !== 32) {
    throw new AttestationError(
      `a key id is a 32-byte digest, got ${request.keyId.length} bytes`,
    );
  }

  let root: x509.X509Certificate;
  try {
    root = new x509.X509Certificate(request.rootCertificatePem);
  } catch (cause) {
    throw new AttestationError(`the configured App Attest root is unreadable: ${cause}`);
  }

  const credCert = await verifyCertificateChain(request.x5c, root, at);

  const authData = parseAuthenticatorData(request.authenticatorData);

  if (authData.aaguid === undefined || authData.credentialId === undefined) {
    throw new AttestationError(
      "an attestation's authenticator data must carry credential data",
    );
  }

  const environment = environmentFromAaguid(authData.aaguid);
  if (!request.allowedEnvironments.includes(environment)) {
    throw new AttestationError(
      `a ${environment} attestation is not accepted by this deployment`,
    );
  }
  if (request.allowedValidationCategories !== undefined) {
    if (authData.validationCategory === undefined) {
      throw new AttestationError(
        "this deployment requires an Apple validation category but the attestation has none",
      );
    }
    if (!request.allowedValidationCategories.includes(authData.validationCategory)) {
      throw new AttestationError(
        `validation category ${authData.validationCategory} is not accepted by this deployment`,
      );
    }
  }
  if (request.allowedBundleVersions !== undefined) {
    if (authData.bundleVersion === undefined) {
      throw new AttestationError(
        "this deployment requires an Apple bundle version but the attestation has none",
      );
    }
    if (!request.allowedBundleVersions.includes(authData.bundleVersion)) {
      throw new AttestationError(
        `bundle version "${authData.bundleVersion}" is not accepted by this deployment`,
      );
    }
  }

  // A fresh key has produced no assertions. A non-zero counter here means this
  // is not a fresh key, which means it is not a fresh attestation either.
  if (authData.signCount !== 0) {
    throw new AttestationError(
      `an attestation's counter must be 0, got ${authData.signCount}`,
    );
  }

  const expectedRpIdHash = await sha256(utf8(request.appId));
  if (!bytesEqual(authData.rpIdHash, expectedRpIdHash)) {
    throw new AttestationError(
      "the attestation was produced for a different app id",
    );
  }

  if (!bytesEqual(authData.credentialId, request.keyId)) {
    throw new AttestationError(
      "the key id in the authenticator data is not the one the client claims",
    );
  }

  // The key id is Apple's digest of the attested public key, so deriving it
  // here and comparing is what ties the certificate to the key id the client
  // named. The database holds the same relation as a CHECK, so a mismatch has
  // to get past both.
  let publicKey: Bytes;
  try {
    const imported = await crypto.subtle.importKey(
      "spki",
      credCert.publicKey.rawData,
      ECDSA_P256,
      true,
      ["verify"],
    );
    publicKey = new Uint8Array(await crypto.subtle.exportKey("raw", imported));
  } catch (cause) {
    throw new AttestationError(
      `the attested public key is not a P-256 key: ${cause}`,
    );
  }

  if (publicKey.length !== 65 || publicKey[0] !== 0x04) {
    throw new AttestationError("the attested public key is not an uncompressed point");
  }

  if (
    authData.credentialPublicKey !== undefined &&
    !bytesEqual(authData.credentialPublicKey, publicKey)
  ) {
    throw new AttestationError(
      "the COSE credential public key does not match the certificate public key",
    );
  }

  if (!bytesEqual(await sha256(publicKey), request.keyId)) {
    throw new AttestationError(
      "the key id is not the digest of the attested public key",
    );
  }

  // The nonce is what binds this attestation to this challenge. Without it, a
  // captured attestation could be replayed by anyone who saw it once.
  const clientDataHash = await sha256(request.clientData);
  const nonce = await attestationNonce(request.authenticatorData, clientDataHash);

  const extension = credCert.getExtension(OID_APPLE_NONCE);
  if (extension === null) {
    throw new AttestationError(
      "the leaf certificate carries no Apple attestation nonce extension",
    );
  }
  const certificateNonce = nonceFromExtension(new Uint8Array(extension.value));
  if (!bytesEqual(certificateNonce, nonce)) {
    throw new AttestationError(
      "the nonce in the leaf certificate does not match this challenge",
    );
  }

  return {
    publicKey,
    environment,
    validationCategory: authData.validationCategory,
    bundleVersion: authData.bundleVersion,
  };
}

// ---------------------------------------------------------------------------
// Assertion
// ---------------------------------------------------------------------------

/** Everything needed to check one assertion. */
export interface AssertionRequest {
  readonly signature: Bytes;
  readonly authenticatorData: Bytes;
  /** The exact request body the client signed over. */
  readonly clientData: Bytes;
  /** The stored uncompressed P-256 point for this key. */
  readonly publicKey: Bytes;
  readonly appId: string;
}

/** What a verified assertion yields: the counter for the database to consume. */
export interface VerifiedAssertion {
  readonly signCount: number;
  /** Present when Apple supplied its launch-validation extension. */
  readonly validationCategory?: AppleValidationCategory;
  /** Present when Apple supplied its CFBundleVersion extension. */
  readonly bundleVersion?: string;
}

/**
 * Verifies that this payload was signed by this key.
 *
 * The signature covers the nonce — SHA-256 of the authenticator data and the
 * client data hash — and ES256 hashes its message again, so what is actually
 * signed is a digest of a digest. That is Apple's construction rather than a
 * choice made here; it is written as one named step so that if the reading is
 * wrong it is wrong in one line. The consequence of being wrong is that every
 * assertion fails, which is loud.
 *
 * Note what this does *not* do: compare the counter against a stored value.
 * That comparison has to be atomic with consuming it, which application code
 * cannot be, so it lives in the database.
 */
export async function verifyAssertion(
  request: AssertionRequest,
): Promise<VerifiedAssertion> {
  if (request.publicKey.length !== 65 || request.publicKey[0] !== 0x04) {
    throw new AttestationError("the stored public key is not an uncompressed point");
  }

  const authData = parseAuthenticatorData(request.authenticatorData);

  if (authData.aaguid !== undefined) {
    throw new AttestationError(
      "an assertion's authenticator data must not carry credential data",
    );
  }

  const expectedRpIdHash = await sha256(utf8(request.appId));
  if (!bytesEqual(authData.rpIdHash, expectedRpIdHash)) {
    throw new AttestationError("the assertion was produced for a different app id");
  }

  let key: CryptoKey;
  try {
    key = await crypto.subtle.importKey("raw", request.publicKey, ECDSA_P256, false, [
      "verify",
    ]);
  } catch (cause) {
    throw new AttestationError(`the stored public key will not import: ${cause}`);
  }

  const clientDataHash = await sha256(request.clientData);
  const nonce = await attestationNonce(request.authenticatorData, clientDataHash);

  const rawSignature = derToRawEcdsaSignature(request.signature);

  const valid = await crypto.subtle.verify(ECDSA_SHA256, key, rawSignature, nonce);
  if (!valid) {
    throw new AttestationError("the assertion signature does not verify");
  }

  return {
    signCount: authData.signCount,
    validationCategory: authData.validationCategory,
    bundleVersion: authData.bundleVersion,
  };
}
