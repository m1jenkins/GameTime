export const COMMITMENT_DISPATCH_SECRET_HEADER = "x-gametime-payment-dispatch-secret";

/** Hosted production is refused outright; this worker only runs in the sandbox. */
export const COMMITMENT_CHARGE_ENVIRONMENTS: readonly string[] = ["local", "staging"];

export interface CommitmentChargeClaim {
  readonly chargeId: string;
  readonly challengeId: string;
  readonly amountCents: number;
  readonly currency: "usd";
  readonly idempotencyKey: string;
  readonly stripeCustomerId: string;
  readonly stripePaymentMethodId: string;
}

export interface CommitmentChargeResult {
  readonly stripePaymentIntentId: string;
  readonly livemode: boolean;
  readonly status: "processing" | "succeeded" | "requires_action" | "failed";
  readonly failureCode?: string;
}

/** The provider call may or may not have happened; the same key is retried. */
export class CommitmentTransportAmbiguousError extends Error {
  override readonly name = "CommitmentTransportAmbiguousError";
}

/** Stripe refused the request itself before returning a PaymentIntent. */
export class CommitmentProviderRefusedError extends Error {
  override readonly name = "CommitmentProviderRefusedError";
  constructor(readonly failureCode: string) {
    super("Stripe refused the sandbox charge before returning a PaymentIntent");
  }
}

export interface CommitmentChargeDatabase {
  claim(leaseOwner: string, limit: number): Promise<readonly CommitmentChargeClaim[]>;
  record(args: {
    readonly chargeId: string;
    readonly leaseOwner: string;
    readonly status: "processing" | "succeeded" | "requires_action" | "failed";
    readonly stripePaymentIntentId?: string;
    readonly failureCode?: string;
  }): Promise<void>;
}

export interface CommitmentChargeGateway {
  createAndConfirm(claim: CommitmentChargeClaim): Promise<CommitmentChargeResult>;
}

export interface CommitmentChargeDeps {
  readonly deploymentEnvironment: string;
  readonly dispatchSecret: string;
  readonly database: CommitmentChargeDatabase;
  readonly stripe: CommitmentChargeGateway;
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

function json(status: number, body: Readonly<Record<string, unknown>>): Response {
  return Response.json(body, { status, headers: { "cache-control": "no-store" } });
}

/**
 * Dispatches queued commitment charges. A charge exists only after a personal
 * goal became final with a confirmed miss (see the D144 migration); this
 * worker makes one off-session sandbox charge per queued row and records the
 * outcome. Declines are final. Only transport ambiguity reuses the key.
 */
export function createCommitmentChargeHandler(
  deps: CommitmentChargeDeps,
): (request: Request) => Promise<Response> {
  if (!COMMITMENT_CHARGE_ENVIRONMENTS.includes(deps.deploymentEnvironment)) {
    throw new Error("commitment sandbox charging is restricted to local and staging");
  }
  if (deps.dispatchSecret.length < 32) {
    throw new Error("payment dispatch secret must contain at least 32 characters");
  }

  return async (request) => {
    if (request.method !== "POST") {
      return json(405, { error: "method_not_allowed" });
    }
    const supplied = request.headers.get(COMMITMENT_DISPATCH_SECRET_HEADER) ?? "";
    if (!sameSecret(supplied, deps.dispatchSecret)) {
      return json(401, { error: "unauthorized" });
    }

    const leaseOwner = deps.leaseOwner?.() ?? crypto.randomUUID();
    try {
      const claims = await deps.database.claim(leaseOwner, 10);
      const counts = { succeeded: 0, processing: 0, requires_action: 0, failed: 0, ambiguous: 0 };
      for (const claim of claims) {
        let result: CommitmentChargeResult;
        try {
          result = await deps.stripe.createAndConfirm(claim);
        } catch (error) {
          if (error instanceof CommitmentTransportAmbiguousError) {
            await deps.database.record({
              chargeId: claim.chargeId,
              leaseOwner,
              status: "processing",
            });
            counts.ambiguous += 1;
            continue;
          }
          if (error instanceof CommitmentProviderRefusedError) {
            await deps.database.record({
              chargeId: claim.chargeId,
              leaseOwner,
              status: "failed",
              failureCode: error.failureCode,
            });
            counts.failed += 1;
            continue;
          }
          throw error;
        }
        if (result.livemode) {
          throw new Error("Stripe returned a live PaymentIntent to the sandbox worker");
        }
        await deps.database.record({
          chargeId: claim.chargeId,
          leaseOwner,
          status: result.status,
          stripePaymentIntentId: result.stripePaymentIntentId,
          ...(result.failureCode === undefined ? {} : { failureCode: result.failureCode }),
        });
        counts[result.status] += 1;
      }
      return json(200, {
        claimed: claims.length,
        succeeded: counts.succeeded,
        processing: counts.processing,
        requires_action: counts.requires_action,
        failed: counts.failed,
        transport_ambiguous: counts.ambiguous,
      });
    } catch {
      return json(500, { error: "payment_dispatch_unavailable" });
    }
  };
}
