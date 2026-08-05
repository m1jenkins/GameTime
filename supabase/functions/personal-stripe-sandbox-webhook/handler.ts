import { sha256 } from "../_shared/bytes.ts";
import { HttpFailure, jsonResponse, readBody, requirePost, respond } from "../_shared/http.ts";

export const MAX_STRIPE_WEBHOOK_BODY_BYTES = 256 * 1024;
export const STRIPE_SIGNATURE_HEADER = "stripe-signature";

export interface VerifiedStripeEvent {
  readonly id: string;
  readonly type: string;
  readonly objectId: string;
  readonly apiVersion?: string;
  readonly livemode: boolean;
  readonly providerCreatedAt: string;
}

export interface StripeWebhookSetupSnapshot {
  readonly kind: "setup";
  readonly objectId: string;
  readonly livemode: boolean;
  readonly status:
    | "pending_provider"
    | "requires_action"
    | "processing"
    | "succeeded"
    | "cancelled";
  readonly stripeCustomerId: string;
  readonly stripePaymentMethodId?: string;
}

export interface StripeWebhookPaymentSnapshot {
  readonly kind: "payment";
  readonly objectId: string;
  readonly commandId?: string;
  readonly livemode: boolean;
  readonly status:
    | "processing"
    | "succeeded"
    | "requires_action"
    | "failed";
  readonly amountMinor: number;
  readonly currency: string;
  readonly stripeCustomerId: string;
  readonly stripePaymentMethodId?: string;
  readonly failureCode?: string;
}

export type StripeWebhookObjectSnapshot =
  | StripeWebhookSetupSnapshot
  | StripeWebhookPaymentSnapshot;

export interface PersonalStripeWebhookGateway {
  verifyEvent(
    rawBody: Uint8Array<ArrayBuffer>,
    signature: string,
  ): Promise<VerifiedStripeEvent>;
  retrieveSetupIntent(id: string): Promise<StripeWebhookSetupSnapshot>;
  retrievePaymentIntent(id: string): Promise<StripeWebhookPaymentSnapshot>;
}

export interface PersonalStripeWebhookDatabase {
  applyWebhook(args: {
    readonly stripeEventId: string;
    readonly payloadDigest: Uint8Array<ArrayBuffer>;
    readonly eventType: string;
    readonly objectId: string;
    readonly apiVersion?: string;
    readonly providerCreatedAt: string;
    readonly snapshot?: StripeWebhookObjectSnapshot;
    readonly disposition: "applied" | "ignored";
  }): Promise<{ readonly replayed: boolean }>;
}

export interface PersonalStripeWebhookDeps {
  readonly stripe: PersonalStripeWebhookGateway;
  readonly database: PersonalStripeWebhookDatabase;
}

export function createPersonalStripeWebhookHandler(
  deps: PersonalStripeWebhookDeps,
): (request: Request) => Promise<Response> {
  return (request) =>
    respond("personal-stripe-sandbox-webhook", async () => {
      requirePost(request);
      const signature = request.headers.get(STRIPE_SIGNATURE_HEADER);
      if (signature === null || signature.length > 8_192) {
        throw new HttpFailure(
          "bad_request",
          "a valid Stripe-Signature header is required",
        );
      }

      const rawBody = await readBody(
        request,
        MAX_STRIPE_WEBHOOK_BODY_BYTES,
      );
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
        payloadDigest: await sha256(rawBody),
        eventType: event.type,
        objectId: event.objectId,
        ...(event.apiVersion === undefined ? {} : { apiVersion: event.apiVersion }),
        providerCreatedAt: event.providerCreatedAt,
        ...(snapshot === undefined ? {} : { snapshot }),
        disposition: snapshot === undefined ? "ignored" : "applied",
      });

      return jsonResponse(200, {
        received: true,
        replayed: recorded.replayed,
      });
    });
}
