/**
 * POST /ingest-checkin — attested raw location evidence for one geofence visit.
 *
 * As with `ingest-metrics`, the App Attest assertion covers the exact body bytes
 * and its counter is consumed atomically by Postgres. This handler verifies
 * identity, cryptography, and the transport shape. It deliberately does not
 * calculate distance, dwell, or workout overlap: the database records every raw
 * observation and derives the auditable validation outcome from the configured
 * geofence.
 */

import { AttestationError, base64ToBytes, verifyAssertion } from "../_shared/appattest.ts";
import { type Bytes, sha256 } from "../_shared/bytes.ts";
import { asCborBytes, asCborMap, CborError, decodeCbor } from "../_shared/cbor.ts";
import type {
  CheckInDatabase,
  CheckInLocationInput,
  RecordGeofenceCheckInArgs,
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
import { AuthError, bearerToken, verifyAccessToken } from "../_shared/jwt.ts";

/** Apple's key id, base64. Kept byte-for-byte equal to ingest-metrics. */
export const KEY_ID_HEADER = "x-gametime-key-id";

/** The CBOR assertion over the exact request body, base64. */
export const ASSERTION_HEADER = "x-gametime-assertion";

export const MIN_LOCATIONS = 2;
export const MAX_LOCATIONS = 256;
export const MAX_BODY_BYTES = 128 * 1024;
export const MAX_HORIZONTAL_ACCURACY_METERS = 100_000;

const PROVENANCES = new Set(["device", "third_party", "manual", "unknown"]);

/**
 * RFC 3339 with an explicit offset and millisecond-or-coarser precision.
 *
 * Requiring an offset prevents the server's local timezone from changing the
 * instant. Capping fractional precision at milliseconds prevents two distinct
 * strings from being silently collapsed by JavaScript's Date representation.
 */
const ABSOLUTE_TIMESTAMP =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?(Z|[+-](\d{2}):(\d{2}))$/;

export interface IngestCheckInDeps {
  readonly database: CheckInDatabase;
  readonly appId: string;
  readonly jwtSecret: string;
  readonly attestBypass: boolean;
  readonly publicKeyFor?: (keyId: Bytes) => Promise<Bytes | undefined>;
  readonly now?: () => Date;
}

interface ParsedInstant {
  readonly iso: string;
  readonly milliseconds: number;
}

function daysInMonth(year: number, month: number): number {
  if (month === 2) {
    const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
    return leap ? 29 : 28;
  }
  return [4, 6, 9, 11].includes(month) ? 30 : 31;
}

/** Parses an unambiguous instant and refuses calendar rollover. */
function absoluteInstant(value: unknown, where: string): ParsedInstant {
  if (typeof value !== "string" || value.length === 0 || value.length > 64) {
    throw new HttpFailure(
      "bad_request",
      `${where} must be an absolute RFC 3339 timestamp`,
    );
  }

  const match = ABSOLUTE_TIMESTAMP.exec(value);
  if (match === null) {
    throw new HttpFailure(
      "bad_request",
      `${where} must include an explicit UTC offset`,
    );
  }

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const second = Number(match[6]);
  const offsetHour = match[9] === undefined ? 0 : Number(match[9]);
  const offsetMinute = match[10] === undefined ? 0 : Number(match[10]);

  if (
    year < 1 || month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month) ||
    hour > 23 || minute > 59 || second > 59 || offsetHour > 23 || offsetMinute > 59
  ) {
    throw new HttpFailure("bad_request", `${where} is not a valid timestamp`);
  }

  const milliseconds = Date.parse(value);
  if (!Number.isFinite(milliseconds)) {
    throw new HttpFailure("bad_request", `${where} is not a valid timestamp`);
  }
  return { iso: new Date(milliseconds).toISOString(), milliseconds };
}

function objectField(
  body: Record<string, unknown>,
  field: string,
  where = field,
): Record<string, unknown> {
  const value = body[field];
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpFailure("bad_request", `${where} must be an object`);
  }
  return value as Record<string, unknown>;
}

function finiteNumber(
  body: Record<string, unknown>,
  field: string,
  where: string,
): number {
  const value = body[field];
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new HttpFailure("bad_request", `${where} must be a finite number`);
  }
  return value;
}

function booleanField(
  body: Record<string, unknown>,
  field: string,
  where: string,
): boolean {
  const value = body[field];
  if (typeof value !== "boolean") {
    throw new HttpFailure("bad_request", `${where} must be a boolean`);
  }
  return value;
}

function readLocation(entry: unknown, index: number): {
  readonly input: CheckInLocationInput;
  readonly milliseconds: number;
} {
  const where = `locations[${index}]`;
  if (entry === null || typeof entry !== "object" || Array.isArray(entry)) {
    throw new HttpFailure("bad_request", `${where} must be an object`);
  }
  const row = entry as Record<string, unknown>;
  const observedAt = absoluteInstant(row["observedAt"], `${where}.observedAt`);
  const latitude = finiteNumber(row, "latitude", `${where}.latitude`);
  const longitude = finiteNumber(row, "longitude", `${where}.longitude`);
  const horizontalAccuracyMeters = finiteNumber(
    row,
    "horizontalAccuracyMeters",
    `${where}.horizontalAccuracyMeters`,
  );

  if (latitude < -90 || latitude > 90) {
    throw new HttpFailure("bad_request", `${where}.latitude must be between -90 and 90`);
  }
  if (longitude < -180 || longitude > 180) {
    throw new HttpFailure(
      "bad_request",
      `${where}.longitude must be between -180 and 180`,
    );
  }
  if (
    horizontalAccuracyMeters <= 0 ||
    horizontalAccuracyMeters > MAX_HORIZONTAL_ACCURACY_METERS
  ) {
    throw new HttpFailure(
      "bad_request",
      `${where}.horizontalAccuracyMeters must be greater than 0 and at most ${MAX_HORIZONTAL_ACCURACY_METERS}`,
    );
  }

  return {
    milliseconds: observedAt.milliseconds,
    input: {
      observed_at: observedAt.iso,
      latitude,
      longitude,
      accuracy_meters: horizontalAccuracyMeters,
      is_simulated: booleanField(
        row,
        "isSimulatedBySoftware",
        `${where}.isSimulatedBySoftware`,
      ),
      is_produced_by_accessory: booleanField(
        row,
        "isProducedByAccessory",
        `${where}.isProducedByAccessory`,
      ),
    },
  };
}

function readWorkout(body: Record<string, unknown>): Pick<
  RecordGeofenceCheckInArgs,
  | "workoutId"
  | "workoutStartedAt"
  | "workoutEndedAt"
  | "workoutActivityType"
  | "workoutProvenance"
  | "workoutSourceBundleId"
> {
  const workout = objectField(body, "workout");
  const workoutId = requireUuid(workout, "id");
  const startedAt = absoluteInstant(workout["startedAt"], "workout.startedAt");
  const endedAt = absoluteInstant(workout["endedAt"], "workout.endedAt");
  if (endedAt.milliseconds <= startedAt.milliseconds) {
    throw new HttpFailure("bad_request", "workout.endedAt must be after workout.startedAt");
  }

  const activityType = requireString(workout, "activityType", 100);
  const provenance = workout["provenance"];
  if (typeof provenance !== "string" || !PROVENANCES.has(provenance)) {
    throw new HttpFailure("bad_request", "workout.provenance is not a known provenance");
  }

  const sourceBundleId = workout["sourceBundleId"];
  if (
    sourceBundleId !== undefined && sourceBundleId !== null &&
    (typeof sourceBundleId !== "string" || sourceBundleId.length === 0 ||
      sourceBundleId.length > 200)
  ) {
    throw new HttpFailure(
      "bad_request",
      "workout.sourceBundleId must contain 1 to 200 characters",
    );
  }

  return {
    workoutId,
    workoutStartedAt: startedAt.iso,
    workoutEndedAt: endedAt.iso,
    workoutActivityType: activityType,
    workoutProvenance: provenance,
    ...(typeof sourceBundleId === "string" ? { workoutSourceBundleId: sourceBundleId } : {}),
  };
}

/** Narrows a CBOR assertion to the fields `verifyAssertion()` reads. */
function openAssertion(bytes: Bytes) {
  try {
    const outer = asCborMap(decodeCbor(bytes), "assertion");
    return {
      signature: asCborBytes(outer["signature"], "signature"),
      authenticatorData: asCborBytes(outer["authenticatorData"], "authenticatorData"),
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

export function createIngestCheckInHandler(
  deps: IngestCheckInDeps,
): (request: Request) => Promise<Response> {
  const clock = deps.now ?? (() => new Date());

  if (!deps.attestBypass && deps.publicKeyFor === undefined) {
    throw new Error("ingest-checkin needs a key lookup unless the attest bypass is on");
  }

  return (request) =>
    respond("ingest-checkin", async () => {
      requirePost(request);

      // The raw bytes are both the signed client data and the durable digest.
      const raw = await readBody(request, MAX_BODY_BYTES);
      const payloadDigest = await sha256(raw);
      const at = clock();

      let caller;
      try {
        caller = await verifyAccessToken(bearerToken(request), deps.jwtSecret, at);
      } catch (error) {
        if (error instanceof AuthError) {
          throw new HttpFailure("unauthorized", "sign in again", error.message);
        }
        throw error;
      }

      const body = parseJsonObject(raw);
      const contestId = requireUuid(body, "contestId");
      const geofenceId = requireUuid(body, "geofenceId");
      const clientCheckInId = requireUuid(body, "clientCheckInId");

      const entries = requireArray(body, "locations", MAX_LOCATIONS);
      if (entries.length < MIN_LOCATIONS) {
        throw new HttpFailure(
          "bad_request",
          `locations must contain at least ${MIN_LOCATIONS} observations`,
        );
      }
      const parsedLocations = entries.map(readLocation);
      const seenInstants = new Set<number>();
      for (const location of parsedLocations) {
        if (seenInstants.has(location.milliseconds)) {
          throw new HttpFailure(
            "bad_request",
            "locations must have unique observedAt instants",
          );
        }
        seenInstants.add(location.milliseconds);
      }

      const workout = readWorkout(body);

      let keyId: Bytes | undefined;
      let signCount: number | undefined;
      const keyIdHeader = request.headers.get(KEY_ID_HEADER);
      const assertionHeader = request.headers.get(ASSERTION_HEADER);

      if (deps.attestBypass && keyIdHeader === null && assertionHeader === null) {
        console.warn(
          "ingest-checkin: accepting an unattested check-in under ATTEST_DEV_BYPASS",
        );
      } else {
        if (keyIdHeader === null || assertionHeader === null) {
          throw new HttpFailure(
            "bad_request",
            `both ${KEY_ID_HEADER} and ${ASSERTION_HEADER} are required`,
          );
        }

        keyId = decodeHeader(keyIdHeader, KEY_ID_HEADER);
        const assertion = openAssertion(decodeHeader(assertionHeader, ASSERTION_HEADER));
        const publicKey = await deps.publicKeyFor!(keyId);
        if (publicKey === undefined) {
          throw new HttpFailure(
            "unauthorized",
            "the assertion could not be verified",
            "no stored key for that key id",
          );
        }

        try {
          const verified = await verifyAssertion({
            ...assertion,
            clientData: raw,
            publicKey,
            appId: deps.appId,
          });
          signCount = verified.signCount;
        } catch (error) {
          if (error instanceof AttestationError) {
            throw new HttpFailure(
              "unauthorized",
              "the assertion could not be verified",
              error.message,
            );
          }
          throw error;
        }
      }

      const recorded = await deps.database.recordGeofenceCheckIn({
        userId: caller.userId,
        contestId,
        geofenceId,
        clientCheckInId,
        payloadDigest,
        locations: parsedLocations.map((location) => location.input),
        ...workout,
        ...(keyId === undefined ? {} : { keyId }),
        ...(signCount === undefined ? {} : { signCount }),
      });

      return jsonResponse(recorded.replayed ? 200 : 201, {
        checkInId: recorded.checkInId,
        outcome: recorded.outcome,
        dwellSeconds: recorded.dwellSeconds,
        workoutOverlapSeconds: recorded.workoutOverlapSeconds,
        replayed: recorded.replayed,
      });
    });
}
