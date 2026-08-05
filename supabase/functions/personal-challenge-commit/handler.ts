import {
  parsePersonalStripeTerms,
  type PersonalStripeTerms,
} from "../_shared/personal_stripe_contract.ts";
import {
  HttpFailure,
  jsonResponse,
  parseJsonObject,
  readBody,
  requirePost,
  requireUuid,
  respond,
} from "../_shared/http.ts";
import { type AccessTokenVerifier, AuthError, bearerToken } from "../_shared/jwt.ts";
import type { PersonalStripeSetupGateway } from "../personal-payment-setup/handler.ts";

export const MAX_CHALLENGE_COMMIT_BODY_BYTES = 8 * 1024;

export interface LoadPersonalStripeSetupArgs extends PersonalStripeTerms {
  readonly ownerId: string;
  readonly setupId: string;
}

export interface LoadedPersonalStripeSetup {
  readonly stripeCustomerId: string;
  readonly stripeSetupIntentId: string;
  readonly consumedChallengeId?: string;
}

export interface CommittedPersonalStripeChallenge {
  readonly challengeId: string;
  readonly replayed: boolean;
}

export interface PersonalStripeCommitDatabase {
  loadSetupForCommit(
    args: LoadPersonalStripeSetupArgs,
  ): Promise<LoadedPersonalStripeSetup>;
  recordSucceededSetup(args: {
    readonly ownerId: string;
    readonly setupId: string;
    readonly stripeCustomerId: string;
    readonly stripeSetupIntentId: string;
    readonly stripePaymentMethodId: string;
  }): Promise<void>;
  commitChallenge(
    args: LoadPersonalStripeSetupArgs,
  ): Promise<CommittedPersonalStripeChallenge>;
}

export interface PersonalStripeCommitDeps {
  readonly database: PersonalStripeCommitDatabase;
  readonly stripe: Pick<PersonalStripeSetupGateway, "retrieveSetupIntent">;
  readonly verifyToken: AccessTokenVerifier;
  readonly now?: () => Date;
}

export function createPersonalStripeCommitHandler(
  deps: PersonalStripeCommitDeps,
): (request: Request) => Promise<Response> {
  const clock = deps.now ?? (() => new Date());

  return (request) =>
    respond("personal-challenge-commit", async () => {
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
        await readBody(request, MAX_CHALLENGE_COMMIT_BODY_BYTES),
      );
      const setupId = requireUuid(body, "setupId");
      const args = {
        ownerId: caller.userId,
        setupId,
        ...parsePersonalStripeTerms(body),
      };
      const loaded = await deps.database.loadSetupForCommit(args);
      if (loaded.consumedChallengeId !== undefined) {
        return jsonResponse(200, {
          challengeId: loaded.consumedChallengeId,
          paymentState: "method_saved",
          replayed: true,
        });
      }
      const setupIntent = await deps.stripe.retrieveSetupIntent(
        loaded.stripeSetupIntentId,
      );

      if (setupIntent.livemode) {
        throw new HttpFailure(
          "internal",
          "a live payment setup cannot enter the sandbox challenge flow",
        );
      }
      if (
        setupIntent.id !== loaded.stripeSetupIntentId ||
        setupIntent.customerId !== loaded.stripeCustomerId
      ) {
        throw new HttpFailure(
          "internal",
          "Stripe returned a payment setup for different frozen terms",
        );
      }
      if (
        setupIntent.status !== "succeeded" ||
        setupIntent.paymentMethodId === undefined ||
        !setupIntent.paymentMethodId.startsWith("pm_")
      ) {
        throw new HttpFailure(
          "rejected",
          "finish saving your payment method before starting the challenge",
        );
      }

      await deps.database.recordSucceededSetup({
        ownerId: caller.userId,
        setupId,
        stripeCustomerId: loaded.stripeCustomerId,
        stripeSetupIntentId: setupIntent.id,
        stripePaymentMethodId: setupIntent.paymentMethodId,
      });
      const committed = await deps.database.commitChallenge(args);

      return jsonResponse(committed.replayed ? 200 : 201, {
        challengeId: committed.challengeId,
        paymentState: "method_saved",
        replayed: committed.replayed,
      });
    });
}
