import Stripe from "stripe";
import { type EnvSource, requireEnv, runtimeEnv } from "./env.ts";

export const STRIPE_API_VERSION = "2026-02-25.clover" as const;

export interface StripeSandboxConfig {
  readonly publishableKey: string;
  readonly secretKey: string;
  readonly webhookSecret?: string;
}

export function stripeSandboxConfig(
  source?: EnvSource,
  options: { readonly requireWebhookSecret?: boolean } = {},
): StripeSandboxConfig {
  const env = runtimeEnv(source);
  if (env === "production") {
    throw new Error(
      "the Personal Stripe sandbox integration cannot run in production",
    );
  }

  const secretKey = requireEnv("STRIPE_SECRET_KEY", source);
  const publishableKey = requireEnv("STRIPE_PUBLISHABLE_KEY", source);
  if (!secretKey.startsWith("sk_test_")) {
    throw new Error("STRIPE_SECRET_KEY must be a Stripe test secret key");
  }
  if (!publishableKey.startsWith("pk_test_")) {
    throw new Error(
      "STRIPE_PUBLISHABLE_KEY must be a Stripe test publishable key",
    );
  }

  const webhookSecret = source === undefined
    ? Deno.env.get("STRIPE_WEBHOOK_SECRET")
    : source("STRIPE_WEBHOOK_SECRET");
  if (
    options.requireWebhookSecret === true &&
    (webhookSecret === undefined || !webhookSecret.startsWith("whsec_"))
  ) {
    throw new Error(
      "STRIPE_WEBHOOK_SECRET must be a Stripe webhook signing secret",
    );
  }
  if (
    webhookSecret !== undefined &&
    webhookSecret !== "" &&
    !webhookSecret.startsWith("whsec_")
  ) {
    throw new Error(
      "STRIPE_WEBHOOK_SECRET must be a Stripe webhook signing secret",
    );
  }

  return {
    secretKey,
    publishableKey,
    ...(webhookSecret === undefined || webhookSecret === "" ? {} : { webhookSecret }),
  };
}

export function createStripeSandboxClient(secretKey: string): Stripe {
  return new Stripe(secretKey, {
    apiVersion: STRIPE_API_VERSION,
    httpClient: Stripe.createFetchHttpClient(),
  });
}

export function stripeObjectId(
  value:
    | string
    | { readonly id: string }
    | null
    | undefined,
): string | undefined {
  if (typeof value === "string") return value;
  return value?.id;
}
