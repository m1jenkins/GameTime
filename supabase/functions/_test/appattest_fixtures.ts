/**
 * Builds App Attest documents for the suites.
 *
 * Lives under `_test` rather than `_shared` because nothing in a deployed
 * function imports it: a leading underscore keeps the directory from being
 * treated as a function, and staying out of `_shared` keeps it out of every
 * deployed bundle.
 *
 * This mints its own root, intermediate and leaf, and its own device keys, so
 * every check in `appattest.ts` can be exercised with real cryptography rather
 * than a stub. Apple's independently produced conformance values live beside
 * this file in `apple_appattest_2026_vector.ts`.
 */

import * as x509 from "@peculiar/x509";
import { rawToDerEcdsaSignature } from "../_shared/appattest.ts";
import { type Bytes, bytesEqual, sha256, utf8 } from "../_shared/bytes.ts";
import { encodeCbor } from "../_shared/cbor.ts";

const ECDSA_P256 = { name: "ECDSA", namedCurve: "P-256" } as const;
const SIGNING_ALG = { name: "ECDSA", namedCurve: "P-256", hash: "SHA-256" } as const;
const ECDSA_SHA256 = { name: "ECDSA", hash: { name: "SHA-256" } } as const;

const NOT_BEFORE = new Date("2020-01-01T00:00:00Z");
const NOT_AFTER = new Date("2040-01-01T00:00:00Z");

export const AAGUID_DEVELOPMENT: Bytes = utf8("appattestdevelop");

export const AAGUID_PRODUCTION: Bytes = (() => {
  const out = new Uint8Array(16);
  out.set(utf8("appattest"));
  return out;
})();

/** A certificate authority the suites control. */
export interface Authority {
  readonly certificate: x509.X509Certificate;
  readonly keys: CryptoKeyPair;
  readonly pem: string;
}

export async function makeRoot(name = "CN=Test App Attest Root CA"): Promise<Authority> {
  const keys = await crypto.subtle.generateKey(ECDSA_P256, true, ["sign", "verify"]);
  const certificate = await x509.X509CertificateGenerator.createSelfSigned({
    serialNumber: "01",
    name,
    notBefore: NOT_BEFORE,
    notAfter: NOT_AFTER,
    signingAlgorithm: SIGNING_ALG,
    keys,
    extensions: [new x509.BasicConstraintsExtension(true, 2, true)],
  });
  return { certificate, keys, pem: certificate.toString("pem") };
}

export async function makeIntermediate(
  root: Authority,
  name = "CN=Test App Attest CA 1",
): Promise<Authority> {
  const keys = await crypto.subtle.generateKey(ECDSA_P256, true, ["sign", "verify"]);
  const certificate = await x509.X509CertificateGenerator.create({
    serialNumber: "02",
    subject: name,
    issuer: root.certificate.subject,
    notBefore: NOT_BEFORE,
    notAfter: NOT_AFTER,
    signingAlgorithm: SIGNING_ALG,
    publicKey: keys.publicKey,
    signingKey: root.keys.privateKey,
    extensions: [new x509.BasicConstraintsExtension(true, 1, true)],
  });
  return { certificate, keys, pem: certificate.toString("pem") };
}

/** A device: its Secure-Enclave-shaped key pair and the key id Apple derives. */
export interface Device {
  readonly keys: CryptoKeyPair;
  /** Uncompressed P-256 point. */
  readonly publicKey: Bytes;
  /** SHA-256 of publicKey, which is what Apple calls the key id. */
  readonly keyId: Bytes;
}

export async function makeDevice(): Promise<Device> {
  const keys = await crypto.subtle.generateKey(ECDSA_P256, true, ["sign", "verify"]);
  const publicKey = new Uint8Array(await crypto.subtle.exportKey("raw", keys.publicKey));
  return { keys, publicKey, keyId: await sha256(publicKey) };
}

function concatenate(...parts: Bytes[]): Bytes {
  const out = new Uint8Array(parts.reduce((length, part) => length + part.length, 0));
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
}

/** Apple's fixed 77-byte EC2/ES256/P-256 COSE key encoding. */
export function encodeCosePublicKey(publicKey: Bytes): Bytes {
  if (publicKey.length !== 65 || publicKey[0] !== 0x04) {
    throw new Error("the test public key must be an uncompressed P-256 point");
  }
  return new Uint8Array([
    0xa5, // five pairs
    0x01,
    0x02, // 1 (kty): 2 (EC2)
    0x03,
    0x26, // 3 (alg): -7 (ES256)
    0x20,
    0x01, // -1 (crv): 1 (P-256)
    0x21,
    0x58,
    0x20,
    ...publicKey.slice(1, 33), // -2: x
    0x22,
    0x58,
    0x20,
    ...publicKey.slice(33, 65), // -3: y
  ]);
}

/** The two extensions in Apple's iOS 27 attestation authenticator data. */
export function encodeAttestationExtensions(
  validationCategory = 4,
  bundleVersion = "1",
): Bytes {
  const category = new Uint8Array(4);
  new DataView(category.buffer).setUint32(0, validationCategory, true);
  return encodeCbor({
    apple_bundle_version_01: bundleVersion,
    apple_validation_category_01: category,
  });
}

/** Assembles authenticator data in the WebAuthn layout App Attest uses. */
export function buildAuthenticatorData(options: {
  rpIdHash: Bytes;
  signCount: number;
  aaguid?: Bytes;
  credentialId?: Bytes;
  credentialPublicKey?: Bytes;
  validationCategory?: number;
  bundleVersion?: string;
  attestationSuffix?: Bytes;
}): Bytes {
  const hasCredential = options.aaguid !== undefined;
  const credentialId = options.credentialId ?? new Uint8Array(0);
  const suffix = !hasCredential ? new Uint8Array(0) : options.attestationSuffix ??
    (options.credentialPublicKey === undefined ? new Uint8Array(0) : concatenate(
      encodeCosePublicKey(options.credentialPublicKey),
      encodeAttestationExtensions(
        options.validationCategory,
        options.bundleVersion,
      ),
    ));
  const length = hasCredential ? 55 + credentialId.length + suffix.length : 37;
  const out = new Uint8Array(length);
  const view = new DataView(out.buffer);

  out.set(options.rpIdHash, 0);
  out[32] = hasCredential ? 0x40 : 0x00;
  view.setUint32(33, options.signCount, false);

  if (hasCredential) {
    out.set(options.aaguid!, 37);
    view.setUint16(53, credentialId.length, false);
    out.set(credentialId, 55);
    out.set(suffix, 55 + credentialId.length);
  }

  return out;
}

export function nonceExtensionValue(nonce: Bytes): Bytes {
  return new Uint8Array([0x30, 0x24, 0xa1, 0x22, 0x04, 0x20, ...nonce]);
}

/** Options for building one attestation, each defaulting to the valid case. */
export interface AttestationOptions {
  readonly appId?: string;
  readonly clientData?: Bytes;
  readonly aaguid?: Bytes;
  readonly signCount?: number;
  /** Overrides the key id written into the authenticator data. */
  readonly credentialId?: Bytes;
  /** Overrides the COSE key written into the authenticator data. */
  readonly credentialPublicKey?: Bytes;
  readonly validationCategory?: number;
  readonly bundleVersion?: string;
  /** Emits the pre-iOS 27 form that ends immediately after credentialId. */
  readonly legacyAuthenticatorData?: boolean;
  /** Replaces the complete COSE-key/extensions suffix. */
  readonly attestationSuffix?: Bytes;
  /** Overrides the nonce placed in the leaf certificate. */
  readonly nonceOverride?: Bytes;
  /** Replaces the complete DER value of the nonce extension. */
  readonly nonceExtensionValueOverride?: Bytes;
  /** Leaves the nonce extension off entirely. */
  readonly omitNonceExtension?: boolean;
  /** Signs the leaf with this authority instead of the intermediate. */
  readonly leafIssuer?: Authority;
  /** Replaces the certificate list sent to the verifier. */
  readonly x5cOverride?: Bytes[];
  /** Puts a different public key in the leaf than the device's. */
  readonly certificateKey?: CryptoKey;
}

export interface BuiltAttestation {
  /** The CBOR attestation object, as Apple would return it. */
  readonly attestationObject: Bytes;
  readonly authenticatorData: Bytes;
  readonly clientData: Bytes;
  readonly x5c: Bytes[];
  readonly keyId: Bytes;
}

export async function buildAttestation(
  root: Authority,
  intermediate: Authority,
  device: Device,
  options: AttestationOptions = {},
): Promise<BuiltAttestation> {
  const appId = options.appId ?? "ABCDE12345.test.gametime.app";
  const clientData = options.clientData ?? utf8("a-server-issued-challenge");
  const aaguid = options.aaguid ?? AAGUID_PRODUCTION;
  const defaultCategory = bytesEqual(aaguid, AAGUID_DEVELOPMENT) ? 3 : 4;

  const authenticatorData = buildAuthenticatorData({
    rpIdHash: await sha256(utf8(appId)),
    signCount: options.signCount ?? 0,
    aaguid,
    credentialId: options.credentialId ?? device.keyId,
    credentialPublicKey: options.credentialPublicKey ?? device.publicKey,
    validationCategory: options.validationCategory ?? defaultCategory,
    bundleVersion: options.bundleVersion ?? "1",
    attestationSuffix: options.legacyAuthenticatorData
      ? new Uint8Array(0)
      : options.attestationSuffix,
  });

  const nonce = options.nonceOverride ??
    await sha256(authenticatorData, await sha256(clientData));

  const issuer = options.leafIssuer ?? intermediate;

  const leaf = await x509.X509CertificateGenerator.create({
    serialNumber: "03",
    subject: "CN=Test Device Credential",
    issuer: issuer.certificate.subject,
    notBefore: NOT_BEFORE,
    notAfter: NOT_AFTER,
    signingAlgorithm: SIGNING_ALG,
    publicKey: options.certificateKey ?? device.keys.publicKey,
    signingKey: issuer.keys.privateKey,
    extensions: options.omitNonceExtension ? [] : [
      new x509.Extension(
        "1.2.840.113635.100.8.2",
        false,
        options.nonceExtensionValueOverride ?? nonceExtensionValue(nonce),
      ),
    ],
  });

  const x5c = options.x5cOverride ?? [
    new Uint8Array(leaf.rawData),
    new Uint8Array(intermediate.certificate.rawData),
  ];

  const attestationObject = encodeCbor({
    fmt: "apple-appattest",
    attStmt: {
      x5c: x5c,
      receipt: new Uint8Array([0xde, 0xad]),
    },
    authData: authenticatorData,
  });

  // Root is unused in the happy path but keeps the signature honest about what
  // a caller must supply, and lets a test build a chain against a second root.
  void root;

  return { attestationObject, authenticatorData, clientData, x5c, keyId: device.keyId };
}

export interface AssertionOptions {
  readonly appId?: string;
  readonly signCount?: number;
  /** Signs with this key instead of the device's. */
  readonly signingKey?: CryptoKey;
  /** Signs over different bytes than the ones returned. */
  readonly signedClientData?: Bytes;
}

export interface BuiltAssertion {
  /** The CBOR assertion, as Apple would return it. */
  readonly assertionObject: Bytes;
  readonly authenticatorData: Bytes;
  /** DER, which is the form Apple emits. */
  readonly signature: Bytes;
}

export async function buildAssertion(
  device: Device,
  clientData: Bytes,
  options: AssertionOptions = {},
): Promise<BuiltAssertion> {
  const appId = options.appId ?? "ABCDE12345.test.gametime.app";

  const authenticatorData = buildAuthenticatorData({
    rpIdHash: await sha256(utf8(appId)),
    signCount: options.signCount ?? 1,
  });

  const signedOver = options.signedClientData ?? clientData;
  const nonce = await sha256(authenticatorData, await sha256(signedOver));

  const raw = new Uint8Array(
    await crypto.subtle.sign(
      ECDSA_SHA256,
      options.signingKey ?? device.keys.privateKey,
      nonce,
    ),
  );
  const signature = rawToDerEcdsaSignature(raw);

  const assertionObject = encodeCbor({ signature, authenticatorData });

  return { assertionObject, authenticatorData, signature };
}
