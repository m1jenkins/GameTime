import { accessTokenVerification, dataApiConfig } from "../_shared/env.ts";
import { createAccessTokenVerifier } from "../_shared/jwt.ts";
import { createStripeSandboxClient, stripeSandboxConfig } from "../_shared/stripe_sandbox.ts";
import { stripeSetupGateway } from "../personal-payment-setup/stripe.ts";
import { postgrestCommitmentSetupDatabase } from "./database.ts";
import { createCommitmentSetupHandler } from "./handler.ts";

const stripeConfig = stripeSandboxConfig();
const stripe = createStripeSandboxClient(stripeConfig.secretKey);

export const handler = createCommitmentSetupHandler({
  database: postgrestCommitmentSetupDatabase(dataApiConfig()),
  stripe: stripeSetupGateway(stripe),
  publishableKey: stripeConfig.publishableKey,
  verifyToken: createAccessTokenVerifier(accessTokenVerification()),
});

if (import.meta.main) {
  Deno.serve(handler);
}
