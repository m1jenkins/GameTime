import { deviceKeyLookup } from "../_shared/database.ts";
import {
  accessTokenVerification,
  allowedAttestEnvironments,
  appAttestAppIds,
  assertAttestConfigIsSafe,
  dataApiConfig,
} from "../_shared/env.ts";
import { createAccessTokenVerifier } from "../_shared/jwt.ts";
import { realHealthDatabase, realHealthReadinessDatabase } from "./database.ts";
import { createIngestChallengeHealthHandler } from "./handler.ts";

assertAttestConfigIsSafe();
const config = dataApiConfig();
const [appId, ...additionalAppIds] = appAttestAppIds();
export const handler = createIngestChallengeHealthHandler({
  enabled: Deno.env.get("CHALLENGE_REAL_HEALTH_INGEST_ENABLED") === "true",
  appId,
  additionalAppIds,
  verifyToken: createAccessTokenVerifier(accessTokenVerification()),
  publicKeyFor: deviceKeyLookup(config, allowedAttestEnvironments()),
  ingest: realHealthDatabase(config),
  readiness: realHealthReadinessDatabase(config),
});
if (import.meta.main) Deno.serve(handler);
