// Progress is not part of PerformanceScoringInput. These adversarial caller
// extras must never acquire authority when a future client composes a payload.
import { assertEquals } from "@std/assert";
import { evaluatePerformanceCommitment as evaluate } from "./performance_scoring.ts";
import {
  confirm,
  notice,
  performanceFixture,
  proof,
} from "../_test/performance_scoring_fixtures.ts";

const progress = {
  milestones: [{ title: "Run under six minutes", status: "completed", counts_as_proof: false }],
  entries: [{ kind: "check_in", note: "Ran 5K in 5:59", provenance: "owner_reported" }],
};
for (const scenario of ["missing", "no_attempts", "success", "corrected", "no_confirmation"]) {
  Deno.test(`manual progress cannot change ${scenario} proof or result`, () => {
    const f = performanceFixture();
    if (scenario === "no_attempts") f.attempts = [];
    if (["success", "corrected"].includes(scenario)) proof(f, 0, 359);
    if (scenario === "corrected") proof(f, 0, 400);
    if (scenario === "no_confirmation") {
      proof(f, 0, 360);
      proof(f, 1, 400);
    }
    const before = evaluate(f);
    assertEquals(evaluate({ ...f, ...progress }), before);
    const forged = { ...f, manualProgress: { ...progress, counts_as_proof: true } };
    assertEquals(evaluate(forged), before);
  });
}
Deno.test("manually completing a milestone cannot shorten the frozen review window", () => {
  const f = performanceFixture();
  proof(f, 0, 359);
  confirm(f);
  notice(f);
  f.now = "2026-12-11T12:00:00.123455Z";
  const withProgress = { ...f, ...progress };
  assertEquals(evaluate(withProgress), evaluate(f));
  assertEquals(evaluate(withProgress).phase, "provisional");
});
