import { dataApiConfig } from "../_shared/env.ts";
import { createStripeSandboxClient, stripeSandboxConfig } from "../_shared/stripe_sandbox.ts";
import { stripeWebhookGateway } from "../personal-stripe-sandbox-webhook/stripe.ts";
import { postgrestCommitmentWebhookDatabase } from "./database.ts";
import { createCommitmentWebhookHandler } from "./handler.ts";

const stripeConfig = stripeSandboxConfig(undefined, { requireWebhookSecret: true });
const stripe = createStripeSandboxClient(stripeConfig.secretKey);
const webhookSecret = stripeConfig.webhookSecret;
if (webhookSecret === undefined) {
  throw new Error("Stripe webhook signing is not configured");
}

export const handler = createCommitmentWebhookHandler({
  stripe: stripeWebhookGateway(stripe, webhookSecret),
  database: postgrestCommitmentWebhookDatabase(dataApiConfig()),
});

if (import.meta.main) {
  Deno.serve(handler);
}
