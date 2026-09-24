import type { PostgrestConfig } from "../_shared/database.ts";
import { requiredServiceString, serviceRpc } from "../_shared/service_rpc.ts";
import type { CommitmentChargeClaim, CommitmentChargeDatabase } from "./handler.ts";

function claimFromRow(value: unknown): CommitmentChargeClaim {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("challenge_commitment_claim_charges_service_v1 returned an unexpected shape");
  }
  const row = value as Record<string, unknown>;
  const amount = row["amount_cents"];
  if (
    typeof amount !== "number" || !Number.isSafeInteger(amount) || amount < 100 ||
    amount > 5_000 || row["currency"] !== "usd"
  ) {
    throw new Error("challenge_commitment_claim_charges_service_v1 returned an invalid amount");
  }
  return {
    chargeId: requiredServiceString(row, "charge_id"),
    challengeId: requiredServiceString(row, "challenge_id"),
    amountCents: amount,
    currency: "usd",
    idempotencyKey: requiredServiceString(row, "idempotency_key", "gt:challenge-commitment:v1:"),
    stripeCustomerId: requiredServiceString(row, "stripe_customer_id", "cus_"),
    stripePaymentMethodId: requiredServiceString(row, "stripe_payment_method_id", "pm_"),
  };
}

export function postgrestCommitmentChargeDatabase(
  config: PostgrestConfig,
): CommitmentChargeDatabase {
  return {
    async claim(leaseOwner, limit) {
      const result = await serviceRpc(config, "challenge_commitment_claim_charges_service_v1", {
        p_lease_owner: leaseOwner,
        p_limit: limit,
      });
      if (!Array.isArray(result)) {
        throw new Error(
          "challenge_commitment_claim_charges_service_v1 returned an unexpected shape",
        );
      }
      return result.map(claimFromRow);
    },

    async record(args) {
      await serviceRpc(config, "challenge_commitment_record_charge_service_v1", {
        p_charge_id: args.chargeId,
        p_lease_owner: args.leaseOwner,
        p_status: args.status,
        p_payment_intent_id: args.stripePaymentIntentId ?? null,
        p_failure_code: args.failureCode ?? null,
        p_livemode: false,
      });
    },
  };
}
