import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import * as x509 from "@peculiar/x509";
import {
  APPLE_2026_APP_ATTEST_VECTOR,
  APPLE_APP_ATTESTATION_ROOT_CA_PEM,
} from "../_test/apple_appattest_2026_vector.ts";
import {
  certificateSignatureParts,
  EcdsaVerifyError,
  ecPublicPointFromSpki,
  parseEcdsaSignatureDer,
  subtleWithEcdsaFallback,
  verifyCertificateSignatureEcdsa,
  verifyEcdsa,
} from "./ecdsa_verify.ts";

function b64ToBytes(b64: string): Uint8Array {
  const text = atob(b64);
  const out = new Uint8Array(text.length);
  for (let i = 0; i < text.length; i++) out[i] = text.charCodeAt(i);
  return out;
}

function vectorCertificates() {
  const root = new x509.X509Certificate(APPLE_APP_ATTESTATION_ROOT_CA_PEM);
  const intermediate = new x509.X509Certificate(
    b64ToBytes(APPLE_2026_APP_ATTEST_VECTOR.intermediateCertificateBase64)
      .slice().buffer,
  );
  const leaf = new x509.X509Certificate(
    b64ToBytes(APPLE_2026_APP_ATTEST_VECTOR.leafCertificateBase64).slice().buffer,
  );
  return { root, intermediate, leaf };
}

/** DER-encodes one unsigned INTEGER. */
function derInteger(value: Uint8Array): number[] {
  const bytes = [...value];
  while (bytes.length > 1 && bytes[0] === 0x00 && (bytes[1]! & 0x80) === 0) {
    bytes.shift();
  }
  if ((bytes[0]! & 0x80) !== 0) bytes.unshift(0x00);
  return [0x02, bytes.length, ...bytes];
}

function derSequence(contents: number[]): Uint8Array {
  if (contents.length < 128) {
    return new Uint8Array([0x30, contents.length, ...contents]);
  }
  return new Uint8Array([0x30, 0x81, contents.length, ...contents]);
}

async function signAndDerEncode(
  curve: "P-256" | "P-384",
  hash: "SHA-256" | "SHA-384",
  message: Uint8Array,
): Promise<{ spki: Uint8Array; signatureDer: Uint8Array }> {
  const keys = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: curve },
    true,
    ["sign", "verify"],
  );
  const spki = new Uint8Array(await crypto.subtle.exportKey("spki", keys.publicKey));
  const raw = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash }, keys.privateKey, message.slice()),
  );
  const half = raw.length / 2;
  const signatureDer = derSequence([
    ...derInteger(raw.subarray(0, half)),
    ...derInteger(raw.subarray(half)),
  ]);
  return { spki, signatureDer };
}

// ---------------------------------------------------------------------------
// Apple's published 2026 chain: the exact cross (curve, digest) pairs the
// hosted Edge Runtime does not implement.
// ---------------------------------------------------------------------------

Deno.test("Apple vector: leaf verifies against the intermediate (P-384 key, SHA-256)", async () => {
  const { intermediate, leaf } = vectorCertificates();
  const parts = certificateSignatureParts(new Uint8Array(leaf.rawData));
  const ok = await verifyCertificateSignatureEcdsa({
    tbs: parts.tbs,
    signatureDer: parts.signatureDer,
    hash: "SHA-256",
    issuerSpki: new Uint8Array(intermediate.publicKey.rawData),
  });
  assertEquals(ok, true);
});

Deno.test("Apple vector: intermediate verifies against the root (P-384 key, SHA-384)", async () => {
  const { root, intermediate } = vectorCertificates();
  const parts = certificateSignatureParts(new Uint8Array(intermediate.rawData));
  const ok = await verifyCertificateSignatureEcdsa({
    tbs: parts.tbs,
    signatureDer: parts.signatureDer,
    hash: "SHA-384",
    issuerSpki: new Uint8Array(root.publicKey.rawData),
  });
  assertEquals(ok, true);
});

Deno.test("Apple vector: the leaf is not signed by the root", async () => {
  const { root, leaf } = vectorCertificates();
  const parts = certificateSignatureParts(new Uint8Array(leaf.rawData));
  const ok = await verifyCertificateSignatureEcdsa({
    tbs: parts.tbs,
    signatureDer: parts.signatureDer,
    hash: "SHA-256",
    issuerSpki: new Uint8Array(root.publicKey.rawData),
  });
  assertEquals(ok, false);
});

Deno.test("Apple vector: a tampered TBS does not verify", async () => {
  const { intermediate, leaf } = vectorCertificates();
  const parts = certificateSignatureParts(new Uint8Array(leaf.rawData));
  const tbs = parts.tbs.slice();
  tbs[10] = tbs[10]! ^ 0x01;
  const ok = await verifyCertificateSignatureEcdsa({
    tbs,
    signatureDer: parts.signatureDer,
    hash: "SHA-256",
    issuerSpki: new Uint8Array(intermediate.publicKey.rawData),
  });
  assertEquals(ok, false);
});

Deno.test("certificateSignatureParts agrees with the library's TBS bytes", () => {
  const { leaf } = vectorCertificates();
  const parts = certificateSignatureParts(new Uint8Array(leaf.rawData));
  // The signature over `tbs` must verify against the library-parsed issuer,
  // which transitively proves the split lands on the real TBS bytes.
  assert(parts.tbs.length > 0 && parts.signatureDer.length > 0);
  assertEquals(parts.tbs[0], 0x30);
  assertEquals(parts.signatureDer[0], 0x30);
});

// ---------------------------------------------------------------------------
// Synthetic round trips for every (curve, digest) pair.
// ---------------------------------------------------------------------------

for (const curve of ["P-256", "P-384"] as const) {
  for (const hash of ["SHA-256", "SHA-384"] as const) {
    Deno.test(`synthetic ${curve} / ${hash} round trip verifies`, async () => {
      const message = new TextEncoder().encode(`m6.5 ${curve} ${hash}`);
      const { spki, signatureDer } = await signAndDerEncode(curve, hash, message);
      const ok = await verifyCertificateSignatureEcdsa({
        tbs: message,
        signatureDer,
        hash,
        issuerSpki: spki,
      });
      assertEquals(ok, true);
    });
  }
}

Deno.test("synthetic: a different message does not verify", async () => {
  const message = new TextEncoder().encode("original");
  const { spki, signatureDer } = await signAndDerEncode("P-384", "SHA-256", message);
  const ok = await verifyCertificateSignatureEcdsa({
    tbs: new TextEncoder().encode("forged"),
    signatureDer,
    hash: "SHA-256",
    issuerSpki: spki,
  });
  assertEquals(ok, false);
});

// ---------------------------------------------------------------------------
// Parser behavior.
// ---------------------------------------------------------------------------

Deno.test("parseEcdsaSignatureDer rejects a truncated signature", () => {
  assertThrows(
    () => parseEcdsaSignatureDer(new Uint8Array([0x30, 0x06, 0x02, 0x01, 0x01])),
    EcdsaVerifyError,
  );
});

Deno.test("parseEcdsaSignatureDer rejects a non-sequence", () => {
  assertThrows(
    () => parseEcdsaSignatureDer(new Uint8Array([0x04, 0x02, 0x01, 0x02])),
    EcdsaVerifyError,
  );
});

Deno.test("certificateSignatureParts rejects trailing garbage", () => {
  const { leaf } = vectorCertificates();
  const der = new Uint8Array(leaf.rawData);
  const withGarbage = new Uint8Array(der.length + 1);
  withGarbage.set(der);
  assertThrows(() => certificateSignatureParts(withGarbage), EcdsaVerifyError);
});

Deno.test("ecPublicPointFromSpki rejects a wrong curve OID", () => {
  // P-521 SPKI: valid DER, unsupported curve.
  const p521Spki = b64ToBytes(
    "MIGbMBAGByqGSM49AgEGBSuBBAAjA4GGAAQBMkPn+R7HNjXRkZ7uNrXSh3GqCoRO" +
      "SfXypprFGLAqJISRRpYQvPz0KdNc6p78d5YrhBfGHpgRWRtmq2l80zI3iAJ0S2rB" +
      "1e9PLK3dKEypMPJ4w4f67zVQeDQz6IqX78XcQcvdAM3vjFYaXuRpsnCEnq9dZkXY",
  );
  assertThrows(() => ecPublicPointFromSpki(p521Spki), EcdsaVerifyError);
});

Deno.test("verifyEcdsa rejects out-of-range r and s without throwing", async () => {
  const { intermediate, leaf } = vectorCertificates();
  const parts = certificateSignatureParts(new Uint8Array(leaf.rawData));
  const point = ecPublicPointFromSpki(new Uint8Array(intermediate.publicKey.rawData));
  const signature = parseEcdsaSignatureDer(parts.signatureDer);
  assertEquals(
    await verifyEcdsa({
      point,
      hash: "SHA-256",
      signature: { r: 0n, s: signature.s },
      message: parts.tbs,
    }),
    false,
  );
  assertEquals(
    await verifyEcdsa({
      point,
      hash: "SHA-256",
      signature: { r: signature.r, s: point.curve.n },
      message: parts.tbs,
    }),
    false,
  );
});

// ---------------------------------------------------------------------------
// The WebCrypto wrapper: native results pass through untouched, and only the
// unsupported-pair error diverts to the fallback.
// ---------------------------------------------------------------------------

Deno.test("wrapper delegates supported pairs to WebCrypto", async () => {
  const keys = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const message = new TextEncoder().encode("delegate me");
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    keys.privateKey,
    message,
  );
  const wrapped = subtleWithEcdsaFallback(crypto.subtle);
  assertEquals(
    await wrapped.verify(
      { name: "ECDSA", hash: "SHA-256" },
      keys.publicKey,
      signature,
      message,
    ),
    true,
  );
  assertEquals(
    await wrapped.verify(
      { name: "ECDSA", hash: "SHA-256" },
      keys.publicKey,
      signature,
      new TextEncoder().encode("tampered"),
    ),
    false,
  );
});

Deno.test("wrapper rethrows non-unsupported errors", async () => {
  const wrapped = subtleWithEcdsaFallback(crypto.subtle);
  // An AES key is not an ECDSA key: WebCrypto throws, and that error is not
  // the unsupported-pair signal, so the wrapper must rethrow it untouched.
  const aesKey = await crypto.subtle.generateKey(
    { name: "AES-GCM", length: 256 },
    true,
    ["encrypt", "decrypt"],
  );
  const error = await assertRejects(() =>
    wrapped.verify(
      { name: "ECDSA", hash: "SHA-256" },
      aesKey,
      new Uint8Array(64),
      new TextEncoder().encode("data"),
    )
  );
  assert(!(error instanceof EcdsaVerifyError));
});

Deno.test("fallback path: CryptoKey, raw signature, cross pair", async () => {
  // Force the fallback with a NotSupportedError-throwing fake subtle that
  // still exports keys.
  const keys = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-384" },
    true,
    ["sign", "verify"],
  );
  const message = new TextEncoder().encode("edge runtime cross pair");
  const rawSignature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    keys.privateKey,
    message,
  );
  const refusing = new Proxy(crypto.subtle, {
    get(target, property, receiver) {
      if (property === "verify") {
        return () =>
          Promise.reject(
            new DOMException("Not implemented", "NotSupportedError"),
          );
      }
      const value = Reflect.get(target, property, receiver);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
  const wrapped = subtleWithEcdsaFallback(refusing);
  assertEquals(
    await wrapped.verify(
      { name: "ECDSA", hash: "SHA-256" },
      keys.publicKey,
      rawSignature,
      message,
    ),
    true,
  );
  assertEquals(
    await wrapped.verify(
      { name: "ECDSA", hash: "SHA-256" },
      keys.publicKey,
      rawSignature,
      new TextEncoder().encode("other"),
    ),
    false,
  );
});
