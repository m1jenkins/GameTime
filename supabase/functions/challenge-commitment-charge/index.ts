import { dataApiConfig, requireEnv, runtimeEnv } from "../_shared/env.ts";
import { createStripeSandboxClient, stripeSandboxConfig } from "../_shared/stripe_sandbox.ts";
import { postgrestCommitmentChargeDatabase } from "./database.ts";
import { createCommitmentChargeHandler } from "./handler.ts";
import { stripeCommitmentChargeGateway } from "./stripe.ts";

const stripeConfig = stripeSandboxConfig();
const stripe = createStripeSandboxClient(stripeConfig.secretKey);

export const handler = createCommitmentChargeHandler({
  deploymentEnvironment: runtimeEnv(),
  dispatchSecret: requireEnv("GAMETIME_PAYMENT_DISPATCH_SECRET"),
  database: postgrestCommitmentChargeDatabase(dataApiConfig()),
  stripe: stripeCommitmentChargeGateway(stripe),
});

if (import.meta.main) {
  Deno.serve(handler);
}
