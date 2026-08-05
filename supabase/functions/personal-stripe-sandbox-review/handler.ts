import {
  HttpFailure,
  jsonResponse,
  parseJsonObject,
  readBody,
  requirePost,
  requireString,
  requireUuid,
  respond,
} from "../_shared/http.ts";
import { type AccessTokenVerifier, AuthError, bearerToken } from "../_shared/jwt.ts";

export const MAX_PERSONAL_REVIEW_BODY_BYTES = 2 * 1024;
export const PERSONAL_REVIEW_REASON_CODES = [
  "user_disputes_step_data",
  "user_disputes_result",
] as const;

export type PersonalReviewReasonCode = (typeof PERSONAL_REVIEW_REASON_CODES)[number];

export interface PersonalStripeReviewDatabase {
  requestReview(args: {
    readonly ownerId: string;
    readonly challengeId: string;
    readonly reasonCode: PersonalReviewReasonCode;
  }): Promise<{
    readonly reviewState: "under_review";
    readonly reviewDeadline: string;
    readonly replayed: boolean;
  }>;
}

export interface PersonalStripeReviewDeps {
  readonly deploymentEnvironment: string;
  readonly database: PersonalStripeReviewDatabase;
  readonly verifyToken: AccessTokenVerifier;
  readonly now?: () => Date;
}

export function createPersonalStripeReviewHandler(
  deps: PersonalStripeReviewDeps,
): (request: Request) => Promise<Response> {
  if (deps.deploymentEnvironment === "production") {
    throw new Error(
      "personal Stripe sandbox review requests are forbidden in production",
    );
  }
  const clock = deps.now ?? (() => new Date());

  return (request) =>
    respond("personal-stripe-sandbox-review", async () => {
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
        await readBody(request, MAX_PERSONAL_REVIEW_BODY_BYTES),
      );
      const challengeId = requireUuid(body, "challengeId");
      const reasonCode = requireString(body, "reasonCode", 64);
      if (
        !PERSONAL_REVIEW_REASON_CODES.includes(
          reasonCode as PersonalReviewReasonCode,
        )
      ) {
        throw new HttpFailure(
          "bad_request",
          "reasonCode is not a supported review reason",
        );
      }

      const result = await deps.database.requestReview({
        ownerId: caller.userId,
        challengeId,
        reasonCode: reasonCode as PersonalReviewReasonCode,
      });
      return jsonResponse(result.replayed ? 200 : 201, result);
    });
}
