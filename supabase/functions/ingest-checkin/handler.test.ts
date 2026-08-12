import { assertEquals, assertNotEquals } from "@std/assert";
import type {
  CheckInDatabase,
  RecordedGeofenceCheckIn,
  RecordGeofenceCheckInArgs,
} from "../_shared/database.ts";
import { postgrestCheckInDatabase } from "../_shared/database.ts";
import { type Bytes, sha256, toHex, utf8 } from "../_shared/bytes.ts";
import { HttpFailure } from "../_shared/http.ts";
import { createAccessTokenVerifier } from "../_shared/jwt.ts";
import { buildAssertion, type Device, makeDevice } from "../_test/appattest_fixtures.ts";
import { mintAccessToken, TEST_JWT_SECRET } from "../_test/tokens.ts";
import {
  ASSERTION_HEADER,
  createIngestCheckInHandler,
  type IngestCheckInDeps,
  KEY_ID_HEADER,
  MAX_BODY_BYTES,
  MAX_LOCATIONS,
} from "./handler.ts";

const APP_ID = "ABCDE12345.test.gametime.app";
const USER = "11111111-1111-1111-1111-111111111111";
const OTHER_USER = "22222222-2222-2222-2222-222222222222";
const CONTEST = "a0000001-0000-0000-0000-000000000001";
const GEOFENCE = "a0000002-0000-0000-0000-000000000002";
const CLIENT_CHECK_IN = "b0000001-0000-0000-0000-000000000001";
const CHECK_IN = "cafe0001-0000-0000-0000-000000000001";
const WORKOUT = "d0000001-0000-0000-0000-000000000001";

const device: Device = await makeDevice();

function base64(bytes: Bytes): string {
  return btoa(String.fromCharCode(...bytes));
}

function defaultBody(): Record<string, unknown> {
  return {
    contestId: CONTEST,
    geofenceId: GEOFENCE,
    clientCheckInId: CLIENT_CHECK_IN,
    locations: [
      {
        observedAt: "2026-08-01T09:00:00-05:00",
        latitude: 41.881,
        longitude: -87.623,
        horizontalAccuracyMeters: 8.5,
        isSimulatedBySoftware: false,
        isProducedByAccessory: false,
      },
      {
        observedAt: "2026-08-01T09:05:00-05:00",
        latitude: 41.8811,
        longitude: -87.6231,
        horizontalAccuracyMeters: 9,
        isSimulatedBySoftware: false,
        isProducedByAccessory: true,
      },
    ],
    workout: {
      id: WORKOUT,
      startedAt: "2026-08-01T13:55:00Z",
      endedAt: "2026-08-01T14:30:00+00:00",
      activityType: "traditional_strength_training",
      provenance: "device",
      sourceBundleId: "com.apple.health",
    },
  };
}

interface Recorder {
  readonly database: CheckInDatabase;
  readonly calls: RecordGeofenceCheckInArgs[];
}

function recorder(
  result: RecordedGeofenceCheckIn | Error = {
    checkInId: CHECK_IN,
    outcome: "verified",
    dwellSeconds: 300,
    workoutOverlapSeconds: 300,
    replayed: false,
  },
): Recorder {
  const calls: RecordGeofenceCheckInArgs[] = [];
  return {
    calls,
    database: {
      recordGeofenceCheckIn(args) {
        calls.push(args);
        return result instanceof Error ? Promise.reject(result) : Promise.resolve(result);
      },
    },
  };
}

function deps(overrides: Partial<IngestCheckInDeps> = {}): IngestCheckInDeps {
  return {
    database: recorder().database,
    appId: APP_ID,
    verifyToken: createAccessTokenVerifier(TEST_JWT_SECRET),
    attestBypass: false,
    publicKeyFor: () => Promise.resolve(device.publicKey),
    ...overrides,
  };
}

async function signedRequest(options: {
  body?: Record<string, unknown>;
  signCount?: number;
  signingKey?: CryptoKey;
  appId?: string;
  token?: string | null;
  omitAssertion?: boolean;
  assertionExtensions?: boolean;
  onlyKeyId?: boolean;
  mangleKeyId?: string;
  mangleAssertion?: string;
  tamperWith?: (body: Record<string, unknown>) => void;
} = {}): Promise<Request> {
  const body = structuredClone(options.body ?? defaultBody());
  const signedBytes = utf8(JSON.stringify(body));
  const headers: Record<string, string> = { "content-type": "application/json" };

  if (options.token !== null) {
    headers["authorization"] = `Bearer ${options.token ?? await mintAccessToken(USER)}`;
  }

  if (!options.omitAssertion) {
    const built = await buildAssertion(device, signedBytes, {
      signCount: options.signCount ?? 1,
      ...(options.signingKey === undefined ? {} : { signingKey: options.signingKey }),
      ...(options.appId === undefined ? {} : { appId: options.appId }),
      ...(options.assertionExtensions === true
        ? {
          assertionExtensions: {
            validationCategory: 3,
            bundleVersion: "1",
          },
        }
        : {}),
    });
    headers[KEY_ID_HEADER] = options.mangleKeyId ?? base64(device.keyId);
    if (!options.onlyKeyId) {
      headers[ASSERTION_HEADER] = options.mangleAssertion ?? base64(built.assertionObject);
    }
  }

  options.tamperWith?.(body);
  return new Request("https://example.test/ingest-checkin", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

async function bypassRequest(body: Record<string, unknown>): Promise<Request> {
  return await signedRequest({ body, omitAssertion: true });
}

Deno.test("records a current extended assertion check-in from exact signed bytes", async () => {
  const sink = recorder();
  const handler = createIngestCheckInHandler(deps({ database: sink.database }));
  const request = await signedRequest({ signCount: 7, assertionExtensions: true });
  const raw = new Uint8Array(await request.clone().arrayBuffer());

  const response = await handler(request);
  assertEquals(response.status, 201);
  assertEquals(await response.json(), {
    checkInId: CHECK_IN,
    outcome: "verified",
    dwellSeconds: 300,
    workoutOverlapSeconds: 300,
    replayed: false,
  });

  assertEquals(sink.calls.length, 1);
  const call = sink.calls[0]!;
  assertEquals(call.userId, USER);
  assertEquals(call.contestId, CONTEST);
  assertEquals(call.geofenceId, GEOFENCE);
  assertEquals(call.clientCheckInId, CLIENT_CHECK_IN);
  assertEquals(call.signCount, 7);
  assertEquals(toHex(call.keyId!), toHex(device.keyId));
  assertEquals(toHex(call.payloadDigest), toHex(await sha256(raw)));
  assertEquals(call.locations, [
    {
      observed_at: "2026-08-01T14:00:00.000Z",
      latitude: 41.881,
      longitude: -87.623,
      accuracy_meters: 8.5,
      is_simulated: false,
      is_produced_by_accessory: false,
    },
    {
      observed_at: "2026-08-01T14:05:00.000Z",
      latitude: 41.8811,
      longitude: -87.6231,
      accuracy_meters: 9,
      is_simulated: false,
      is_produced_by_accessory: true,
    },
  ]);
  assertEquals(call.workoutId, WORKOUT);
  assertEquals(call.workoutStartedAt, "2026-08-01T13:55:00.000Z");
  assertEquals(call.workoutEndedAt, "2026-08-01T14:30:00.000Z");
  assertEquals(call.workoutActivityType, "traditional_strength_training");
  assertEquals(call.workoutProvenance, "device");
  assertEquals(call.workoutSourceBundleId, "com.apple.health");
});

Deno.test("returns durable validation failures as outcomes rather than HTTP errors", async () => {
  const sink = recorder({
    checkInId: CHECK_IN,
    outcome: "outside_geofence",
    dwellSeconds: 0,
    workoutOverlapSeconds: 0,
    replayed: false,
  });
  const response = await createIngestCheckInHandler(deps({ database: sink.database }))(
    await signedRequest(),
  );

  assertEquals(response.status, 201);
  assertEquals((await response.json()).outcome, "outside_geofence");
});

Deno.test("returns 200 and the original result for an idempotent retry", async () => {
  const sink = recorder({
    checkInId: CHECK_IN,
    outcome: "verified",
    dwellSeconds: 300,
    workoutOverlapSeconds: 180,
    replayed: true,
  });
  const response = await createIngestCheckInHandler(deps({ database: sink.database }))(
    await signedRequest(),
  );

  assertEquals(response.status, 200);
  assertEquals((await response.json()).replayed, true);
});

Deno.test("refuses a body altered after its App Attest assertion was made", async () => {
  const sink = recorder();
  const handler = createIngestCheckInHandler(deps({ database: sink.database }));
  const response = await handler(
    await signedRequest({
      tamperWith: (body) => {
        const locations = body["locations"] as Record<string, unknown>[];
        locations[0]!["latitude"] = 35;
      },
    }),
  );

  assertEquals(response.status, 401);
  assertEquals(sink.calls.length, 0);
});

Deno.test("unknown keys and bad signatures are indistinguishable", async () => {
  const unknown = createIngestCheckInHandler(deps({
    publicKeyFor: () => Promise.resolve(undefined),
  }));
  const badSignature = createIngestCheckInHandler(deps());
  const other = await makeDevice();

  const a = await unknown(await signedRequest());
  const b = await badSignature(
    await signedRequest({ signingKey: other.keys.privateKey }),
  );
  assertEquals(a.status, 401);
  assertEquals(a.status, b.status);
  assertEquals(await a.json(), await b.json());
});

Deno.test("refuses an assertion made for a different app id", async () => {
  const response = await createIngestCheckInHandler(deps())(
    await signedRequest({ appId: "ZZZZZ99999.someone.elses.app" }),
  );
  assertEquals(response.status, 401);
});

Deno.test("refuses missing, partial, invalid-base64, and malformed-CBOR assertions", async () => {
  const sink = recorder();
  const handler = createIngestCheckInHandler(deps({ database: sink.database }));
  const cases = [
    await signedRequest({ omitAssertion: true }),
    await signedRequest({ onlyKeyId: true }),
    await signedRequest({ mangleKeyId: "***not-base64***" }),
    await signedRequest({ mangleAssertion: "***not-base64***" }),
    await signedRequest({ mangleAssertion: base64(utf8("not cbor")) }),
  ];

  for (const request of cases) {
    assertEquals((await handler(request)).status, 400);
  }
  assertEquals(sink.calls.length, 0);
});

Deno.test("the local bypass is auditable and omits key and counter", async () => {
  const sink = recorder();
  const handler = createIngestCheckInHandler(deps({
    database: sink.database,
    attestBypass: true,
    publicKeyFor: undefined,
  }));

  const response = await handler(await signedRequest({ omitAssertion: true }));
  assertEquals(response.status, 201);
  assertEquals(sink.calls[0]!.keyId, undefined);
  assertEquals(sink.calls[0]!.signCount, undefined);
});

Deno.test("a supplied assertion is still verified while the bypass is enabled", async () => {
  const sink = recorder();
  const handler = createIngestCheckInHandler(deps({
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

Deno.test("refuses to construct a handler with neither verification nor bypass", () => {
  let threw = false;
  try {
    createIngestCheckInHandler({
      database: recorder().database,
      appId: APP_ID,
      verifyToken: createAccessTokenVerifier(TEST_JWT_SECRET),
      attestBypass: false,
    });
  } catch {
    threw = true;
  }
  assertEquals(threw, true);
});

Deno.test("requires a genuine access token and attributes from its subject", async () => {
  const sink = recorder();
  const handler = createIngestCheckInHandler(deps({ database: sink.database }));

  assertEquals((await handler(await signedRequest({ token: null }))).status, 401);
  const forged = await mintAccessToken(USER, {
    secret: "another-secret-that-is-long-enough-to-pass",
  });
  assertEquals((await handler(await signedRequest({ token: forged }))).status, 401);

  const body = defaultBody();
  body["userId"] = USER;
  const response = await handler(
    await signedRequest({ body, token: await mintAccessToken(OTHER_USER) }),
  );
  assertEquals(response.status, 201);
  assertEquals(sink.calls.length, 1);
  assertEquals(sink.calls[0]!.userId, OTHER_USER);
  assertNotEquals(sink.calls[0]!.userId, USER);
});

Deno.test("accepts coordinate boundaries, all provenance values, and an absent bundle id", async () => {
  const sink = recorder();
  const handler = createIngestCheckInHandler(deps({
    database: sink.database,
    attestBypass: true,
    publicKeyFor: undefined,
  }));

  for (const provenance of ["device", "third_party", "manual", "unknown"]) {
    const body = defaultBody();
    body["locations"] = [
      {
        observedAt: "2026-08-01T14:00:00Z",
        latitude: -90,
        longitude: -180,
        horizontalAccuracyMeters: Number.MIN_VALUE,
        isSimulatedBySoftware: false,
        isProducedByAccessory: false,
      },
      {
        observedAt: "2026-08-01T14:00:01Z",
        latitude: 90,
        longitude: 180,
        horizontalAccuracyMeters: 100_000,
        isSimulatedBySoftware: true,
        isProducedByAccessory: true,
      },
    ];
    const workout = body["workout"] as Record<string, unknown>;
    workout["provenance"] = provenance;
    delete workout["sourceBundleId"];
    assertEquals((await handler(await bypassRequest(body))).status, 201);
  }

  assertEquals(sink.calls.length, 4);
  assertEquals(sink.calls.every((call) => call.workoutSourceBundleId === undefined), true);
});

Deno.test("requires two to 256 location observations", async () => {
  const handler = createIngestCheckInHandler(deps({
    attestBypass: true,
    publicKeyFor: undefined,
  }));

  const one = defaultBody();
  one["locations"] = (one["locations"] as unknown[]).slice(0, 1);
  assertEquals((await handler(await bypassRequest(one))).status, 400);

  const none = defaultBody();
  none["locations"] = [];
  assertEquals((await handler(await bypassRequest(none))).status, 400);

  const notArray = defaultBody();
  notArray["locations"] = {};
  assertEquals((await handler(await bypassRequest(notArray))).status, 400);

  const tooMany = defaultBody();
  tooMany["locations"] = Array.from({ length: MAX_LOCATIONS + 1 }, (_, index) => ({
    observedAt: new Date(Date.UTC(2026, 7, 1, 14, 0, index)).toISOString(),
    latitude: 41,
    longitude: -87,
    horizontalAccuracyMeters: 1,
    isSimulatedBySoftware: false,
    isProducedByAccessory: false,
  }));
  assertEquals((await handler(await bypassRequest(tooMany))).status, 400);
});

Deno.test("accepts exactly 256 uniquely timed observations", async () => {
  const sink = recorder();
  const handler = createIngestCheckInHandler(deps({
    database: sink.database,
    attestBypass: true,
    publicKeyFor: undefined,
  }));
  const body = defaultBody();
  body["locations"] = Array.from({ length: MAX_LOCATIONS }, (_, index) => ({
    observedAt: new Date(Date.UTC(2026, 7, 1, 14, 0, index)).toISOString(),
    latitude: 41,
    longitude: -87,
    horizontalAccuracyMeters: 1,
    isSimulatedBySoftware: false,
    isProducedByAccessory: false,
  }));

  assertEquals((await handler(await bypassRequest(body))).status, 201);
  assertEquals(sink.calls[0]!.locations.length, MAX_LOCATIONS);
});

Deno.test("refuses invalid coordinate, accuracy, and source-information fields", async () => {
  const handler = createIngestCheckInHandler(deps({
    attestBypass: true,
    publicKeyFor: undefined,
  }));
  const mutations: Array<(location: Record<string, unknown>) => void> = [
    (row) => row["latitude"] = -90.0001,
    (row) => row["latitude"] = 90.0001,
    (row) => row["longitude"] = -180.0001,
    (row) => row["longitude"] = 180.0001,
    (row) => row["latitude"] = "41",
    (row) => row["longitude"] = null,
    (row) => row["horizontalAccuracyMeters"] = 0,
    (row) => row["horizontalAccuracyMeters"] = -1,
    (row) => row["horizontalAccuracyMeters"] = 100_000.01,
    (row) => row["horizontalAccuracyMeters"] = Number.POSITIVE_INFINITY,
    (row) => row["isSimulatedBySoftware"] = 0,
    (row) => row["isProducedByAccessory"] = "false",
  ];

  for (const mutate of mutations) {
    const body = defaultBody();
    mutate((body["locations"] as Record<string, unknown>[])[0]!);
    assertEquals((await handler(await bypassRequest(body))).status, 400);
  }

  for (const entry of [null, "location", []]) {
    const body = defaultBody();
    (body["locations"] as unknown[])[0] = entry;
    assertEquals((await handler(await bypassRequest(body))).status, 400);
  }
});

Deno.test("requires valid, absolute, unique location timestamps", async () => {
  const handler = createIngestCheckInHandler(deps({
    attestBypass: true,
    publicKeyFor: undefined,
  }));
  const invalid = [
    "2026-08-01T14:00:00",
    "2026-02-30T14:00:00Z",
    "2026-08-01T24:00:00Z",
    "2026-08-01T14:00:00.1234Z",
    "not-a-time",
  ];
  for (const timestamp of invalid) {
    const body = defaultBody();
    (body["locations"] as Record<string, unknown>[])[0]!["observedAt"] = timestamp;
    assertEquals((await handler(await bypassRequest(body))).status, 400);
  }

  const duplicate = defaultBody();
  const locations = duplicate["locations"] as Record<string, unknown>[];
  locations[0]!["observedAt"] = "2026-08-01T14:00:00Z";
  locations[1]!["observedAt"] = "2026-08-01T09:00:00-05:00";
  assertEquals((await handler(await bypassRequest(duplicate))).status, 400);
});

Deno.test("refuses malformed workout identity, ranges, and metadata", async () => {
  const handler = createIngestCheckInHandler(deps({
    attestBypass: true,
    publicKeyFor: undefined,
  }));
  const mutations: Array<(workout: Record<string, unknown>) => void> = [
    (row) => row["id"] = "not-a-uuid",
    (row) => row["startedAt"] = "2026-08-01T13:00:00",
    (row) => row["endedAt"] = "2026-08-01T13:55:00Z",
    (row) => row["endedAt"] = "2026-08-01T13:00:00Z",
    (row) => row["endedAt"] = "2026-02-30T13:00:00Z",
    (row) => row["activityType"] = "",
    (row) => row["activityType"] = "x".repeat(101),
    (row) => row["activityType"] = 12,
    (row) => row["provenance"] = "trusted",
    (row) => row["sourceBundleId"] = "",
    (row) => row["sourceBundleId"] = "x".repeat(201),
    (row) => row["sourceBundleId"] = 1,
  ];

  for (const mutate of mutations) {
    const body = defaultBody();
    mutate(body["workout"] as Record<string, unknown>);
    assertEquals((await handler(await bypassRequest(body))).status, 400);
  }

  for (const workout of [null, [], "workout"]) {
    const body = defaultBody();
    body["workout"] = workout;
    assertEquals((await handler(await bypassRequest(body))).status, 400);
  }
});

Deno.test("refuses malformed envelope UUIDs and unsupported methods", async () => {
  const handler = createIngestCheckInHandler(deps({
    attestBypass: true,
    publicKeyFor: undefined,
  }));
  for (const field of ["contestId", "geofenceId", "clientCheckInId"]) {
    const body = defaultBody();
    body[field] = "not-a-uuid";
    assertEquals((await handler(await bypassRequest(body))).status, 400);
  }

  const get = new Request("https://example.test/ingest-checkin", { method: "GET" });
  assertEquals((await handler(get)).status, 400);
});

Deno.test("refuses a body over the byte ceiling before processing it", async () => {
  const handler = createIngestCheckInHandler(deps({
    attestBypass: true,
    publicKeyFor: undefined,
  }));
  const request = new Request("https://example.test/ingest-checkin", {
    method: "POST",
    headers: {
      "authorization": `Bearer ${await mintAccessToken(USER)}`,
      "content-type": "application/json",
    },
    body: "x".repeat(MAX_BODY_BYTES + 1),
  });
  assertEquals((await handler(request)).status, 400);
});

Deno.test("database rule refusals retain their non-retryable status", async () => {
  const sink = recorder(
    new HttpFailure("rejected", "this check-in overlaps another recorded check-in"),
  );
  const response = await createIngestCheckInHandler(deps({ database: sink.database }))(
    await signedRequest(),
  );
  assertEquals(response.status, 422);
  assertEquals((await response.json()).error, "rejected");
});

Deno.test("the PostgREST adapter sends the exact RPC shape and parses one row", async () => {
  const originalFetch = globalThis.fetch;
  let capturedUrl = "";
  let capturedBody: Record<string, unknown> = {};
  let capturedHeaders = new Headers();
  try {
    globalThis.fetch = (input, init) => {
      capturedUrl = String(input);
      capturedBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      capturedHeaders = new Headers(init?.headers);
      return Promise.resolve(
        new Response(
          JSON.stringify([{
            checkin_id: CHECK_IN,
            outcome: "accepted",
            dwell_seconds: 300,
            workout_overlap_seconds: 240,
            replayed: false,
          }]),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      );
    };

    const result = await postgrestCheckInDatabase({
      url: "https://database.example.test",
      serviceRoleKey: "sb_secret_staging",
      authorizationBearer: false,
    }).recordGeofenceCheckIn({
      userId: USER,
      contestId: CONTEST,
      geofenceId: GEOFENCE,
      clientCheckInId: CLIENT_CHECK_IN,
      payloadDigest: await sha256(utf8("signed body")),
      locations: [{
        observed_at: "2026-08-01T14:00:00.000Z",
        latitude: 41,
        longitude: -87,
        accuracy_meters: 5,
        is_simulated: false,
        is_produced_by_accessory: true,
      }, {
        observed_at: "2026-08-01T14:05:00.000Z",
        latitude: 41,
        longitude: -87,
        accuracy_meters: 5,
        is_simulated: false,
        is_produced_by_accessory: true,
      }],
      workoutId: WORKOUT,
      workoutStartedAt: "2026-08-01T14:00:00.000Z",
      workoutEndedAt: "2026-08-01T14:30:00.000Z",
      workoutActivityType: "running",
      workoutProvenance: "device",
      workoutSourceBundleId: "com.apple.health",
      keyId: device.keyId,
      signCount: 9,
    });

    assertEquals(
      capturedUrl,
      "https://database.example.test/rest/v1/rpc/record_geofence_checkin",
    );
    assertEquals(capturedHeaders.get("apikey"), "sb_secret_staging");
    assertEquals(capturedHeaders.get("authorization"), null);
    assertEquals(capturedBody["p_user_id"], USER);
    assertEquals(capturedBody["p_client_checkin_id"], CLIENT_CHECK_IN);
    assertEquals(capturedBody["p_locations"], [{
      observed_at: "2026-08-01T14:00:00.000Z",
      latitude: 41,
      longitude: -87,
      accuracy_meters: 5,
      is_simulated: false,
      is_produced_by_accessory: true,
    }, {
      observed_at: "2026-08-01T14:05:00.000Z",
      latitude: 41,
      longitude: -87,
      accuracy_meters: 5,
      is_simulated: false,
      is_produced_by_accessory: true,
    }]);
    assertEquals(capturedBody["p_workout_provenance"], "device");
    assertEquals(capturedBody["p_sign_count"], 9);
    assertEquals(result, {
      checkInId: CHECK_IN,
      outcome: "accepted",
      dwellSeconds: 300,
      workoutOverlapSeconds: 240,
      replayed: false,
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("the PostgREST adapter maps exclusion violations without leaking SQL detail", async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = () =>
      Promise.resolve(
        new Response(
          JSON.stringify({
            code: "23P01",
            message: "conflicting key contains (secret coordinates)",
          }),
          { status: 409, headers: { "content-type": "application/json" } },
        ),
      );

    let failure: unknown;
    try {
      await postgrestCheckInDatabase({
        url: "https://database.example.test",
        serviceRoleKey: "service-role-secret",
      }).recordGeofenceCheckIn({
        userId: USER,
        contestId: CONTEST,
        geofenceId: GEOFENCE,
        clientCheckInId: CLIENT_CHECK_IN,
        payloadDigest: await sha256(utf8("signed body")),
        locations: [],
        workoutId: WORKOUT,
        workoutStartedAt: "2026-08-01T14:00:00.000Z",
        workoutEndedAt: "2026-08-01T14:30:00.000Z",
        workoutActivityType: "running",
        workoutProvenance: "device",
      });
    } catch (error) {
      failure = error;
    }

    assertEquals(failure instanceof HttpFailure, true);
    if (!(failure instanceof HttpFailure)) throw new Error("expected HttpFailure");
    assertEquals(failure.kind, "rejected");
    assertEquals(failure.message, "this check-in overlaps another recorded check-in");
    assertEquals(failure.message.includes("secret coordinates"), false);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("unexpected database failures become secretless 500 responses", async () => {
  const sink = recorder(
    new Error("connection to 10.0.0.5 refused, password=super-secret"),
  );
  const response = await createIngestCheckInHandler(deps({ database: sink.database }))(
    await signedRequest(),
  );
  assertEquals(response.status, 500);
  const text = await response.text();
  assertEquals(text.includes("10.0.0.5"), false);
  assertEquals(text.includes("super-secret"), false);
});
