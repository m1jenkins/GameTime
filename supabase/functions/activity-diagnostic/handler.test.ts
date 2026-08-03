import { assertEquals } from "@std/assert";
import { type Bytes, sha256, toHex, utf8 } from "../_shared/bytes.ts";
import { createAccessTokenVerifier } from "../_shared/jwt.ts";
import { buildAssertion, type Device, makeDevice } from "../_test/appattest_fixtures.ts";
import { mintAccessToken, TEST_JWT_SECRET } from "../_test/tokens.ts";
import {
  type ActivityDiagnosticDatabase,
  type ActivityDiagnosticDeps,
  createActivityDiagnosticHandler,
  DIAGNOSTIC_ASSERTION_HEADER,
  DIAGNOSTIC_KEY_ID_HEADER,
  type RecordActivityDiagnosticArgs,
} from "./handler.ts";

const APP_ID = "ABCDE12345.test.gametime.app";
const USER = "11111111-1111-1111-1111-111111111111";
const DIAGNOSTIC = "d1000001-0000-0000-0000-000000000001";
const device: Device = await makeDevice();

function base64(bytes: Bytes): string {
  return btoa(String.fromCharCode(...bytes));
}

interface Recorder {
  readonly database: ActivityDiagnosticDatabase;
  readonly calls: RecordActivityDiagnosticArgs[];
}

function recorder(replayed = false): Recorder {
  const calls: RecordActivityDiagnosticArgs[] = [];
  return {
    calls,
    database: {
      recordActivityDiagnostic(args) {
        calls.push(args);
        return Promise.resolve({
          diagnosticId: "d2000001-0000-0000-0000-000000000001",
          performedAt: "2026-08-01T15:05:00.000Z",
          replayed,
          clearedHold: true,
        });
      },
    },
  };
}

function deps(overrides: Partial<ActivityDiagnosticDeps> = {}): ActivityDiagnosticDeps {
  return {
    database: recorder().database,
    appId: APP_ID,
    verifyToken: createAccessTokenVerifier(TEST_JWT_SECRET),
    publicKeyFor: () => Promise.resolve(device.publicKey),
    ...overrides,
  };
}

async function signedRequest(options: {
  readonly trustedDeviceSampleCount?: number;
  readonly readStartedAt?: string;
  readonly readEndedAt?: string;
  readonly token?: string | null;
  readonly omitAssertion?: boolean;
  readonly signingKey?: CryptoKey;
  readonly tamperWith?: (body: Record<string, unknown>) => void;
} = {}): Promise<Request> {
  const body: Record<string, unknown> = {
    clientDiagnosticId: DIAGNOSTIC,
    observedAt: "2026-08-01T15:05:00.000Z",
    healthKitReadStartedAt: options.readStartedAt ?? "2026-08-01T15:00:00.000Z",
    healthKitReadEndedAt: options.readEndedAt ?? "2026-08-01T15:04:00.000Z",
    trustedDeviceSampleCount: options.trustedDeviceSampleCount ?? 3,
  };
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (options.token !== null) {
    headers.authorization = `Bearer ${options.token ?? await mintAccessToken(USER)}`;
  }
  if (!options.omitAssertion) {
    const assertion = await buildAssertion(device, utf8(JSON.stringify(body)), {
      signCount: 9,
      ...(options.signingKey === undefined ? {} : { signingKey: options.signingKey }),
    });
    headers[DIAGNOSTIC_KEY_ID_HEADER] = base64(device.keyId);
    headers[DIAGNOSTIC_ASSERTION_HEADER] = base64(assertion.assertionObject);
  }
  options.tamperWith?.(body);
  return new Request("https://example.test/activity-diagnostic", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

Deno.test("records an exact-byte App Attest backed HealthKit diagnostic", async () => {
  const sink = recorder();
  const handler = createActivityDiagnosticHandler(deps({ database: sink.database }));
  const request = await signedRequest();
  const raw = new Uint8Array(await request.clone().arrayBuffer());

  const response = await handler(request);
  assertEquals(response.status, 201);
  assertEquals(await response.json(), {
    diagnosticId: "d2000001-0000-0000-0000-000000000001",
    performedAt: "2026-08-01T15:05:00.000Z",
    replayed: false,
    clearedHold: true,
  });
  assertEquals(sink.calls.length, 1);
  assertEquals(sink.calls[0]!.userId, USER);
  assertEquals(sink.calls[0]!.trustedDeviceSampleCount, 3);
  assertEquals(sink.calls[0]!.signCount, 9);
  assertEquals(toHex(sink.calls[0]!.payloadDigest), toHex(await sha256(raw)));
});

Deno.test("returns an exact retry as a replay", async () => {
  const sink = recorder(true);
  const handler = createActivityDiagnosticHandler(deps({ database: sink.database }));
  const response = await handler(await signedRequest());
  assertEquals(response.status, 200);
  assertEquals((await response.json()).replayed, true);
});

Deno.test("does not allow an unattested development diagnostic", async () => {
  const sink = recorder();
  const handler = createActivityDiagnosticHandler(deps({ database: sink.database }));
  const response = await handler(await signedRequest({ omitAssertion: true }));
  assertEquals(response.status, 400);
  assertEquals(sink.calls.length, 0);
});

Deno.test("maps malformed diagnostic assertion headers to a client error", async () => {
  for (
    const header of [
      DIAGNOSTIC_KEY_ID_HEADER,
      DIAGNOSTIC_ASSERTION_HEADER,
    ]
  ) {
    const sink = recorder();
    const handler = createActivityDiagnosticHandler(deps({ database: sink.database }));
    const request = await signedRequest();
    request.headers.set(header, "%not-base64%");

    const response = await handler(request);
    assertEquals(response.status, 400);
    assertEquals(sink.calls.length, 0);
  }
});

Deno.test("requires a positive trusted-device sample", async () => {
  const sink = recorder();
  const handler = createActivityDiagnosticHandler(deps({ database: sink.database }));
  const response = await handler(
    await signedRequest({ trustedDeviceSampleCount: 0 }),
  );
  assertEquals(response.status, 400);
  assertEquals(sink.calls.length, 0);
});

Deno.test("requires a forward HealthKit read interval", async () => {
  const handler = createActivityDiagnosticHandler(deps());
  const response = await handler(
    await signedRequest({
      readStartedAt: "2026-08-01T15:04:00.000Z",
      readEndedAt: "2026-08-01T15:04:00.000Z",
    }),
  );
  assertEquals(response.status, 400);
});

Deno.test("refuses a diagnostic body altered after signing", async () => {
  const sink = recorder();
  const handler = createActivityDiagnosticHandler(deps({ database: sink.database }));
  const response = await handler(
    await signedRequest({
      tamperWith(body) {
        body["trustedDeviceSampleCount"] = 99;
      },
    }),
  );
  assertEquals(response.status, 401);
  assertEquals(sink.calls.length, 0);
});

Deno.test("refuses a diagnostic signed by another key", async () => {
  const other = await makeDevice();
  const sink = recorder();
  const handler = createActivityDiagnosticHandler(deps({ database: sink.database }));
  const response = await handler(
    await signedRequest({ signingKey: other.keys.privateKey }),
  );
  assertEquals(response.status, 401);
  assertEquals(sink.calls.length, 0);
});
