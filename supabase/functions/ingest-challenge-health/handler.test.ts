import { assertEquals } from "@std/assert";
import { createAccessTokenVerifier } from "../_shared/jwt.ts";
import { sha256, toHex, utf8 } from "../_shared/bytes.ts";
import { buildAssertion, makeDevice } from "../_test/appattest_fixtures.ts";
import { mintAccessToken, TEST_JWT_SECRET } from "../_test/tokens.ts";
import {
  createIngestChallengeHealthHandler,
  type RealHealthIngestArgs,
  type RealHealthReadinessArgs,
} from "./handler.ts";

const actor = "11111111-1111-1111-1111-111111111111";
const session = "22222222-2222-2222-2222-222222222222";
const appId = "ABCDE12345.test.gametime.app";
const at = new Date("2026-09-19T12:00:00Z");
const device = await makeDevice();
const base = {
  contract_version: 1,
  actor_id: actor,
  challenge_id: "33333333-3333-3333-3333-333333333333",
  agreement_version: 1,
  terms_digest: "a".repeat(64),
  source_policy_version: "apple_watch_steps_v1",
  metric: "steps",
  window_starts_at: "2026-09-19T00:00:00Z",
  window_ends_at: "2026-09-20T00:00:00Z",
  request_id: "44444444-4444-4444-4444-444444444444",
  revision: 1,
  previous_revision: null,
  state: "value",
  value: 100,
  observed_at: "2026-09-19T12:00:00Z",
  queried_through_at: "2026-09-19T12:00:00Z",
};
const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));

async function run(body: Record<string, unknown> = base, options: {
  claims?: Record<string, unknown>;
  unsigned?: boolean;
  tampered?: boolean;
  wrongApp?: boolean;
  enabled?: boolean;
  missingKey?: boolean;
  whitespace?: boolean;
} = {}) {
  const claims = options.claims ??
    { sub: actor, role: "authenticated", session_id: session, exp: at.getTime() / 1000 + 300 };
  const token = await mintAccessToken(actor, { claims });
  const exact = JSON.stringify(body, null, options.whitespace ? 2 : undefined);
  const signed = await buildAssertion(device, utf8(exact), {
    signCount: 7,
    appId: options.wrongApp ? "WRONG.test.app" : appId,
  });
  const calls: RealHealthIngestArgs[] = [];
  const readinessCalls: RealHealthReadinessArgs[] = [];
  const handler = createIngestChallengeHealthHandler({
    enabled: options.enabled ?? true,
    appId,
    verifyToken: createAccessTokenVerifier(TEST_JWT_SECRET),
    now: () => at,
    publicKeyFor: () => Promise.resolve(options.missingKey ? undefined : device.publicKey),
    ingest: (args) => {
      calls.push(args);
      return Promise.resolve({ request_id: args.payload.request_id });
    },
    readiness: (args) => {
      readinessCalls.push(args);
      return Promise.resolve({ request_id: args.payload.request_id });
    },
  });
  const response = await handler(
    new Request("https://local.test/ingest-challenge-health", {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        ...(options.unsigned ? {} : {
          "x-gametime-key-id": b64(device.keyId),
          "x-gametime-assertion": b64(signed.assertionObject),
        }),
      },
      body: options.tampered ? exact.replace('"value":100', '"value":101') : exact,
    }),
  );
  await response.body?.cancel();
  return { status: response.status, calls, readinessCalls, exact };
}

const readiness = {
  contract_version: 1,
  actor_id: actor,
  source_policy_version: "apple_watch_steps_v1",
  observed_at: "2026-09-19T12:00:00Z",
  request_id: "55555555-5555-5555-5555-555555555555",
};

Deno.test("P8 attested readiness binds the actor, source policy and exact bytes without history", async () => {
  const result = await run(readiness, { whitespace: true, enabled: false });
  assertEquals(result.status, 200);
  assertEquals(result.calls, []);
  const call = result.readinessCalls[0]!;
  assertEquals(call.payload, readiness);
  assertEquals(call.sessionID, session);
  assertEquals(call.recoveryOnly, true);
  assertEquals(toHex(call.payloadDigest), toHex(await sha256(utf8(result.exact))));
});

for (
  const change of [
    { history: [] },
    { baseline: 100 },
    { ready: true },
    { complete: true },
    { source_policy_version: "any_watch" },
    { observed_at: "2026-02-30T00:00:00Z" },
  ]
) {
  Deno.test(`P8 rejects readiness fields ${JSON.stringify(change)}`, async () => {
    const result = await run({ ...readiness, ...change });
    assertEquals(result.status, 400);
    assertEquals(result.calls, []);
    assertEquals(result.readinessCalls, []);
  });
}

Deno.test("P8 signs and hashes the exact normalized bytes, binding live session and expiry", async () => {
  const result = await run(base, { whitespace: true });
  assertEquals(result.status, 200);
  assertEquals(result.calls.length, 1);
  const call = result.calls[0]!;
  assertEquals(toHex(call.payloadDigest), toHex(await sha256(utf8(result.exact))));
  assertEquals(call.sessionID, session);
  assertEquals(call.tokenExpiresAt, "2026-09-19T12:05:00.000Z");
  assertEquals(call.signCount, 7);
  assertEquals(call.recoveryOnly, false);
});

Deno.test("P8 closed Edge gate delegates only exact committed recovery", async () => {
  const result = await run(base, { enabled: false });
  assertEquals(result.calls[0]?.recoveryOnly, true);
});

Deno.test("P8 Exercise lineage limitation refuses real readiness and positive credit", async () => {
  assertEquals(
    (await run({ ...readiness, source_policy_version: "apple_watch_exercise_v1" })).status,
    400,
  );
  assertEquals(
    (await run({ ...base, metric: "exercise", source_policy_version: "apple_watch_exercise_v1" }))
      .status,
    400,
  );
  const unresolved = await run({
    ...base,
    metric: "exercise",
    source_policy_version: "apple_watch_exercise_v1",
    state: "unresolved",
    value: null,
  });
  assertEquals(unresolved.status, 200);
  assertEquals(unresolved.calls[0]?.payload.value, null);
});

Deno.test("P8 cumulative outdoor running keeps whole millimetres and policy binding", async () => {
  const runBody = {
    ...base,
    metric: "distance",
    source_policy_version: "apple_workout_outdoor_distance_v1",
    value: 5_000_001,
  };
  const result = await run(runBody);
  assertEquals(result.status, 200);
  assertEquals(result.calls[0]?.payload.value, 5_000_001);
  assertEquals((await run({ ...runBody, value: 5_000_001.1 })).status, 400);
  assertEquals(
    (await run({ ...runBody, source_policy_version: "apple_watch_steps_v1" })).status,
    400,
  );
  assertEquals(
    (await run({ ...readiness, source_policy_version: "apple_workout_outdoor_distance_v1" }))
      .status,
    200,
  );
});

Deno.test("P8 timed uploads and readiness bind one selected distance without workout details", async () => {
  const timed = {
    ...base,
    metric: "timed",
    source_policy_version: "apple_workout_outdoor_timed_v1",
    distance_mm: 5_000_000,
    value: 1501,
  };
  const accepted = await run(timed);
  assertEquals(accepted.status, 200);
  assertEquals(accepted.calls[0]?.payload.distance_mm, 5_000_000);
  assertEquals(accepted.calls[0]?.payload.value, 1501);
  const timedReadiness = {
    ...readiness,
    source_policy_version: timed.source_policy_version,
    distance_mm: 5_000_000,
  };
  assertEquals((await run(timedReadiness)).readinessCalls[0]?.payload.distance_mm, 5_000_000);
  const { distance_mm: _distance, ...missingDistance } = timed;
  assertEquals((await run(missingDistance)).status, 400);
  assertEquals(
    (await run({ ...readiness, source_policy_version: timed.source_policy_version })).status,
    400,
  );
  for (const distance of [null, 0, -1, 5_000_000.1, 1_000_000_001]) {
    assertEquals((await run({ ...timed, distance_mm: distance })).status, 400);
    assertEquals((await run({ ...timedReadiness, distance_mm: distance })).status, 400);
  }
  assertEquals((await run({ ...base, distance_mm: 5_000_000 })).status, 400);
  assertEquals((await run({ ...readiness, distance_mm: 5_000_000 })).status, 400);
});

for (
  const [label, change] of Object.entries({
    "raw records": { records: [] },
    "routes": { route: [] },
    "source names": { source_name: "Watch" },
    "baselines": { baseline: 100 },
    "complete": { complete: true },
    "qualification": { qualified: true },
    "final": { final: true },
    "arbitrary policy": { source_policy_version: "anything" },
    "wrong metric": { metric: "exercise" },
    "wrong version": { contract_version: 2 },
    "zero": { value: 0 },
    "fractional activity": { value: 1.1 },
    "unsafe integer": { value: 2 ** 53 },
    "over contract value": { value: 1_000_000_001 },
    "over contract revision": { revision: 2_147_483_648, previous_revision: 2_147_483_647 },
    "over contract agreement version": { agreement_version: 2_147_483_648 },
    "negative": { value: -1 },
    "invalid deletion": { state: "deleted", value: 100 },
    "invalid unresolved": { state: "unresolved", value: 100 },
    "revision gap": { revision: 3, previous_revision: 1 },
    "wrong parent": { revision: 1, previous_revision: 0 },
    "future query": { queried_through_at: "2026-09-20T00:00:01Z" },
    "impossible date": { observed_at: "2026-02-30T00:00:00Z" },
    "reversed window": { window_starts_at: "2026-09-21T00:00:00Z" },
    "bad digest": { terms_digest: "Z".repeat(64) },
  })
) {
  Deno.test(`P8 rejects ${label} before database`, async () => {
    const result = await run({ ...base, ...change });
    assertEquals(result.status, 400);
    assertEquals(result.calls.length, 0);
  });
}

for (const state of ["deleted", "unresolved"]) {
  Deno.test(`P8 preserves explicit ${state} without zero`, async () => {
    assertEquals((await run({ ...base, state, value: null })).status, 200);
  });
}
for (
  const [label, options] of Object.entries({
    "missing assertion": { unsigned: true },
    "altered bytes": { tampered: true },
    "different app": { wrongApp: true },
    "missing key": { missingKey: true },
    "missing session": {
      claims: { sub: actor, role: "authenticated", exp: at.getTime() / 1000 + 300 },
    },
    "expired JWT": {
      claims: {
        sub: actor,
        role: "authenticated",
        session_id: session,
        exp: at.getTime() / 1000 - 1,
      },
    },
    "service caller": {
      claims: {
        sub: actor,
        role: "service_role",
        session_id: session,
        exp: at.getTime() / 1000 + 300,
      },
    },
  })
) {
  Deno.test(`P8 refuses ${label}`, async () => {
    const result = await run(base, options);
    assertEquals(result.status, 401);
    assertEquals(result.calls.length, 0);
  });
}
Deno.test("P8 refuses a different actor", async () => {
  const result = await run({ ...base, actor_id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" });
  assertEquals(result.status, 403);
  assertEquals(result.calls.length, 0);
});
