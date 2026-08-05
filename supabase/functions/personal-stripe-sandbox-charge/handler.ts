export const PAYMENT_DISPATCH_SECRET_HEADER = "x-gametime-payment-dispatch-secret";

export interface PersonalStripeChargeClaim {
  readonly commandId: string;
  readonly challengeId: string;
  readonly resultId: string;
  readonly amountMinor: number;
  readonly currency: string;
  readonly stripeCustomerId: string;
  readonly stripePaymentMethodId: string;
  readonly stripeIdempotencyKey: string;
}

export interface PersonalStripeChargeResult {
  readonly stripePaymentIntentId: string;
  readonly livemode: boolean;
  readonly status:
    | "processing"
    | "succeeded"
    | "requires_action"
    | "failed";
  readonly failureCode?: string;
}

export class StripeTransportAmbiguousError extends Error {
  override readonly name = "StripeTransportAmbiguousError";
}

export class StripeWorkerTerminalError extends Error {
  override readonly name = "StripeWorkerTerminalError";

  constructor(readonly failureCode: string) {
    super("Stripe refused the sandbox charge before returning a PaymentIntent");
  }
}

export interface PersonalStripeChargeDatabase {
  claim(
    leaseOwner: string,
    limit: number,
  ): Promise<readonly PersonalStripeChargeClaim[]>;
  record(
    commandId: string,
    leaseOwner: string,
    result:
      | PersonalStripeChargeResult
      | {
        readonly status: "transport_ambiguous";
        readonly failureCode: "stripe_transport_ambiguous";
      }
      | {
        readonly status: "worker_failed";
        readonly failureCode: string;
      },
  ): Promise<void>;
}

export interface PersonalStripeChargeGateway {
  createAndConfirm(args: PersonalStripeChargeClaim): Promise<
    PersonalStripeChargeResult
  >;
}

export interface PersonalStripeChargeDeps {
  readonly deploymentEnvironment: string;
  readonly dispatchSecret: string;
  readonly database: PersonalStripeChargeDatabase;
  readonly stripe: PersonalStripeChargeGateway;
  readonly leaseOwner?: () => string;
}

function sameSecret(left: string, right: string): boolean {
  const leftBytes = new TextEncoder().encode(left);
  const rightBytes = new TextEncoder().encode(right);
  let difference = leftBytes.length ^ rightBytes.length;
  const length = Math.max(leftBytes.length, rightBytes.length);
  for (let index = 0; index < length; index += 1) {
    difference |= (leftBytes[index] ?? 0) ^ (rightBytes[index] ?? 0);
  }
  return difference === 0;
}

function json(
  status: number,
  body: Readonly<Record<string, unknown>>,
): Response {
  return Response.json(body, {
    status,
    headers: { "cache-control": "no-store" },
  });
}

export function createPersonalStripeChargeHandler(
  deps: PersonalStripeChargeDeps,
): (request: Request) => Promise<Response> {
  if (deps.deploymentEnvironment !== "staging") {
    throw new Error(
      "personal Stripe sandbox charging is restricted to staging",
    );
  }
  if (deps.dispatchSecret.length < 32) {
    throw new Error(
      "payment dispatch secret must contain at least 32 characters",
    );
  }

  return async (request) => {
    if (request.method !== "POST") {
      return json(405, { error: "method_not_allowed" });
    }
    const supplied = request.headers.get(PAYMENT_DISPATCH_SECRET_HEADER) ??
      "";
    if (!sameSecret(supplied, deps.dispatchSecret)) {
      return json(401, { error: "unauthorized" });
    }

    const leaseOwner = deps.leaseOwner?.() ?? crypto.randomUUID();
    try {
      const claims = await deps.database.claim(leaseOwner, 10);
      let succeeded = 0;
      let processing = 0;
      let requiresAction = 0;
      let failed = 0;
      let ambiguous = 0;

      for (const claim of claims) {
        let result: PersonalStripeChargeResult;
        try {
          result = await deps.stripe.createAndConfirm(claim);
        } catch (error) {
          if (error instanceof StripeTransportAmbiguousError) {
            await deps.database.record(claim.commandId, leaseOwner, {
              status: "transport_ambiguous",
              failureCode: "stripe_transport_ambiguous",
            });
            ambiguous += 1;
            continue;
          }
          if (error instanceof StripeWorkerTerminalError) {
            await deps.database.record(claim.commandId, leaseOwner, {
              status: "worker_failed",
              failureCode: error.failureCode,
            });
            failed += 1;
            continue;
          }
          throw error;
        }

        // A provider call is the only ambiguity that may reuse the frozen
        // idempotency key. Database refusals and sandbox provenance failures
        // must fail closed instead of being mislabeled as retryable transport.
        if (result.livemode) {
          throw new Error(
            "Stripe returned a live PaymentIntent to the sandbox worker",
          );
        }
        await deps.database.record(claim.commandId, leaseOwner, result);
        switch (result.status) {
          case "succeeded":
            succeeded += 1;
            break;
          case "processing":
            processing += 1;
            break;
          case "requires_action":
            requiresAction += 1;
            break;
          case "failed":
            failed += 1;
            break;
        }
      }

      return json(200, {
        claimed: claims.length,
        succeeded,
        processing,
        requires_action: requiresAction,
        failed,
        transport_ambiguous: ambiguous,
      });
    } catch {
      return json(500, { error: "payment_dispatch_unavailable" });
    }
  };
}
