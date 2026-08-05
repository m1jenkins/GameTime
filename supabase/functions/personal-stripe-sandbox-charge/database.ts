import type { PostgrestConfig } from "../_shared/database.ts";
import { requiredServiceString, serviceRpc } from "../_shared/service_rpc.ts";
import type { PersonalStripeChargeClaim, PersonalStripeChargeDatabase } from "./handler.ts";

function isChargeClaim(value: unknown): value is PersonalStripeChargeClaim {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return false;
  }
  const row = value as Record<string, unknown>;
  return typeof row["command_id"] === "string" &&
    typeof row["challenge_id"] === "string" &&
    typeof row["result_id"] === "string" &&
    typeof row["amount_minor"] === "number" &&
    Number.isSafeInteger(row["amount_minor"]) &&
    row["amount_minor"] >= 1_000 &&
    row["amount_minor"] <= 5_000 &&
    row["currency"] === "USD" &&
    typeof row["stripe_customer_id"] === "string" &&
    row["stripe_customer_id"].startsWith("cus_") &&
    typeof row["stripe_payment_method_id"] === "string" &&
    row["stripe_payment_method_id"].startsWith("pm_") &&
    typeof row["stripe_idempotency_key"] === "string" &&
    row["stripe_idempotency_key"].startsWith("gt:personal-charge:v1:");
}

function claimFromRow(row: Record<string, unknown>): PersonalStripeChargeClaim {
  return {
    commandId: requiredServiceString(row, "command_id"),
    challengeId: requiredServiceString(row, "challenge_id"),
    resultId: requiredServiceString(row, "result_id"),
    amountMinor: row["amount_minor"] as number,
    currency: "USD",
    stripeCustomerId: requiredServiceString(
      row,
      "stripe_customer_id",
      "cus_",
    ),
    stripePaymentMethodId: requiredServiceString(
      row,
      "stripe_payment_method_id",
      "pm_",
    ),
    stripeIdempotencyKey: requiredServiceString(
      row,
      "stripe_idempotency_key",
      "gt:personal-charge:v1:",
    ),
  };
}

export function postgrestPersonalStripeChargeDatabase(
  config: PostgrestConfig,
): PersonalStripeChargeDatabase {
  return {
    async claim(leaseOwner, limit) {
      const result = await serviceRpc(
        config,
        "claim_personal_stripe_sandbox_charges_v1",
        {
          p_lease_owner: leaseOwner,
          p_limit: limit,
        },
      );
      if (
        !Array.isArray(result) ||
        !result.every(isChargeClaim)
      ) {
        throw new Error(
          "claim_personal_stripe_sandbox_charges_v1 returned an unexpected shape",
        );
      }
      return result.map((row) => claimFromRow(row as unknown as Record<string, unknown>));
    },

    async record(commandId, leaseOwner, result) {
      await serviceRpc(
        config,
        "record_personal_stripe_sandbox_charge_v1",
        {
          p_command_id: commandId,
          p_lease_owner: leaseOwner,
          p_stripe_payment_intent_id: "stripePaymentIntentId" in result
            ? result.stripePaymentIntentId
            : null,
          p_status: result.status,
          p_failure_code: result.failureCode ?? null,
        },
      );
    },
  };
}
