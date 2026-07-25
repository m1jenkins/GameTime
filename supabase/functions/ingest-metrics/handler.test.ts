import { assertEquals, assertNotEquals } from "@std/assert";
import {
  ASSERTION_HEADER,
  createIngestMetricsHandler,
  type IngestMetricsDeps,
  KEY_ID_HEADER,
} from "./handler.ts";
import type { Database, RecordMetricBatchArgs } from "../_shared/database.ts";
import { type Bytes, sha256, toHex, utf8 } from "../_shared/bytes.ts";
import { HttpFailure } from "../_shared/http.ts";
import { buildAssertion, type Device, makeDevice } from "../_test/appattest_fixtures.ts";
import { mintAccessToken, TEST_JWT_SECRET } from "../_test/tokens.ts";

const APP_ID = "ABCDE12345.test.gametime.app";
const USER = "11111111-1111-1111-1111-111111111111";
const CONTEST = "a0000001-0000-0000-0000-000000000001";
const BATCH = "b0000001-0000-0000-0000-000000000001";

const device: Device = await makeDevice();

function base64(bytes: Bytes): string {
  return btoa(String.fromCharCode(...bytes));
}

interface Recorder {
  readonly database: Database;
  readonly calls: RecordMetricBatchArgs[];
}

function recorder(
  result: { batchId: string; observationCount: number; replayed: boolean } | Error = {
    batchId: "cafe0001-0000-0000-0000-000000000001",
    observationCount: 1,
    replayed: false,
  },
): Recorder {
  const calls: RecordMetricBatchArgs[] = [];
  return {
    calls,
    database: {
      registerDeviceKey: () => {
        throw new Error("ingest-metrics must not register a key");
      },
      recordMetricBatch: (args) => {
        calls.push(args);
        if (result instanceof Error) return Promise.reject(result);
        return Promise.resolve(result);
      },
    },
  };
}

function deps(overrides: Partial<IngestMetricsDeps> = {}): IngestMetricsDeps {
  return {
    database: recorder().database,
    appId: APP_ID,
    jwtSecret: TEST_JWT_SECRET,
    attestBypass: false,
    publicKeyFor: () => Promise.resolve(device.publicKey),
    ...overrides,
  };
}

const OBSERVATION = {
  metric: "steps",
  bucketStart: "2026-08-01T14:00:00.000Z",
  value: 812,
  provenance: "device",
  sampleCount: 6,
  sourceBundleId: "com.apple.health",
  deviceModel: "Watch",
};

/**
 * Builds the request the client would send: the body serialised once, and the
 * assertion computed over exactly those bytes.
 *
 * `tamperWith` runs *after* signing, which is how the man-in-the-middle cases
 * are expressed — the signature covers the original bytes and the request
 * carries the altered ones.
 */
async function signedRequest(options: {
  observations?: unknown[];
  contestId?: string;
  clientBatchId?: string;
  observedAt?: string;
  signCount?: number;
  signingKey?: CryptoKey;
  appId?: string;
  token?: string | null;
  omitAssertion?: boolean;
  mangleAssertion?: string;
  tamperWith?: (body: Record<string, unknown>) => void;
} = {}): Promise<Request> {
  const body: Record<string, unknown> = {
    contestId: options.contestId ?? CONTEST,
    clientBatchId: options.clientBatchId ?? BATCH,
    observedAt: options.observedAt ?? "2026-08-01T15:05:00.000Z",
    observations: options.observations ?? [OBSERVATION],
  };

  const headers: Record<string, string> = { "content-type": "application/json" };
  if (options.token !== null) {
    headers["authorization"] = `Bearer ${options.token ?? await mintAccessToken(USER)}`;
  }

  if (!options.omitAssertion) {
    const built = await buildAssertion(device, utf8(JSON.stringify(body)), {
      signCount: options.signCount ?? 1,
      ...(options.signingKey === undefined ? {} : { signingKey: options.signingKey }),
      ...(options.appId === undefined ? {} : { appId: options.appId }),
    });
    headers[KEY_ID_HEADER] = base64(device.keyId);
    headers[ASSERTION_HEADER] = options.mangleAssertion === undefined
      ? base64(built.assertionObject)
      : options.mangleAssertion;
  }

  // After signing, so the signature covers the original bytes and the request
  // carries whatever this produced.
  options.tamperWith?.(body);

  return new Request("https://example.test/ingest-metrics", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

// ---------------------------------------------------------------------------
// The happy path
// ---------------------------------------------------------------------------
// Note what this proves and what it does not. The signature, the payload digest,
// the parsing, and every field check are real. Whether the observation is inside
// the contest window, aligned to the participant's hour, or a downward revision
// is the database's answer, and 100/110_*.test.sql are where those are asserted.
Deno.test("records an attested batch and passes the digest through", async () => {
  const sink = recorder();
  const handler = createIngestMetricsHandler(deps({ database: sink.database }));

  const request = await signedRequest();
  const raw = new Uint8Array(await request.clone().arrayBuffer());

  const response = await handler(request);
  assertEquals(response.status, 201);
  assertEquals(await response.json(), {
    batchId: "cafe0001-0000-0000-0000-000000000001",
    observationCount: 1,
    replayed: false,
  });

  assertEquals(sink.calls.length, 1);
  const call = sink.calls[0]!;

  // The account comes from the token; there is no body field for it.
  assertEquals(call.userId, USER);
  assertEquals(call.contestId, CONTEST);
  assertEquals(call.clientBatchId, BATCH);
  assertEquals(call.signCount, 1);
  assertEquals(toHex(call.keyId!), toHex(device.keyId));

  // The digest is over the bytes that actually arrived, which is what makes
  // "this batch was attested" checkable later.
  assertEquals(toHex(call.payloadDigest), toHex(await sha256(raw)));

  // Field names are snake_case on the way to Postgres, and optional fields are
  // carried rather than dropped.
  assertEquals(call.observations[0], {
    metric: "steps",
    bucket_start: "2026-08-01T14:00:00.000Z",
    value: 812,
    provenance: "device",
    sample_count: 6,
    source_bundle_id: "com.apple.health",
    device_model: "Watch",
  });
});

Deno.test("a replayed batch comes back 200 rather than 201", async () => {
  const sink = recorder({
    batchId: "cafe0001-0000-0000-0000-000000000001",
    observationCount: 1,
    replayed: true,
  });
  const handler = createIngestMetricsHandler(deps({ database: sink.database }));

  const response = await handler(await signedRequest());
  assertEquals(response.status, 200);
  assertEquals((await response.json()).replayed, true);
});

Deno.test("carries a manual observation through rather than filtering it", async () => {
  // The client reports what HealthKit told it and the server decides what
  // counts. Dropping it here would mean trusting the client's silence, and the
  // ledger would never learn that 20,000 steps were typed in by hand.
  const sink = recorder();
  const handler = createIngestMetricsHandler(deps({ database: sink.database }));

  const response = await handler(
    await signedRequest({
      observations: [{ ...OBSERVATION, provenance: "manual", value: 20000 }],
    }),
  );

  assertEquals(response.status, 201);
  assertEquals(sink.calls[0]!.observations[0]!.provenance, "manual");
});

Deno.test("rounds a value to the two decimals the ledger stores", async () => {
  const sink = recorder();
  const handler = createIngestMetricsHandler(deps({ database: sink.database }));

  await handler(
    await signedRequest({
      observations: [{ ...OBSERVATION, value: 1234.56789 }],
    }),
  );

  assertEquals(sink.calls[0]!.observations[0]!.value, 1234.57);
});

// ---------------------------------------------------------------------------
// The assertion
// ---------------------------------------------------------------------------
Deno.test("refuses a batch whose body was altered after signing", async () => {
  // The whole reason the assertion covers the body: an intercepted request
  // cannot have its numbers raised on the way through.
  const sink = recorder();
  const handler = createIngestMetricsHandler(deps({ database: sink.database }));

  const response = await handler(
    await signedRequest({
      tamperWith: (body) => {
        (body["observations"] as Record<string, unknown>[])[0]!["value"] = 99999;
      },
    }),
  );

  assertEquals(response.status, 401);
  assertEquals(sink.calls.length, 0, "nothing reached the database");
});

Deno.test("refuses a batch signed by a key that is not the stored one", async () => {
  const other = await makeDevice();
  const sink = recorder();
  const handler = createIngestMetricsHandler(deps({ database: sink.database }));

  const response = await handler(
    await signedRequest({ signingKey: other.keys.privateKey }),
  );

  assertEquals(response.status, 401);
  assertEquals(sink.calls.length, 0);
});

Deno.test("refuses a key id with no stored key, indistinguishably from a bad signature", async () => {
  // Two different failures, one message. Otherwise this endpoint answers "is
  // this key registered?" for any key id somebody cares to try.
  const sink = recorder();
  const unknownKey = createIngestMetricsHandler(deps({
    database: sink.database,
    publicKeyFor: () => Promise.resolve(undefined),
  }));
  const badSignature = createIngestMetricsHandler(deps({ database: sink.database }));

  const a = await unknownKey(await signedRequest());
  const other = await makeDevice();
  const b = await badSignature(await signedRequest({ signingKey: other.keys.privateKey }));

  assertEquals(a.status, b.status);
  assertEquals(await a.json(), await b.json());
});

Deno.test("refuses an assertion produced for another app id", async () => {
  const handler = createIngestMetricsHandler(deps());
  const response = await handler(
    await signedRequest({ appId: "ZZZZZ99999.someone.elses.app" }),
  );
  assertEquals(response.status, 401);
});

Deno.test("passes the assertion counter through without judging it", async () => {
  // Whether the counter has advanced is atomic with consuming it, so it is the
  // database's call. What this endpoint owes is the number from inside the
  // signed structure, unmodified.
  const sink = recorder();
  const handler = createIngestMetricsHandler(deps({ database: sink.database }));

  for (const signCount of [1, 2, 70000]) {
    await handler(await signedRequest({ signCount }));
  }

  assertEquals(sink.calls.map((c) => c.signCount), [1, 2, 70000]);
});

Deno.test("refuses a missing or malformed assertion when the bypass is off", async () => {
  const sink = recorder();
  const handler = createIngestMetricsHandler(deps({ database: sink.database }));

  assertEquals((await handler(await signedRequest({ omitAssertion: true }))).status, 400);

  const mangled = await handler(
    await signedRequest({ mangleAssertion: base64(utf8("not cbor at all")) }),
  );
  assertEquals(mangled.status, 400);
  assertEquals(sink.calls.length, 0);
});

// ---------------------------------------------------------------------------
// The development bypass
// ---------------------------------------------------------------------------
Deno.test("accepts an unattested batch only under the bypass, and marks it so", async () => {
  const sink = recorder();
  const handler = createIngestMetricsHandler(deps({
    database: sink.database,
    attestBypass: true,
    publicKeyFor: undefined,
  }));

  const response = await handler(await signedRequest({ omitAssertion: true }));
  assertEquals(response.status, 201);

  // No key and no counter, which is what makes `attested` false on the row and
  // keeps a bypassed batch distinguishable forever.
  assertEquals(sink.calls[0]!.keyId, undefined);
  assertEquals(sink.calls[0]!.signCount, undefined);
});

Deno.test("still verifies an assertion under the bypass when one is supplied", async () => {
  // The bypass is for the case where no device can produce an assertion, not a
  // switch that makes a supplied one ignorable.
  const sink = recorder();
  const handler = createIngestMetricsHandler(deps({
    database: sink.database,
    attestBypass: true,
  }));

  const other = await makeDevice();
  const response = await handler(
    await signedRequest({ signingKey: other.keys.privateKey }),
  );

  assertEquals(response.status, 401);
  assertEquals(sink.calls.length, 0);
});

Deno.test("refuses to build a handler that can neither verify nor bypass", () => {
  // A misconfiguration that would otherwise show up as "every request is
  // unauthorized", which is a confusing way to learn about it.
  let threw = false;
  try {
    createIngestMetricsHandler({
      database: recorder().database,
      appId: APP_ID,
      jwtSecret: TEST_JWT_SECRET,
      attestBypass: false,
    });
  } catch {
    threw = true;
  }
  assertEquals(threw, true);
});

// ---------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------
Deno.test("refuses a request with no token, and one with a forged token", async () => {
  const sink = recorder();
  const handler = createIngestMetricsHandler(deps({ database: sink.database }));

  assertEquals((await handler(await signedRequest({ token: null }))).status, 401);

  const forged = await mintAccessToken(USER, {
    secret: "another-secret-that-is-long-enough-to-pass",
  });
  assertEquals((await handler(await signedRequest({ token: forged }))).status, 401);
  assertEquals(sink.calls.length, 0);
});

Deno.test("attributes the batch to the token's subject, not to anything in the body", async () => {
  // There is no body field for the account, and adding one changes nothing —
  // which is the property worth pinning, because the alternative is an endpoint
  // where a client names whose evidence it is writing.
  const sink = recorder();
  const handler = createIngestMetricsHandler(deps({ database: sink.database }));

  const other = "22222222-2222-2222-2222-222222222222";
  await handler(
    await signedRequest({
      token: await mintAccessToken(other),
      observations: [{ ...OBSERVATION, userId: USER }],
    }),
  );

  assertEquals(sink.calls.length, 1);
  assertEquals(sink.calls[0]!.userId, other);
  assertNotEquals(sink.calls[0]!.userId, USER);
});

// ---------------------------------------------------------------------------
// Field validation
// ---------------------------------------------------------------------------
Deno.test("refuses malformed envelopes", async () => {
  const handler = createIngestMetricsHandler(deps({ attestBypass: true }));

  const cases: Record<string, unknown>[] = [
    { clientBatchId: BATCH, observedAt: "2026-08-01T15:00:00Z", observations: [OBSERVATION] },
    {
      contestId: "not-a-uuid",
      clientBatchId: BATCH,
      observedAt: "2026-08-01T15:00:00Z",
      observations: [OBSERVATION],
    },
    {
      contestId: CONTEST,
      clientBatchId: BATCH,
      observedAt: "yesterday",
      observations: [OBSERVATION],
    },
    {
      contestId: CONTEST,
      clientBatchId: BATCH,
      observedAt: "2026-08-01T15:00:00Z",
      observations: [],
    },
    {
      contestId: CONTEST,
      clientBatchId: BATCH,
      observedAt: "2026-08-01T15:00:00Z",
      observations: {},
    },
  ];

  for (const body of cases) {
    const response = await handler(
      new Request("https://example.test/ingest-metrics", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "authorization": `Bearer ${await mintAccessToken(USER)}`,
        },
        body: JSON.stringify(body),
      }),
    );
    assertEquals(response.status, 400, JSON.stringify(body));
  }
});

Deno.test("refuses malformed observations", async () => {
  const handler = createIngestMetricsHandler(deps({ attestBypass: true }));

  const bad: unknown[] = [
    { ...OBSERVATION, metric: "heart_rate" },
    { ...OBSERVATION, provenance: "trustworthy" },
    { ...OBSERVATION, bucketStart: "not a time" },
    { ...OBSERVATION, value: -1 },
    { ...OBSERVATION, value: "800" },
    { ...OBSERVATION, value: Number.POSITIVE_INFINITY },
    { ...OBSERVATION, value: 1e12 },
    { ...OBSERVATION, sampleCount: 0 },
    { ...OBSERVATION, sampleCount: 1.5 },
    { ...OBSERVATION, sourceBundleId: "x".repeat(201) },
    { ...OBSERVATION, deviceModel: "x".repeat(101) },
    "not an object",
    null,
  ];

  for (const observation of bad) {
    const response = await handler(
      new Request("https://example.test/ingest-metrics", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "authorization": `Bearer ${await mintAccessToken(USER)}`,
        },
        body: JSON.stringify({
          contestId: CONTEST,
          clientBatchId: BATCH,
          observedAt: "2026-08-01T15:00:00Z",
          observations: [observation],
        }),
      }),
    );
    assertEquals(response.status, 400, JSON.stringify(observation));
  }
});

Deno.test("refuses more observations than one batch may carry", async () => {
  const handler = createIngestMetricsHandler(deps({ attestBypass: true }));
  const response = await handler(
    new Request("https://example.test/ingest-metrics", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "authorization": `Bearer ${await mintAccessToken(USER)}`,
      },
      body: JSON.stringify({
        contestId: CONTEST,
        clientBatchId: BATCH,
        observedAt: "2026-08-01T15:00:00Z",
        observations: Array(2001).fill(OBSERVATION),
      }),
    }),
  );
  assertEquals(response.status, 400);
});

// ---------------------------------------------------------------------------
// Database refusals become the right status
// ---------------------------------------------------------------------------
Deno.test("a rule that refused the write becomes 422, not 500", async () => {
  // The ledger's rules — window, alignment, monotonicity — surface here as
  // HttpFailure("rejected"). A 500 would tell the client to retry something that
  // will never succeed.
  const sink = recorder(
    new HttpFailure("rejected", "the evidence was refused by a rule of this contest"),
  );
  const handler = createIngestMetricsHandler(deps({ database: sink.database }));

  const response = await handler(await signedRequest());
  assertEquals(response.status, 422);
  assertEquals((await response.json()).error, "rejected");
});

Deno.test("an unexpected database error becomes a 500 that says nothing", async () => {
  const sink = recorder(new Error("connection to 10.0.0.5:5432 refused, password=hunter2"));
  const handler = createIngestMetricsHandler(deps({ database: sink.database }));

  const response = await handler(await signedRequest());
  assertEquals(response.status, 500);

  const text = await response.text();
  assertEquals(text.includes("hunter2"), false, "no internals leak into the body");
  assertEquals(text.includes("10.0.0.5"), false);
});
