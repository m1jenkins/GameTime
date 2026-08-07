/**
 * Entry point. See the note in `attest-device/index.ts`: configuration is read
 * and checked at module load so that a deployment which cannot verify
 * attestations refuses to start (D11), and the handler takes its dependencies as
 * an argument so it can be tested by calling it (D9).
 */

import {
  accessTokenVerification,
  allowedAttestEnvironments,
  appAttestAppIds,
  assertAttestConfigIsSafe,
  attestBypassEnabled,
  dataApiConfig,
} from "../_shared/env.ts";
import { deviceKeyLookup, postgrestDatabase } from "../_shared/database.ts";
import { createAccessTokenVerifier } from "../_shared/jwt.ts";
import { createIngestMetricsHandler } from "./handler.ts";

assertAttestConfigIsSafe();

const dataApi = dataApiConfig();
const allowedEnvironments = allowedAttestEnvironments();
const [appId, ...additionalAppIds] = appAttestAppIds();

export const handler: (request: Request) => Promise<Response> = createIngestMetricsHandler({
  database: postgrestDatabase(dataApi),
  appId,
  additionalAppIds,
  verifyToken: createAccessTokenVerifier(accessTokenVerification()),
  attestBypass: attestBypassEnabled(),
  publicKeyFor: deviceKeyLookup(dataApi, allowedEnvironments),
});

if (import.meta.main) {
  Deno.serve(handler);
}
