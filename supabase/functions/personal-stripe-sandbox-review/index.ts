import { accessTokenVerification, dataApiConfig, runtimeEnv } from "../_shared/env.ts";
import { createAccessTokenVerifier } from "../_shared/jwt.ts";
import { postgrestPersonalStripeReviewDatabase } from "./database.ts";
import { createPersonalStripeReviewHandler } from "./handler.ts";

export const handler = createPersonalStripeReviewHandler({
  deploymentEnvironment: runtimeEnv(),
  database: postgrestPersonalStripeReviewDatabase(dataApiConfig()),
  verifyToken: createAccessTokenVerifier(accessTokenVerification()),
});

if (import.meta.main) {
  Deno.serve(handler);
}
