import Stripe from "stripe";
import { stripeObjectId } from "../_shared/stripe_sandbox.ts";
import type {
  PersonalStripeChargeClaim,
  PersonalStripeChargeGateway,
  PersonalStripeChargeResult,
} from "./handler.ts";
import { StripeTransportAmbiguousError, StripeWorkerTerminalError } from "./handler.ts";

function normalizedFailureCode(value: string | undefined, fallback: string): string {
  const normalized = value
    ?.toLowerCase()
    .replaceAll(/[^a-z0-9_]/g, "_")
    .replaceAll(/_+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 80);
  return normalized === undefined || normalized.length === 0 ? fallback : normalized;
}

function snapshot(
  intent: Stripe.PaymentIntent,
): PersonalStripeChargeResult {
  let status: PersonalStripeChargeResult["status"];
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
  const providerFailureCode = normalizedFailureCode(
    intent.last_payment_error?.code,
    status === "requires_action" ? "provider_requires_action" : "provider_failed",
  );
  const failureCode = status === "requires_action"
    ? providerFailureCode
    : status === "failed"
    ? providerFailureCode
    : undefined;
  return {
    stripePaymentIntentId: intent.id,
    livemode: intent.livemode,
    status,
    ...(failureCode === undefined ? {} : { failureCode }),
  };
}

function matchesFrozenTerms(
  intent: Stripe.PaymentIntent,
  claim: PersonalStripeChargeClaim,
): boolean {
  return intent.amount === claim.amountMinor &&
    intent.currency.toUpperCase() === claim.currency &&
    stripeObjectId(intent.customer) === claim.stripeCustomerId &&
    stripeObjectId(intent.payment_method) ===
      claim.stripePaymentMethodId;
}

export function stripeChargeGateway(
  stripe: Stripe,
): PersonalStripeChargeGateway {
  return {
    async createAndConfirm(claim) {
      let intent: Stripe.PaymentIntent;
      try {
        intent = await stripe.paymentIntents.create(
          {
            amount: claim.amountMinor,
            currency: claim.currency.toLowerCase(),
            customer: claim.stripeCustomerId,
            payment_method: claim.stripePaymentMethodId,
            automatic_payment_methods: {
              enabled: true,
              allow_redirects: "never",
            },
            off_session: true,
            confirm: true,
            description: "GameTime confirmed missed challenge",
            metadata: {
              gametime_charge_command_id: claim.commandId,
              gametime_challenge_id: claim.challengeId,
              gametime_result_id: claim.resultId,
              gametime_environment: "sandbox",
            },
          },
          { idempotencyKey: claim.stripeIdempotencyKey },
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
          throw new StripeTransportAmbiguousError();
        } else if (error instanceof Stripe.errors.StripeError) {
          throw new StripeWorkerTerminalError(
            normalizedFailureCode(error.code, "stripe_provider_error"),
          );
        } else {
          throw error;
        }
      }

      if (!matchesFrozenTerms(intent, claim)) {
        return {
          stripePaymentIntentId: intent.id,
          livemode: intent.livemode,
          status: "failed",
          failureCode: "provider_terms_mismatch",
        };
      }
      return snapshot(intent);
    },
  };
}
