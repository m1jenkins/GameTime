/**
 * Loads PKI.js without its Node engine registry tripping over Supabase's
 * Node-compatibility shim.
 *
 * Hosted Edge Runtime currently exposes both `global` and a `process.pid`
 * property whose value is `undefined`, while omitting the browser `window`
 * alias. PKI.js sees that as Node, then tries to store its crypto engine at
 * `global[process.pid]` — which is the read-only `globalThis.undefined`
 * property in this runtime. Giving that Window-shaped global its conventional
 * alias makes PKI.js use its browser-local engine registry and WebCrypto.
 *
 * Normal Deno and Node processes have a numeric pid, so this adapter leaves
 * their globals untouched.
 */

export type PkijsRuntimeGlobals = {
  readonly process?: { readonly pid?: unknown };
  readonly window?: unknown;
};

import { subtleWithEcdsaFallback } from "./ecdsa_verify.ts";

export function needsPkijsBrowserAlias(runtimeGlobals: PkijsRuntimeGlobals): boolean {
  return runtimeGlobals.window === undefined &&
    runtimeGlobals.process !== undefined &&
    "pid" in runtimeGlobals.process &&
    runtimeGlobals.process.pid === undefined;
}

const runtimeGlobals = globalThis as PkijsRuntimeGlobals;
if (needsPkijsBrowserAlias(runtimeGlobals)) {
  Object.defineProperty(runtimeGlobals, "window", {
    value: runtimeGlobals,
    configurable: true,
  });
}

export const pkijs = await import("pkijs");

// The hosted Edge Runtime implements WebCrypto ECDSA verify only for the
// matched (curve, digest) pairs, and Apple's receipt chain signs its P-256
// leaf with SHA-256 under a P-384 intermediate. PKI.js checks the chain
// through the engine installed here, so its verify calls fall back to the
// pure implementation in ecdsa_verify.ts instead of failing the whole CMS
// check (M6.5 live finding).
const engineName = "gametime-webcrypto-with-ecdsa-fallback";
pkijs.setEngine(
  engineName,
  new pkijs.CryptoEngine({
    name: engineName,
    crypto: globalThis.crypto,
    subtle: subtleWithEcdsaFallback(globalThis.crypto.subtle),
  }),
);
