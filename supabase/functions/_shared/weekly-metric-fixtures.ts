/**
 * W3/W4 local mathematical prototypes, deliberately disconnected from ingestion,
 * agreements, workers and money. Every observation is FICTIONAL. A closed-world
 * assertion here is a test premise, never a field a real client may assert.
 * No I/O, ambient clock, historical evaluator or finality authority.
 */
export const METRIC_FIXTURE_VERSION = "weekly-metric-fixtures-v1";
export const TRUE_MILE_MILLIMETERS = 1_609_344;
export const TRACK_1600_MILLIMETERS = 1_600_000;

/** Arithmetic/resource bounds only, not recommended goals or launch policy. */
export const METRIC_FIXTURE_BOUNDS = Object.freeze({
  maximumDistanceMillimeters: 1_000_000_000,
  maximumExerciseMilliminutes: 100_000_000,
  maximumElapsedMicroseconds: 86_400_000_000,
  maximumWindowDays: 3660,
  maximumRevisions: 100,
  maximumRecords: 10_000,
});

interface CommonTerms {
  version: typeof METRIC_FIXTURE_VERSION;
  fixture_only: true;
  actor_id: string;
  agreement_id: string;
  starts_at: string;
  ends_at: string;
  corrections_close_at: string;
  display_timezone: string;
}
export interface ExerciseFixtureTerms extends CommonTerms {
  format: "exercise_minutes";
  source: "fixture_apple_exercise_minutes_v1";
  unit: "milliminutes";
  target: number;
  comparator: "gte";
  /** Eight frozen local midnights; exactly seven dates, possibly 167/169 hours. */
  day_boundaries: string[];
}
export interface CumulativeDistanceFixtureTerms extends CommonTerms {
  format: "cumulative_running_distance";
  source: "fixture_cumulative_running_distance_v1";
  unit: "millimeters";
  target: number;
  comparator: "gte";
  activity: "running";
}
export interface TimedDistanceFixtureTerms extends CommonTerms {
  format: "timed_running_distance";
  source: "fixture_timed_running_distance_v1";
  unit: "millimeters";
  target: number;
  activity: "running";
  comparator: "lt" | "lte";
  elapsed_target_microseconds: number;
  timing_basis: "full_elapsed_including_pauses";
  segment_policy: "whole_run_only";
  attempt_window: "start_inclusive_finish_exclusive";
  /** Explicit fictional tolerances; zero is supported, neither is launch-approved. */
  short_tolerance_millimeters: number;
  long_tolerance_millimeters: number;
}
export type MetricFixtureTerms =
  | ExerciseFixtureTerms
  | CumulativeDistanceFixtureTerms
  | TimedDistanceFixtureTerms;

export interface MetricFixtureConsent {
  actor_id: string;
  accepted_at: string;
  /** Full frozen value, compared canonically; no caller-chosen digest authority. */
  terms: MetricFixtureTerms;
}

export interface MetricFixtureRecord {
  id: string;
  /** Distinct imports of the same fictional measurement share this identity. */
  origin_id: string;
  kind: "apple_exercise_time" | "running_workout";
  unit: "milliminutes" | "millimeters";
  value: number;
  starts_at: string;
  ends_at: string;
  provenance: "fixture_sensor" | "manual" | "imported" | "unknown";
  /** Unknown/manual/imported records cannot qualify. This is fixture data only. */
  lineage: "fixture_known" | "unknown";
}

export interface MetricFixtureRevision {
  revision: number;
  supersedes_revision: number | null;
  actor_id: string;
  agreement_id: string;
  source: MetricFixtureTerms["source"];
  terms_binding: string;
  recorded_at: string;
  state: "usable" | "partial" | "permission_unknown" | "source_revoked" | "query_failed";
  /** The test author asserts a fictional closed universe, not Health completeness. */
  fixture_capture: "closed_world" | "unknown";
  /** Whole replacement snapshot, so corrections and deletions can lower totals. */
  records: MetricFixtureRecord[];
}

export interface MetricFixtureDecision {
  qualification: "pending" | "met" | "confirmed_miss" | "unresolved";
  reason:
    | "target_met"
    | "window_or_correction_open"
    | "fictional_closed_set_below_target"
    | "source_unresolved";
  provisional_total: number | null;
  best_elapsed_microseconds: number | null;
  revision: number | null;
  fixture_only: true;
  final: false;
  real_source_available: false;
}

export class MetricFixtureError extends Error {
  override name = "MetricFixtureError";
}
function check(value: unknown, message: string): asserts value {
  if (!value) throw new MetricFixtureError(message);
}
function exactKeys(value: unknown, keys: string[]): asserts value is Record<string, unknown> {
  check(value !== null && typeof value === "object" && !Array.isArray(value), "invalid_object");
  check(
    Object.keys(value).sort().join("|") === [...keys].sort().join("|"),
    "unexpected_or_missing_fields",
  );
}
function identifier(value: unknown): void {
  check(
    typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$/.test(value),
    "invalid_id",
  );
}
function integer(value: unknown, min: number, max: number): asserts value is number {
  check(
    Number.isSafeInteger(value) && Number(value) >= min && Number(value) <= max,
    "invalid_integer",
  );
}
/** Canonical UTC instants preserve PostgreSQL's microsecond boundaries. */
function instant(value: unknown): bigint {
  check(typeof value === "string", "invalid_instant");
  const match = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,6}))?Z$/.exec(value);
  check(match, "invalid_instant");
  const normalized = `${match[1]}.000Z`;
  const ms = Date.parse(normalized);
  check(Number.isFinite(ms) && new Date(ms).toISOString() === normalized, "invalid_instant");
  return BigInt(ms) * 1000n + BigInt((match[2] ?? "").padEnd(6, "0"));
}
function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value !== null && typeof value === "object") {
    return `{${
      Object.keys(value).sort().map((key) =>
        `${JSON.stringify(key)}:${canonical((value as Record<string, unknown>)[key])}`
      ).join(",")
    }}`;
  }
  return JSON.stringify(value);
}

function validateTerms(terms: MetricFixtureTerms): void {
  const common = [
    "version",
    "fixture_only",
    "actor_id",
    "agreement_id",
    "starts_at",
    "ends_at",
    "corrections_close_at",
    "display_timezone",
    "format",
    "source",
    "unit",
    "target",
    "comparator",
  ];
  check(terms !== null && typeof terms === "object", "invalid_terms");
  const format = terms.format;
  check(
    ["exercise_minutes", "cumulative_running_distance", "timed_running_distance"].includes(format),
    "unsupported_format",
  );
  const extra = format === "exercise_minutes"
    ? ["day_boundaries"]
    : format === "cumulative_running_distance"
    ? ["activity"]
    : [
      "activity",
      "elapsed_target_microseconds",
      "timing_basis",
      "segment_policy",
      "attempt_window",
      "short_tolerance_millimeters",
      "long_tolerance_millimeters",
    ];
  exactKeys(terms, [...common, ...extra]);
  check(terms.version === METRIC_FIXTURE_VERSION && terms.fixture_only === true, "fixture_only");
  identifier(terms.actor_id);
  identifier(terms.agreement_id);
  const start = instant(terms.starts_at);
  const end = instant(terms.ends_at);
  const cutoff = instant(terms.corrections_close_at);
  check(start < end && end < cutoff, "invalid_window");
  check(
    end - start <= BigInt(METRIC_FIXTURE_BOUNDS.maximumWindowDays) * 86_400_000_000n,
    "window_too_long",
  );
  check(cutoff - end <= 30n * 86_400_000_000n, "correction_window_too_long");
  let formatter: Intl.DateTimeFormat;
  try {
    check(
      typeof terms.display_timezone === "string" && terms.display_timezone.length > 0,
      "invalid_zone",
    );
    formatter = new Intl.DateTimeFormat("en-CA", {
      timeZone: terms.display_timezone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hourCycle: "h23",
    });
  } catch {
    throw new MetricFixtureError("invalid_zone");
  }
  if (terms.format === "exercise_minutes") {
    check(
      terms.source === "fixture_apple_exercise_minutes_v1" && terms.unit === "milliminutes",
      "wrong_source_or_unit",
    );
    check(terms.comparator === "gte", "wrong_comparator");
    integer(terms.target, 1, METRIC_FIXTURE_BOUNDS.maximumExerciseMilliminutes);
    check(
      Array.isArray(terms.day_boundaries) && terms.day_boundaries.length === 8,
      "invalid_calendar_week",
    );
    check(
      instant(terms.day_boundaries[0]) === start && instant(terms.day_boundaries[7]) === end,
      "wrong_calendar_window",
    );
    let priorDate: number | null = null;
    let priorBoundary: bigint | null = null;
    for (const boundary of terms.day_boundaries) {
      const at = instant(boundary);
      check(at % 1_000_000n === 0n, "non_midnight_boundary");
      const parts = Object.fromEntries(
        formatter.formatToParts(new Date(Number(at / 1000n))).map((
          part,
        ) => [part.type, part.value]),
      );
      check(
        parts.hour === "00" && parts.minute === "00" && parts.second === "00",
        "non_midnight_boundary",
      );
      const date = Date.parse(`${parts.year}-${parts.month}-${parts.day}T00:00:00Z`);
      if (priorDate === null) check(new Date(date).getUTCDay() === 1, "week_must_start_monday");
      if (priorDate !== null) check(date - priorDate === 86_400_000, "nonconsecutive_dates");
      if (priorBoundary !== null) check(at > priorBoundary, "unordered_boundaries");
      priorDate = date;
      priorBoundary = at;
    }
  } else {
    check(terms.unit === "millimeters" && terms.activity === "running", "wrong_unit_or_activity");
    integer(terms.target, 1, METRIC_FIXTURE_BOUNDS.maximumDistanceMillimeters);
    if (terms.format === "cumulative_running_distance") {
      check(
        terms.source === "fixture_cumulative_running_distance_v1" && terms.comparator === "gte",
        "wrong_source_or_comparator",
      );
    } else {
      check(terms.source === "fixture_timed_running_distance_v1", "wrong_source");
      check(terms.comparator === "lt" || terms.comparator === "lte", "wrong_comparator");
      check(
        terms.timing_basis === "full_elapsed_including_pauses" &&
          terms.segment_policy === "whole_run_only" &&
          terms.attempt_window === "start_inclusive_finish_exclusive",
        "unsupported_timing",
      );
      integer(
        terms.elapsed_target_microseconds,
        1,
        METRIC_FIXTURE_BOUNDS.maximumElapsedMicroseconds,
      );
      integer(terms.short_tolerance_millimeters, 0, terms.target - 1);
      integer(
        terms.long_tolerance_millimeters,
        0,
        METRIC_FIXTURE_BOUNDS.maximumDistanceMillimeters - terms.target,
      );
    }
  }
}

/** Stable complete-value binding for fixtures, not a cryptographic attestation. */
export function metricFixtureTermsBinding(terms: MetricFixtureTerms): string {
  validateTerms(terms);
  return canonical(terms);
}

export function evaluateMetricFixture(input: {
  terms: MetricFixtureTerms;
  consent: MetricFixtureConsent;
  revisions: MetricFixtureRevision[];
  now: string;
}): MetricFixtureDecision {
  exactKeys(input, ["terms", "consent", "revisions", "now"]);
  const { terms, consent, revisions } = input;
  validateTerms(terms);
  exactKeys(consent, ["actor_id", "accepted_at", "terms"]);
  validateTerms(consent.terms);
  check(
    consent.actor_id === terms.actor_id && canonical(consent.terms) === canonical(terms),
    "consent_mismatch",
  );
  const now = instant(input.now);
  const accepted = instant(consent.accepted_at);
  const start = instant(terms.starts_at);
  const end = instant(terms.ends_at);
  const cutoff = instant(terms.corrections_close_at);
  check(accepted < start && accepted <= now, "invalid_consent_time");
  check(
    Array.isArray(revisions) && revisions.length <= METRIC_FIXTURE_BOUNDS.maximumRevisions,
    "invalid_revisions",
  );

  let latest: MetricFixtureRevision | null = null;
  let latestRecords: MetricFixtureRecord[] = [];
  let latestUncertainty = false;
  let previousAt = start - 1n;
  for (const revision of revisions) {
    exactKeys(revision, [
      "revision",
      "supersedes_revision",
      "actor_id",
      "agreement_id",
      "source",
      "terms_binding",
      "recorded_at",
      "state",
      "fixture_capture",
      "records",
    ]);
    check(
      revision.revision === (latest?.revision ?? 0) + 1 &&
        revision.supersedes_revision === (latest?.revision ?? null),
      "invalid_revision_chain",
    );
    check(
      revision.actor_id === terms.actor_id && revision.agreement_id === terms.agreement_id &&
        revision.source === terms.source,
      "observation_binding_mismatch",
    );
    check(revision.terms_binding === canonical(terms), "observation_terms_mismatch");
    const recorded = instant(revision.recorded_at);
    check(
      recorded >= start && recorded > previousAt && recorded <= now && recorded < cutoff,
      "invalid_revision_time",
    );
    check(
      ["usable", "partial", "permission_unknown", "source_revoked", "query_failed"].includes(
        revision.state,
      ),
      "invalid_read_state",
    );
    check(["closed_world", "unknown"].includes(revision.fixture_capture), "invalid_capture");
    check(
      Array.isArray(revision.records) &&
        revision.records.length <= METRIC_FIXTURE_BOUNDS.maximumRecords,
      "invalid_records",
    );
    check(
      revision.state === "usable" || revision.state === "partial" || revision.records.length === 0,
      "unusable_query_has_records",
    );
    let uncertain = revision.state !== "usable";
    const ids = new Set<string>();
    const origins = new Set<string>();
    const eligible: MetricFixtureRecord[] = [];
    for (const record of revision.records) {
      exactKeys(record, [
        "id",
        "origin_id",
        "kind",
        "unit",
        "value",
        "starts_at",
        "ends_at",
        "provenance",
        "lineage",
      ]);
      identifier(record.id);
      identifier(record.origin_id);
      check(!ids.has(record.id), "duplicate_record_id");
      ids.add(record.id);
      check(record.unit === terms.unit, "wrong_record_unit");
      check(
        record.kind ===
          (terms.format === "exercise_minutes" ? "apple_exercise_time" : "running_workout"),
        "wrong_metric_kind",
      );
      integer(
        record.value,
        0,
        terms.format === "exercise_minutes"
          ? METRIC_FIXTURE_BOUNDS.maximumExerciseMilliminutes
          : METRIC_FIXTURE_BOUNDS.maximumDistanceMillimeters,
      );
      const rs = instant(record.starts_at);
      const re = instant(record.ends_at);
      check(rs >= start && rs < re && re <= end && re <= recorded, "record_outside_window");
      if (terms.format === "timed_running_distance") {
        check(re < end, "attempt_finish_at_or_after_deadline");
      }
      check(
        ["fixture_sensor", "manual", "imported", "unknown"].includes(record.provenance),
        "invalid_provenance",
      );
      check(["fixture_known", "unknown"].includes(record.lineage), "invalid_lineage");
      if (origins.has(record.origin_id)) uncertain = true;
      origins.add(record.origin_id);
      if (record.provenance === "unknown" || record.lineage === "unknown") uncertain = true;
      if (record.provenance === "fixture_sensor" && record.lineage === "fixture_known") {
        eligible.push(record);
      }
    }
    eligible.sort((a, b) =>
      instant(a.starts_at) < instant(b.starts_at)
        ? -1
        : instant(a.starts_at) > instant(b.starts_at)
        ? 1
        : a.id.localeCompare(b.id)
    );
    let greatestEnd = start;
    for (const record of eligible) {
      // Reconciliation is not invented: any overlapping eligible measurements
      // leave the fixture unresolved instead of summing or selecting a device.
      if (instant(record.starts_at) < greatestEnd) uncertain = true;
      if (instant(record.ends_at) > greatestEnd) greatestEnd = instant(record.ends_at);
    }
    latest = revision;
    previousAt = recorded;
    latestRecords = eligible;
    latestUncertainty = uncertain;
  }

  let total: number | null = null;
  let bestElapsed: number | null = null;
  let met = false;
  if (latest && !latestUncertainty) {
    if (terms.format === "timed_running_distance") {
      for (const record of latestRecords) {
        if (
          record.value < terms.target - terms.short_tolerance_millimeters ||
          record.value > terms.target + terms.long_tolerance_millimeters
        ) continue;
        const elapsed = instant(record.ends_at) - instant(record.starts_at);
        check(elapsed <= BigInt(Number.MAX_SAFE_INTEGER), "elapsed_overflow");
        bestElapsed = Math.min(bestElapsed ?? Number(elapsed), Number(elapsed));
        if (
          terms.comparator === "lt"
            ? elapsed < BigInt(terms.elapsed_target_microseconds)
            : elapsed <= BigInt(terms.elapsed_target_microseconds)
        ) met = true;
      }
    } else {
      const sum = latestRecords.reduce((sum, record) => sum + BigInt(record.value), 0n);
      check(sum <= BigInt(Number.MAX_SAFE_INTEGER), "total_overflow");
      total = Number(sum);
      met = total >= terms.target;
    }
  }
  // A closed snapshot captured mid-window cannot assert the future never
  // contains another workout, even when evaluated much later.
  const fictionalClosedSet = latest !== null && !latestUncertainty &&
    latest.fixture_capture === "closed_world" && instant(latest.recorded_at) >= end;
  const qualification = met
    ? "met"
    : now < cutoff
    ? "pending"
    : fictionalClosedSet
    ? "confirmed_miss"
    : "unresolved";
  return {
    qualification,
    reason: met
      ? "target_met"
      : now < cutoff
      ? "window_or_correction_open"
      : fictionalClosedSet
      ? "fictional_closed_set_below_target"
      : "source_unresolved",
    provisional_total: total,
    best_elapsed_microseconds: bestElapsed,
    revision: latest?.revision ?? null,
    fixture_only: true,
    final: false,
    real_source_available: false,
  };
}
