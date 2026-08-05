import { assertEquals } from "@std/assert";
import { toHex } from "../_shared/bytes.ts";
import { HttpFailure } from "../_shared/http.ts";
import {
  createPersonalStripeWebhookHandler,
  type PersonalStripeWebhookDatabase,
  type PersonalStripeWebhookDeps,
  type PersonalStripeWebhookGateway,
  type StripeWebhookObjectSnapshot,
} from "./handler.ts";

const RAW = JSON.stringify({ id: "evt_sandbox", object: "event" });

function request(
  signature: string | null = "t=123,v1=signature",
  body = RAW,
): Request {
  return new Request(
    "https://example.test/personal-stripe-sandbox-webhook",
    {
      method: "POST",
      headers: signature === null ? {} : { "stripe-signature": signature },
      body,
    },
  );
}

function fixture(options: {
  readonly eventType?: string;
  readonly eventLivemode?: boolean;
  readonly snapshotLivemode?: boolean;
  readonly replayed?: boolean;
  readonly invalidSignature?: boolean;
} = {}): {
  readonly deps: PersonalStripeWebhookDeps;
  readonly calls: string[];
  readonly applied: Array<Record<string, unknown>>;
} {
  const calls: string[] = [];
  const applied: Array<Record<string, unknown>> = [];
  const gateway: PersonalStripeWebhookGateway = {
    verifyEvent(raw, signature) {
      calls.push(`verify:${new TextDecoder().decode(raw)}:${signature}`);
      if (options.invalidSignature === true) {
        throw new HttpFailure(
          "unauthorized",
          "the Stripe webhook signature is invalid",
        );
      }
      const type = options.eventType ?? "setup_intent.succeeded";
      return Promise.resolve({
        id: "evt_sandbox",
        type,
        objectId: type.startsWith("setup_intent.") ? "seti_sandbox" : "pi_sandbox",
        apiVersion: "2026-02-25.clover",
        livemode: options.eventLivemode ?? false,
        providerCreatedAt: "2026-08-05T12:00:00.000Z",
      });
    },
    retrieveSetupIntent() {
      calls.push("retrieveSetup");
      return Promise.resolve({
        kind: "setup",
        objectId: "seti_sandbox",
        livemode: options.snapshotLivemode ?? false,
        status: "succeeded",
        stripeCustomerId: "cus_sandbox",
        stripePaymentMethodId: "pm_sandbox",
      });
    },
    retrievePaymentIntent() {
      calls.push("retrievePayment");
      return Promise.resolve({
        kind: "payment",
        objectId: "pi_sandbox",
        commandId: "11111111-1111-4111-8111-111111111111",
        livemode: options.snapshotLivemode ?? false,
        status: "succeeded",
        amountMinor: 2_000,
        currency: "USD",
        stripeCustomerId: "cus_sandbox",
        stripePaymentMethodId: "pm_sandbox",
      });
    },
  };
  const database: PersonalStripeWebhookDatabase = {
    applyWebhook(args) {
      calls.push("apply");
      applied.push(args as unknown as Record<string, unknown>);
      return Promise.resolve({ replayed: options.replayed ?? false });
    },
  };
  return { deps: { stripe: gateway, database }, calls, applied };
}

Deno.test("verifies raw bytes then reconciles canonical SetupIntent state", async () => {
  const value = fixture();
  const handler = createPersonalStripeWebhookHandler(value.deps);
  const response = await handler(request());

  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    received: true,
    replayed: false,
  });
  assertEquals(value.calls, [
    `verify:${RAW}:t=123,v1=signature`,
    "retrieveSetup",
    "apply",
  ]);
  assertEquals(value.applied[0]!["stripeEventId"], "evt_sandbox");
  assertEquals(
    toHex(
      value.applied[0]!["payloadDigest"] as Uint8Array<ArrayBuffer>,
    ).length,
    64,
  );
  assertEquals(
    (value.applied[0]!["snapshot"] as StripeWebhookObjectSnapshot).kind,
    "setup",
  );
});

Deno.test("reconciles PaymentIntent state and exact event retries", async () => {
  const value = fixture({
    eventType: "payment_intent.succeeded",
    replayed: true,
  });
  const handler = createPersonalStripeWebhookHandler(value.deps);
  const response = await handler(request());

  assertEquals(response.status, 200);
  assertEquals((await response.json()).replayed, true);
  assertEquals(value.calls, [
    `verify:${RAW}:t=123,v1=signature`,
    "retrievePayment",
    "apply",
  ]);
  assertEquals(
    (
      value.applied[0]!["snapshot"] as StripeWebhookObjectSnapshot & {
        readonly commandId?: string;
      }
    ).commandId,
    "11111111-1111-4111-8111-111111111111",
  );
});

Deno.test("records unrelated signed events as ignored", async () => {
  const value = fixture({ eventType: "customer.updated" });
  const handler = createPersonalStripeWebhookHandler(value.deps);
  const response = await handler(request());

  assertEquals(response.status, 200);
  assertEquals(value.calls, [
    `verify:${RAW}:t=123,v1=signature`,
    "apply",
  ]);
  assertEquals(value.applied[0]!["disposition"], "ignored");
  assertEquals(value.applied[0]!["snapshot"], undefined);
});

Deno.test("rejects missing or invalid signatures before database work", async () => {
  for (
    const options of [
      { signature: null, invalidSignature: false },
      { signature: "bad", invalidSignature: true },
    ]
  ) {
    const value = fixture({ invalidSignature: options.invalidSignature });
    const handler = createPersonalStripeWebhookHandler(value.deps);
    const response = await handler(request(options.signature));

    assertEquals(
      response.status,
      options.signature === null ? 400 : 401,
    );
    assertEquals(value.calls.includes("apply"), false);
  }
});

Deno.test("rejects live event or object provenance", async () => {
  for (
    const options of [
      { eventLivemode: true },
      { snapshotLivemode: true },
    ]
  ) {
    const value = fixture(options);
    const handler = createPersonalStripeWebhookHandler(value.deps);
    const response = await handler(request());

    assertEquals(response.status, 403);
    assertEquals(value.calls.includes("apply"), false);
  }
});
