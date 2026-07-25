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

import * as x509 from "@peculiar/x509";
import type { AccessTokenVerification, JsonWebKeySet } from "./jwt.ts";

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

/**
 * Reads GAMETIME_ENV. Local tooling may omit it; a hosted function must name
 * staging or production.
 *
 * Hosted Supabase reserves the SUPABASE_ prefix for platform-injected values,
 * so the old SUPABASE_ENV name could never be configured on staging. Silently
 * defaulting a hosted deployment to `local` would also make the bypass guard
 * believe it was somewhere permissive.
 */
export function runtimeEnv(source: EnvSource = denoEnv): RuntimeEnv {
  const configured = source("GAMETIME_ENV");
  const hosted = (source("DENO_DEPLOYMENT_ID")?.trim().length ?? 0) > 0 ||
    (source("SB_REGION")?.trim().length ?? 0) > 0;
  if (configured === undefined || configured.trim() === "") {
    if (hosted) {
      throw new ConfigError(
        "required environment variable GAMETIME_ENV is unset in a hosted deployment",
      );
    }
    return "local";
  }
  const raw = configured.trim().toLowerCase();
  if (!RUNTIME_ENVS.includes(raw as RuntimeEnv)) {
    throw new ConfigError(
      `GAMETIME_ENV must be one of ${RUNTIME_ENVS.join(", ")}, got ${JSON.stringify(raw)}`,
    );
  }
  if (hosted && (raw === "local" || raw === "test")) {
    throw new ConfigError(
      `GAMETIME_ENV=${raw} is forbidden in a hosted deployment`,
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
      `ATTEST_DEV_BYPASS is enabled in GAMETIME_ENV=${env}; ` +
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

// ---------------------------------------------------------------------------
// M3 — attested ingest
// ---------------------------------------------------------------------------

/**
 * The App ID Apple binds attestations to: `<teamId>.<bundleId>`.
 *
 * Assembled from the two halves rather than read as one string because those
 * are the two values the Apple Developer portal actually shows, and a
 * hand-concatenated third copy is a third thing to get wrong. The format check
 * is deliberately loose on the bundle id — Apple permits a lot there — and
 * strict on the team id, which is always ten alphanumerics.
 */
export function appAttestAppId(source: EnvSource = denoEnv): string {
  const teamId = requireEnv("APPLE_TEAM_ID", source).trim();
  const bundleId = requireEnv("APPLE_BUNDLE_ID", source).trim();

  if (!/^[A-Z0-9]{10}$/.test(teamId)) {
    throw new ConfigError(
      `APPLE_TEAM_ID must be ten uppercase alphanumerics, got ${JSON.stringify(teamId)}`,
    );
  }
  if (!/^[A-Za-z0-9.-]{1,200}$/.test(bundleId) || !bundleId.includes(".")) {
    throw new ConfigError(
      `APPLE_BUNDLE_ID does not look like a bundle identifier: ${JSON.stringify(bundleId)}`,
    );
  }

  return `${teamId}.${bundleId}`;
}

/**
 * Apple's App Attest root certificate, PEM, from configuration.
 *
 * Not compiled in, and that is a decision rather than laziness. A pinned root
 * is the anchor the whole attestation chain hangs from: get its bytes wrong in
 * the harmless direction and every attestation fails, get them wrong in the
 * other and the server accepts a chain Apple never issued. Those bytes are
 * published by Apple and are not something to reproduce from memory, which is
 * the same reasoning D26 applied to charity EINs — a plausible-but-wrong value
 * for a security anchor is worse than an absent one, because absent fails
 * loudly.
 *
 * Absent, this throws, so a deployment that cannot verify attestations refuses
 * to serve rather than quietly accepting them. See the owner action in
 * DECISIONS.md.
 */
export function appAttestRootCertificate(source: EnvSource = denoEnv): string {
  // Supabase secrets are commonly uploaded from a one-line dotenv file. Accept
  // escaped newlines as well as an actual multiline PEM so the documented
  // staging setup round-trips without hand-editing the hosted secret.
  const pem = requireEnv("APP_ATTEST_ROOT_CA_PEM", source)
    .replaceAll("\\n", "\n")
    .trim();
  try {
    // Parse now, while the function module is loading. A marker-only check
    // would let a malformed trust anchor boot and fail every registration.
    new x509.X509Certificate(pem);
  } catch {
    throw new ConfigError(
      "APP_ATTEST_ROOT_CA_PEM is not a parseable X.509 certificate",
    );
  }
  return pem;
}

/**
 * Which App Attest environments this deployment will accept attestations from.
 *
 * A development attestation can be produced by a debug build on a device its
 * owner fully controls, so accepting one in production defeats the point of
 * asking. Permitted where no real contest data exists, refused in production
 * whatever the flag says — the same shape as the bypass guard above, for the
 * same reason.
 */
export function allowedAttestEnvironments(
  source: EnvSource = denoEnv,
): readonly ("development" | "production")[] {
  const env = runtimeEnv(source);
  const requested = boolEnv(
    "APP_ATTEST_ALLOW_DEVELOPMENT",
    env === "local" || env === "test",
    source,
  );

  if (requested && env === "production") {
    throw new ConfigError(
      "APP_ATTEST_ALLOW_DEVELOPMENT is enabled in GAMETIME_ENV=production; " +
        "a development attestation is not evidence of anything there",
    );
  }

  return requested ? ["development", "production"] : ["production"];
}

function namedSecretKey(raw: string, requestedName: string): string {
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    throw new ConfigError("SUPABASE_SECRET_KEYS is not valid JSON");
  }
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new ConfigError("SUPABASE_SECRET_KEYS is not a JSON object");
  }
  const selected = (value as Record<string, unknown>)[requestedName];
  if (typeof selected !== "string" || selected.trim() === "") {
    throw new ConfigError(
      `SUPABASE_SECRET_KEYS contains no non-empty ${JSON.stringify(requestedName)} key`,
    );
  }
  return selected;
}

/** The Data API endpoint and admin key that reach the guarded ingest RPCs. */
export function dataApiConfig(
  source: EnvSource = denoEnv,
): { url: string; serviceRoleKey: string; authorizationBearer: boolean } {
  const url = requireEnv("SUPABASE_URL", source).replace(/\/+$/, "");
  const modern = source("SUPABASE_SECRET_KEYS");
  if (modern !== undefined && modern.trim() !== "") {
    const name = optionalEnv("GAMETIME_ADMIN_KEY_NAME", "default", source).trim();
    return {
      url,
      serviceRoleKey: namedSecretKey(modern, name),
      // Opaque sb_secret_ keys authenticate in `apikey`; they are not JWTs.
      authorizationBearer: false,
    };
  }
  return {
    url,
    serviceRoleKey: requireEnv("SUPABASE_SERVICE_ROLE_KEY", source),
    authorizationBearer: true,
  };
}

/** Public hosted JWKS, with an explicit legacy fallback for local projects. */
export function accessTokenVerification(
  source: EnvSource = denoEnv,
): AccessTokenVerification {
  const projectUrl = requireEnv("SUPABASE_URL", source).replace(/\/+$/, "");
  const claims = {
    expectedIssuer: `${projectUrl}/auth/v1`,
    expectedAudience: "authenticated",
  } as const;
  const rawJwks = source("SUPABASE_JWKS");
  if (rawJwks !== undefined && rawJwks.trim() !== "") {
    let parsed: unknown;
    try {
      parsed = JSON.parse(rawJwks);
    } catch {
      throw new ConfigError("SUPABASE_JWKS is not valid JSON");
    }
    if (
      parsed === null || typeof parsed !== "object" || Array.isArray(parsed) ||
      !Array.isArray((parsed as { keys?: unknown }).keys)
    ) {
      throw new ConfigError("SUPABASE_JWKS is not a JSON Web Key Set");
    }
    const jwks = parsed as JsonWebKeySet;
    if (jwks.keys.length > 0) return { kind: "jwks", jwks, ...claims };
  }

  const env = runtimeEnv(source);
  const legacy = source("GAMETIME_LEGACY_JWT_SECRET") ??
    ((env === "local" || env === "test") ? source("SUPABASE_JWT_SECRET") : undefined);
  if (legacy === undefined || legacy.trim() === "") {
    throw new ConfigError(
      "no usable SUPABASE_JWKS or GAMETIME_LEGACY_JWT_SECRET is configured",
    );
  }
  if (legacy.length < 32) {
    throw new ConfigError("GAMETIME_LEGACY_JWT_SECRET is too short");
  }
  return { kind: "legacy-hs256", secret: legacy, ...claims };
}

/** Separate HMAC key for D47's short-lived, account-bound attest challenge. */
export function attestChallengeSecret(source: EnvSource = denoEnv): string {
  const configuredRaw = source("GAMETIME_ATTEST_CHALLENGE_SECRET");
  const configured = configuredRaw === undefined || configuredRaw.trim() === ""
    ? undefined
    : configuredRaw;
  const env = runtimeEnv(source);
  const localFallback = (env === "local" || env === "test")
    ? source("GAMETIME_LEGACY_JWT_SECRET") ?? source("SUPABASE_JWT_SECRET")
    : undefined;
  const secret = configured ?? localFallback;
  if (secret === undefined || secret.length < 32) {
    throw new ConfigError(
      "GAMETIME_ATTEST_CHALLENGE_SECRET must contain at least 32 characters",
    );
  }
  return secret;
}
