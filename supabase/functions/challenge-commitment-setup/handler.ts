import {
  HttpFailure,
  jsonResponse,
  parseJsonObject,
  readBody,
  requirePost,
  respond,
} from "../_shared/http.ts";
import { type AccessTokenVerifier, AuthError, bearerToken } from "../_shared/jwt.ts";
import type {
  PersonalStripeSetupGateway,
  StripeSetupIntentSnapshot,
} from "../personal-payment-setup/handler.ts";

export const MAX_COMMITMENT_SETUP_BODY_BYTES = 4 * 1024;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export type CommitmentSetupStatus =
  | "pending_provider"
  | "requires_action"
  | "processing"
  | "succeeded"
  | "cancelled"
  | "consumed";

export interface BegunCommitmentSetup {
  readonly setupId: string;
  readonly status: CommitmentSetupStatus;
  readonly stripeCustomerId?: string;
  readonly stripeSetupIntentId?: string;
}

/** Database refusals the app can explain. Anything else is a server error. */
export class CommitmentRefusal extends Error {
  override readonly name = "CommitmentRefusal";
  constructor(readonly reason: string, readonly kind: "forbidden" | "rejected" | "bad_request") {
    super(reason);
  }
}

export interface CommitmentSetupDatabase {
  beginSetup(args: {
    readonly actorId: string;
    readonly requestId: string;
    readonly amountCents: number;
  }): Promise<BegunCommitmentSetup>;
  recordCustomer(args: {
    readonly actorId: string;
    readonly stripeCustomerId: string;
  }): Promise<void>;
  recordSetup(args: {
    readonly actorId: string;
    readonly setupId: string;
    readonly stripeSetupIntentId: string;
    readonly stripePaymentMethodId?: string;
    readonly status: string;
  }): Promise<{ readonly status: CommitmentSetupStatus }>;
}

export interface CommitmentSetupDeps {
  readonly database: CommitmentSetupDatabase;
  readonly stripe: PersonalStripeSetupGateway;
  readonly publishableKey: string;
  readonly verifyToken: AccessTokenVerifier;
  readonly now?: () => Date;
}

export function parseCommitmentSetupRequest(
  body: Record<string, unknown>,
): { readonly requestId: string; readonly amountCents: number } {
  const keys = Object.keys(body).sort();
  const requestId = body["requestId"];
  const amountCents = body["amountCents"];
  if (
    keys.join(",") !== "amountCents,requestId" ||
    typeof requestId !== "string" || !UUID.test(requestId) ||
    typeof amountCents !== "number" || !Number.isSafeInteger(amountCents) ||
    amountCents < 100 || amountCents > 5_000 || amountCents % 100 !== 0
  ) {
    throw new HttpFailure(
      "bad_request",
      "a request id and a whole-dollar amount from $1 to $50 are required",
    );
  }
  return { requestId, amountCents };
}

function requireSandbox(object: { readonly livemode: boolean }, kind: string): void {
  if (object.livemode) {
    throw new HttpFailure("internal", `${kind} was created outside the Stripe sandbox`);
  }
}

function requireClientSecret(snapshot: StripeSetupIntentSnapshot): string {
  if (
    snapshot.clientSecret === undefined ||
    !snapshot.clientSecret.startsWith(`${snapshot.id}_secret_`)
  ) {
    throw new HttpFailure("internal", "Stripe did not return a usable card setup secret");
  }
  return snapshot.clientSecret;
}

/**
 * Saves a card for a personal goal commitment in the Stripe sandbox.
 *
 * The same request id is sent twice: once to start (returns the secret the
 * app hands to Stripe's card sheet) and once after the sheet closes, which
 * re-reads the SetupIntent from Stripe and records whether the card was saved.
 * Nothing is charged here.
 */
export function createCommitmentSetupHandler(
  deps: CommitmentSetupDeps,
): (request: Request) => Promise<Response> {
  const clock = deps.now ?? (() => new Date());

  return (request) =>
    respond("challenge-commitment-setup", async () => {
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
      const { requestId, amountCents } = parseCommitmentSetupRequest(
        parseJsonObject(await readBody(request, MAX_COMMITMENT_SETUP_BODY_BYTES)),
      );

      try {
        const begun = await deps.database.beginSetup({
          actorId: caller.userId,
          requestId,
          amountCents,
        });
        if (begun.status === "consumed") {
          return jsonResponse(200, { setupId: begun.setupId, status: begun.status });
        }

        let customerId = begun.stripeCustomerId;
        if (customerId === undefined) {
          const customer = await deps.stripe.createCustomer({
            ownerId: caller.userId,
            idempotencyKey: `gt:challenge-commitment-customer:v1:${caller.userId}`,
          });
          requireSandbox(customer, "customer");
          customerId = customer.id;
          await deps.database.recordCustomer({
            actorId: caller.userId,
            stripeCustomerId: customerId,
          });
        }

        const setupIntent = begun.stripeSetupIntentId === undefined
          ? await deps.stripe.createSetupIntent({
            customerId,
            setupId: begun.setupId,
            requestId,
            idempotencyKey: `gt:challenge-commitment-setup:v1:${begun.setupId}`,
          })
          : await deps.stripe.retrieveSetupIntent(begun.stripeSetupIntentId);
        requireSandbox(setupIntent, "setup intent");
        if (setupIntent.customerId !== customerId) {
          throw new HttpFailure("internal", "Stripe returned a card setup for another customer");
        }

        const recorded = await deps.database.recordSetup({
          actorId: caller.userId,
          setupId: begun.setupId,
          stripeSetupIntentId: setupIntent.id,
          ...(setupIntent.status === "succeeded" && setupIntent.paymentMethodId !== undefined
            ? { stripePaymentMethodId: setupIntent.paymentMethodId }
            : {}),
          status: setupIntent.status,
        });

        return jsonResponse(begun.stripeSetupIntentId === undefined ? 201 : 200, {
          setupId: begun.setupId,
          publishableKey: deps.publishableKey,
          setupIntentClientSecret: requireClientSecret(setupIntent),
          status: recorded.status,
        });
      } catch (error) {
        if (error instanceof CommitmentRefusal) {
          throw new HttpFailure(error.kind, error.reason);
        }
        throw error;
      }
    });
}
