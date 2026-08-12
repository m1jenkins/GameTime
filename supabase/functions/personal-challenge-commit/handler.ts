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
export const PERSONAL_HEALTH_STEP_DATA_POLICY = "healthkit_nonmanual_daily_v1";

export type PersonalStripeCommitStepDataPolicy = typeof PERSONAL_HEALTH_STEP_DATA_POLICY;

export interface LoadPersonalStripeSetupArgs extends PersonalStripeTerms {
  readonly ownerId: string;
  readonly setupId: string;
  /** Missing for legacy builds; exact Health policy opts the commit into v2. */
  readonly stepDataPolicy?: PersonalStripeCommitStepDataPolicy;
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
      const rawStepDataPolicy = body["stepDataPolicy"];
      if (
        rawStepDataPolicy !== undefined &&
        rawStepDataPolicy !== PERSONAL_HEALTH_STEP_DATA_POLICY
      ) {
        throw new HttpFailure(
          "bad_request",
          "stepDataPolicy is not supported",
        );
      }
      const args: LoadPersonalStripeSetupArgs = {
        ownerId: caller.userId,
        setupId,
        ...parsePersonalStripeTerms(body),
        ...(rawStepDataPolicy === PERSONAL_HEALTH_STEP_DATA_POLICY
          ? { stepDataPolicy: PERSONAL_HEALTH_STEP_DATA_POLICY }
          : {}),
      };
      const loaded = await deps.database.loadSetupForCommit(args);
      if (loaded.consumedChallengeId !== undefined) {
        const committed = await deps.database.commitChallenge(args);
        if (
          !committed.replayed ||
          committed.challengeId !== loaded.consumedChallengeId
        ) {
          throw new HttpFailure(
            "internal",
            "the consumed payment setup did not replay its frozen challenge",
          );
        }
        return jsonResponse(200, {
          challengeId: committed.challengeId,
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
