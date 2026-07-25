/**
 * POST /ingest-metrics — the only route into the evidence ledger.
 *
 * The body is a batch of hourly observations for one contest. Two credentials
 * have to agree before any of it is written:
 *
 *   the access token   says which account this is
 *   the assertion      proves the payload was signed by a key that account
 *                      registered, and carries the counter that makes the
 *                      request single-use
 *
 * Requiring both is not belt-and-braces for its own sake. A stolen access token
 * cannot produce an assertion, because the key never leaves the Secure Enclave;
 * a stolen device cannot write someone else's evidence, because the key is bound
 * to one account. Either credential alone leaves one of those open.
 *
 * ---------------------------------------------------------------------------
 * Why the credentials are headers and not fields
 * ---------------------------------------------------------------------------
 * The assertion signs the exact bytes of the body, so it cannot be one of them:
 * a field inside the document it signs is a document that changes when the
 * signature is added to it. Both credentials therefore travel as headers, and
 * the body is exactly the bytes that were signed — no canonical subset to agree
 * on, no re-serialisation.
 *
 * That last part matters more than it looks. JSON has many encodings of one
 * value — key order, whitespace, number formatting — so hashing a *parsed and
 * re-encoded* body would hash a different document than the client signed, and
 * every assertion would fail for reasons that look like a crypto bug. So the
 * bytes are read once, hashed, and only then parsed.
 *
 * The digest is handed to the database and stored on the batch, which is what
 * keeps "this evidence was attested" checkable after the fact rather than a
 * claim about a payload nobody kept.
 */

import { AttestationError, base64ToBytes, verifyAssertion } from "../_shared/appattest.ts";
import { type Bytes, sha256 } from "../_shared/bytes.ts";
import { asCborBytes, asCborMap, CborError, decodeCbor } from "../_shared/cbor.ts";
import type { Database, ObservationInput } from "../_shared/database.ts";
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

/**
 * The same ceiling `record_metric_batch()` enforces. Two thousand hourly
 * observations is eleven weeks of one metric, so anything larger is a mistake.
 */
export const MAX_OBSERVATIONS = 2000;

/** Roughly 400 bytes per observation, plus the envelope. */
export const MAX_BODY_BYTES = 1024 * 1024;

const METRICS = new Set([
  "steps",
  "distance_meters",
  "active_energy_kcal",
  "exercise_minutes",
]);

const PROVENANCES = new Set(["device", "third_party", "manual", "unknown"]);

/** Apple's key id, base64. */
export const KEY_ID_HEADER = "x-gametime-key-id";

/** The CBOR assertion over the request body, base64. */
export const ASSERTION_HEADER = "x-gametime-assertion";

export interface IngestMetricsDeps {
  readonly database: Database;
  readonly appId: string;
  readonly verifyToken: AccessTokenVerifier;
  /**
   * True only where the App Attest development bypass is both requested and
   * permitted. `assertAttestConfigIsSafe()` is what makes it impossible to set
   * here in a deployed environment; this flag only carries the answer.
   */
  readonly attestBypass: boolean;
  /** Looks up the stored public key for a key id. Absent under the bypass. */
  readonly publicKeyFor?: (keyId: Bytes) => Promise<Bytes | undefined>;
  readonly now?: () => Date;
}

/** One observation, after checking. */
function readObservation(entry: unknown, index: number): ObservationInput {
  if (entry === null || typeof entry !== "object" || Array.isArray(entry)) {
    throw new HttpFailure("bad_request", `observations[${index}] is not an object`);
  }
  const row = entry as Record<string, unknown>;
  const where = `observations[${index}]`;

  const metric = row["metric"];
  if (typeof metric !== "string" || !METRICS.has(metric)) {
    throw new HttpFailure("bad_request", `${where}.metric is not a known metric`);
  }

  const provenance = row["provenance"];
  if (typeof provenance !== "string" || !PROVENANCES.has(provenance)) {
    // Note what is *not* done here: filtering out `manual`. The client reports
    // what HealthKit told it and the server decides what counts, because a
    // client that filters its own evidence is a client whose silence we would
    // have to trust. The ledger stores it and marks it inadmissible.
    throw new HttpFailure("bad_request", `${where}.provenance is not a known provenance`);
  }

  const bucketStart = row["bucketStart"];
  if (typeof bucketStart !== "string" || Number.isNaN(Date.parse(bucketStart))) {
    throw new HttpFailure("bad_request", `${where}.bucketStart is not a timestamp`);
  }

  const value = row["value"];
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    throw new HttpFailure("bad_request", `${where}.value is not a non-negative number`);
  }
  // The ledger stores numeric(12,2). Rounding here rather than letting Postgres
  // do it keeps the digest the client signed and the row that lands in
  // agreement about what was claimed.
  const rounded = Math.round(value * 100) / 100;
  if (rounded >= 1e10) {
    throw new HttpFailure("bad_request", `${where}.value is implausibly large`);
  }

  const sampleCount = row["sampleCount"];
  if (
    typeof sampleCount !== "number" || !Number.isInteger(sampleCount) || sampleCount < 1 ||
    sampleCount > 100000
  ) {
    throw new HttpFailure("bad_request", `${where}.sampleCount is not a positive count`);
  }

  const bundleId = row["sourceBundleId"];
  if (bundleId !== undefined && bundleId !== null) {
    if (typeof bundleId !== "string" || bundleId.length > 200) {
      throw new HttpFailure("bad_request", `${where}.sourceBundleId is not a bundle id`);
    }
  }

  const deviceModel = row["deviceModel"];
  if (deviceModel !== undefined && deviceModel !== null) {
    if (typeof deviceModel !== "string" || deviceModel.length > 100) {
      throw new HttpFailure("bad_request", `${where}.deviceModel is not a model name`);
    }
  }

  return {
    metric,
    bucket_start: new Date(bucketStart).toISOString(),
    value: rounded,
    provenance,
    sample_count: sampleCount,
    ...(typeof bundleId === "string" ? { source_bundle_id: bundleId } : {}),
    ...(typeof deviceModel === "string" ? { device_model: deviceModel } : {}),
  };
}

/** Narrows a CBOR assertion to the two fields the verifier reads. */
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

export function createIngestMetricsHandler(
  deps: IngestMetricsDeps,
): (request: Request) => Promise<Response> {
  const clock = deps.now ?? (() => new Date());

  if (!deps.attestBypass && deps.publicKeyFor === undefined) {
    // A misconfiguration that would otherwise surface as "every request is
    // unauthorized", which is a confusing way to learn about it.
    throw new Error("ingest-metrics needs a key lookup unless the attest bypass is on");
  }

  return (request) =>
    respond("ingest-metrics", async () => {
      requirePost(request);

      const at = clock();

      let caller;
      try {
        caller = await deps.verifyToken(bearerToken(request), at);
      } catch (error) {
        if (error instanceof AuthError) {
          throw new HttpFailure("unauthorized", "sign in again", error.message);
        }
        throw error;
      }

      // Bytes first, and hashed before anything parses them, because these are
      // what the assertion covers.
      const raw = await readBody(request, MAX_BODY_BYTES);
      const payloadDigest = await sha256(raw);

      const body = parseJsonObject(raw);

      const contestId = requireUuid(body, "contestId");
      const clientBatchId = requireUuid(body, "clientBatchId");

      const observedAtRaw = requireString(body, "observedAt", 64);
      if (Number.isNaN(Date.parse(observedAtRaw))) {
        throw new HttpFailure("bad_request", "observedAt is not a timestamp");
      }

      const entries = requireArray(body, "observations", MAX_OBSERVATIONS);
      const observations = entries.map(readObservation);

      // ---------------------------------------------------------------------
      // The assertion
      // ---------------------------------------------------------------------
      let keyId: Bytes | undefined;
      let signCount: number | undefined;

      const keyIdHeader = request.headers.get(KEY_ID_HEADER);
      const assertionHeader = request.headers.get(ASSERTION_HEADER);

      if (deps.attestBypass && assertionHeader === null && keyIdHeader === null) {
        // The development path (D11). It leaves `attested = false` on the batch
        // permanently, so a deployment can be audited for it, and
        // assertAttestConfigIsSafe() makes it unreachable outside local and
        // test.
        console.warn(
          "ingest-metrics: accepting an unattested batch under ATTEST_DEV_BYPASS",
        );
      } else {
        if (keyIdHeader === null || assertionHeader === null) {
          throw new HttpFailure(
            "bad_request",
            `both ${KEY_ID_HEADER} and ${ASSERTION_HEADER} are required`,
          );
        }
        keyId = base64ToBytes(keyIdHeader, KEY_ID_HEADER);
        const assertion = openAssertion(base64ToBytes(assertionHeader, ASSERTION_HEADER));

        const publicKey = await deps.publicKeyFor!(keyId);
        if (publicKey === undefined) {
          // Deliberately the same refusal as a signature that does not verify:
          // otherwise this distinguishes "no such key" from "not your key",
          // which is a way to enumerate registered devices.
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

      // Whether the counter has actually advanced is the database's call, not
      // this one: read-then-write here would let two copies of a captured
      // request both pass, and the check has to be atomic with consuming it.
      const recorded = await deps.database.recordMetricBatch({
        userId: caller.userId,
        contestId,
        clientBatchId,
        payloadDigest,
        observedAt: new Date(observedAtRaw).toISOString(),
        observations,
        ...(keyId === undefined ? {} : { keyId }),
        ...(signCount === undefined ? {} : { signCount }),
      });

      return jsonResponse(recorded.replayed ? 200 : 201, {
        batchId: recorded.batchId,
        observationCount: recorded.observationCount,
        replayed: recorded.replayed,
      });
    });
}
