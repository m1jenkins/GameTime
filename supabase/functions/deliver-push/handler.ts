import type { PushTransport } from "./apns.ts";
import type { PushDeliveryDatabase } from "./database.ts";

export interface DeliverPushDependencies {
  readonly deploymentEnvironment: string;
  readonly dispatchSecret: string;
  readonly database: PushDeliveryDatabase;
  readonly transport: PushTransport;
  readonly leaseOwner?: () => string;
}

const STAGING_BUNDLE_ID = "com.mjenkins.gametime.staging";

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
  return Response.json(body, {
    status,
    headers: { "cache-control": "no-store" },
  });
}

export function createDeliverPushHandler(
  dependencies: DeliverPushDependencies,
): (request: Request) => Promise<Response> {
  if (dependencies.deploymentEnvironment !== "staging") {
    throw new Error("deliver-push is restricted to the staging environment");
  }
  if (dependencies.dispatchSecret.length < 32) {
    throw new Error("push dispatch secret must contain at least 32 characters");
  }

  return async (request) => {
    if (request.method !== "POST") {
      return json(405, { error: "method_not_allowed" });
    }
    const supplied = request.headers.get("x-gametime-dispatch-secret") ?? "";
    if (!sameSecret(supplied, dependencies.dispatchSecret)) {
      return json(401, { error: "unauthorized" });
    }

    const leaseOwner = dependencies.leaseOwner?.() ?? crypto.randomUUID();
    try {
      const claims = await dependencies.database.claim(leaseOwner, 25);
      let delivered = 0;
      let retrying = 0;
      let permanentlyFailed = 0;

      for (const claim of claims) {
        let result;
        if (
          claim.environment !== "development" ||
          claim.bundle_id !== STAGING_BUNDLE_ID
        ) {
          result = {
            outcome: "permanent_failure" as const,
            statusCode: 400,
            reason: "EnvironmentMismatch",
          };
        } else {
          try {
            result = await dependencies.transport.send({
              deviceToken: claim.device_token,
              environment: claim.environment,
              bundleId: claim.bundle_id,
              contestId: claim.contest_id,
              snapshotId: claim.snapshot_id,
            });
          } catch {
            result = {
              outcome: "retry" as const,
              statusCode: 503,
              reason: "TransportUnavailable",
            };
          }
        }

        await dependencies.database.record(
          claim.delivery_id,
          leaseOwner,
          result,
        );
        if (result.outcome === "delivered") delivered += 1;
        else if (result.outcome === "retry") retrying += 1;
        else permanentlyFailed += 1;
      }

      return json(200, {
        claimed: claims.length,
        delivered,
        retrying,
        permanently_failed: permanentlyFailed,
      });
    } catch {
      return json(500, { error: "delivery_unavailable" });
    }
  };
}
