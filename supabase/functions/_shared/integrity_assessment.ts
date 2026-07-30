/**
 * M7's device-independent integrity-assessment boundary.
 *
 * Postgres loads and freezes the authoritative ledgers. This module strictly
 * decodes that complete load, invokes the one TypeScript scoring/integrity
 * pipeline, and prepares the privacy-minimized document that Postgres records
 * immutably. It performs no I/O and installs no hosted finalizer.
 */

import { sha256, toHex, utf8 } from "./bytes.ts";
import type { IntegrityAssessmentDatabase } from "./database.ts";
import {
  DEFAULT_INTEGRITY_TUNING,
  type IntegrityFlag,
  type IntegrityFlagCode,
  type IntegrityInput,
  type IntegrityTuningConfig,
  type QuarantineEvidence,
  scoreContestWithIntegrity,
} from "./integrity.ts";
import {
  type ContestMetric,
  type ContestScoring,
  type Outcome,
  SCORING_VERSION,
  ScoringError,
} from "./scoring.ts";

export const INTEGRITY_INPUT_SCHEMA_VERSION = "m7-integrity-input-v1";
export const INTEGRITY_ASSESSMENT_SCHEMA_VERSION = "m7-integrity-assessment-v1";

// PostgreSQL's uuid type accepts canonical hex UUIDs without requiring an RFC
// version/variant nibble. Test fixtures and imported historical ids do too.
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SHA256_PATTERN = /^[0-9a-f]{64}$/;
const METRICS = new Set([
  "steps",
  "distance_meters",
  "active_energy_kcal",
  "exercise_minutes",
]);
const PARTICIPANT_STATUSES = new Set([
  "invited",
  "accepted",
  "declined",
  "withdrawn",
  "lapsed",
]);
const PROVENANCES = new Set(["device", "third_party"]);
const QUARANTINE_STATES = new Set(["pending", "approved", "rejected"]);
const CHECKIN_OUTCOMES = new Set([
  "accepted",
  "outside_contest_window",
  "future_evidence",
  "simulated_location",
  "low_accuracy",
  "outside_geofence",
  "insufficient_dwell",
  "insufficient_workout_overlap",
  "untrusted_workout",
  "overlapping_checkin",
  "reused_workout",
  "overlapping_workout",
]);

interface QuarantineCandidate {
  readonly snapshotId: string;
  readonly userId: string;
  readonly metric: ContestMetric;
  readonly bucketStart: string;
  readonly recordedAt: string;
  readonly reportingLagMs: number;
}

export interface TrustedIntegrityLoad {
  readonly schemaVersion: typeof INTEGRITY_INPUT_SCHEMA_VERSION;
  readonly evidenceCutoff: string;
  readonly loadedAt: string;
  readonly evidenceDigest: string;
  readonly inputDigest: string;
  readonly input: IntegrityInput;
  readonly quarantineCandidates: readonly QuarantineCandidate[];
}

export interface RequiredQuarantine {
  readonly snapshot_id: string;
  readonly rule_version: string;
  readonly signal_key: string;
  readonly threshold_ms: number;
  readonly details: Readonly<Record<string, string | number | boolean>>;
}

export interface AssessmentRationale {
  readonly code: string;
  readonly summary: string;
  readonly points: number;
}

export interface AssessmentStanding {
  readonly participant_id: string;
  readonly display_order: number;
  readonly rank: number;
  readonly qualified: boolean;
  readonly total: number;
  readonly qualifying_days: number;
  readonly scoreable_days: number;
  readonly day_rate: number;
  readonly reached_target_at: string | null;
  readonly integrity_score: number;
  readonly integrity_flags: readonly string[];
  readonly rationale: readonly AssessmentRationale[];
}

export type AssessmentOutcome =
  | {
    readonly kind: "winner";
    readonly reason:
      | "sole_qualifier"
      | "earliest_to_target"
      | "integrity_score";
    readonly participant_id: string;
  }
  | {
    readonly kind: "all_donate";
    readonly reason: "both_donate";
    readonly participant_ids: readonly string[];
  }
  | {
    readonly kind: "void";
    readonly reason:
      | "no_qualifying_participant"
      | "tie_break_void";
  }
  | {
    readonly kind: "inconclusive";
    readonly reason: "tie_break_inconclusive";
  };

export interface PreparedIntegrityAssessment {
  readonly contestId: string;
  readonly evidenceCutoff: string;
  readonly scoringVersion: typeof SCORING_VERSION;
  readonly integrityConfigurationVersion: string;
  readonly evidenceDigest: string;
  readonly inputDigest: string;
  readonly standings: readonly AssessmentStanding[];
  readonly outcome: AssessmentOutcome;
  readonly assessmentDocument: Readonly<Record<string, unknown>>;
  readonly requiredQuarantines: readonly RequiredQuarantine[];
}

export interface RecordedIntegrityAssessment extends PreparedIntegrityAssessment {
  readonly assessmentId: string;
}

function object(
  value: unknown,
  field: string,
): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new ScoringError(`${field} must be an object`);
  }
  return value as Record<string, unknown>;
}

function array(value: unknown, field: string): readonly unknown[] {
  if (!Array.isArray(value)) {
    throw new ScoringError(`${field} must be supplied as an array`);
  }
  return value;
}

function string(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new ScoringError(`${field} must be a non-empty string`);
  }
  return value;
}

function boundedString(value: unknown, field: string, maximum: number): string {
  const parsed = string(value, field);
  if (parsed.length > maximum) {
    throw new ScoringError(`${field} must not exceed ${maximum} characters`);
  }
  return parsed;
}

function uuid(value: unknown, field: string): string {
  const parsed = string(value, field);
  if (!UUID_PATTERN.test(parsed)) {
    throw new ScoringError(`${field} must be a UUID`);
  }
  return parsed.toLowerCase();
}

function instant(value: unknown, field: string): string {
  const parsed = string(value, field);
  if (!Number.isFinite(Date.parse(parsed))) {
    throw new ScoringError(`${field} must be an ISO instant`);
  }
  return parsed;
}

function finiteNumber(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new ScoringError(`${field} must be a finite number`);
  }
  return value;
}

function nonNegativeNumber(value: unknown, field: string): number {
  const parsed = finiteNumber(value, field);
  if (parsed < 0) throw new ScoringError(`${field} must not be negative`);
  return parsed;
}

function integer(value: unknown, field: string): number {
  const parsed = nonNegativeNumber(value, field);
  if (!Number.isSafeInteger(parsed)) {
    throw new ScoringError(`${field} must be a non-negative integer`);
  }
  return parsed;
}

function boolean(value: unknown, field: string): boolean {
  if (typeof value !== "boolean") {
    throw new ScoringError(`${field} must be boolean`);
  }
  return value;
}

function nullableString(value: unknown, field: string): string | null {
  return value === null ? null : string(value, field);
}

function enumValue<T extends string>(
  value: unknown,
  allowed: ReadonlySet<string>,
  field: string,
): T {
  const parsed = string(value, field);
  if (!allowed.has(parsed)) {
    throw new ScoringError(`${field} is not a supported value`);
  }
  return parsed as T;
}

function metric(value: unknown, field: string): ContestMetric {
  return enumValue<ContestMetric>(value, METRICS, field);
}

function digest(value: unknown, field: string): string {
  const parsed = string(value, field);
  if (!SHA256_PATTERN.test(parsed)) {
    throw new ScoringError(`${field} must be a lowercase SHA-256 digest`);
  }
  return parsed;
}

function exactKeys(
  row: Record<string, unknown>,
  expected: readonly string[],
  field: string,
): void {
  const actual = Object.keys(row).sort();
  const wanted = [...expected].sort();
  if (
    actual.length !== wanted.length ||
    actual.some((key, index) => key !== wanted[index])
  ) {
    throw new ScoringError(`${field} must use the exact trusted-loader field set`);
  }
}

function decodeInput(raw: Record<string, unknown>): IntegrityInput {
  exactKeys(raw, [
    "contest",
    "roster",
    "evidence",
    "timezoneChanges",
    "sourceEvidence",
    "quarantineState",
    "checkIns",
    "locations",
  ], "input");

  const contest = object(raw.contest, "input.contest");
  exactKeys(contest, [
    "id",
    "metric",
    "cadence",
    "targetValue",
    "tieBreak",
    "startsAt",
    "endsAt",
  ], "input.contest");

  const targetValue = contest.targetValue;
  if (
    !(
      typeof targetValue === "number" && Number.isFinite(targetValue) ||
      typeof targetValue === "string" && targetValue.length > 0
    )
  ) {
    throw new ScoringError("input.contest.targetValue must be numeric");
  }

  const roster = array(raw.roster, "input.roster").map((value, index) => {
    const row = object(value, `input.roster[${index}]`);
    exactKeys(
      row,
      ["userId", "status", "timezone", "charityId"],
      `input.roster[${index}]`,
    );
    return {
      userId: uuid(row.userId, `input.roster[${index}].userId`),
      status: enumValue(
        row.status,
        PARTICIPANT_STATUSES,
        `input.roster[${index}].status`,
      ),
      timezone: string(row.timezone, `input.roster[${index}].timezone`),
      charityId: row.charityId === null
        ? null
        : uuid(row.charityId, `input.roster[${index}].charityId`),
    } as IntegrityInput["roster"][number];
  });

  const evidence = array(raw.evidence, "input.evidence").map((value, index) => {
    const row = object(value, `input.evidence[${index}]`);
    exactKeys(row, [
      "userId",
      "metric",
      "bucketStart",
      "localDay",
      "localHour",
      "value",
      "sampleCount",
      "observationCount",
      "firstRecordedAt",
      "lastRecordedAt",
    ], `input.evidence[${index}]`);
    const numericValue = row.value;
    if (
      !(
        typeof numericValue === "number" && Number.isFinite(numericValue) ||
        typeof numericValue === "string" && numericValue.length > 0
      )
    ) {
      throw new ScoringError(`input.evidence[${index}].value must be numeric`);
    }
    return {
      userId: uuid(row.userId, `input.evidence[${index}].userId`),
      metric: metric(row.metric, `input.evidence[${index}].metric`),
      bucketStart: instant(
        row.bucketStart,
        `input.evidence[${index}].bucketStart`,
      ),
      localDay: string(
        row.localDay,
        `input.evidence[${index}].localDay`,
      ) as IntegrityInput["evidence"][number]["localDay"],
      localHour: integer(
        row.localHour,
        `input.evidence[${index}].localHour`,
      ),
      value: numericValue,
      sampleCount: integer(
        row.sampleCount,
        `input.evidence[${index}].sampleCount`,
      ),
      observationCount: integer(
        row.observationCount,
        `input.evidence[${index}].observationCount`,
      ),
      firstRecordedAt: instant(
        row.firstRecordedAt,
        `input.evidence[${index}].firstRecordedAt`,
      ),
      lastRecordedAt: instant(
        row.lastRecordedAt,
        `input.evidence[${index}].lastRecordedAt`,
      ),
    };
  });

  const timezoneChanges = array(
    raw.timezoneChanges,
    "input.timezoneChanges",
  ).map((value, index) => {
    const row = object(value, `input.timezoneChanges[${index}]`);
    exactKeys(row, [
      "userId",
      "fromTimezone",
      "toTimezone",
      "effectiveAt",
    ], `input.timezoneChanges[${index}]`);
    return {
      userId: uuid(row.userId, `input.timezoneChanges[${index}].userId`),
      fromTimezone: string(
        row.fromTimezone,
        `input.timezoneChanges[${index}].fromTimezone`,
      ),
      toTimezone: string(
        row.toTimezone,
        `input.timezoneChanges[${index}].toTimezone`,
      ),
      effectiveAt: instant(
        row.effectiveAt,
        `input.timezoneChanges[${index}].effectiveAt`,
      ),
    };
  });

  const sourceEvidence = array(
    raw.sourceEvidence,
    "input.sourceEvidence",
  ).map((value, index) => {
    const row = object(value, `input.sourceEvidence[${index}]`);
    exactKeys(row, [
      "userId",
      "metric",
      "bucketStart",
      "provenance",
      "sourceBundleId",
    ], `input.sourceEvidence[${index}]`);
    return {
      userId: uuid(row.userId, `input.sourceEvidence[${index}].userId`),
      metric: metric(row.metric, `input.sourceEvidence[${index}].metric`),
      bucketStart: instant(
        row.bucketStart,
        `input.sourceEvidence[${index}].bucketStart`,
      ),
      provenance: enumValue(
        row.provenance,
        PROVENANCES,
        `input.sourceEvidence[${index}].provenance`,
      ),
      sourceBundleId: nullableString(
        row.sourceBundleId,
        `input.sourceEvidence[${index}].sourceBundleId`,
      ),
    } as IntegrityInput["sourceEvidence"][number];
  });

  const quarantineState = array(
    raw.quarantineState,
    "input.quarantineState",
  ).map((value, index) => {
    const row = object(value, `input.quarantineState[${index}]`);
    exactKeys(row, [
      "id",
      "snapshotId",
      "userId",
      "metric",
      "bucketStart",
      "ruleVersion",
      "signalKey",
      "thresholdMs",
      "reportingLagMs",
      "reviewerCount",
      "approvalsRequired",
      "approvalCount",
      "rejectionCount",
      "state",
    ], `input.quarantineState[${index}]`);
    return {
      id: uuid(row.id, `input.quarantineState[${index}].id`),
      snapshotId: uuid(
        row.snapshotId,
        `input.quarantineState[${index}].snapshotId`,
      ),
      userId: uuid(row.userId, `input.quarantineState[${index}].userId`),
      metric: metric(row.metric, `input.quarantineState[${index}].metric`),
      bucketStart: instant(
        row.bucketStart,
        `input.quarantineState[${index}].bucketStart`,
      ),
      ruleVersion: boundedString(
        row.ruleVersion,
        `input.quarantineState[${index}].ruleVersion`,
        80,
      ),
      signalKey: boundedString(
        row.signalKey,
        `input.quarantineState[${index}].signalKey`,
        300,
      ),
      thresholdMs: integer(
        row.thresholdMs,
        `input.quarantineState[${index}].thresholdMs`,
      ),
      reportingLagMs: integer(
        row.reportingLagMs,
        `input.quarantineState[${index}].reportingLagMs`,
      ),
      reviewerCount: integer(
        row.reviewerCount,
        `input.quarantineState[${index}].reviewerCount`,
      ),
      approvalsRequired: integer(
        row.approvalsRequired,
        `input.quarantineState[${index}].approvalsRequired`,
      ),
      approvalCount: integer(
        row.approvalCount,
        `input.quarantineState[${index}].approvalCount`,
      ),
      rejectionCount: integer(
        row.rejectionCount,
        `input.quarantineState[${index}].rejectionCount`,
      ),
      state: enumValue(
        row.state,
        QUARANTINE_STATES,
        `input.quarantineState[${index}].state`,
      ),
    } as QuarantineEvidence;
  });

  const checkIns = array(raw.checkIns, "input.checkIns").map(
    (value, index) => {
      const row = object(value, `input.checkIns[${index}]`);
      exactKeys(row, [
        "userId",
        "checkInId",
        "geofenceId",
        "startedAt",
        "endedAt",
        "outcome",
        "dwellSeconds",
        "workoutOverlapSeconds",
        "attested",
        "ruleVersion",
      ], `input.checkIns[${index}]`);
      return {
        userId: uuid(row.userId, `input.checkIns[${index}].userId`),
        checkInId: uuid(
          row.checkInId,
          `input.checkIns[${index}].checkInId`,
        ),
        geofenceId: uuid(
          row.geofenceId,
          `input.checkIns[${index}].geofenceId`,
        ),
        startedAt: instant(
          row.startedAt,
          `input.checkIns[${index}].startedAt`,
        ),
        endedAt: instant(
          row.endedAt,
          `input.checkIns[${index}].endedAt`,
        ),
        outcome: enumValue(
          row.outcome,
          CHECKIN_OUTCOMES,
          `input.checkIns[${index}].outcome`,
        ),
        dwellSeconds: nonNegativeNumber(
          row.dwellSeconds,
          `input.checkIns[${index}].dwellSeconds`,
        ),
        workoutOverlapSeconds: nonNegativeNumber(
          row.workoutOverlapSeconds,
          `input.checkIns[${index}].workoutOverlapSeconds`,
        ),
        attested: boolean(
          row.attested,
          `input.checkIns[${index}].attested`,
        ),
        ruleVersion: boundedString(
          row.ruleVersion,
          `input.checkIns[${index}].ruleVersion`,
          80,
        ),
      } as IntegrityInput["checkIns"][number];
    },
  );

  const locations = array(raw.locations, "input.locations").map(
    (value, index) => {
      const row = object(value, `input.locations[${index}]`);
      exactKeys(row, [
        "userId",
        "observedAt",
        "latitude",
        "longitude",
        "accuracyMeters",
      ], `input.locations[${index}]`);
      return {
        userId: uuid(row.userId, `input.locations[${index}].userId`),
        observedAt: instant(
          row.observedAt,
          `input.locations[${index}].observedAt`,
        ),
        latitude: finiteNumber(
          row.latitude,
          `input.locations[${index}].latitude`,
        ),
        longitude: finiteNumber(
          row.longitude,
          `input.locations[${index}].longitude`,
        ),
        accuracyMeters: nonNegativeNumber(
          row.accuracyMeters,
          `input.locations[${index}].accuracyMeters`,
        ),
      };
    },
  );

  return {
    contest: {
      id: uuid(contest.id, "input.contest.id"),
      metric: metric(contest.metric, "input.contest.metric"),
      cadence: enumValue(
        contest.cadence,
        new Set(["daily", "cumulative"]),
        "input.contest.cadence",
      ),
      targetValue,
      tieBreak: enumValue(
        contest.tieBreak,
        new Set([
          "integrity_score",
          "earliest_to_target",
          "both_donate",
          "void",
        ]),
        "input.contest.tieBreak",
      ),
      startsAt: instant(contest.startsAt, "input.contest.startsAt"),
      endsAt: instant(contest.endsAt, "input.contest.endsAt"),
    },
    roster,
    evidence,
    timezoneChanges,
    sourceEvidence,
    quarantineState,
    checkIns,
    locations,
  };
}

/** Strictly decodes the exact document returned by the service-only SQL loader. */
export function decodeTrustedIntegrityLoad(value: unknown): TrustedIntegrityLoad {
  const root = object(value, "trusted integrity load");
  exactKeys(root, [
    "schemaVersion",
    "evidenceCutoff",
    "loadedAt",
    "evidenceDigest",
    "inputDigest",
    "input",
    "quarantineCandidates",
  ], "trusted integrity load");

  if (root.schemaVersion !== INTEGRITY_INPUT_SCHEMA_VERSION) {
    throw new ScoringError("trusted integrity load uses an unsupported schema version");
  }

  const candidates = array(
    root.quarantineCandidates,
    "quarantineCandidates",
  ).map((value, index) => {
    const row = object(value, `quarantineCandidates[${index}]`);
    exactKeys(row, [
      "snapshotId",
      "userId",
      "metric",
      "bucketStart",
      "recordedAt",
      "reportingLagMs",
    ], `quarantineCandidates[${index}]`);
    return {
      snapshotId: uuid(
        row.snapshotId,
        `quarantineCandidates[${index}].snapshotId`,
      ),
      userId: uuid(row.userId, `quarantineCandidates[${index}].userId`),
      metric: metric(row.metric, `quarantineCandidates[${index}].metric`),
      bucketStart: instant(
        row.bucketStart,
        `quarantineCandidates[${index}].bucketStart`,
      ),
      recordedAt: instant(
        row.recordedAt,
        `quarantineCandidates[${index}].recordedAt`,
      ),
      reportingLagMs: integer(
        row.reportingLagMs,
        `quarantineCandidates[${index}].reportingLagMs`,
      ),
    };
  });

  return {
    schemaVersion: INTEGRITY_INPUT_SCHEMA_VERSION,
    evidenceCutoff: instant(root.evidenceCutoff, "evidenceCutoff"),
    loadedAt: instant(root.loadedAt, "loadedAt"),
    evidenceDigest: digest(root.evidenceDigest, "evidenceDigest"),
    inputDigest: digest(root.inputDigest, "inputDigest"),
    input: decodeInput(object(root.input, "input")),
    quarantineCandidates: candidates,
  };
}

const RATIONALE_SUMMARIES: Readonly<Record<IntegrityFlagCode, string>> = {
  plausibility_ceiling: "A scored bucket exceeded the configured plausibility ceiling.",
  cross_metric_corroboration: "A large scored bucket lacked configured same-hour corroboration.",
  third_party_source_reputation: "A third-party source carried a configured reputation deduction.",
  timezone_change: "An approved timezone epoch change carried a bounded deduction.",
  geofence_checkin_failure: "A check-in failed a configured location validation.",
  workout_overlap_validation: "A check-in failed a configured workout-overlap validation.",
  impossible_travel: "Trusted observations implied travel above the configured ceiling.",
  reporting_lag: "A scored bucket arrived after the configured reporting window.",
  retroactive_evidence_quarantine:
    "A scored bucket arrived late enough to require participant review.",
};

function standingsFor(
  scoring: ContestScoring,
  integrityScores: Readonly<Record<string, number>>,
  participants: ReadonlyMap<
    string,
    {
      readonly penalties: Readonly<Record<IntegrityFlagCode, number>>;
    }
  >,
): readonly AssessmentStanding[] {
  return scoring.standings.map((standing, index) => {
    const assessed = participants.get(standing.userId);
    const integrityScore = integrityScores[standing.userId];
    if (assessed === undefined || integrityScore === undefined) {
      throw new ScoringError("integrity assessment is incomplete for the accepted roster");
    }

    const flags = (Object.keys(assessed.penalties) as IntegrityFlagCode[])
      .filter((code) => assessed.penalties[code] > 0);
    const rationale: AssessmentRationale[] = flags.map((code) => ({
      code,
      summary: RATIONALE_SUMMARIES[code],
      points: -assessed.penalties[code],
    }));
    if (rationale.length === 0) {
      rationale.push({
        code: "clean_evidence",
        summary: "No scored integrity deductions.",
        points: 0,
      });
    }

    return {
      participant_id: standing.userId,
      display_order: index + 1,
      rank: standing.rank,
      qualified: standing.qualified,
      total: standing.total,
      qualifying_days: standing.qualifyingDays,
      scoreable_days: standing.scoreableDays,
      day_rate: standing.dayRate,
      reached_target_at: standing.reachedTargetAt,
      integrity_score: integrityScore,
      integrity_flags: flags,
      rationale,
    };
  });
}

function outcomeFor(outcome: Outcome): AssessmentOutcome {
  switch (outcome.kind) {
    case "winner":
      return {
        kind: "winner",
        reason: outcome.decidedBy,
        participant_id: outcome.userId,
      };
    case "all_donate":
      return {
        kind: "all_donate",
        reason: "both_donate",
        participant_ids: [...outcome.userIds],
      };
    case "void":
      if (outcome.reason === "insufficient_participants") {
        throw new ScoringError(
          "an active contest assessment cannot finalize an insufficient roster",
        );
      }
      return { kind: "void", reason: outcome.reason };
    case "undecided":
      if (outcome.reason !== "tie_break_inconclusive") {
        throw new ScoringError(
          "a complete integrity assessment cannot lack integrity scores",
        );
      }
      return { kind: "inconclusive", reason: "tie_break_inconclusive" };
  }
}

function candidateKey(
  userId: string,
  metric: ContestMetric | undefined,
  bucketStart: string | undefined,
): string {
  return `${userId}\u0000${metric ?? ""}\u0000${bucketStart ?? ""}`;
}

function requiredQuarantinesFor(
  flags: readonly IntegrityFlag[],
  candidates: readonly QuarantineCandidate[],
  tuning: IntegrityTuningConfig,
): readonly RequiredQuarantine[] {
  const byBucket = new Map<string, QuarantineCandidate>();
  for (const candidate of candidates) {
    const key = candidateKey(
      candidate.userId,
      candidate.metric,
      candidate.bucketStart,
    );
    if (byBucket.has(key)) {
      throw new ScoringError("trusted loader returned duplicate quarantine candidates");
    }
    byBucket.set(key, candidate);
  }

  return flags
    .filter((flag) => flag.code === "retroactive_evidence_quarantine")
    .map((flag) => {
      const candidate = byBucket.get(
        candidateKey(flag.userId, flag.metric, flag.bucketStart),
      );
      if (candidate === undefined) {
        throw new ScoringError(
          "retroactive evidence flag has no exact snapshot quarantine candidate",
        );
      }
      const reportingLagMs = flag.details.reportingLagMs;
      if (
        typeof reportingLagMs !== "number" ||
        reportingLagMs !== candidate.reportingLagMs
      ) {
        throw new ScoringError(
          "quarantine candidate reporting lag disagrees with assessed evidence",
        );
      }
      return {
        snapshot_id: candidate.snapshotId,
        rule_version: tuning.version,
        signal_key: flag.signalKey,
        threshold_ms: tuning.retroactiveQuarantine.quarantineAfterMs,
        details: {
          assessment_schema_version: INTEGRITY_ASSESSMENT_SCHEMA_VERSION,
          reporting_lag_ms: reportingLagMs,
          quarantine_after_ms: tuning.retroactiveQuarantine.quarantineAfterMs,
          evidence_still_scores: true,
        },
      };
    })
    .sort((a, b) => a.snapshot_id < b.snapshot_id ? -1 : a.snapshot_id > b.snapshot_id ? 1 : 0);
}

async function sanitizedFlags(
  flags: readonly IntegrityFlag[],
): Promise<readonly Readonly<Record<string, unknown>>[]> {
  return await Promise.all(flags.map(async (flag) => {
    const details: Record<string, unknown> = {};
    for (
      const key of [
        "reputationTier",
        "validationOutcome",
        "validationRuleVersion",
        "reportingLagMs",
        "quarantineAfterMs",
        "flagAfterMs",
        "fromTimezone",
        "toTimezone",
        "effectiveAt",
        "conservativeDistanceKm",
        "elapsedMs",
        "speedKph",
        "maximumSpeedKph",
        "evidenceStillScores",
        "disposition",
      ]
    ) {
      if (flag.details[key] !== undefined) details[key] = flag.details[key];
    }

    return {
      code: flag.code,
      severity: flag.severity,
      signal_key_sha256: toHex(await sha256(utf8(flag.signalKey))),
      ...(flag.metric === undefined ? {} : { metric: flag.metric }),
      ...(flag.bucketStart === undefined ? {} : { bucket_start: flag.bucketStart }),
      ...(flag.observedAt === undefined ? {} : { observed_at: flag.observedAt }),
      penalty_points: flag.penaltyPoints,
      details,
    };
  }));
}

/**
 * Runs the canonical evaluator and prepares the exact service-only recorder
 * input. The returned document contains no raw coordinates, source bundle ids,
 * check-in ids, geofence ids, or unhashed signal keys.
 */
export async function prepareIntegrityAssessment(
  loadedValue: unknown,
  tuning: IntegrityTuningConfig = DEFAULT_INTEGRITY_TUNING,
): Promise<PreparedIntegrityAssessment> {
  const loaded = decodeTrustedIntegrityLoad(loadedValue);
  if (tuning.version.length === 0 || tuning.version.length > 80) {
    throw new ScoringError("integrity configuration version is invalid");
  }

  const result = scoreContestWithIntegrity(loaded.input, tuning);
  const participants = new Map(
    result.integrity.participants.map((participant) => [
      participant.userId,
      participant,
    ]),
  );
  const standings = standingsFor(
    result.scoring,
    result.integrity.scores,
    participants,
  );
  const outcome = outcomeFor(result.scoring.outcome);
  const requiredQuarantines = requiredQuarantinesFor(
    result.integrity.participants.flatMap((participant) => participant.flags),
    loaded.quarantineCandidates,
    tuning,
  );

  const quarantineCounts = {
    total: loaded.input.quarantineState.length,
    pending: loaded.input.quarantineState.filter((row) => row.state === "pending")
      .length,
    approved: loaded.input.quarantineState.filter((row) => row.state === "approved").length,
    rejected: loaded.input.quarantineState.filter((row) => row.state === "rejected").length,
  };
  const participantAssessments = await Promise.all(
    result.integrity.participants.map(async (participant) => ({
      participant_id: participant.userId,
      score: participant.score,
      total_penalty: participant.totalPenalty,
      penalties: participant.penalties,
      flags: await sanitizedFlags(participant.flags),
    })),
  );

  const assessmentDocument: Readonly<Record<string, unknown>> = {
    schema_version: INTEGRITY_ASSESSMENT_SCHEMA_VERSION,
    contest_id: loaded.input.contest.id,
    evidence_cutoff: loaded.evidenceCutoff,
    scoring_version: SCORING_VERSION,
    integrity_configuration_version: result.integrity.ruleVersion,
    evidence_digest: loaded.evidenceDigest,
    input_digest: loaded.inputDigest,
    input_counts: {
      roster: loaded.input.roster.length,
      contest_evidence: loaded.input.evidence.length,
      source_reputation: loaded.input.sourceEvidence.length,
      timezone_events: loaded.input.timezoneChanges.length,
      quarantine_state: loaded.input.quarantineState.length,
      checkin_integrity: loaded.input.checkIns.length,
      trusted_locations: loaded.input.locations.length,
    },
    quarantine_observation: quarantineCounts,
    required_quarantine_count: requiredQuarantines.length,
    clean_zero_quarantines: quarantineCounts.total === 0 && requiredQuarantines.length === 0,
    standings,
    outcome,
    integrity: participantAssessments,
  };

  return {
    contestId: loaded.input.contest.id,
    evidenceCutoff: loaded.evidenceCutoff,
    scoringVersion: SCORING_VERSION,
    integrityConfigurationVersion: result.integrity.ruleVersion,
    evidenceDigest: loaded.evidenceDigest,
    inputDigest: loaded.inputDigest,
    standings,
    outcome,
    assessmentDocument,
    requiredQuarantines,
  };
}

/**
 * Loads, evaluates, and atomically records one contest assessment through the
 * trusted service seam. This is a dormant library operation, not a handler,
 * scheduler, hosted finalizer, or result publisher.
 */
export async function recordTrustedIntegrityAssessment(
  database: IntegrityAssessmentDatabase,
  contestId: string,
  tuning: IntegrityTuningConfig = DEFAULT_INTEGRITY_TUNING,
): Promise<RecordedIntegrityAssessment> {
  const requestedContestId = uuid(contestId, "contestId");
  const prepared = await prepareIntegrityAssessment(
    await database.loadContestIntegrityInput(requestedContestId),
    tuning,
  );
  if (prepared.contestId !== requestedContestId) {
    throw new ScoringError("trusted loader returned a different contest");
  }

  const assessmentId = await database.recordIntegrityAssessment({
    contestId: prepared.contestId,
    evidenceCutoff: prepared.evidenceCutoff,
    scoringVersion: prepared.scoringVersion,
    integrityConfigurationVersion: prepared.integrityConfigurationVersion,
    evidenceDigestHex: prepared.evidenceDigest,
    inputDigestHex: prepared.inputDigest,
    assessmentDocument: prepared.assessmentDocument,
    requiredQuarantines: prepared.requiredQuarantines,
  });

  return { ...prepared, assessmentId };
}
