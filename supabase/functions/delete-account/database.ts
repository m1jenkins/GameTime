import { oneServiceRow, serviceRpc, ServiceRpcError } from "../_shared/service_rpc.ts";
import type {
  AccountDeletionDatabase,
  AccountDeletionProviderIdentity,
  AccountDeletionRecovery,
  AccountDeletionStatus,
  DeletionReviewReason,
} from "./handler.ts";
import { AccountDeletionRightsRejected } from "./handler.ts";

function rethrowDefinitiveRightsFailure(error: unknown): never {
  if (
    error instanceof ServiceRpcError &&
    ["22023", "23505", "55000"].includes(error.code ?? "")
  ) {
    throw new AccountDeletionRightsRejected();
  }
  throw error;
}

interface PostgrestConfig {
  readonly url: string;
  readonly serviceRoleKey: string;
  readonly authorizationBearer: boolean;
}

function deletionStatus(value: unknown, name: string): AccountDeletionStatus {
  const row = oneServiceRow(value, name);
  const state = row["state"];
  if (
    ![
      "pending_provider",
      "pending_account_close",
      "held",
      "completed",
      "expired",
    ].includes(state as string)
  ) {
    throw new Error(`${name} returned an invalid deletion state`);
  }
  return row as AccountDeletionStatus;
}

export function postgrestAccountDeletionDatabase(
  config: PostgrestConfig,
): AccountDeletionDatabase {
  return {
    async providerIdentity(ownerId): Promise<AccountDeletionProviderIdentity> {
      const row = oneServiceRow(
        await serviceRpc(
          config,
          "challenge_account_deletion_provider_identity_v1",
          { p_actor_id: ownerId },
        ),
        "challenge_account_deletion_provider_identity_v1",
      );
      const appleSubject = row["apple_subject"];
      const stripeCustomerId = row["stripe_customer_id"];
      if (
        typeof appleSubject !== "string" || appleSubject.length === 0 ||
        appleSubject.length > 255 ||
        (stripeCustomerId !== null && typeof stripeCustomerId !== "string")
      ) {
        throw new Error("account deletion provider identity is invalid");
      }
      return {
        appleSubject,
        ...(typeof stripeCustomerId === "string" ? { stripeCustomerId } : {}),
      };
    },
    async assertLiveSession(ownerId, sessionId) {
      await serviceRpc(config, "challenge_account_deletion_assert_live_session_v1", {
        p_actor_id: ownerId,
        p_session_id: sessionId,
      });
    },
    async begin(ownerId, requestId, receiptSecret, appleSubject, stripeCustomerId) {
      return deletionStatus(
        await serviceRpc(config, "challenge_begin_account_deletion_v1", {
          p_actor_id: ownerId,
          p_request_id: requestId,
          p_receipt_secret: receiptSecret,
          p_apple_subject: appleSubject,
          p_stripe_customer_id: stripeCustomerId ?? null,
        }),
        "challenge_begin_account_deletion_v1",
      );
    },
    async providerRecovery(receiptSecret, appleSubject): Promise<AccountDeletionRecovery> {
      const row = oneServiceRow(
        await serviceRpc(config, "challenge_account_deletion_provider_recovery_v1", {
          p_receipt_secret: receiptSecret,
          p_apple_subject: appleSubject,
        }),
        "challenge_account_deletion_provider_recovery_v1",
      );
      const actorId = row["actor_id"];
      const requestId = row["request_id"];
      const stripeCustomerId = row["stripe_customer_id"];
      if (
        typeof actorId !== "string" || typeof requestId !== "string" ||
        (stripeCustomerId !== null && typeof stripeCustomerId !== "string")
      ) {
        throw new Error("account deletion provider recovery is invalid");
      }
      return {
        actorId,
        requestId,
        ...(typeof stripeCustomerId === "string" ? { stripeCustomerId } : {}),
      };
    },
    async recovery(receiptSecret) {
      const row = oneServiceRow(
        await serviceRpc(config, "challenge_account_deletion_recovery_v1", {
          p_receipt_secret: receiptSecret,
        }),
        "challenge_account_deletion_recovery_v1",
      );
      const actorId = row["actor_id"];
      const requestId = row["request_id"];
      const state = row["state"];
      if (
        typeof actorId !== "string" || typeof requestId !== "string" ||
        !["pending_provider", "pending_account_close", "held", "completed"].includes(
          state as string,
        )
      ) {
        throw new Error("account deletion recovery is invalid");
      }
      return { actorId, requestId, state: state as AccountDeletionStatus["state"] };
    },
    async providerComplete(ownerId, requestId, receiptSecret, appleSubject) {
      return deletionStatus(
        await serviceRpc(config, "challenge_account_deletion_provider_complete_v1", {
          p_actor_id: ownerId,
          p_request_id: requestId,
          p_receipt_secret: receiptSecret,
          p_apple_subject: appleSubject,
        }),
        "challenge_account_deletion_provider_complete_v1",
      );
    },
    async complete(ownerId, requestId, receiptSecret) {
      return deletionStatus(
        await serviceRpc(config, "challenge_complete_account_deletion_v1", {
          p_actor_id: ownerId,
          p_request_id: requestId,
          p_receipt_secret: receiptSecret,
        }),
        "challenge_complete_account_deletion_v1",
      );
    },
    async status(receiptSecret) {
      return deletionStatus(
        await serviceRpc(config, "challenge_account_deletion_status_v1", {
          p_receipt_secret: receiptSecret,
        }),
        "challenge_account_deletion_status_v1",
      );
    },
    async advance(receiptSecret) {
      return deletionStatus(
        await serviceRpc(config, "challenge_advance_account_deletion_v1", {
          p_receipt_secret: receiptSecret,
        }),
        "challenge_advance_account_deletion_v1",
      );
    },
    async fileReview(
      receiptSecret,
      requestId,
      challengeId,
      noticeRevision,
      reason: DeletionReviewReason,
    ) {
      try {
        return oneServiceRow(
          await serviceRpc(config, "challenge_account_deletion_file_review_v1", {
            p_receipt_secret: receiptSecret,
            p_request_id: requestId,
            p_challenge_id: challengeId,
            p_notice_revision: noticeRevision,
            p_reason: reason,
          }),
          "challenge_account_deletion_file_review_v1",
        );
      } catch (error) {
        rethrowDefinitiveRightsFailure(error);
      }
    },
    async fileAppeal(receiptSecret, requestId) {
      try {
        return oneServiceRow(
          await serviceRpc(config, "challenge_account_deletion_file_appeal_v1", {
            p_receipt_secret: receiptSecret,
            p_request_id: requestId,
          }),
          "challenge_account_deletion_file_appeal_v1",
        );
      } catch (error) {
        rethrowDefinitiveRightsFailure(error);
      }
    },
  };
}
