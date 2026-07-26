/**
 * Synthetic App Attest receipt PKCS#7 fixtures.
 *
 * Every certificate and signature is minted at test time. No Apple receipt,
 * private key, device identifier, or staging value is checked in. The shape is
 * Apple's documented App-Store-receipt-style payload inside CMS SignedData.
 */

import * as asn1js from "asn1js";
import * as pkijs from "pkijs";
import * as x509 from "@peculiar/x509";
import {
  APP_ATTEST_RECEIPT_SIGNER_OID,
  type AppAttestReceiptType,
} from "../_shared/appattest_receipt.ts";
import type { Bytes } from "../_shared/bytes.ts";

const ECDSA_P256 = { name: "ECDSA", namedCurve: "P-256" } as const;
const SIGNING_ALG = { name: "ECDSA", namedCurve: "P-256", hash: "SHA-256" } as const;
const NOT_BEFORE = new Date("2020-01-01T00:00:00Z");
const NOT_AFTER = new Date("2040-01-01T00:00:00Z");

export const RECEIPT_APP_ID = "ABCDE12345.test.gametime.app";
export const RECEIPT_CAPTURED_AT = new Date("2026-08-01T12:00:00.000Z");
export const RECEIPT_CREATED_AT = new Date("2026-08-01T11:59:00.000Z");

export interface ReceiptAuthority {
  readonly certificate: x509.X509Certificate;
  readonly keys: CryptoKeyPair;
  readonly pem: string;
}

export interface ReceiptFixtureContext {
  readonly root: ReceiptAuthority;
  readonly intermediate: ReceiptAuthority;
  readonly signer: ReceiptAuthority;
  readonly deviceKeys: CryptoKeyPair;
  readonly publicKey: Bytes;
  readonly deviceCertificate: x509.X509Certificate;
}

export interface ReceiptAttributeFixture {
  readonly type: number;
  readonly version?: number;
  readonly value: Bytes;
}

export interface ReceiptFixtureOptions {
  readonly appId?: string;
  readonly creationTime?: string;
  readonly receiptType?: AppAttestReceiptType | string;
  readonly attestedKeyCertificate?: Bytes;
  readonly omitFields?: readonly number[];
  readonly duplicateFields?: readonly number[];
  /** Overrides the ASN.1 schema version of selected receipt fields. */
  readonly fieldVersions?: Readonly<Record<number, number>>;
  readonly extraAttributes?: readonly ReceiptAttributeFixture[];
  readonly payloadOverride?: Bytes;
  readonly signer?: ReceiptAuthority;
  readonly certificates?: readonly x509.X509Certificate[];
  readonly contentType?: string;
  readonly detached?: boolean;
  readonly signerCount?: number;
}

export interface BuiltReceiptFixture {
  readonly receipt: Bytes;
  readonly payload: Bytes;
}

function raw(certificate: x509.X509Certificate): Bytes {
  return new Uint8Array(certificate.rawData);
}

function pkijsCertificate(certificate: x509.X509Certificate): pkijs.Certificate {
  return pkijs.Certificate.fromBER(certificate.rawData);
}

async function makeRoot(): Promise<ReceiptAuthority> {
  const keys = await crypto.subtle.generateKey(ECDSA_P256, true, ["sign", "verify"]);
  const certificate = await x509.X509CertificateGenerator.createSelfSigned({
    serialNumber: "10",
    name: "CN=Test Apple Receipt Root",
    notBefore: NOT_BEFORE,
    notAfter: NOT_AFTER,
    signingAlgorithm: SIGNING_ALG,
    keys,
    extensions: [
      new x509.BasicConstraintsExtension(true, 2, true),
      new x509.KeyUsagesExtension(
        x509.KeyUsageFlags.keyCertSign | x509.KeyUsageFlags.cRLSign,
        true,
      ),
      await x509.SubjectKeyIdentifierExtension.create(keys.publicKey),
    ],
  });
  return { certificate, keys, pem: certificate.toString("pem") };
}

async function makeIssuedAuthority(
  issuer: ReceiptAuthority,
  options: {
    readonly serialNumber: string;
    readonly subject: string;
    readonly isCa: boolean;
    readonly pathLength?: number;
    readonly notBefore?: Date;
    readonly notAfter?: Date;
    readonly extendedKeyUsages?: readonly string[];
    readonly receiptSigningMarker?: boolean;
  },
): Promise<ReceiptAuthority> {
  const keys = await crypto.subtle.generateKey(ECDSA_P256, true, ["sign", "verify"]);
  const keyUsage = options.isCa
    ? x509.KeyUsageFlags.keyCertSign | x509.KeyUsageFlags.cRLSign
    : x509.KeyUsageFlags.digitalSignature;
  const certificate = await x509.X509CertificateGenerator.create({
    serialNumber: options.serialNumber,
    subject: options.subject,
    issuer: issuer.certificate.subject,
    notBefore: options.notBefore ?? NOT_BEFORE,
    notAfter: options.notAfter ?? NOT_AFTER,
    signingAlgorithm: SIGNING_ALG,
    publicKey: keys.publicKey,
    signingKey: issuer.keys.privateKey,
    extensions: [
      new x509.BasicConstraintsExtension(
        options.isCa,
        options.pathLength,
        true,
      ),
      new x509.KeyUsagesExtension(keyUsage, true),
      await x509.SubjectKeyIdentifierExtension.create(keys.publicKey),
      await x509.AuthorityKeyIdentifierExtension.create(
        issuer.certificate,
        false,
      ),
      ...(options.extendedKeyUsages === undefined ? [] : [
        new x509.ExtendedKeyUsageExtension([
          ...options.extendedKeyUsages,
        ]),
      ]),
      ...(options.receiptSigningMarker
        ? [
          new x509.Extension(
            APP_ATTEST_RECEIPT_SIGNER_OID,
            false,
            new Uint8Array([0x05, 0x00]),
          ),
        ]
        : []),
    ],
  });
  return { certificate, keys, pem: certificate.toString("pem") };
}

export async function makeReceiptFixtureContext(
  deviceKeys?: CryptoKeyPair,
): Promise<ReceiptFixtureContext> {
  const root = await makeRoot();
  const intermediate = await makeIssuedAuthority(root, {
    serialNumber: "11",
    subject: "CN=Test Apple Receipt CA",
    isCa: true,
    pathLength: 1,
  });
  const signer = await makeIssuedAuthority(intermediate, {
    serialNumber: "12",
    subject: "CN=Test Apple Receipt Signer",
    isCa: false,
    receiptSigningMarker: true,
  });

  deviceKeys ??= await crypto.subtle.generateKey(ECDSA_P256, true, [
    "sign",
    "verify",
  ]);
  const publicKey = new Uint8Array(
    await crypto.subtle.exportKey("raw", deviceKeys.publicKey),
  );
  const deviceCertificate = await x509.X509CertificateGenerator.create({
    serialNumber: "13",
    subject: "CN=Test App Attest Device Key",
    issuer: intermediate.certificate.subject,
    notBefore: NOT_BEFORE,
    notAfter: NOT_AFTER,
    signingAlgorithm: SIGNING_ALG,
    publicKey: deviceKeys.publicKey,
    signingKey: intermediate.keys.privateKey,
  });

  return {
    root,
    intermediate,
    signer,
    deviceKeys,
    publicKey,
    deviceCertificate,
  };
}

export async function makeExpiredReceiptSigner(
  intermediate: ReceiptAuthority,
): Promise<ReceiptAuthority> {
  return await makeIssuedAuthority(intermediate, {
    serialNumber: "14",
    subject: "CN=Expired Test Apple Receipt Signer",
    isCa: false,
    notBefore: new Date("2020-01-01T00:00:00Z"),
    notAfter: new Date("2025-01-01T00:00:00Z"),
    receiptSigningMarker: true,
  });
}

/** A same-root signer that is valid for code signing, not App Attest receipts. */
export async function makeWrongPurposeReceiptSigner(
  intermediate: ReceiptAuthority,
): Promise<ReceiptAuthority> {
  return await makeIssuedAuthority(intermediate, {
    serialNumber: "15",
    subject: "CN=Wrong-Purpose Test Apple Signer",
    isCa: false,
    extendedKeyUsages: [x509.ExtendedKeyUsage.codeSigning],
  });
}

function text(value: string): Bytes {
  return new TextEncoder().encode(value);
}

function receiptAttribute(attribute: ReceiptAttributeFixture): asn1js.Sequence {
  return new asn1js.Sequence({
    value: [
      new asn1js.Integer({ value: attribute.type }),
      new asn1js.Integer({ value: attribute.version ?? 1 }),
      new asn1js.OctetString({ valueHex: attribute.value }),
    ],
  });
}

function receiptPayload(
  context: ReceiptFixtureContext,
  options: ReceiptFixtureOptions,
): Bytes {
  if (options.payloadOverride !== undefined) return options.payloadOverride;

  const attributes: ReceiptAttributeFixture[] = [
    {
      type: 2,
      value: text(options.appId ?? RECEIPT_APP_ID),
    },
    {
      type: 3,
      value: options.attestedKeyCertificate ?? raw(context.deviceCertificate),
    },
    {
      type: 4,
      value: new Uint8Array(32).fill(0x44),
    },
    {
      type: 5,
      value: text("synthetic-token"),
    },
    {
      type: 6,
      value: text(options.receiptType ?? "ATTEST"),
    },
    {
      type: 12,
      value: text(options.creationTime ?? RECEIPT_CREATED_AT.toISOString()),
    },
    {
      type: 21,
      value: text("2026-09-01T12:00:00.000Z"),
    },
    ...(options.extraAttributes ?? []),
  ];

  const omitted = new Set(options.omitFields ?? []);
  const selected = attributes.filter((attribute) => !omitted.has(attribute.type));
  for (const attribute of selected) {
    const version = options.fieldVersions?.[attribute.type];
    if (version !== undefined) {
      const index = selected.indexOf(attribute);
      selected[index] = { ...attribute, version };
    }
  }
  for (const duplicate of options.duplicateFields ?? []) {
    const source = selected.find((attribute) => attribute.type === duplicate);
    if (source !== undefined) selected.push({ ...source });
  }

  return new Uint8Array(
    new asn1js.Set({
      // Reverse field order deliberately. Receipt SET ordering must not become
      // a semantic dependency in the verifier.
      value: selected.reverse().map(receiptAttribute),
    }).toBER(false),
  );
}

function signerInfo(certificate: pkijs.Certificate): pkijs.SignerInfo {
  return new pkijs.SignerInfo({
    version: 1,
    sid: new pkijs.IssuerAndSerialNumber({
      issuer: certificate.issuer,
      serialNumber: certificate.serialNumber,
    }),
  });
}

export async function buildReceiptFixture(
  context: ReceiptFixtureContext,
  options: ReceiptFixtureOptions = {},
): Promise<BuiltReceiptFixture> {
  const payload = receiptPayload(context, options);
  const signer = options.signer ?? context.signer;
  const signerCertificate = pkijsCertificate(signer.certificate);
  const signerCount = options.signerCount ?? 1;

  const signedData = new pkijs.SignedData({
    version: 1,
    encapContentInfo: new pkijs.EncapsulatedContentInfo({
      eContentType: options.contentType ?? pkijs.ContentInfo.DATA,
      ...(options.detached ? {} : { eContent: new asn1js.OctetString({ valueHex: payload }) }),
    }),
    signerInfos: Array.from(
      { length: signerCount },
      () => signerInfo(signerCertificate),
    ),
    certificates: (options.certificates ?? [
      signer.certificate,
      context.intermediate.certificate,
    ]).map(pkijsCertificate),
  });

  for (let index = 0; index < signerCount; index++) {
    await signedData.sign(
      signer.keys.privateKey,
      index,
      "SHA-256",
      options.detached ? payload : undefined,
    );
  }

  const contentInfo = new pkijs.ContentInfo({
    contentType: pkijs.ContentInfo.SIGNED_DATA,
    content: signedData.toSchema(true),
  });

  return {
    receipt: new Uint8Array(contentInfo.toSchema().toBER(false)),
    payload,
  };
}

/** Returns a copy with one matching byte changed, useful for signature failures. */
export function tamperFirst(haystack: Bytes, needle: Bytes): Bytes {
  const output = Uint8Array.from(haystack);
  outer:
  for (let start = 0; start <= output.length - needle.length; start++) {
    for (let offset = 0; offset < needle.length; offset++) {
      if (output[start + offset] !== needle[offset]) continue outer;
    }
    output[start] = output[start]! ^ 0x01;
    return output;
  }
  throw new Error("fixture bytes do not contain the requested sequence");
}

/** Re-encodes the outer ContentInfo SEQUENCE with BER indefinite length. */
export function outerSequenceAsIndefinite(der: Bytes): Bytes {
  if (der[0] !== 0x30 || der.length < 2) {
    throw new Error("fixture is not a DER SEQUENCE");
  }
  const firstLength = der[1]!;
  const lengthBytes = (firstLength & 0x80) === 0 ? 0 : firstLength & 0x7f;
  if (lengthBytes > 4 || 2 + lengthBytes > der.length) {
    throw new Error("fixture has an unsupported DER length");
  }
  const contentOffset = 2 + lengthBytes;
  const output = new Uint8Array(2 + der.length - contentOffset + 2);
  output.set([0x30, 0x80], 0);
  output.set(der.slice(contentOffset), 2);
  // End-of-contents is already zero-filled.
  return output;
}

export function certificateBytes(certificate: x509.X509Certificate): Bytes {
  return raw(certificate);
}
