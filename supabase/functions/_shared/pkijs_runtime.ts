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
