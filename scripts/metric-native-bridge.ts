/**
 * Verify an actual native XCTest attachment against the sole metric scorer.
 * Usage: deno run --allow-read=/path/to/attachment.json \
 *   scripts/metric-native-bridge.ts /path/to/attachment.json
 * No source reads, network, Health or writes. The attachment contains fiction.
 */
import {
  evaluateMetricFixture,
  type MetricFixtureTerms,
  metricFixtureTermsBinding,
} from "../supabase/functions/_shared/weekly-metric-fixtures.ts";

function check(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
check(
  Deno.args.length === 1,
  "Provide the native metric bridge JSON attachment path.",
);
const bytes = await Deno.readFile(Deno.args[0]);
check(bytes.byteLength <= 32_768, "Oversized native bridge artifact.");
const artifact = JSON.parse(new TextDecoder().decode(bytes));
check(
  artifact.kind === "metric-native-bridge-v1",
  "Wrong native bridge version.",
);
check(
  Array.isArray(artifact.cases) && artifact.cases.length === 4,
  "Expected four cases.",
);
const formats = new Set<string>();
for (const sample of artifact.cases) {
  check(
    typeof sample.terms_json === "string",
    "Missing exact native terms bytes.",
  );
  const terms = JSON.parse(sample.terms_json) as MetricFixtureTerms;
  // This validates all keys, units, source, DST days and timing semantics, and
  // establishes byte-exact canonical agreement binding across Swift and TS.
  check(
    metricFixtureTermsBinding(terms) === sample.terms_json,
    "Native binding differs.",
  );
  const decision = evaluateMetricFixture({
    terms,
    consent: {
      actor_id: terms.actor_id,
      accepted_at: sample.accepted_at,
      terms,
    },
    revisions: [],
    now: sample.now,
  });
  check(
    decision.qualification === "unresolved" &&
      decision.reason === "source_unresolved" &&
      decision.provisional_total === null &&
      decision.best_elapsed_microseconds === null &&
      decision.fixture_only && !decision.final &&
      !decision.real_source_available,
    "Absent observations acquired result authority.",
  );
  formats.add(`${terms.format}:${terms.comparator}`);
}
check(
  [
    "exercise_minutes:gte",
    "cumulative_running_distance:gte",
    "timed_running_distance:lt",
    "timed_running_distance:lte",
  ].every((key) => formats.has(key)),
  "Missing Exercise, cumulative distance or strict/inclusive timed cases.",
);
console.log(
  "PASS: four actual native terms accepted byte-exactly by TypeScript; all unknown observations remain unresolved/nonfinal.",
);
