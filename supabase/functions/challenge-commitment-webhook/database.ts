import type { PostgrestConfig } from "../_shared/database.ts";
import { oneServiceRow, requiredServiceString, serviceRpc } from "../_shared/service_rpc.ts";
import { normalizedFailureCode } from "../challenge-commitment-charge/stripe.ts";
import type { CommitmentWebhookDatabase } from "./handler.ts";

export function postgrestCommitmentWebhookDatabase(
  config: PostgrestConfig,
): CommitmentWebhookDatabase {
  return {
    async applyWebhook(args) {
      const name = "challenge_commitment_apply_webhook_service_v1";
      const row = oneServiceRow(
        await serviceRpc(config, name, {
          p_event_id: args.stripeEventId,
          p_event_type: args.eventType,
          p_object_kind: args.objectKind,
          p_object_id: args.objectId,
          p_status: args.status,
          p_payment_method_id: args.stripePaymentMethodId ?? null,
          p_failure_code: args.failureCode === undefined
            ? null
            : normalizedFailureCode(args.failureCode, "provider_failed"),
          p_livemode: false,
        }),
        name,
      );
      return { disposition: requiredServiceString(row, "disposition") };
    },
  };
}
