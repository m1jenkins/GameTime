import { assertEquals, assertThrows } from "@std/assert";
import {
  type CumulativeDistanceFixtureTerms,
  evaluateMetricFixture,
  type ExerciseFixtureTerms,
  METRIC_FIXTURE_VERSION,
  MetricFixtureError,
  type MetricFixtureRecord,
  type MetricFixtureRevision,
  type MetricFixtureTerms,
  metricFixtureTermsBinding,
  type TimedDistanceFixtureTerms,
  TRACK_1600_MILLIMETERS,
  TRUE_MILE_MILLIMETERS,
} from "./weekly-metric-fixtures.ts";

function common() {
  return {
    version: METRIC_FIXTURE_VERSION as typeof METRIC_FIXTURE_VERSION,
    fixture_only: true as const,
    actor_id: "actor-1",
    agreement_id: "new-metric-1",
    starts_at: "2026-09-07T05:00:00Z",
    ends_at: "2026-09-14T05:00:00Z",
    corrections_close_at: "2026-09-15T05:00:00Z",
    display_timezone: "America/Chicago",
  };
}
function exercise(): ExerciseFixtureTerms {
  return {
    ...common(),
    format: "exercise_minutes",
    source: "fixture_apple_exercise_minutes_v1",
    unit: "milliminutes",
    target: 30_000,
    comparator: "gte",
    day_boundaries: Array.from(
      { length: 8 },
      (_, i) => `2026-09-${String(7 + i).padStart(2, "0")}T05:00:00Z`,
    ),
  };
}
function cumulative(): CumulativeDistanceFixtureTerms {
  return {
    ...common(),
    format: "cumulative_running_distance",
    source: "fixture_cumulative_running_distance_v1",
    unit: "millimeters",
    target: 2_000_000,
    comparator: "gte",
    activity: "running",
  };
}
function timed(): TimedDistanceFixtureTerms {
  return {
    ...common(),
    format: "timed_running_distance",
    source: "fixture_timed_running_distance_v1",
    unit: "millimeters",
    target: TRUE_MILE_MILLIMETERS,
    activity: "running",
    comparator: "lt",
    elapsed_target_microseconds: 360_000_000,
    timing_basis: "full_elapsed_including_pauses",
    segment_policy: "whole_run_only",
    attempt_window: "start_inclusive_finish_exclusive",
    short_tolerance_millimeters: 0,
    long_tolerance_millimeters: 0,
  };
}
function record(terms: MetricFixtureTerms, value = terms.target): MetricFixtureRecord {
  return {
    id: "record-1",
    origin_id: "measurement-1",
    unit: terms.unit,
    value,
    kind: terms.format === "exercise_minutes" ? "apple_exercise_time" : "running_workout",
    starts_at: terms.starts_at,
    ends_at: "2026-09-07T05:05:59.999999Z",
    provenance: "fixture_sensor",
    lineage: "fixture_known",
  };
}
function revision(terms: MetricFixtureTerms, records = [record(terms)]): MetricFixtureRevision {
  return {
    revision: 1,
    supersedes_revision: null,
    actor_id: terms.actor_id,
    agreement_id: terms.agreement_id,
    source: terms.source,
    terms_binding: metricFixtureTermsBinding(terms),
    recorded_at: terms.ends_at,
    state: "usable",
    fixture_capture: "closed_world",
    records,
  };
}
function evaluate(
  terms: MetricFixtureTerms,
  revisions = [revision(terms)],
  now = terms.corrections_close_at,
) {
  return evaluateMetricFixture({
    terms,
    consent: {
      actor_id: terms.actor_id,
      accepted_at: "2026-09-01T00:00:00Z",
      terms: structuredClone(terms),
    },
    revisions,
    now,
  });
}

Deno.test("new metric fixtures: Exercise below/exact/above uses actual Exercise units", () => {
  const terms = exercise();
  for (const value of [29_999, 30_000, 30_001]) {
    const result = evaluate(terms, [revision(terms, [record(terms, value)])]);
    assertEquals(result.qualification, value >= terms.target ? "met" : "confirmed_miss");
    assertEquals(result.final, false);
    assertEquals(result.fixture_only, true);
    assertEquals(result.real_source_available, false);
  }
});

Deno.test("new metric fixtures: workout duration and Garmin/ring units cannot masquerade as Exercise", () => {
  for (
    const replacement of [{ kind: "running_workout" }, { unit: "workout_seconds" }, {
      unit: "garmin_intensity_minutes",
    }, { unit: "ring_percentage" }]
  ) {
    const terms = exercise();
    const wrong = { ...record(terms), ...replacement } as MetricFixtureRecord;
    assertThrows(() => evaluate(terms, [revision(terms, [wrong])]), MetricFixtureError);
  }
});

Deno.test("new metric fixtures: manual/imported credit excluded; unknown generated lineage unresolved", () => {
  const terms = exercise();
  for (const provenance of ["manual", "imported"] as const) {
    const input = { ...record(terms), provenance };
    assertEquals(evaluate(terms, [revision(terms, [input])]).provisional_total, 0);
  }
  for (const replacement of [{ lineage: "unknown" }, { provenance: "unknown" }]) {
    const input = { ...record(terms), ...replacement } as MetricFixtureRecord;
    assertEquals(evaluate(terms, [revision(terms, [input])]).qualification, "unresolved");
  }
});

Deno.test("new metric fixtures: missing, partial, revoked and failed data never establish a miss", () => {
  for (const terms of [exercise(), cumulative(), timed()]) {
    assertEquals(evaluate(terms, []).qualification, "unresolved");
    for (
      const state of ["partial", "permission_unknown", "source_revoked", "query_failed"] as const
    ) {
      const input = { ...revision(terms, []), state };
      assertEquals(evaluate(terms, [input]).qualification, "unresolved");
    }
    const unknown = { ...revision(terms, []), fixture_capture: "unknown" as const };
    assertEquals(evaluate(terms, [unknown]).qualification, "unresolved");
  }
});

Deno.test("new metric fixtures: a zero is distinct from no capture; only fictional closed set can miss", () => {
  const terms = exercise();
  assertEquals(
    evaluate(terms, [revision(terms, [record(terms, 0)])]).qualification,
    "confirmed_miss",
  );
  assertEquals(evaluate(terms, [revision(terms, [])]).qualification, "confirmed_miss");
  assertEquals(evaluate(terms, []).provisional_total, null);
  const early = { ...revision(terms, []), recorded_at: "2026-09-08T00:00:00Z" };
  assertEquals(evaluate(terms, [early]).qualification, "unresolved");
});

Deno.test("new metric fixtures: correction cutoff is microsecond exact and rejects equality uploads", () => {
  const terms = exercise();
  const zero = revision(terms, []);
  assertEquals(evaluate(terms, [zero], "2026-09-15T04:59:59.999999Z").qualification, "pending");
  assertEquals(evaluate(terms, [zero], terms.corrections_close_at).qualification, "confirmed_miss");
  assertThrows(
    () => evaluate(terms, [{ ...zero, recorded_at: terms.corrections_close_at }]),
    MetricFixtureError,
  );
});

Deno.test("new metric fixtures: upward/downward corrections and deletion replace the complete snapshot", () => {
  const terms = cumulative();
  const low = revision(terms, [record(terms, 1)]);
  const high = {
    ...revision(terms),
    revision: 2,
    supersedes_revision: 1,
    recorded_at: "2026-09-14T06:00:00Z",
  };
  const deleted = {
    ...high,
    revision: 3,
    supersedes_revision: 2,
    recorded_at: "2026-09-14T07:00:00Z",
    records: [],
  };
  assertEquals(evaluate(terms, [low]).qualification, "confirmed_miss");
  assertEquals(evaluate(terms, [low, high]).qualification, "met");
  assertEquals(evaluate(terms, [low, high, deleted]).qualification, "confirmed_miss");
  const uncertain = { ...deleted, fixture_capture: "unknown" as const };
  assertEquals(evaluate(terms, [low, high, uncertain]).qualification, "unresolved");
});

Deno.test("new metric fixtures: same UUID duplication rejects and reimport/overlap stays unresolved", () => {
  const terms = cumulative();
  const a = record(terms);
  assertThrows(() => evaluate(terms, [revision(terms, [a, a])]), MetricFixtureError);
  const reimport = { ...a, id: "record-2" };
  assertEquals(evaluate(terms, [revision(terms, [a, reimport])]).qualification, "unresolved");
  const overlap = { ...reimport, origin_id: "another-origin" };
  assertEquals(evaluate(terms, [revision(terms, [a, overlap])]).qualification, "unresolved");
});

Deno.test("new metric fixtures: disjoint running totals accumulate without forcing 5K", () => {
  const terms = cumulative();
  const a = record(terms, 1_000_000);
  const b = {
    ...a,
    id: "run-2",
    origin_id: "origin-2",
    starts_at: "2026-09-08T00:00:00Z",
    ends_at: "2026-09-08T00:05:00Z",
  };
  const result = evaluate(terms, [revision(terms, [a, b])]);
  assertEquals(result.qualification, "met");
  assertEquals(result.provisional_total, 2_000_000);
  assertEquals(result.best_elapsed_microseconds, null);
});

Deno.test("new metric fixtures: 1600 meters cannot satisfy an exact true-mile attempt", () => {
  const terms = timed();
  assertEquals(TRUE_MILE_MILLIMETERS - TRACK_1600_MILLIMETERS, 9_344);
  assertEquals(
    evaluate(terms, [revision(terms, [record(terms, TRACK_1600_MILLIMETERS)])]).qualification,
    "confirmed_miss",
  );
  terms.target = TRACK_1600_MILLIMETERS;
  assertEquals(evaluate(terms).qualification, "met");
});

Deno.test("new metric fixtures: strict versus inclusive elapsed threshold and pause handling", () => {
  const terms = timed();
  for (
    const [end, expected] of [["2026-09-07T05:05:59.999999Z", "met"], [
      "2026-09-07T05:06:00Z",
      "confirmed_miss",
    ], ["2026-09-07T05:06:00.000001Z", "confirmed_miss"]] as const
  ) {
    const run = { ...record(terms), ends_at: end };
    assertEquals(evaluate(terms, [revision(terms, [run])]).qualification, expected);
  }
  terms.comparator = "lte";
  const run = { ...record(terms), ends_at: "2026-09-07T05:06:00Z" };
  assertEquals(evaluate(terms, [revision(terms, [run])]).qualification, "met");
  const paused = { ...run, ends_at: "2026-09-07T05:07:00Z" };
  assertEquals(evaluate(terms, [revision(terms, [paused])]).best_elapsed_microseconds, 420_000_000);
  assertThrows(
    () =>
      evaluate(terms, [
        revision(terms, [{ ...paused, moving_microseconds: 300_000_000 } as MetricFixtureRecord]),
      ]),
    MetricFixtureError,
  );
});

Deno.test("new metric fixtures: daily totals and shorter separate runs cannot prove a timed attempt", () => {
  const terms = timed();
  const a = record(terms, 800_000);
  const b = {
    ...a,
    id: "run-2",
    origin_id: "origin-2",
    starts_at: "2026-09-08T00:00:00Z",
    ends_at: "2026-09-08T00:02:00Z",
  };
  assertEquals(evaluate(terms, [revision(terms, [a, b])]).qualification, "confirmed_miss");
  assertThrows(
    () =>
      evaluate(terms, [
        revision(terms, [{ ...a, kind: "daily_distance_total" } as unknown as MetricFixtureRecord]),
      ]),
    MetricFixtureError,
  );
});

Deno.test("new metric fixtures: explicit configurable tolerance applies to a whole run only", () => {
  const terms = timed();
  terms.short_tolerance_millimeters = 9_344;
  assertEquals(
    evaluate(terms, [revision(terms, [record(terms, TRACK_1600_MILLIMETERS)])]).qualification,
    "met",
  );
  assertEquals(
    evaluate(terms, [revision(terms, [record(terms, TRACK_1600_MILLIMETERS - 1)])]).qualification,
    "confirmed_miss",
  );
  assertEquals(
    evaluate(terms, [revision(terms, [record(terms, 5_000_000)])]).qualification,
    "confirmed_miss",
  );
});

Deno.test("new metric fixtures: a timed run ending at the exclusive deadline cannot qualify", () => {
  const terms = timed();
  const equality = { ...record(terms), starts_at: "2026-09-14T04:55:00Z", ends_at: terms.ends_at };
  assertThrows(() => evaluate(terms, [revision(terms, [equality])]), MetricFixtureError);
  const before = { ...equality, ends_at: "2026-09-14T04:59:59.999999Z" };
  assertEquals(evaluate(terms, [revision(terms, [before])]).qualification, "met");
});

Deno.test("new metric fixtures: slower later run preserves success; corrected/deleted success does not", () => {
  const terms = timed();
  const fast = record(terms);
  const slow = {
    ...fast,
    id: "slow",
    origin_id: "slow-origin",
    starts_at: "2026-09-08T00:00:00Z",
    ends_at: "2026-09-08T00:08:00Z",
  };
  assertEquals(evaluate(terms, [revision(terms, [fast, slow])]).qualification, "met");
  const corrected = {
    ...revision(terms, [slow]),
    revision: 2,
    supersedes_revision: 1,
    recorded_at: "2026-09-14T06:00:00Z",
  };
  assertEquals(
    evaluate(terms, [revision(terms, [fast, slow]), corrected]).qualification,
    "confirmed_miss",
  );
});

Deno.test("new metric fixtures: Exercise weeks preserve spring/fall DST and frozen travel zone", () => {
  for (
    const [dates, hours] of [
      [[
        "2026-03-02T06:00:00Z",
        "2026-03-03T06:00:00Z",
        "2026-03-04T06:00:00Z",
        "2026-03-05T06:00:00Z",
        "2026-03-06T06:00:00Z",
        "2026-03-07T06:00:00Z",
        "2026-03-08T06:00:00Z",
        "2026-03-09T05:00:00Z",
      ], 167],
      [[
        "2026-10-26T05:00:00Z",
        "2026-10-27T05:00:00Z",
        "2026-10-28T05:00:00Z",
        "2026-10-29T05:00:00Z",
        "2026-10-30T05:00:00Z",
        "2026-10-31T05:00:00Z",
        "2026-11-01T05:00:00Z",
        "2026-11-02T06:00:00Z",
      ], 169],
    ] as const
  ) {
    const terms: ExerciseFixtureTerms = {
      ...exercise(),
      starts_at: dates[0],
      ends_at: dates[7],
      corrections_close_at: new Date(Date.parse(dates[7]) + 86_400_000).toISOString(),
      day_boundaries: [...dates],
    };
    const input = {
      terms,
      consent: {
        actor_id: terms.actor_id,
        accepted_at: "2026-01-01T00:00:00Z",
        terms: structuredClone(terms),
      },
      revisions: [revision(terms, [])],
      now: terms.corrections_close_at,
    };
    assertEquals((Date.parse(terms.ends_at) - Date.parse(terms.starts_at)) / 3_600_000, hours);
    assertEquals(evaluateMetricFixture(input).qualification, "confirmed_miss");
    const moved = { ...terms, display_timezone: "Asia/Tokyo" };
    assertThrows(() => evaluate(moved, []), MetricFixtureError);
  }
});

Deno.test("new metric fixtures: distance supports longer windows independently of 28–90-day legacy bounds", () => {
  for (const days of [1, 14, 120, 365]) {
    const terms = cumulative();
    terms.ends_at = new Date(Date.parse(terms.starts_at) + days * 86_400_000).toISOString();
    terms.corrections_close_at = new Date(Date.parse(terms.ends_at) + 86_400_000).toISOString();
    assertEquals(evaluate(terms).qualification, "met");
  }
});

Deno.test("new metric fixtures: exact consent, actor, source, agreement and complete terms binding", () => {
  const terms = cumulative();
  const input = {
    terms,
    consent: {
      actor_id: terms.actor_id,
      accepted_at: "2026-09-01T00:00:00Z",
      terms: { ...terms, target: terms.target + 1 },
    },
    revisions: [revision(terms)],
    now: terms.corrections_close_at,
  };
  assertThrows(() => evaluateMetricFixture(input), MetricFixtureError);
  for (
    const changes of [{ actor_id: "other" }, { agreement_id: "other" }, {
      source: "fixture_timed_running_distance_v1",
    }, { terms_binding: "forged" }]
  ) {
    assertThrows(
      () => evaluate(terms, [{ ...revision(terms), ...changes } as MetricFixtureRevision]),
      MetricFixtureError,
    );
  }
  const saved = revision(terms);
  terms.target += 1;
  assertThrows(() => evaluate(terms, [saved]), MetricFixtureError);
});

Deno.test("new metric fixtures: invalid inputs do not round, overflow, accept non-running or escalate trust", () => {
  for (const target of [0, -1, 1.5, NaN, Infinity, Number.MAX_SAFE_INTEGER]) {
    assertThrows(() => evaluate({ ...cumulative(), target }, []), MetricFixtureError);
  }
  const terms = cumulative();
  for (const value of [-1, 0.1, NaN, Infinity]) {
    assertThrows(
      () => evaluate(terms, [revision(terms, [record(terms, value)])]),
      MetricFixtureError,
    );
  }
  for (
    const changes of [
      { activity: "cycling" },
      { source: "healthkit_nonmanual_daily_v1" },
      { fixture_only: false },
      { complete: true },
      { verified: true },
    ]
  ) {
    assertThrows(
      () => evaluate({ ...terms, ...changes } as MetricFixtureTerms, []),
      MetricFixtureError,
    );
  }
});

Deno.test("new metric fixtures: invalid timestamps/window records, revision reorder and replay", () => {
  const terms = timed();
  const saved = revision(terms);
  for (
    const recorded_at of [
      "2026-02-30T00:00:00Z",
      "2026-09-14T05:00:00.0000001Z",
      "2026-09-16T05:00:00Z",
    ]
  ) {
    assertThrows(() => evaluate(terms, [{ ...saved, recorded_at }]), MetricFixtureError);
  }
  assertThrows(() => evaluate(terms, [{ ...saved, revision: 2 }]), MetricFixtureError);
  assertThrows(() => evaluate(terms, [saved, saved]), MetricFixtureError);
  assertThrows(
    () =>
      evaluate(terms, [
        revision(terms, [{ ...record(terms), starts_at: "2026-09-07T04:59:59.999999Z" }]),
      ]),
    MetricFixtureError,
  );
  assertEquals(evaluate(terms, [saved]), evaluate(terms, [structuredClone(saved)]));
});
