import { HttpFailure, jsonResponse, readBody, requirePost, respond } from "../_shared/http.ts";
import type {
  PersonalStripeWebhookGateway,
  StripeWebhookObjectSnapshot,
} from "../personal-stripe-sandbox-webhook/handler.ts";

export const MAX_COMMITMENT_WEBHOOK_BODY_BYTES = 256 * 1024;
export const STRIPE_SIGNATURE_HEADER = "stripe-signature";

export interface CommitmentWebhookDatabase {
  applyWebhook(args: {
    readonly stripeEventId: string;
    readonly eventType: string;
    readonly objectKind: "payment_intent" | "setup_intent" | "other";
    readonly objectId: string;
    readonly status: string;
    readonly stripePaymentMethodId?: string;
    readonly failureCode?: string;
  }): Promise<{ readonly disposition: string }>;
}

export interface CommitmentWebhookDeps {
  readonly stripe: PersonalStripeWebhookGateway;
  readonly database: CommitmentWebhookDatabase;
}

/** Maps a verified, re-fetched snapshot back to the Stripe status the database expects. */
export function providerStatus(snapshot: StripeWebhookObjectSnapshot): string {
  if (snapshot.kind === "setup") {
    switch (snapshot.status) {
      case "pending_provider":
        return "requires_payment_method";
      case "cancelled":
        return "canceled";
      default:
        return snapshot.status;
    }
  }
  return snapshot.status === "failed" ? "requires_payment_method" : snapshot.status;
}

/**
 * Reconciles the commitment sandbox with Stripe. The signature is verified
 * over the raw body and the object is re-read from Stripe; the event body's
 * own copy of the object is never trusted. Live events are refused.
 */
export function createCommitmentWebhookHandler(
  deps: CommitmentWebhookDeps,
): (request: Request) => Promise<Response> {
  return (request) =>
    respond("challenge-commitment-webhook", async () => {
      requirePost(request);
      const signature = request.headers.get(STRIPE_SIGNATURE_HEADER);
      if (signature === null || signature.length > 8_192) {
        throw new HttpFailure("bad_request", "a valid Stripe-Signature header is required");
      }
      const rawBody = await readBody(request, MAX_COMMITMENT_WEBHOOK_BODY_BYTES);
      const event = await deps.stripe.verifyEvent(rawBody, signature);
      if (event.livemode) {
        throw new HttpFailure(
          "forbidden",
          "live Stripe events are forbidden on this sandbox endpoint",
        );
      }

      let snapshot: StripeWebhookObjectSnapshot | undefined;
      if (event.type.startsWith("setup_intent.")) {
        snapshot = await deps.stripe.retrieveSetupIntent(event.objectId);
      } else if (event.type.startsWith("payment_intent.")) {
        snapshot = await deps.stripe.retrievePaymentIntent(event.objectId);
      }
      if (snapshot?.livemode) {
        throw new HttpFailure(
          "forbidden",
          "live Stripe objects are forbidden on this sandbox endpoint",
        );
      }

      const recorded = await deps.database.applyWebhook({
        stripeEventId: event.id,
        eventType: event.type,
        objectKind: snapshot === undefined
          ? "other"
          : snapshot.kind === "setup"
          ? "setup_intent"
          : "payment_intent",
        objectId: event.objectId,
        status: snapshot === undefined ? "ignored" : providerStatus(snapshot),
        ...(snapshot?.stripePaymentMethodId === undefined
          ? {}
          : { stripePaymentMethodId: snapshot.stripePaymentMethodId }),
        ...(snapshot?.kind === "payment" && snapshot.failureCode !== undefined
          ? { failureCode: snapshot.failureCode }
          : {}),
      });
      return jsonResponse(200, { received: true, disposition: recorded.disposition });
    });
}
