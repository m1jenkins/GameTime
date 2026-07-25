/**
 * The two writes M3 makes, behind an interface.
 *
 * Both go through PostgREST as `service_role`, because both are
 * SECURITY DEFINER functions with EXECUTE revoked from every client role — the
 * thing that authorises them is a signature, and RLS cannot check one.
 *
 * The interface exists so that the handler suites can exercise real request
 * parsing and real cryptography against a fake, which is the seam D9's
 * "handlers are plain functions" style wants: everything up to the write is
 * tested here, and the invariants past the write are tested by pgTAP against a
 * real Postgres. Neither suite pretends to cover the other's half.
 *
 * `fetch` rather than supabase-js: two RPC calls do not justify a client
 * library, and a fake for `fetch` is harder to get right than a fake for two
 * named methods.
 */

import { type Bytes, fromHex, toByteaLiteral } from "./bytes.ts";
import { HttpFailure } from "./http.ts";

/** What `public.register_device_key()` needs. */
export interface RegisterDeviceKeyArgs {
  readonly userId: string;
  readonly keyId: Bytes;
  readonly publicKey: Bytes;
  readonly environment: "development" | "production";
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
  registerDeviceKey(args: RegisterDeviceKeyArgs): Promise<void>;
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

export interface PostgrestConfig {
  readonly url: string;
  readonly serviceRoleKey: string;
}

/**
 * Maps a Postgres error onto a refusal.
 *
 * The SQLSTATE carries the meaning, and the migration raises deliberate ones:
 * `23001` for a rule that refused the write, `42501` for a key that is not the
 * caller's, `22023` for a bad parameter. Mapping on the code rather than the
 * message means a reworded exception does not silently become a 500.
 *
 * The database's own message is *not* forwarded. It names contest ids, counter
 * values, and banked figures, all of which are useful to somebody probing.
 */
function failureFor(code: string | undefined, detail: string): HttpFailure {
  switch (code) {
    case "23001": // restrict_violation
      return new HttpFailure(
        "rejected",
        "the evidence was refused by a rule of this contest",
        detail,
      );
    case "22023": // invalid_parameter_value
      return new HttpFailure("rejected", "one of the observations is not acceptable", detail);
    case "23505": // unique_violation
      return new HttpFailure(
        "rejected",
        "this batch id was already used for a different payload",
        detail,
      );
    case "23503": // foreign_key_violation
      return new HttpFailure("forbidden", "you are not a participant in that contest", detail);
    case "42501": // insufficient_privilege
      return new HttpFailure("forbidden", "this device is not registered to you", detail);
    case "54000": // program_limit_exceeded
      return new HttpFailure("bad_request", "the batch is too large", detail);
    case "23514": // check_violation
      return new HttpFailure("rejected", "one of the observations is not acceptable", detail);
    default:
      return new HttpFailure("internal", "the request could not be processed", detail);
  }
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

async function rpc(
  config: PostgrestConfig,
  name: string,
  args: Record<string, unknown>,
  mapFailure: (code: string | undefined, detail: string) => HttpFailure = failureFor,
): Promise<unknown> {
  let response: Response;
  try {
    response = await fetch(`${config.url}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "apikey": config.serviceRoleKey,
        "authorization": `Bearer ${config.serviceRoleKey}`,
        // Ask for a single object rather than a one-row array where the
        // function returns one row.
        "accept": "application/json",
      },
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

/** The production implementation. */
export function postgrestDatabase(config: PostgrestConfig): Database {
  return {
    async registerDeviceKey(args) {
      await rpc(config, "register_device_key", {
        p_user_id: args.userId,
        // bytea travels as a Postgres hex literal, since PostgREST speaks JSON.
        p_key_id: toByteaLiteral(args.keyId),
        p_public_key: toByteaLiteral(args.publicKey),
        p_environment: args.environment,
      });
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
          "authorization": `Bearer ${config.serviceRoleKey}`,
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
