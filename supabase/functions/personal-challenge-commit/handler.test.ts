import { assertEquals } from "@std/assert";
import { createAccessTokenVerifier } from "../_shared/jwt.ts";
import {
  PERSONAL_STRIPE_AGREEMENT_VERSION,
  PERSONAL_STRIPE_CONSENT_VERSION,
} from "../_shared/personal_stripe_contract.ts";
import { mintAccessToken, TEST_JWT_SECRET } from "../_test/tokens.ts";
import type { PersonalStripeSetupGateway } from "../personal-payment-setup/handler.ts";
import {
  createPersonalStripeCommitHandler,
  type LoadPersonalStripeSetupArgs,
  type PersonalStripeCommitDatabase,
  type PersonalStripeCommitDeps,
} from "./handler.ts";

const USER = "11111111-1111-1111-1111-111111111111";
const REQUEST = "22222222-2222-2222-2222-222222222222";
const SETUP = "33333333-3333-3333-3333-333333333333";
const CHALLENGE = "44444444-4444-4444-4444-444444444444";

function requestBody() {
  return {
    setupId: SETUP,
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

async function request(token?: string | null): Promise<Request> {
  const accessToken = token === undefined ? await mintAccessToken(USER) : token;
  return new Request("https://example.test/personal-challenge-commit", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(accessToken === null ? {} : { authorization: `Bearer ${accessToken}` }),
    },
    body: JSON.stringify(requestBody()),
  });
}

function dependencies(options: {
  readonly status?: string;
  readonly livemode?: boolean;
  readonly paymentMethodId?: string;
  readonly replayed?: boolean;
  readonly consumedChallengeId?: string;
} = {}): {
  readonly deps: PersonalStripeCommitDeps;
  readonly calls: string[];
  readonly loadedArgs: LoadPersonalStripeSetupArgs[];
} {
  const calls: string[] = [];
  const loadedArgs: LoadPersonalStripeSetupArgs[] = [];
  const database: PersonalStripeCommitDatabase = {
    loadSetupForCommit(args) {
      calls.push("load");
      loadedArgs.push(args);
      return Promise.resolve({
        stripeCustomerId: "cus_sandbox",
        stripeSetupIntentId: "seti_sandbox",
        ...(options.consumedChallengeId === undefined
          ? {}
          : { consumedChallengeId: options.consumedChallengeId }),
      });
    },
    recordSucceededSetup() {
      calls.push("record");
      return Promise.resolve();
    },
    commitChallenge() {
      calls.push("commit");
      return Promise.resolve({
        challengeId: CHALLENGE,
        replayed: options.replayed ?? false,
      });
    },
  };
  const stripe: Pick<PersonalStripeSetupGateway, "retrieveSetupIntent"> = {
    retrieveSetupIntent() {
      calls.push("stripe");
      return Promise.resolve({
        id: "seti_sandbox",
        clientSecret: "seti_sandbox_secret_example",
        customerId: "cus_sandbox",
        paymentMethodId: options.paymentMethodId ?? "pm_sandbox",
        livemode: options.livemode ?? false,
        status: options.status ?? "succeeded",
      });
    },
  };
  return {
    calls,
    loadedArgs,
    deps: {
      database,
      stripe,
      verifyToken: createAccessTokenVerifier(TEST_JWT_SECRET),
    },
  };
}

Deno.test("commits only after Stripe confirms the saved method", async () => {
  const fixture = dependencies();
  const handler = createPersonalStripeCommitHandler(fixture.deps);
  const response = await handler(await request());

  assertEquals(response.status, 201);
  assertEquals(await response.json(), {
    challengeId: CHALLENGE,
    paymentState: "method_saved",
    replayed: false,
  });
  assertEquals(fixture.calls, ["load", "stripe", "record", "commit"]);
  assertEquals(fixture.loadedArgs[0]!.ownerId, USER);
  assertEquals(fixture.loadedArgs[0]!.requestId, REQUEST);
});

Deno.test("returns an exact challenge retry without making a second challenge", async () => {
  const fixture = dependencies({ consumedChallengeId: CHALLENGE });
  const handler = createPersonalStripeCommitHandler(fixture.deps);
  const response = await handler(await request());

  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    challengeId: CHALLENGE,
    paymentState: "method_saved",
    replayed: true,
  });
  assertEquals(fixture.calls, ["load"]);
});

Deno.test("does not trust PaymentSheet completion without provider success", async () => {
  for (
    const options of [
      { status: "requires_action" },
      { status: "processing" },
      { status: "succeeded", paymentMethodId: "" },
    ]
  ) {
    const fixture = dependencies(options);
    const handler = createPersonalStripeCommitHandler(fixture.deps);
    const response = await handler(await request());

    assertEquals(response.status, 422);
    assertEquals(fixture.calls, ["load", "stripe"]);
  }
});

Deno.test("refuses live provider state in the sandbox commit flow", async () => {
  const fixture = dependencies({ livemode: true });
  const handler = createPersonalStripeCommitHandler(fixture.deps);
  const response = await handler(await request());

  assertEquals(response.status, 500);
  assertEquals(fixture.calls, ["load", "stripe"]);
});

Deno.test("requires an authenticated GameTime user", async () => {
  const fixture = dependencies();
  const handler = createPersonalStripeCommitHandler(fixture.deps);
  const response = await handler(await request(null));

  assertEquals(response.status, 401);
  assertEquals(fixture.calls, []);
});
