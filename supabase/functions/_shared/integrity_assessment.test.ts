import {
  assertEquals,
  assertNotEquals,
  assertRejects,
  assertStringIncludes,
  assertThrows,
} from "@std/assert";
import { SCORING_FIXTURES } from "../_test/scoring_fixtures.ts";
import type { IntegrityAssessmentDatabase } from "./database.ts";
import { type IntegrityInput, type QuarantineEvidence } from "./integrity.ts";
import {
  decodeTrustedIntegrityLoad,
  INTEGRITY_ASSESSMENT_SCHEMA_VERSION,
  INTEGRITY_INPUT_SCHEMA_VERSION,
  prepareIntegrityAssessment,
  recordTrustedIntegrityAssessment,
} from "./integrity_assessment.ts";
import { SCORING_VERSION, ScoringError } from "./scoring.ts";

const ALICE = "11111111-1111-1111-1111-111111111111";
const BOB = "22222222-2222-2222-2222-222222222222";
const ZERO_DIGEST = "00".repeat(32);
const ONE_DIGEST = "11".repeat(32);

function fixtureInput(name: string): IntegrityInput {
  const fixture = SCORING_FIXTURES.find((candidate) => candidate.name === name);
  if (fixture === undefined) throw new Error(`missing fixture ${name}`);
  return {
    ...fixture.input,
    locations: [],
    sourceEvidence: [],
    checkIns: [],
    quarantineState: [],
  };
}

function candidateFor(
  row: IntegrityInput["evidence"][number],
  index: number,
) {
  return {
    snapshotId: `d0000000-0000-0000-0000-${String(index + 1).padStart(12, "0")}`,
    userId: row.userId,
    metric: row.metric,
    bucketStart: row.bucketStart,
    recordedAt: row.lastRecordedAt,
    reportingLagMs: Math.max(
      0,
      Date.parse(row.lastRecordedAt) - Date.parse(row.bucketStart) - 3_600_000,
    ),
  };
}

function trustedLoad(
  input: IntegrityInput,
  quarantineCandidates: readonly ReturnType<typeof candidateFor>[] = [],
) {
  const cutoff = new Date(
    Date.parse(input.contest.endsAt) + 6 * 3_600_000,
  ).toISOString();
  return {
    schemaVersion: INTEGRITY_INPUT_SCHEMA_VERSION,
    evidenceCutoff: cutoff,
    loadedAt: new Date(Date.parse(cutoff) + 1_000).toISOString(),
    evidenceDigest: ZERO_DIGEST,
    inputDigest: ONE_DIGEST,
    input,
    quarantineCandidates,
  };
}

Deno.test("a genuinely clean complete load produces an explicit zero-quarantine assessment", async () => {
  const prepared = await prepareIntegrityAssessment(
    trustedLoad(
      fixtureInput("daily/both-perfect-with-no-integrity-scores"),
    ),
  );

  assertEquals(prepared.scoringVersion, SCORING_VERSION);
  assertEquals(prepared.integrityConfigurationVersion, "m6-v1");
  assertEquals(prepared.requiredQuarantines, []);
  assertEquals(
    prepared.assessmentDocument.schema_version,
    INTEGRITY_ASSESSMENT_SCHEMA_VERSION,
  );
  assertEquals(prepared.assessmentDocument.clean_zero_quarantines, true);
  assertEquals(prepared.assessmentDocument.quarantine_observation, {
    total: 0,
    pending: 0,
    approved: 0,
    rejected: 0,
  });
  assertEquals(prepared.standings.length, 2);
});

Deno.test("the assessment loads and accounts for every required M7 evidence sidecar", async () => {
  const base = fixtureInput("daily/both-perfect-with-no-integrity-scores");
  const bobEvidence = base.evidence.find((row) => row.userId === BOB);
  if (bobEvidence === undefined) throw new Error("fixture lost Bob evidence");

  const observedQuarantine: QuarantineEvidence = {
    id: "e0000000-0000-0000-0000-000000000001",
    snapshotId: "d0000000-0000-0000-0000-000000000001",
    userId: ALICE,
    metric: "steps",
    bucketStart: bobEvidence.bucketStart,
    ruleVersion: "m5-v2",
    signalKey: `steps:${bobEvidence.bucketStart}`,
    thresholdMs: 1,
    reportingLagMs: 1,
    reviewerCount: 1,
    approvalsRequired: 1,
    approvalCount: 1,
    rejectionCount: 0,
    state: "approved",
  };
  const input: IntegrityInput = {
    ...base,
    sourceEvidence: [{
      userId: BOB,
      metric: bobEvidence.metric,
      bucketStart: bobEvidence.bucketStart,
      provenance: "third_party",
      sourceBundleId: "com.private.unreviewed-source",
    }],
    timezoneChanges: [{
      userId: BOB,
      fromTimezone: "UTC",
      toTimezone: "Europe/London",
      effectiveAt: "2026-01-06T00:00:00.000Z",
    }],
    quarantineState: [observedQuarantine],
    checkIns: [{
      userId: BOB,
      checkInId: "c0000000-0000-0000-0000-000000000001",
      geofenceId: "f0000000-0000-0000-0000-000000000001",
      startedAt: "2026-01-06T12:00:00.000Z",
      endedAt: "2026-01-06T12:30:00.000Z",
      outcome: "outside_geofence",
      dwellSeconds: 0,
      workoutOverlapSeconds: 0,
      attested: true,
      ruleVersion: "m6-v1",
    }],
    locations: [
      {
        userId: BOB,
        observedAt: "2026-01-06T12:00:00.000Z",
        latitude: 40.7128,
        longitude: -74.006,
        accuracyMeters: 100,
      },
      {
        userId: BOB,
        observedAt: "2026-01-06T14:00:00.000Z",
        latitude: 51.5074,
        longitude: -0.1278,
        accuracyMeters: 100,
      },
    ],
  };

  const prepared = await prepareIntegrityAssessment(trustedLoad(input));
  assertEquals(prepared.assessmentDocument.input_counts, {
    roster: 2,
    contest_evidence: input.evidence.length,
    source_reputation: 1,
    timezone_events: 1,
    quarantine_state: 1,
    checkin_integrity: 1,
    trusted_locations: 2,
  });
  assertEquals(prepared.assessmentDocument.clean_zero_quarantines, false);

  const serialized = JSON.stringify(prepared.assessmentDocument);
  assertEquals(serialized.includes("com.private.unreviewed-source"), false);
  assertEquals(serialized.includes("40.7128"), false);
  assertEquals(serialized.includes("-74.006"), false);
  assertEquals(
    serialized.includes("c0000000-0000-0000-0000-000000000001"),
    false,
  );
  assertStringIncludes(serialized, "third_party_source_reputation");
  assertStringIncludes(serialized, "timezone_change");
  assertStringIncludes(serialized, "geofence_checkin_failure");
  assertStringIncludes(serialized, "impossible_travel");
});

Deno.test("none of the required sidecar arrays may be omitted or replaced with null", () => {
  const complete = trustedLoad(
    fixtureInput("daily/both-perfect-with-no-integrity-scores"),
  );
  for (
    const field of [
      "evidence",
      "timezoneChanges",
      "sourceEvidence",
      "quarantineState",
      "checkIns",
      "locations",
    ] as const
  ) {
    const broken = structuredClone(complete) as Record<string, unknown>;
    const input = broken.input as Record<string, unknown>;
    delete input[field];
    assertThrows(
      () => decodeTrustedIntegrityLoad(broken),
      ScoringError,
      "exact trusted-loader field set",
    );

    input[field] = null;
    assertThrows(
      () => decodeTrustedIntegrityLoad(broken),
      ScoringError,
      "must be supplied as an array",
    );
  }
});

Deno.test("preparing the same frozen load twice is byte-stable and side-effect free", async () => {
  const loaded = trustedLoad(
    fixtureInput("daily/both-perfect-with-no-integrity-scores"),
  );
  const untouched = structuredClone(loaded);
  const first = await prepareIntegrityAssessment(loaded);
  const retry = await prepareIntegrityAssessment(loaded);

  assertEquals(retry, first);
  assertEquals(loaded, untouched);
});

Deno.test("every retroactive flag maps to one exact durable quarantine request", async () => {
  const input = fixtureInput(
    "fraud/a-bucket-first-reported-eleven-days-late-still-scores",
  );
  const candidates = input.evidence.map(candidateFor);
  const prepared = await prepareIntegrityAssessment(
    trustedLoad(input, candidates),
  );

  assertNotEquals(prepared.requiredQuarantines.length, 0);
  for (const required of prepared.requiredQuarantines) {
    assertEquals(required.rule_version, "m6-v1");
    assertEquals(required.threshold_ms > 0, true);
    assertEquals(
      candidates.some((candidate) => candidate.snapshotId === required.snapshot_id),
      true,
    );
    assertEquals(required.details.evidence_still_scores, true);
  }
  assertEquals(
    prepared.assessmentDocument.required_quarantine_count,
    prepared.requiredQuarantines.length,
  );
  assertEquals(prepared.assessmentDocument.clean_zero_quarantines, false);
});

Deno.test("a retroactive flag without its exact snapshot candidate fails closed", async () => {
  const input = fixtureInput(
    "fraud/a-bucket-first-reported-eleven-days-late-still-scores",
  );
  await assertRejects(
    () => prepareIntegrityAssessment(trustedLoad(input)),
    ScoringError,
    "no exact snapshot quarantine candidate",
  );
});

Deno.test("candidate lag must agree exactly with the aggregate assessed by TypeScript", async () => {
  const input = fixtureInput(
    "fraud/a-bucket-first-reported-eleven-days-late-still-scores",
  );
  const candidates = input.evidence.map(candidateFor);
  const lateIndex = candidates.findIndex((candidate) => candidate.reportingLagMs > 0);
  if (lateIndex < 0) throw new Error("fixture lost its late evidence");
  candidates[lateIndex] = {
    ...candidates[lateIndex]!,
    reportingLagMs: candidates[lateIndex]!.reportingLagMs + 1,
  };

  await assertRejects(
    () => prepareIntegrityAssessment(trustedLoad(input, candidates)),
    ScoringError,
    "reporting lag disagrees",
  );
});

Deno.test("the dormant service operation composes trusted load, canonical assessment, and record", async () => {
  const loaded = trustedLoad(
    fixtureInput("daily/both-perfect-with-no-integrity-scores"),
  );
  const assessmentId = "a4000000-0000-4000-8000-000000000001";
  const calls: unknown[] = [];
  const database: IntegrityAssessmentDatabase = {
    loadContestIntegrityInput(contestId) {
      calls.push({ load: contestId });
      return Promise.resolve(loaded);
    },
    recordIntegrityAssessment(args) {
      calls.push({ record: args });
      return Promise.resolve(assessmentId);
    },
  };

  const recorded = await recordTrustedIntegrityAssessment(
    database,
    loaded.input.contest.id,
  );

  assertEquals(recorded.assessmentId, assessmentId);
  assertEquals(calls, [
    { load: loaded.input.contest.id },
    {
      record: {
        contestId: recorded.contestId,
        evidenceCutoff: recorded.evidenceCutoff,
        scoringVersion: recorded.scoringVersion,
        integrityConfigurationVersion: recorded.integrityConfigurationVersion,
        evidenceDigestHex: recorded.evidenceDigest,
        inputDigestHex: recorded.inputDigest,
        assessmentDocument: recorded.assessmentDocument,
        requiredQuarantines: recorded.requiredQuarantines,
      },
    },
  ]);
});
