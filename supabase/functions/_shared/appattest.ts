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
 * The suite mints its own certificate chain and its own P-256 keys, so it can
 * exercise every rejection path with real cryptography: a tampered payload, a
 * substituted key, a chain that does not reach the configured root, a nonce
 * that does not match, the wrong app id, the wrong environment. Those are
 * genuine properties and they are genuinely tested.
 *
 * What a self-minted vector cannot establish is *conformance*. It proves this
 * verifier agrees with this test's signer; it cannot prove either of them
 * agrees with an iPhone. Two details in particular are asserted here from
 * Apple's published description rather than from an observed device
 * attestation — the exact DER shape of the nonce extension, and that an
 * assertion signs the nonce rather than the concatenation directly. Both are
 * written so that being wrong fails closed: a mismatch rejects the attestation
 * rather than accepting a bad one. Confirming them against a real device is an
 * owner action, recorded in DECISIONS.md.
 */

import * as x509 from "@peculiar/x509";
import { decodeBase64 } from "@std/encoding/base64";
import { type Bytes, bytesEqual, sha256, toHex, utf8 } from "./bytes.ts";

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
}

const FLAG_ATTESTED_CREDENTIAL_DATA = 0x40;

/**
 * Parses WebAuthn-shaped authenticator data.
 *
 * Layout: rpIdHash(32) || flags(1) || signCount(4, big endian), then, if the
 * attested-credential-data flag is set, aaguid(16) || credentialIdLength(2, big
 * endian) || credentialId.
 *
 * An assertion's authenticator data is exactly 37 bytes and carries none of the
 * credential half. Anything longer than the structure accounts for is refused
 * rather than ignored: trailing bytes in a signed structure are a place for two
 * implementations to disagree about what was signed.
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
    if (bytes.length !== 37) {
      throw new AttestationError(
        `authenticator data carries no credential data but is ${bytes.length} bytes`,
      );
    }
    return { rpIdHash, flags, signCount };
  }

  if (bytes.length < 55) {
    throw new AttestationError(
      "authenticator data claims credential data but is too short to hold it",
    );
  }

  const aaguid = bytes.slice(37, 53);
  const credentialIdLength = view.getUint16(53, false);
  const credentialIdEnd = 55 + credentialIdLength;

  if (bytes.length !== credentialIdEnd) {
    throw new AttestationError(
      `credential id length ${credentialIdLength} does not account for ` +
        `${bytes.length - 55} remaining bytes`,
    );
  }

  return {
    rpIdHash,
    flags,
    signCount,
    aaguid,
    credentialId: bytes.slice(55, credentialIdEnd),
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
 * Builds the exact DER the credCert's nonce extension should contain.
 *
 * The structure is a SEQUENCE holding a single context-specific [1] element
 * holding a 32-byte OCTET STRING:
 *
 *   30 24            SEQUENCE, 36 bytes
 *      a1 22         [1], 34 bytes
 *         04 20      OCTET STRING, 32 bytes
 *            <nonce>
 *
 * Building the whole thing and comparing all 38 bytes is deliberate, rather
 * than parsing the extension and pulling the nonce out of it. It checks the
 * structure and the value in one comparison, and anything shaped differently is
 * refused instead of being groped for a 32-byte run that looks like a digest.
 * If Apple's shape is not this, the failure is a rejected attestation — which
 * is the direction to be wrong in.
 */
export function expectedNonceExtension(nonce: Bytes): Bytes {
  if (nonce.length !== 32) {
    throw new AttestationError("a nonce is a 32-byte digest");
  }
  return new Uint8Array([0x30, 0x24, 0xa1, 0x22, 0x04, 0x20, ...nonce]);
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
      throw new AttestationError(
        `could not check the signature on "${subject.subject}": ${cause}`,
      );
    }
    if (!ok) {
      throw new AttestationError(
        `certificate "${subject.subject}" is not signed by "${issuer.subject}"`,
      );
    }
  }

  return certs[0]!;
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
  /** Injectable for tests; defaults to now. */
  readonly at?: Date;
}

/** What a verified attestation yields. */
export interface VerifiedAttestation {
  /** The uncompressed P-256 point, 0x04 || X || Y. What the database stores. */
  readonly publicKey: Bytes;
  readonly environment: AttestEnvironment;
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
  if (!bytesEqual(new Uint8Array(extension.value), expectedNonceExtension(nonce))) {
    throw new AttestationError(
      "the nonce in the leaf certificate does not match this challenge",
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

  if (!bytesEqual(await sha256(publicKey), request.keyId)) {
    throw new AttestationError(
      "the key id is not the digest of the attested public key",
    );
  }

  return { publicKey, environment };
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

  return { signCount: authData.signCount };
}
