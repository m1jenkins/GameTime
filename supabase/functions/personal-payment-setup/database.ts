import type { PostgrestConfig } from "../_shared/database.ts";
import { personalStripeTermsRpcArgs } from "../_shared/personal_stripe_contract.ts";
import { oneServiceRow, requiredServiceString, serviceRpc } from "../_shared/service_rpc.ts";
import type { PersonalStripeSetupDatabase } from "./handler.ts";

export function postgrestPersonalStripeSetupDatabase(
  config: PostgrestConfig,
): PersonalStripeSetupDatabase {
  return {
    async beginSetup(args) {
      const result = await serviceRpc(
        config,
        "begin_personal_stripe_sandbox_setup_service_v1",
        {
          p_owner_id: args.ownerId,
          ...personalStripeTermsRpcArgs(args),
        },
      );
      const row = oneServiceRow(
        result,
        "begin_personal_stripe_sandbox_setup_service_v1",
      );
      return {
        setupId: requiredServiceString(row, "setup_id"),
        replayed: row["replayed"] === true,
        ...(typeof row["stripe_customer_id"] === "string"
          ? {
            stripeCustomerId: requiredServiceString(
              row,
              "stripe_customer_id",
              "cus_",
            ),
          }
          : {}),
        ...(typeof row["stripe_setup_intent_id"] === "string"
          ? {
            stripeSetupIntentId: requiredServiceString(
              row,
              "stripe_setup_intent_id",
              "seti_",
            ),
          }
          : {}),
      };
    },

    async recordCustomer(args) {
      await serviceRpc(
        config,
        "record_personal_stripe_sandbox_customer_v1",
        {
          p_owner_id: args.ownerId,
          p_stripe_customer_id: args.stripeCustomerId,
        },
      );
    },

    async recordSetup(args) {
      await serviceRpc(
        config,
        "record_personal_stripe_sandbox_setup_v1",
        {
          p_owner_id: args.ownerId,
          p_setup_id: args.setupId,
          p_stripe_customer_id: args.stripeCustomerId,
          p_stripe_setup_intent_id: args.stripeSetupIntentId,
          p_stripe_payment_method_id: args.stripePaymentMethodId ?? null,
          p_status: args.status,
        },
      );
    },
  };
}
