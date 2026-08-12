import { assertEquals } from "@std/assert";
import { PERSONAL_HEALTH_STEP_DATA_POLICY } from "./handler.ts";
import { personalStripeCommitRpcName, postgrestPersonalStripeCommitDatabase } from "./database.ts";

const CONFIG = {
  url: "https://database.example.test",
  serviceRoleKey: "sb_secret_test",
  authorizationBearer: false,
} as const;

const COMMIT_ARGS = {
  ownerId: "11111111-1111-4111-8111-111111111111",
  setupId: "22222222-2222-4222-8222-222222222222",
  requestId: "33333333-3333-4333-8333-333333333333",
  cadence: "daily",
  targetSteps: 10_000,
  commitmentAmountMinor: 1_000,
  currency: "USD",
  timezone: "UTC",
  agreementVersion: "personal-stripe-sandbox-v1",
  consentVersion: "personal-stripe-sandbox-consent-v1",
} as const;

Deno.test("missing policy preserves the deployed Stripe v1 commit RPC", () => {
  assertEquals(
    personalStripeCommitRpcName(),
    "commit_personal_stripe_sandbox_challenge_service_v1",
  );
});

Deno.test("the exact Health policy selects the explicit Stripe v2 commit RPC", () => {
  assertEquals(
    personalStripeCommitRpcName(PERSONAL_HEALTH_STEP_DATA_POLICY),
    "commit_personal_stripe_sandbox_challenge_service_v2",
  );
});

Deno.test("the PostgREST adapter sends missing and Health policies to distinct RPCs", async () => {
  const originalFetch = globalThis.fetch;
  const requests: Array<{ url: string; body: Record<string, unknown> }> = [];

  try {
    globalThis.fetch = (input, init) => {
      requests.push({
        url: String(input),
        body: JSON.parse(String(init?.body)) as Record<string, unknown>,
      });
      return Promise.resolve(
        new Response(
          JSON.stringify({
            challenge_id: "44444444-4444-4444-8444-444444444444",
            replayed: false,
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      );
    };

    const database = postgrestPersonalStripeCommitDatabase(CONFIG);
    await database.commitChallenge(COMMIT_ARGS);
    await database.commitChallenge({
      ...COMMIT_ARGS,
      stepDataPolicy: PERSONAL_HEALTH_STEP_DATA_POLICY,
    });

    assertEquals(
      requests.map((request) => request.url),
      [
        "https://database.example.test/rest/v1/rpc/commit_personal_stripe_sandbox_challenge_service_v1",
        "https://database.example.test/rest/v1/rpc/commit_personal_stripe_sandbox_challenge_service_v2",
      ],
    );
    assertEquals(requests[0]!.body, requests[1]!.body);
    assertEquals(requests[0]!.body["p_owner_id"], COMMIT_ARGS.ownerId);
    assertEquals(requests[0]!.body["p_request_id"], COMMIT_ARGS.requestId);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
