/**
 * Engine behaviour the corpus does not cover: malformed inputs, the arithmetic
 * guards, and the ranking rules.
 *
 * The corpus in `_test/scoring_fixtures.ts` is the specification for who wins.
 * What is here is everything a portable fixture cannot express — thrown errors
 * on inputs a caller should never produce, and the properties of the ordering
 * rather than of any one contest.
 */

import { assertEquals, assertThrows } from "@std/assert";
import {
  type EvidenceBucket,
  type RosterEntry,
  scoreContest,
  ScoringError,
  type ScoringInput,
} from "./scoring.ts";
import { UnknownTimeZoneError } from "./localdays.ts";

const ALICE = "11111111-1111-1111-1111-111111111111";
const BOB = "22222222-2222-2222-2222-222222222222";
const CAROL = "33333333-3333-3333-3333-333333333333";

function accepted(userId: string, timezone = "UTC"): RosterEntry {
  return { userId, status: "accepted", timezone, charityId: null };
}

function bucket(userId: string, hour: number, value: number | string): EvidenceBucket {
  const start = new Date(Date.UTC(2026, 0, 5, hour)).toISOString();
  const recorded = new Date(Date.UTC(2026, 0, 5, hour + 1)).toISOString();
  return {
    userId,
    metric: "steps",
    bucketStart: start,
    localDay: "2026-01-05",
    localHour: hour,
    value,
    sampleCount: 4,
    observationCount: 2,
    firstRecordedAt: recorded,
    lastRecordedAt: recorded,
  };
}

function input(overrides: Partial<ScoringInput> = {}): ScoringInput {
  return {
    contest: {
      id: "a0000001-0000-0000-0000-000000000001",
      metric: "steps",
      cadence: "cumulative",
      targetValue: 10000,
      tieBreak: "integrity_score",
      startsAt: "2026-01-05T00:00:00Z",
      endsAt: "2026-01-06T00:00:00Z",
    },
    roster: [accepted(ALICE), accepted(BOB)],
    evidence: [bucket(ALICE, 8, 12000), bucket(BOB, 9, 3000)],
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// Malformed terms
// ---------------------------------------------------------------------------

Deno.test("refuses a window that does not move forwards", () => {
  assertThrows(
    () =>
      scoreContest(input({
        contest: { ...input().contest, startsAt: "2026-01-06T00:00:00Z" },
      })),
    ScoringError,
    "endsAt is not after",
  );
});

Deno.test("refuses an unparseable instant", () => {
  assertThrows(
    () => scoreContest(input({ contest: { ...input().contest, startsAt: "last Tuesday" } })),
    ScoringError,
    "is not an instant",
  );
});

Deno.test("refuses a target that is not positive", () => {
  assertThrows(
    () => scoreContest(input({ contest: { ...input().contest, targetValue: 0 } })),
    ScoringError,
    "must be positive",
  );
});

// ---------------------------------------------------------------------------
// Exact arithmetic
// ---------------------------------------------------------------------------

Deno.test("refuses a value with more precision than the column can hold", () => {
  // numeric(12, 2) cannot produce a third decimal, so one arriving means the
  // caller is reading a different column than it thinks — worth stopping over
  // rather than silently rounding somebody's total.
  assertThrows(
    () => scoreContest(input({ evidence: [bucket(ALICE, 8, 12000.005)] })),
    ScoringError,
    "more than two decimal places",
  );
});

Deno.test("refuses a non-finite value", () => {
  assertThrows(
    () => scoreContest(input({ evidence: [bucket(ALICE, 8, "not a number")] })),
    ScoringError,
    "is not a finite number",
  );
});

Deno.test("sums fractional values exactly", () => {
  // 0.1 + 0.2 is 0.30000000000000004 and 8.7 + 0.1 is 8.799999999999999. Both
  // must read as their exact two-decimal sums.
  const scoring = scoreContest(input({
    contest: {
      ...input().contest,
      metric: "exercise_minutes",
      targetValue: 9,
    },
    evidence: [
      { ...bucket(ALICE, 8, 8.7), metric: "exercise_minutes" },
      { ...bucket(ALICE, 9, 0.1), metric: "exercise_minutes" },
      { ...bucket(BOB, 8, 0.1), metric: "exercise_minutes" },
      { ...bucket(BOB, 9, 0.2), metric: "exercise_minutes" },
    ],
  }));

  assertEquals(scoring.standings.find((s) => s.userId === ALICE)?.total, 8.8);
  assertEquals(scoring.standings.find((s) => s.userId === BOB)?.total, 0.3);
});

// ---------------------------------------------------------------------------
// Ranking
// ---------------------------------------------------------------------------

Deno.test("equal scores share a rank and the next rank skips", () => {
  const scoring = scoreContest(input({
    roster: [accepted(ALICE), accepted(BOB), accepted(CAROL)],
    evidence: [
      bucket(ALICE, 8, 12000),
      bucket(BOB, 8, 12000),
      bucket(CAROL, 8, 500),
    ],
  }));

  const ranks = new Map(scoring.standings.map((s) => [s.userId, s.rank]));
  assertEquals(ranks.get(ALICE), 1);
  assertEquals(ranks.get(BOB), 1);
  assertEquals(ranks.get(CAROL), 3);
});

Deno.test("among equal totals, whoever got there first ranks higher", () => {
  const scoring = scoreContest(input({
    evidence: [bucket(ALICE, 20, 12000), bucket(BOB, 8, 12000)],
  }));
  // Same total and therefore the same rank, but Bob is listed first.
  assertEquals(scoring.standings.map((s) => s.userId), [BOB, ALICE]);
  assertEquals(scoring.standings.map((s) => s.rank), [1, 1]);
});

Deno.test("display order is stable but never decides the outcome", () => {
  // Two participants identical in every respect. The ordering has to put one
  // first because a leaderboard is a list, and the outcome must still refuse to
  // name a winner — otherwise a donation is settled by whose UUID sorts lower.
  const scoring = scoreContest(input({
    evidence: [bucket(ALICE, 8, 12000), bucket(BOB, 8, 12000)],
  }));

  assertEquals(scoring.standings.map((s) => s.userId), [ALICE, BOB]);
  assertEquals(scoring.outcome, {
    kind: "undecided",
    reason: "integrity_score_unavailable",
    tied: [ALICE, BOB],
  });
});

// ---------------------------------------------------------------------------
// Tie-breaks
// ---------------------------------------------------------------------------

Deno.test("an integrity score missing for one qualifier decides nothing", () => {
  // Partial data is not better than none: whoever is missing a score would lose
  // by default, which is a worse failure than declining to answer.
  const scoring = scoreContest(input({
    evidence: [bucket(ALICE, 8, 12000), bucket(BOB, 8, 12000)],
    integrityScores: { [ALICE]: 90 },
  }));
  assertEquals(scoring.outcome.kind, "undecided");
  assertEquals(
    scoring.outcome.kind === "undecided" ? scoring.outcome.reason : undefined,
    "integrity_score_unavailable",
  );
});

Deno.test("equal integrity scores decide nothing", () => {
  const scoring = scoreContest(input({
    evidence: [bucket(ALICE, 8, 12000), bucket(BOB, 8, 12000)],
    integrityScores: { [ALICE]: 90, [BOB]: 90 },
  }));
  assertEquals(scoring.outcome, {
    kind: "undecided",
    reason: "tie_break_inconclusive",
    tied: [ALICE, BOB],
  });
});

Deno.test("an integrity score is consulted only for qualifiers", () => {
  // Bob did not clear the bar, so his spotless integrity score is irrelevant:
  // there is no tie to break and Alice is the sole qualifier.
  const scoring = scoreContest(input({
    evidence: [bucket(ALICE, 8, 12000), bucket(BOB, 8, 500)],
    integrityScores: { [ALICE]: 40, [BOB]: 100 },
  }));
  assertEquals(scoring.outcome, {
    kind: "winner",
    userId: ALICE,
    decidedBy: "sole_qualifier",
  });
});

// ---------------------------------------------------------------------------
// Evidence summary
// ---------------------------------------------------------------------------

Deno.test("the evidence summary aggregates what M5 reads", () => {
  const scoring = scoreContest(input({
    roster: [accepted(ALICE), accepted(BOB)],
    evidence: [
      bucket(ALICE, 8, 4000),
      bucket(ALICE, 9, 9000),
      bucket(BOB, 8, 100),
    ],
  }));

  const alice = scoring.standings.find((s) => s.userId === ALICE);
  assertEquals(alice?.evidence.bucketCount, 2);
  assertEquals(alice?.evidence.sampleCount, 8);
  assertEquals(alice?.evidence.observationCount, 4);
  assertEquals(alice?.evidence.maxBucketValue, 9000);
});

Deno.test("a bucket reported before it closed has no lag, not a negative one", () => {
  const early: EvidenceBucket = {
    ...bucket(ALICE, 8, 12000),
    // Reported half an hour into the hour it covers, which is ordinary for a
    // live sync rather than something to record as time travel.
    firstRecordedAt: "2026-01-05T08:30:00Z",
    lastRecordedAt: "2026-01-05T08:30:00Z",
  };
  const scoring = scoreContest(input({ evidence: [early, bucket(BOB, 9, 100)] }));
  assertEquals(scoring.standings.find((s) => s.userId === ALICE)?.evidence.maxReportingLagMs, 0);
});

// ---------------------------------------------------------------------------
// Zones
// ---------------------------------------------------------------------------

Deno.test("an unknown zone on a daily contest raises rather than voiding", () => {
  assertThrows(
    () =>
      scoreContest(input({
        contest: { ...input().contest, cadence: "daily", endsAt: "2026-01-08T00:00:00Z" },
        roster: [accepted(ALICE, "Mars/Olympus_Mons"), accepted(BOB)],
      })),
    UnknownTimeZoneError,
  );
});

Deno.test("a cumulative contest never consults a zone", () => {
  // Cumulative cadence only cares about the window's two instants, so a zone
  // ICU cannot resolve must not be able to break scoring for it.
  const scoring = scoreContest(input({
    roster: [accepted(ALICE, "Mars/Olympus_Mons"), accepted(BOB)],
  }));
  assertEquals(scoring.outcome, {
    kind: "winner",
    userId: ALICE,
    decidedBy: "sole_qualifier",
  });
});

// ---------------------------------------------------------------------------
// Shape
// ---------------------------------------------------------------------------

Deno.test("reports the contest it scored and the target it used", () => {
  const scoring = scoreContest(input({
    contest: { ...input().contest, targetValue: "10000.00" },
  }));
  assertEquals(scoring.contestId, "a0000001-0000-0000-0000-000000000001");
  assertEquals(scoring.metric, "steps");
  assertEquals(scoring.cadence, "cumulative");
  assertEquals(scoring.target, 10000);
});

Deno.test("an empty roster voids rather than throwing", () => {
  const scoring = scoreContest(input({ roster: [], evidence: [] }));
  assertEquals(scoring.outcome, { kind: "void", reason: "insufficient_participants" });
  assertEquals(scoring.standings, []);
});
