import { dataApiConfig, requireEnv, runtimeEnv } from "../_shared/env.ts";
import { createStripeSandboxClient, stripeSandboxConfig } from "../_shared/stripe_sandbox.ts";
import { postgrestPersonalStripeChargeDatabase } from "./database.ts";
import { createPersonalStripeChargeHandler } from "./handler.ts";
import { stripeChargeGateway } from "./stripe.ts";

const stripeConfig = stripeSandboxConfig();
const stripe = createStripeSandboxClient(stripeConfig.secretKey);

export const handler = createPersonalStripeChargeHandler({
  deploymentEnvironment: runtimeEnv(),
  dispatchSecret: requireEnv("GAMETIME_PAYMENT_DISPATCH_SECRET"),
  database: postgrestPersonalStripeChargeDatabase(dataApiConfig()),
  stripe: stripeChargeGateway(stripe),
});

if (import.meta.main) {
  Deno.serve(handler);
}
