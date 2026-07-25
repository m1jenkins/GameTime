import { assertEquals, assertThrows } from "@std/assert";
import { SCORING_FIXTURES } from "../_test/scoring_fixtures.ts";
import {
  assessContestIntegrity,
  DEFAULT_INTEGRITY_TUNING,
  type IntegrityFlagCode,
  type IntegrityInput,
  type IntegrityTuning,
  scoreContestWithIntegrity,
} from "./integrity.ts";
import { ScoringError } from "./scoring.ts";

const ALICE = "11111111-1111-1111-1111-111111111111";
const BOB = "22222222-2222-2222-2222-222222222222";

function corpusInput(name: string): IntegrityInput {
  const fixture = SCORING_FIXTURES.find((candidate) => candidate.name === name);
  if (fixture === undefined) throw new Error(`missing scoring fixture ${name}`);
  return fixture.input;
}

function participant(
  result: ReturnType<typeof assessContestIntegrity>,
  userId: string,
) {
  const found = result.participants.find((candidate) => candidate.userId === userId);
  if (found === undefined) throw new Error(`no integrity result for ${userId}`);
  return found;
}

function codes(
  result: ReturnType<typeof assessContestIntegrity>,
  userId: string,
): IntegrityFlagCode[] {
  return participant(result, userId).flags.map((candidate) => candidate.code);
}

function withTuning(
  patch: Partial<IntegrityTuning>,
): IntegrityTuning {
  return { ...DEFAULT_INTEGRITY_TUNING, ...patch };
}

Deno.test("an hourly plausibility ceiling raises a flag and does not discard the bucket", () => {
  const input = corpusInput("fraud/an-implausible-single-hour-still-scores");
  const result = scoreContestWithIntegrity(input);
  const bob = participant(result.integrity, BOB);
  const standing = result.scoring.standings.find((candidate) => candidate.userId === BOB);

  assertEquals(codes(result.integrity, BOB).includes("plausibility_ceiling"), true);
  assertEquals(bob.penalties.plausibility_ceiling, 25);
  assertEquals(standing?.total, 90_000);
  assertEquals(standing?.qualified, true);
  assertEquals(result.scoring.outcome, {
    kind: "winner",
    userId: BOB,
    decidedBy: "sole_qualifier",
  });
});

Deno.test("plausibility ceilings are tunable data, not hard-coded validation", () => {
  const input = corpusInput("fraud/an-implausible-single-hour-still-scores");
  const tuning = withTuning({
    version: "test-high-step-ceiling",
    plausibility: {
      ...DEFAULT_INTEGRITY_TUNING.plausibility,
      hourlyCeilings: {
        ...DEFAULT_INTEGRITY_TUNING.plausibility.hourlyCeilings,
        steps: 100_000,
      },
    },
  });

  assertEquals(
    codes(assessContestIntegrity(input, tuning), BOB).includes("plausibility_ceiling"),
    false,
  );
});

Deno.test("a large primary metric needs same-hour cross-metric corroboration", () => {
  const base = corpusInput("fraud/an-implausible-single-hour-still-scores");
  const bobBucket = base.evidence.find((row) => row.userId === BOB);
  if (bobBucket === undefined) throw new Error("fixture lost Bob's bucket");

  const without = assessContestIntegrity(base);
  assertEquals(codes(without, BOB).includes("cross_metric_corroboration"), true);

  const withCorroboration: IntegrityInput = {
    ...base,
    evidence: [
      ...base.evidence,
      {
        ...bobBucket,
        metric: "distance_meters",
        value: 12_000,
      },
    ],
  };
  const withSignal = assessContestIntegrity(withCorroboration);
  assertEquals(codes(withSignal, BOB).includes("cross_metric_corroboration"), false);
});

Deno.test("corroborating metrics remain excluded from the contest total", () => {
  const input = corpusInput("fraud/cross-metric-padding");
  const result = scoreContestWithIntegrity(input);
  const bob = result.scoring.standings.find((candidate) => candidate.userId === BOB);

  assertEquals(bob?.total, 4_000);
  assertEquals(result.scoring.excluded.other_metric, 2);
});

Deno.test("impossible travel uses conservative distance after location accuracy", () => {
  const base = corpusInput("daily/both-perfect-with-no-integrity-scores");
  const input: IntegrityInput = {
    ...base,
    locations: [
      {
        userId: BOB,
        observedAt: "2026-01-06T12:00:00Z",
        latitude: 40.7128,
        longitude: -74.006,
        accuracyMeters: 100,
      },
      {
        userId: BOB,
        observedAt: "2026-01-06T14:00:00Z",
        latitude: 51.5074,
        longitude: -0.1278,
        accuracyMeters: 100,
      },
    ],
  };

  const result = assessContestIntegrity(input);
  const travel = participant(result, BOB).flags.find(
    (candidate) => candidate.code === "impossible_travel",
  );
  assertEquals(travel?.details.maximumSpeedKph, 1_200);
  assertEquals(typeof travel?.details.speedKph, "number");
  assertEquals(participant(result, BOB).penalties.impossible_travel, 35);
});

Deno.test("ordinary travel under the configured speed does not flag", () => {
  const base = corpusInput("daily/both-perfect-with-no-integrity-scores");
  const input: IntegrityInput = {
    ...base,
    locations: [
      {
        userId: BOB,
        observedAt: "2026-01-06T12:00:00Z",
        latitude: 40.7128,
        longitude: -74.006,
        accuracyMeters: 100,
      },
      {
        userId: BOB,
        observedAt: "2026-01-06T20:00:00Z",
        latitude: 41.8781,
        longitude: -87.6298,
        accuracyMeters: 100,
      },
    ],
  };

  assertEquals(codes(assessContestIntegrity(input), BOB).includes("impossible_travel"), false);
});

Deno.test("reporting lag and retroactive quarantine are separate visible flags", () => {
  const input = corpusInput("fraud/a-bucket-first-reported-eleven-days-late-still-scores");
  const result = scoreContestWithIntegrity(input);
  const bob = participant(result.integrity, BOB);
  const standing = result.scoring.standings.find((candidate) => candidate.userId === BOB);
  const quarantine = bob.flags.find(
    (candidate) => candidate.code === "retroactive_evidence_quarantine",
  );

  assertEquals(codes(result.integrity, BOB).includes("reporting_lag"), true);
  assertEquals(quarantine?.details.disposition, "review_required");
  assertEquals(quarantine?.details.evidenceStillScores, true);
  assertEquals(standing?.total, 21_000);
  assertEquals(standing?.qualified, true);
});

Deno.test("cleaner evidence wins the M4 integrity-score tie-break", () => {
  const input = corpusInput("fraud/a-bucket-first-reported-eleven-days-late-still-scores");
  const result = scoreContestWithIntegrity(input);

  // Both 21k single-hour buckets carry the same plausibility/corroboration
  // penalties. Bob alone also carries lag and quarantine penalties.
  assertEquals(result.integrity.scores[ALICE], 63);
  assertEquals(result.integrity.scores[BOB], 33);
  assertEquals(result.scoring.outcome, {
    kind: "winner",
    userId: ALICE,
    decidedBy: "integrity_score",
  });
});

Deno.test("equal clean integrity scores leave the declared tie-break inconclusive", () => {
  const base = corpusInput("daily/both-perfect-with-no-integrity-scores");
  const aliceEvidence = base.evidence.filter((row) => row.userId === ALICE);
  const input: IntegrityInput = {
    ...base,
    evidence: [
      ...aliceEvidence,
      ...aliceEvidence.map((row) => ({ ...row, userId: BOB })),
    ],
  };
  const result = scoreContestWithIntegrity(input);

  assertEquals(result.integrity.scores[ALICE], result.integrity.scores[BOB]);
  assertEquals(result.scoring.outcome, {
    kind: "undecided",
    reason: "tie_break_inconclusive",
    tied: [ALICE, BOB],
  });
});

Deno.test("every accepted participant gets a score, including one with no evidence", () => {
  const input = corpusInput("roster/a-participant-with-no-evidence-at-all");
  const result = assessContestIntegrity(input);

  assertEquals(Object.keys(result.scores).sort(), [ALICE, BOB]);
  assertEquals(result.scores[BOB], 100);
});

Deno.test("per-rule penalty caps make repeated flags tunable and bounded", () => {
  const base = corpusInput("fraud/an-implausible-single-hour-still-scores");
  const suspicious = base.evidence.find((row) => row.userId === BOB);
  if (suspicious === undefined) throw new Error("fixture lost Bob's bucket");
  const input: IntegrityInput = {
    ...base,
    evidence: [
      ...base.evidence,
      ...[10, 11, 12].map((hour) => ({
        ...suspicious,
        bucketStart: `2026-01-05T${hour}:00:00.000Z`,
        localHour: hour,
        firstRecordedAt: `2026-01-05T${hour + 1}:30:00.000Z`,
        lastRecordedAt: `2026-01-05T${hour + 1}:30:00.000Z`,
      })),
    ],
  };

  const bob = participant(assessContestIntegrity(input), BOB);
  assertEquals(bob.penalties.plausibility_ceiling, 50);
});

Deno.test("a disabled rule emits neither flags nor penalties", () => {
  const input = corpusInput("fraud/an-implausible-single-hour-still-scores");
  const tuning = withTuning({
    version: "test-disabled-plausibility",
    plausibility: {
      ...DEFAULT_INTEGRITY_TUNING.plausibility,
      enabled: false,
    },
  });
  const result = assessContestIntegrity(input, tuning);

  assertEquals(codes(result, BOB).includes("plausibility_ceiling"), false);
  assertEquals(participant(result, BOB).penalties.plausibility_ceiling, 0);
});

Deno.test("invalid tuning fails loudly instead of changing scoring semantics", () => {
  const input = corpusInput("daily/both-perfect-with-no-integrity-scores");
  const tuning = withTuning({
    version: "bad-threshold-order",
    reportingLag: {
      ...DEFAULT_INTEGRITY_TUNING.reportingLag,
      flagAfterMs: 10_000,
    },
    retroactiveQuarantine: {
      ...DEFAULT_INTEGRITY_TUNING.retroactiveQuarantine,
      quarantineAfterMs: 1_000,
    },
  });

  assertThrows(
    () => assessContestIntegrity(input, tuning),
    ScoringError,
    "must not precede",
  );
});

Deno.test("integrity assessment is deterministic and does not mutate fixture input", () => {
  const input = corpusInput("fraud/a-bucket-first-reported-eleven-days-late-still-scores");
  const before = JSON.stringify(input);
  const first = scoreContestWithIntegrity(input);
  const second = scoreContestWithIntegrity(input);

  assertEquals(first, second);
  assertEquals(JSON.stringify(input), before);
});
