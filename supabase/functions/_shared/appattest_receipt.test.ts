import { assertEquals, assertRejects } from "@std/assert";
import * as asn1js from "asn1js";
import * as x509 from "@peculiar/x509";
import {
  RECEIPT_MAX_AGE_MS,
  ReceiptVerificationError,
  verifyAppAttestReceipt,
} from "./appattest_receipt.ts";
import { base64ToBytes } from "./appattest.ts";
import { type Bytes, toHex } from "./bytes.ts";
import {
  buildReceiptFixture,
  certificateBytes,
  makeExpiredReceiptSigner,
  makeReceiptFixtureContext,
  makeWrongPurposeReceiptSigner,
  outerSequenceAsIndefinite,
  RECEIPT_APP_ID,
  RECEIPT_CAPTURED_AT,
  RECEIPT_CREATED_AT,
  tamperFirst,
} from "../_test/appattest_receipt_fixtures.ts";
import {
  APPLE_2026_APP_ATTEST_VECTOR,
  APPLE_ROOT_CA_G3_PEM,
} from "../_test/apple_appattest_2026_vector.ts";

const context = await makeReceiptFixtureContext();

function request(
  receipt: Bytes,
  overrides: Partial<Parameters<typeof verifyAppAttestReceipt>[0]> = {},
) {
  return {
    receipt,
    appId: RECEIPT_APP_ID,
    publicKey: context.publicKey,
    receiptRootCertificatePem: context.root.pem,
    receivedAt: RECEIPT_CAPTURED_AT,
    ...overrides,
  };
}

async function rejectsReceipt(
  receipt: Bytes,
  overrides: Partial<Parameters<typeof verifyAppAttestReceipt>[0]> = {},
) {
  await assertRejects(
    () => verifyAppAttestReceipt(request(receipt, overrides)),
    ReceiptVerificationError,
  );
}

Deno.test("verifies signature, chain, App ID, creation time, and public-key binding", async () => {
  const built = await buildReceiptFixture(context);
  const result = await verifyAppAttestReceipt(request(built.receipt));

  assertEquals(result.type, "ATTEST");
  assertEquals(result.creationTime, RECEIPT_CREATED_AT);
  assertEquals(
    toHex(result.receiptSha256).length,
    64,
    "the exact verified receipt yields a SHA-256 marker capability",
  );
});

Deno.test("verifies Apple's complete official 2026 App Attest receipt vector", async () => {
  const vector = APPLE_2026_APP_ATTEST_VECTOR;
  const leaf = new x509.X509Certificate(
    base64ToBytes(vector.leafCertificateBase64, "official leaf certificate"),
  );
  const leafPublicKey = await crypto.subtle.importKey(
    "spki",
    leaf.publicKey.rawData,
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["verify"],
  );
  const publicKey = new Uint8Array(
    await crypto.subtle.exportKey("raw", leafPublicKey),
  );

  const result = await verifyAppAttestReceipt({
    receipt: base64ToBytes(vector.receiptBase64, "official receipt"),
    appId: vector.appId,
    publicKey,
    receiptRootCertificatePem: APPLE_ROOT_CA_G3_PEM,
    receivedAt: vector.receiptCreatedAt,
  });

  assertEquals(result.type, "ATTEST");
  assertEquals(result.creationTime, vector.receiptCreatedAt);
  assertEquals(
    toHex(result.receiptSha256),
    "26a7ef09ab4cff17140e02780c57bec69672f4933d1a175ee84229b0107b6de0",
  );
});

Deno.test("accepts unknown future fields and SET ordering", async () => {
  const built = await buildReceiptFixture(context, {
    extraAttributes: [
      { type: 99, version: 7, value: new Uint8Array([1, 2, 3]) },
    ],
  });
  assertEquals(
    (await verifyAppAttestReceipt(request(built.receipt))).type,
    "ATTEST",
  );
});

Deno.test("accepts Apple's BER indefinite-length outer receipt container", async () => {
  const built = await buildReceiptFixture(context);
  const ber = outerSequenceAsIndefinite(built.receipt);
  assertEquals((await verifyAppAttestReceipt(request(ber))).type, "ATTEST");
});

Deno.test("accepts a separately issued certificate carrying the same device key", async () => {
  const replacement = await x509.X509CertificateGenerator.create({
    serialNumber: "20",
    subject: "CN=Same Device Key",
    issuer: context.intermediate.certificate.subject,
    notBefore: new Date("2020-01-01T00:00:00Z"),
    notAfter: new Date("2040-01-01T00:00:00Z"),
    signingAlgorithm: {
      name: "ECDSA",
      hash: "SHA-256",
    },
    publicKey: context.deviceKeys.publicKey,
    signingKey: context.intermediate.keys.privateKey,
  });
  const built = await buildReceiptFixture(context, {
    attestedKeyCertificate: certificateBytes(replacement),
  });
  await verifyAppAttestReceipt(request(built.receipt));
});

Deno.test("rejects tampered content and a tampered signature", async () => {
  const built = await buildReceiptFixture(context);
  await rejectsReceipt(
    tamperFirst(built.receipt, new TextEncoder().encode(RECEIPT_APP_ID)),
  );

  const signatureTampered = Uint8Array.from(built.receipt);
  const last = signatureTampered.length - 1;
  signatureTampered[last] = signatureTampered[last]! ^ 0x01;
  await rejectsReceipt(signatureTampered);
});

Deno.test("rejects rogue, incomplete, and time-invalid signer chains", async () => {
  const rogue = await makeReceiptFixtureContext();
  await rejectsReceipt((await buildReceiptFixture(rogue)).receipt);

  await rejectsReceipt(
    (await buildReceiptFixture(context, {
      certificates: [context.signer.certificate],
    })).receipt,
  );

  const expired = await makeExpiredReceiptSigner(context.intermediate);
  await rejectsReceipt(
    (await buildReceiptFixture(context, { signer: expired })).receipt,
  );
});

Deno.test("rejects a valid same-root signer without Apple's receipt marker", async () => {
  const wrongPurpose = await makeWrongPurposeReceiptSigner(
    context.intermediate,
  );
  await rejectsReceipt(
    (await buildReceiptFixture(context, { signer: wrongPurpose })).receipt,
  );
});

Deno.test("rejects detached data, wrong content type, and multiple signers", async () => {
  await rejectsReceipt(
    (await buildReceiptFixture(context, { detached: true })).receipt,
  );
  await rejectsReceipt(
    (await buildReceiptFixture(context, { contentType: "1.2.3.4" })).receipt,
  );
  await rejectsReceipt(
    (await buildReceiptFixture(context, { signerCount: 2 })).receipt,
  );
});

Deno.test("rejects malformed, truncated, oversized, and trailing PKCS#7", async () => {
  await rejectsReceipt(new Uint8Array([0x30, 0x01, 0xff]));
  const valid = (await buildReceiptFixture(context)).receipt;
  await rejectsReceipt(valid.slice(0, valid.length - 1));

  const trailing = new Uint8Array(valid.length + 1);
  trailing.set(valid);
  trailing[valid.length] = 0;
  await rejectsReceipt(trailing);
  await rejectsReceipt(new Uint8Array(32 * 1024 + 1));
});

Deno.test("bounds receipt ASN.1 depth and node count", async () => {
  let deeplyNested = new Uint8Array([0x05, 0x00]);
  for (let depth = 0; depth < 30; depth++) {
    deeplyNested = new Uint8Array([
      0x30,
      deeplyNested.length,
      ...deeplyNested,
    ]);
  }
  await rejectsReceipt(
    (await buildReceiptFixture(context, {
      payloadOverride: new Uint8Array([
        0x31,
        deeplyNested.length,
        ...deeplyNested,
      ]),
    })).receipt,
  );

  const tooManyNodes = new Uint8Array([
    0x31,
    0x84,
    0x00,
    0x00,
    0x04,
    0x02,
    ...new Uint8Array(513 * 2).map((_, index) => index % 2 === 0 ? 0x05 : 0x00),
  ]);
  await rejectsReceipt(
    (await buildReceiptFixture(context, {
      payloadOverride: tooManyNodes,
    })).receipt,
  );
});

Deno.test("rejects receipt attribute integers larger than safe numbers", async () => {
  const huge = new asn1js.Integer({
    valueHex: new Uint8Array(16).fill(0x7f),
  });
  for (
    const attribute of [
      new asn1js.Sequence({
        value: [
          huge,
          new asn1js.Integer({ value: 1 }),
          new asn1js.OctetString(),
        ],
      }),
      new asn1js.Sequence({
        value: [
          new asn1js.Integer({ value: 2 }),
          huge,
          new asn1js.OctetString(),
        ],
      }),
    ]
  ) {
    const payload = new Uint8Array(
      new asn1js.Set({ value: [attribute] }).toBER(false),
    );
    await rejectsReceipt(
      (await buildReceiptFixture(context, { payloadOverride: payload }))
        .receipt,
    );
  }
});

Deno.test("requires unique App ID, public-key, type, and creation fields", async () => {
  for (const field of [2, 3, 6, 12]) {
    await rejectsReceipt(
      (await buildReceiptFixture(context, { omitFields: [field] })).receipt,
    );
    await rejectsReceipt(
      (await buildReceiptFixture(context, { duplicateFields: [field] })).receipt,
    );
  }
});

Deno.test("requires version 1 for every interpreted receipt field", async () => {
  for (const field of [2, 3, 6, 12]) {
    await rejectsReceipt(
      (await buildReceiptFixture(context, {
        fieldVersions: { [field]: 2 },
      })).receipt,
    );
  }
});

Deno.test("requires an exact App ID and rejects hidden text suffixes", async () => {
  for (
    const appId of [
      "ZZZZZ99999.test.gametime.app",
      `${RECEIPT_APP_ID}.other`,
      `${RECEIPT_APP_ID}\0`,
    ]
  ) {
    await rejectsReceipt(
      (await buildReceiptFixture(context, { appId })).receipt,
    );
  }
});

Deno.test("enforces the inclusive five-minute capture-time window", async () => {
  const atCapture = await buildReceiptFixture(context, {
    creationTime: RECEIPT_CAPTURED_AT.toISOString(),
  });
  await verifyAppAttestReceipt(request(atCapture.receipt));

  const boundary = await buildReceiptFixture(context, {
    creationTime: new Date(
      RECEIPT_CAPTURED_AT.getTime() - RECEIPT_MAX_AGE_MS,
    ).toISOString(),
  });
  await verifyAppAttestReceipt(request(boundary.receipt));

  const stale = await buildReceiptFixture(context, {
    creationTime: new Date(
      RECEIPT_CAPTURED_AT.getTime() - RECEIPT_MAX_AGE_MS - 1,
    ).toISOString(),
  });
  await rejectsReceipt(stale.receipt);

  const future = await buildReceiptFixture(context, {
    creationTime: new Date(RECEIPT_CAPTURED_AT.getTime() + 1).toISOString(),
  });
  await rejectsReceipt(future.receipt);
});

Deno.test("uses immutable first capture time so a later retry remains valid", async () => {
  const built = await buildReceiptFixture(context);
  // The verifier has no wall-clock input. Re-running hours later with the same
  // immutable database receivedAt proves freshness against first capture.
  await verifyAppAttestReceipt(request(built.receipt));
  await verifyAppAttestReceipt(request(built.receipt));
});

Deno.test("rejects malformed and impossible creation times", async () => {
  for (
    const creationTime of [
      "not-a-date",
      "2026-02-30T12:00:00.000Z",
      "2026-08-01T12:00:00+00:00",
      "2026-08-01 12:00:00Z",
      "2026-08-01T12:00:00.0000Z",
    ]
  ) {
    await rejectsReceipt(
      (await buildReceiptFixture(context, { creationTime })).receipt,
    );
  }
});

Deno.test("rejects the wrong, malformed, and non-P-256 attested key", async () => {
  const other = await makeReceiptFixtureContext();
  await rejectsReceipt(
    (await buildReceiptFixture(context, {
      attestedKeyCertificate: certificateBytes(other.deviceCertificate),
    })).receipt,
  );
  await rejectsReceipt(
    (await buildReceiptFixture(context, {
      attestedKeyCertificate: new Uint8Array([1, 2, 3]),
    })).receipt,
  );

  const rsa = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  const rsaCertificate = await x509.X509CertificateGenerator.createSelfSigned({
    serialNumber: "30",
    name: "CN=Wrong RSA Device Key",
    notBefore: new Date("2020-01-01T00:00:00Z"),
    notAfter: new Date("2040-01-01T00:00:00Z"),
    signingAlgorithm: {
      name: "RSASSA-PKCS1-v1_5",
      hash: "SHA-256",
    },
    keys: rsa,
  });
  await rejectsReceipt(
    (await buildReceiptFixture(context, {
      attestedKeyCertificate: certificateBytes(rsaCertificate),
    })).receipt,
  );
});

Deno.test("requires ATTEST for registration but can verify a refreshed RECEIPT", async () => {
  const refreshed = await buildReceiptFixture(context, {
    receiptType: "RECEIPT",
  });
  await rejectsReceipt(refreshed.receipt);
  assertEquals(
    (await verifyAppAttestReceipt(
      request(refreshed.receipt, { expectedTypes: ["RECEIPT"] }),
    )).type,
    "RECEIPT",
  );

  await rejectsReceipt(
    (await buildReceiptFixture(context, { receiptType: "UNKNOWN" })).receipt,
  );
});

Deno.test("rejects an unreadable root and invalid stored-key context", async () => {
  const built = await buildReceiptFixture(context);
  await rejectsReceipt(built.receipt, {
    receiptRootCertificatePem: "not a certificate",
  });
  await rejectsReceipt(built.receipt, { publicKey: new Uint8Array(65) });
  await rejectsReceipt(built.receipt, { receivedAt: new Date("invalid") });
});
