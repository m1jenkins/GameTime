import { dataApiConfig } from "../_shared/env.ts";
import { createStripeSandboxClient, stripeSandboxConfig } from "../_shared/stripe_sandbox.ts";
import { postgrestPersonalStripeWebhookDatabase } from "./database.ts";
import { createPersonalStripeWebhookHandler } from "./handler.ts";
import { stripeWebhookGateway } from "./stripe.ts";

const stripeConfig = stripeSandboxConfig(undefined, {
  requireWebhookSecret: true,
});
const stripe = createStripeSandboxClient(stripeConfig.secretKey);
const webhookSecret = stripeConfig.webhookSecret;
if (webhookSecret === undefined) {
  throw new Error("Stripe webhook signing is not configured");
}

export const handler = createPersonalStripeWebhookHandler({
  stripe: stripeWebhookGateway(stripe, webhookSecret),
  database: postgrestPersonalStripeWebhookDatabase(dataApiConfig()),
});

if (import.meta.main) {
  Deno.serve(handler);
}
