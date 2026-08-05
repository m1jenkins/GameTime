import { toByteaLiteral } from "../_shared/bytes.ts";
import type { PostgrestConfig } from "../_shared/database.ts";
import { oneServiceRow, serviceRpc } from "../_shared/service_rpc.ts";
import type { PersonalStripeWebhookDatabase } from "./handler.ts";

export function postgrestPersonalStripeWebhookDatabase(
  config: PostgrestConfig,
): PersonalStripeWebhookDatabase {
  return {
    async applyWebhook(args) {
      const snapshot = args.snapshot;
      const result = await serviceRpc(
        config,
        "apply_personal_stripe_sandbox_webhook_v1",
        {
          p_stripe_event_id: args.stripeEventId,
          p_payload_digest: toByteaLiteral(args.payloadDigest),
          p_event_type: args.eventType,
          p_object_id: args.objectId,
          p_api_version: args.apiVersion ?? null,
          p_provider_created_at: args.providerCreatedAt,
          p_disposition: args.disposition,
          p_object_kind: snapshot?.kind ?? null,
          p_status: snapshot?.status ?? null,
          p_livemode: snapshot?.livemode ?? false,
          p_command_id: snapshot?.kind === "payment" ? snapshot.commandId ?? null : null,
          p_stripe_customer_id: snapshot?.stripeCustomerId ?? null,
          p_stripe_payment_method_id: snapshot?.stripePaymentMethodId ?? null,
          p_amount_minor: snapshot?.kind === "payment" ? snapshot.amountMinor : null,
          p_currency: snapshot?.kind === "payment" ? snapshot.currency : null,
          p_failure_code: snapshot?.kind === "payment" ? snapshot.failureCode ?? null : null,
        },
      );
      const row = oneServiceRow(
        result,
        "apply_personal_stripe_sandbox_webhook_v1",
      );
      return { replayed: row["replayed"] === true };
    },
  };
}
