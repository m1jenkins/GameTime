/**
 * ECDSA signature verification without WebCrypto.
 *
 * Supabase's hosted Edge Runtime implements `crypto.subtle.verify` for ECDSA
 * only when the key curve and the digest are the matching pair — (P-256,
 * SHA-256) and (P-384, SHA-384). The cross pairs throw
 * `NotSupportedError: Not implemented`. Apple's App Attest PKI uses exactly
 * those cross pairs: the attestation leaf is a SHA-256 signature under the
 * P-384 intermediate, and the receipt chain has the same shape under Apple
 * Root CA G3. This was found live during the M6.5 device run (probe results
 * in the M6.5 thread): on the edge, `verify_P-384_SHA-256` and
 * `verify_P-256_SHA-384` are not implemented while both matched pairs work.
 *
 * The math here is plain FIPS 186-4 ECDSA over the published curve constants.
 * Message digesting still uses WebCrypto, which the runtime does implement for
 * both SHA-256 and SHA-384; only the group operations live here.
 */

export class EcdsaVerifyError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "EcdsaVerifyError";
  }
}

type Bytes = Uint8Array;

export type EcdsaCurveName = "P-256" | "P-384";

interface CurveParameters {
  readonly name: EcdsaCurveName;
  /** Field prime. */
  readonly p: bigint;
  /** Curve coefficient b; a is always p - 3 for these curves. */
  readonly b: bigint;
  /** Group order. */
  readonly n: bigint;
  /** Base point. */
  readonly gx: bigint;
  readonly gy: bigint;
  /** Byte length of one coordinate. */
  readonly coordinateBytes: number;
  /** OBJECT IDENTIFIER body for the curve, DER contents octets. */
  readonly oidBody: Bytes;
}

// secp256r1 / NIST P-256, FIPS 186-4 D.1.2.3. OID 1.2.840.10045.3.1.7.
const P256: CurveParameters = {
  name: "P-256",
  p: 0xffffffff00000001000000000000000000000000ffffffffffffffffffffffffn,
  b: 0x5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604bn,
  n: 0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551n,
  gx: 0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296n,
  gy: 0x4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5n,
  coordinateBytes: 32,
  oidBody: new Uint8Array([0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07]),
};

// secp384r1 / NIST P-384, FIPS 186-4 D.1.2.4. OID 1.3.132.0.34.
const P384: CurveParameters = {
  name: "P-384",
  p: 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeffffffff0000000000000000ffffffffn,
  b: 0xb3312fa7e23ee7e4988e056be3f82d19181d9c6efe8141120314088f5013875ac656398d8a2ed19d2a85c8edd3ec2aefn,
  n: 0xffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973n,
  gx:
    0xaa87ca22be8b05378eb1c71ef320ad746e1d3b628ba79b9859f741e082542a385502f25dbf55296c3a545e3872760ab7n,
  gy:
    0x3617de4a96262c6f5d9e98bf9292dc29f8f41dbd289a147ce9da3113b5f0b8c00a60b1ce1d7e819d7a431d7c90ea0e5fn,
  coordinateBytes: 48,
  oidBody: new Uint8Array([0x2b, 0x81, 0x04, 0x00, 0x22]),
};

const KNOWN_CURVES: readonly CurveParameters[] = [P256, P384];

/** id-ecPublicKey, RFC 5480. */
const OID_EC_PUBLIC_KEY = new Uint8Array([0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01]);

// ---------------------------------------------------------------------------
// Bigint field arithmetic
// ---------------------------------------------------------------------------

function mod(value: bigint, modulus: bigint): bigint {
  const result = value % modulus;
  return result >= 0n ? result : result + modulus;
}

function modMul(a: bigint, b: bigint, modulus: bigint): bigint {
  return mod(a * b, modulus);
}

/** a**exponent mod modulus, square-and-multiply. Moduli here are prime. */
function modPow(base: bigint, exponent: bigint, modulus: bigint): bigint {
  let result = 1n;
  let b = mod(base, modulus);
  let e = exponent;
  while (e > 0n) {
    if (e & 1n) result = modMul(result, b, modulus);
    b = modMul(b, b, modulus);
    e >>= 1n;
  }
  return result;
}

function modInverse(value: bigint, modulus: bigint): bigint {
  const v = mod(value, modulus);
  if (v === 0n) throw new EcdsaVerifyError("cannot invert zero");
  return modPow(v, modulus - 2n, modulus);
}

// ---------------------------------------------------------------------------
// Jacobian point arithmetic (curve coefficient a = -3 for both curves)
// ---------------------------------------------------------------------------

interface JacobianPoint {
  readonly x: bigint;
  readonly y: bigint;
  readonly z: bigint;
}

const POINT_AT_INFINITY: JacobianPoint = { x: 0n, y: 1n, z: 0n };

function isInfinity(point: JacobianPoint): boolean {
  return point.z === 0n;
}

function toJacobian(x: bigint, y: bigint): JacobianPoint {
  return { x, y, z: 1n };
}

function toAffine(
  point: JacobianPoint,
  curve: CurveParameters,
): { readonly x: bigint; readonly y: bigint } | null {
  if (isInfinity(point)) return null;
  const zInverse = modInverse(point.z, curve.p);
  const zInverseSquared = modMul(zInverse, zInverse, curve.p);
  return {
    x: modMul(point.x, zInverseSquared, curve.p),
    y: modMul(point.y, modMul(zInverseSquared, zInverse, curve.p), curve.p),
  };
}

/** Point doubling for a = -3, Guide to Elliptic Curve Cryptography 3.21. */
function pointDouble(point: JacobianPoint, curve: CurveParameters): JacobianPoint {
  if (isInfinity(point) || point.y === 0n) return POINT_AT_INFINITY;
  const p = curve.p;
  const delta = modMul(point.z, point.z, p);
  const gamma = modMul(point.y, point.y, p);
  const beta = modMul(point.x, gamma, p);
  const alpha = mod(
    3n * mod(point.x - delta, p) * mod(point.x + delta, p),
    p,
  );
  const x3 = mod(alpha * alpha - 8n * beta, p);
  const z3 = mod((point.y + point.z) * (point.y + point.z) - gamma - delta, p);
  const y3 = mod(alpha * (4n * beta - x3) - 8n * gamma * gamma, p);
  return { x: x3, y: y3, z: z3 };
}

/** Mixed addition: Jacobian point plus an affine point. */
function pointAddAffine(
  point: JacobianPoint,
  affineX: bigint,
  affineY: bigint,
  curve: CurveParameters,
): JacobianPoint {
  if (isInfinity(point)) return toJacobian(affineX, affineY);
  const p = curve.p;
  const z1z1 = modMul(point.z, point.z, p);
  const u2 = modMul(affineX, z1z1, p);
  const s2 = modMul(affineY, modMul(z1z1, point.z, p), p);
  const h = mod(u2 - point.x, p);
  const r = mod(2n * (s2 - point.y), p);
  if (h === 0n) {
    if (r === 0n) return pointDouble(point, curve);
    return POINT_AT_INFINITY;
  }
  const hh = modMul(h, h, p);
  const i = mod(4n * hh, p);
  const j = modMul(h, i, p);
  const v = modMul(point.x, i, p);
  const x3 = mod(r * r - j - 2n * v, p);
  const y3 = mod(r * (v - x3) - 2n * point.y * j, p);
  const z3 = mod((point.z + h) * (point.z + h) - z1z1 - hh, p);
  return { x: x3, y: y3, z: z3 };
}

function scalarMultiply(
  scalar: bigint,
  x: bigint,
  y: bigint,
  curve: CurveParameters,
): JacobianPoint {
  let result = POINT_AT_INFINITY;
  const bits = scalar.toString(2);
  for (const bit of bits) {
    result = pointDouble(result, curve);
    if (bit === "1") result = pointAddAffine(result, x, y, curve);
  }
  return result;
}

function isOnCurve(x: bigint, y: bigint, curve: CurveParameters): boolean {
  const p = curve.p;
  const left = modMul(y, y, p);
  const right = mod(modMul(modMul(x, x, p), x, p) - 3n * x + curve.b, p);
  return left === right;
}

// ---------------------------------------------------------------------------
// Byte and DER helpers
// ---------------------------------------------------------------------------

function bytesToBigint(bytes: Bytes): bigint {
  let value = 0n;
  for (const byte of bytes) value = (value << 8n) | BigInt(byte);
  return value;
}

export function bigintToBytes(value: bigint, length: number): Bytes {
  const out = new Uint8Array(length);
  let v = value;
  for (let i = length - 1; i >= 0; i--) {
    out[i] = Number(v & 0xffn);
    v >>= 8n;
  }
  if (v !== 0n) throw new EcdsaVerifyError("integer does not fit the field size");
  return out;
}

interface TlvElement {
  readonly tag: number;
  readonly valueStart: number;
  readonly valueEnd: number;
  readonly next: number;
}

function readTlv(bytes: Bytes, offset: number, what: string): TlvElement {
  if (offset + 2 > bytes.length) {
    throw new EcdsaVerifyError(`${what}: truncated TLV header`);
  }
  const tag = bytes[offset]!;
  let length = bytes[offset + 1]!;
  let cursor = offset + 2;
  if (length === 0x80) {
    throw new EcdsaVerifyError(`${what}: indefinite length is not DER`);
  }
  if (length > 0x80) {
    const lengthBytes = length & 0x7f;
    if (lengthBytes > 3 || cursor + lengthBytes > bytes.length) {
      throw new EcdsaVerifyError(`${what}: bad long-form length`);
    }
    length = 0;
    for (let i = 0; i < lengthBytes; i++) {
      length = (length << 8) | bytes[cursor + i]!;
    }
    cursor += lengthBytes;
  }
  if (cursor + length > bytes.length) {
    throw new EcdsaVerifyError(`${what}: TLV value overruns the input`);
  }
  return { tag, valueStart: cursor, valueEnd: cursor + length, next: cursor + length };
}

function expectTlv(
  bytes: Bytes,
  offset: number,
  tag: number,
  what: string,
): TlvElement {
  const element = readTlv(bytes, offset, what);
  if (element.tag !== tag) {
    throw new EcdsaVerifyError(
      `${what}: expected tag 0x${tag.toString(16)}, got 0x${element.tag.toString(16)}`,
    );
  }
  return element;
}

function bytesEqual(a: Bytes, b: Bytes): boolean {
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a[i]! ^ b[i]!;
  return difference === 0;
}

// ---------------------------------------------------------------------------
// Public parsing helpers
// ---------------------------------------------------------------------------

export interface EcdsaSignature {
  readonly r: bigint;
  readonly s: bigint;
}

/** Parses an ASN.1 ECDSA-Sig-Value (SEQUENCE of two INTEGERs). */
export function parseEcdsaSignatureDer(signatureDer: Bytes): EcdsaSignature {
  const what = "ECDSA signature";
  const sequence = expectTlv(signatureDer, 0, 0x30, what);
  if (sequence.valueEnd !== signatureDer.length) {
    throw new EcdsaVerifyError(`${what}: trailing bytes after the SEQUENCE`);
  }
  const rElement = expectTlv(signatureDer, sequence.valueStart, 0x02, what);
  const sElement = expectTlv(signatureDer, rElement.next, 0x02, what);
  if (sElement.next !== sequence.valueEnd) {
    throw new EcdsaVerifyError(`${what}: unexpected element after s`);
  }
  const r = bytesToBigint(
    signatureDer.subarray(rElement.valueStart, rElement.valueEnd),
  );
  const s = bytesToBigint(
    signatureDer.subarray(sElement.valueStart, sElement.valueEnd),
  );
  return { r, s };
}

export interface EcPublicPoint {
  readonly curve: CurveParameters;
  readonly x: bigint;
  readonly y: bigint;
}

/** Extracts the curve and uncompressed point from an EC SubjectPublicKeyInfo. */
export function ecPublicPointFromSpki(spki: Bytes): EcPublicPoint {
  const what = "EC SubjectPublicKeyInfo";
  const sequence = expectTlv(spki, 0, 0x30, what);
  if (sequence.valueEnd !== spki.length) {
    throw new EcdsaVerifyError(`${what}: trailing bytes after the SEQUENCE`);
  }
  const algorithm = expectTlv(spki, sequence.valueStart, 0x30, what);
  const keyOid = expectTlv(spki, algorithm.valueStart, 0x06, what);
  if (
    !bytesEqual(
      spki.subarray(keyOid.valueStart, keyOid.valueEnd),
      OID_EC_PUBLIC_KEY,
    )
  ) {
    throw new EcdsaVerifyError(`${what}: algorithm is not id-ecPublicKey`);
  }
  const curveOid = expectTlv(spki, keyOid.next, 0x06, what);
  const curve = KNOWN_CURVES.find((candidate) =>
    bytesEqual(spki.subarray(curveOid.valueStart, curveOid.valueEnd), candidate.oidBody)
  );
  if (curve === undefined) {
    throw new EcdsaVerifyError(`${what}: curve is not P-256 or P-384`);
  }
  const bitString = expectTlv(spki, algorithm.next, 0x03, what);
  if (bitString.valueEnd - bitString.valueStart !== 1 + 2 * curve.coordinateBytes + 1) {
    throw new EcdsaVerifyError(`${what}: public point has a bad length`);
  }
  if (spki[bitString.valueStart] !== 0x00) {
    throw new EcdsaVerifyError(`${what}: BIT STRING has unused bits`);
  }
  if (spki[bitString.valueStart + 1] !== 0x04) {
    throw new EcdsaVerifyError(`${what}: public point is not uncompressed`);
  }
  const x = bytesToBigint(
    spki.subarray(bitString.valueStart + 2, bitString.valueStart + 2 + curve.coordinateBytes),
  );
  const y = bytesToBigint(
    spki.subarray(bitString.valueStart + 2 + curve.coordinateBytes, bitString.valueEnd),
  );
  if (x >= curve.p || y >= curve.p || !isOnCurve(x, y, curve)) {
    throw new EcdsaVerifyError(`${what}: public point is not on the curve`);
  }
  return { curve, x, y };
}

export interface CertificateSignatureParts {
  /** The TBSCertificate element, full TLV — the exact signed bytes. */
  readonly tbs: Bytes;
  /** The signature BIT STRING contents: ASN.1 ECDSA-Sig-Value DER. */
  readonly signatureDer: Bytes;
}

/**
 * Splits a DER X.509 certificate into its signed body and signature value,
 * without relying on any parsing library's private surface:
 *   Certificate ::= SEQUENCE { tbsCertificate, signatureAlgorithm, BIT STRING }
 */
export function certificateSignatureParts(certificateDer: Bytes): CertificateSignatureParts {
  const what = "X.509 certificate";
  const sequence = expectTlv(certificateDer, 0, 0x30, what);
  if (sequence.valueEnd !== certificateDer.length) {
    throw new EcdsaVerifyError(`${what}: trailing bytes after the SEQUENCE`);
  }
  const tbsElement = readTlv(certificateDer, sequence.valueStart, what);
  if (tbsElement.tag !== 0x30) {
    throw new EcdsaVerifyError(`${what}: tbsCertificate is not a SEQUENCE`);
  }
  const algorithmElement = readTlv(certificateDer, tbsElement.next, what);
  const bitString = expectTlv(certificateDer, algorithmElement.next, 0x03, what);
  if (bitString.valueEnd - bitString.valueStart < 2) {
    throw new EcdsaVerifyError(`${what}: signature BIT STRING is empty`);
  }
  if (certificateDer[bitString.valueStart] !== 0x00) {
    throw new EcdsaVerifyError(`${what}: signature BIT STRING has unused bits`);
  }
  return {
    tbs: certificateDer.slice(sequence.valueStart, tbsElement.valueEnd),
    signatureDer: certificateDer.slice(bitString.valueStart + 1, bitString.valueEnd),
  };
}

// ---------------------------------------------------------------------------
// Verification
// ---------------------------------------------------------------------------

export type EcdsaDigestName = "SHA-256" | "SHA-384";

export interface EcdsaVerifyParams {
  readonly point: EcPublicPoint;
  readonly hash: EcdsaDigestName;
  readonly signature: EcdsaSignature;
  readonly message: Bytes;
}

/** FIPS 186-4 section 6.4 ECDSA verification of one message. */
export async function verifyEcdsa(params: EcdsaVerifyParams): Promise<boolean> {
  const { curve } = params.point;
  const { r, s } = params.signature;
  if (r < 1n || r >= curve.n || s < 1n || s >= curve.n) return false;

  // slice() copies into a fresh ArrayBuffer-backed array, which is what the
  // BufferSource parameter of subtle.digest demands from Uint8Array.
  const message = params.message.slice();
  const digest = new Uint8Array(await crypto.subtle.digest(params.hash, message));
  const digestBits = BigInt(digest.length * 8);
  const orderBits = BigInt(curve.n.toString(2).length);
  const digestInteger = bytesToBigint(digest);
  const e = digestBits > orderBits ? digestInteger >> (digestBits - orderBits) : digestInteger;

  const w = modInverse(s, curve.n);
  const u1 = modMul(e, w, curve.n);
  const u2 = modMul(r, w, curve.n);

  const u1TimesG = scalarMultiply(u1, curve.gx, curve.gy, curve);
  const u2TimesQ = scalarMultiply(u2, params.point.x, params.point.y, curve);
  let sum = u1TimesG;
  if (!isInfinity(u2TimesQ)) {
    const qAffine = toAffine(u2TimesQ, curve);
    if (qAffine !== null) {
      sum = pointAddAffine(u1TimesG, qAffine.x, qAffine.y, curve);
    }
  }
  const candidate = toAffine(sum, curve);
  if (candidate === null) return false;
  return mod(candidate.x, curve.n) === r;
}

export interface CertificateSignatureParams {
  /** The TBSCertificate bytes exactly as signed. */
  readonly tbs: Bytes;
  /** The certificate's signature value, ASN.1 ECDSA-Sig-Value DER. */
  readonly signatureDer: Bytes;
  /** Digest named by the certificate's signatureAlgorithm. */
  readonly hash: EcdsaDigestName;
  /** The issuer's SubjectPublicKeyInfo DER. */
  readonly issuerSpki: Bytes;
}

/**
 * Verifies one certificate's signature against its issuer's public key without
 * WebCrypto. Throws EcdsaVerifyError for malformed inputs; returns false for a
 * well-formed signature that does not match.
 */
export async function verifyCertificateSignatureEcdsa(
  params: CertificateSignatureParams,
): Promise<boolean> {
  const point = ecPublicPointFromSpki(params.issuerSpki);
  const signature = parseEcdsaSignatureDer(params.signatureDer);
  return await verifyEcdsa({
    point,
    hash: params.hash,
    signature,
    message: params.tbs,
  });
}

// ---------------------------------------------------------------------------
// WebCrypto fallback wiring
// ---------------------------------------------------------------------------

/**
 * True when an error is the hosted Edge Runtime's "this (curve, hash) pair is
 * not implemented" refusal, as opposed to a real verification failure (which
 * resolves false, not an exception).
 */
export function isUnsupportedSubtleError(cause: unknown): boolean {
  if (cause instanceof DOMException && cause.name === "NotSupportedError") {
    return true;
  }
  return cause instanceof Error &&
    cause.name === "NotSupportedError" &&
    /not implemented/i.test(cause.message);
}

interface NormalizedEcdsaParams {
  readonly hash: EcdsaDigestName;
  readonly curve: EcdsaCurveName;
  readonly coordinateBytes: number;
}

function normalizeEcdsaAlgorithm(
  algorithm: AlgorithmIdentifier | EcdsaParams,
  key: CryptoKey,
): NormalizedEcdsaParams {
  const name = typeof algorithm === "string" ? algorithm : algorithm.name;
  if (name.toUpperCase() !== "ECDSA") {
    throw new EcdsaVerifyError(`fallback only covers ECDSA, not ${name}`);
  }
  const hashValue = typeof algorithm === "string" ? undefined : (algorithm as EcdsaParams).hash;
  const hashName = typeof hashValue === "string" ? hashValue : hashValue?.name;
  if (hashName !== "SHA-256" && hashName !== "SHA-384") {
    throw new EcdsaVerifyError(`fallback only covers SHA-256/SHA-384, not ${hashName}`);
  }
  const keyAlgorithm = key.algorithm as EcKeyAlgorithm;
  const curve = KNOWN_CURVES.find((candidate) => candidate.name === keyAlgorithm.namedCurve);
  if (curve === undefined) {
    throw new EcdsaVerifyError(
      `fallback only covers P-256/P-384 keys, not ${keyAlgorithm.namedCurve}`,
    );
  }
  return { hash: hashName, curve: curve.name, coordinateBytes: curve.coordinateBytes };
}

async function verifyEcdsaFromCryptoKey(
  subtle: SubtleCrypto,
  algorithm: AlgorithmIdentifier | EcdsaParams,
  key: CryptoKey,
  signature: BufferSource,
  data: BufferSource,
): Promise<boolean> {
  const normalized = normalizeEcdsaAlgorithm(algorithm, key);
  const signatureBytes = signature instanceof Uint8Array ? signature : new Uint8Array(
    signature instanceof ArrayBuffer ? signature : signature.buffer.slice(
      signature.byteOffset,
      signature.byteOffset + signature.byteLength,
    ),
  );
  const messageBytes = data instanceof Uint8Array ? data : new Uint8Array(
    data instanceof ArrayBuffer ? data : data.buffer.slice(
      data.byteOffset,
      data.byteOffset + data.byteLength,
    ),
  );

  // The raw point needs an extractable key; every public key this codebase
  // imports is extractable, and if a caller ever breaks that rule the original
  // WebCrypto error is more truthful than a fallback failure.
  const pointBytes = new Uint8Array(await subtle.exportKey("raw", key));
  if (pointBytes.length !== 1 + 2 * normalized.coordinateBytes || pointBytes[0] !== 0x04) {
    throw new EcdsaVerifyError("fallback key is not an uncompressed point");
  }
  const curve = KNOWN_CURVES.find((candidate) => candidate.name === normalized.curve)!;
  const point: EcPublicPoint = {
    curve,
    x: bytesToBigint(pointBytes.subarray(1, 1 + normalized.coordinateBytes)),
    y: bytesToBigint(pointBytes.subarray(1 + normalized.coordinateBytes)),
  };

  // Callers pass either the raw P1363 form (r || s) or the ASN.1 DER form.
  let parsed: EcdsaSignature;
  if (signatureBytes.length === 2 * normalized.coordinateBytes) {
    parsed = {
      r: bytesToBigint(signatureBytes.subarray(0, normalized.coordinateBytes)),
      s: bytesToBigint(signatureBytes.subarray(normalized.coordinateBytes)),
    };
  } else {
    parsed = parseEcdsaSignatureDer(signatureBytes);
  }
  return await verifyEcdsa({
    point,
    hash: normalized.hash,
    signature: parsed,
    message: messageBytes,
  });
}

/**
 * A SubtleCrypto whose `verify` delegates to WebCrypto and falls back to the
 * pure implementation for the (curve, digest) pairs the hosted Edge Runtime
 * does not implement. Every other method and every genuine failure passes
 * through untouched.
 */
export function subtleWithEcdsaFallback(subtle: SubtleCrypto): SubtleCrypto {
  return new Proxy(subtle, {
    get(target, property, receiver) {
      if (property !== "verify") {
        const value = Reflect.get(target, property, receiver);
        return typeof value === "function" ? value.bind(target) : value;
      }
      return (
        algorithm: AlgorithmIdentifier | EcdsaParams,
        key: CryptoKey,
        signature: BufferSource,
        data: BufferSource,
      ): Promise<boolean> =>
        target.verify(algorithm, key, signature, data).catch((cause) => {
          if (!isUnsupportedSubtleError(cause)) throw cause;
          return verifyEcdsaFromCryptoKey(target, algorithm, key, signature, data);
        });
    },
  });
}
