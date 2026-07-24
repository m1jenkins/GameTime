/**
 * Typed, fail-fast environment access for Edge Functions.
 *
 * Two rules this module exists to enforce:
 *
 *  1. A missing required variable is a startup error, not a silent `undefined`
 *     that surfaces later as a confusing 500 or, worse, as a security control
 *     that quietly evaluated to false.
 *
 *  2. Development escape hatches must be impossible to leave on in production.
 *     `assertAttestConfigIsSafe` is the one that matters: it refuses to let a
 *     deployed environment run with App Attest verification bypassed.
 */

export class ConfigError extends Error {
  override readonly name = "ConfigError";
}

/** Deployment environments, ordered from most permissive to least. */
export type RuntimeEnv = "local" | "test" | "staging" | "production";

const RUNTIME_ENVS: readonly RuntimeEnv[] = ["local", "test", "staging", "production"];

/**
 * A read-only view over the process environment. Injecting this (rather than
 * reading `Deno.env` directly) is what lets tests exercise config handling
 * without mutating global state.
 */
export type EnvSource = (key: string) => string | undefined;

export const denoEnv: EnvSource = (key) => Deno.env.get(key);

/** Returns the value of `name`, or throws if it is unset or blank. */
export function requireEnv(name: string, source: EnvSource = denoEnv): string {
  const raw = source(name);
  if (raw === undefined || raw.trim() === "") {
    throw new ConfigError(`required environment variable ${name} is unset or empty`);
  }
  return raw;
}

/** Returns the value of `name`, or `fallback` if it is unset or blank. */
export function optionalEnv(
  name: string,
  fallback: string,
  source: EnvSource = denoEnv,
): string {
  const raw = source(name);
  return raw === undefined || raw.trim() === "" ? fallback : raw;
}

/**
 * Strict boolean parse. Only "true"/"false" (any casing, surrounding
 * whitespace ignored) are accepted; "1", "yes", and "on" are rejected on
 * purpose so that a typo in a security-relevant flag fails loudly rather than
 * landing on a default.
 */
export function boolEnv(name: string, fallback: boolean, source: EnvSource = denoEnv): boolean {
  const raw = source(name);
  if (raw === undefined || raw.trim() === "") return fallback;
  const normalized = raw.trim().toLowerCase();
  if (normalized === "true") return true;
  if (normalized === "false") return false;
  throw new ConfigError(
    `environment variable ${name} must be "true" or "false", got ${JSON.stringify(raw)}`,
  );
}

/** Reads SUPABASE_ENV, defaulting to "local". Rejects unknown values. */
export function runtimeEnv(source: EnvSource = denoEnv): RuntimeEnv {
  const raw = optionalEnv("SUPABASE_ENV", "local", source).trim().toLowerCase();
  if (!RUNTIME_ENVS.includes(raw as RuntimeEnv)) {
    throw new ConfigError(
      `SUPABASE_ENV must be one of ${RUNTIME_ENVS.join(", ")}, got ${JSON.stringify(raw)}`,
    );
  }
  return raw as RuntimeEnv;
}

/**
 * The App Attest development bypass lets the backend be exercised without a
 * physical Apple device, which the whole ingest test suite depends on. It is
 * also a total defeat of anti-cheat rule 9, so it is permitted only where no
 * real contest data exists.
 *
 * Call this at module load in any function that ingests measurements. Throwing
 * here takes the function down at boot, which is the correct outcome: a
 * deployment that cannot verify attestations must not accept snapshots.
 */
export function assertAttestConfigIsSafe(source: EnvSource = denoEnv): void {
  const env = runtimeEnv(source);
  const bypass = boolEnv("ATTEST_DEV_BYPASS", false, source);
  if (bypass && (env === "staging" || env === "production")) {
    throw new ConfigError(
      `ATTEST_DEV_BYPASS is enabled in SUPABASE_ENV=${env}; ` +
        "attested ingest cannot be bypassed outside local and test environments",
    );
  }
}

/** True when the App Attest bypass is both requested and permitted. */
export function attestBypassEnabled(source: EnvSource = denoEnv): boolean {
  assertAttestConfigIsSafe(source);
  return boolEnv("ATTEST_DEV_BYPASS", false, source);
}

/** Builds an {@link EnvSource} from a plain object. Test helper. */
export function envFromRecord(record: Record<string, string>): EnvSource {
  return (key) => record[key];
}
