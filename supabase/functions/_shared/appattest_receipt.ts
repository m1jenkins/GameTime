/**
 * Independent verification for the PKCS#7 receipt beside an App Attest
 * attestation.
 *
 * The attestation certificate authenticates the device key registration. It
 * does not authenticate the separate `attStmt.receipt` bytes, so those bytes
 * stay quarantined until every check here succeeds:
 *
 *   1. the CMS signature and signer chain reach Apple's public receipt root;
 *   2. the signed payload names this exact App ID;
 *   3. its creation time was no more than five minutes before first capture;
 *   4. the certificate in field 3 carries the already-attested public key.
 *
 * The caller receives the receipt digest only on complete success. That digest
 * is the capability passed to the narrowly scoped database marker RPC, which
 * prevents a concurrently refreshed receipt from inheriting this result.
 */

import * as asn1js from "asn1js";
import * as pkijs from "pkijs";
import * as x509 from "@peculiar/x509";
import { type Bytes, bytesEqual, sha256 } from "./bytes.ts";

export class ReceiptVerificationError extends Error {
  override readonly name = "ReceiptVerificationError";
}

/** Apple's replay-resistance window for a newly received App Attest receipt. */
export const RECEIPT_MAX_AGE_MS = 5 * 60 * 1000;

/** Private extension on Apple's dedicated fraud-receipt CMS signer. */
export const APP_ATTEST_RECEIPT_SIGNER_OID = "1.2.840.113635.100.12.15";

/** Registration returns ATTEST; Apple's later fraud-metric exchange returns RECEIPT. */
export type AppAttestReceiptType = "ATTEST" | "RECEIPT";

export interface AppAttestReceiptRequest {
  /** Raw DER/BER PKCS#7 ContentInfo bytes. */
  readonly receipt: Bytes;
  /** `<team-id>.<bundle-id>`. */
  readonly appId: string;
  /** Stored X9.62 uncompressed P-256 point from verified attestation. */
  readonly publicKey: Bytes;
  /** Apple's public root certificate for App Attest receipt signing, PEM. */
  readonly receiptRootCertificatePem: string;
  /** Immutable time this exact receipt candidate first entered quarantine. */
  readonly receivedAt: Date;
  /** Which receipt kind this call accepts. Initial registration requires ATTEST. */
  readonly expectedTypes?: readonly AppAttestReceiptType[];
}

export interface VerifiedAppAttestReceipt {
  readonly type: AppAttestReceiptType;
  readonly creationTime: Date;
  /** SHA-256 over the exact PKCS#7 bytes that passed every check. */
  readonly receiptSha256: Bytes;
}

interface ParsedCms {
  readonly signedData: pkijs.SignedData;
  readonly payload: Bytes;
}

interface ReceiptAttribute {
  readonly type: number;
  readonly version: number;
  readonly value: Bytes;
}

const CMS_DATA_OID = "1.2.840.113549.1.7.1";
const MAX_RECEIPT_BYTES = 32 * 1024;
const MAX_CERTIFICATES = 8;
const MAX_ATTRIBUTES = 32;

const FIELD_APP_ID = 2;
const FIELD_ATTESTED_PUBLIC_KEY = 3;
const FIELD_RECEIPT_TYPE = 6;
const FIELD_CREATION_TIME = 12;

const ECDSA_P256 = { name: "ECDSA", namedCurve: "P-256" } as const;
const UTF8 = new TextDecoder("utf-8", { fatal: true });

function asArrayBuffer(bytes: Bytes): ArrayBuffer {
  return bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  ) as ArrayBuffer;
}

function fail(message: string, cause?: unknown): never {
  const detail = cause === undefined ? message : `${message}: ${String(cause)}`;
  throw new ReceiptVerificationError(detail);
}

function parseBer(bytes: Bytes, what: string): asn1js.BaseBlock {
  let parsed: asn1js.FromBerResult;
  try {
    parsed = asn1js.fromBER(asArrayBuffer(bytes), {
      maxDepth: 24,
      maxNodes: 512,
      maxContentLength: MAX_RECEIPT_BYTES,
    });
  } catch (cause) {
    fail(`${what} is not valid ASN.1`, cause);
  }
  if (parsed.offset === -1) {
    fail(`${what} is not valid ASN.1`);
  }
  if (parsed.offset !== bytes.length) {
    fail(`${what} has trailing bytes`);
  }
  return parsed.result;
}

function octetStringBytes(value: asn1js.OctetString, what: string): Bytes {
  try {
    return new Uint8Array(value.getValue());
  } catch (cause) {
    fail(`${what} is not a readable OCTET STRING`, cause);
  }
}

function parseCms(receipt: Bytes): ParsedCms {
  if (receipt.length === 0 || receipt.length > MAX_RECEIPT_BYTES) {
    fail(`receipt must contain 1 to ${MAX_RECEIPT_BYTES} bytes`);
  }

  let contentInfo: pkijs.ContentInfo;
  try {
    contentInfo = new pkijs.ContentInfo({
      schema: parseBer(receipt, "receipt PKCS#7 container"),
    });
  } catch (cause) {
    if (cause instanceof ReceiptVerificationError) throw cause;
    fail("receipt is not a PKCS#7 ContentInfo", cause);
  }
  if (contentInfo.contentType !== pkijs.ContentInfo.SIGNED_DATA) {
    fail("receipt ContentInfo is not SignedData");
  }

  let signedData: pkijs.SignedData;
  try {
    signedData = new pkijs.SignedData({ schema: contentInfo.content });
  } catch (cause) {
    fail("receipt SignedData is malformed", cause);
  }
  if (signedData.signerInfos.length !== 1) {
    fail("receipt must contain exactly one signer");
  }
  if (signedData.encapContentInfo.eContentType !== CMS_DATA_OID) {
    fail("receipt SignedData does not contain CMS data");
  }
  const eContent = signedData.encapContentInfo.eContent;
  if (!(eContent instanceof asn1js.OctetString)) {
    fail("receipt SignedData has no embedded payload");
  }
  if (
    signedData.certificates === undefined ||
    signedData.certificates.length === 0 ||
    signedData.certificates.length > MAX_CERTIFICATES ||
    signedData.certificates.some((certificate) => !(certificate instanceof pkijs.Certificate))
  ) {
    fail("receipt has an invalid embedded certificate set");
  }

  return {
    signedData,
    payload: octetStringBytes(eContent, "receipt payload"),
  };
}

function integerValue(value: asn1js.Integer, what: string): number {
  if (value.valueBlock.isHexOnly) {
    fail(`${what} is too large to interpret safely`);
  }
  const number = value.valueBlock.valueDec;
  if (!Number.isSafeInteger(number) || number < 0) {
    fail(`${what} is not a nonnegative safe integer`);
  }
  return number;
}

function parsePayload(payload: Bytes): Map<number, ReceiptAttribute> {
  const parsed = parseBer(payload, "receipt payload");
  if (!(parsed instanceof asn1js.Set)) {
    fail("receipt payload is not a SET OF attributes");
  }

  const values = parsed.valueBlock.value;
  if (values.length === 0 || values.length > MAX_ATTRIBUTES) {
    fail(`receipt payload must contain 1 to ${MAX_ATTRIBUTES} attributes`);
  }

  const attributes = new Map<number, ReceiptAttribute>();
  for (const [index, candidate] of values.entries()) {
    if (!(candidate instanceof asn1js.Sequence)) {
      fail(`receipt attribute ${index} is not a SEQUENCE`);
    }
    const parts = candidate.valueBlock.value;
    if (
      parts.length !== 3 ||
      !(parts[0] instanceof asn1js.Integer) ||
      !(parts[1] instanceof asn1js.Integer) ||
      !(parts[2] instanceof asn1js.OctetString)
    ) {
      fail(`receipt attribute ${index} has the wrong shape`);
    }

    const type = integerValue(parts[0], `receipt attribute ${index} type`);
    if (attributes.has(type)) {
      fail(`receipt payload repeats field ${type}`);
    }
    attributes.set(type, {
      type,
      version: integerValue(parts[1], `receipt field ${type} version`),
      value: octetStringBytes(parts[2], `receipt field ${type} value`),
    });
  }

  return attributes;
}

function requiredField(
  attributes: ReadonlyMap<number, ReceiptAttribute>,
  type: number,
): ReceiptAttribute {
  const attribute = attributes.get(type);
  if (attribute === undefined) fail(`receipt payload is missing field ${type}`);
  if (attribute.version !== 1) {
    fail(`receipt field ${type} uses unsupported version ${attribute.version}`);
  }
  return attribute;
}

function strictText(bytes: Bytes, what: string, maxLength: number): string {
  if (bytes.length === 0 || bytes.length > maxLength || bytes.includes(0)) {
    fail(`${what} is empty, oversized, or contains NUL`);
  }
  let value: string;
  try {
    value = UTF8.decode(bytes);
  } catch (cause) {
    fail(`${what} is not valid UTF-8`, cause);
  }
  // Reject non-canonical replacement paths and control characters. App IDs,
  // type names, and RFC 3339 timestamps need none of them.
  for (const character of value) {
    const codePoint = character.codePointAt(0)!;
    if (codePoint <= 0x1f || codePoint === 0x7f) {
      fail(`${what} contains a control character`);
    }
  }
  return value;
}

function receiptDate(bytes: Bytes): Date {
  const value = strictText(bytes, "receipt creation time", 64);
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?Z$/.exec(value);
  if (match === null) fail("receipt creation time is not strict RFC 3339 UTC");

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const second = Number(match[6]);
  const milliseconds = Number((match[7] ?? "").padEnd(3, "0"));
  const time = Date.UTC(year, month - 1, day, hour, minute, second, milliseconds);
  const parsed = new Date(time);
  if (
    !Number.isFinite(time) ||
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== month - 1 ||
    parsed.getUTCDate() !== day ||
    parsed.getUTCHours() !== hour ||
    parsed.getUTCMinutes() !== minute ||
    parsed.getUTCSeconds() !== second
  ) {
    fail("receipt creation time names an impossible date");
  }
  return parsed;
}

function pkijsCertificate(der: Bytes, what: string): pkijs.Certificate {
  try {
    return new pkijs.Certificate({ schema: parseBer(der, what) });
  } catch (cause) {
    if (cause instanceof ReceiptVerificationError) throw cause;
    fail(`${what} is not a certificate`, cause);
  }
}

async function verifyCms(
  signedData: pkijs.SignedData,
  rootCertificatePem: string,
  creationTime: Date,
): Promise<void> {
  let rootDer: Bytes;
  try {
    rootDer = new Uint8Array(new x509.X509Certificate(rootCertificatePem).rawData);
  } catch (cause) {
    fail("configured App Attest receipt root is unreadable", cause);
  }
  const root = pkijsCertificate(rootDer, "configured App Attest receipt root");

  let verification: pkijs.SignedDataVerifyResult;
  try {
    verification = await signedData.verify({
      signer: 0,
      checkChain: true,
      trustedCerts: [root],
      checkDate: creationTime,
      extendedMode: true,
    });
  } catch (cause) {
    fail("receipt signature or Apple certificate chain is invalid", cause);
  }
  if (
    verification.signatureVerified !== true ||
    verification.signerCertificateVerified !== true ||
    verification.signerCertificate === null ||
    verification.signerCertificate === undefined
  ) {
    fail("receipt signature or Apple certificate chain is invalid");
  }

  // Apple Root CA G3 is shared by several Apple PKI purposes, including
  // certificates whose private keys are not receipt signers. A valid generic
  // Apple chain is therefore insufficient: the exact certificate selected by
  // SignerInfo must carry Apple's dedicated fraud-receipt marker extension.
  const signerMarker = verification.signerCertificate.extensions?.find(
    (extension) => extension.extnID === APP_ATTEST_RECEIPT_SIGNER_OID,
  );
  if (
    signerMarker === undefined ||
    !bytesEqual(
      octetStringBytes(signerMarker.extnValue, "receipt signer marker"),
      new Uint8Array([0x05, 0x00]),
    )
  ) {
    fail("receipt signer is not an App Attest fraud-receipt signer");
  }
}

async function certificatePublicKey(certificateDer: Bytes): Promise<Bytes> {
  let certificate: x509.X509Certificate;
  try {
    certificate = new x509.X509Certificate(certificateDer);
  } catch (cause) {
    fail("receipt field 3 is not a DER X.509 certificate", cause);
  }

  try {
    const imported = await crypto.subtle.importKey(
      "spki",
      certificate.publicKey.rawData,
      ECDSA_P256,
      true,
      ["verify"],
    );
    const point = new Uint8Array(await crypto.subtle.exportKey("raw", imported));
    if (point.length !== 65 || point[0] !== 0x04) {
      fail("receipt field 3 does not carry an uncompressed P-256 public key");
    }
    return point;
  } catch (cause) {
    if (cause instanceof ReceiptVerificationError) throw cause;
    fail("receipt field 3 does not carry a P-256 public key", cause);
  }
}

/**
 * Verifies one quarantined App Attest receipt without performing any write.
 *
 * Field 12 is parsed before CMS verification only so its claimed instant can
 * be used as the certificate-chain validation time, as Apple requires. It
 * remains untrusted until the signature succeeds; all semantic checks follow.
 */
export async function verifyAppAttestReceipt(
  request: AppAttestReceiptRequest,
): Promise<VerifiedAppAttestReceipt> {
  if (
    !Number.isFinite(request.receivedAt.getTime()) ||
    request.publicKey.length !== 65 ||
    request.publicKey[0] !== 0x04
  ) {
    fail("receipt verification context is invalid");
  }

  const { signedData, payload } = parseCms(request.receipt);
  const attributes = parsePayload(payload);
  const creationTime = receiptDate(
    requiredField(attributes, FIELD_CREATION_TIME).value,
  );

  await verifyCms(
    signedData,
    request.receiptRootCertificatePem,
    creationTime,
  );

  const appId = strictText(
    requiredField(attributes, FIELD_APP_ID).value,
    "receipt App ID",
    256,
  );
  if (appId !== request.appId) {
    fail("receipt was produced for a different App ID");
  }

  const typeText = strictText(
    requiredField(attributes, FIELD_RECEIPT_TYPE).value,
    "receipt type",
    16,
  );
  if (typeText !== "ATTEST" && typeText !== "RECEIPT") {
    fail("receipt field 6 has an unknown type");
  }
  const type: AppAttestReceiptType = typeText;
  const expectedTypes = request.expectedTypes ?? ["ATTEST"];
  if (!expectedTypes.includes(type)) {
    fail(`receipt type ${type} is not accepted in this flow`);
  }

  const age = request.receivedAt.getTime() - creationTime.getTime();
  if (age < 0) {
    fail("receipt creation time is in the future");
  }
  if (age > RECEIPT_MAX_AGE_MS) {
    fail("receipt creation time is more than five minutes before capture");
  }

  const embeddedPublicKey = await certificatePublicKey(
    requiredField(attributes, FIELD_ATTESTED_PUBLIC_KEY).value,
  );
  if (!bytesEqual(embeddedPublicKey, request.publicKey)) {
    fail("receipt public key does not match the attested public key");
  }

  return {
    type,
    creationTime,
    receiptSha256: await sha256(request.receipt),
  };
}
