import Stripe from "stripe";
import { HttpFailure } from "../_shared/http.ts";
import { stripeObjectId } from "../_shared/stripe_sandbox.ts";
import type {
  PersonalStripeWebhookGateway,
  StripeWebhookPaymentSnapshot,
  StripeWebhookSetupSnapshot,
} from "./handler.ts";

function requiredObjectId(
  value: string | { readonly id: string } | null | undefined,
  label: string,
): string {
  const id = stripeObjectId(value);
  if (id === undefined) {
    throw new HttpFailure("internal", `Stripe ${label} is missing`);
  }
  return id;
}

function setupSnapshot(
  intent: Stripe.SetupIntent,
): StripeWebhookSetupSnapshot {
  let status: StripeWebhookSetupSnapshot["status"];
  switch (intent.status) {
    case "requires_payment_method":
    case "requires_confirmation":
      status = "pending_provider";
      break;
    case "requires_action":
      status = "requires_action";
      break;
    case "processing":
      status = "processing";
      break;
    case "succeeded":
      status = "succeeded";
      break;
    case "canceled":
      status = "cancelled";
      break;
    default:
      throw new HttpFailure(
        "internal",
        "Stripe returned an unsupported payment setup state",
      );
  }
  return {
    kind: "setup",
    objectId: intent.id,
    livemode: intent.livemode,
    status,
    stripeCustomerId: requiredObjectId(intent.customer, "Customer"),
    ...(stripeObjectId(intent.payment_method) === undefined
      ? {}
      : { stripePaymentMethodId: stripeObjectId(intent.payment_method)! }),
  };
}

function paymentSnapshot(
  intent: Stripe.PaymentIntent,
): StripeWebhookPaymentSnapshot {
  let status: StripeWebhookPaymentSnapshot["status"];
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
      throw new HttpFailure(
        "internal",
        "Stripe returned an unsupported charge state",
      );
  }
  const failureCode = intent.last_payment_error?.code;
  const commandId = intent.metadata["gametime_charge_command_id"];
  if (
    commandId !== undefined &&
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(commandId)
  ) {
    throw new HttpFailure(
      "internal",
      "Stripe returned malformed GameTime charge metadata",
    );
  }
  return {
    kind: "payment",
    objectId: intent.id,
    ...(commandId === undefined ? {} : { commandId }),
    livemode: intent.livemode,
    status,
    amountMinor: intent.amount,
    currency: intent.currency.toUpperCase(),
    stripeCustomerId: requiredObjectId(intent.customer, "Customer"),
    ...(stripeObjectId(intent.payment_method) === undefined
      ? {}
      : { stripePaymentMethodId: stripeObjectId(intent.payment_method)! }),
    ...(failureCode === undefined ? {} : { failureCode: failureCode.slice(0, 80) }),
  };
}

export function stripeWebhookGateway(
  stripe: Stripe,
  webhookSecret: string,
): PersonalStripeWebhookGateway {
  const cryptoProvider = Stripe.createSubtleCryptoProvider();
  return {
    async verifyEvent(rawBody, signature) {
      let event: Stripe.Event;
      try {
        const rawText = new TextDecoder("utf-8", { fatal: true }).decode(
          rawBody,
        );
        event = await stripe.webhooks.constructEventAsync(
          rawText,
          signature,
          webhookSecret,
          undefined,
          cryptoProvider,
        );
      } catch {
        throw new HttpFailure(
          "unauthorized",
          "the Stripe webhook signature is invalid",
        );
      }
      const object = event.data.object as { readonly id?: unknown };
      if (typeof object.id !== "string" || object.id.length > 255) {
        throw new HttpFailure(
          "bad_request",
          "the Stripe event has no usable object id",
        );
      }
      return {
        id: event.id,
        type: event.type,
        objectId: object.id,
        ...(event.api_version === null ? {} : { apiVersion: event.api_version }),
        livemode: event.livemode,
        providerCreatedAt: new Date(event.created * 1_000).toISOString(),
      };
    },

    async retrieveSetupIntent(id) {
      return setupSnapshot(await stripe.setupIntents.retrieve(id));
    },

    async retrievePaymentIntent(id) {
      return paymentSnapshot(await stripe.paymentIntents.retrieve(id));
    },
  };
}
