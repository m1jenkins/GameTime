import { assertEquals, assertThrows } from "@std/assert";
import {
  COMMITMENT_DISPATCH_SECRET_HEADER,
  type CommitmentChargeClaim,
  type CommitmentChargeDatabase,
  type CommitmentChargeGateway,
  type CommitmentChargeResult,
  CommitmentProviderRefusedError,
  CommitmentTransportAmbiguousError,
  createCommitmentChargeHandler,
} from "./handler.ts";

const SECRET = "sandbox-payment-dispatch-secret-0001";
const CLAIM: CommitmentChargeClaim = {
  chargeId: "11111111-1111-1111-1111-111111111111",
  challengeId: "22222222-2222-2222-2222-222222222222",
  amountCents: 2_000,
  currency: "usd",
  idempotencyKey: "gt:challenge-commitment:v1:22222222-2222-2222-2222-222222222222:user",
  stripeCustomerId: "cus_sandbox",
  stripePaymentMethodId: "pm_sandbox",
};

function request(secret = SECRET): Request {
  return new Request("https://example.test/challenge-commitment-charge", {
    method: "POST",
    headers: { [COMMITMENT_DISPATCH_SECRET_HEADER]: secret },
  });
}

function fixture(outcome: CommitmentChargeResult | Error, environment = "local") {
  const records: unknown[] = [];
  const database: CommitmentChargeDatabase = {
    claim() {
      return Promise.resolve([CLAIM]);
    },
    record(args) {
      records.push(args);
      return Promise.resolve();
    },
  };
  const stripe: CommitmentChargeGateway = {
    createAndConfirm() {
      return outcome instanceof Error ? Promise.reject(outcome) : Promise.resolve(outcome);
    },
  };
  const handler = createCommitmentChargeHandler({
    deploymentEnvironment: environment,
    dispatchSecret: SECRET,
    database,
    stripe,
    leaseOwner: () => "lease",
  });
  return { handler, records };
}

Deno.test("refuses to run in production", () => {
  assertThrows(() =>
    fixture({ stripePaymentIntentId: "pi_1", livemode: false, status: "succeeded" }, "production")
  );
});

Deno.test("requires the dispatch secret", async () => {
  const { handler, records } = fixture({
    stripePaymentIntentId: "pi_1",
    livemode: false,
    status: "succeeded",
  });
  assertEquals((await handler(request("wrong-secret-wrong-secret-wrong-secret"))).status, 401);
  assertEquals(records, []);
});

Deno.test("records a successful charge", async () => {
  const { handler, records } = fixture({
    stripePaymentIntentId: "pi_1",
    livemode: false,
    status: "succeeded",
  });
  const response = await handler(request());
  assertEquals(response.status, 200);
  assertEquals((await response.json()).succeeded, 1);
  assertEquals(records, [{
    chargeId: CLAIM.chargeId,
    leaseOwner: "lease",
    status: "succeeded",
    stripePaymentIntentId: "pi_1",
  }]);
});

Deno.test("a decline is final", async () => {
  const { handler, records } = fixture({
    stripePaymentIntentId: "pi_1",
    livemode: false,
    status: "failed",
    failureCode: "card_declined",
  });
  await handler(request());
  assertEquals(records, [{
    chargeId: CLAIM.chargeId,
    leaseOwner: "lease",
    status: "failed",
    stripePaymentIntentId: "pi_1",
    failureCode: "card_declined",
  }]);
});

Deno.test("a transport error leaves the charge for a keyed retry", async () => {
  const { handler, records } = fixture(new CommitmentTransportAmbiguousError());
  const response = await handler(request());
  assertEquals((await response.json()).transport_ambiguous, 1);
  assertEquals(records, [{ chargeId: CLAIM.chargeId, leaseOwner: "lease", status: "processing" }]);
});

Deno.test("a refused request is recorded as failed", async () => {
  const { handler, records } = fixture(new CommitmentProviderRefusedError("parameter_invalid"));
  await handler(request());
  assertEquals(records, [{
    chargeId: CLAIM.chargeId,
    leaseOwner: "lease",
    status: "failed",
    failureCode: "parameter_invalid",
  }]);
});

Deno.test("a live PaymentIntent stops the worker without recording it", async () => {
  const { handler, records } = fixture({
    stripePaymentIntentId: "pi_1",
    livemode: true,
    status: "succeeded",
  });
  assertEquals((await handler(request())).status, 500);
  assertEquals(records, []);
});
