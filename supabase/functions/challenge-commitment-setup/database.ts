import type { PostgrestConfig } from "../_shared/database.ts";
import {
  oneServiceRow,
  requiredServiceString,
  serviceRpc,
  ServiceRpcError,
} from "../_shared/service_rpc.ts";
import {
  CommitmentRefusal,
  type CommitmentSetupDatabase,
  type CommitmentSetupStatus,
} from "./handler.ts";

const STATUSES: readonly CommitmentSetupStatus[] = [
  "pending_provider",
  "requires_action",
  "processing",
  "succeeded",
  "cancelled",
  "consumed",
];

function status(row: Record<string, unknown>): CommitmentSetupStatus {
  const value = row["status"];
  if (typeof value !== "string" || !STATUSES.includes(value as CommitmentSetupStatus)) {
    throw new Error("service RPC returned an invalid status");
  }
  return value as CommitmentSetupStatus;
}

/**
 * Maps the database's SQLSTATE to a reason the app can put into words. The
 * reason codes match the exceptions in the D144 migration.
 */
export function commitmentRefusal(error: unknown): unknown {
  if (!(error instanceof ServiceRpcError)) return error;
  switch (error.code) {
    case "42501":
      return new CommitmentRefusal("challenge_commitment_unavailable", "forbidden");
    case "55000":
      return new CommitmentRefusal("challenge_commitment_unpaid", "rejected");
    case "23505":
      return new CommitmentRefusal("challenge_commitment_limit", "rejected");
    case "22023":
      return new CommitmentRefusal("challenge_commitment_invalid_request", "bad_request");
    default:
      return error;
  }
}

async function call(
  config: PostgrestConfig,
  name: string,
  args: Readonly<Record<string, unknown>>,
): Promise<unknown> {
  try {
    return await serviceRpc(config, name, args);
  } catch (error) {
    throw commitmentRefusal(error);
  }
}

export function postgrestCommitmentSetupDatabase(
  config: PostgrestConfig,
): CommitmentSetupDatabase {
  return {
    async beginSetup(args) {
      const name = "challenge_commitment_begin_setup_service_v1";
      const row = oneServiceRow(
        await call(config, name, {
          p_actor: args.actorId,
          p_request_id: args.requestId,
          p_amount_cents: args.amountCents,
        }),
        name,
      );
      return {
        setupId: requiredServiceString(row, "setup_id"),
        status: status(row),
        ...(typeof row["stripe_customer_id"] === "string"
          ? { stripeCustomerId: requiredServiceString(row, "stripe_customer_id", "cus_") }
          : {}),
        ...(typeof row["stripe_setup_intent_id"] === "string"
          ? { stripeSetupIntentId: requiredServiceString(row, "stripe_setup_intent_id", "seti_") }
          : {}),
      };
    },

    async recordCustomer(args) {
      await call(config, "challenge_commitment_record_customer_service_v1", {
        p_actor: args.actorId,
        p_customer_id: args.stripeCustomerId,
        p_livemode: false,
      });
    },

    async recordSetup(args) {
      const name = "challenge_commitment_record_setup_service_v1";
      const row = oneServiceRow(
        await call(config, name, {
          p_actor: args.actorId,
          p_setup_id: args.setupId,
          p_setup_intent_id: args.stripeSetupIntentId,
          p_payment_method_id: args.stripePaymentMethodId ?? null,
          p_status: args.status,
          p_livemode: false,
        }),
        name,
      );
      return { status: status(row) };
    },
  };
}
