/**
 * Entry point. Configuration is read and checked here at module load so that a
 * deployment which cannot verify attestations refuses to start rather than
 * accepting them (D11).
 *
 * The handler itself lives in `handler.ts` and takes its dependencies as an
 * argument, which is what lets the suite exercise it against a fake database
 * without setting environment variables or booting the edge runtime (D9).
 *
 * Supabase Edge Runtime's Node compatibility layer currently exposes an
 * undefined `process.pid` while omitting the browser `window` alias. PKI.js
 * treats that as Node and tries to write its engine to
 * `global[process.pid]`, which is the runtime's read-only `undefined` global.
 * Install the conventional alias before the receipt verifier enters the module
 * graph. The dynamic imports are intentional: static imports would run first.
 */

type RuntimeGlobals = typeof globalThis & {
  readonly process?: { readonly pid?: unknown };
  readonly window?: unknown;
};

const runtimeGlobals = globalThis as RuntimeGlobals;
if (
  runtimeGlobals.window === undefined &&
  runtimeGlobals.process !== undefined &&
  "pid" in runtimeGlobals.process &&
  runtimeGlobals.process.pid === undefined
) {
  Object.defineProperty(runtimeGlobals, "window", {
    value: runtimeGlobals,
    configurable: true,
  });
}

const {
  accessTokenVerification,
  allowedAttestEnvironments,
  appAttestAppId,
  appAttestReceiptRootCertificate,
  appAttestRootCertificate,
  assertAttestConfigIsSafe,
  attestChallengeSecret,
  dataApiConfig,
} = await import("../_shared/env.ts");
const { postgrestDatabase } = await import("../_shared/database.ts");
const { createAccessTokenVerifier } = await import("../_shared/jwt.ts");
const { createAttestDeviceHandler } = await import("./handler.ts");

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
