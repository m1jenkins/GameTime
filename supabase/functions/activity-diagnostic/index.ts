import {
  accessTokenVerification,
  allowedAttestEnvironments,
  appAttestAppIds,
  assertAttestConfigIsSafe,
  dataApiConfig,
} from "../_shared/env.ts";
import { deviceKeyLookup, postgrestActivityDiagnosticDatabase } from "../_shared/database.ts";
import { createAccessTokenVerifier } from "../_shared/jwt.ts";
import { createActivityDiagnosticHandler } from "./handler.ts";

assertAttestConfigIsSafe();

const dataApi = dataApiConfig();
const allowedEnvironments = allowedAttestEnvironments();
const [appId, ...additionalAppIds] = appAttestAppIds();

export const handler: (request: Request) => Promise<Response> = createActivityDiagnosticHandler({
  database: postgrestActivityDiagnosticDatabase(dataApi),
  appId,
  additionalAppIds,
  verifyToken: createAccessTokenVerifier(accessTokenVerification()),
  publicKeyFor: deviceKeyLookup(dataApi, allowedEnvironments),
});

if (import.meta.main) {
  Deno.serve(handler);
}
