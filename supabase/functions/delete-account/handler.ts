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

export interface AccountDeletionProviderIds {
  readonly stripeCustomerId?: string;
}

export interface AccountDeletionDatabase {
  providerIds(ownerId: string): Promise<AccountDeletionProviderIds>;
  deleteAccount(ownerId: string): Promise<void>;
}

export interface AppleTokenRevoker {
  revokeAuthorizationCode(code: string): Promise<void>;
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

function requireAppleAuthorizationCode(body: Record<string, unknown>): string {
  const code = requireString(body, "appleAuthorizationCode", 4096);
  if (code.length < 8) {
    throw new HttpFailure(
      "bad_request",
      "appleAuthorizationCode is not valid",
    );
  }
  return code;
}

function customerId(providerIds: AccountDeletionProviderIds): string | undefined {
  const value = providerIds.stripeCustomerId;
  if (value === undefined) return undefined;
  if (!/^cus_[A-Za-z0-9]+$/.test(value) || value.length > 255) {
    throw new HttpFailure("internal", "the stored Stripe Customer is invalid");
  }
  return value;
}

export function createDeleteAccountHandler(
  deps: DeleteAccountDeps,
): (request: Request) => Promise<Response> {
  const clock = deps.now ?? (() => new Date());

  return (request) =>
    respond("delete-account", async () => {
      requirePost(request);

      let caller;
      try {
        caller = await deps.verifyToken(bearerToken(request), clock());
      } catch (error) {
        if (error instanceof AuthError) {
          throw new HttpFailure("unauthorized", "sign in again", error.message);
        }
        throw error;
      }

      const body = parseJsonObject(
        await readBody(request, MAX_DELETE_ACCOUNT_BODY_BYTES),
      );
      const authorizationCode = requireAppleAuthorizationCode(body);
      const providers = await deps.database.providerIds(caller.userId);

      // Apple revocation is deliberately first. If a later provider/database
      // call fails, the user can retry with a new Apple authorization code and
      // the endpoint will continue from the already-cleaned provider state.
      await deps.apple.revokeAuthorizationCode(authorizationCode);

      const stripeCustomerId = customerId(providers);
      if (stripeCustomerId !== undefined) {
        await deps.stripe.deleteTestCustomer(stripeCustomerId);
      }

      // This call returns a capability-bearing JSON document. It must never be
      // forwarded to the client; the endpoint exposes only completion status.
      await deps.database.deleteAccount(caller.userId);

      return jsonResponse(200, { deleted: true });
    });
}
