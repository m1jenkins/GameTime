/**
 * POST /personal-sync-coverage
 *
 * Records which completed activity intervals an exact HealthKit query covered,
 * independently of whether any interval contained positive steps. This is what
 * distinguishes a genuine zero from absent evidence. The body is App Attest
 * signed and exact retries are resolved transactionally by the database.
 */

import { AttestationError, base64ToBytes, verifyAssertion } from "../_shared/appattest.ts";
import { type Bytes, sha256 } from "../_shared/bytes.ts";
import { asCborBytes, asCborMap, CborError, decodeCbor } from "../_shared/cbor.ts";
import type {
  PersonalCoverageDatabase,
  RecordedPersonalCoverage,
  RecordPersonalCoverageArgs,
} from "../_shared/database.ts";
import {
  HttpFailure,
  jsonResponse,
  parseJsonObject,
  readBody,
  requireArray,
  requirePost,
  requireString,
  requireUuid,
  respond,
} from "../_shared/http.ts";
import { type AccessTokenVerifier, AuthError, bearerToken } from "../_shared/jwt.ts";

export const MAX_COVERED_INTERVALS = 2000;
export const MAX_COVERAGE_BODY_BYTES = 256 * 1024;
export const COVERAGE_KEY_ID_HEADER = "x-gametime-key-id";
export const COVERAGE_ASSERTION_HEADER = "x-gametime-assertion";

export type { PersonalCoverageDatabase, RecordedPersonalCoverage, RecordPersonalCoverageArgs };

export interface PersonalCoverageDeps {
  readonly database: PersonalCoverageDatabase;
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

function coveredIntervals(body: Record<string, unknown>): readonly string[] {
  const entries = requireArray(
    body,
    "coveredIntervalStarts",
    MAX_COVERED_INTERVALS,
  );
  if (entries.length === 0) {
    throw new HttpFailure("bad_request", "coveredIntervalStarts must not be empty");
  }

  const normalized = entries.map((entry, index) => {
    if (typeof entry !== "string" || !Number.isFinite(Date.parse(entry))) {
      throw new HttpFailure(
        "bad_request",
        `coveredIntervalStarts[${index}] is not a timestamp`,
      );
    }
    return new Date(entry).toISOString();
  });
  if (new Set(normalized).size !== normalized.length) {
    throw new HttpFailure(
      "bad_request",
      "coveredIntervalStarts must contain unique instants",
    );
  }
  return normalized;
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

export function createPersonalCoverageHandler(
  deps: PersonalCoverageDeps,
): (request: Request) => Promise<Response> {
  const clock = deps.now ?? (() => new Date());
  const appIds = [deps.appId, ...(deps.additionalAppIds ?? [])];

  return (request) =>
    respond("personal-sync-coverage", async () => {
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

      const raw = await readBody(request, MAX_COVERAGE_BODY_BYTES);
      const payloadDigest = await sha256(raw);
      const body = parseJsonObject(raw);
      const challengeId = requireUuid(body, "challengeId");
      const clientCoverageId = requireUuid(body, "clientCoverageId");
      const observedAt = timestamp(body, "observedAt");
      const coveredIntervalStarts = coveredIntervals(body);

      const keyIdHeader = request.headers.get(COVERAGE_KEY_ID_HEADER);
      const assertionHeader = request.headers.get(COVERAGE_ASSERTION_HEADER);
      if (keyIdHeader === null || assertionHeader === null) {
        throw new HttpFailure(
          "bad_request",
          `both ${COVERAGE_KEY_ID_HEADER} and ${COVERAGE_ASSERTION_HEADER} are required`,
        );
      }

      const keyId = decodeHeader(keyIdHeader, COVERAGE_KEY_ID_HEADER);
      const assertion = openAssertion(
        decodeHeader(assertionHeader, COVERAGE_ASSERTION_HEADER),
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

      const recorded = await deps.database.recordPersonalCoverage({
        userId: caller.userId,
        challengeId,
        clientCoverageId,
        payloadDigest,
        observedAt,
        coveredIntervalStarts,
        keyId,
        signCount,
      });

      return jsonResponse(recorded.replayed ? 200 : 201, {
        coverageBatchId: recorded.coverageBatchId,
        replayed: recorded.replayed,
      });
    });
}
