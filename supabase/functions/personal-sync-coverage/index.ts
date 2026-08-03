import {
  accessTokenVerification,
  appAttestAppIds,
  assertAttestConfigIsSafe,
  dataApiConfig,
} from "../_shared/env.ts";
import { deviceKeyLookup, postgrestPersonalCoverageDatabase } from "../_shared/database.ts";
import { createAccessTokenVerifier } from "../_shared/jwt.ts";
import { createPersonalCoverageHandler } from "./handler.ts";

assertAttestConfigIsSafe();

const dataApi = dataApiConfig();
const [appId, ...additionalAppIds] = appAttestAppIds();

export const handler: (request: Request) => Promise<Response> = createPersonalCoverageHandler({
  database: postgrestPersonalCoverageDatabase(dataApi),
  appId,
  additionalAppIds,
  verifyToken: createAccessTokenVerifier(accessTokenVerification()),
  publicKeyFor: deviceKeyLookup(dataApi),
});

if (import.meta.main) {
  Deno.serve(handler);
}
