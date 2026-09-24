import { assertEquals } from "@std/assert";
import { createAccessTokenVerifier } from "../_shared/jwt.ts";
import { ServiceRpcError } from "../_shared/service_rpc.ts";
import { mintAccessToken, TEST_JWT_SECRET } from "../_test/tokens.ts";
import type { PersonalStripeSetupGateway } from "../personal-payment-setup/handler.ts";
import { commitmentRefusal } from "./database.ts";
import {
  type BegunCommitmentSetup,
  type CommitmentSetupDatabase,
  createCommitmentSetupHandler,
} from "./handler.ts";

const USER = "11111111-1111-1111-1111-111111111111";
const REQUEST = "22222222-2222-2222-2222-222222222222";
const SETUP = "33333333-3333-3333-3333-333333333333";
const CUSTOMER = "cus_sandbox";
const INTENT = "seti_sandbox";

async function request(body: Record<string, unknown> = { requestId: REQUEST, amountCents: 2_000 }) {
  return new Request("https://example.test/challenge-commitment-setup", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${await mintAccessToken(USER)}`,
    },
    body: JSON.stringify(body),
  });
}

function fixture(options: {
  readonly begun?: BegunCommitmentSetup;
  readonly status?: string;
  readonly livemode?: boolean;
  readonly beginError?: unknown;
} = {}) {
  const calls: string[] = [];
  const records: unknown[] = [];
  const database: CommitmentSetupDatabase = {
    beginSetup(args) {
      calls.push(`begin:${args.actorId}:${args.requestId}:${args.amountCents}`);
      if (options.beginError !== undefined) return Promise.reject(options.beginError);
      return Promise.resolve(options.begun ?? { setupId: SETUP, status: "pending_provider" });
    },
    recordCustomer(args) {
      calls.push(`customer:${args.stripeCustomerId}`);
      return Promise.resolve();
    },
    recordSetup(args) {
      records.push(args);
      return Promise.resolve({
        status: args.status === "succeeded" ? "succeeded" : "pending_provider",
      });
    },
  };
  const setup = {
    id: INTENT,
    clientSecret: `${INTENT}_secret_example`,
    customerId: CUSTOMER,
    paymentMethodId: "pm_sandbox",
    livemode: options.livemode ?? false,
    status: options.status ?? "requires_payment_method",
  };
  const stripe: PersonalStripeSetupGateway = {
    createCustomer(args) {
      calls.push(`createCustomer:${args.idempotencyKey}`);
      return Promise.resolve({ id: CUSTOMER, livemode: false });
    },
    createSetupIntent(args) {
      calls.push(`createSetupIntent:${args.idempotencyKey}`);
      return Promise.resolve(setup);
    },
    retrieveSetupIntent(id) {
      calls.push(`retrieve:${id}`);
      return Promise.resolve(setup);
    },
  };
  const handler = createCommitmentSetupHandler({
    database,
    stripe,
    publishableKey: "pk_test_sandbox",
    verifyToken: createAccessTokenVerifier(TEST_JWT_SECRET),
  });
  return { handler, calls, records };
}

Deno.test("starts a card setup without charging anything", async () => {
  const { handler, calls, records } = fixture();
  const response = await handler(await request());
  assertEquals(response.status, 201);
  assertEquals(await response.json(), {
    setupId: SETUP,
    publishableKey: "pk_test_sandbox",
    setupIntentClientSecret: `${INTENT}_secret_example`,
    status: "pending_provider",
  });
  assertEquals(calls, [
    `begin:${USER}:${REQUEST}:2000`,
    `createCustomer:gt:challenge-commitment-customer:v1:${USER}`,
    `customer:${CUSTOMER}`,
    `createSetupIntent:gt:challenge-commitment-setup:v1:${SETUP}`,
  ]);
  assertEquals(records, [{
    actorId: USER,
    setupId: SETUP,
    stripeSetupIntentId: INTENT,
    status: "requires_payment_method",
  }]);
});

Deno.test("the second call re-reads Stripe and records the saved card", async () => {
  const { handler, calls, records } = fixture({
    begun: {
      setupId: SETUP,
      status: "pending_provider",
      stripeCustomerId: CUSTOMER,
      stripeSetupIntentId: INTENT,
    },
    status: "succeeded",
  });
  const response = await handler(await request());
  assertEquals(response.status, 200);
  assertEquals((await response.json()).status, "succeeded");
  assertEquals(calls, [`begin:${USER}:${REQUEST}:2000`, `retrieve:${INTENT}`]);
  assertEquals(records, [{
    actorId: USER,
    setupId: SETUP,
    stripeSetupIntentId: INTENT,
    stripePaymentMethodId: "pm_sandbox",
    status: "succeeded",
  }]);
});

Deno.test("refuses a live SetupIntent", async () => {
  const { handler, records } = fixture({ livemode: true });
  const response = await handler(await request());
  assertEquals(response.status, 500);
  assertEquals(records, []);
});

Deno.test("refuses amounts outside $1 to $50 in whole dollars", async () => {
  for (const amountCents of [0, 50, 250, 5_100]) {
    const { handler, calls } = fixture();
    const response = await handler(await request({ requestId: REQUEST, amountCents }));
    assertEquals(response.status, 400);
    assertEquals(calls, []);
  }
  const { handler } = fixture();
  assertEquals(
    (await handler(await request({ requestId: REQUEST, amountCents: 2_000, extra: 1 }))).status,
    400,
  );
});

Deno.test("passes database refusals through as reasons the app can explain", async () => {
  const cases: Array<[string, number, string]> = [
    ["42501", 403, "challenge_commitment_unavailable"],
    ["55000", 422, "challenge_commitment_unpaid"],
    ["23505", 422, "challenge_commitment_limit"],
  ];
  for (const [code, status, reason] of cases) {
    const { handler } = fixture({
      beginError: commitmentRefusal(
        new ServiceRpcError("challenge_commitment_begin_setup_service_v1", 400, code),
      ),
    });
    const response = await handler(await request());
    assertEquals(response.status, status);
    assertEquals((await response.json()).message, reason);
  }
});

Deno.test("a consumed setup is reported without touching Stripe", async () => {
  const { handler, calls } = fixture({ begun: { setupId: SETUP, status: "consumed" } });
  const response = await handler(await request());
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { setupId: SETUP, status: "consumed" });
  assertEquals(calls, [`begin:${USER}:${REQUEST}:2000`]);
});
