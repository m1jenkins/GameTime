/**
 * POST /activity-diagnostic
 *
 * A diagnostic is successful only when a signed production code path reports a
 * fresh HealthKit read containing at least one trusted Apple-device sample.
 * The App Attest assertion covers the exact body bytes. The database consumes
 * the assertion counter, makes exact retries idempotent, and is the only layer
 * allowed to clear an eligibility hold.
 */

import { AttestationError, base64ToBytes, verifyAssertion } from "../_shared/appattest.ts";
import { type Bytes, sha256 } from "../_shared/bytes.ts";
import { asCborBytes, asCborMap, CborError, decodeCbor } from "../_shared/cbor.ts";
import type {
  ActivityDiagnosticDatabase,
  RecordActivityDiagnosticArgs,
  RecordedActivityDiagnostic,
} from "../_shared/database.ts";
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

export const MAX_DIAGNOSTIC_BODY_BYTES = 16 * 1024;
export const DIAGNOSTIC_KEY_ID_HEADER = "x-gametime-key-id";
export const DIAGNOSTIC_ASSERTION_HEADER = "x-gametime-assertion";

export type {
  ActivityDiagnosticDatabase,
  RecordActivityDiagnosticArgs,
  RecordedActivityDiagnostic,
};

export interface ActivityDiagnosticDeps {
  readonly database: ActivityDiagnosticDatabase;
  readonly appId: string;
  readonly additionalAppIds?: readonly string[];
  readonly verifyToken: AccessTokenVerifier;
  readonly publicKeyFor: (keyId: Bytes) => Promise<Bytes | undefined>;
  readonly now?: () => Date;
}

function timestamp(body: Record<string, unknown>, field: string): string {
  const raw = requireString(body, field, 64);
  const parsed = Date.parse(raw);
  if (!Number.isFinite(parsed)) {
    throw new HttpFailure("bad_request", `${field} is not a timestamp`);
  }
  return new Date(parsed).toISOString();
}

function positiveSampleCount(body: Record<string, unknown>): number {
  const value = body["trustedDeviceSampleCount"];
  if (
    typeof value !== "number" || !Number.isSafeInteger(value) || value < 1 ||
    value > 100_000
  ) {
    throw new HttpFailure(
      "bad_request",
      "trustedDeviceSampleCount is not a positive bounded count",
    );
  }
  return value;
}

function openAssertion(bytes: Bytes) {
  try {
    const outer = asCborMap(decodeCbor(bytes), "assertion");
    return {
      signature: asCborBytes(outer["signature"], "signature"),
      authenticatorData: asCborBytes(
        outer["authenticatorData"],
        "authenticatorData",
      ),
    };
  } catch (error) {
    if (error instanceof CborError) {
      throw new HttpFailure(
        "bad_request",
        "the assertion is not a well-formed assertion object",
        error.message,
      );
    }
    throw error;
  }
}

function decodeHeader(value: string, name: string): Bytes {
  try {
    return base64ToBytes(value, name);
  } catch (error) {
    if (error instanceof AttestationError) {
      throw new HttpFailure("bad_request", `${name} is not valid base64`);
    }
    throw error;
  }
}

export function createActivityDiagnosticHandler(
  deps: ActivityDiagnosticDeps,
): (request: Request) => Promise<Response> {
  const clock = deps.now ?? (() => new Date());
  const appIds = [deps.appId, ...(deps.additionalAppIds ?? [])];

  return (request) =>
    respond("activity-diagnostic", async () => {
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

      const raw = await readBody(request, MAX_DIAGNOSTIC_BODY_BYTES);
      const payloadDigest = await sha256(raw);
      const body = parseJsonObject(raw);

      const clientDiagnosticId = requireUuid(body, "clientDiagnosticId");
      const observedAt = timestamp(body, "observedAt");
      const healthKitReadStartedAt = timestamp(body, "healthKitReadStartedAt");
      const healthKitReadEndedAt = timestamp(body, "healthKitReadEndedAt");
      if (Date.parse(healthKitReadEndedAt) <= Date.parse(healthKitReadStartedAt)) {
        throw new HttpFailure(
          "bad_request",
          "healthKitReadEndedAt must be after healthKitReadStartedAt",
        );
      }
      const trustedDeviceSampleCount = positiveSampleCount(body);

      const keyIdHeader = request.headers.get(DIAGNOSTIC_KEY_ID_HEADER);
      const assertionHeader = request.headers.get(DIAGNOSTIC_ASSERTION_HEADER);
      if (keyIdHeader === null || assertionHeader === null) {
        throw new HttpFailure(
          "bad_request",
          `both ${DIAGNOSTIC_KEY_ID_HEADER} and ${DIAGNOSTIC_ASSERTION_HEADER} are required`,
        );
      }

      const keyId = decodeHeader(keyIdHeader, DIAGNOSTIC_KEY_ID_HEADER);
      const assertion = openAssertion(
        decodeHeader(assertionHeader, DIAGNOSTIC_ASSERTION_HEADER),
      );
      const publicKey = await deps.publicKeyFor(keyId);
      if (publicKey === undefined) {
        throw new HttpFailure(
          "unauthorized",
          "the assertion could not be verified",
          "no stored key for that key id",
        );
      }

      let signCount: number | undefined;
      let lastError: unknown;
      for (const appId of appIds) {
        try {
          const verified = await verifyAssertion({
            ...assertion,
            clientData: raw,
            publicKey,
            appId,
          });
          signCount = verified.signCount;
          break;
        } catch (error) {
          if (!(error instanceof AttestationError)) throw error;
          lastError = error;
        }
      }
      if (signCount === undefined) {
        throw new HttpFailure(
          "unauthorized",
          "the assertion could not be verified",
          String(lastError),
        );
      }

      const recorded = await deps.database.recordActivityDiagnostic({
        userId: caller.userId,
        clientDiagnosticId,
        payloadDigest,
        observedAt,
        healthKitReadStartedAt,
        healthKitReadEndedAt,
        trustedDeviceSampleCount,
        keyId,
        signCount,
      });

      return jsonResponse(recorded.replayed ? 200 : 201, {
        diagnosticId: recorded.diagnosticId,
        performedAt: recorded.performedAt,
        replayed: recorded.replayed,
        clearedHold: recorded.clearedHold,
      });
    });
}
