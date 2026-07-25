/**
 * Drives the corpus in `_test/scoring_fixtures.ts`.
 *
 * The fixtures are the specification and this file is only the harness, which is
 * why it is short and why it asserts on nothing of its own. A change in
 * behaviour should show up as a changed expectation in the corpus, where the
 * `why` field forces whoever changes it to say what property they are giving up.
 */

import { assertEquals, assertThrows } from "@std/assert";
import { SCORING_FIXTURES } from "../_test/scoring_fixtures.ts";
import {
  type ContestScoring,
  type ParticipantStanding,
  scoreContest,
  ScoringError,
} from "./scoring.ts";

function standingFor(scoring: ContestScoring, userId: string): ParticipantStanding {
  const found = scoring.standings.find((standing) => standing.userId === userId);
  if (found === undefined) {
    throw new Error(`no standing for ${userId}; scoring returned ${scoring.standings.length}`);
  }
  return found;
}

for (const fixture of SCORING_FIXTURES) {
  Deno.test(`fixture: ${fixture.name}`, () => {
    if (fixture.error !== undefined) {
      assertThrows(() => scoreContest(fixture.input), ScoringError, fixture.error);
      return;
    }

    const scoring = scoreContest(fixture.input);

    if (fixture.outcome !== undefined) {
      assertEquals(scoring.outcome, fixture.outcome, `outcome for ${fixture.name}`);
    }

    for (const [userId, expected] of Object.entries(fixture.participants ?? {})) {
      const standing = standingFor(scoring, userId);
      const where = `${fixture.name} / ${userId}`;

      if (expected.rank !== undefined) {
        assertEquals(standing.rank, expected.rank, `rank for ${where}`);
      }
      if (expected.qualified !== undefined) {
        assertEquals(standing.qualified, expected.qualified, `qualified for ${where}`);
      }
      if (expected.total !== undefined) {
        assertEquals(standing.total, expected.total, `total for ${where}`);
      }
      if (expected.qualifyingDays !== undefined) {
        assertEquals(standing.qualifyingDays, expected.qualifyingDays, `qualifyingDays ${where}`);
      }
      if (expected.scoreableDays !== undefined) {
        assertEquals(standing.scoreableDays, expected.scoreableDays, `scoreableDays ${where}`);
      }
      if (expected.dayRate !== undefined) {
        assertEquals(standing.dayRate, expected.dayRate, `dayRate for ${where}`);
      }
      if (expected.reachedTargetAt !== undefined) {
        assertEquals(
          standing.reachedTargetAt,
          expected.reachedTargetAt,
          `reachedTargetAt ${where}`,
        );
      }
      if (expected.maxBucketValue !== undefined) {
        assertEquals(
          standing.evidence.maxBucketValue,
          expected.maxBucketValue,
          `maxBucketValue ${where}`,
        );
      }
      if (expected.maxReportingLagMs !== undefined) {
        assertEquals(
          standing.evidence.maxReportingLagMs,
          expected.maxReportingLagMs,
          `maxReportingLagMs ${where}`,
        );
      }
      if (expected.bucketCount !== undefined) {
        assertEquals(standing.evidence.bucketCount, expected.bucketCount, `bucketCount ${where}`);
      }
    }

    for (const [reason, count] of Object.entries(fixture.excluded ?? {})) {
      assertEquals(
        scoring.excluded[reason as keyof typeof scoring.excluded],
        count,
        `excluded.${reason} for ${fixture.name}`,
      );
    }

    if (fixture.order !== undefined) {
      assertEquals(
        scoring.standings.map((standing) => standing.userId),
        fixture.order,
        `display order for ${fixture.name}`,
      );
    }
  });
}

Deno.test("the corpus is portable data, not TypeScript", () => {
  // D3's escape hatch: if a second engine ever has to exist in Swift, the two
  // must be held to the same corpus. That only works while the fixtures survive
  // being written to a file, so this fails the moment somebody reaches for a
  // function, a Date, or a class in a fixture.
  const roundTripped = JSON.parse(JSON.stringify(SCORING_FIXTURES));
  assertEquals(roundTripped, SCORING_FIXTURES);
});

Deno.test("every fixture says what it pins, and no two share a name", () => {
  const names = new Set<string>();
  for (const fixture of SCORING_FIXTURES) {
    if (fixture.why.trim().length < 20) {
      throw new Error(`fixture ${fixture.name} does not explain what it pins`);
    }
    if (fixture.outcome === undefined && fixture.error === undefined) {
      throw new Error(`fixture ${fixture.name} asserts neither an outcome nor an error`);
    }
    if (names.has(fixture.name)) throw new Error(`duplicate fixture name: ${fixture.name}`);
    names.add(fixture.name);
  }
});

Deno.test("scoring is deterministic and does not mutate its input", () => {
  // Re-scoring a disputed contest years later has to give the same answer, and
  // the fixtures are shared across cases, so a mutation here would show up as a
  // test that passes alone and fails in suite order.
  for (const fixture of SCORING_FIXTURES) {
    if (fixture.error !== undefined) continue;
    const before = JSON.stringify(fixture.input);
    const first = scoreContest(fixture.input);
    const second = scoreContest(fixture.input);
    assertEquals(first, second, `re-scoring ${fixture.name} changed the answer`);
    assertEquals(JSON.stringify(fixture.input), before, `scoring mutated ${fixture.name}`);
  }
});
