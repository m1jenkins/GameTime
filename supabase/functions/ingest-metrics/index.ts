/**
 * Entry point. See the note in `attest-device/index.ts`: configuration is read
 * and checked at module load so that a deployment which cannot verify
 * attestations refuses to start (D11), and the handler takes its dependencies as
 * an argument so it can be tested by calling it (D9).
 */

import {
  appAttestAppId,
  assertAttestConfigIsSafe,
  attestBypassEnabled,
  dataApiConfig,
  jwtSecret,
} from "../_shared/env.ts";
import { deviceKeyLookup, postgrestDatabase } from "../_shared/database.ts";
import { createIngestMetricsHandler } from "./handler.ts";

assertAttestConfigIsSafe();

const dataApi = dataApiConfig();

export const handler: (request: Request) => Promise<Response> = createIngestMetricsHandler({
  database: postgrestDatabase(dataApi),
  appId: appAttestAppId(),
  jwtSecret: jwtSecret(),
  attestBypass: attestBypassEnabled(),
  publicKeyFor: deviceKeyLookup(dataApi),
});

if (import.meta.main) {
  Deno.serve(handler);
}
