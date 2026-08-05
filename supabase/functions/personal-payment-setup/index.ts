import { accessTokenVerification, dataApiConfig } from "../_shared/env.ts";
import { createAccessTokenVerifier } from "../_shared/jwt.ts";
import { createStripeSandboxClient, stripeSandboxConfig } from "../_shared/stripe_sandbox.ts";
import { postgrestPersonalStripeSetupDatabase } from "./database.ts";
import { createPersonalStripeSetupHandler } from "./handler.ts";
import { stripeSetupGateway } from "./stripe.ts";

const stripeConfig = stripeSandboxConfig();
const stripe = createStripeSandboxClient(stripeConfig.secretKey);

export const handler = createPersonalStripeSetupHandler({
  database: postgrestPersonalStripeSetupDatabase(dataApiConfig()),
  stripe: stripeSetupGateway(stripe),
  publishableKey: stripeConfig.publishableKey,
  verifyToken: createAccessTokenVerifier(accessTokenVerification()),
});

if (import.meta.main) {
  Deno.serve(handler);
}
