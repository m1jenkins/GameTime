import { assertEquals } from "@std/assert";
import { type Bytes, sha256, toHex, utf8 } from "../_shared/bytes.ts";
import { createAccessTokenVerifier } from "../_shared/jwt.ts";
import { buildAssertion, type Device, makeDevice } from "../_test/appattest_fixtures.ts";
import { mintAccessToken, TEST_JWT_SECRET } from "../_test/tokens.ts";
import {
  COVERAGE_ASSERTION_HEADER,
  COVERAGE_KEY_ID_HEADER,
  createPersonalCoverageHandler,
  type PersonalCoverageDatabase,
  type PersonalCoverageDeps,
  type RecordPersonalCoverageArgs,
} from "./handler.ts";

const APP_ID = "ABCDE12345.test.gametime.app";
const USER = "11111111-1111-1111-1111-111111111111";
const CHALLENGE = "a1000001-0000-0000-0000-000000000001";
const COVERAGE = "c1000001-0000-0000-0000-000000000001";
const device: Device = await makeDevice();

function base64(bytes: Bytes): string {
  return btoa(String.fromCharCode(...bytes));
}

interface Recorder {
  readonly database: PersonalCoverageDatabase;
  readonly calls: RecordPersonalCoverageArgs[];
}

function recorder(replayed = false): Recorder {
  const calls: RecordPersonalCoverageArgs[] = [];
  return {
    calls,
    database: {
      recordPersonalCoverage(args) {
        calls.push(args);
        return Promise.resolve({
          coverageBatchId: "c2000001-0000-0000-0000-000000000001",
          replayed,
        });
      },
    },
  };
}

function deps(overrides: Partial<PersonalCoverageDeps> = {}): PersonalCoverageDeps {
  return {
    database: recorder().database,
    appId: APP_ID,
    verifyToken: createAccessTokenVerifier(TEST_JWT_SECRET),
    publicKeyFor: () => Promise.resolve(device.publicKey),
    ...overrides,
  };
}

async function signedRequest(options: {
  readonly coveredIntervalStarts?: unknown[];
  readonly omitAssertion?: boolean;
  readonly assertionExtensions?: boolean;
  readonly tamperWith?: (body: Record<string, unknown>) => void;
} = {}): Promise<Request> {
  const body: Record<string, unknown> = {
    challengeId: CHALLENGE,
    clientCoverageId: COVERAGE,
    observedAt: "2026-08-01T15:05:00.000Z",
    coveredIntervalStarts: options.coveredIntervalStarts ?? [
      "2026-08-01T13:00:00.000Z",
      "2026-08-01T14:00:00.000Z",
    ],
  };
  const headers: Record<string, string> = {
    "content-type": "application/json",
    authorization: `Bearer ${await mintAccessToken(USER)}`,
  };
  if (!options.omitAssertion) {
    const assertion = await buildAssertion(device, utf8(JSON.stringify(body)), {
      signCount: 7,
      ...(options.assertionExtensions === true
        ? {
          assertionExtensions: {
            validationCategory: 3,
            bundleVersion: "1",
          },
        }
        : {}),
    });
    headers[COVERAGE_KEY_ID_HEADER] = base64(device.keyId);
    headers[COVERAGE_ASSERTION_HEADER] = base64(assertion.assertionObject);
  }
  options.tamperWith?.(body);
  return new Request("https://example.test/personal-sync-coverage", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

Deno.test("records current extended assertion coverage", async () => {
  const sink = recorder();
  const handler = createPersonalCoverageHandler(deps({ database: sink.database }));
  const request = await signedRequest({ assertionExtensions: true });
  const raw = new Uint8Array(await request.clone().arrayBuffer());

  const response = await handler(request);
  assertEquals(response.status, 201);
  assertEquals(await response.json(), {
    coverageBatchId: "c2000001-0000-0000-0000-000000000001",
    replayed: false,
  });
  assertEquals(sink.calls.length, 1);
  assertEquals(sink.calls[0]!.userId, USER);
  assertEquals(sink.calls[0]!.challengeId, CHALLENGE);
  assertEquals(sink.calls[0]!.coveredIntervalStarts, [
    "2026-08-01T13:00:00.000Z",
    "2026-08-01T14:00:00.000Z",
  ]);
  assertEquals(sink.calls[0]!.signCount, 7);
  assertEquals(toHex(sink.calls[0]!.payloadDigest), toHex(await sha256(raw)));
});

Deno.test("returns an exact coverage retry as a replay", async () => {
  const sink = recorder(true);
  const handler = createPersonalCoverageHandler(deps({ database: sink.database }));
  const response = await handler(await signedRequest());
  assertEquals(response.status, 200);
  assertEquals((await response.json()).replayed, true);
});

Deno.test("does not accept unattested coverage", async () => {
  const sink = recorder();
  const handler = createPersonalCoverageHandler(deps({ database: sink.database }));
  const response = await handler(await signedRequest({ omitAssertion: true }));
  assertEquals(response.status, 400);
  assertEquals(sink.calls.length, 0);
});

Deno.test("maps malformed coverage assertion headers to a client error", async () => {
  for (const header of [COVERAGE_KEY_ID_HEADER, COVERAGE_ASSERTION_HEADER]) {
    const sink = recorder();
    const handler = createPersonalCoverageHandler(deps({ database: sink.database }));
    const request = await signedRequest();
    request.headers.set(header, "%not-base64%");

    const response = await handler(request);
    assertEquals(response.status, 400);
    assertEquals(sink.calls.length, 0);
  }
});

Deno.test("requires a nonempty unique coverage set", async () => {
  const handler = createPersonalCoverageHandler(deps());
  assertEquals(
    (await handler(await signedRequest({ coveredIntervalStarts: [] }))).status,
    400,
  );
  assertEquals(
    (await handler(
      await signedRequest({
        coveredIntervalStarts: [
          "2026-08-01T14:00:00.000Z",
          "2026-08-01T14:00:00Z",
        ],
      }),
    )).status,
    400,
  );
});

Deno.test("refuses coverage bytes altered after signing", async () => {
  const sink = recorder();
  const handler = createPersonalCoverageHandler(deps({ database: sink.database }));
  const response = await handler(
    await signedRequest({
      tamperWith(body) {
        (body["coveredIntervalStarts"] as string[]).push(
          "2026-08-01T15:00:00.000Z",
        );
      },
    }),
  );
  assertEquals(response.status, 401);
  assertEquals(sink.calls.length, 0);
});
