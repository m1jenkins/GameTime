import { assertEquals } from "@std/assert";
import { M6_INTEGRITY_FIXTURES } from "../_test/m6_integrity_fixtures.ts";
import { SCORING_FIXTURES } from "../_test/scoring_fixtures.ts";
import {
  assessContestIntegrity,
  type IntegrityInput,
  scoreContestWithIntegrity,
} from "./integrity.ts";

const ALICE = "11111111-1111-1111-1111-111111111111";
const BOB = "22222222-2222-2222-2222-222222222222";

function cleanTieInput(): IntegrityInput {
  const fixture = SCORING_FIXTURES.find(
    (candidate) => candidate.name === "daily/both-perfect-with-no-integrity-scores",
  );
  if (fixture === undefined) throw new Error("missing clean daily fixture");
  const aliceEvidence = fixture.input.evidence.filter((row) => row.userId === ALICE);
  return {
    ...fixture.input,
    locations: [],
    sourceEvidence: [],
    checkIns: [],
    quarantineState: [],
    evidence: [
      ...aliceEvidence,
      ...aliceEvidence.map((row) => ({ ...row, userId: BOB })),
    ],
  };
}

for (const fixture of M6_INTEGRITY_FIXTURES) {
  Deno.test(`M6 fixture: ${fixture.name}`, () => {
    const input: IntegrityInput = {
      ...cleanTieInput(),
      checkIns: [fixture.checkIn],
    };
    const assessment = assessContestIntegrity(input);
    const bob = assessment.participants.find((participant) => participant.userId === BOB);
    if (bob === undefined) throw new Error("fixture lost Bob");

    assertEquals(
      bob.flags.map((flag) => flag.code),
      fixture.expectedFlag === null ? [] : [fixture.expectedFlag],
      fixture.why,
    );
    const actualPenalty = fixture.expectedFlag === null ? 0 : bob.penalties[fixture.expectedFlag];
    assertEquals(actualPenalty, fixture.expectedPenalty, fixture.why);

    const scored = scoreContestWithIntegrity(input);
    const standing = scored.scoring.standings.find((row) => row.userId === BOB);
    assertEquals(standing?.total, 20_000, "check-in validation never rewrites metric totals");
    assertEquals(standing?.qualified, true, "check-in validation never changes qualification");
  });
}

Deno.test("M6 integrity fixtures remain portable plain data", () => {
  assertEquals(
    JSON.parse(JSON.stringify(M6_INTEGRITY_FIXTURES)),
    M6_INTEGRITY_FIXTURES,
  );
});
