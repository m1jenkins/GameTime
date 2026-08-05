import { accessTokenVerification, dataApiConfig } from "../_shared/env.ts";
import { createAccessTokenVerifier } from "../_shared/jwt.ts";
import { createStripeSandboxClient, stripeSandboxConfig } from "../_shared/stripe_sandbox.ts";
import { postgrestPersonalStripeCommitDatabase } from "./database.ts";
import { createPersonalStripeCommitHandler } from "./handler.ts";
import { stripeSetupGateway } from "../personal-payment-setup/stripe.ts";

const stripeConfig = stripeSandboxConfig();
const stripe = createStripeSandboxClient(stripeConfig.secretKey);

export const handler = createPersonalStripeCommitHandler({
  database: postgrestPersonalStripeCommitDatabase(dataApiConfig()),
  stripe: stripeSetupGateway(stripe),
  verifyToken: createAccessTokenVerifier(accessTokenVerification()),
});

if (import.meta.main) {
  Deno.serve(handler);
}
