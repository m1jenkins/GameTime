import { assertEquals } from "@std/assert";
import { createAccessTokenVerifier } from "../_shared/jwt.ts";
import {
  PERSONAL_STRIPE_AGREEMENT_VERSION,
  PERSONAL_STRIPE_CONSENT_VERSION,
} from "../_shared/personal_stripe_contract.ts";
import { mintAccessToken, TEST_JWT_SECRET } from "../_test/tokens.ts";
import {
  type BegunPersonalStripeSetup,
  createPersonalStripeSetupHandler,
  type PersonalStripeSetupDatabase,
  type PersonalStripeSetupDeps,
  type PersonalStripeSetupGateway,
} from "./handler.ts";

const USER = "11111111-1111-1111-1111-111111111111";
const REQUEST = "22222222-2222-2222-2222-222222222222";
const SETUP = "33333333-3333-3333-3333-333333333333";
const CUSTOMER = "cus_sandbox";
const INTENT = "seti_sandbox";

function body() {
  return {
    requestId: REQUEST,
    cadence: "daily",
    targetSteps: 10_000,
    commitmentAmountMinor: 2_000,
    currency: "USD",
    timezone: "America/Chicago",
    requestedStartsAt: "2026-08-06T15:00:00Z",
    agreementVersion: PERSONAL_STRIPE_AGREEMENT_VERSION,
    consentVersion: PERSONAL_STRIPE_CONSENT_VERSION,
    consentAccepted: true,
  };
}

async function request(
  overrides: Record<string, unknown> = {},
  token?: string | null,
): Promise<Request> {
  const accessToken = token === undefined ? await mintAccessToken(USER) : token;
  return new Request("https://example.test/personal-payment-setup", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(accessToken === null ? {} : { authorization: `Bearer ${accessToken}` }),
    },
    body: JSON.stringify({ ...body(), ...overrides }),
  });
}

interface DatabaseRecorder {
  readonly database: PersonalStripeSetupDatabase;
  readonly calls: Array<{ readonly name: string; readonly args: unknown }>;
}

function databaseRecorder(
  begun: BegunPersonalStripeSetup = {
    setupId: SETUP,
    replayed: false,
  },
): DatabaseRecorder {
  const calls: Array<{ readonly name: string; readonly args: unknown }> = [];
  return {
    calls,
    database: {
      beginSetup(args) {
        calls.push({ name: "begin", args });
        return Promise.resolve(begun);
      },
      recordCustomer(args) {
        calls.push({ name: "customer", args });
        return Promise.resolve();
      },
      recordSetup(args) {
        calls.push({ name: "setup", args });
        return Promise.resolve();
      },
    },
  };
}

interface StripeRecorder {
  readonly gateway: PersonalStripeSetupGateway;
  readonly calls: Array<{ readonly name: string; readonly args: unknown }>;
}

function stripeRecorder(
  options: {
    readonly customerLivemode?: boolean;
    readonly setupLivemode?: boolean;
    readonly status?: string;
  } = {},
): StripeRecorder {
  const calls: Array<{ readonly name: string; readonly args: unknown }> = [];
  const setup = {
    id: INTENT,
    clientSecret: `${INTENT}_secret_example`,
    customerId: CUSTOMER,
    paymentMethodId: "pm_sandbox",
    livemode: options.setupLivemode ?? false,
    status: options.status ?? "requires_payment_method",
  };
  return {
    calls,
    gateway: {
      createCustomer(args) {
        calls.push({ name: "createCustomer", args });
        return Promise.resolve({
          id: CUSTOMER,
          livemode: options.customerLivemode ?? false,
        });
      },
      createSetupIntent(args) {
        calls.push({ name: "createSetupIntent", args });
        return Promise.resolve(setup);
      },
      retrieveSetupIntent(id) {
        calls.push({ name: "retrieveSetupIntent", args: id });
        return Promise.resolve(setup);
      },
    },
  };
}

function deps(
  database: PersonalStripeSetupDatabase,
  stripe: PersonalStripeSetupGateway,
): PersonalStripeSetupDeps {
  return {
    database,
    stripe,
    publishableKey: "pk_test_sandbox",
    verifyToken: createAccessTokenVerifier(TEST_JWT_SECRET),
  };
}

Deno.test("creates a sandbox Customer and reusable SetupIntent", async () => {
  const database = databaseRecorder();
  const stripe = stripeRecorder();
  const handler = createPersonalStripeSetupHandler(
    deps(database.database, stripe.gateway),
  );

  const response = await handler(await request());
  assertEquals(response.status, 201);
  assertEquals(await response.json(), {
    setupId: SETUP,
    publishableKey: "pk_test_sandbox",
    setupIntentClientSecret: `${INTENT}_secret_example`,
    status: "pending_provider",
    replayed: false,
  });
  assertEquals(stripe.calls.map((call) => call.name), [
    "createCustomer",
    "createSetupIntent",
  ]);
  assertEquals(database.calls.map((call) => call.name), [
    "begin",
    "customer",
    "setup",
  ]);
  const begin = database.calls[0]!.args as Record<string, unknown>;
  assertEquals(begin["ownerId"], USER);
  assertEquals(begin["commitmentAmountMinor"], 2_000);
  const recordedSetup = database.calls[2]!.args as Record<string, unknown>;
  assertEquals(recordedSetup["status"], "pending_provider");
  assertEquals(recordedSetup["stripePaymentMethodId"], undefined);
});

Deno.test("an exact replay retrieves the same SetupIntent", async () => {
  const database = databaseRecorder({
    setupId: SETUP,
    replayed: true,
    stripeCustomerId: CUSTOMER,
    stripeSetupIntentId: INTENT,
  });
  const stripe = stripeRecorder({ status: "succeeded" });
  const handler = createPersonalStripeSetupHandler(
    deps(database.database, stripe.gateway),
  );

  const response = await handler(await request());
  assertEquals(response.status, 200);
  assertEquals((await response.json()).replayed, true);
  assertEquals(stripe.calls.map((call) => call.name), [
    "retrieveSetupIntent",
  ]);
  assertEquals(database.calls.map((call) => call.name), [
    "begin",
    "setup",
  ]);
});

Deno.test("a database beta-control refusal stops all Stripe setup work", async () => {
  const calls: string[] = [];
  const database: PersonalStripeSetupDatabase = {
    beginSetup() {
      calls.push("begin");
      return Promise.reject(new Error("database beta admission refused"));
    },
    recordCustomer() {
      calls.push("customer");
      return Promise.resolve();
    },
    recordSetup() {
      calls.push("setup");
      return Promise.resolve();
    },
  };
  const stripe = stripeRecorder();
  const handler = createPersonalStripeSetupHandler(
    deps(database, stripe.gateway),
  );

  const response = await handler(await request());
  assertEquals(response.status, 500);
  assertEquals(calls, ["begin"]);
  assertEquals(stripe.calls, []);
});

Deno.test("requires explicit current consent", async () => {
  const database = databaseRecorder();
  const stripe = stripeRecorder();
  const handler = createPersonalStripeSetupHandler(
    deps(database.database, stripe.gateway),
  );

  const response = await handler(
    await request({ consentAccepted: false }),
  );
  assertEquals(response.status, 400);
  assertEquals(database.calls.length, 0);
  assertEquals(stripe.calls.length, 0);
});

Deno.test("refuses a live Stripe object in the sandbox handler", async () => {
  for (
    const options of [
      { customerLivemode: true },
      { setupLivemode: true },
    ]
  ) {
    const database = databaseRecorder();
    const stripe = stripeRecorder(options);
    const handler = createPersonalStripeSetupHandler(
      deps(database.database, stripe.gateway),
    );

    const response = await handler(await request());
    assertEquals(response.status, 500);
    assertEquals(
      database.calls.some((call) => call.name === "setup"),
      false,
    );
  }
});

Deno.test("requires an authenticated GameTime user", async () => {
  const database = databaseRecorder();
  const stripe = stripeRecorder();
  const handler = createPersonalStripeSetupHandler(
    deps(database.database, stripe.gateway),
  );

  const response = await handler(await request({}, null));
  assertEquals(response.status, 401);
  assertEquals(database.calls.length, 0);
  assertEquals(stripe.calls.length, 0);
});
