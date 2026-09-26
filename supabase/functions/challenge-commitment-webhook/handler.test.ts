import { assertEquals } from "@std/assert";
import type {
  PersonalStripeWebhookGateway,
  StripeWebhookPaymentSnapshot,
} from "../personal-stripe-sandbox-webhook/handler.ts";
import { type CommitmentWebhookDatabase, createCommitmentWebhookHandler } from "./handler.ts";

const PAYMENT: StripeWebhookPaymentSnapshot = {
  kind: "payment",
  objectId: "pi_sandbox",
  livemode: false,
  status: "failed",
  amountMinor: 2_000,
  currency: "USD",
  stripeCustomerId: "cus_sandbox",
  stripePaymentMethodId: "pm_sandbox",
  failureCode: "card_declined",
};

function fixture(options: { readonly eventLivemode?: boolean; readonly type?: string } = {}) {
  const applied: unknown[] = [];
  const stripe: PersonalStripeWebhookGateway = {
    verifyEvent() {
      return Promise.resolve({
        id: "evt_sandbox",
        type: options.type ?? "payment_intent.payment_failed",
        objectId: "pi_sandbox",
        livemode: options.eventLivemode ?? false,
        providerCreatedAt: "2026-09-24T00:00:00.000Z",
      });
    },
    retrieveSetupIntent() {
      return Promise.reject(new Error("not used"));
    },
    retrievePaymentIntent() {
      return Promise.resolve(PAYMENT);
    },
  };
  const database: CommitmentWebhookDatabase = {
    applyWebhook(args) {
      applied.push(args);
      return Promise.resolve({ disposition: "applied" });
    },
  };
  return { handler: createCommitmentWebhookHandler({ stripe, database }), applied };
}

function request(signature: string | null = "t=1,v1=sig"): Request {
  return new Request("https://example.test/challenge-commitment-webhook", {
    method: "POST",
    headers: signature === null ? {} : { "stripe-signature": signature },
    body: "{}",
  });
}

Deno.test("applies a re-fetched PaymentIntent", async () => {
  const { handler, applied } = fixture();
  const response = await handler(request());
  assertEquals(response.status, 200);
  assertEquals(applied, [{
    stripeEventId: "evt_sandbox",
    eventType: "payment_intent.payment_failed",
    objectKind: "payment_intent",
    objectId: "pi_sandbox",
    status: "requires_payment_method",
    stripePaymentMethodId: "pm_sandbox",
    failureCode: "card_declined",
  }]);
});

Deno.test("refuses unsigned and live events", async () => {
  const unsigned = fixture();
  assertEquals((await unsigned.handler(request(null))).status, 400);
  const live = fixture({ eventLivemode: true });
  assertEquals((await live.handler(request())).status, 403);
  assertEquals([...unsigned.applied, ...live.applied], []);
});

Deno.test("records unrelated events as ignored", async () => {
  const { handler, applied } = fixture({ type: "customer.created" });
  await handler(request());
  assertEquals((applied[0] as { objectKind: string }).objectKind, "other");
});
