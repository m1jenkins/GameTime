/**
 * Entry point. Configuration is read and checked here, at module load, so that
 * a deployment which cannot verify attestations refuses to start rather than
 * accepting them (D11).
 *
 * The handler itself lives in `handler.ts` and takes its dependencies as an
 * argument, which is what lets the suite exercise it against a fake database
 * without setting environment variables or booting the edge runtime (D9).
 */

import {
  accessTokenVerification,
  allowedAttestEnvironments,
  appAttestAppId,
  appAttestReceiptRootCertificate,
  appAttestRootCertificate,
  assertAttestConfigIsSafe,
  attestChallengeSecret,
  dataApiConfig,
} from "../_shared/env.ts";
import { postgrestDatabase } from "../_shared/database.ts";
import { createAccessTokenVerifier } from "../_shared/jwt.ts";
import { createAttestDeviceHandler } from "./handler.ts";

assertAttestConfigIsSafe();

export const handler: (request: Request) => Promise<Response> = createAttestDeviceHandler({
  database: postgrestDatabase(dataApiConfig()),
  appId: appAttestAppId(),
  rootCertificatePem: appAttestRootCertificate(),
  receiptRootCertificatePem: appAttestReceiptRootCertificate(),
  allowedEnvironments: allowedAttestEnvironments(),
  verifyToken: createAccessTokenVerifier(accessTokenVerification()),
  challengeSecret: attestChallengeSecret(),
});

if (import.meta.main) {
  Deno.serve(handler);
}
