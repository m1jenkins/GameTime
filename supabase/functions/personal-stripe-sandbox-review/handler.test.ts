import { assertEquals, assertThrows } from "@std/assert";
import { createAccessTokenVerifier } from "../_shared/jwt.ts";
import { mintAccessToken, TEST_JWT_SECRET } from "../_test/tokens.ts";
import {
  createPersonalStripeReviewHandler,
  type PersonalStripeReviewDatabase,
  type PersonalStripeReviewDeps,
} from "./handler.ts";

const USER = "11111111-1111-4111-8111-111111111111";
const CHALLENGE = "22222222-2222-4222-8222-222222222222";

async function request(options: {
  readonly token?: string | null;
  readonly reasonCode?: string;
} = {}): Promise<Request> {
  const token = options.token === undefined ? await mintAccessToken(USER) : options.token;
  return new Request(
    "https://example.test/personal-stripe-sandbox-review",
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(token === null ? {} : { authorization: `Bearer ${token}` }),
      },
      body: JSON.stringify({
        challengeId: CHALLENGE,
        reasonCode: options.reasonCode ?? "user_disputes_step_data",
      }),
    },
  );
}

function fixture(replayed = false): {
  readonly deps: PersonalStripeReviewDeps;
  readonly calls: unknown[];
} {
  const calls: unknown[] = [];
  const database: PersonalStripeReviewDatabase = {
    requestReview(args) {
      calls.push(args);
      return Promise.resolve({
        reviewState: "under_review",
        reviewDeadline: "2026-08-20T12:00:00.000Z",
        replayed,
      });
    },
  };
  return {
    calls,
    deps: {
      deploymentEnvironment: "staging",
      database,
      verifyToken: createAccessTokenVerifier(TEST_JWT_SECRET),
    },
  };
}

Deno.test("an authenticated owner files a bounded review before charging", async () => {
  const value = fixture();
  const handler = createPersonalStripeReviewHandler(value.deps);
  const response = await handler(await request());

  assertEquals(response.status, 201);
  assertEquals(await response.json(), {
    reviewState: "under_review",
    reviewDeadline: "2026-08-20T12:00:00.000Z",
    replayed: false,
  });
  assertEquals(value.calls, [{
    ownerId: USER,
    challengeId: CHALLENGE,
    reasonCode: "user_disputes_step_data",
  }]);
});

Deno.test("an exact review retry is a replay", async () => {
  const value = fixture(true);
  const handler = createPersonalStripeReviewHandler(value.deps);
  const response = await handler(
    await request({
      reasonCode: "user_disputes_result",
    }),
  );

  assertEquals(response.status, 200);
  assertEquals((await response.json()).replayed, true);
});

Deno.test("review filing requires auth and a supported reason", async () => {
  for (
    const options of [
      { token: null, reasonCode: "user_disputes_step_data" },
      { token: undefined, reasonCode: "charge_me_twice" },
    ]
  ) {
    const value = fixture();
    const handler = createPersonalStripeReviewHandler(value.deps);
    const response = await handler(await request(options));
    assertEquals(response.status, options.token === null ? 401 : 400);
    assertEquals(value.calls, []);
  }
});

Deno.test("the sandbox review endpoint cannot boot in production", () => {
  const value = fixture();
  assertThrows(() =>
    createPersonalStripeReviewHandler({
      ...value.deps,
      deploymentEnvironment: "production",
    })
  );
});
