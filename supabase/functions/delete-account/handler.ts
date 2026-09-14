import {
  HttpFailure,
  jsonResponse,
  parseJsonObject,
  readBody,
  requirePost,
  requireString,
  respond,
} from "../_shared/http.ts";
import { type AccessTokenVerifier, AuthError, bearerToken } from "../_shared/jwt.ts";

export const MAX_DELETE_ACCOUNT_BODY_BYTES = 8 * 1024;

export interface AccountDeletionProviderIdentity {
  readonly appleSubject: string;
  readonly stripeCustomerId?: string;
}

export interface AccountDeletionRecovery {
  readonly actorId: string;
  readonly requestId: string;
  readonly stripeCustomerId?: string;
}

export interface AccountDeletionStatus {
  readonly state: "pending_provider" | "pending_account_close" | "held" | "completed" | "expired";
  readonly [key: string]: unknown;
}

export type DeletionReviewReason = "wrong_total" | "missing_activity" | "wrong_result";

export interface AccountDeletionDatabase {
  providerIdentity(ownerId: string): Promise<AccountDeletionProviderIdentity>;
  assertLiveSession(ownerId: string, sessionId: string): Promise<void>;
  begin(
    ownerId: string,
    requestId: string,
    receiptSecret: string,
    appleSubject: string,
    stripeCustomerId?: string,
  ): Promise<AccountDeletionStatus>;
  providerRecovery(receiptSecret: string, appleSubject: string): Promise<AccountDeletionRecovery>;
  recovery(
    receiptSecret: string,
  ): Promise<
    Omit<AccountDeletionRecovery, "stripeCustomerId"> & {
      readonly state: AccountDeletionStatus["state"];
    }
  >;
  providerComplete(
    ownerId: string,
    requestId: string,
    receiptSecret: string,
    appleSubject: string,
  ): Promise<AccountDeletionStatus>;
  complete(
    ownerId: string,
    requestId: string,
    receiptSecret: string,
  ): Promise<AccountDeletionStatus>;
  status(receiptSecret: string): Promise<AccountDeletionStatus>;
  advance(receiptSecret: string): Promise<AccountDeletionStatus>;
  fileReview(
    receiptSecret: string,
    requestId: string,
    challengeId: string,
    noticeRevision: number,
    reason: DeletionReviewReason,
  ): Promise<Record<string, unknown>>;
  fileAppeal(receiptSecret: string, requestId: string): Promise<Record<string, unknown>>;
}

/** The returned object keeps Apple's revocation token in process memory only. */
export interface AppleAuthorization {
  readonly subject: string;
}

export interface AppleTokenRevoker {
  exchangeAuthorizationCode(code: string): Promise<AppleAuthorization>;
  revoke(authorization: AppleAuthorization): Promise<void>;
}

export interface StripeCustomerDeleter {
  deleteTestCustomer(customerId: string): Promise<void>;
}

export interface DeleteAccountDeps {
  readonly database: AccountDeletionDatabase;
  readonly apple: AppleTokenRevoker;
  readonly stripe: StripeCustomerDeleter;
  readonly verifyToken: AccessTokenVerifier;
  readonly now?: () => Date;
}

interface DeletionRequest {
  readonly requestId: string;
  readonly receiptSecret: string;
  readonly authorizationCode: string;
}

function requireUUID(body: Record<string, unknown>, field: string): string {
  const value = requireString(body, field, 64).toLowerCase();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(value)) {
    throw new HttpFailure("bad_request", `${field} is not valid`);
  }
  return value;
}

function requireReceiptSecret(body: Record<string, unknown>): string {
  const secret = requireString(body, "deletionReceipt", 512);
  if (secret.length < 32 || !/^[A-Za-z0-9_-]+$/.test(secret)) {
    throw new HttpFailure("bad_request", "deletionReceipt is not valid");
  }
  return secret;
}

function deletionRequest(body: Record<string, unknown>): DeletionRequest {
  const authorizationCode = requireString(body, "appleAuthorizationCode", 4096);
  if (authorizationCode.length < 8) {
    throw new HttpFailure("bad_request", "appleAuthorizationCode is not valid");
  }
  return {
    requestId: requireUUID(body, "deletionRequestId"),
    receiptSecret: requireReceiptSecret(body),
    authorizationCode,
  };
}

function reviewRequest(body: Record<string, unknown>): {
  readonly receiptSecret: string;
  readonly requestId: string;
  readonly challengeId: string;
  readonly noticeRevision: number;
  readonly reason: DeletionReviewReason;
} {
  const noticeRevision = body["noticeRevision"];
  const reason = requireString(body, "reason", 64);
  if (!Number.isInteger(noticeRevision) || (noticeRevision as number) < 1) {
    throw new HttpFailure("bad_request", "the review request is not valid");
  }
  if (
    !(["wrong_total", "missing_activity", "wrong_result"] as const).includes(
      reason as DeletionReviewReason,
    )
  ) {
    throw new HttpFailure("bad_request", "the review request is not valid");
  }
  return {
    receiptSecret: requireReceiptSecret(body),
    requestId: requireUUID(body, "deletionRequestId"),
    challengeId: requireUUID(body, "challengeId"),
    noticeRevision: noticeRevision as number,
    reason: reason as DeletionReviewReason,
  };
}

function customerId(value: string | undefined): string | undefined {
  if (value === undefined) return undefined;
  if (!/^cus_[A-Za-z0-9]+$/.test(value) || value.length > 255) {
    throw new HttpFailure("internal", "the stored payment customer is invalid");
  }
  return value;
}

function statusResponse(status: AccountDeletionStatus): Response {
  // Receipt expiry is the one terminal status the native client must treat as
  // removal of this restricted recovery path. It is deliberately not a
  // generic authorization failure: expiry cannot reopen the account or cause
  // the deletion workflow to run again.
  if (status.state === "expired") {
    return jsonResponse(410, { deleted: true, deletion: status });
  }
  const pending = status.state === "pending_provider" || status.state === "pending_account_close";
  return jsonResponse(pending ? 202 : 200, {
    deleted: !pending,
    deletion: status,
  });
}

function hasOnly(body: Record<string, unknown>, fields: readonly string[]): boolean {
  return Object.keys(body).every((key) => fields.includes(key));
}

async function finishProvider(
  deps: DeleteAccountDeps,
  request: DeletionRequest,
  recovery: AccountDeletionRecovery,
  authorization: AppleAuthorization,
): Promise<AccountDeletionStatus> {
  const bound = await deps.database.providerRecovery(
    request.receiptSecret,
    authorization.subject,
  );
  if (bound.actorId !== recovery.actorId || bound.requestId !== request.requestId) {
    throw new HttpFailure("forbidden", "the deletion request is unavailable");
  }
  await deps.apple.revoke(authorization);
  const stripeCustomerId = customerId(bound.stripeCustomerId);
  if (stripeCustomerId !== undefined) {
    await deps.stripe.deleteTestCustomer(stripeCustomerId);
  }
  let status = await deps.database.providerComplete(
    bound.actorId,
    request.requestId,
    request.receiptSecret,
    authorization.subject,
  );
  if (status.state === "pending_account_close") {
    status = await deps.database.complete(
      bound.actorId,
      request.requestId,
      request.receiptSecret,
    );
  }
  return status;
}

export function createDeleteAccountHandler(
  deps: DeleteAccountDeps,
): (request: Request) => Promise<Response> {
  const clock = deps.now ?? (() => new Date());
  return (request) =>
    respond("delete-account", async () => {
      requirePost(request);
      const body = parseJsonObject(await readBody(request, MAX_DELETE_ACCOUNT_BODY_BYTES));
      const operation = body["operation"];

      // This is the sole post-Auth access path. It can read status or make the
      // same saved request progress after a provider ambiguity; it cannot create
      // a new request, sign in, or expose legacy continuation capabilities.
      if (operation === "status") {
        if (!hasOnly(body, ["operation", "deletionReceipt"])) {
          throw new HttpFailure("bad_request", "the status request is not valid");
        }
        return statusResponse(await deps.database.advance(requireReceiptSecret(body)));
      }
      if (operation === "review") {
        if (
          !hasOnly(body, [
            "operation",
            "deletionReceipt",
            "deletionRequestId",
            "challengeId",
            "noticeRevision",
            "reason",
          ])
        ) {
          throw new HttpFailure("bad_request", "the review request is not valid");
        }
        const saved = reviewRequest(body);
        // This both enforces receipt expiry and avoids exposing a general
        // signed-out challenge read route. The RPC preserves the original
        // 48-hour notice and 72-hour reviewer windows.
        await deps.database.advance(saved.receiptSecret);
        return jsonResponse(200, {
          saved: await deps.database.fileReview(
            saved.receiptSecret,
            saved.requestId,
            saved.challengeId,
            saved.noticeRevision,
            saved.reason,
          ),
        });
      }
      if (operation === "appeal") {
        if (!hasOnly(body, ["operation", "deletionReceipt", "deletionRequestId"])) {
          throw new HttpFailure("bad_request", "the appeal request is not valid");
        }
        const receiptSecret = requireReceiptSecret(body);
        const requestId = requireUUID(body, "deletionRequestId");
        await deps.database.advance(receiptSecret);
        return jsonResponse(200, {
          saved: await deps.database.fileAppeal(receiptSecret, requestId),
        });
      }
      if (operation === "resume") {
        if (
          !hasOnly(body, [
            "operation",
            "deletionRequestId",
            "deletionReceipt",
            "appleAuthorizationCode",
          ])
        ) {
          throw new HttpFailure("bad_request", "the deletion request is not valid");
        }
        const saved = {
          requestId: requireUUID(body, "deletionRequestId"),
          receiptSecret: requireReceiptSecret(body),
        };
        // The actor is established only after an Apple exchange is matched to the
        // stored digest. A deliberately empty recovery object prevents an
        // accidental status request from acquiring provider authority.
        const recovered = await deps.database.recovery(saved.receiptSecret);
        if (recovered.requestId !== saved.requestId) {
          throw new HttpFailure("forbidden", "the deletion request is unavailable");
        }
        if (recovered.state === "held" || recovered.state === "completed") {
          return statusResponse(await deps.database.advance(saved.receiptSecret));
        }
        if (recovered.state === "pending_account_close") {
          return statusResponse(
            await deps.database.complete(recovered.actorId, saved.requestId, saved.receiptSecret),
          );
        }
        const authorizationCode = requireString(body, "appleAuthorizationCode", 4096);
        if (authorizationCode.length < 8) {
          throw new HttpFailure("bad_request", "appleAuthorizationCode is not valid");
        }
        try {
          const authorization = await deps.apple.exchangeAuthorizationCode(authorizationCode);
          let bound: AccountDeletionRecovery;
          try {
            bound = await deps.database.providerRecovery(
              saved.receiptSecret,
              authorization.subject,
            );
          } catch {
            // Possession of a receipt alone cannot authorize a different Apple
            // account to continue provider cleanup.
            throw new HttpFailure("forbidden", "the Apple confirmation is for a different account");
          }
          if (bound.requestId !== saved.requestId) {
            throw new HttpFailure("forbidden", "the deletion request is unavailable");
          }
          await deps.apple.revoke(authorization);
          const stripeCustomerId = customerId(bound.stripeCustomerId);
          if (stripeCustomerId !== undefined) {
            await deps.stripe.deleteTestCustomer(stripeCustomerId);
          }
          let status = await deps.database.providerComplete(
            bound.actorId,
            saved.requestId,
            saved.receiptSecret,
            authorization.subject,
          );
          if (status.state === "pending_account_close") {
            status = await deps.database.complete(
              bound.actorId,
              saved.requestId,
              saved.receiptSecret,
            );
          }
          return statusResponse(status);
        } catch (error) {
          if (error instanceof HttpFailure) throw error;
          // The exact receipt was already recovered above. A provider failure
          // is therefore safe to report as pending, while an expired or bad
          // receipt never becomes a fake pending request.
          return jsonResponse(202, { deleted: false, deletion: { state: "pending_provider" } });
        }
      }
      if (
        operation !== undefined ||
        !hasOnly(body, ["deletionRequestId", "deletionReceipt", "appleAuthorizationCode"])
      ) {
        throw new HttpFailure("bad_request", "the deletion request is not valid");
      }

      let caller;
      try {
        caller = await deps.verifyToken(bearerToken(request), clock());
      } catch (error) {
        if (error instanceof AuthError) {
          throw new HttpFailure("unauthorized", "sign in again", error.message);
        }
        throw error;
      }
      const saved = deletionRequest(body);
      const provider = await deps.database.providerIdentity(caller.userId);
      if (caller.sessionId === undefined) {
        throw new HttpFailure("unauthorized", "sign in again");
      }
      try {
        await deps.database.assertLiveSession(caller.userId, caller.sessionId);
      } catch {
        throw new HttpFailure("unauthorized", "sign in again");
      }
      const authorization = await deps.apple.exchangeAuthorizationCode(saved.authorizationCode);
      if (authorization.subject !== provider.appleSubject) {
        throw new HttpFailure("forbidden", "the Apple confirmation is for a different account");
      }
      let status = await deps.database.begin(
        caller.userId,
        saved.requestId,
        saved.receiptSecret,
        provider.appleSubject,
        provider.stripeCustomerId,
      );
      if (status.state !== "pending_provider") {
        return statusResponse(status);
      }

      try {
        status = await finishProvider(deps, saved, {
          actorId: caller.userId,
          requestId: saved.requestId,
        }, authorization);
        return statusResponse(status);
      } catch (error) {
        if (error instanceof HttpFailure) throw error;
        // The durable request already closed ordinary access. Tell the app that
        // provider cleanup is pending; never call this a completed deletion.
        return statusResponse(status);
      }
    });
}
