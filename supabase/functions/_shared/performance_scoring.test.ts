import { assertEquals, assertThrows } from "@std/assert";
import {
  evaluatePerformanceCommitment as evaluate,
  PERFORMANCE_SCORING_VERSION,
  PerformanceScoringError,
} from "./performance_scoring.ts";
import {
  confirm,
  notice,
  performanceFixture,
  proof,
} from "../_test/performance_scoring_fixtures.ts";

Deno.test("strict 5K target: 359 succeeds, exactly 360 and 361 miss after complete-set confirmation", () => {
  for (const seconds of [359, 360, 361]) {
    const f = performanceFixture();
    proof(f, 0, seconds);
    proof(f, 1, 400);
    confirm(f);
    notice(f);
    f.now = "2026-12-11T12:00:00.123456Z";
    assertEquals(evaluate(f).outcome?.kind, seconds < 360 ? "success" : "miss");
    assertEquals(evaluate(f).phase, "ready_to_finalize");
  }
});
Deno.test("a later slower run retains the earlier success, even with another missing record", () => {
  const f = performanceFixture();
  proof(f, 0, 359);
  proof(f, 1, 400);
  assertEquals(evaluate(f).outcome, {
    kind: "success",
    reason: "strict_target_met",
    attemptId: "attempt-1",
  });
  f.proofRevisions.pop();
  assertEquals(evaluate(f).outcome?.kind, "success");
});
Deno.test("only a correction to the successful attempt removes that success", () => {
  const f = performanceFixture();
  proof(f, 0, 359);
  proof(f, 1, 400);
  proof(f, 0, 380);
  confirm(f);
  assertEquals(evaluate(f).outcome?.kind, "miss");
});
Deno.test("no nominations is missing proof until explicitly acknowledged after deadline", () => {
  const f = performanceFixture();
  f.attempts = [];
  assertEquals(evaluate(f).outcome?.kind, "inconclusive");
  confirm(f);
  assertEquals(evaluate(f).outcome, { kind: "miss", reason: "explicit_no_attempts" });
  assertEquals(evaluate(f).phase, "provisional");
});
Deno.test("complete nominated records without the owner's complete-set confirmation are not a proven miss", () => {
  const f = performanceFixture();
  proof(f, 0, 360);
  proof(f, 1, 361);
  assertEquals(evaluate(f).outcome?.kind, "inconclusive");
});
for (const status of ["dns", "dnf", "disqualified", "missing", "ambiguous"] as const) {
  Deno.test(`official ${status} remains distinct from unknown proof`, () => {
    const f = performanceFixture();
    f.attempts.pop();
    const r = proof(f, 0, 400).source.document;
    Object.assign(r, { status, chip_seconds: null, started_at: null, finished_at: null });
    confirm(f);
    assertEquals(
      evaluate(f).outcome?.kind,
      ["missing", "ambiguous"].includes(status) ? "inconclusive" : "miss",
    );
  });
}
for (
  const [key, value] of Object.entries({
    source: "garmin",
    distance_meters: 1609.344,
    timing_basis: "moving",
    precision_ms: 1,
    published_bib: "wrong",
    chip_seconds: 359.5,
    event_id: "different",
  })
) {
  Deno.test(`unsupported proof ${key} cannot establish success or a miss`, () => {
    const f = performanceFixture();
    f.attempts.pop();
    Object.assign(proof(f, 0, 359).source.document, { [key]: value });
    confirm(f);
    assertEquals(evaluate(f).outcome?.kind, "inconclusive");
  });
}
Deno.test("actual chip start and finish must match the event window and whole-second duration", () => {
  const f = performanceFixture();
  f.attempts.pop();
  const r = proof(f, 0, 359).source.document;
  r.started_at = "2026-10-03T12:00:00.123455Z";
  assertEquals(evaluate(f).outcome?.kind, "inconclusive");
});
Deno.test("start inclusive and end exclusive retain PostgreSQL microseconds", () => {
  const f = performanceFixture();
  f.attempts.pop();
  const e = f.attempts[0]!.event;
  e.starts_at = f.agreement.terms.starts_at;
  e.ends_at = "2026-10-02T14:00:00.123456Z";
  proof(f, 0, 359);
  assertEquals(evaluate(f).outcome?.kind, "success");
  e.starts_at = "2026-10-02T12:00:00.123455Z";
  assertThrows(() => evaluate(f), PerformanceScoringError, "invalid_nominated_window");
  e.starts_at = "2026-12-01T10:00:00.123456Z";
  e.ends_at = f.agreement.terms.deadline_at;
  assertThrows(() => evaluate(f), PerformanceScoringError, "invalid_nominated_window");
});
for (const at of ["2026-12-04T12:00:00.123455Z", "2026-12-04T12:00:00.123456Z"]) {
  Deno.test(`initial proof receipt cutoff ${at}`, () => {
    const f = performanceFixture();
    proof(f, 0, 359, at);
    assertEquals(evaluate(f).outcome?.kind, at.endsWith("455Z") ? "success" : "inconclusive");
    assertEquals(evaluate(f).supportCorrectionRequired, at.endsWith("456Z"));
  });
}
Deno.test("a late first record cannot become admissible via an earlier-looking correction", () => {
  const f = performanceFixture();
  proof(f, 0, 359, f.now);
  f.now = "2026-12-05T12:00:00.123456Z";
  proof(f, 0, 350, f.now);
  assertEquals(evaluate(f).outcome?.kind, "inconclusive");
});
Deno.test("correction starts a fresh full seven-day notice window", () => {
  const f = performanceFixture();
  proof(f, 0, 359);
  notice(f);
  proof(f, 0, 380, "2026-12-10T12:00:00.123456Z");
  f.now = "2026-12-11T12:00:00.123456Z";
  assertEquals(evaluate(f).disputeClosesAt, null);
  notice(f, "2026-12-10T12:00:00.123456Z");
  assertEquals(evaluate(f).disputeClosesAt, "2026-12-17T12:00:00.123456Z");
  assertEquals(evaluate(f).phase, "provisional");
});
Deno.test("notice deadline equality finalizes; one microsecond earlier does not", () => {
  const f = performanceFixture();
  proof(f, 0, 359);
  notice(f);
  f.now = "2026-12-11T12:00:00.123455Z";
  assertEquals(evaluate(f).phase, "provisional");
  f.now = "2026-12-11T12:00:00.123456Z";
  assertEquals(evaluate(f).phase, "ready_to_finalize");
});
Deno.test("no durable notice means no confirmed miss and cap yields inconclusive", () => {
  const f = performanceFixture();
  proof(f, 0, 400);
  proof(f, 1, 400);
  confirm(f);
  assertEquals(evaluate(f).phase, "provisional");
  f.now = f.agreement.terms.finality_due_at;
  assertEquals(evaluate(f).outcome, { kind: "inconclusive", reason: "finality_timeout" });
});
Deno.test("corrections near cap never shorten the seven-day review window", () => {
  const f = performanceFixture();
  proof(f, 0, 359);
  notice(f);
  proof(f, 0, 380, "2026-12-30T12:00:00.123456Z");
  notice(f, "2026-12-30T12:00:00.123456Z");
  f.now = f.agreement.terms.finality_due_at;
  assertEquals(evaluate(f).outcome, { kind: "inconclusive", reason: "finality_timeout" });
});
Deno.test("correction at finality cap is support-only", () => {
  const f = performanceFixture();
  proof(f, 0, 359);
  notice(f);
  proof(f, 0, 380, f.agreement.terms.finality_due_at);
  f.now = f.agreement.terms.finality_due_at;
  assertEquals(evaluate(f).outcome?.kind, "success");
  assertEquals(evaluate(f).supportCorrectionRequired, true);
});
Deno.test("review is independent and has a full seven-day deadline", () => {
  const f = performanceFixture();
  proof(f, 0, 359);
  notice(f);
  f.reviews = [{
    id: "case",
    proofRevision: 1,
    filedBy: f.agreement.actor_id,
    filedAt: "2026-12-11T12:00:00.123455Z",
    resolution: null,
  }];
  f.now = "2026-12-18T12:00:00.123454Z";
  assertEquals(evaluate(f).phase, "provisional");
  assertEquals(evaluate(f).reviewDueAt, "2026-12-18T12:00:00.123455Z");
  f.now = "2026-12-18T12:00:00.123455Z";
  assertEquals(evaluate(f).outcome, { kind: "inconclusive", reason: "review_timeout" });
  f.reviews[0]!.resolution = {
    reviewerId: f.agreement.actor_id,
    decidedAt: "2026-12-12T12:00:00.123456Z",
    decision: "uphold",
  };
  assertThrows(() => evaluate(f), PerformanceScoringError, "invalid_review_resolution");
});
Deno.test("filing exactly at review deadline is too late", () => {
  const f = performanceFixture();
  proof(f, 0, 359);
  notice(f);
  f.now = "2026-12-11T12:00:00.123456Z";
  f.reviews = [{
    id: "case",
    proofRevision: 1,
    filedBy: f.agreement.actor_id,
    filedAt: f.now,
    resolution: null,
  }];
  assertThrows(() => evaluate(f), PerformanceScoringError, "invalid_review_case");
});
Deno.test("independent review can uphold or remove consequence without changing a time", () => {
  for (const decision of ["uphold", "inconclusive"] as const) {
    const f = performanceFixture();
    proof(f, 0, 359);
    notice(f);
    f.now = "2026-12-11T12:00:00.123456Z";
    f.reviews = [{
      id: "case",
      proofRevision: 1,
      filedBy: f.agreement.actor_id,
      filedAt: "2026-12-05T12:00:00.123456Z",
      resolution: {
        reviewerId: "reviewer-two",
        decidedAt: "2026-12-06T12:00:00.123456Z",
        decision,
      },
    }];
    assertEquals(evaluate(f).outcome?.kind, decision === "uphold" ? "success" : "inconclusive");
  }
});
Deno.test("persisted final survives later correction with a support flag", () => {
  const f = performanceFixture();
  proof(f, 0, 359);
  notice(f);
  f.now = "2026-12-11T12:00:00.123456Z";
  const result = evaluate(f);
  f.finalResult = {
    version: PERFORMANCE_SCORING_VERSION,
    commitmentId: f.agreement.id,
    termsDigest: f.agreement.terms_digest,
    finalizedAt: f.now,
    proofRevision: result.proofRevision,
    outcome: result.outcome!,
  };
  proof(f, 0, 380, "2026-12-12T12:00:00.123456Z");
  f.now = "2026-12-12T12:00:00.123456Z";
  assertEquals(evaluate(f).outcome, result.outcome);
  assertEquals(evaluate(f).phase, "final");
  assertEquals(evaluate(f).supportCorrectionRequired, true);
});
for (const reason of ["cancel", "withdrawal", "injury", "account_deleted"] as const) {
  Deno.test(`safe exit ${reason} remains zero-consequence`, () => {
    const f = performanceFixture();
    f.attempts = [];
    f.agreement.status = reason === "cancel" ? "cancelled" : "withdrawn";
    f.agreement.closed_at = reason === "cancel"
      ? "2026-10-01T14:00:00.123456Z"
      : "2026-12-01T14:00:00.123456Z";
    f.agreement.close_reason = reason;
    assertEquals(evaluate(f).outcome, { kind: "closed", reason });
  });
}
Deno.test("mutated terms, consent and revision chains fail closed", () => {
  for (
    const mutate of [
      (f: ReturnType<typeof performanceFixture>) => {
        f.agreement.terms.policy.comparator = "lte";
      },
      (f: ReturnType<typeof performanceFixture>) => {
        f.agreement.consent.terms_digest = "b".repeat(64);
      },
      (f: ReturnType<typeof performanceFixture>) => {
        proof(f, 0, 359).reviewer_id = f.agreement.actor_id;
      },
      (f: ReturnType<typeof performanceFixture>) => {
        proof(f, 0, 359).supersedes_revision = 1;
      },
      (f: ReturnType<typeof performanceFixture>) => {
        f.attempts.push(structuredClone(f.attempts[0]!));
      },
    ]
  ) {
    const f = performanceFixture();
    mutate(f);
    assertThrows(() => evaluate(f), PerformanceScoringError);
  }
});
Deno.test("invalid calendar and pre-agreement clock rejected", () => {
  const f = performanceFixture();
  f.now = "2026-02-30T00:00:00Z";
  assertThrows(() => evaluate(f), PerformanceScoringError, "invalid_instant");
  f.now = "2026-10-01T12:00:00.123455Z";
  assertThrows(() => evaluate(f), PerformanceScoringError, "invalid_agreement_window");
});
Deno.test("DST and leap day use elapsed instants over 60 days, with equivalent offsets", () => {
  const f = performanceFixture();
  f.attempts = [];
  Object.assign(f.agreement, { created_at: "2028-02-01T12:00:00.123456Z" });
  f.agreement.consent.accepted_at = f.agreement.created_at;
  Object.assign(f.agreement.terms, {
    starts_at: "2028-02-02T06:00:00.123456-06:00",
    deadline_at: "2028-04-02T07:00:00.123456-05:00",
    results_due_at: "2028-04-05T12:00:00.123456Z",
    finality_due_at: "2028-05-02T12:00:00.123456Z",
  });
  f.now = "2028-04-05T12:00:00.123456Z";
  assertEquals(evaluate(f).phase, "provisional");
});
Deno.test("scheduled, active, and awaiting proof cannot produce a result", () => {
  const f = performanceFixture();
  f.attempts = [];
  for (
    const [at, phase] of [["2026-10-01T12:00:00.123456Z", "scheduled"], [
      f.agreement.terms.starts_at,
      "active",
    ], [f.agreement.terms.deadline_at, "awaiting_proof"]]
  ) {
    f.now = at!;
    assertEquals(evaluate(f).phase, phase);
    assertEquals(evaluate(f).outcome, null);
  }
});
