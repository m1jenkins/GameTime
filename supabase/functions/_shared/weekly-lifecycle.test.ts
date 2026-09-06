import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { WEEKLY_STEPS_POLICY_V1, weeklyStepsConsentBinding } from "./weekly-steps.ts";
import {
  evaluateWeeklyLifecycle,
  runWeeklyLifecycle,
  type WeeklyLifecycleDatabase,
  type WeeklyLifecycleInput,
} from "./weekly-lifecycle.ts";

function fixture(): WeeklyLifecycleInput {
  const days = Array.from({ length: 7 }, (_, i) => ({
    date: `2026-09-${String(7 + i).padStart(2, "0")}`,
    startsAt: `2026-09-${String(7 + i).padStart(2, "0")}T05:00:00Z`,
    endsAt: `2026-09-${String(8 + i).padStart(2, "0")}T05:00:00Z`,
  }));
  const terms = {
    agreementVersion: 1 as const,
    policy: WEEKLY_STEPS_POLICY_V1,
    creatorId: "alice",
    createdAt: "2026-09-01T10:00:00Z",
    timezone: "America/Chicago",
    startsAt: "2026-09-07T05:00:00Z",
    endsAt: "2026-09-14T05:00:00Z",
    uploadClosesAt: "2026-09-15T05:00:00Z",
    correctionsCloseAt: "2026-09-16T05:00:00Z",
    lifecycle: {
      noticeBy: "2026-09-17T05:00:00Z",
      filingWindowHours: 48 as const,
      resolutionWindowHours: 72 as const,
      finalityBy: "2026-09-23T05:00:00Z",
      simulationEntryCents: 2000 as const,
      feeCents: 0 as const,
      exitPolicy: "void_friend_refund_community_v1" as const,
      retentionPolicy: "private_fictional_receipts_v1" as const,
    },
    days,
    participants: ["alice", "bob"].map((participantId) => ({ participantId, targetSteps: 7000 })),
  };
  return {
    agreement: { id: "fixture", termsDigest: "a".repeat(64), terms },
    mode: "friend",
    version: 1,
    status: "scheduled",
    joinBy: "2026-09-07T04:00:00Z",
    capacity: 2,
    now: "2026-09-16T05:00:00.000001Z",
    participants: terms.participants.map((p) => ({
      actor_id: p.participantId,
      target_steps: p.targetSteps,
      accepted_at: "2026-09-01T11:00:00Z",
      exited_at: null,
    })),
    consents: terms.participants.map((p) => ({
      agreementId: "fixture",
      participantId: p.participantId,
      termsDigest: "a".repeat(64),
      policyVersion: WEEKLY_STEPS_POLICY_V1.version,
      termsBinding: weeklyStepsConsentBinding(terms),
      acceptedAt: "2026-09-01T11:00:00Z",
    })),
    revisions: terms.participants.flatMap((p) =>
      days.map((d) => ({
        agreementId: "fixture",
        participantId: p.participantId,
        termsDigest: "a".repeat(64),
        policyVersion: WEEKLY_STEPS_POLICY_V1.version,
        sourceVersion: WEEKLY_STEPS_POLICY_V1.source,
        date: d.date,
        revision: 1,
        previousRevision: null,
        receivedAt: "2026-09-15T04:59:59.999999Z",
        status: "complete" as const,
        steps: p.participantId === "alice" ? 1000 : 0,
      }))
    ),
    notices: [],
    cases: [],
    exits: [],
    result: null,
  };
}
function notice(input: WeeklyLifecycleInput) {
  const decision = evaluateWeeklyLifecycle(input);
  input.notices = [{
    revision: 1,
    source_count: input.revisions.length,
    recorded_at: input.now,
    file_by: "2026-09-18T05:00:00.000001Z",
    resolve_by: "2026-09-21T05:00:00.000001Z",
    qualifications: decision.qualifications,
  }];
}
Deno.test("provisional qualification is distinct from saved/final result", () => {
  const input = fixture();
  assertEquals(evaluateWeeklyLifecycle(input).phase, "notice");
  assertEquals(evaluateWeeklyLifecycle(input).qualifications.map((x) => x.qualification), [
    "met",
    "confirmed_miss",
  ]);
  notice(input);
  assertEquals(evaluateWeeklyLifecycle(input).phase, "review");
});
for (
  const [now, expected] of [
    ["2026-09-18T05:00:00.000000Z", "review"],
    ["2026-09-18T05:00:00.000001Z", "final"],
  ] as const
) {
  Deno.test(`filing boundary retains microsecond ${now}`, () => {
    const input = fixture();
    notice(input);
    input.now = now;
    assertEquals(evaluateWeeklyLifecycle(input).phase, expected);
  });
}
for (
  const [now, expected] of [
    ["2026-09-21T05:00:00.000000Z", "review"],
    ["2026-09-21T05:00:00.000001Z", "final"],
  ] as const
) {
  Deno.test(`unresolved independent review full window ${now}`, () => {
    const input = fixture();
    notice(input);
    input.cases = [{ id: "case", actor_id: "bob", notice_revision: 1, resolution: null }];
    input.now = now;
    const value = evaluateWeeklyLifecycle(input);
    assertEquals(value.phase, expected);
    if (expected === "final") {
      assertEquals(value.qualifications.map((q) => q.qualification), ["refund", "refund"]);
    }
  });
}
Deno.test("independently upheld review does not shorten filing window", () => {
  const input = fixture();
  notice(input);
  input.cases = [{
    id: "case",
    actor_id: "bob",
    notice_revision: 1,
    resolution: { decision: "upheld", recorded_at: input.now },
  }];
  assertEquals(evaluateWeeklyLifecycle(input).phase, "review");
  input.now = input.notices[0]!.file_by;
  assertEquals(evaluateWeeklyLifecycle(input).qualifications.map((q) => q.qualification), [
    "met",
    "confirmed_miss",
  ]);
});
Deno.test("delayed missing notice never shortens full review window", () => {
  const input = fixture();
  input.now = "2026-09-17T05:00:00.000001Z";
  assertEquals(evaluateWeeklyLifecycle(input).qualifications.map((q) => q.qualification), [
    "refund",
    "refund",
  ]);
  assertEquals(evaluateWeeklyLifecycle(input).reason, "notice_window_unavailable");
});
for (const kind of ["injury", "withdrawal", "account_deleted", "decline"]) {
  Deno.test(`${kind} friend exit is safe even before source observations`, () => {
    const input = fixture();
    input.revisions = [];
    input.now = "2026-09-08T05:00:00Z";
    input.exits = [{ actor_id: "alice", kind, recorded_at: input.now }];
    assertEquals(evaluateWeeklyLifecycle(input).qualifications.map((q) => q.qualification), [
      "refund",
      "refund",
    ]);
  });
}
Deno.test("missing consent never invents a second stake or confirmed miss", () => {
  const input = fixture();
  input.participants[1]!.accepted_at = null;
  input.consents.pop();
  const decision = evaluateWeeklyLifecycle(input);
  assertEquals(decision.qualifications, [{ participantId: "alice", qualification: "refund" }]);
});
Deno.test("final result remains authoritative after source correction", () => {
  const input = fixture();
  input.result = {
    qualifications: [{ participantId: "alice", qualification: "refund" }, {
      participantId: "bob",
      qualification: "refund",
    }],
    reason: "support_review",
    recorded_at: input.now,
  };
  input.revisions = [];
  assertEquals(evaluateWeeklyLifecycle(input).qualifications, input.result.qualifications);
});
Deno.test("post-notice downward correction requests fresh complete review", () => {
  const input = fixture();
  notice(input);
  input.revisions.push({
    ...input.revisions[0]!,
    revision: 2,
    previousRevision: 1,
    steps: 0,
    receivedAt: "2026-09-16T04:59:59.999999Z",
  });
  const value = evaluateWeeklyLifecycle(input);
  assertEquals(value.phase, "notice");
  assertEquals(value.qualifications[0]?.qualification, "confirmed_miss");
});
Deno.test("community per-person target override cannot reuse consent", () => {
  const input = fixture();
  input.mode = "community";
  assertThrows(() => evaluateWeeklyLifecycle(input), Error, "community_contract_mismatch");
});
Deno.test("bounded optimistic retries settle only after successful final commit", async () => {
  const input = fixture();
  input.result = { qualifications: [], reason: "saved", recorded_at: input.now };
  let loads = 0;
  let commits = 0;
  let settles = 0;
  const db: WeeklyLifecycleDatabase = {
    load: () => {
      loads++;
      return Promise.resolve(input);
    },
    commit: () => Promise.resolve(++commits < 3 ? "stale" : "final"),
    settle: () => {
      settles++;
      return Promise.resolve(null);
    },
  };
  assertEquals(await runWeeklyLifecycle(db, "fixture"), "final");
  assertEquals([loads, commits, settles], [3, 3, 1]);
});
Deno.test("persistent contention stops at bounded retry without allocation", async () => {
  let count = 0;
  const db: WeeklyLifecycleDatabase = {
    load: () => Promise.resolve(fixture()),
    commit: () => {
      count++;
      return Promise.resolve("stale");
    },
    settle: () => {
      throw new Error("must not settle");
    },
  };
  assertEquals(await runWeeklyLifecycle(db, "fixture"), "stale");
  assertEquals(count, 4);
});
Deno.test("final commit survives interrupted allocation and retry resumes once", async () => {
  const input = fixture();
  input.result = { qualifications: [], reason: "saved", recorded_at: input.now };
  let settles = 0;
  const db: WeeklyLifecycleDatabase = {
    load: () => Promise.resolve(input),
    commit: () => Promise.resolve("final"),
    settle: () => {
      if (++settles === 1) throw new Error("interrupted");
      return Promise.resolve(null);
    },
  };
  await assertRejects(() => runWeeklyLifecycle(db, "fixture"), Error, "interrupted");
  assertEquals(await runWeeklyLifecycle(db, "fixture"), "final");
  assertEquals(settles, 2);
});
