import { assertEquals, assertNotEquals } from "@std/assert";
import { type AttestDeviceDeps, challengeFor, createAttestDeviceHandler } from "./handler.ts";
import type { Database, RegisterDeviceKeyArgs } from "../_shared/database.ts";
import { HttpFailure } from "../_shared/http.ts";
import { createAccessTokenVerifier } from "../_shared/jwt.ts";
import { toHex } from "../_shared/bytes.ts";
import { asCborMap, decodeCbor, encodeCbor } from "../_shared/cbor.ts";
import {
  AAGUID_DEVELOPMENT,
  type Authority,
  buildAttestation,
  type Device,
  makeDevice,
  makeIntermediate,
  makeRoot,
} from "../_test/appattest_fixtures.ts";
import { mintAccessToken, TEST_CHALLENGE_SECRET, TEST_JWT_SECRET } from "../_test/tokens.ts";

const APP_ID = "ABCDE12345.test.gametime.app";
const USER = "11111111-1111-1111-1111-111111111111";
const OTHER_USER = "22222222-2222-2222-2222-222222222222";

const root: Authority = await makeRoot();
const intermediate: Authority = await makeIntermediate(root);

/** Records what the handler tried to write, so the suite can assert on it. */
function recordingDatabase(
  onRegister: (args: RegisterDeviceKeyArgs) => void | Promise<void> = () => {},
): Database {
  return {
    registerDeviceKey: async (args) => {
      await onRegister(args);
    },
    recordMetricBatch: () => {
      throw new Error("attest-device must not record a batch");
    },
  };
}

function deps(overrides: Partial<AttestDeviceDeps> = {}): AttestDeviceDeps {
  return {
    database: recordingDatabase(),
    appId: APP_ID,
    rootCertificatePem: root.pem,
    allowedEnvironments: ["production"],
    verifyToken: createAccessTokenVerifier(TEST_JWT_SECRET),
    challengeSecret: TEST_CHALLENGE_SECRET,
    ...overrides,
  };
}

function base64(bytes: Uint8Array<ArrayBuffer>): string {
  return btoa(String.fromCharCode(...bytes));
}

async function post(
  handler: (request: Request) => Promise<Response>,
  body: unknown,
  options: {
    token?: string | null;
    path?: string;
    method?: string;
    /** Keeps the token valid against an injected clock. */
    at?: Date;
  } = {},
): Promise<Response> {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (options.token !== null) {
    const token = options.token ?? await mintAccessToken(USER, {
      expiresAt: Math.floor((options.at ?? new Date()).getTime() / 1000) + 3600,
    });
    headers["authorization"] = `Bearer ${token}`;
  }
  const method = options.method ?? "POST";
  return await handler(
    new Request(`https://example.test/attest-device${options.path ?? ""}`, {
      method,
      headers,
      // GET and HEAD cannot carry one, and `requirePost` is what rejects them.
      body: body === undefined || method === "GET" || method === "HEAD"
        ? undefined
        : JSON.stringify(body),
    }),
  );
}

/** A registration body for `device`, bound to the challenge the server issues. */
async function registrationBody(
  device: Device,
  at: Date,
  overrides: Parameters<typeof buildAttestation>[3] = {},
) {
  const challenge = await challengeFor(USER, TEST_CHALLENGE_SECRET, at);
  const built = await buildAttestation(root, intermediate, device, {
    appId: APP_ID,
    clientData: challenge,
    ...overrides,
  });
  return {
    keyId: base64(built.keyId),
    attestation: base64(built.attestationObject),
  };
}

// ---------------------------------------------------------------------------
// The challenge route
// ---------------------------------------------------------------------------
Deno.test("issues a challenge to a signed-in caller", async () => {
  const handler = createAttestDeviceHandler(deps());
  const response = await post(handler, undefined, { path: "/challenge" });

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(typeof body.challenge, "string");
  assertEquals(body.expiresInSeconds, 600);
});

Deno.test("a challenge is bound to the account that asked for it", async () => {
  // Otherwise one user could obtain a challenge and hand it to another, which
  // is the only thing binding registration to an identity at all.
  const at = new Date("2026-08-01T12:00:00Z");
  const mine = await challengeFor(USER, TEST_CHALLENGE_SECRET, at);
  const theirs = await challengeFor(OTHER_USER, TEST_CHALLENGE_SECRET, at);
  assertNotEquals(toHex(mine), toHex(theirs));

  // And to the secret, so it cannot be computed by a client.
  const withOtherSecret = await challengeFor(
    USER,
    "a-completely-different-secret-of-sufficient-length",
    at,
  );
  assertNotEquals(toHex(mine), toHex(withOtherSecret));
});

Deno.test("refuses a challenge without a valid token", async () => {
  const handler = createAttestDeviceHandler(deps());

  assertEquals(
    (await post(handler, undefined, { path: "/challenge", token: null })).status,
    401,
  );
  assertEquals(
    (await post(handler, undefined, { path: "/challenge", token: "not.a.token" })).status,
    401,
  );
});

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------
Deno.test("registers a well-formed attestation against the calling account", async () => {
  const device = await makeDevice();
  const at = new Date();
  let written: RegisterDeviceKeyArgs | undefined;

  const handler = createAttestDeviceHandler(deps({
    database: recordingDatabase((args) => {
      written = args;
    }),
    now: () => at,
  }));

  const response = await post(handler, await registrationBody(device, at));

  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    registered: true,
    environment: "production",
    validationCategory: 4,
    bundleVersion: "1",
  });

  // The account comes from the verified token, never from the body — there is
  // no field a client could set to attribute a key to someone else.
  assertEquals(written?.userId, USER);
  assertEquals(toHex(written!.keyId), toHex(device.keyId));
  assertEquals(toHex(written!.publicKey), toHex(device.publicKey));
  assertEquals(toHex(written!.receipt), "dead");
  assertEquals(written?.environment, "production");
});

Deno.test("registers a legacy attestation without claiming unavailable app signals", async () => {
  const device = await makeDevice();
  const at = new Date();
  let written: RegisterDeviceKeyArgs | undefined;

  const handler = createAttestDeviceHandler(deps({
    database: recordingDatabase((args) => {
      written = args;
    }),
    now: () => at,
  }));
  const response = await post(
    handler,
    await registrationBody(device, at, { legacyAuthenticatorData: true }),
  );

  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    registered: true,
    environment: "production",
  });
  assertEquals(toHex(written!.keyId), toHex(device.keyId));
  assertEquals(toHex(written!.publicKey), toHex(device.publicKey));
});

Deno.test("accepts a challenge from the previous window", async () => {
  // A request that straddles a window boundary must not be refused for arriving
  // a second late, so the previous window is tried too.
  const device = await makeDevice();
  const issuedAt = new Date("2026-08-01T12:00:00Z");
  const arrivesAt = new Date(issuedAt.getTime() + 605_000);

  const handler = createAttestDeviceHandler(deps({ now: () => arrivesAt }));
  const response = await post(handler, await registrationBody(device, issuedAt), {
    at: arrivesAt,
  });

  assertEquals(response.status, 200);
});

Deno.test("refuses a challenge that is two windows old", async () => {
  const device = await makeDevice();
  const issuedAt = new Date("2026-08-01T12:00:00Z");
  const arrivesAt = new Date(issuedAt.getTime() + 30 * 60_000);

  const handler = createAttestDeviceHandler(deps({ now: () => arrivesAt }));
  const response = await post(handler, await registrationBody(device, issuedAt), {
    at: arrivesAt,
  });

  assertEquals(response.status, 401);
  assertEquals((await response.json()).message, "the attestation could not be verified");
});

Deno.test("refuses an attestation bound to another account's challenge", async () => {
  // The handover attack: get a victim to fetch a challenge, attest against it,
  // and try to register the key under your own account.
  const device = await makeDevice();
  const at = new Date();
  const theirChallenge = await challengeFor(
    OTHER_USER,
    TEST_CHALLENGE_SECRET,
    at,
  );

  const built = await buildAttestation(root, intermediate, device, {
    appId: APP_ID,
    clientData: theirChallenge,
  });

  const handler = createAttestDeviceHandler(deps({ now: () => at }));
  const response = await post(handler, {
    keyId: base64(built.keyId),
    attestation: base64(built.attestationObject),
  });

  assertEquals(response.status, 401);
});

Deno.test("refuses a development attestation where only production is allowed", async () => {
  const device = await makeDevice();
  const at = new Date();

  const handler = createAttestDeviceHandler(deps({ now: () => at }));
  const response = await post(
    handler,
    await registrationBody(device, at, { aaguid: AAGUID_DEVELOPMENT }),
  );

  assertEquals(response.status, 401);
});

Deno.test("accepts a development attestation where it is allowed, and records which", async () => {
  const device = await makeDevice();
  const at = new Date();
  let written: RegisterDeviceKeyArgs | undefined;

  const handler = createAttestDeviceHandler(deps({
    allowedEnvironments: ["development", "production"],
    database: recordingDatabase((args) => {
      written = args;
    }),
    now: () => at,
  }));

  const response = await post(
    handler,
    await registrationBody(device, at, { aaguid: AAGUID_DEVELOPMENT }),
  );

  assertEquals(response.status, 200);
  // Stored, so a row's origin stays auditable long after the deployment that
  // accepted it has been reconfigured.
  assertEquals(written?.environment, "development");
});

Deno.test("refuses a chain that does not reach the configured root", async () => {
  const device = await makeDevice();
  const at = new Date();
  const otherRoot = await makeRoot("CN=Not Apple");

  const handler = createAttestDeviceHandler(deps({
    rootCertificatePem: otherRoot.pem,
    now: () => at,
  }));

  const response = await post(handler, await registrationBody(device, at));
  assertEquals(response.status, 401);
});

Deno.test("does not write when verification fails", async () => {
  const device = await makeDevice();
  const at = new Date();

  const handler = createAttestDeviceHandler(deps({
    database: recordingDatabase(() => {
      throw new Error("must not reach the database");
    }),
    now: () => at,
  }));

  const response = await post(
    handler,
    await registrationBody(device, at, { nonceOverride: new Uint8Array(32).fill(9) }),
  );
  assertEquals(response.status, 401);
});

// ---------------------------------------------------------------------------
// Request shape
// ---------------------------------------------------------------------------
Deno.test("refuses the wrong method, a missing body, and malformed fields", async () => {
  const handler = createAttestDeviceHandler(deps());

  assertEquals((await post(handler, { a: 1 }, { method: "GET" })).status, 400);
  assertEquals((await post(handler, undefined)).status, 400);
  assertEquals((await post(handler, { keyId: "AAAA" })).status, 400);
  assertEquals(
    (await post(handler, { keyId: "not base64!", attestation: "AAAA" })).status,
    400,
  );
  assertEquals(
    (await post(handler, { keyId: base64(new Uint8Array(32)), attestation: "AAAA" }))
      .status,
    400,
  );
});

Deno.test("refuses an attestation statement that drops Apple's receipt", async () => {
  const device = await makeDevice();
  const at = new Date();
  const body = await registrationBody(device, at);
  const bytes = Uint8Array.from(atob(body.attestation), (character) => character.charCodeAt(0));
  const outer = asCborMap(decodeCbor(bytes), "attestation");
  const statement = asCborMap(outer["attStmt"], "attStmt");
  delete statement["receipt"];
  body.attestation = base64(encodeCbor(outer));

  const response = await post(
    createAttestDeviceHandler(deps({ now: () => at })),
    body,
  );
  assertEquals(response.status, 400);
  assertEquals(
    (await response.json()).message,
    "the attestation is not a well-formed attestation object",
  );
});

Deno.test("refuses a body larger than the ceiling", async () => {
  const handler = createAttestDeviceHandler(deps());
  const response = await post(handler, {
    keyId: base64(new Uint8Array(32)),
    attestation: "A".repeat(80_000),
  });
  assertEquals(response.status, 400);
});

Deno.test("an error carries no detail into the response body", async () => {
  // The detail is for the log. A refusal that names which of eight checks failed
  // is a map of what to try next.
  const failure = new HttpFailure("unauthorized", "public", "private detail");
  assertEquals(failure.detail, "private detail");

  const device = await makeDevice();
  const at = new Date();
  const handler = createAttestDeviceHandler(deps({ now: () => at }));
  const response = await post(
    handler,
    await registrationBody(device, at, { omitNonceExtension: true }),
  );

  const body = await response.text();
  assertEquals(body.includes("nonce"), false, "the response does not name the check");
  assertEquals(JSON.parse(body).message, "the attestation could not be verified");
});
