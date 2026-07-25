/**
 * Tunable anti-cheat signals and integrity scoring (M5–M6).
 *
 * This module judges evidence; it never edits it. `scoreContest()` remains the
 * only definition of qualification and totals, and `contest_evidence` remains
 * the only definition of admissibility. Integrity runs beside that path:
 *
 *   1. validate and score the unchanged M4 input;
 *   2. join optional M3 provenance metadata beside those same evidence buckets;
 *   3. raise explicit, auditable flags against the same fixture-shaped data;
 *   4. start every accepted participant at the configured score and subtract
 *      capped, configured penalties;
 *   5. pass the complete score map through M4's existing `integrityScores` seam.
 *
 * A flag is a reason to review evidence, not a verdict that it is false. Even a
 * bucket marked `retroactive_evidence_quarantine` remains in the scoring input
 * and therefore in the participant's total. The SQL half of M5 records the
 * review state without changing `metric_snapshots.is_admissible` or filtering
 * `contest_evidence`.
 */

import {
  type ContestMetric,
  type ContestScoring,
  type EvidenceBucket,
  type NumericValue,
  scoreContest,
  ScoringError,
  type ScoringInput,
  type TimezoneChange,
} from "./scoring.ts";

export type IntegrityFlagCode =
  | "plausibility_ceiling"
  | "cross_metric_corroboration"
  | "third_party_source_reputation"
  | "timezone_change"
  | "geofence_checkin_failure"
  | "workout_overlap_validation"
  | "impossible_travel"
  | "reporting_lag"
  | "retroactive_evidence_quarantine";

export type IntegritySeverity = "low" | "medium" | "high" | "critical";

export type IntegrityDetailValue = string | number | boolean | null;

export interface IntegrityFlag {
  readonly code: IntegrityFlagCode;
  readonly userId: string;
  readonly severity: IntegritySeverity;
  /**
   * Stable within a rule version. Persistence uses this to make retries
   * idempotent without pretending two different suspicious hours are one flag.
   */
  readonly signalKey: string;
  readonly metric?: ContestMetric;
  readonly bucketStart?: string;
  readonly observedAt?: string;
  readonly penaltyPoints: number;
  readonly details: Readonly<Record<string, IntegrityDetailValue>>;
}

export interface RulePenalty {
  readonly enabled: boolean;
  readonly severity: IntegritySeverity;
  readonly pointsPerFlag: number;
  /** Repeated observations cannot subtract more than this for one rule. */
  readonly maxPoints: number;
}

export type SourceReputationTier =
  | "known"
  | "unrecognized"
  | "missing"
  | "malformed";

export interface SourceReputationTierTuning {
  readonly severity: IntegritySeverity;
  readonly pointsPerFlag: number;
}

export interface SourceReputationTuning {
  readonly enabled: boolean;
  /**
   * Canonical, lower-case bundle identifiers that have been reviewed for this
   * rule version. Matching is case-insensitive after syntax validation.
   */
  readonly knownBundleIds: readonly string[];
  readonly tiers: Readonly<
    Record<Exclude<SourceReputationTier, "known">, SourceReputationTierTuning>
  >;
  /** All source-reputation tiers share one cap per participant. */
  readonly maxPoints: number;
}

export interface PlausibilityTuning extends RulePenalty {
  /** Maximum plausible value for one hourly bucket, by metric. */
  readonly hourlyCeilings: Readonly<Record<ContestMetric, number>>;
}

export interface CorroboratingMetric {
  readonly metric: ContestMetric;
  readonly minimumValue: number;
}

export interface CorroborationRule {
  /**
   * Small hours do not need corroboration. Only a primary metric at or above
   * this value asks another metric to tell the same physical story.
   */
  readonly triggerValue: number;
  /** At least one of these metric/value pairs must be present in the same hour. */
  readonly anyOf: readonly CorroboratingMetric[];
}

export interface CorroborationTuning extends RulePenalty {
  readonly byPrimaryMetric: Readonly<Record<ContestMetric, CorroborationRule>>;
}

export interface TravelTuning extends RulePenalty {
  readonly minimumDistanceKm: number;
  readonly maximumSpeedKph: number;
  /**
   * Two points further apart than this are not treated as one journey. This
   * stops sparse, months-apart observations from being described as a trip.
   */
  readonly maximumGapMs: number;
}

export interface ReportingLagTuning extends RulePenalty {
  /** A bucket reported this long after it closed gets a visible lag flag. */
  readonly flagAfterMs: number;
}

export interface RetroactiveQuarantineTuning extends RulePenalty {
  /**
   * A bucket reported this long after it closed needs participant review.
   * This threshold must be at least the ordinary reporting-lag threshold.
   */
  readonly quarantineAfterMs: number;
}

export interface IntegrityTuning {
  /** Stored with flags so a re-score can name the exact thresholds it used. */
  readonly version: string;
  readonly startingScore: number;
  readonly floorScore: number;
  readonly plausibility: PlausibilityTuning;
  readonly corroboration: CorroborationTuning;
  readonly sourceReputation: SourceReputationTuning;
  readonly timezoneChange: RulePenalty;
  readonly geofenceCheckIn: RulePenalty;
  readonly workoutOverlap: RulePenalty;
  readonly travel: TravelTuning;
  readonly reportingLag: ReportingLagTuning;
  readonly retroactiveQuarantine: RetroactiveQuarantineTuning;
}

/** The exact pre-M6 M5 configuration retained for reproducible re-scores. */
export type IntegrityTuningV3 = Omit<
  IntegrityTuning,
  "geofenceCheckIn" | "workoutOverlap"
>;

/** The exact pre-timezone-change M5 configuration retained for reproducible re-scores. */
export type IntegrityTuningV2 = Omit<IntegrityTuningV3, "timezoneChange">;

/** A persisted tuning document accepted by the assessor. */
export type IntegrityTuningConfig =
  | IntegrityTuning
  | IntegrityTuningV3
  | IntegrityTuningV2;

const HOUR_MS = 3_600_000;
const DAY_MS = 86_400_000;

/**
 * The historical M5 configuration is an explicit object rather than something
 * synthesized from today's defaults. A disputed contest scored under m5-v2
 * can therefore load the same shape and thresholds years later.
 */
export const M5_V2_INTEGRITY_TUNING: IntegrityTuningV2 = {
  version: "m5-v2",
  startingScore: 100,
  floorScore: 0,
  plausibility: {
    enabled: true,
    severity: "high",
    pointsPerFlag: 25,
    maxPoints: 50,
    hourlyCeilings: {
      steps: 15_000,
      distance_meters: 20_000,
      active_energy_kcal: 2_500,
      exercise_minutes: 60,
    },
  },
  corroboration: {
    enabled: true,
    severity: "medium",
    pointsPerFlag: 12,
    maxPoints: 36,
    byPrimaryMetric: {
      steps: {
        triggerValue: 8_000,
        anyOf: [
          { metric: "distance_meters", minimumValue: 1_000 },
          { metric: "active_energy_kcal", minimumValue: 50 },
        ],
      },
      distance_meters: {
        triggerValue: 8_000,
        anyOf: [
          { metric: "steps", minimumValue: 3_000 },
          { metric: "active_energy_kcal", minimumValue: 100 },
        ],
      },
      active_energy_kcal: {
        triggerValue: 1_200,
        anyOf: [
          { metric: "exercise_minutes", minimumValue: 10 },
          { metric: "distance_meters", minimumValue: 1_000 },
          { metric: "steps", minimumValue: 3_000 },
        ],
      },
      exercise_minutes: {
        triggerValue: 55,
        anyOf: [
          { metric: "active_energy_kcal", minimumValue: 100 },
          { metric: "distance_meters", minimumValue: 1_000 },
          { metric: "steps", minimumValue: 1_000 },
        ],
      },
    },
  },
  sourceReputation: {
    enabled: true,
    knownBundleIds: [
      "com.garmin.connect.mobile",
      "com.nike.nikeplus-gps",
      "com.strava.stravaride",
    ],
    tiers: {
      unrecognized: {
        severity: "low",
        pointsPerFlag: 5,
      },
      missing: {
        severity: "medium",
        pointsPerFlag: 10,
      },
      malformed: {
        severity: "high",
        pointsPerFlag: 15,
      },
    },
    maxPoints: 30,
  },
  travel: {
    enabled: true,
    severity: "critical",
    pointsPerFlag: 35,
    maxPoints: 70,
    minimumDistanceKm: 500,
    maximumSpeedKph: 1_200,
    maximumGapMs: DAY_MS,
  },
  reportingLag: {
    enabled: true,
    severity: "low",
    pointsPerFlag: 5,
    maxPoints: 15,
    flagAfterMs: DAY_MS,
  },
  retroactiveQuarantine: {
    enabled: true,
    severity: "high",
    pointsPerFlag: 25,
    maxPoints: 50,
    quarantineAfterMs: 3 * DAY_MS,
  },
};

/** The exact timezone-aware M5 configuration retained for reproducible re-scores. */
export const M5_V3_INTEGRITY_TUNING: IntegrityTuningV3 = {
  ...M5_V2_INTEGRITY_TUNING,
  version: "m5-v3",
  timezoneChange: {
    enabled: true,
    severity: "medium",
    pointsPerFlag: 10,
    maxPoints: 20,
  },
};

/**
 * M6 adds two auditable validation sidecars. Neither rule changes metric
 * admissibility, qualification, or totals; their configured penalties can
 * only flow through M4's already-declared integrity-score tie-break.
 */
export const DEFAULT_INTEGRITY_TUNING: IntegrityTuning = {
  ...M5_V3_INTEGRITY_TUNING,
  version: "m6-v1",
  geofenceCheckIn: {
    enabled: true,
    severity: "medium",
    pointsPerFlag: 10,
    maxPoints: 30,
  },
  workoutOverlap: {
    enabled: true,
    severity: "high",
    pointsPerFlag: 15,
    maxPoints: 30,
  },
};

/**
 * A trusted location signal supplied beside metric evidence.
 *
 * M6's geofence check-ins are the intended producer. Keeping the input explicit
 * now means impossible-travel logic is real and fixture-tested without claiming
 * that an hourly HealthKit value contains a location it does not contain.
 */
export interface LocationObservation {
  readonly userId: string;
  readonly observedAt: string;
  readonly latitude: number;
  readonly longitude: number;
  /** Horizontal uncertainty. Subtracted from the distance before speed. */
  readonly accuracyMeters: number;
}

export type AdmissibleMetricProvenance = "device" | "third_party";

/**
 * One row of `public.contest_evidence_sources`, the M3 metadata sidecar for the
 * current admissible contribution of one provenance to one evidence bucket.
 */
export interface SourceEvidence {
  readonly userId: string;
  readonly metric: ContestMetric;
  readonly bucketStart: string;
  readonly provenance: AdmissibleMetricProvenance;
  readonly sourceBundleId?: string | null;
}

export type CheckInValidationOutcome =
  | "accepted"
  | "outside_contest_window"
  | "future_evidence"
  | "simulated_location"
  | "low_accuracy"
  | "outside_geofence"
  | "insufficient_dwell"
  | "insufficient_workout_overlap"
  | "untrusted_workout"
  | "overlapping_checkin"
  | "reused_workout"
  | "overlapping_workout";

/**
 * One row of `public.contest_checkin_integrity`.
 *
 * It is deliberately a validation result, not a scored measurement. The
 * database has already computed the geofence distance, dwell, and temporal
 * workout overlap from attested absolute-time observations. Integrity records
 * a failed result as a flag without removing any metric bucket.
 */
export interface CheckInEvidence {
  readonly userId: string;
  readonly checkInId: string;
  readonly geofenceId: string;
  readonly startedAt: string;
  readonly endedAt: string;
  readonly outcome: CheckInValidationOutcome;
  readonly dwellSeconds: number;
  readonly workoutOverlapSeconds: number;
  readonly attested: boolean;
}

export interface IntegrityInput extends ScoringInput {
  readonly locations?: readonly LocationObservation[];
  readonly sourceEvidence?: readonly SourceEvidence[];
  readonly checkIns?: readonly CheckInEvidence[];
}

export interface ParticipantIntegrity {
  readonly userId: string;
  readonly score: number;
  readonly totalPenalty: number;
  readonly penalties: Readonly<Record<IntegrityFlagCode, number>>;
  readonly flags: readonly IntegrityFlag[];
}

export interface IntegrityAssessment {
  readonly ruleVersion: string;
  readonly participants: readonly ParticipantIntegrity[];
  /** Complete for every accepted participant, which M4 requires for a tie. */
  readonly scores: Readonly<Record<string, number>>;
}

export interface IntegrityScoring {
  readonly scoring: ContestScoring;
  readonly integrity: IntegrityAssessment;
}

function finite(value: number, field: string): number {
  if (!Number.isFinite(value)) throw new ScoringError(`${field} is not a finite number`);
  return value;
}

function nonNegative(value: number, field: string): number {
  finite(value, field);
  if (value < 0) throw new ScoringError(`${field} must not be negative`);
  return value;
}

function positive(value: number, field: string): number {
  finite(value, field);
  if (value <= 0) throw new ScoringError(`${field} must be positive`);
  return value;
}

function numeric(value: NumericValue, field: string): number {
  const parsed = typeof value === "string" ? Number(value) : value;
  finite(parsed, field);
  if (parsed < 0) throw new ScoringError(`${field} must not be negative`);
  return parsed;
}

function instant(value: string, field: string): number {
  const parsed = Date.parse(value);
  if (Number.isNaN(parsed)) {
    throw new ScoringError(`${field} is not an instant: ${JSON.stringify(value)}`);
  }
  return parsed;
}

const BUNDLE_IDENTIFIER_PATTERN =
  /^(?:[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$/;

function normalizedBundleIdentifier(value: string): string | null {
  if (value.length > 200 || !BUNDLE_IDENTIFIER_PATTERN.test(value)) return null;
  return value.toLowerCase();
}

function validatePenalty(rule: RulePenalty, field: string): void {
  nonNegative(rule.pointsPerFlag, `${field}.pointsPerFlag`);
  nonNegative(rule.maxPoints, `${field}.maxPoints`);
  if (rule.maxPoints < rule.pointsPerFlag) {
    throw new ScoringError(`${field}.maxPoints must cover at least one flag`);
  }
}

const LEGACY_DISABLED_TIMEZONE_CHANGE: RulePenalty = {
  enabled: false,
  severity: "medium",
  pointsPerFlag: 0,
  maxPoints: 0,
};

const LEGACY_DISABLED_GEOFENCE_CHECKIN: RulePenalty = {
  enabled: false,
  severity: "medium",
  pointsPerFlag: 0,
  maxPoints: 0,
};

const LEGACY_DISABLED_WORKOUT_OVERLAP: RulePenalty = {
  enabled: false,
  severity: "high",
  pointsPerFlag: 0,
  maxPoints: 0,
};

/**
 * Loads the historical M5 shapes into the current evaluator without changing
 * their behavior. A current or unknown version must declare every current rule
 * explicitly so a partially loaded configuration cannot fail open.
 */
function materializeTuning(tuning: IntegrityTuningConfig): IntegrityTuning {
  const partial = tuning as Partial<IntegrityTuning>;
  let timezoneChange = partial.timezoneChange;
  if (timezoneChange === undefined) {
    if (tuning.version !== M5_V2_INTEGRITY_TUNING.version) {
      throw new ScoringError(
        `integrity.timezoneChange is required for tuning version ${JSON.stringify(tuning.version)}`,
      );
    }
    timezoneChange = LEGACY_DISABLED_TIMEZONE_CHANGE;
  }

  let geofenceCheckIn = partial.geofenceCheckIn;
  let workoutOverlap = partial.workoutOverlap;
  if (geofenceCheckIn === undefined || workoutOverlap === undefined) {
    const historicalM5 = tuning.version === M5_V2_INTEGRITY_TUNING.version ||
      tuning.version === M5_V3_INTEGRITY_TUNING.version;
    if (!historicalM5) {
      const missing = [
        ...(geofenceCheckIn === undefined ? ["geofenceCheckIn"] : []),
        ...(workoutOverlap === undefined ? ["workoutOverlap"] : []),
      ].join(" and ");
      throw new ScoringError(
        `integrity.${missing} is required for tuning version ${JSON.stringify(tuning.version)}`,
      );
    }
    geofenceCheckIn ??= LEGACY_DISABLED_GEOFENCE_CHECKIN;
    workoutOverlap ??= LEGACY_DISABLED_WORKOUT_OVERLAP;
  }

  if (
    timezoneChange === undefined || geofenceCheckIn === undefined ||
    workoutOverlap === undefined
  ) {
    throw new ScoringError(
      `integrity tuning version ${JSON.stringify(tuning.version)} is incomplete`,
    );
  }

  return {
    ...tuning,
    timezoneChange,
    geofenceCheckIn,
    workoutOverlap,
  };
}

function validateTuning(tuning: IntegrityTuning): void {
  if (tuning.version.trim().length === 0 || tuning.version.length > 80) {
    throw new ScoringError("integrity tuning version must contain 1 to 80 characters");
  }
  finite(tuning.startingScore, "integrity.startingScore");
  finite(tuning.floorScore, "integrity.floorScore");
  if (tuning.floorScore > tuning.startingScore) {
    throw new ScoringError("integrity.floorScore must not exceed startingScore");
  }

  validatePenalty(tuning.plausibility, "integrity.plausibility");
  validatePenalty(tuning.corroboration, "integrity.corroboration");
  validatePenalty(tuning.timezoneChange, "integrity.timezoneChange");
  validatePenalty(tuning.geofenceCheckIn, "integrity.geofenceCheckIn");
  validatePenalty(tuning.workoutOverlap, "integrity.workoutOverlap");
  validatePenalty(tuning.travel, "integrity.travel");
  validatePenalty(tuning.reportingLag, "integrity.reportingLag");
  validatePenalty(tuning.retroactiveQuarantine, "integrity.retroactiveQuarantine");

  nonNegative(tuning.sourceReputation.maxPoints, "integrity.sourceReputation.maxPoints");
  for (const [tier, rule] of Object.entries(tuning.sourceReputation.tiers)) {
    nonNegative(
      rule.pointsPerFlag,
      `integrity.sourceReputation.tiers.${tier}.pointsPerFlag`,
    );
    if (tuning.sourceReputation.maxPoints < rule.pointsPerFlag) {
      throw new ScoringError(
        `integrity.sourceReputation.maxPoints must cover one ${tier} flag`,
      );
    }
  }

  const knownBundleIds = new Set<string>();
  for (const bundleId of tuning.sourceReputation.knownBundleIds) {
    const normalized = normalizedBundleIdentifier(bundleId);
    if (normalized === null || normalized !== bundleId) {
      throw new ScoringError(
        "integrity.sourceReputation.knownBundleIds must be canonical bundle identifiers",
      );
    }
    if (knownBundleIds.has(normalized)) {
      throw new ScoringError(
        `integrity.sourceReputation.knownBundleIds repeats ${JSON.stringify(bundleId)}`,
      );
    }
    knownBundleIds.add(normalized);
  }

  for (const [metric, ceiling] of Object.entries(tuning.plausibility.hourlyCeilings)) {
    positive(ceiling, `integrity.plausibility.hourlyCeilings.${metric}`);
  }

  for (const [metric, rule] of Object.entries(tuning.corroboration.byPrimaryMetric)) {
    nonNegative(rule.triggerValue, `integrity.corroboration.${metric}.triggerValue`);
    if (rule.anyOf.length === 0) {
      throw new ScoringError(`integrity.corroboration.${metric}.anyOf must not be empty`);
    }
    for (const corroborator of rule.anyOf) {
      nonNegative(
        corroborator.minimumValue,
        `integrity.corroboration.${metric}.${corroborator.metric}`,
      );
      if (corroborator.metric === metric) {
        throw new ScoringError(`integrity.corroboration.${metric} cannot corroborate itself`);
      }
    }
  }

  positive(tuning.travel.minimumDistanceKm, "integrity.travel.minimumDistanceKm");
  positive(tuning.travel.maximumSpeedKph, "integrity.travel.maximumSpeedKph");
  positive(tuning.travel.maximumGapMs, "integrity.travel.maximumGapMs");
  nonNegative(tuning.reportingLag.flagAfterMs, "integrity.reportingLag.flagAfterMs");
  nonNegative(
    tuning.retroactiveQuarantine.quarantineAfterMs,
    "integrity.retroactiveQuarantine.quarantineAfterMs",
  );
  if (
    tuning.retroactiveQuarantine.quarantineAfterMs <
      tuning.reportingLag.flagAfterMs
  ) {
    throw new ScoringError(
      "retroactive quarantine threshold must not precede the reporting-lag threshold",
    );
  }
}

type StandardIntegrityFlagCode = Exclude<
  IntegrityFlagCode,
  "third_party_source_reputation"
>;

function standardRuleFor(
  tuning: IntegrityTuning,
  code: StandardIntegrityFlagCode,
): RulePenalty {
  switch (code) {
    case "plausibility_ceiling":
      return tuning.plausibility;
    case "cross_metric_corroboration":
      return tuning.corroboration;
    case "timezone_change":
      return tuning.timezoneChange;
    case "geofence_checkin_failure":
      return tuning.geofenceCheckIn;
    case "workout_overlap_validation":
      return tuning.workoutOverlap;
    case "impossible_travel":
      return tuning.travel;
    case "reporting_lag":
      return tuning.reportingLag;
    case "retroactive_evidence_quarantine":
      return tuning.retroactiveQuarantine;
  }
}

function maxPointsFor(
  tuning: IntegrityTuning,
  code: IntegrityFlagCode,
): number {
  if (code === "third_party_source_reputation") {
    return tuning.sourceReputation.maxPoints;
  }
  return standardRuleFor(tuning, code).maxPoints;
}

function weightedFlag(
  code: IntegrityFlagCode,
  userId: string,
  signalKey: string,
  rule: SourceReputationTierTuning,
  fields: Omit<IntegrityFlag, "code" | "userId" | "signalKey" | "severity" | "penaltyPoints">,
): IntegrityFlag {
  return {
    code,
    userId,
    signalKey,
    severity: rule.severity,
    penaltyPoints: rule.pointsPerFlag,
    ...fields,
  };
}

function flag(
  code: StandardIntegrityFlagCode,
  userId: string,
  signalKey: string,
  tuning: IntegrityTuning,
  fields: Omit<IntegrityFlag, "code" | "userId" | "signalKey" | "severity" | "penaltyPoints">,
): IntegrityFlag {
  return weightedFlag(code, userId, signalKey, standardRuleFor(tuning, code), fields);
}

interface PreparedEvidence {
  readonly row: EvidenceBucket;
  readonly startsAt: number;
  readonly closesAt: number;
  readonly value: number;
  readonly reportingLagMs: number;
}

function prepareEvidence(
  input: IntegrityInput,
  accepted: ReadonlySet<string>,
): readonly PreparedEvidence[] {
  const windowStart = instant(input.contest.startsAt, "contest.startsAt");
  const windowEnd = instant(input.contest.endsAt, "contest.endsAt");
  const prepared: PreparedEvidence[] = [];

  for (const row of input.evidence) {
    if (!accepted.has(row.userId)) continue;
    const startsAt = instant(row.bucketStart, "evidence.bucketStart");
    const closesAt = startsAt + HOUR_MS;
    // Integrity judges the same agreed window. It does not turn out-of-window
    // rows that M4 excludes into a penalty through a side door.
    if (startsAt < windowStart || closesAt > windowEnd) continue;

    const lastRecordedAt = instant(row.lastRecordedAt, "evidence.lastRecordedAt");
    prepared.push({
      row,
      startsAt,
      closesAt,
      value: numeric(row.value, "evidence.value"),
      reportingLagMs: Math.max(0, lastRecordedAt - closesAt),
    });
  }

  return prepared.sort((a, b) => {
    if (a.row.userId !== b.row.userId) return a.row.userId < b.row.userId ? -1 : 1;
    if (a.startsAt !== b.startsAt) return a.startsAt - b.startsAt;
    return a.row.metric < b.row.metric ? -1 : a.row.metric > b.row.metric ? 1 : 0;
  });
}

interface ClassifiedSource {
  readonly tier: SourceReputationTier;
  readonly normalizedBundleId: string | null;
}

function classifySource(
  sourceBundleId: string | null | undefined,
  knownBundleIds: ReadonlySet<string>,
): ClassifiedSource {
  if (sourceBundleId === null || sourceBundleId === undefined) {
    return { tier: "missing", normalizedBundleId: null };
  }

  const normalized = normalizedBundleIdentifier(sourceBundleId);
  if (normalized === null) {
    return { tier: "malformed", normalizedBundleId: null };
  }
  if (knownBundleIds.has(normalized)) {
    return { tier: "known", normalizedBundleId: normalized };
  }
  return { tier: "unrecognized", normalizedBundleId: normalized };
}

function sourceEvidenceKey(
  userId: string,
  metric: ContestMetric,
  bucketStart: string,
): string {
  return `${userId}\u0000${metric}\u0000${bucketStart}`;
}

function sourceReputationFlags(
  sources: readonly SourceEvidence[],
  evidence: readonly PreparedEvidence[],
  tuning: IntegrityTuning,
): IntegrityFlag[] {
  if (!tuning.sourceReputation.enabled) return [];

  const eligibleBuckets = new Set(
    evidence.map((item) =>
      sourceEvidenceKey(item.row.userId, item.row.metric, item.row.bucketStart)
    ),
  );
  const knownBundleIds = new Set(tuning.sourceReputation.knownBundleIds);
  const flagsBySignal = new Map<string, IntegrityFlag>();

  for (const source of sources) {
    // Device provenance is first-party by construction. The bundle identifier
    // remains useful audit metadata, but a malformed copy cannot turn genuine
    // hardware into a third-party reputation penalty.
    if (source.provenance === "device") continue;
    if (
      !eligibleBuckets.has(
        sourceEvidenceKey(source.userId, source.metric, source.bucketStart),
      )
    ) {
      // The source sidecar may be loaded for a wider window than M4 scores.
      // It cannot penalize a row the integrity assessor did not judge.
      continue;
    }

    const classified = classifySource(source.sourceBundleId, knownBundleIds);
    if (classified.tier === "known") continue;

    const tierRule = tuning.sourceReputation.tiers[classified.tier];
    const sourceIdentity = classified.normalizedBundleId ??
      source.sourceBundleId ??
      "<missing>";
    const signalKey = `${source.metric}:${source.bucketStart}:${classified.tier}:${sourceIdentity}`;
    const deduplicationKey = `${source.userId}\u0000${signalKey}`;
    if (flagsBySignal.has(deduplicationKey)) continue;

    flagsBySignal.set(
      deduplicationKey,
      weightedFlag(
        "third_party_source_reputation",
        source.userId,
        signalKey,
        tierRule,
        {
          metric: source.metric,
          bucketStart: source.bucketStart,
          details: {
            provenance: source.provenance,
            sourceBundleId: source.sourceBundleId ?? null,
            normalizedSourceBundleId: classified.normalizedBundleId,
            reputationTier: classified.tier,
            evidenceStillScores: true,
          },
        },
      ),
    );
  }

  return [...flagsBySignal.values()];
}

function plausibilityFlags(
  evidence: readonly PreparedEvidence[],
  tuning: IntegrityTuning,
): IntegrityFlag[] {
  if (!tuning.plausibility.enabled) return [];
  const flags: IntegrityFlag[] = [];

  for (const item of evidence) {
    const ceiling = tuning.plausibility.hourlyCeilings[item.row.metric];
    if (item.value <= ceiling) continue;
    flags.push(
      flag(
        "plausibility_ceiling",
        item.row.userId,
        `${item.row.metric}:${item.row.bucketStart}`,
        tuning,
        {
          metric: item.row.metric,
          bucketStart: item.row.bucketStart,
          details: {
            value: item.value,
            hourlyCeiling: ceiling,
            sampleCount: item.row.sampleCount,
          },
        },
      ),
    );
  }

  return flags;
}

function corroborationFlags(
  evidence: readonly PreparedEvidence[],
  primaryMetric: ContestMetric,
  tuning: IntegrityTuning,
): IntegrityFlag[] {
  if (!tuning.corroboration.enabled) return [];

  const rule = tuning.corroboration.byPrimaryMetric[primaryMetric];
  const byHour = new Map<string, Map<ContestMetric, number>>();

  for (const item of evidence) {
    const key = `${item.row.userId}\u0000${item.row.bucketStart}`;
    let metrics = byHour.get(key);
    if (metrics === undefined) {
      metrics = new Map();
      byHour.set(key, metrics);
    }
    metrics.set(item.row.metric, (metrics.get(item.row.metric) ?? 0) + item.value);
  }

  const flags: IntegrityFlag[] = [];
  for (const [key, metrics] of byHour) {
    const primaryValue = metrics.get(primaryMetric) ?? 0;
    if (primaryValue < rule.triggerValue) continue;

    const corroborated = rule.anyOf.some(
      (candidate) => (metrics.get(candidate.metric) ?? 0) >= candidate.minimumValue,
    );
    if (corroborated) continue;

    const separator = key.indexOf("\u0000");
    const userId = key.slice(0, separator);
    const bucketStart = key.slice(separator + 1);
    flags.push(
      flag(
        "cross_metric_corroboration",
        userId,
        `${primaryMetric}:${bucketStart}`,
        tuning,
        {
          metric: primaryMetric,
          bucketStart,
          details: {
            primaryValue,
            triggerValue: rule.triggerValue,
            expectedAnyOf: rule.anyOf
              .map((candidate) => `${candidate.metric}>=${candidate.minimumValue}`)
              .join("|"),
          },
        },
      ),
    );
  }

  return flags;
}

function reportingFlags(
  evidence: readonly PreparedEvidence[],
  tuning: IntegrityTuning,
): IntegrityFlag[] {
  const flags: IntegrityFlag[] = [];

  for (const item of evidence) {
    if (
      tuning.reportingLag.enabled &&
      item.reportingLagMs >= tuning.reportingLag.flagAfterMs
    ) {
      flags.push(
        flag(
          "reporting_lag",
          item.row.userId,
          `${item.row.metric}:${item.row.bucketStart}`,
          tuning,
          {
            metric: item.row.metric,
            bucketStart: item.row.bucketStart,
            details: {
              reportingLagMs: item.reportingLagMs,
              flagAfterMs: tuning.reportingLag.flagAfterMs,
              lastRecordedAt: item.row.lastRecordedAt,
            },
          },
        ),
      );
    }

    if (
      tuning.retroactiveQuarantine.enabled &&
      item.reportingLagMs >= tuning.retroactiveQuarantine.quarantineAfterMs
    ) {
      flags.push(
        flag(
          "retroactive_evidence_quarantine",
          item.row.userId,
          `${item.row.metric}:${item.row.bucketStart}`,
          tuning,
          {
            metric: item.row.metric,
            bucketStart: item.row.bucketStart,
            details: {
              reportingLagMs: item.reportingLagMs,
              quarantineAfterMs: tuning.retroactiveQuarantine.quarantineAfterMs,
              disposition: "review_required",
              evidenceStillScores: true,
            },
          },
        ),
      );
    }
  }

  return flags;
}

function timezoneChangeFlags(
  changes: readonly TimezoneChange[],
  accepted: ReadonlySet<string>,
  tuning: IntegrityTuning,
): IntegrityFlag[] {
  if (!tuning.timezoneChange.enabled) return [];

  return changes
    .filter((change) => accepted.has(change.userId))
    .map((change) => ({
      change,
      at: instant(change.effectiveAt, "timezoneChange.effectiveAt"),
    }))
    .sort((a, b) => {
      if (a.change.userId !== b.change.userId) {
        return a.change.userId < b.change.userId ? -1 : 1;
      }
      return a.at - b.at;
    })
    .map(({ change }) =>
      flag(
        "timezone_change",
        change.userId,
        `${change.effectiveAt}:${change.fromTimezone}:${change.toTimezone}`,
        tuning,
        {
          observedAt: change.effectiveAt,
          details: {
            fromTimezone: change.fromTimezone,
            toTimezone: change.toTimezone,
            effectiveAt: change.effectiveAt,
          },
        },
      )
    );
}

const CHECKIN_OUTCOMES: ReadonlySet<string> = new Set<CheckInValidationOutcome>([
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

const WORKOUT_VALIDATION_OUTCOMES: ReadonlySet<CheckInValidationOutcome> = new Set([
  "insufficient_workout_overlap",
  "untrusted_workout",
  "reused_workout",
  "overlapping_workout",
]);

function checkInFlags(
  checkIns: readonly CheckInEvidence[],
  accepted: ReadonlySet<string>,
  tuning: IntegrityTuning,
): IntegrityFlag[] {
  const seen = new Map<string, string>();
  const flags: IntegrityFlag[] = [];

  for (const checkIn of checkIns) {
    // Match every other integrity input: rows for somebody M4 does not score
    // cannot create a side-channel penalty, and malformed ignored rows do not
    // turn a wider-than-needed query into a failed assessment.
    if (!accepted.has(checkIn.userId)) continue;

    if (!CHECKIN_OUTCOMES.has(checkIn.outcome)) {
      throw new ScoringError(
        `checkIn.outcome is not known: ${JSON.stringify(checkIn.outcome)}`,
      );
    }
    const startedAt = instant(checkIn.startedAt, "checkIn.startedAt");
    const endedAt = instant(checkIn.endedAt, "checkIn.endedAt");
    if (endedAt <= startedAt) {
      throw new ScoringError("checkIn.endedAt must be after startedAt");
    }
    nonNegative(checkIn.dwellSeconds, "checkIn.dwellSeconds");
    nonNegative(checkIn.workoutOverlapSeconds, "checkIn.workoutOverlapSeconds");
    if (checkIn.workoutOverlapSeconds > checkIn.dwellSeconds) {
      throw new ScoringError("checkIn.workoutOverlapSeconds must not exceed dwellSeconds");
    }
    if (typeof checkIn.attested !== "boolean") {
      throw new ScoringError("checkIn.attested must be boolean");
    }

    const identity = `${checkIn.userId}\u0000${checkIn.checkInId}`;
    const material = JSON.stringify([
      checkIn.geofenceId,
      startedAt,
      endedAt,
      checkIn.outcome,
      checkIn.dwellSeconds,
      checkIn.workoutOverlapSeconds,
      checkIn.attested,
    ]);
    const prior = seen.get(identity);
    if (prior !== undefined) {
      if (prior !== material) {
        throw new ScoringError(
          `check-in ${JSON.stringify(checkIn.checkInId)} appears with conflicting validation`,
        );
      }
      continue;
    }
    seen.set(identity, material);

    if (checkIn.outcome === "accepted") continue;

    const code: StandardIntegrityFlagCode = WORKOUT_VALIDATION_OUTCOMES.has(
        checkIn.outcome,
      )
      ? "workout_overlap_validation"
      : "geofence_checkin_failure";
    const rule = standardRuleFor(tuning, code);
    if (!rule.enabled) continue;

    flags.push(
      flag(
        code,
        checkIn.userId,
        `${checkIn.checkInId}:${checkIn.outcome}`,
        tuning,
        {
          observedAt: checkIn.endedAt,
          details: {
            checkInId: checkIn.checkInId,
            geofenceId: checkIn.geofenceId,
            validationOutcome: checkIn.outcome,
            dwellSeconds: checkIn.dwellSeconds,
            workoutOverlapSeconds: checkIn.workoutOverlapSeconds,
            attested: checkIn.attested,
            evidenceStillScores: true,
          },
        },
      ),
    );
  }

  return flags;
}

const EARTH_RADIUS_KM = 6_371.0088;

function radians(degrees: number): number {
  return degrees * Math.PI / 180;
}

function distanceKm(a: LocationObservation, b: LocationObservation): number {
  const lat1 = radians(a.latitude);
  const lat2 = radians(b.latitude);
  const deltaLat = lat2 - lat1;
  const deltaLon = radians(b.longitude - a.longitude);
  const haversine = Math.sin(deltaLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(deltaLon / 2) ** 2;
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.min(1, Math.sqrt(haversine)));
}

interface PreparedLocation {
  readonly observation: LocationObservation;
  readonly at: number;
}

function travelFlags(
  locations: readonly LocationObservation[],
  accepted: ReadonlySet<string>,
  windowStart: number,
  windowEnd: number,
  tuning: IntegrityTuning,
): IntegrityFlag[] {
  if (!tuning.travel.enabled) return [];
  const byUser = new Map<string, PreparedLocation[]>();

  for (const observation of locations) {
    if (!accepted.has(observation.userId)) continue;
    finite(observation.latitude, "location.latitude");
    finite(observation.longitude, "location.longitude");
    nonNegative(observation.accuracyMeters, "location.accuracyMeters");
    if (observation.latitude < -90 || observation.latitude > 90) {
      throw new ScoringError("location.latitude must be between -90 and 90");
    }
    if (observation.longitude < -180 || observation.longitude > 180) {
      throw new ScoringError("location.longitude must be between -180 and 180");
    }

    const at = instant(observation.observedAt, "location.observedAt");
    if (at < windowStart || at >= windowEnd) continue;
    const existing = byUser.get(observation.userId);
    if (existing === undefined) byUser.set(observation.userId, [{ observation, at }]);
    else existing.push({ observation, at });
  }

  const flags: IntegrityFlag[] = [];
  for (const [userId, points] of byUser) {
    points.sort((a, b) => a.at - b.at);
    for (let index = 1; index < points.length; index += 1) {
      const from = points[index - 1];
      const to = points[index];
      if (from === undefined || to === undefined) continue;
      const elapsedMs = to.at - from.at;
      if (elapsedMs <= 0 || elapsedMs > tuning.travel.maximumGapMs) continue;

      const measuredKm = distanceKm(from.observation, to.observation);
      const uncertaintyKm = (from.observation.accuracyMeters + to.observation.accuracyMeters) /
        1_000;
      const conservativeKm = Math.max(0, measuredKm - uncertaintyKm);
      const speedKph = conservativeKm / (elapsedMs / HOUR_MS);
      if (
        conservativeKm < tuning.travel.minimumDistanceKm ||
        speedKph <= tuning.travel.maximumSpeedKph
      ) {
        continue;
      }

      flags.push(
        flag(
          "impossible_travel",
          userId,
          `${from.observation.observedAt}:${to.observation.observedAt}`,
          tuning,
          {
            observedAt: to.observation.observedAt,
            details: {
              fromObservedAt: from.observation.observedAt,
              toObservedAt: to.observation.observedAt,
              conservativeDistanceKm: Math.round(conservativeKm * 100) / 100,
              elapsedMs,
              speedKph: Math.round(speedKph * 100) / 100,
              maximumSpeedKph: tuning.travel.maximumSpeedKph,
            },
          },
        ),
      );
    }
  }

  return flags;
}

const FLAG_ORDER: Readonly<Record<IntegrityFlagCode, number>> = {
  plausibility_ceiling: 0,
  cross_metric_corroboration: 1,
  third_party_source_reputation: 2,
  timezone_change: 3,
  geofence_checkin_failure: 4,
  workout_overlap_validation: 5,
  impossible_travel: 6,
  reporting_lag: 7,
  retroactive_evidence_quarantine: 8,
};

function sortFlags(flags: IntegrityFlag[]): IntegrityFlag[] {
  return flags.sort((a, b) => {
    const byCode = FLAG_ORDER[a.code] - FLAG_ORDER[b.code];
    if (byCode !== 0) return byCode;
    if (a.signalKey !== b.signalKey) return a.signalKey < b.signalKey ? -1 : 1;
    return a.userId < b.userId ? -1 : a.userId > b.userId ? 1 : 0;
  });
}

function participantAssessment(
  userId: string,
  flags: readonly IntegrityFlag[],
  tuning: IntegrityTuning,
): ParticipantIntegrity {
  const penalties: Record<IntegrityFlagCode, number> = {
    plausibility_ceiling: 0,
    cross_metric_corroboration: 0,
    third_party_source_reputation: 0,
    timezone_change: 0,
    geofence_checkin_failure: 0,
    workout_overlap_validation: 0,
    impossible_travel: 0,
    reporting_lag: 0,
    retroactive_evidence_quarantine: 0,
  };

  for (const participantFlag of flags) {
    penalties[participantFlag.code] = Math.min(
      maxPointsFor(tuning, participantFlag.code),
      penalties[participantFlag.code] + participantFlag.penaltyPoints,
    );
  }

  const totalPenalty = Object.values(penalties).reduce((sum, value) => sum + value, 0);
  return {
    userId,
    score: Math.max(tuning.floorScore, tuning.startingScore - totalPenalty),
    totalPenalty,
    penalties,
    flags,
  };
}

/**
 * Produces flags and a complete score map without changing the scoring result.
 */
export function assessContestIntegrity(
  input: IntegrityInput,
  tuningConfig: IntegrityTuningConfig = DEFAULT_INTEGRITY_TUNING,
): IntegrityAssessment {
  const tuning = materializeTuning(tuningConfig);
  validateTuning(tuning);

  // This validates the M4 input and, critically, gives integrity exactly M4's
  // accepted roster. Supplied scores are ignored here: callers cannot seed an
  // assessment with a result they chose themselves.
  const baseline = scoreContest({
    contest: input.contest,
    roster: input.roster,
    evidence: input.evidence,
    timezoneChanges: input.timezoneChanges,
  });
  const accepted = new Set(baseline.standings.map((standing) => standing.userId));
  const evidence = prepareEvidence(input, accepted);
  const windowStart = instant(input.contest.startsAt, "contest.startsAt");
  const windowEnd = instant(input.contest.endsAt, "contest.endsAt");

  const allFlags = sortFlags([
    ...plausibilityFlags(evidence, tuning),
    ...corroborationFlags(evidence, input.contest.metric, tuning),
    ...sourceReputationFlags(input.sourceEvidence ?? [], evidence, tuning),
    ...timezoneChangeFlags(input.timezoneChanges, accepted, tuning),
    ...checkInFlags(input.checkIns ?? [], accepted, tuning),
    ...reportingFlags(evidence, tuning),
    ...travelFlags(input.locations ?? [], accepted, windowStart, windowEnd, tuning),
  ]);

  const participants = baseline.standings.map((standing) =>
    participantAssessment(
      standing.userId,
      allFlags.filter((candidate) => candidate.userId === standing.userId),
      tuning,
    )
  );
  const scores: Record<string, number> = {};
  for (const participant of participants) scores[participant.userId] = participant.score;

  return {
    ruleVersion: tuning.version,
    participants,
    scores,
  };
}

/**
 * The M5 integration point: assess, then use M4's declared tie-break seam.
 *
 * Qualification, totals and evidence summaries are computed by `scoreContest`
 * from the original rows. Only the optional integrity score map is new.
 */
export function scoreContestWithIntegrity(
  input: IntegrityInput,
  tuning: IntegrityTuningConfig = DEFAULT_INTEGRITY_TUNING,
): IntegrityScoring {
  const integrity = assessContestIntegrity(input, tuning);
  const scoring = scoreContest({
    contest: input.contest,
    roster: input.roster,
    evidence: input.evidence,
    timezoneChanges: input.timezoneChanges,
    integrityScores: integrity.scores,
  });
  return { scoring, integrity };
}
