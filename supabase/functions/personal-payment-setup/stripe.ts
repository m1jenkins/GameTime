import type Stripe from "stripe";
import { stripeObjectId } from "../_shared/stripe_sandbox.ts";
import type { PersonalStripeSetupGateway, StripeSetupIntentSnapshot } from "./handler.ts";

function snapshot(intent: Stripe.SetupIntent): StripeSetupIntentSnapshot {
  const customerId = stripeObjectId(intent.customer);
  if (customerId === undefined) {
    throw new Error("Stripe SetupIntent is missing its Customer");
  }
  return {
    id: intent.id,
    ...(intent.client_secret === null ? {} : { clientSecret: intent.client_secret }),
    customerId,
    ...(stripeObjectId(intent.payment_method) === undefined
      ? {}
      : { paymentMethodId: stripeObjectId(intent.payment_method)! }),
    livemode: intent.livemode,
    status: intent.status,
  };
}

export function stripeSetupGateway(
  stripe: Stripe,
): PersonalStripeSetupGateway {
  return {
    async createCustomer(args) {
      const customer = await stripe.customers.create(
        {
          metadata: {
            gametime_owner_id: args.ownerId,
            gametime_environment: "sandbox",
          },
        },
        { idempotencyKey: args.idempotencyKey },
      );
      return { id: customer.id, livemode: customer.livemode };
    },

    async createSetupIntent(args) {
      const intent = await stripe.setupIntents.create(
        {
          automatic_payment_methods: { enabled: true },
          customer: args.customerId,
          metadata: {
            gametime_setup_id: args.setupId,
            gametime_request_id: args.requestId,
            gametime_environment: "sandbox",
          },
          usage: "off_session",
        },
        { idempotencyKey: args.idempotencyKey },
      );
      return snapshot(intent);
    },

    async retrieveSetupIntent(id) {
      return snapshot(await stripe.setupIntents.retrieve(id));
    },
  };
}
