import { accessTokenVerification, dataApiConfig, requireEnv } from "../_shared/env.ts";
import { createAccessTokenVerifier } from "../_shared/jwt.ts";
import { createStripeSandboxClient, stripeSandboxConfig } from "../_shared/stripe_sandbox.ts";
import { postgrestAccountDeletionDatabase } from "./database.ts";
import { createAppleTokenRevoker } from "./apple.ts";
import { createDeleteAccountHandler } from "./handler.ts";
import { stripeCustomerDeleter } from "./stripe.ts";

const dataApi = dataApiConfig();
const stripeConfig = stripeSandboxConfig();
const stripe = createStripeSandboxClient(stripeConfig.secretKey);

export const handler = createDeleteAccountHandler({
  database: postgrestAccountDeletionDatabase(dataApi),
  apple: createAppleTokenRevoker({
    clientId: requireEnv("SUPABASE_AUTH_EXTERNAL_APPLE_CLIENT_ID"),
    clientSecret: requireEnv("SUPABASE_AUTH_EXTERNAL_APPLE_SECRET"),
  }),
  stripe: stripeCustomerDeleter(stripe),
  verifyToken: createAccessTokenVerifier(accessTokenVerification()),
});

if (import.meta.main) {
  Deno.serve(handler);
}
