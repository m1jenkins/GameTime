import { HttpFailure, requireString, requireUuid } from "./http.ts";

export const PERSONAL_STRIPE_AGREEMENT_VERSION = "personal-stripe-sandbox-v1";
export const PERSONAL_STRIPE_CONSENT_VERSION = "personal-stripe-sandbox-consent-v1";
export const PERSONAL_STRIPE_CURRENCY = "USD";
export const PERSONAL_STRIPE_AMOUNTS_MINOR = [
  1_000,
  2_000,
  3_000,
  4_000,
  5_000,
] as const;

export type PersonalStripeCadence = "daily" | "cumulative";

export interface PersonalStripeTerms {
  readonly requestId: string;
  readonly cadence: PersonalStripeCadence;
  readonly targetSteps: number;
  readonly commitmentAmountMinor: number;
  readonly currency: typeof PERSONAL_STRIPE_CURRENCY;
  readonly timezone: string;
  readonly requestedStartsAt?: string;
  readonly agreementVersion: typeof PERSONAL_STRIPE_AGREEMENT_VERSION;
  readonly consentVersion: typeof PERSONAL_STRIPE_CONSENT_VERSION;
}

export function personalStripeTermsRpcArgs(
  terms: PersonalStripeTerms,
): Readonly<Record<string, unknown>> {
  return {
    p_request_id: terms.requestId,
    p_cadence: terms.cadence,
    p_target_steps: terms.targetSteps,
    p_commitment_amount_minor: terms.commitmentAmountMinor,
    p_currency: terms.currency,
    p_timezone: terms.timezone,
    p_requested_starts_at: terms.requestedStartsAt ?? null,
    p_agreement_version: terms.agreementVersion,
    p_consent_version: terms.consentVersion,
  };
}

function boundedInteger(
  body: Record<string, unknown>,
  field: string,
  minimum: number,
  maximum: number,
): number {
  const value = body[field];
  if (
    typeof value !== "number" ||
    !Number.isSafeInteger(value) ||
    value < minimum ||
    value > maximum
  ) {
    throw new HttpFailure(
      "bad_request",
      `${field} must be a whole number from ${minimum} through ${maximum}`,
    );
  }
  return value;
}

function optionalTimestamp(
  body: Record<string, unknown>,
  field: string,
): string | undefined {
  const value = body[field];
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string" || value.length > 64) {
    throw new HttpFailure("bad_request", `${field} must be a timestamp`);
  }
  const parsed = Date.parse(value);
  if (!Number.isFinite(parsed)) {
    throw new HttpFailure("bad_request", `${field} must be a timestamp`);
  }
  return new Date(parsed).toISOString();
}

export function parsePersonalStripeTerms(
  body: Record<string, unknown>,
): PersonalStripeTerms {
  const requestId = requireUuid(body, "requestId");
  const cadence = requireString(body, "cadence", 16);
  if (cadence !== "daily" && cadence !== "cumulative") {
    throw new HttpFailure(
      "bad_request",
      "cadence must be daily or cumulative",
    );
  }

  const targetSteps = boundedInteger(body, "targetSteps", 1, 1_000_000);
  const commitmentAmountMinor = boundedInteger(
    body,
    "commitmentAmountMinor",
    1_000,
    5_000,
  );
  if (
    !PERSONAL_STRIPE_AMOUNTS_MINOR.includes(
      commitmentAmountMinor as (typeof PERSONAL_STRIPE_AMOUNTS_MINOR)[number],
    )
  ) {
    throw new HttpFailure(
      "bad_request",
      "commitmentAmountMinor is not an allowed commitment",
    );
  }

  const currency = requireString(body, "currency", 3);
  if (currency !== PERSONAL_STRIPE_CURRENCY) {
    throw new HttpFailure("bad_request", "currency must be USD");
  }

  const timezone = requireString(body, "timezone", 80);
  const agreementVersion = requireString(body, "agreementVersion", 80);
  if (agreementVersion !== PERSONAL_STRIPE_AGREEMENT_VERSION) {
    throw new HttpFailure(
      "bad_request",
      "agreementVersion is not supported",
    );
  }
  const consentVersion = requireString(body, "consentVersion", 80);
  if (consentVersion !== PERSONAL_STRIPE_CONSENT_VERSION) {
    throw new HttpFailure("bad_request", "consentVersion is not supported");
  }
  if (body["consentAccepted"] !== true) {
    throw new HttpFailure(
      "bad_request",
      "consentAccepted must be true before saving a payment method",
    );
  }

  const requestedStartsAt = optionalTimestamp(body, "requestedStartsAt");
  return {
    requestId,
    cadence,
    targetSteps,
    commitmentAmountMinor,
    currency,
    timezone,
    agreementVersion,
    consentVersion,
    ...(requestedStartsAt === undefined ? {} : { requestedStartsAt }),
  };
}
