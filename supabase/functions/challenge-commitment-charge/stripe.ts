import Stripe from "stripe";
import { stripeObjectId } from "../_shared/stripe_sandbox.ts";
import {
  type CommitmentChargeClaim,
  type CommitmentChargeGateway,
  type CommitmentChargeResult,
  CommitmentProviderRefusedError,
  CommitmentTransportAmbiguousError,
} from "./handler.ts";

export function normalizedFailureCode(value: string | undefined, fallback: string): string {
  const normalized = value
    ?.toLowerCase()
    .replaceAll(/[^a-z0-9_]/g, "_")
    .replaceAll(/_+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 80);
  return normalized === undefined || normalized.length === 0 ? fallback : normalized;
}

export function chargeSnapshot(intent: Stripe.PaymentIntent): CommitmentChargeResult {
  let status: CommitmentChargeResult["status"];
  switch (intent.status) {
    case "processing":
      status = "processing";
      break;
    case "succeeded":
      status = "succeeded";
      break;
    case "requires_action":
      status = "requires_action";
      break;
    case "requires_payment_method":
    case "canceled":
      status = "failed";
      break;
    default:
      return {
        stripePaymentIntentId: intent.id,
        livemode: intent.livemode,
        status: "failed",
        failureCode: "provider_status_unsupported",
      };
  }
  const failureCode = status === "requires_action" || status === "failed"
    ? normalizedFailureCode(
      intent.last_payment_error?.code,
      status === "requires_action" ? "provider_requires_action" : "provider_failed",
    )
    : undefined;
  return {
    stripePaymentIntentId: intent.id,
    livemode: intent.livemode,
    status,
    ...(failureCode === undefined ? {} : { failureCode }),
  };
}

function matchesBinding(intent: Stripe.PaymentIntent, claim: CommitmentChargeClaim): boolean {
  return intent.amount === claim.amountCents &&
    intent.currency.toLowerCase() === claim.currency &&
    stripeObjectId(intent.customer) === claim.stripeCustomerId &&
    stripeObjectId(intent.payment_method) === claim.stripePaymentMethodId;
}

export function stripeCommitmentChargeGateway(stripe: Stripe): CommitmentChargeGateway {
  return {
    async createAndConfirm(claim) {
      let intent: Stripe.PaymentIntent;
      try {
        intent = await stripe.paymentIntents.create(
          {
            amount: claim.amountCents,
            currency: claim.currency,
            customer: claim.stripeCustomerId,
            payment_method: claim.stripePaymentMethodId,
            automatic_payment_methods: { enabled: true, allow_redirects: "never" },
            off_session: true,
            confirm: true,
            description: "GameTime missed personal goal",
            metadata: {
              gametime_commitment_charge_id: claim.chargeId,
              gametime_challenge_id: claim.challengeId,
              gametime_environment: "sandbox",
            },
          },
          { idempotencyKey: claim.idempotencyKey },
        );
      } catch (error) {
        if (
          error instanceof Stripe.errors.StripeCardError &&
          error.payment_intent !== undefined &&
          typeof error.payment_intent !== "string"
        ) {
          intent = error.payment_intent;
        } else if (
          error instanceof Stripe.errors.StripeConnectionError ||
          error instanceof Stripe.errors.StripeAPIError
        ) {
          throw new CommitmentTransportAmbiguousError();
        } else if (error instanceof Stripe.errors.StripeError) {
          throw new CommitmentProviderRefusedError(
            normalizedFailureCode(error.code, "stripe_provider_error"),
          );
        } else {
          throw error;
        }
      }
      if (!matchesBinding(intent, claim)) {
        return {
          stripePaymentIntentId: intent.id,
          livemode: intent.livemode,
          status: "failed",
          failureCode: "provider_terms_mismatch",
        };
      }
      return chargeSnapshot(intent);
    },
  };
}
