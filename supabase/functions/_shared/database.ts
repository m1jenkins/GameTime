/**
 * Privileged Edge Function database calls, behind narrow interfaces.
 *
 * They go through PostgREST as `service_role`, because they are trusted
 * SECURITY DEFINER functions with EXECUTE revoked from every client role. The
 * handler verifies caller identity or cryptographic proof first, while the RPC
 * owns the transactional database invariant.
 *
 * The interface exists so that the handler suites can exercise real request
 * parsing and real cryptography against a fake, which is the seam D9's
 * "handlers are plain functions" style wants: everything up to the write is
 * tested here, and the invariants past the write are tested by pgTAP against a
 * real Postgres. Neither suite pretends to cover the other's half.
 *
 * `fetch` rather than supabase-js: this small RPC set does not justify a client
 * library, and a fake for `fetch` is harder to get right than fakes for narrow
 * named methods.
 */

import { type Bytes, fromHex, toByteaLiteral } from "./bytes.ts";
import { HttpFailure } from "./http.ts";

/** What `public.register_device_key()` needs. */
export interface RegisterDeviceKeyArgs {
  readonly userId: string;
  readonly keyId: Bytes;
  readonly publicKey: Bytes;
  /** Opaque, untrusted Apple receipt bytes quarantined for later validation. */
  readonly receipt: Bytes;
  readonly environment: "development" | "production";
}

/** The immutable receipt-capture metadata returned by registration. */
export interface RegisteredDeviceKey {
  /**
   * When the database first quarantined this exact receipt.
   *
   * Receipt freshness is measured against capture rather than a later retry,
   * so a lost marker response cannot turn a fresh receipt into a stale one.
   */
  readonly receiptReceivedAt: Date;
}

/** What the digest-bound receipt marker needs after complete verification. */
export interface MarkDeviceReceiptVerifiedArgs {
  readonly keyId: Bytes;
  readonly receiptSha256: Bytes;
}

/**
 * The one database write an independently verified receipt may perform.
 *
 * Kept as its own interface so unrelated ingest fakes do not acquire receipt
 * methods merely because the production adapter implements both seams.
 */
export interface ReceiptVerificationDatabase {
  markDeviceReceiptVerified(args: MarkDeviceReceiptVerifiedArgs): Promise<Date>;
}

/**
 * The one service-role check needed before issuing an App Attest challenge.
 *
 * Kept separate from {@link Database} so ingest fakes do not acquire an
 * unrelated account-lifecycle method.
 */
export interface ActiveActorDatabase {
  assertActiveActor(userId: string): Promise<void>;
}

/** One App-Attest-bound coverage upload for a personal challenge. */
export interface RecordPersonalCoverageArgs {
  readonly userId: string;
  readonly challengeId: string;
  readonly clientCoverageId: string;
  readonly payloadDigest: Bytes;
  readonly observedAt: string;
  readonly coveredIntervalStarts: readonly string[];
  readonly keyId: Bytes;
  readonly signCount: number;
}

export interface RecordedPersonalCoverage {
  readonly coverageBatchId: string;
  readonly replayed: boolean;
}

export interface PersonalCoverageDatabase {
  recordPersonalCoverage(
    args: RecordPersonalCoverageArgs,
  ): Promise<RecordedPersonalCoverage>;
}

/** One positive trusted-device HealthKit diagnostic, signed by App Attest. */
export interface RecordActivityDiagnosticArgs {
  readonly userId: string;
  readonly clientDiagnosticId: string;
  readonly payloadDigest: Bytes;
  readonly observedAt: string;
  readonly healthKitReadStartedAt: string;
  readonly healthKitReadEndedAt: string;
  readonly trustedDeviceSampleCount: number;
  readonly keyId: Bytes;
  readonly signCount: number;
}

export interface RecordedActivityDiagnostic {
  readonly diagnosticId: string;
  readonly performedAt: string;
  readonly replayed: boolean;
  readonly clearedHold: boolean;
}

export interface ActivityDiagnosticDatabase {
  recordActivityDiagnostic(
    args: RecordActivityDiagnosticArgs,
  ): Promise<RecordedActivityDiagnostic>;
}

/** One hour of one metric, as the client reports it. */
export interface ObservationInput {
  readonly metric: string;
  readonly bucket_start: string;
  readonly value: number;
  readonly provenance: string;
  readonly sample_count: number;
  readonly source_bundle_id?: string;
  readonly device_model?: string;
}

/** What `public.record_metric_batch()` needs. */
export interface RecordMetricBatchArgs {
  readonly userId: string;
  readonly contestId: string;
  readonly clientBatchId: string;
  readonly payloadDigest: Bytes;
  readonly observedAt: string;
  readonly observations: readonly ObservationInput[];
  /** Absent only under the development bypass. */
  readonly keyId?: Bytes;
  readonly signCount?: number;
}

export interface RecordedBatch {
  readonly batchId: string;
  readonly observationCount: number;
  readonly replayed: boolean;
}

export interface Database {
  registerDeviceKey(args: RegisterDeviceKeyArgs): Promise<RegisteredDeviceKey>;
  recordMetricBatch(args: RecordMetricBatchArgs): Promise<RecordedBatch>;
}

/** One raw Core Location observation in the shape the check-in RPC accepts. */
export interface CheckInLocationInput {
  readonly observed_at: string;
  readonly latitude: number;
  readonly longitude: number;
  readonly accuracy_meters: number;
  readonly is_simulated: boolean;
  readonly is_produced_by_accessory: boolean;
}

/** What `public.record_geofence_checkin()` needs after request validation. */
export interface RecordGeofenceCheckInArgs {
  readonly userId: string;
  readonly contestId: string;
  readonly geofenceId: string;
  readonly clientCheckInId: string;
  readonly payloadDigest: Bytes;
  readonly locations: readonly CheckInLocationInput[];
  readonly workoutId: string;
  readonly workoutStartedAt: string;
  readonly workoutEndedAt: string;
  readonly workoutActivityType: string;
  readonly workoutProvenance: string;
  readonly workoutSourceBundleId?: string;
  /** Absent only under the development bypass. */
  readonly keyId?: Bytes;
  readonly signCount?: number;
}

/** The durable validation result returned by `record_geofence_checkin()`. */
export interface RecordedGeofenceCheckIn {
  readonly checkInId: string;
  readonly outcome: string;
  readonly dwellSeconds: number;
  readonly workoutOverlapSeconds: number;
  readonly replayed: boolean;
}

/**
 * Kept separate from {@link Database}: M3's handler fakes implement exactly the
 * two M3 writes, and adding an M6 method to that interface would make an
 * unrelated milestone's tests change for type-system bookkeeping alone.
 */
export interface CheckInDatabase {
  recordGeofenceCheckIn(
    args: RecordGeofenceCheckInArgs,
  ): Promise<RecordedGeofenceCheckIn>;
}

export interface RecordIntegrityAssessmentArgs {
  readonly contestId: string;
  readonly evidenceCutoff: string;
  readonly scoringVersion: string;
  readonly integrityConfigurationVersion: string;
  readonly evidenceDigestHex: string;
  readonly inputDigestHex: string;
  readonly assessmentDocument: Readonly<Record<string, unknown>>;
  readonly requiredQuarantines: readonly {
    readonly snapshot_id: string;
    readonly rule_version: string;
    readonly signal_key: string;
    readonly threshold_ms: number;
    readonly details: Readonly<Record<string, string | number | boolean>>;
  }[];
}

/**
 * The dormant M7 worker seam. No handler or schedule is installed in this
 * slice; a later, explicitly authorized caller can load, assess, and record
 * through only these two service-role RPCs.
 */
export interface IntegrityAssessmentDatabase {
  loadContestIntegrityInput(contestId: string): Promise<unknown>;
  recordIntegrityAssessment(args: RecordIntegrityAssessmentArgs): Promise<string>;
}

export interface PostgrestConfig {
  readonly url: string;
  readonly serviceRoleKey: string;
  /**
   * Legacy service_role keys are JWTs and travel in both headers. Modern
   * sb_secret_ keys are opaque and authenticate only through `apikey`.
   */
  readonly authorizationBearer?: boolean;
}

/**
 * Maps a Postgres error onto a refusal.
 *
 * The SQLSTATE carries the meaning, and the migration raises deliberate ones:
 * `23001` for a rule that refused the write, `42501` for a key that is not the
 * caller's, `22023` for a bad parameter. Mapping on the code rather than the
 * message means a reworded exception does not silently become a 500.
 *
 * The database's own message is discarded before constructing the failure.
 * `HttpFailure.detail` is loggable, while a metric refusal can name raw health
 * values, source metadata, contest ids, or counters.
 */
function failureFor(code: string | undefined, _detail: string): HttpFailure {
  switch (code) {
    case "23001": // restrict_violation
      return new HttpFailure(
        "rejected",
        "the evidence was refused by a rule of this contest",
      );
    case "22023": // invalid_parameter_value
      return new HttpFailure("rejected", "one of the observations is not acceptable");
    case "23505": // unique_violation
      return new HttpFailure(
        "rejected",
        "this batch id was already used for a different payload",
      );
    case "23503": // foreign_key_violation
      return new HttpFailure("forbidden", "you are not a participant in that contest");
    case "42501": // insufficient_privilege
      return new HttpFailure("forbidden", "this device is not registered to you");
    case "54000": // program_limit_exceeded
      return new HttpFailure("bad_request", "the batch is too large");
    case "23514": // check_violation
      return new HttpFailure("rejected", "one of the observations is not acceptable");
    default:
      return new HttpFailure("internal", "the request could not be processed");
  }
}

/** Registration-specific wording; a duplicate key is not a duplicate batch. */
function registrationFailureFor(
  code: string | undefined,
  detail: string,
): HttpFailure {
  switch (code) {
    case "23505": // unique_violation
    case "23514": // check_violation
    case "22023": // invalid_parameter_value
      return new HttpFailure(
        "rejected",
        "this device key cannot be registered",
        detail,
      );
    case "42501": // insufficient_privilege
      return new HttpFailure(
        "forbidden",
        "complete onboarding before registering a device",
        detail,
      );
    default:
      return new HttpFailure("internal", "the request could not be processed", detail);
  }
}

/** Active-account refusals must not inherit device-registration wording. */
function activeActorFailureFor(
  code: string | undefined,
  detail: string,
): HttpFailure {
  if (code === "42501") {
    return new HttpFailure("forbidden", "this account is not active", detail);
  }
  return new HttpFailure("internal", "the request could not be processed", detail);
}

/**
 * A receipt-marker refusal is never useful to a client.
 *
 * A digest mismatch can mean either a refresh race or a missing private row,
 * and exposing that distinction would turn the marker into a receipt-existence
 * oracle. Keep every database detail on the server side.
 */
function receiptVerificationFailureFor(
  _code: string | undefined,
  detail: string,
): HttpFailure {
  return new HttpFailure("internal", "the request could not be processed", detail);
}

/** SQLSTATE mapping whose public messages use the check-in domain's words. */
function checkInFailureFor(code: string | undefined, detail: string): HttpFailure {
  switch (code) {
    case "23P01": // exclusion_violation
      return new HttpFailure(
        "rejected",
        "this check-in overlaps another recorded check-in",
        detail,
      );
    case "23001": // restrict_violation
    case "23514": // check_violation
    case "22023": // invalid_parameter_value
    case "22003": // numeric_value_out_of_range
      return new HttpFailure(
        "rejected",
        "the check-in was refused by a validation rule",
        detail,
      );
    case "23505": // unique_violation
      return new HttpFailure(
        "rejected",
        "this check-in id was already used for a different payload",
        detail,
      );
    case "23503": // foreign_key_violation
      return new HttpFailure(
        "forbidden",
        "the contest or geofence is not available to you",
        detail,
      );
    case "42501": // insufficient_privilege
      return new HttpFailure("forbidden", "this device is not registered to you", detail);
    case "54000": // program_limit_exceeded
      return new HttpFailure("bad_request", "the check-in is too large", detail);
    default:
      return new HttpFailure("internal", "the request could not be processed", detail);
  }
}

/** M7 assessment failures never expose evidence, coordinates, or source data. */
function integrityAssessmentFailureFor(
  code: string | undefined,
  detail: string,
): HttpFailure {
  switch (code) {
    case "23001": // restrict_violation
      return new HttpFailure(
        "rejected",
        "the contest evidence is not ready for a complete assessment",
      );
    case "23503": // foreign_key_violation
    case "22023": // invalid_parameter_value
    case "23514": // check_violation
    case "23505": // unique_violation
      return new HttpFailure(
        "rejected",
        "the integrity assessment was refused",
      );
    case "42501": // insufficient_privilege
      return new HttpFailure("forbidden", "the integrity assessment is not authorized");
    default:
      return new HttpFailure(
        "internal",
        "the request could not be processed",
        detail,
      );
  }
}

/** Personal health-data endpoints never expose row, device, or payload detail. */
function personalActivityFailureFor(
  code: string | undefined,
  _detail: string,
): HttpFailure {
  switch (code) {
    case "23001": // restrict_violation
    case "22023": // invalid_parameter_value
    case "23514": // check_violation
      return new HttpFailure("rejected", "the trusted activity request was refused");
    case "23505": // unique_violation
      return new HttpFailure(
        "rejected",
        "this request id was already used for different contents",
      );
    case "23503": // foreign_key_violation
    case "42501": // insufficient_privilege
      return new HttpFailure("forbidden", "the trusted activity request is not authorized");
    default:
      // A database refusal can quote source bundle IDs, device metadata, or a
      // signed interval. Personal activity endpoints deliberately discard that
      // detail even from application logs; operational correlation belongs in
      // database-side request IDs, not copied health evidence.
      return new HttpFailure("internal", "the request could not be processed");
  }
}

async function rpc(
  config: PostgrestConfig,
  name: string,
  args: Record<string, unknown>,
  mapFailure: (code: string | undefined, detail: string) => HttpFailure = failureFor,
): Promise<unknown> {
  let response: Response;
  try {
    const headers: Record<string, string> = {
      "content-type": "application/json",
      "apikey": config.serviceRoleKey,
      // Ask for a single object rather than a one-row array where the
      // function returns one row.
      "accept": "application/json",
    };
    if (config.authorizationBearer !== false) {
      headers["authorization"] = `Bearer ${config.serviceRoleKey}`;
    }
    response = await fetch(`${config.url}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers,
      body: JSON.stringify(args),
    });
  } catch (cause) {
    throw new HttpFailure("internal", "the request could not be processed", String(cause));
  }

  const text = await response.text();

  if (!response.ok) {
    let code: string | undefined;
    let message = text;
    try {
      const parsed = JSON.parse(text) as { code?: string; message?: string };
      code = parsed.code;
      message = parsed.message ?? text;
    } catch {
      // A non-JSON body from PostgREST is itself unexpected; the raw text is
      // the most useful detail available.
    }
    throw mapFailure(code, `${name} failed with ${response.status}: ${message}`);
  }

  if (text === "") return null;
  try {
    return JSON.parse(text);
  } catch (cause) {
    throw new HttpFailure(
      "internal",
      "the request could not be processed",
      `${name} returned unparseable JSON: ${cause}`,
    );
  }
}

/** Narrows a scalar PostgREST `timestamptz` result to a real Date. */
function timestampResult(result: unknown, rpcName: string): Date {
  if (typeof result !== "string") {
    throw new HttpFailure(
      "internal",
      "the request could not be processed",
      `${rpcName} returned an unexpected timestamp: ${JSON.stringify(result)}`,
    );
  }

  const timestamp = new Date(result);
  if (!Number.isFinite(timestamp.getTime())) {
    throw new HttpFailure(
      "internal",
      "the request could not be processed",
      `${rpcName} returned an invalid timestamp: ${JSON.stringify(result)}`,
    );
  }
  return timestamp;
}

/** The production implementation. */
export function postgrestDatabase(
  config: PostgrestConfig,
): Database & ReceiptVerificationDatabase & ActiveActorDatabase {
  return {
    async assertActiveActor(userId) {
      await rpc(
        config,
        "assert_active_actor",
        { p_user_id: userId },
        activeActorFailureFor,
      );
    },

    async registerDeviceKey(args) {
      const result = await rpc(
        config,
        "register_device_key",
        {
          p_user_id: args.userId,
          // bytea travels as a Postgres hex literal, since PostgREST speaks JSON.
          p_key_id: toByteaLiteral(args.keyId),
          p_public_key: toByteaLiteral(args.publicKey),
          p_attestation_receipt: toByteaLiteral(args.receipt),
          p_environment: args.environment,
        },
        registrationFailureFor,
      );
      return {
        receiptReceivedAt: timestampResult(result, "register_device_key"),
      };
    },

    async markDeviceReceiptVerified(args) {
      const result = await rpc(
        config,
        "mark_device_receipt_verified",
        {
          p_key_id: toByteaLiteral(args.keyId),
          p_receipt_sha256: toByteaLiteral(args.receiptSha256),
        },
        receiptVerificationFailureFor,
      );
      return timestampResult(result, "mark_device_receipt_verified");
    },

    async recordMetricBatch(args) {
      const result = await rpc(config, "record_metric_batch", {
        p_user_id: args.userId,
        p_contest_id: args.contestId,
        p_client_batch_id: args.clientBatchId,
        p_payload_digest: toByteaLiteral(args.payloadDigest),
        p_observed_at: args.observedAt,
        p_observations: args.observations,
        p_key_id: args.keyId === undefined ? null : toByteaLiteral(args.keyId),
        p_sign_count: args.signCount ?? null,
      });

      // A set-returning function comes back as an array of rows.
      const rows = Array.isArray(result) ? result : [result];
      const row = rows[0] as
        | { batch_id?: string; observation_count?: number; replayed?: boolean }
        | undefined;

      if (
        row === undefined || typeof row.batch_id !== "string" ||
        typeof row.observation_count !== "number" || typeof row.replayed !== "boolean"
      ) {
        throw new HttpFailure(
          "internal",
          "the request could not be processed",
          `record_metric_batch returned an unexpected shape: ${JSON.stringify(result)}`,
        );
      }

      return {
        batchId: row.batch_id,
        observationCount: row.observation_count,
        replayed: row.replayed,
      };
    },
  };
}

/** Production adapters for personal coverage and trusted diagnostics. */
export function postgrestPersonalCoverageDatabase(
  config: PostgrestConfig,
): PersonalCoverageDatabase {
  return {
    async recordPersonalCoverage(args) {
      const result = await rpc(
        config,
        "record_personal_sync_coverage_v1",
        {
          p_user_id: args.userId,
          p_challenge_id: args.challengeId,
          p_client_coverage_id: args.clientCoverageId,
          p_payload_digest: toByteaLiteral(args.payloadDigest),
          p_observed_at: args.observedAt,
          p_covered_bucket_starts: args.coveredIntervalStarts,
          p_key_id: toByteaLiteral(args.keyId),
          p_sign_count: args.signCount,
        },
        personalActivityFailureFor,
      );
      const rows = Array.isArray(result) ? result : [result];
      const row = rows[0] as
        | { coverage_batch_id?: unknown; replayed?: unknown }
        | undefined;
      if (
        row === undefined || typeof row.coverage_batch_id !== "string" ||
        typeof row.replayed !== "boolean"
      ) {
        throw new HttpFailure(
          "internal",
          "the request could not be processed",
          "record_personal_sync_coverage_v1 returned an unexpected shape",
        );
      }
      return {
        coverageBatchId: row.coverage_batch_id,
        replayed: row.replayed,
      };
    },
  };
}

export function postgrestActivityDiagnosticDatabase(
  config: PostgrestConfig,
): ActivityDiagnosticDatabase {
  return {
    async recordActivityDiagnostic(args) {
      const result = await rpc(
        config,
        "record_trusted_personal_diagnostic_v1",
        {
          p_user_id: args.userId,
          p_client_diagnostic_id: args.clientDiagnosticId,
          p_payload_digest: toByteaLiteral(args.payloadDigest),
          p_observed_at: args.observedAt,
          p_query_started_at: args.healthKitReadStartedAt,
          p_query_ended_at: args.healthKitReadEndedAt,
          p_trusted_device_sample_count: args.trustedDeviceSampleCount,
          p_key_id: toByteaLiteral(args.keyId),
          p_sign_count: args.signCount,
        },
        personalActivityFailureFor,
      );
      const rows = Array.isArray(result) ? result : [result];
      const row = rows[0] as
        | {
          diagnostic_id?: unknown;
          performed_at?: unknown;
          replayed?: unknown;
          cleared_hold?: unknown;
        }
        | undefined;
      if (
        row === undefined || typeof row.diagnostic_id !== "string" ||
        typeof row.performed_at !== "string" ||
        !Number.isFinite(Date.parse(row.performed_at)) ||
        typeof row.replayed !== "boolean" ||
        typeof row.cleared_hold !== "boolean"
      ) {
        throw new HttpFailure(
          "internal",
          "the request could not be processed",
          "record_trusted_personal_diagnostic_v1 returned an unexpected shape",
        );
      }
      return {
        diagnosticId: row.diagnostic_id,
        performedAt: new Date(row.performed_at).toISOString(),
        replayed: row.replayed,
        clearedHold: row.cleared_hold,
      };
    },
  };
}

/** Production adapter for M6's attested geofence check-in RPC. */
export function postgrestCheckInDatabase(config: PostgrestConfig): CheckInDatabase {
  return {
    async recordGeofenceCheckIn(args) {
      const result = await rpc(
        config,
        "record_geofence_checkin",
        {
          p_user_id: args.userId,
          p_contest_id: args.contestId,
          p_geofence_id: args.geofenceId,
          p_client_checkin_id: args.clientCheckInId,
          p_payload_digest: toByteaLiteral(args.payloadDigest),
          p_locations: args.locations,
          p_workout_id: args.workoutId,
          p_workout_started_at: args.workoutStartedAt,
          p_workout_ended_at: args.workoutEndedAt,
          p_workout_activity_type: args.workoutActivityType,
          p_workout_provenance: args.workoutProvenance,
          p_workout_source_bundle_id: args.workoutSourceBundleId ?? null,
          p_key_id: args.keyId === undefined ? null : toByteaLiteral(args.keyId),
          p_sign_count: args.signCount ?? null,
        },
        checkInFailureFor,
      );

      // A set-returning function comes back as an array of rows.
      const rows = Array.isArray(result) ? result : [result];
      const row = rows[0] as
        | {
          checkin_id?: unknown;
          outcome?: unknown;
          dwell_seconds?: unknown;
          workout_overlap_seconds?: unknown;
          replayed?: unknown;
        }
        | undefined;

      if (
        row === undefined || typeof row.checkin_id !== "string" ||
        typeof row.outcome !== "string" || row.outcome.length === 0 ||
        typeof row.dwell_seconds !== "number" || !Number.isFinite(row.dwell_seconds) ||
        row.dwell_seconds < 0 ||
        typeof row.workout_overlap_seconds !== "number" ||
        !Number.isFinite(row.workout_overlap_seconds) ||
        row.workout_overlap_seconds < 0 ||
        typeof row.replayed !== "boolean"
      ) {
        throw new HttpFailure(
          "internal",
          "the request could not be processed",
          `record_geofence_checkin returned an unexpected shape: ${JSON.stringify(result)}`,
        );
      }

      return {
        checkInId: row.checkin_id,
        outcome: row.outcome,
        dwellSeconds: row.dwell_seconds,
        workoutOverlapSeconds: row.workout_overlap_seconds,
        replayed: row.replayed,
      };
    },
  };
}

/** Production adapter for M7's complete trusted load and immutable recorder. */
export function postgrestIntegrityAssessmentDatabase(
  config: PostgrestConfig,
): IntegrityAssessmentDatabase {
  return {
    async loadContestIntegrityInput(contestId) {
      return await rpc(
        config,
        "load_contest_integrity_input_v1",
        { p_contest_id: contestId },
        integrityAssessmentFailureFor,
      );
    },

    async recordIntegrityAssessment(args) {
      let evidenceDigest: Bytes;
      let inputDigest: Bytes;
      try {
        evidenceDigest = fromHex(args.evidenceDigestHex);
        inputDigest = fromHex(args.inputDigestHex);
      } catch (cause) {
        throw new HttpFailure(
          "internal",
          "the request could not be processed",
          `integrity assessment digest is invalid: ${cause}`,
        );
      }
      if (evidenceDigest.length !== 32 || inputDigest.length !== 32) {
        throw new HttpFailure(
          "internal",
          "the request could not be processed",
          "integrity assessment digests must be SHA-256",
        );
      }

      const result = await rpc(
        config,
        "record_contest_integrity_assessment_v1",
        {
          p_contest_id: args.contestId,
          p_evidence_cutoff: args.evidenceCutoff,
          p_scoring_version: args.scoringVersion,
          p_integrity_configuration_version: args.integrityConfigurationVersion,
          p_evidence_digest: toByteaLiteral(evidenceDigest),
          p_input_digest: toByteaLiteral(inputDigest),
          p_assessment_document: args.assessmentDocument,
          p_required_quarantines: args.requiredQuarantines,
        },
        integrityAssessmentFailureFor,
      );

      if (
        typeof result !== "string" ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
          .test(result)
      ) {
        throw new HttpFailure(
          "internal",
          "the request could not be processed",
          `record_contest_integrity_assessment_v1 returned an unexpected id: ${
            JSON.stringify(result)
          }`,
        );
      }
      return result;
    },
  };
}

/**
 * Reads the stored public key for a key id.
 *
 * Deliberately does not filter revoked keys. `record_metric_batch()` refuses a
 * revoked key itself, and duplicating that rule here would mean two places to
 * change it and one of them eventually not changing. What this returns is "the
 * key bytes on file", and whether the key may still be used is a question about
 * the contest, answered where the rest of those questions are.
 */
export function deviceKeyLookup(
  config: PostgrestConfig,
): (keyId: Bytes) => Promise<Bytes | undefined> {
  return async (keyId) => {
    const query = new URLSearchParams({
      key_id: `eq.${toByteaLiteral(keyId)}`,
      select: "public_key",
      limit: "1",
    });

    let response: Response;
    try {
      response = await fetch(`${config.url}/rest/v1/device_attestations?${query}`, {
        headers: {
          "apikey": config.serviceRoleKey,
          ...(config.authorizationBearer === false
            ? {}
            : { "authorization": `Bearer ${config.serviceRoleKey}` }),
          "accept": "application/json",
        },
      });
    } catch (cause) {
      throw new HttpFailure("internal", "the request could not be processed", String(cause));
    }

    const text = await response.text();
    if (!response.ok) {
      throw new HttpFailure(
        "internal",
        "the request could not be processed",
        `device key lookup failed with ${response.status}: ${text}`,
      );
    }

    let rows: unknown;
    try {
      rows = JSON.parse(text);
    } catch (cause) {
      throw new HttpFailure(
        "internal",
        "the request could not be processed",
        `device key lookup returned unparseable JSON: ${cause}`,
      );
    }

    if (!Array.isArray(rows) || rows.length === 0) return undefined;

    const encoded = (rows[0] as { public_key?: unknown }).public_key;
    if (typeof encoded !== "string") {
      throw new HttpFailure(
        "internal",
        "the request could not be processed",
        "device key lookup returned no public_key",
      );
    }

    // bytea arrives as a `\x…` hex literal.
    try {
      return fromHex(encoded);
    } catch (cause) {
      throw new HttpFailure(
        "internal",
        "the request could not be processed",
        `stored public key is not hex: ${cause}`,
      );
    }
  };
}
