import { assertEquals, assertThrows } from "@std/assert";
import {
  accessTokenVerification,
  appAttestReceiptRootCertificate,
  appAttestRootCertificate,
  assertAttestConfigIsSafe,
  attestBypassEnabled,
  attestChallengeSecret,
  boolEnv,
  ConfigError,
  dataApiConfig,
  envFromRecord,
  optionalEnv,
  requireEnv,
  runtimeEnv,
} from "./env.ts";
import { makeRoot } from "../_test/appattest_fixtures.ts";

const root = await makeRoot("CN=Environment Test Root");
const LEGACY_SECRET = "legacy-jwt-secret-long-enough-for-real-verification";
const CHALLENGE_SECRET = "separate-attestation-challenge-secret-for-tests";

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

Deno.test("runtimeEnv defaults only local tooling and rejects unknown values", () => {
  assertEquals(runtimeEnv(envFromRecord({})), "local");
  assertEquals(runtimeEnv(envFromRecord({ GAMETIME_ENV: "PRODUCTION" })), "production");
  assertThrows(() => runtimeEnv(envFromRecord({ GAMETIME_ENV: "prod" })), ConfigError);
  assertThrows(
    () => runtimeEnv(envFromRecord({ DENO_DEPLOYMENT_ID: "project_function_1" })),
    ConfigError,
    "hosted deployment",
  );
  for (const unsafe of ["local", "test"]) {
    assertThrows(
      () =>
        runtimeEnv(envFromRecord({
          DENO_DEPLOYMENT_ID: "project_function_1",
          GAMETIME_ENV: unsafe,
        })),
      ConfigError,
      "forbidden in a hosted deployment",
    );
  }
  assertEquals(
    runtimeEnv(envFromRecord({
      SB_REGION: "us-east-1",
      GAMETIME_ENV: "staging",
    })),
    "staging",
  );
});

Deno.test("attest bypass is allowed in local and test", () => {
  for (const env of ["local", "test"]) {
    const source = envFromRecord({ GAMETIME_ENV: env, ATTEST_DEV_BYPASS: "true" });
    assertAttestConfigIsSafe(source);
    assertEquals(attestBypassEnabled(source), true);
  }
});

Deno.test("attest bypass is refused in staging and production", () => {
  for (const env of ["staging", "production"]) {
    const source = envFromRecord({ GAMETIME_ENV: env, ATTEST_DEV_BYPASS: "true" });
    assertThrows(() => assertAttestConfigIsSafe(source), ConfigError);
    assertThrows(() => attestBypassEnabled(source), ConfigError);
  }
});

Deno.test("production without the bypass flag is safe and reports false", () => {
  const source = envFromRecord({ GAMETIME_ENV: "production" });
  assertAttestConfigIsSafe(source);
  assertEquals(attestBypassEnabled(source), false);
});

Deno.test("the App Attest root is parsed at startup", () => {
  assertEquals(
    appAttestRootCertificate(envFromRecord({ APP_ATTEST_ROOT_CA_PEM: root.pem })),
    root.pem.trim(),
  );
  assertEquals(
    appAttestRootCertificate(envFromRecord({
      APP_ATTEST_ROOT_CA_PEM: root.pem.trim().replaceAll("\n", "\\n"),
    })),
    root.pem.trim(),
  );
  assertThrows(
    () =>
      appAttestRootCertificate(envFromRecord({
        APP_ATTEST_ROOT_CA_PEM:
          "-----BEGIN CERTIFICATE-----\nnot-a-certificate\n-----END CERTIFICATE-----",
      })),
    ConfigError,
    "parseable",
  );
});

Deno.test("the independent App Attest receipt root is parsed at startup", () => {
  assertEquals(
    appAttestReceiptRootCertificate(
      envFromRecord({ APP_ATTEST_RECEIPT_ROOT_CA_PEM: root.pem }),
    ),
    root.pem.trim(),
  );
  assertEquals(
    appAttestReceiptRootCertificate(envFromRecord({
      APP_ATTEST_RECEIPT_ROOT_CA_PEM: root.pem.trim().replaceAll("\n", "\\n"),
    })),
    root.pem.trim(),
  );
  assertThrows(
    () =>
      appAttestReceiptRootCertificate(envFromRecord({
        APP_ATTEST_RECEIPT_ROOT_CA_PEM:
          "-----BEGIN CERTIFICATE-----\nnot-a-certificate\n-----END CERTIFICATE-----",
      })),
    ConfigError,
    "APP_ATTEST_RECEIPT_ROOT_CA_PEM",
  );
});

Deno.test("hosted JWT verification uses the injected JWKS", () => {
  const jwks = {
    keys: [{
      kty: "EC",
      crv: "P-256",
      kid: "current",
      alg: "ES256",
      x: "x",
      y: "y",
    }],
  };
  assertEquals(
    accessTokenVerification(envFromRecord({
      GAMETIME_ENV: "staging",
      SUPABASE_URL: "https://staging-project.supabase.co",
      SUPABASE_JWKS: JSON.stringify(jwks),
    })),
    {
      kind: "jwks",
      jwks,
      expectedIssuer: "https://staging-project.supabase.co/auth/v1",
      expectedAudience: "authenticated",
    },
  );
  assertThrows(
    () =>
      accessTokenVerification(envFromRecord({
        GAMETIME_ENV: "staging",
        SUPABASE_URL: "https://staging-project.supabase.co",
        SUPABASE_JWKS: "{",
      })),
    ConfigError,
    "valid JSON",
  );
});

Deno.test("legacy JWT verification is explicit outside local", () => {
  assertEquals(
    accessTokenVerification(envFromRecord({
      GAMETIME_ENV: "staging",
      SUPABASE_URL: "https://staging-project.supabase.co",
      GAMETIME_LEGACY_JWT_SECRET: LEGACY_SECRET,
    })),
    {
      kind: "legacy-hs256",
      secret: LEGACY_SECRET,
      expectedIssuer: "https://staging-project.supabase.co/auth/v1",
      expectedAudience: "authenticated",
    },
  );
  assertThrows(
    () =>
      accessTokenVerification(envFromRecord({
        GAMETIME_ENV: "staging",
        SUPABASE_URL: "https://staging-project.supabase.co",
      })),
    ConfigError,
  );
  assertEquals(
    accessTokenVerification(envFromRecord({
      SUPABASE_URL: "http://127.0.0.1:54321",
      SUPABASE_JWT_SECRET: LEGACY_SECRET,
    })),
    {
      kind: "legacy-hs256",
      secret: LEGACY_SECRET,
      expectedIssuer: "http://127.0.0.1:54321/auth/v1",
      expectedAudience: "authenticated",
    },
  );
});

Deno.test("the attest challenge uses a separate deployed secret", () => {
  assertEquals(
    attestChallengeSecret(envFromRecord({
      GAMETIME_ENV: "staging",
      GAMETIME_ATTEST_CHALLENGE_SECRET: CHALLENGE_SECRET,
    })),
    CHALLENGE_SECRET,
  );
  assertThrows(
    () =>
      attestChallengeSecret(envFromRecord({
        GAMETIME_ENV: "staging",
        GAMETIME_LEGACY_JWT_SECRET: LEGACY_SECRET,
      })),
    ConfigError,
  );
  assertEquals(
    attestChallengeSecret(envFromRecord({
      GAMETIME_ENV: "local",
      GAMETIME_ATTEST_CHALLENGE_SECRET: "",
      SUPABASE_JWT_SECRET: LEGACY_SECRET,
    })),
    LEGACY_SECRET,
  );
});

Deno.test("Data API config prefers an injected opaque secret key", () => {
  assertEquals(
    dataApiConfig(envFromRecord({
      SUPABASE_URL: "https://project.example/",
      SUPABASE_SECRET_KEYS: JSON.stringify({ default: "sb_secret_staging" }),
    })),
    {
      url: "https://project.example",
      serviceRoleKey: "sb_secret_staging",
      authorizationBearer: false,
    },
  );
  assertEquals(
    dataApiConfig(envFromRecord({
      SUPABASE_URL: "http://127.0.0.1:54321",
      SUPABASE_SERVICE_ROLE_KEY: "legacy-service-role-jwt",
    })),
    {
      url: "http://127.0.0.1:54321",
      serviceRoleKey: "legacy-service-role-jwt",
      authorizationBearer: true,
    },
  );
});
