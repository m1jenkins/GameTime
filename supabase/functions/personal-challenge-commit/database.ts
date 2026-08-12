import type { PostgrestConfig } from "../_shared/database.ts";
import { personalStripeTermsRpcArgs } from "../_shared/personal_stripe_contract.ts";
import { oneServiceRow, requiredServiceString, serviceRpc } from "../_shared/service_rpc.ts";
import {
  PERSONAL_HEALTH_STEP_DATA_POLICY,
  type PersonalStripeCommitDatabase,
  type PersonalStripeCommitStepDataPolicy,
} from "./handler.ts";

export type PersonalStripeCommitRpcName =
  | "commit_personal_stripe_sandbox_challenge_service_v1"
  | "commit_personal_stripe_sandbox_challenge_service_v2";

export function personalStripeCommitRpcName(
  stepDataPolicy?: PersonalStripeCommitStepDataPolicy,
): PersonalStripeCommitRpcName {
  return stepDataPolicy === PERSONAL_HEALTH_STEP_DATA_POLICY
    ? "commit_personal_stripe_sandbox_challenge_service_v2"
    : "commit_personal_stripe_sandbox_challenge_service_v1";
}

export function postgrestPersonalStripeCommitDatabase(
  config: PostgrestConfig,
): PersonalStripeCommitDatabase {
  return {
    async loadSetupForCommit(args) {
      const result = await serviceRpc(
        config,
        "load_personal_stripe_sandbox_setup_service_v1",
        {
          p_owner_id: args.ownerId,
          p_setup_id: args.setupId,
          ...personalStripeTermsRpcArgs(args),
        },
      );
      const row = oneServiceRow(
        result,
        "load_personal_stripe_sandbox_setup_service_v1",
      );
      const consumed = row["consumed"] === true;
      const consumedChallengeId = row["consumed_challenge_id"];
      if (
        consumed !== (typeof consumedChallengeId === "string") ||
        (
          typeof consumedChallengeId === "string" &&
          !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
            .test(consumedChallengeId)
        )
      ) {
        throw new Error(
          "load_personal_stripe_sandbox_setup_service_v1 returned an invalid consumed challenge",
        );
      }
      return {
        stripeCustomerId: requiredServiceString(
          row,
          "stripe_customer_id",
          "cus_",
        ),
        stripeSetupIntentId: requiredServiceString(
          row,
          "stripe_setup_intent_id",
          "seti_",
        ),
        ...(typeof consumedChallengeId === "string" ? { consumedChallengeId } : {}),
      };
    },

    async recordSucceededSetup(args) {
      await serviceRpc(
        config,
        "record_personal_stripe_sandbox_setup_v1",
        {
          p_owner_id: args.ownerId,
          p_setup_id: args.setupId,
          p_stripe_customer_id: args.stripeCustomerId,
          p_stripe_setup_intent_id: args.stripeSetupIntentId,
          p_stripe_payment_method_id: args.stripePaymentMethodId,
          p_status: "succeeded",
        },
      );
    },

    async commitChallenge(args) {
      const rpcName = personalStripeCommitRpcName(args.stepDataPolicy);
      const result = await serviceRpc(
        config,
        rpcName,
        {
          p_owner_id: args.ownerId,
          p_setup_id: args.setupId,
          ...personalStripeTermsRpcArgs(args),
        },
      );
      const row = oneServiceRow(
        result,
        rpcName,
      );
      return {
        challengeId: requiredServiceString(row, "challenge_id"),
        replayed: row["replayed"] === true,
      };
    },
  };
}
