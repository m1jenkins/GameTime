import { AttestationError, base64ToBytes, verifyAssertion } from "../_shared/appattest.ts";
import { type Bytes, sha256 } from "../_shared/bytes.ts";
import { asCborBytes, asCborMap, CborError, decodeCbor } from "../_shared/cbor.ts";
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

// These are source-policy versions, not caller-configurable source allowlists.
export const REAL_HEALTH_POLICIES: Readonly<Record<string, string>> = {
  steps: "apple_watch_steps_v1",
  exercise: "apple_watch_exercise_v1",
  distance: "apple_workout_outdoor_distance_v1",
  timed: "apple_workout_outdoor_timed_v1",
};
export const EXERCISE_CREDIT_V2 = "apple_watch_exercise_credit_v2";
function matchesSource(metric: string, source: unknown): boolean {
  return REAL_HEALTH_POLICIES[metric] === source ||
    (metric === "exercise" && source === EXERCISE_CREDIT_V2);
}
export const MAX_BODY_BYTES = 4096;
export const KEY_ID_HEADER = "x-gametime-key-id";
export const ASSERTION_HEADER = "x-gametime-assertion";

export interface RealHealthPayload {
  contract_version: 1;
  actor_id: string;
  challenge_id: string;
  agreement_version: number;
  terms_digest: string;
  source_policy_version: string;
  metric: string;
  window_starts_at: string;
  window_ends_at: string;
  request_id: string;
  revision: number;
  previous_revision: number | null;
  state: "value" | "deleted" | "unresolved";
  value: number | null;
  observed_at: string;
  queried_through_at: string;
  distance_mm?: number;
}

export interface RealHealthIngestArgs {
  payload: RealHealthPayload;
  sessionID: string;
  tokenExpiresAt: string;
  keyID: Bytes | null;
  signCount: number | null;
  payloadDigest: Bytes;
  recoveryOnly: boolean;
}

export interface RealHealthReadinessPayload {
  contract_version: 1;
  actor_id: string;
  source_policy_version: string;
  observed_at: string;
  request_id: string;
  distance_mm?: number;
}
export type RealHealthReadinessArgs = Omit<RealHealthIngestArgs, "payload"> & {
  payload: RealHealthReadinessPayload;
};

export interface RealHealthIngestDeps {
  readonly enabled: boolean;
  readonly appId: string;
  readonly additionalAppIds?: readonly string[];
  readonly verifyToken: AccessTokenVerifier;
  readonly publicKeyFor: (keyId: Bytes) => Promise<Bytes | undefined>;
  readonly ingest: (args: RealHealthIngestArgs) => Promise<unknown>;
  readonly readiness?: (args: RealHealthReadinessArgs) => Promise<unknown>;
  readonly now?: () => Date;
}

const FIELDS = new Set([
  "contract_version",
  "actor_id",
  "challenge_id",
  "agreement_version",
  "terms_digest",
  "source_policy_version",
  "metric",
  "window_starts_at",
  "window_ends_at",
  "request_id",
  "revision",
  "previous_revision",
  "state",
  "value",
  "observed_at",
  "queried_through_at",
]);

function invalid(): never {
  throw new HttpFailure(
    "bad_request",
    "We couldn’t read this activity update. Try updating again.",
  );
}

function timestamp(value: unknown): number {
  if (
    typeof value !== "string" ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$/.test(value)
  ) invalid();
  const millis = Date.parse(value);
  if (!Number.isFinite(millis)) invalid();
  // Date.parse normalizes impossible dates such as February 30.
  if (new Date(millis).toISOString().slice(0, 19) !== value.slice(0, 19)) invalid();
  return millis;
}

export function readRealHealthPayload(raw: Bytes): RealHealthPayload {
  const body = parseJsonObject(raw);
  const fields = body.metric === "timed" ? new Set([...FIELDS, "distance_mm"]) : FIELDS;
  if (Object.keys(body).length !== fields.size || Object.keys(body).some((k) => !fields.has(k))) {
    invalid();
  }
  if (
    body.metric === "timed" && (!Number.isSafeInteger(body.distance_mm) ||
      (body.distance_mm as number) < 1 || (body.distance_mm as number) > 1_000_000_000)
  ) invalid();
  for (const field of ["actor_id", "challenge_id", "request_id"]) requireUuid(body, field);
  if (
    body.contract_version !== 1 || !Number.isSafeInteger(body.agreement_version) ||
    (body.agreement_version as number) < 1 || (body.agreement_version as number) > 2_147_483_647 ||
    typeof body.terms_digest !== "string" ||
    !/^[a-f0-9]{64}$/.test(body.terms_digest) || typeof body.metric !== "string" ||
    !Object.hasOwn(REAL_HEALTH_POLICIES, body.metric) ||
    !matchesSource(body.metric, body.source_policy_version)
  ) invalid();
  if (
    !Number.isSafeInteger(body.revision) || (body.revision as number) < 1 ||
    (body.revision as number) > 2_147_483_647 ||
    body.previous_revision !==
      ((body.revision as number) === 1 ? null : (body.revision as number) - 1)
  ) {
    invalid();
  }
  if (body.state === "value") {
    if (
      !Number.isSafeInteger(body.value) || (body.value as number) <= 0 ||
      (body.value as number) > 1_000_000_000
    ) invalid();
    // Apple's quantity API does not identify the activity that caused an
    // Exercise credit. Strict v1 cannot accept a positive real value.
    if (body.source_policy_version === "apple_watch_exercise_v1") invalid();
  } else if ((body.state !== "deleted" && body.state !== "unresolved") || body.value !== null) {
    invalid();
  }
  const start = timestamp(body.window_starts_at), end = timestamp(body.window_ends_at);
  const observed = timestamp(body.observed_at), through = timestamp(body.queried_through_at);
  if (start >= end || through < start || through > end || through > observed) invalid();
  return body as unknown as RealHealthPayload;
}

export function readRealHealthReadiness(raw: Bytes): RealHealthReadinessPayload {
  const body = parseJsonObject(raw);
  const timed = body.source_policy_version === "apple_workout_outdoor_timed_v1";
  if (
    Object.keys(body).sort().join(",") !==
      (timed
        ? "actor_id,contract_version,distance_mm,observed_at,request_id,source_policy_version"
        : "actor_id,contract_version,observed_at,request_id,source_policy_version") ||
    body.contract_version !== 1 ||
    ![...Object.values(REAL_HEALTH_POLICIES), EXERCISE_CREDIT_V2].includes(
      body.source_policy_version as string,
    ) ||
    body.source_policy_version === "apple_watch_exercise_v1"
  ) invalid();
  if (
    timed && (!Number.isSafeInteger(body.distance_mm) || (body.distance_mm as number) < 1 ||
      (body.distance_mm as number) > 1_000_000_000)
  ) invalid();
  requireUuid(body, "actor_id");
  requireUuid(body, "request_id");
  timestamp(body.observed_at);
  return body as unknown as RealHealthReadinessPayload;
}

function isActivity(
  payload: RealHealthPayload | RealHealthReadinessPayload,
): payload is RealHealthPayload {
  return "metric" in payload;
}

/** App Attest binds exact bytes to an app key, not Health completeness or origin.
 * The database consumes the key counter and replacement revision atomically.
 * This boundary deliberately has no development-attestation bypass. Synthetic
 * verification signs inputs with disposable test keys through this same code.
 */
export function createIngestChallengeHealthHandler(deps: RealHealthIngestDeps) {
  return (request: Request): Promise<Response> =>
    respond("ingest-challenge-health", async () => {
      requirePost(request);
      const now = deps.now?.() ?? new Date();
      let caller;
      try {
        caller = await deps.verifyToken(bearerToken(request), now);
      } catch (error) {
        if (error instanceof AuthError) {
          throw new HttpFailure("unauthorized", "Sign in again to update your activity.");
        }
        throw error;
      }
      if (
        caller.role !== "authenticated" || !caller.sessionId ||
        caller.expiresAt <= now.getTime() / 1000
      ) {
        throw new HttpFailure("unauthorized", "Sign in again to update your activity.");
      }
      const raw = await readBody(request, MAX_BODY_BYTES);
      const payload = Object.keys(parseJsonObject(raw)).length <= 6
        ? readRealHealthReadiness(raw)
        : readRealHealthPayload(raw);
      if (payload.actor_id.toLowerCase() !== caller.userId.toLowerCase()) {
        throw new HttpFailure(
          "forbidden",
          "Sign in to the account that saved this update and try again.",
        );
      }
      const key = request.headers.get(KEY_ID_HEADER),
        signed = request.headers.get(ASSERTION_HEADER);
      if ((key === null) !== (signed === null)) {
        throw new HttpFailure(
          "unauthorized",
          "We couldn’t confirm this update. Try updating again.",
        );
      }
      let keyID: Bytes | null = null;
      let signCount: number | null = null;
      if (key !== null && signed !== null) {
        keyID = base64ToBytes(key, KEY_ID_HEADER);
        if (keyID.length !== 32 || signed.length > 8192) invalid();
        const publicKey = await deps.publicKeyFor(keyID);
        if (!publicKey) {
          throw new HttpFailure(
            "unauthorized",
            "We couldn’t confirm this update. Try updating again.",
          );
        }
        let assertion;
        try {
          const map = asCborMap(decodeCbor(base64ToBytes(signed, ASSERTION_HEADER)), "assertion");
          assertion = {
            signature: asCborBytes(map.signature, "signature"),
            authenticatorData: asCborBytes(map.authenticatorData, "authenticatorData"),
          };
        } catch (error) {
          if (error instanceof CborError) invalid();
          throw error;
        }
        for (const appId of [deps.appId, ...(deps.additionalAppIds ?? [])]) {
          try {
            signCount = (await verifyAssertion({ ...assertion, clientData: raw, publicKey, appId }))
              .signCount;
            break;
          } catch (error) {
            if (!(error instanceof AttestationError)) throw error;
          }
        }
        if (signCount === null) {
          throw new HttpFailure(
            "unauthorized",
            "We couldn’t confirm this update. Try updating again.",
          );
        }
      }
      // The authoritative DB switch is checked AFTER exact committed recovery.
      // The Edge switch follows the same rule via the RPC's recovery-only input.
      const authorization = {
        sessionID: caller.sessionId,
        tokenExpiresAt: new Date(caller.expiresAt * 1000).toISOString(),
        keyID,
        signCount,
        payloadDigest: await sha256(raw),
        recoveryOnly: !deps.enabled,
      };
      let result: unknown;
      if (isActivity(payload)) result = await deps.ingest({ ...authorization, payload });
      else if (deps.readiness) result = await deps.readiness({ ...authorization, payload });
      else {throw new HttpFailure(
          "forbidden",
          "Activity updates aren’t available yet. Try again later.",
        );}
      return jsonResponse(200, result);
    });
}
