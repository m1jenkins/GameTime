import * as x509 from "@peculiar/x509";
import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import {
  AttestationError,
  base64ToBytes,
  derToRawEcdsaSignature,
  environmentFromAaguid,
  nonceFromExtension,
  parseAuthenticatorData,
  rawToDerEcdsaSignature,
  verifyAssertion,
  verifyAttestation,
} from "./appattest.ts";
import { type Bytes, utf8 } from "./bytes.ts";
import {
  asCborBytes,
  asCborBytesArray,
  asCborMap,
  asCborText,
  decodeCbor,
  encodeCbor,
} from "./cbor.ts";
import {
  AAGUID_DEVELOPMENT,
  AAGUID_PRODUCTION,
  type Authority,
  buildAssertion,
  buildAttestation,
  buildAuthenticatorData,
  type Device,
  encodeCosePublicKey,
  makeDevice,
  makeIntermediate,
  makeRoot,
} from "../_test/appattest_fixtures.ts";
import {
  APPLE_2026_APP_ATTEST_VECTOR,
  APPLE_APP_ATTESTATION_ROOT_CA_PEM,
} from "../_test/apple_appattest_2026_vector.ts";

const APP_ID = "ABCDE12345.test.gametime.app";

// One chain for the whole file. Generating P-256 keys and signing certificates
// is the slow part, and every test here wants the same valid baseline to
// perturb one thing at a time.
const root: Authority = await makeRoot();
const intermediate: Authority = await makeIntermediate(root);
const device: Device = await makeDevice();

/** Pulls an attestation object apart the way the handler does. */
function openAttestation(attestationObject: Bytes) {
  const outer = asCborMap(decodeCbor(attestationObject), "attestation object");
  const statement = asCborMap(outer["attStmt"], "attStmt");
  return {
    fmt: asCborText(outer["fmt"], "fmt"),
    authenticatorData: asCborBytes(outer["authData"], "authData"),
    x5c: asCborBytesArray(statement["x5c"], "x5c"),
  };
}

function attestationRequest(
  built: Awaited<ReturnType<typeof buildAttestation>>,
  overrides: Partial<Parameters<typeof verifyAttestation>[0]> = {},
) {
  return {
    ...openAttestation(built.attestationObject),
    keyId: built.keyId,
    clientData: built.clientData,
    appId: APP_ID,
    rootCertificatePem: root.pem,
    allowedEnvironments: ["production"] as const,
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// Authenticator data
// ---------------------------------------------------------------------------
Deno.test("parses assertion-shaped authenticator data", () => {
  const bytes = buildAuthenticatorData({
    rpIdHash: new Uint8Array(32).fill(7),
    signCount: 66051,
  });
  const parsed = parseAuthenticatorData(bytes);
  assertEquals(parsed.signCount, 66051, "the counter is big endian");
  assertEquals(parsed.aaguid, undefined);
  assertEquals(parsed.credentialId, undefined);
});

Deno.test("parses attestation-shaped authenticator data", () => {
  const credentialId = new Uint8Array(32).fill(3);
  const parsed = parseAuthenticatorData(buildAuthenticatorData({
    rpIdHash: new Uint8Array(32).fill(7),
    signCount: 0,
    aaguid: AAGUID_PRODUCTION,
    credentialId,
    credentialPublicKey: device.publicKey,
    validationCategory: 4,
    bundleVersion: "27.3.14",
  }));
  assertEquals(parsed.aaguid, AAGUID_PRODUCTION);
  assertEquals(parsed.credentialId, credentialId);
  assertEquals(parsed.credentialPublicKey, device.publicKey);
  assertEquals(parsed.validationCategory, 4);
  assertEquals(parsed.bundleVersion, "27.3.14");
});

Deno.test("parses the legacy attestation form that ends after credentialId", () => {
  const credentialId = new Uint8Array(32).fill(3);
  const legacy = buildAuthenticatorData({
    rpIdHash: new Uint8Array(32).fill(7),
    signCount: 0,
    aaguid: AAGUID_PRODUCTION,
    credentialId,
  });
  const parsed = parseAuthenticatorData(legacy);

  assertEquals(parsed.aaguid, AAGUID_PRODUCTION);
  assertEquals(parsed.credentialId, credentialId);
  assertEquals(parsed.credentialPublicKey, undefined);
  assertEquals(parsed.validationCategory, undefined);
  assertEquals(parsed.bundleVersion, undefined);

  // Compatibility is exact, not a license to ignore trailing data. Once even
  // one suffix byte is present, the complete two-value iOS 27 form is required.
  assertThrows(
    () => parseAuthenticatorData(new Uint8Array([...legacy, 0x00])),
    AttestationError,
    "a COSE key and extensions map are required",
  );
});

Deno.test("refuses authenticator data that is short or has trailing bytes", () => {
  assertThrows(
    () => parseAuthenticatorData(new Uint8Array(36)),
    AttestationError,
    "at least 37",
  );

  // The 2026 conformance change is attestation-only: without a published Apple
  // assertion vector, a 37-byte assertion plus any suffix remains a refusal.
  // Trailing bytes inside a signed structure are a place for two
  // implementations to disagree about what was signed.
  assertThrows(
    () => parseAuthenticatorData(new Uint8Array(38)),
    AttestationError,
    "carries no credential data",
  );

  const valid = buildAuthenticatorData({
    rpIdHash: new Uint8Array(32),
    signCount: 0,
    aaguid: AAGUID_PRODUCTION,
    credentialId: new Uint8Array(32),
    credentialPublicKey: device.publicKey,
  });
  assertThrows(
    () => parseAuthenticatorData(new Uint8Array([...valid, 0x00])),
    AttestationError,
    "CBOR values",
  );
});

Deno.test("maps AAGUIDs onto environments and refuses anything else", () => {
  assertEquals(environmentFromAaguid(AAGUID_PRODUCTION), "production");
  assertEquals(environmentFromAaguid(AAGUID_DEVELOPMENT), "development");
  assertThrows(
    () => environmentFromAaguid(new Uint8Array(16).fill(1)),
    AttestationError,
    "unrecognised AAGUID",
  );
});

Deno.test("Apple's official 2026 vector pins the current attestation suffix and root", async () => {
  const vector = APPLE_2026_APP_ATTEST_VECTOR;
  const authenticatorData = base64ToBytes(vector.authDataBase64, "official authData");
  const keyId = base64ToBytes(vector.keyIdBase64, "official key id");
  const x5c = [
    base64ToBytes(vector.leafCertificateBase64, "official leaf"),
    base64ToBytes(vector.intermediateCertificateBase64, "official intermediate"),
  ];

  const parsed = parseAuthenticatorData(authenticatorData);
  assertEquals(parsed.flags, 0x40);
  assertEquals(parsed.signCount, 0);
  assertEquals(parsed.aaguid, AAGUID_PRODUCTION);
  assertEquals(parsed.credentialId, keyId);
  assertEquals(parsed.validationCategory, 1);
  assertEquals(parsed.bundleVersion, "1");
  assertEquals(parsed.credentialPublicKey?.length, 65);
  assertEquals(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", parsed.credentialPublicKey!),
    ),
    keyId,
  );

  const leaf = new x509.X509Certificate(x5c[0]!);
  const nonceExtension = leaf.getExtension("1.2.840.113635.100.8.2");
  if (nonceExtension === null) throw new Error("official leaf has no nonce extension");
  assertEquals(
    nonceFromExtension(new Uint8Array(nonceExtension.value)),
    base64ToBytes(vector.nonceBase64, "official nonce"),
  );

  // The published object is internally inconsistent: its certificate nonce is
  // SHA256(authData || UTF8(serverChallenge)), while Apple's prose and the
  // production verifier correctly require
  // SHA256(authData || SHA256(serverChallenge)). The guide also prints a public
  // key digest that differs from both its key id and certificate. Reaching the
  // nonce mismatch proves the official chain rooted at Apple's public App
  // Attestation root, RP ID, COSE/certificate key, and key-id digest all passed
  // without weakening the production nonce construction.
  await assertRejects(
    () =>
      verifyAttestation({
        fmt: "apple-appattest",
        x5c,
        authenticatorData,
        keyId,
        clientData: utf8(vector.serverChallenge),
        appId: vector.appId,
        rootCertificatePem: APPLE_APP_ATTESTATION_ROOT_CA_PEM,
        allowedEnvironments: ["production"],
        allowedValidationCategories: [1],
        allowedBundleVersions: ["1"],
        at: vector.at,
      }),
    AttestationError,
    "nonce in the leaf certificate does not match",
  );
});

Deno.test("strictly validates the COSE key and both Apple extensions", async () => {
  const built = await buildAttestation(root, intermediate, device);
  const coseStart = 55 + built.keyId.length;

  const wrongAlgorithm = new Uint8Array(built.authenticatorData);
  wrongAlgorithm[coseStart + 4] = 0x25; // -6 instead of ES256's -7
  assertThrows(
    () => parseAuthenticatorData(wrongAlgorithm),
    AttestationError,
    "does not use ES256",
  );

  const noExtensions = buildAuthenticatorData({
    rpIdHash: new Uint8Array(32),
    signCount: 0,
    aaguid: AAGUID_PRODUCTION,
    credentialId: device.keyId,
    attestationSuffix: encodeCosePublicKey(device.publicKey),
  });
  assertThrows(
    () => parseAuthenticatorData(noExtensions),
    AttestationError,
    "a COSE key and extensions map are required",
  );

  const invalidCategory = await buildAttestation(root, intermediate, device, {
    validationCategory: 7,
  });
  assertThrows(
    () => parseAuthenticatorData(invalidCategory.authenticatorData),
    AttestationError,
    "is not an app category",
  );

  const invalidBundle = await buildAttestation(root, intermediate, device, {
    bundleVersion: "1-beta",
  });
  assertThrows(
    () => parseAuthenticatorData(invalidBundle.authenticatorData),
    AttestationError,
    "not a valid bundle version",
  );
});

// ---------------------------------------------------------------------------
// Signature encoding
// ---------------------------------------------------------------------------
// Apple emits DER and Web Crypto wants r||s, so this conversion sits directly
// under every assertion check. A bug here would look like "no assertion ever
// verifies", which is at least loud, but the malformed-input cases are the ones
// worth pinning: a signature is not a place to be forgiving.
Deno.test("DER and raw ECDSA signatures round-trip, including padded scalars", async () => {
  // Real signatures, so the high-bit and leading-zero cases show up naturally
  // across enough draws.
  for (let i = 0; i < 40; i++) {
    const raw = new Uint8Array(
      await crypto.subtle.sign(
        { name: "ECDSA", hash: { name: "SHA-256" } },
        device.keys.privateKey,
        utf8(`message-${i}`),
      ),
    );
    assertEquals(derToRawEcdsaSignature(rawToDerEcdsaSignature(raw)), raw);
  }
});

Deno.test("converts a DER signature whose scalars need left-padding", () => {
  // r is one byte, s is 32 with the high bit set (so DER pads it to 33).
  const der = new Uint8Array([
    0x30,
    0x26,
    0x02,
    0x01,
    0x05,
    0x02,
    0x21,
    0x00,
    ...new Uint8Array(32).fill(0xff),
  ]);
  const raw = derToRawEcdsaSignature(der);
  assertEquals(raw.length, 64);
  assertEquals(raw[31], 0x05, "a short r is left-padded, not left-aligned");
  assertEquals(raw.slice(0, 31), new Uint8Array(31), "and zero-filled ahead of it");
  assertEquals(raw.slice(32), new Uint8Array(32).fill(0xff));
});

Deno.test("refuses malformed DER signatures", () => {
  const cases: [Bytes, string][] = [
    [new Uint8Array([0x31, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x01]), "SEQUENCE tag"],
    [new Uint8Array([0x30, 0x81, 0x06]), "long-form"],
    [new Uint8Array([0x30, 0x06, 0x02, 0x01, 0x01]), "does not match"],
    [new Uint8Array([0x30, 0x06, 0x03, 0x01, 0x01, 0x02, 0x01, 0x01]), "INTEGER tag"],
    [new Uint8Array([0x30, 0x04, 0x02, 0x01, 0x00, 0x00]), "zero-valued"],
    // Two leading zero bytes: non-minimal, which DER forbids.
    [
      new Uint8Array([0x30, 0x08, 0x02, 0x03, 0x00, 0x00, 0x01, 0x02, 0x01, 0x01]),
      "non-minimal",
    ],
    // High bit set with no sign byte: a negative INTEGER, not a coordinate.
    [new Uint8Array([0x30, 0x06, 0x02, 0x01, 0x80, 0x02, 0x01, 0x01]), "negative"],
    // A 34-byte scalar cannot be a P-256 coordinate.
    [
      new Uint8Array([
        0x30,
        0x26,
        0x02,
        0x22,
        0x00,
        ...new Uint8Array(33).fill(0xff),
        0x02,
        0x01,
        0x01,
      ]),
      "not DER",
    ],
  ];
  for (const [der, message] of cases) {
    assertThrows(() => derToRawEcdsaSignature(der), AttestationError, message);
  }
});

Deno.test("refuses a raw signature that is not 64 bytes", () => {
  assertThrows(
    () => rawToDerEcdsaSignature(new Uint8Array(63)),
    AttestationError,
    "64 bytes",
  );
});

Deno.test("extracts the nonce octet string from strict DER", () => {
  const nonce = new Uint8Array(32).fill(0x5a);
  const extension = new Uint8Array([
    0x30,
    0x24,
    0xa1,
    0x22,
    0x04,
    0x20,
    ...nonce,
  ]);
  assertEquals(nonceFromExtension(extension), nonce);

  const wrongTag = new Uint8Array(extension);
  wrongTag[2] = 0xa2;
  assertThrows(() => nonceFromExtension(wrongTag), AttestationError, "context-specific [1]");

  const nonMinimalLength = new Uint8Array([
    0x30,
    0x81,
    0x24,
    ...extension.slice(2),
  ]);
  assertThrows(() => nonceFromExtension(nonMinimalLength), AttestationError, "non-minimal");

  assertThrows(
    () => nonceFromExtension(new Uint8Array([...extension, 0x00])),
    AttestationError,
    "does not account",
  );
});

// ---------------------------------------------------------------------------
// Attestation: the happy path
// ---------------------------------------------------------------------------
Deno.test("verifies a well-formed attestation and yields the key to store", async () => {
  const built = await buildAttestation(root, intermediate, device);
  const verified = await verifyAttestation(attestationRequest(built));

  assertEquals(verified.environment, "production");
  assertEquals(verified.validationCategory, 4);
  assertEquals(verified.bundleVersion, "1");
  assertEquals(verified.publicKey, device.publicKey);
  assertEquals(verified.publicKey.length, 65);
  assertEquals(verified.publicKey[0], 0x04, "an uncompressed point, as the schema requires");

  // The key id must be the digest of what we return, because the database holds
  // that same relation as a CHECK and the insert would fail otherwise.
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", verified.publicKey));
  assertEquals(digest, built.keyId);
});

Deno.test("verifies a legacy attestation without iOS 27 app signals", async () => {
  const built = await buildAttestation(root, intermediate, device, {
    legacyAuthenticatorData: true,
  });
  const verified = await verifyAttestation(attestationRequest(built));

  assertEquals(verified.publicKey, device.publicKey);
  assertEquals(verified.environment, "production");
  assertEquals(verified.validationCategory, undefined);
  assertEquals(verified.bundleVersion, undefined);
});

Deno.test("accepts a development attestation only where it is allowed", async () => {
  const built = await buildAttestation(root, intermediate, device, {
    aaguid: AAGUID_DEVELOPMENT,
  });

  const verified = await verifyAttestation(attestationRequest(built, {
    allowedEnvironments: ["development", "production"],
  }));
  assertEquals(verified.environment, "development");

  // A debug build on a device the attacker controls produces one of these, so a
  // deployment that only trusts production attestations has to refuse it.
  await assertRejects(
    () => verifyAttestation(attestationRequest(built)),
    AttestationError,
    "a development attestation is not accepted",
  );
});

Deno.test("applies deployment policy to validation category and bundle version", async () => {
  const built = await buildAttestation(root, intermediate, device, {
    validationCategory: 2,
    bundleVersion: "42.7",
  });

  const verified = await verifyAttestation(attestationRequest(built, {
    allowedValidationCategories: [2, 4],
    allowedBundleVersions: ["42.7", "42.8"],
  }));
  assertEquals(verified.validationCategory, 2);
  assertEquals(verified.bundleVersion, "42.7");

  await assertRejects(
    () =>
      verifyAttestation(attestationRequest(built, {
        allowedValidationCategories: [4],
      })),
    AttestationError,
    "validation category 2 is not accepted",
  );
  await assertRejects(
    () =>
      verifyAttestation(attestationRequest(built, {
        allowedBundleVersions: ["42.8"],
      })),
    AttestationError,
    'bundle version "42.7" is not accepted',
  );

  const legacy = await buildAttestation(root, intermediate, device, {
    legacyAuthenticatorData: true,
  });
  await assertRejects(
    () =>
      verifyAttestation(attestationRequest(legacy, {
        allowedValidationCategories: [4],
      })),
    AttestationError,
    "requires an Apple validation category",
  );
  await assertRejects(
    () =>
      verifyAttestation(attestationRequest(legacy, {
        allowedBundleVersions: ["1"],
      })),
    AttestationError,
    "requires an Apple bundle version",
  );
});

// ---------------------------------------------------------------------------
// Attestation: every rejection path
// ---------------------------------------------------------------------------
Deno.test("refuses an attestation whose chain does not reach the configured root", async () => {
  const built = await buildAttestation(root, intermediate, device);
  const otherRoot = await makeRoot("CN=Someone Else's Root");

  // Caught by the issuer-name comparison, which runs before the signature
  // check and is the cheaper of the two ways this chain fails.
  await assertRejects(
    () => verifyAttestation(attestationRequest(built, { rootCertificatePem: otherRoot.pem })),
    AttestationError,
    "which is not",
  );
});

Deno.test("refuses a leaf signed by an authority outside the chain", async () => {
  // A self-signed leaf: the shape an attacker produces when they generate their
  // own key and want the server to store it.
  const rogue = await makeRoot("CN=Test App Attest CA 1");
  const built = await buildAttestation(root, intermediate, device, {
    leafIssuer: rogue,
  });

  await assertRejects(
    () => verifyAttestation(attestationRequest(built)),
    AttestationError,
    "is not signed by",
  );
});

Deno.test("refuses a chain whose issuer names do not link up", async () => {
  const built = await buildAttestation(root, intermediate, device);
  const unrelated = await makeIntermediate(root, "CN=Unrelated Intermediate");

  await assertRejects(
    () =>
      verifyAttestation(attestationRequest(built, {
        x5c: [built.x5c[0]!, new Uint8Array(unrelated.certificate.rawData)],
      })),
    AttestationError,
    "which is not",
  );
});

Deno.test("refuses an empty, oversized, or malformed certificate list", async () => {
  const built = await buildAttestation(root, intermediate, device);

  await assertRejects(
    () => verifyAttestation(attestationRequest(built, { x5c: [] })),
    AttestationError,
    "no certificates",
  );

  await assertRejects(
    () =>
      verifyAttestation(attestationRequest(built, {
        x5c: Array(5).fill(built.x5c[0]!),
      })),
    AttestationError,
    "at most 4",
  );

  await assertRejects(
    () =>
      verifyAttestation(attestationRequest(built, {
        x5c: [new Uint8Array([1, 2, 3])],
      })),
    AttestationError,
    "not valid DER",
  );
});

Deno.test("refuses an attestation for a different app id", async () => {
  const built = await buildAttestation(root, intermediate, device, {
    appId: "ZZZZZ99999.someone.elses.app",
  });

  await assertRejects(
    () => verifyAttestation(attestationRequest(built)),
    AttestationError,
    "different app id",
  );
});

Deno.test("refuses an attestation whose nonce does not match the challenge", async () => {
  // The replay case: a captured attestation object presented against a
  // different challenge. Without the nonce check, anyone who saw one once
  // could register that key again.
  const built = await buildAttestation(root, intermediate, device);

  await assertRejects(
    () =>
      verifyAttestation(attestationRequest(built, {
        clientData: utf8("a-different-challenge"),
      })),
    AttestationError,
    "does not match this challenge",
  );
});

Deno.test("refuses an attestation whose leaf carries a forged nonce", async () => {
  const built = await buildAttestation(root, intermediate, device, {
    nonceOverride: new Uint8Array(32).fill(0xab),
  });

  await assertRejects(
    () => verifyAttestation(attestationRequest(built)),
    AttestationError,
    "does not match this challenge",
  );
});

Deno.test("refuses an attestation whose leaf has no nonce extension at all", async () => {
  const built = await buildAttestation(root, intermediate, device, {
    omitNonceExtension: true,
  });

  await assertRejects(
    () => verifyAttestation(attestationRequest(built)),
    AttestationError,
    "no Apple attestation nonce extension",
  );
});

Deno.test("refuses an attestation whose key id is not the digest of the attested key", async () => {
  // The substitution attack the CHECK in the schema also guards: a genuine
  // Apple chain, with the client naming a key id belonging to some other key.
  const built = await buildAttestation(root, intermediate, device);
  const other = await makeDevice();

  await assertRejects(
    () => verifyAttestation(attestationRequest(built, { keyId: other.keyId })),
    AttestationError,
    // Caught at the authenticator-data comparison, which comes first.
    "not the one the client claims",
  );
});

Deno.test("refuses an attestation whose certificate holds a different key than the key id", async () => {
  // The same substitution one step deeper: the authenticator data agrees with
  // the claimed key id, but the certificate attests to a different key. The
  // signed COSE/certificate comparison catches it before the digest check.
  const other = await makeDevice();
  const built = await buildAttestation(root, intermediate, device, {
    certificateKey: other.keys.publicKey,
  });

  await assertRejects(
    () => verifyAttestation(attestationRequest(built)),
    AttestationError,
    "COSE credential public key does not match",
  );
});

Deno.test("refuses an attestation with a non-zero counter", async () => {
  const built = await buildAttestation(root, intermediate, device, { signCount: 3 });

  await assertRejects(
    () => verifyAttestation(attestationRequest(built)),
    AttestationError,
    "counter must be 0",
  );
});

Deno.test("refuses an attestation carrying no credential data", async () => {
  const built = await buildAttestation(root, intermediate, device);
  const assertionShaped = buildAuthenticatorData({
    rpIdHash: new Uint8Array(
      await crypto.subtle.digest("SHA-256", utf8(APP_ID)),
    ),
    signCount: 0,
  });

  await assertRejects(
    () =>
      verifyAttestation(attestationRequest(built, {
        authenticatorData: assertionShaped,
      })),
    AttestationError,
    "must carry credential data",
  );
});

Deno.test("refuses the wrong format, a bad key id length, and an unreadable root", async () => {
  const built = await buildAttestation(root, intermediate, device);

  await assertRejects(
    () => verifyAttestation(attestationRequest(built, { fmt: "packed" })),
    AttestationError,
    "apple-appattest",
  );

  await assertRejects(
    () => verifyAttestation(attestationRequest(built, { keyId: new Uint8Array(16) })),
    AttestationError,
    "32-byte digest",
  );

  await assertRejects(
    () =>
      verifyAttestation(attestationRequest(built, {
        rootCertificatePem: "not a certificate",
      })),
    AttestationError,
    "root is unreadable",
  );
});

Deno.test("refuses a chain that has expired", async () => {
  const built = await buildAttestation(root, intermediate, device);

  await assertRejects(
    () =>
      verifyAttestation(attestationRequest(built, {
        at: new Date("2050-01-01T00:00:00Z"),
      })),
    AttestationError,
    "outside its validity window",
  );
});

// ---------------------------------------------------------------------------
// Assertion
// ---------------------------------------------------------------------------
Deno.test("verifies an assertion over the exact payload and reports its counter", async () => {
  const payload = utf8('{"clientBatchId":"abc","observations":[]}');
  const built = await buildAssertion(device, payload, { signCount: 42 });

  const decoded = asCborMap(decodeCbor(built.assertionObject), "assertion");
  const verified = await verifyAssertion({
    signature: asCborBytes(decoded["signature"], "signature"),
    authenticatorData: asCborBytes(decoded["authenticatorData"], "authenticatorData"),
    clientData: payload,
    publicKey: device.publicKey,
    appId: APP_ID,
  });

  assertEquals(verified.signCount, 42);
});

Deno.test("refuses an assertion over a payload that was altered in flight", async () => {
  // The whole point of signing the body: change one byte of what the server
  // will act on and the signature stops matching.
  const payload = utf8('{"observations":[{"value":800}]}');
  const built = await buildAssertion(device, payload);

  await assertRejects(
    () =>
      verifyAssertion({
        signature: built.signature,
        authenticatorData: built.authenticatorData,
        clientData: utf8('{"observations":[{"value":80000}]}'),
        publicKey: device.publicKey,
        appId: APP_ID,
      }),
    AttestationError,
    "does not verify",
  );
});

Deno.test("refuses an assertion signed by a different key", async () => {
  const payload = utf8("payload");
  const other = await makeDevice();
  const built = await buildAssertion(device, payload, {
    signingKey: other.keys.privateKey,
  });

  await assertRejects(
    () =>
      verifyAssertion({
        signature: built.signature,
        authenticatorData: built.authenticatorData,
        clientData: payload,
        publicKey: device.publicKey,
        appId: APP_ID,
      }),
    AttestationError,
    "does not verify",
  );
});

Deno.test("refuses an assertion produced for a different app id", async () => {
  const payload = utf8("payload");
  const built = await buildAssertion(device, payload, {
    appId: "ZZZZZ99999.someone.elses.app",
  });

  await assertRejects(
    () =>
      verifyAssertion({
        signature: built.signature,
        authenticatorData: built.authenticatorData,
        clientData: payload,
        publicKey: device.publicKey,
        appId: APP_ID,
      }),
    AttestationError,
    "different app id",
  );
});

Deno.test("refuses an assertion whose authenticator data carries credential data", async () => {
  // An attestation's authenticator data replayed as an assertion's. Accepting
  // it would mean the two shapes are interchangeable, and the counter would be
  // read out of a structure that has no live counter in it.
  const payload = utf8("payload");
  const attestationShaped = buildAuthenticatorData({
    rpIdHash: new Uint8Array(
      await crypto.subtle.digest("SHA-256", utf8(APP_ID)),
    ),
    signCount: 0,
    aaguid: AAGUID_PRODUCTION,
    credentialId: device.keyId,
    credentialPublicKey: device.publicKey,
  });
  const built = await buildAssertion(device, payload);

  await assertRejects(
    () =>
      verifyAssertion({
        signature: built.signature,
        authenticatorData: attestationShaped,
        clientData: payload,
        publicKey: device.publicKey,
        appId: APP_ID,
      }),
    AttestationError,
    "must not carry credential data",
  );
});

Deno.test("refuses an assertion checked against a malformed stored key", async () => {
  const payload = utf8("payload");
  const built = await buildAssertion(device, payload);

  await assertRejects(
    () =>
      verifyAssertion({
        signature: built.signature,
        authenticatorData: built.authenticatorData,
        clientData: payload,
        publicKey: new Uint8Array(65),
        appId: APP_ID,
      }),
    AttestationError,
    "not an uncompressed point",
  );

  const wrongPrefix = new Uint8Array(device.publicKey);
  wrongPrefix[0] = 0x02;
  await assertRejects(
    () =>
      verifyAssertion({
        signature: built.signature,
        authenticatorData: built.authenticatorData,
        clientData: payload,
        publicKey: wrongPrefix,
        appId: APP_ID,
      }),
    AttestationError,
    "not an uncompressed point",
  );
});

Deno.test("the assertion counter is read big-endian from the signed structure", async () => {
  // The counter is what the database uses as the replay defence, and it is
  // inside the bytes the signature covers — so a client cannot advance it
  // without re-signing. This pins the byte order, which is the one way to get
  // a working-looking counter that counts wrong.
  const payload = utf8("payload");
  for (const signCount of [0, 1, 255, 256, 65536, 4294967295]) {
    const built = await buildAssertion(device, payload, { signCount });
    const verified = await verifyAssertion({
      signature: built.signature,
      authenticatorData: built.authenticatorData,
      clientData: payload,
      publicKey: device.publicKey,
      appId: APP_ID,
    });
    assertEquals(verified.signCount, signCount);
  }
});

// ---------------------------------------------------------------------------
// Base64
// ---------------------------------------------------------------------------
Deno.test("base64 decoding round-trips and reports bad input clearly", () => {
  const encoded = encodeCbor({ a: new Uint8Array([1, 2, 3]) });
  const b64 = btoa(String.fromCharCode(...encoded));
  assertEquals(base64ToBytes(b64, "doc"), encoded);
  assertThrows(() => base64ToBytes("not base64!!", "doc"), AttestationError, "doc");
});
