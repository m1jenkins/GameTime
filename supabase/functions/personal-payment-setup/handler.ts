import type { PersonalStripeTerms } from "../_shared/personal_stripe_contract.ts";
import { parsePersonalStripeTerms } from "../_shared/personal_stripe_contract.ts";
import {
  HttpFailure,
  jsonResponse,
  parseJsonObject,
  readBody,
  requirePost,
  respond,
} from "../_shared/http.ts";
import { type AccessTokenVerifier, AuthError, bearerToken } from "../_shared/jwt.ts";

export const MAX_PAYMENT_SETUP_BODY_BYTES = 8 * 1024;

export type PersonalStripeSetupStatus =
  | "pending_provider"
  | "requires_action"
  | "processing"
  | "succeeded"
  | "failed"
  | "cancelled";

export interface BegunPersonalStripeSetup {
  readonly setupId: string;
  readonly replayed: boolean;
  readonly stripeCustomerId?: string;
  readonly stripeSetupIntentId?: string;
}

export interface PersonalStripeSetupDatabase {
  beginSetup(
    args: PersonalStripeTerms & { readonly ownerId: string },
  ): Promise<BegunPersonalStripeSetup>;
  recordCustomer(args: {
    readonly ownerId: string;
    readonly stripeCustomerId: string;
  }): Promise<void>;
  recordSetup(args: {
    readonly ownerId: string;
    readonly setupId: string;
    readonly stripeCustomerId: string;
    readonly stripeSetupIntentId: string;
    readonly stripePaymentMethodId?: string;
    readonly status: PersonalStripeSetupStatus;
  }): Promise<void>;
}

export interface StripeSetupIntentSnapshot {
  readonly id: string;
  readonly clientSecret?: string;
  readonly customerId: string;
  readonly paymentMethodId?: string;
  readonly livemode: boolean;
  readonly status: string;
}

export interface PersonalStripeSetupGateway {
  createCustomer(args: {
    readonly ownerId: string;
    readonly idempotencyKey: string;
  }): Promise<{ readonly id: string; readonly livemode: boolean }>;
  createSetupIntent(args: {
    readonly customerId: string;
    readonly setupId: string;
    readonly requestId: string;
    readonly idempotencyKey: string;
  }): Promise<StripeSetupIntentSnapshot>;
  retrieveSetupIntent(id: string): Promise<StripeSetupIntentSnapshot>;
}

export interface PersonalStripeSetupDeps {
  readonly database: PersonalStripeSetupDatabase;
  readonly stripe: PersonalStripeSetupGateway;
  readonly publishableKey: string;
  readonly verifyToken: AccessTokenVerifier;
  readonly now?: () => Date;
}

function normalizedStatus(status: string): PersonalStripeSetupStatus {
  switch (status) {
    case "requires_payment_method":
    case "requires_confirmation":
      return "pending_provider";
    case "requires_action":
      return "requires_action";
    case "processing":
      return "processing";
    case "succeeded":
      return "succeeded";
    case "canceled":
      return "cancelled";
    default:
      throw new HttpFailure(
        "internal",
        "Stripe returned an unsupported payment setup state",
      );
  }
}

function requireSandbox(
  object: { readonly livemode: boolean },
  kind: string,
): void {
  if (object.livemode) {
    throw new HttpFailure(
      "internal",
      `${kind} was created outside the Stripe sandbox`,
    );
  }
}

function requireClientSecret(
  snapshot: StripeSetupIntentSnapshot,
): string {
  if (
    snapshot.clientSecret === undefined ||
    !snapshot.clientSecret.startsWith(`${snapshot.id}_secret_`)
  ) {
    throw new HttpFailure(
      "internal",
      "Stripe did not return a usable payment setup secret",
    );
  }
  return snapshot.clientSecret;
}

export function createPersonalStripeSetupHandler(
  deps: PersonalStripeSetupDeps,
): (request: Request) => Promise<Response> {
  const clock = deps.now ?? (() => new Date());

  return (request) =>
    respond("personal-payment-setup", async () => {
      requirePost(request);

      let caller;
      try {
        caller = await deps.verifyToken(bearerToken(request), clock());
      } catch (error) {
        if (error instanceof AuthError) {
          throw new HttpFailure("unauthorized", "sign in again", error.message);
        }
        throw error;
      }

      const body = parseJsonObject(
        await readBody(request, MAX_PAYMENT_SETUP_BODY_BYTES),
      );
      const terms = parsePersonalStripeTerms(body);
      const begun = await deps.database.beginSetup({
        ownerId: caller.userId,
        ...terms,
      });

      let customerId = begun.stripeCustomerId;
      if (customerId === undefined) {
        const customer = await deps.stripe.createCustomer({
          ownerId: caller.userId,
          idempotencyKey: `gt:personal-customer:v1:${caller.userId}`,
        });
        requireSandbox(customer, "customer");
        customerId = customer.id;
        await deps.database.recordCustomer({
          ownerId: caller.userId,
          stripeCustomerId: customerId,
        });
      }

      const setupIntent = begun.stripeSetupIntentId === undefined
        ? await deps.stripe.createSetupIntent({
          customerId,
          setupId: begun.setupId,
          requestId: terms.requestId,
          idempotencyKey: `gt:personal-setup:v1:${begun.setupId}`,
        })
        : await deps.stripe.retrieveSetupIntent(
          begun.stripeSetupIntentId,
        );

      requireSandbox(setupIntent, "setup intent");
      if (setupIntent.customerId !== customerId) {
        throw new HttpFailure(
          "internal",
          "Stripe returned a payment setup for another customer",
        );
      }

      const status = normalizedStatus(setupIntent.status);
      await deps.database.recordSetup({
        ownerId: caller.userId,
        setupId: begun.setupId,
        stripeCustomerId: customerId,
        stripeSetupIntentId: setupIntent.id,
        ...(status === "succeeded" &&
            setupIntent.paymentMethodId !== undefined
          ? { stripePaymentMethodId: setupIntent.paymentMethodId }
          : {}),
        status,
      });

      return jsonResponse(begun.replayed ? 200 : 201, {
        setupId: begun.setupId,
        publishableKey: deps.publishableKey,
        setupIntentClientSecret: requireClientSecret(setupIntent),
        status,
        replayed: begun.replayed,
      });
    });
}
