/**
 * Production entry point for M6's attested geofence check-in ingest.
 *
 * Configuration is checked at module load, matching the M3 ingest functions:
 * a deployed function with an unsafe App Attest bypass refuses to start.
 */

import {
  accessTokenVerification,
  allowedAttestEnvironments,
  appAttestAppId,
  assertAttestConfigIsSafe,
  attestBypassEnabled,
  dataApiConfig,
} from "../_shared/env.ts";
import { deviceKeyLookup, postgrestCheckInDatabase } from "../_shared/database.ts";
import { createAccessTokenVerifier } from "../_shared/jwt.ts";
import { createIngestCheckInHandler } from "./handler.ts";

assertAttestConfigIsSafe();

const dataApi = dataApiConfig();
const allowedEnvironments = allowedAttestEnvironments();

export const handler: (request: Request) => Promise<Response> = createIngestCheckInHandler({
  database: postgrestCheckInDatabase(dataApi),
  appId: appAttestAppId(),
  verifyToken: createAccessTokenVerifier(accessTokenVerification()),
  attestBypass: attestBypassEnabled(),
  publicKeyFor: deviceKeyLookup(dataApi, allowedEnvironments),
});

if (import.meta.main) {
  Deno.serve(handler);
}
