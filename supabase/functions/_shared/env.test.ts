import { assertEquals, assertThrows } from "@std/assert";
import {
  assertAttestConfigIsSafe,
  attestBypassEnabled,
  boolEnv,
  ConfigError,
  envFromRecord,
  optionalEnv,
  requireEnv,
  runtimeEnv,
} from "./env.ts";

Deno.test("requireEnv returns a set value", () => {
  const env = envFromRecord({ APPLE_TEAM_ID: "ABCDE12345" });
  assertEquals(requireEnv("APPLE_TEAM_ID", env), "ABCDE12345");
});

Deno.test("requireEnv throws on unset and on blank", () => {
  const env = envFromRecord({ BLANK: "   " });
  assertThrows(() => requireEnv("MISSING", env), ConfigError);
  assertThrows(() => requireEnv("BLANK", env), ConfigError);
});

Deno.test("optionalEnv falls back on unset and on blank", () => {
  const env = envFromRecord({ SET: "value", BLANK: "" });
  assertEquals(optionalEnv("SET", "fallback", env), "value");
  assertEquals(optionalEnv("BLANK", "fallback", env), "fallback");
  assertEquals(optionalEnv("MISSING", "fallback", env), "fallback");
});

Deno.test("boolEnv accepts only true/false, case-insensitively", () => {
  const env = envFromRecord({ T: "true", F: "FALSE", PADDED: "  True  " });
  assertEquals(boolEnv("T", false, env), true);
  assertEquals(boolEnv("F", true, env), false);
  assertEquals(boolEnv("PADDED", false, env), true);
  assertEquals(boolEnv("MISSING", true, env), true);
});

Deno.test("boolEnv rejects truthy-looking values that are not true/false", () => {
  // A security flag set to "1" must fail loudly rather than silently
  // resolving to the default.
  for (const value of ["1", "0", "yes", "no", "on", "off", "TRUE!"]) {
    const env = envFromRecord({ FLAG: value });
    assertThrows(() => boolEnv("FLAG", false, env), ConfigError);
  }
});

Deno.test("runtimeEnv defaults to local and rejects unknown values", () => {
  assertEquals(runtimeEnv(envFromRecord({})), "local");
  assertEquals(runtimeEnv(envFromRecord({ SUPABASE_ENV: "PRODUCTION" })), "production");
  assertThrows(() => runtimeEnv(envFromRecord({ SUPABASE_ENV: "prod" })), ConfigError);
});

Deno.test("attest bypass is allowed in local and test", () => {
  for (const env of ["local", "test"]) {
    const source = envFromRecord({ SUPABASE_ENV: env, ATTEST_DEV_BYPASS: "true" });
    assertAttestConfigIsSafe(source);
    assertEquals(attestBypassEnabled(source), true);
  }
});

Deno.test("attest bypass is refused in staging and production", () => {
  for (const env of ["staging", "production"]) {
    const source = envFromRecord({ SUPABASE_ENV: env, ATTEST_DEV_BYPASS: "true" });
    assertThrows(() => assertAttestConfigIsSafe(source), ConfigError);
    assertThrows(() => attestBypassEnabled(source), ConfigError);
  }
});

Deno.test("production without the bypass flag is safe and reports false", () => {
  const source = envFromRecord({ SUPABASE_ENV: "production" });
  assertAttestConfigIsSafe(source);
  assertEquals(attestBypassEnabled(source), false);
});
