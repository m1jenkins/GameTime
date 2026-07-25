/**
 * Production entry point for M6's attested geofence check-in ingest.
 *
 * Configuration is checked at module load, matching the M3 ingest functions:
 * a deployed function with an unsafe App Attest bypass refuses to start.
 */

import {
  appAttestAppId,
  assertAttestConfigIsSafe,
  attestBypassEnabled,
  dataApiConfig,
  jwtSecret,
} from "../_shared/env.ts";
import { deviceKeyLookup, postgrestCheckInDatabase } from "../_shared/database.ts";
import { createIngestCheckInHandler } from "./handler.ts";

assertAttestConfigIsSafe();

const dataApi = dataApiConfig();

export const handler: (request: Request) => Promise<Response> = createIngestCheckInHandler({
  database: postgrestCheckInDatabase(dataApi),
  appId: appAttestAppId(),
  jwtSecret: jwtSecret(),
  attestBypass: attestBypassEnabled(),
  publicKeyFor: deviceKeyLookup(dataApi),
});

if (import.meta.main) {
  Deno.serve(handler);
}
