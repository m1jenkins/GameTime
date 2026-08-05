import { assertEquals, assertThrows } from "@std/assert";
import type { EnvSource } from "./env.ts";
import { stripeSandboxConfig } from "./stripe_sandbox.ts";

function source(
  overrides: Readonly<Record<string, string | undefined>> = {},
): EnvSource {
  const values: Readonly<Record<string, string | undefined>> = {
    GAMETIME_ENV: "staging",
    STRIPE_SECRET_KEY: "sk_test_example",
    STRIPE_PUBLISHABLE_KEY: "pk_test_example",
    STRIPE_WEBHOOK_SECRET: "whsec_example",
    ...overrides,
  };
  return (name) => values[name];
}

Deno.test("loads only Stripe sandbox credentials outside production", () => {
  assertEquals(stripeSandboxConfig(source()), {
    secretKey: "sk_test_example",
    publishableKey: "pk_test_example",
    webhookSecret: "whsec_example",
  });
});

Deno.test("the sandbox integration cannot boot in production", () => {
  assertThrows(() => stripeSandboxConfig(source({ GAMETIME_ENV: "production" })));
});

Deno.test("rejects live or malformed Stripe API keys", () => {
  assertThrows(() => stripeSandboxConfig(source({ STRIPE_SECRET_KEY: "sk_live_example" })));
  assertThrows(() =>
    stripeSandboxConfig(
      source({ STRIPE_PUBLISHABLE_KEY: "pk_live_example" }),
    )
  );
});

Deno.test("webhook handlers require a Stripe signing secret", () => {
  assertThrows(() =>
    stripeSandboxConfig(
      source({ STRIPE_WEBHOOK_SECRET: undefined }),
      { requireWebhookSecret: true },
    )
  );
});
