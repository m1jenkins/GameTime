import type { PostgrestConfig } from "../_shared/database.ts";
import { oneServiceRow, requiredServiceString, serviceRpc } from "../_shared/service_rpc.ts";
import type { PersonalStripeReviewDatabase } from "./handler.ts";

export function postgrestPersonalStripeReviewDatabase(
  config: PostgrestConfig,
): PersonalStripeReviewDatabase {
  return {
    async requestReview(args) {
      const result = await serviceRpc(
        config,
        "request_personal_stripe_sandbox_review_service_v1",
        {
          p_owner_id: args.ownerId,
          p_challenge_id: args.challengeId,
          p_reason_code: args.reasonCode,
          p_reference: null,
        },
      );
      const row = oneServiceRow(
        result,
        "request_personal_stripe_sandbox_review_service_v1",
      );
      const reviewState = requiredServiceString(row, "review_state");
      const reviewDeadline = requiredServiceString(row, "review_deadline");
      if (
        reviewState !== "under_review" ||
        !Number.isFinite(Date.parse(reviewDeadline))
      ) {
        throw new Error(
          "request_personal_stripe_sandbox_review_service_v1 returned an unexpected shape",
        );
      }
      return {
        reviewState,
        reviewDeadline: new Date(reviewDeadline).toISOString(),
        replayed: row["replayed"] === true,
      };
    },
  };
}
