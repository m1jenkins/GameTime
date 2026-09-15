import { accessTokenVerification, dataApiConfig, requireEnv } from "../_shared/env.ts";
import { createAccessTokenVerifier } from "../_shared/jwt.ts";
import { createStripeSandboxClient, stripeSandboxConfig } from "../_shared/stripe_sandbox.ts";
import { postgrestAccountDeletionDatabase } from "./database.ts";
import { createAppleTokenRevoker } from "./apple.ts";
import { createDeleteAccountHandler, type StripeCustomerDeleter } from "./handler.ts";
import { stripeCustomerDeleter } from "./stripe.ts";

const dataApi = dataApiConfig();
// A challenge-only local account has no Personal sandbox customer. Do not make
// that path require a Stripe key at cold start. A stored customer still fails
// closed unless the explicit local test substitute is configured.
const stripe: StripeCustomerDeleter = (() => {
  if (
    !Deno.env.get("STRIPE_SECRET_KEY")?.trim() || !Deno.env.get("STRIPE_PUBLISHABLE_KEY")?.trim()
  ) {
    return {
      deleteTestCustomer: () =>
        Promise.reject(new Error("the local payment substitute is not configured")),
    };
  }
  const stripeConfig = stripeSandboxConfig();
  return stripeCustomerDeleter(createStripeSandboxClient(stripeConfig.secretKey));
})();

export const handler = createDeleteAccountHandler({
  database: postgrestAccountDeletionDatabase(dataApi),
  apple: createAppleTokenRevoker({
    clientId: requireEnv("SUPABASE_AUTH_EXTERNAL_APPLE_CLIENT_ID"),
    clientSecret: requireEnv("SUPABASE_AUTH_EXTERNAL_APPLE_SECRET"),
  }),
  stripe,
  verifyToken: createAccessTokenVerifier(accessTokenVerification()),
});

if (import.meta.main) {
  Deno.serve(handler);
}
