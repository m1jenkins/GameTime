import { assertEquals, assertRejects } from "@std/assert";
import { stub } from "@std/testing/mock";
import { HttpFailure } from "../_shared/http.ts";
import { realHealthDatabase, realHealthReadinessDatabase } from "./database.ts";
import type { RealHealthIngestArgs, RealHealthReadinessArgs } from "./handler.ts";

const config = { url: "https://local.test", serviceRoleKey: "local-test-only" };
const args: RealHealthIngestArgs = {
  payload: {
    contract_version: 1,
    actor_id: "11111111-1111-1111-1111-111111111111",
    challenge_id: "22222222-2222-2222-2222-222222222222",
    agreement_version: 1,
    terms_digest: "a".repeat(64),
    source_policy_version: "apple_watch_steps_v1",
    metric: "steps",
    window_starts_at: "2026-09-19T00:00:00Z",
    window_ends_at: "2026-09-20T00:00:00Z",
    request_id: "33333333-3333-3333-3333-333333333333",
    revision: 1,
    previous_revision: null,
    state: "value",
    value: 100,
    observed_at: "2026-09-19T12:00:00Z",
    queried_through_at: "2026-09-19T12:00:00Z",
  },
  sessionID: "44444444-4444-4444-4444-444444444444",
  tokenExpiresAt: "2026-09-19T13:00:00Z",
  keyID: new Uint8Array(32).fill(1),
  signCount: 7,
  payloadDigest: new Uint8Array(32).fill(2),
  recoveryOnly: false,
};
const receipt = {
  version: "challenge_real_health_receipt_v1",
  challenge_id: args.payload.challenge_id,
  request_id: args.payload.request_id,
  revision: 1,
  accepted_at: "2026-09-19T12:00:00Z",
};

Deno.test("P8 database adapter binds session, digest and counter with explicit service credentials", async () => {
  const mock = stub(globalThis, "fetch", (input, init) => {
    assertEquals(input, config.url + "/rest/v1/rpc/challenge_real_health_ingest_v1");
    assertEquals(init?.redirect, "error");
    assertEquals(new Headers(init?.headers).get("authorization"), "Bearer local-test-only");
    const body = JSON.parse(init?.body as string);
    assertEquals(body, {
      p_request_id: args.payload.request_id,
      p_payload: args.payload,
      p_session_id: args.sessionID,
      p_token_expires_at: args.tokenExpiresAt,
      p_device_key_id: "\\x" + "01".repeat(32),
      p_assertion_counter: 7,
      p_payload_digest: "\\x" + "02".repeat(32),
      p_recovery_only: false,
    });
    return Promise.resolve(Response.json(receipt));
  });
  try {
    assertEquals(await realHealthDatabase(config)(args), receipt);
  } finally {
    mock.restore();
  }
});

Deno.test("P8 readiness database adapter forwards only minimal readiness fields", async () => {
  const ready: RealHealthReadinessArgs = {
    ...args,
    recoveryOnly: true,
    payload: {
      contract_version: 1,
      actor_id: args.payload.actor_id,
      source_policy_version: args.payload.source_policy_version,
      observed_at: args.payload.observed_at,
      request_id: args.payload.request_id,
    },
  };
  const response = {
    version: "challenge_real_health_readiness_receipt_v1",
    request_id: ready.payload.request_id,
    accepted_at: receipt.accepted_at,
  };
  const mock = stub(globalThis, "fetch", (input, init) => {
    assertEquals(input, config.url + "/rest/v1/rpc/challenge_real_health_readiness_v1");
    const body = JSON.parse(init?.body as string);
    assertEquals(body.p_actor_id, ready.payload.actor_id);
    assertEquals(body.p_source_policy_version, "apple_watch_steps_v1");
    assertEquals(body.p_observed_at, ready.payload.observed_at);
    assertEquals(body.p_recovery_only, true);
    assertEquals(Object.keys(body).length, 10);
    return Promise.resolve(Response.json(response));
  });
  try {
    assertEquals(await realHealthReadinessDatabase(config)(ready), response);
  } finally {
    mock.restore();
  }
});

for (
  const change of [
    { actor_id: args.payload.actor_id },
    { raw: [123] },
    { revision: 2 },
    { request_id: args.sessionID },
    { challenge_id: args.sessionID },
    { accepted_at: null },
  ]
) {
  Deno.test(`P8 refuses unexpected receipt ${JSON.stringify(change)}`, async () => {
    const mock = stub(
      globalThis,
      "fetch",
      () => Promise.resolve(Response.json({ ...receipt, ...change })),
    );
    try {
      await assertRejects(() => realHealthDatabase(config)(args), HttpFailure);
    } finally {
      mock.restore();
    }
  });
}

for (
  const [code, expected] of [["42501", "forbidden"], ["22023", "rejected"], ["XX000", "internal"]]
) {
  Deno.test(`P8 strips private database error content for ${code}`, async () => {
    const mock = stub(globalThis, "fetch", () =>
      Promise.resolve(Response.json({
        code,
        message: "private values 12345",
        details: args.payload,
      }, { status: 400 })));
    try {
      const error = await assertRejects(() => realHealthDatabase(config)(args), HttpFailure);
      assertEquals(error.kind, expected);
      assertEquals(error.message.includes("12345"), false);
      assertEquals(error.detail, undefined);
    } finally {
      mock.restore();
    }
  });
}
