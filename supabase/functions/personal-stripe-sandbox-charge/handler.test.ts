import { assertEquals, assertThrows } from "@std/assert";
import {
  createPersonalStripeChargeHandler,
  PAYMENT_DISPATCH_SECRET_HEADER,
  type PersonalStripeChargeClaim,
  type PersonalStripeChargeDatabase,
  type PersonalStripeChargeDeps,
  type PersonalStripeChargeGateway,
  StripeTransportAmbiguousError,
  StripeWorkerTerminalError,
} from "./handler.ts";

const SECRET = "sandbox-payment-dispatch-secret-0001";
const CLAIM: PersonalStripeChargeClaim = {
  commandId: "11111111-1111-1111-1111-111111111111",
  challengeId: "22222222-2222-2222-2222-222222222222",
  resultId: "33333333-3333-3333-3333-333333333333",
  amountMinor: 2_000,
  currency: "USD",
  stripeCustomerId: "cus_sandbox",
  stripePaymentMethodId: "pm_sandbox",
  stripeIdempotencyKey: "gt:personal-charge:v1:33333333-3333-3333-3333-333333333333",
};

function request(secret = SECRET): Request {
  return new Request(
    "https://example.test/personal-stripe-sandbox-charge",
    {
      method: "POST",
      headers: { [PAYMENT_DISPATCH_SECRET_HEADER]: secret },
    },
  );
}

function fixture(options: {
  readonly status?: "processing" | "succeeded" | "requires_action" | "failed";
  readonly transportFailure?: boolean;
  readonly terminalWorkerFailure?: boolean;
  readonly unknownFailure?: boolean;
  readonly databaseRecordFailure?: boolean;
  readonly livemode?: boolean;
  readonly claims?: readonly PersonalStripeChargeClaim[];
} = {}): {
  readonly deps: PersonalStripeChargeDeps;
  readonly calls: string[];
  readonly records: unknown[];
} {
  const calls: string[] = [];
  const records: unknown[] = [];
  const database: PersonalStripeChargeDatabase = {
    claim(leaseOwner, limit) {
      calls.push(`claim:${leaseOwner}:${limit}`);
      return Promise.resolve(options.claims ?? [CLAIM]);
    },
    record(commandId, leaseOwner, result) {
      calls.push(`record:${commandId}:${leaseOwner}`);
      records.push(result);
      if (options.databaseRecordFailure === true) {
        throw new Error("database invariant refused the result");
      }
      return Promise.resolve();
    },
  };
  const stripe: PersonalStripeChargeGateway = {
    createAndConfirm(claim) {
      calls.push(`stripe:${claim.stripeIdempotencyKey}`);
      if (options.transportFailure === true) {
        throw new StripeTransportAmbiguousError();
      }
      if (options.terminalWorkerFailure === true) {
        throw new StripeWorkerTerminalError("stripe_authentication_error");
      }
      if (options.unknownFailure === true) {
        throw new Error("unexpected local invariant");
      }
      return Promise.resolve({
        stripePaymentIntentId: "pi_sandbox",
        livemode: options.livemode ?? false,
        status: options.status ?? "succeeded",
        ...(options.status === "failed"
          ? { failureCode: "card_declined" }
          : options.status === "requires_action"
          ? { failureCode: "provider_requires_action" }
          : {}),
      });
    },
  };
  return {
    calls,
    records,
    deps: {
      deploymentEnvironment: "staging",
      dispatchSecret: SECRET,
      database,
      stripe,
      leaseOwner: () => "lease-owner",
    },
  };
}

Deno.test("charges only database-approved confirmed misses", async () => {
  const value = fixture();
  const handler = createPersonalStripeChargeHandler(value.deps);
  const response = await handler(request());

  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    claimed: 1,
    succeeded: 1,
    processing: 0,
    requires_action: 0,
    failed: 0,
    transport_ambiguous: 0,
  });
  assertEquals(value.calls, [
    "claim:lease-owner:10",
    `stripe:${CLAIM.stripeIdempotencyKey}`,
    `record:${CLAIM.commandId}:lease-owner`,
  ]);
});

Deno.test("a database kill switch yields no claims or Stripe calls", async () => {
  const value = fixture({ claims: [] });
  const handler = createPersonalStripeChargeHandler(value.deps);
  const response = await handler(request());

  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    claimed: 0,
    succeeded: 0,
    processing: 0,
    requires_action: 0,
    failed: 0,
    transport_ambiguous: 0,
  });
  assertEquals(value.calls, ["claim:lease-owner:10"]);
  assertEquals(value.records, []);
});

Deno.test("a provider decline or action requirement is terminal for automatic dispatch", async () => {
  for (const status of ["failed", "requires_action"] as const) {
    const value = fixture({ status });
    const handler = createPersonalStripeChargeHandler(value.deps);
    const response = await handler(request());
    const result = await response.json();

    assertEquals(response.status, 200);
    assertEquals(result[status === "failed" ? "failed" : "requires_action"], 1);
    assertEquals(
      (value.records[0] as { readonly status: string }).status,
      status,
    );
  }
});

Deno.test("transport ambiguity preserves the deterministic idempotency key", async () => {
  const value = fixture({ transportFailure: true });
  const handler = createPersonalStripeChargeHandler(value.deps);
  const response = await handler(request());

  assertEquals(response.status, 200);
  assertEquals((await response.json()).transport_ambiguous, 1);
  assertEquals(value.calls[1], `stripe:${CLAIM.stripeIdempotencyKey}`);
  assertEquals(value.records, [{
    status: "transport_ambiguous",
    failureCode: "stripe_transport_ambiguous",
  }]);
});

Deno.test("definite worker failures stop automatic dispatch", async () => {
  const value = fixture({ terminalWorkerFailure: true });
  const handler = createPersonalStripeChargeHandler(value.deps);
  const response = await handler(request());

  assertEquals(response.status, 200);
  assertEquals((await response.json()).failed, 1);
  assertEquals(value.records, [{
    status: "worker_failed",
    failureCode: "stripe_authentication_error",
  }]);
});

Deno.test("unknown local errors fail closed instead of becoming transport ambiguity", async () => {
  const value = fixture({ unknownFailure: true });
  const handler = createPersonalStripeChargeHandler(value.deps);
  const response = await handler(request());

  assertEquals(response.status, 500);
  assertEquals(value.records, []);
});

Deno.test("database refusals are not mislabeled as retryable Stripe transport", async () => {
  const value = fixture({ databaseRecordFailure: true });
  const handler = createPersonalStripeChargeHandler(value.deps);
  const response = await handler(request());

  assertEquals(response.status, 500);
  assertEquals(value.calls, [
    "claim:lease-owner:10",
    `stripe:${CLAIM.stripeIdempotencyKey}`,
    `record:${CLAIM.commandId}:lease-owner`,
  ]);
  assertEquals(value.records, [{
    stripePaymentIntentId: "pi_sandbox",
    livemode: false,
    status: "succeeded",
  }]);
});

Deno.test("a live provider result fails closed without recording ambiguity", async () => {
  const value = fixture({ livemode: true });
  const handler = createPersonalStripeChargeHandler(value.deps);
  const response = await handler(request());

  assertEquals(response.status, 500);
  assertEquals(value.calls, [
    "claim:lease-owner:10",
    `stripe:${CLAIM.stripeIdempotencyKey}`,
  ]);
  assertEquals(value.records, []);
});

Deno.test("requires the internal dispatch secret", async () => {
  const value = fixture();
  const handler = createPersonalStripeChargeHandler(value.deps);
  const response = await handler(request("wrong"));

  assertEquals(response.status, 401);
  assertEquals(value.calls, []);
});

Deno.test("cannot boot outside staging or with a weak secret", () => {
  const value = fixture();
  assertThrows(() =>
    createPersonalStripeChargeHandler({
      ...value.deps,
      deploymentEnvironment: "production",
    })
  );
  assertThrows(() =>
    createPersonalStripeChargeHandler({
      ...value.deps,
      dispatchSecret: "short",
    })
  );
});
