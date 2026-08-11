import type { PostgrestConfig } from "../_shared/database.ts";
import { serviceRpc } from "../_shared/service_rpc.ts";
import type { PushEnvironment } from "./apns.ts";

export interface PushDeliveryClaim {
  readonly delivery_id: string;
  readonly intent_id: number;
  readonly attempt_count: number;
  readonly device_token: string;
  readonly environment: PushEnvironment;
  readonly bundle_id: string;
  readonly contest_id: string;
  readonly snapshot_id: string;
  readonly event_type: "contest_lead_lost";
}

export interface PushDeliveryDatabase {
  claim(leaseOwner: string, limit: number): Promise<readonly PushDeliveryClaim[]>;
  record(
    deliveryId: string,
    leaseOwner: string,
    result: {
      readonly outcome: "delivered" | "retry" | "permanent_failure";
      readonly statusCode: number;
      readonly reason?: string;
    },
  ): Promise<void>;
}

function isClaim(value: unknown): value is PushDeliveryClaim {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return false;
  const row = value as Partial<PushDeliveryClaim>;
  return typeof row.delivery_id === "string" &&
    typeof row.intent_id === "number" &&
    typeof row.attempt_count === "number" &&
    typeof row.device_token === "string" &&
    (row.environment === "development" || row.environment === "production") &&
    typeof row.bundle_id === "string" &&
    typeof row.contest_id === "string" &&
    typeof row.snapshot_id === "string" &&
    row.event_type === "contest_lead_lost";
}

export function postgrestPushDeliveryDatabase(
  config: PostgrestConfig,
): PushDeliveryDatabase {
  return {
    async claim(leaseOwner, limit) {
      const result = await serviceRpc(config, "claim_push_deliveries_v1", {
        p_lease_owner: leaseOwner,
        p_limit: limit,
      });
      if (!Array.isArray(result) || !result.every(isClaim)) {
        throw new Error("claim_push_deliveries_v1 returned an unexpected shape");
      }
      return result;
    },

    async record(deliveryId, leaseOwner, result) {
      await serviceRpc(config, "record_push_delivery_v1", {
        p_delivery_id: deliveryId,
        p_lease_owner: leaseOwner,
        p_outcome: result.outcome,
        p_status_code: result.statusCode,
        p_reason: result.reason ?? null,
      });
    },
  };
}
