import { assertEquals, assertThrows } from "@std/assert";
import { SCORING_FIXTURES } from "../_test/scoring_fixtures.ts";
import {
  assessContestIntegrity,
  DEFAULT_INTEGRITY_TUNING,
  type IntegrityFlagCode,
  type IntegrityInput,
  type IntegrityTuning,
  type IntegrityTuningV2,
  M5_V2_INTEGRITY_TUNING,
  scoreContestWithIntegrity,
  type SourceEvidence,
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

function cleanTieInput(): IntegrityInput {
  const base = corpusInput("daily/both-perfect-with-no-integrity-scores");
  const aliceEvidence = base.evidence.filter((row) => row.userId === ALICE);
  return {
    ...base,
    evidence: [
      ...aliceEvidence,
      ...aliceEvidence.map((row) => ({ ...row, userId: BOB })),
    ],
  };
}

function sourceEvidenceFor(
  input: IntegrityInput,
  userId: string,
  sourceBundleId: string | null,
  provenance: SourceEvidence["provenance"] = "third_party",
): SourceEvidence[] {
  return input.evidence
    .filter((row) => row.userId === userId)
    .map((row) => ({
      userId,
      metric: row.metric,
      bucketStart: row.bucketStart,
      provenance,
      sourceBundleId,
    }));
}

function oneSourceEvidence(
  input: IntegrityInput,
  userId: string,
  sourceBundleId: string | null,
  provenance: SourceEvidence["provenance"] = "third_party",
): SourceEvidence {
  const source = sourceEvidenceFor(input, userId, sourceBundleId, provenance)[0];
  if (source === undefined) throw new Error(`fixture has no evidence for ${userId}`);
  return source;
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

Deno.test("a known third-party bundle is reputation-clean", () => {
  const base = cleanTieInput();
  const input: IntegrityInput = {
    ...base,
    sourceEvidence: [
      oneSourceEvidence(base, BOB, "COM.STRAVA.STRAVARIDE"),
    ],
  };
  const result = assessContestIntegrity(input);

  assertEquals(
    codes(result, BOB).includes("third_party_source_reputation"),
    false,
  );
  assertEquals(
    participant(result, BOB).penalties.third_party_source_reputation,
    0,
  );
});

Deno.test("an unknown but well-formed third-party bundle gets the unrecognized tier", () => {
  const base = cleanTieInput();
  const input: IntegrityInput = {
    ...base,
    sourceEvidence: [
      oneSourceEvidence(base, BOB, "com.example.unreviewed"),
    ],
  };
  const result = assessContestIntegrity(input);
  const sourceFlag = participant(result, BOB).flags.find(
    (candidate) => candidate.code === "third_party_source_reputation",
  );

  assertEquals(sourceFlag?.details.reputationTier, "unrecognized");
  assertEquals(sourceFlag?.details.evidenceStillScores, true);
  assertEquals(
    participant(result, BOB).penalties.third_party_source_reputation,
    5,
  );
});

Deno.test("a missing third-party bundle id gets its own tunable tier", () => {
  const base = cleanTieInput();
  const input: IntegrityInput = {
    ...base,
    sourceEvidence: [oneSourceEvidence(base, BOB, null)],
  };
  const result = assessContestIntegrity(input);
  const sourceFlag = participant(result, BOB).flags.find(
    (candidate) => candidate.code === "third_party_source_reputation",
  );

  assertEquals(sourceFlag?.details.reputationTier, "missing");
  assertEquals(sourceFlag?.details.sourceBundleId, null);
  assertEquals(
    participant(result, BOB).penalties.third_party_source_reputation,
    10,
  );
});

Deno.test("a malformed third-party bundle id is flagged without rejecting evidence", () => {
  const base = cleanTieInput();
  const input: IntegrityInput = {
    ...base,
    sourceEvidence: [
      oneSourceEvidence(base, BOB, "not a bundle id"),
    ],
  };
  const result = scoreContestWithIntegrity(input);
  const sourceFlag = participant(result.integrity, BOB).flags.find(
    (candidate) => candidate.code === "third_party_source_reputation",
  );
  const bob = result.scoring.standings.find((candidate) => candidate.userId === BOB);

  assertEquals(sourceFlag?.details.reputationTier, "malformed");
  assertEquals(sourceFlag?.details.evidenceStillScores, true);
  assertEquals(bob?.total, 20_000);
  assertEquals(bob?.qualified, true);
});

Deno.test("device provenance never receives a third-party source penalty", () => {
  const base = cleanTieInput();
  const input: IntegrityInput = {
    ...base,
    sourceEvidence: [
      oneSourceEvidence(base, BOB, "not a bundle id", "device"),
    ],
  };
  const result = assessContestIntegrity(input);

  assertEquals(
    codes(result, BOB).includes("third_party_source_reputation"),
    false,
  );
});

Deno.test("the reviewed bundle allow-list is versioned, tunable data", () => {
  const base = cleanTieInput();
  const input: IntegrityInput = {
    ...base,
    sourceEvidence: [
      oneSourceEvidence(base, BOB, "com.example.unreviewed"),
    ],
  };
  const tuning = withTuning({
    version: "test-reviewed-source",
    sourceReputation: {
      ...DEFAULT_INTEGRITY_TUNING.sourceReputation,
      knownBundleIds: [
        ...DEFAULT_INTEGRITY_TUNING.sourceReputation.knownBundleIds,
        "com.example.unreviewed",
      ],
    },
  });
  const result = assessContestIntegrity(input, tuning);

  assertEquals(result.ruleVersion, "test-reviewed-source");
  assertEquals(
    codes(result, BOB).includes("third_party_source_reputation"),
    false,
  );
});

Deno.test("source reputation can be disabled without changing evidence", () => {
  const base = cleanTieInput();
  const input: IntegrityInput = {
    ...base,
    sourceEvidence: sourceEvidenceFor(base, BOB, null),
  };
  const tuning = withTuning({
    version: "test-disabled-source-reputation",
    sourceReputation: {
      ...DEFAULT_INTEGRITY_TUNING.sourceReputation,
      enabled: false,
    },
  });
  const result = scoreContestWithIntegrity(input, tuning);
  const bob = result.scoring.standings.find((candidate) => candidate.userId === BOB);

  assertEquals(
    codes(result.integrity, BOB).includes("third_party_source_reputation"),
    false,
  );
  assertEquals(bob?.total, 20_000);
});

Deno.test("source reputation penalties are capped across repeated buckets", () => {
  const base = cleanTieInput();
  const input: IntegrityInput = {
    ...base,
    sourceEvidence: sourceEvidenceFor(base, BOB, null),
  };
  const result = assessContestIntegrity(input);

  assertEquals(
    participant(result, BOB).flags.filter(
      (candidate) => candidate.code === "third_party_source_reputation",
    ).length,
    4,
  );
  assertEquals(
    participant(result, BOB).penalties.third_party_source_reputation,
    30,
  );
});

Deno.test("repeated source rows are deterministic evaluator retries", () => {
  const base = cleanTieInput();
  const source = oneSourceEvidence(base, BOB, "com.example.unreviewed");
  const first = assessContestIntegrity({
    ...base,
    sourceEvidence: [source],
  });
  const retry = assessContestIntegrity({
    ...base,
    sourceEvidence: [source, source],
  });

  assertEquals(retry, first);
});

Deno.test("third-party source reputation resolves an otherwise clean integrity tie", () => {
  const base = cleanTieInput();
  const input: IntegrityInput = {
    ...base,
    sourceEvidence: [
      ...sourceEvidenceFor(base, ALICE, "com.strava.stravaride"),
      ...sourceEvidenceFor(base, BOB, "com.example.unreviewed"),
    ],
  };
  const result = scoreContestWithIntegrity(input);
  const alice = result.scoring.standings.find((candidate) => candidate.userId === ALICE);
  const bob = result.scoring.standings.find((candidate) => candidate.userId === BOB);

  assertEquals(alice?.total, bob?.total);
  assertEquals(result.integrity.scores[ALICE], 100);
  assertEquals(result.integrity.scores[BOB], 80);
  assertEquals(result.scoring.outcome, {
    kind: "winner",
    userId: ALICE,
    decidedBy: "integrity_score",
  });
});

Deno.test("an applied timezone change emits one bounded flag without changing totals", () => {
  const base = cleanTieInput();
  const input: IntegrityInput = {
    ...base,
    timezoneChanges: [{
      userId: BOB,
      fromTimezone: "UTC",
      toTimezone: "Europe/London",
      effectiveAt: "2026-01-06T00:00:00Z",
    }],
  };
  const result = scoreContestWithIntegrity(input);
  const alice = result.scoring.standings.find((candidate) => candidate.userId === ALICE);
  const bob = result.scoring.standings.find((candidate) => candidate.userId === BOB);
  const timezoneFlags = participant(result.integrity, BOB).flags.filter(
    (candidate) => candidate.code === "timezone_change",
  );

  assertEquals(DEFAULT_INTEGRITY_TUNING.version, "m5-v3");
  assertEquals(DEFAULT_INTEGRITY_TUNING.timezoneChange.pointsPerFlag, 10);
  assertEquals(DEFAULT_INTEGRITY_TUNING.timezoneChange.maxPoints, 20);
  assertEquals(timezoneFlags.length, 1);
  assertEquals(timezoneFlags[0]?.severity, "medium");
  assertEquals(timezoneFlags[0]?.observedAt, "2026-01-06T00:00:00Z");
  assertEquals(timezoneFlags[0]?.details, {
    fromTimezone: "UTC",
    toTimezone: "Europe/London",
    effectiveAt: "2026-01-06T00:00:00Z",
  });
  assertEquals(participant(result.integrity, BOB).penalties.timezone_change, 10);
  assertEquals(codes(result.integrity, BOB).includes("impossible_travel"), false);
  assertEquals(alice?.total, 20_000);
  assertEquals(bob?.total, 20_000);
  assertEquals(result.integrity.scores[ALICE], 100);
  assertEquals(result.integrity.scores[BOB], 90);
  assertEquals(result.scoring.outcome, {
    kind: "winner",
    userId: ALICE,
    decidedBy: "integrity_score",
  });
});

Deno.test("a persisted m5-v2 tuning document remains reproducibly loadable", () => {
  const base = cleanTieInput();
  const input: IntegrityInput = {
    ...base,
    timezoneChanges: [{
      userId: BOB,
      fromTimezone: "UTC",
      toTimezone: "Europe/London",
      effectiveAt: "2026-01-06T00:00:00Z",
    }],
  };
  const loaded = JSON.parse(
    JSON.stringify(M5_V2_INTEGRITY_TUNING),
  ) as IntegrityTuningV2;
  const result = scoreContestWithIntegrity(input, loaded);

  assertEquals(result.integrity.ruleVersion, "m5-v2");
  assertEquals(codes(result.integrity, BOB).includes("timezone_change"), false);
  assertEquals(participant(result.integrity, BOB).penalties.timezone_change, 0);
  assertEquals(result.integrity.scores[ALICE], 100);
  assertEquals(result.integrity.scores[BOB], 100);
  assertEquals(result.scoring.outcome.kind, "undecided");
});

Deno.test("a current tuning document cannot omit its timezone-change rule", () => {
  const incomplete = {
    ...M5_V2_INTEGRITY_TUNING,
    version: "m5-v3",
  };

  assertThrows(
    () => assessContestIntegrity(cleanTieInput(), incomplete),
    ScoringError,
    "integrity.timezoneChange is required",
  );
});

Deno.test("timezone changes for unscored users are ignored completely", () => {
  const base = cleanTieInput();
  const result = assessContestIntegrity({
    ...base,
    timezoneChanges: [{
      userId: "99999999-9999-9999-9999-999999999999",
      fromTimezone: "not even",
      toTimezone: "not even",
      effectiveAt: "not an instant",
    }],
  });

  assertEquals(
    result.participants.flatMap((candidate) =>
      candidate.flags.filter((flag) => flag.code === "timezone_change")
    ),
    [],
  );
  assertEquals(result.scores[ALICE], 100);
  assertEquals(result.scores[BOB], 100);
});

Deno.test("the timezone-change rule can be disabled without changing evidence", () => {
  const base = cleanTieInput();
  const input: IntegrityInput = {
    ...base,
    timezoneChanges: [{
      userId: BOB,
      fromTimezone: "UTC",
      toTimezone: "Europe/London",
      effectiveAt: "2026-01-06T00:00:00Z",
    }],
  };
  const tuning = withTuning({
    version: "test-disabled-timezone-change",
    timezoneChange: {
      ...DEFAULT_INTEGRITY_TUNING.timezoneChange,
      enabled: false,
    },
  });
  const result = scoreContestWithIntegrity(input, tuning);
  const alice = result.scoring.standings.find((candidate) => candidate.userId === ALICE);
  const bob = result.scoring.standings.find((candidate) => candidate.userId === BOB);

  assertEquals(codes(result.integrity, BOB).includes("timezone_change"), false);
  assertEquals(participant(result.integrity, BOB).penalties.timezone_change, 0);
  assertEquals(alice?.total, 20_000);
  assertEquals(bob?.total, 20_000);
  assertEquals(result.scoring.outcome.kind, "undecided");
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

Deno.test("timezone-change tuning must cover at least one configured flag", () => {
  const input = cleanTieInput();
  const tuning = withTuning({
    version: "bad-timezone-change-cap",
    timezoneChange: {
      ...DEFAULT_INTEGRITY_TUNING.timezoneChange,
      pointsPerFlag: 10,
      maxPoints: 5,
    },
  });

  assertThrows(
    () => assessContestIntegrity(input, tuning),
    ScoringError,
    "maxPoints must cover at least one flag",
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
