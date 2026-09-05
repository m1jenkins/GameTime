import { assert, assertEquals, assertThrows } from "@std/assert";
import {
  DUEL_POLICY_V1,
  DUEL_SCORING_VERSION,
  type DuelFinalResult,
  type DuelOutcome,
  DuelScoringError,
  type DuelScoringInput,
  evaluateDuel,
} from "./duel_scoring.ts";
import {
  AGREEMENT,
  ALICE,
  at,
  BOB,
  DUEL_SCORING_FIXTURES,
  input,
  notices,
  proof,
  record,
  REVIEWER,
} from "../_test/duel_scoring_fixtures.ts";

for (const fixture of DUEL_SCORING_FIXTURES) {
  Deno.test(`duel: ${fixture.name}`, () => {
    const original = JSON.stringify(fixture.input);
    const actual = evaluateDuel(fixture.input);
    assertEquals(actual.version, DUEL_SCORING_VERSION);
    assertEquals(actual.challengeId, AGREEMENT.id);
    assertEquals(actual.termsDigest, AGREEMENT.terms_digest);
    assertEquals(actual.phase, fixture.phase);
    assertEquals(actual.outcome, fixture.outcome);
    if (fixture.proofRevision !== undefined) {
      assertEquals(actual.proofRevision, fixture.proofRevision);
    }
    assertEquals(JSON.stringify(fixture.input), original, "must not mutate the supplied ledger");
    assertEquals(
      evaluateDuel(JSON.parse(original)),
      actual,
      "fixture is portable and deterministic",
    );
  });
}

Deno.test("duel: exact frozen policy matches the captured Phase 1B RPC agreement", () => {
  assertEquals(DUEL_POLICY_V1, AGREEMENT.terms.policy);
});

Deno.test("duel: roster, proof and notice row ordering does not decide a winner", () => {
  for (const fixture of DUEL_SCORING_FIXTURES) {
    const i = fixture.input;
    assertEquals(
      evaluateDuel({
        ...i,
        agreement: { ...i.agreement, participants: [...i.agreement.participants].reverse() },
        proofRevisions: [...i.proofRevisions].reverse().map((r) => ({
          ...r,
          records: [...r.records].reverse(),
        })),
        notices: [...i.notices].reverse(),
        reviews: [...i.reviews].reverse(),
      }),
      evaluateDuel(i),
      fixture.name,
    );
  }
});

Deno.test("duel: private source reference, bib and reviewer never appear in a decision", () => {
  const decision = JSON.stringify(evaluateDuel(input()));
  for (
    const forbidden of [
      "fixture://",
      "fictional-bib",
      REVIEWER,
      "chipSeconds",
      "records",
      "sourceReference",
    ]
  ) {
    assert(!decision.includes(forbidden), forbidden);
  }
});

Deno.test("duel: deadline output retains microseconds and elapsed hours", () => {
  const result = evaluateDuel(
    input({
      now: at(170),
      reviews: [{ id: "case", filedBy: BOB, proofRevision: 1, filedAt: at(169), resolution: null }],
    }),
  );
  assertEquals(result.disputeClosesAt, at(170));
  assertEquals(result.reviewDueAt, at(337));
});

Deno.test("duel: explicit offsets represent identical instants without local calendar arithmetic", () => {
  const original = input({ now: at(170) });
  const offset = { ...original, now: "2026-09-14T00:11:18.360255-05:00" };
  assertEquals(evaluateDuel(offset), evaluateDuel(original));
});

type Mutable<T> = { -readonly [K in keyof T]: T[K] extends object ? Mutable<T[K]> : T[K] };
function bad(change: (i: Mutable<DuelScoringInput>) => void, message?: string) {
  const i = structuredClone(input()) as Mutable<DuelScoringInput>;
  change(i);
  assertThrows(() => evaluateDuel(i), DuelScoringError, message);
}

const invalid: [string, (i: Mutable<DuelScoringInput>) => void, string][] = [
  ["unknown policy", (i) => {
    i.agreement.terms.policy_version = "duel-live-v1";
  }, "unsupported_duel_policy"],
  ["live mode", (i) => {
    i.agreement.terms.policy.mode = "live";
  }, "unsupported_duel_policy"],
  ["changed stakes", (i) => {
    i.agreement.terms.policy.stake_cents_each = 5000;
  }, "unsupported_duel_policy"],
  ["nonzero fee", (i) => {
    i.agreement.terms.policy.fee_cents_each = 1;
  }, "unsupported_duel_policy"],
  ["new policy fields", (i) => {
    i.agreement.terms.policy.extra = true;
  }, "unsupported_duel_policy"],
  ["missing policy field", (i) => {
    delete i.agreement.terms.policy.winner;
  }, "unsupported_duel_policy"],
  ["self duel", (i) => {
    i.agreement.terms.invitee_id = ALICE;
  }, "invalid_duel_pair"],
  ["missing consent", (i) => {
    i.agreement.participants[1]!.accepted_at = null;
  }, "matching_consents"],
  ["different consent digest", (i) => {
    i.agreement.participants[1]!.consent_terms_digest = "a".repeat(64);
  }, "matching_consents"],
  ["different consent policy", (i) => {
    i.agreement.participants[1]!.consent_policy_version = "other";
  }, "matching_consents"],
  ["accepted at cutoff", (i) => {
    i.agreement.participants[1]!.accepted_at = i.agreement.terms.accept_by;
  }, "consent_time"],
  ["third runner", (i) => {
    i.agreement.participants.push({ ...i.agreement.participants[0]! });
  }, "invalid_duel_roster"],
  ["duplicate runner", (i) => {
    i.agreement.participants[1]!.actor_id = ALICE;
  }, "invalid_duel_roster"],
  ["changed proof cutoff", (i) => {
    i.agreement.terms.results_due_at = at(73);
  }, "deadlines"],
  ["changed cap", (i) => {
    i.agreement.terms.finality_due_at = at(721);
  }, "deadlines"],
  ["self proof review by creator", (i) => {
    i.proofRevisions[0]!.reviewerId = ALICE;
  }, "independent_reviewer"],
  ["self proof review by invitee", (i) => {
    i.proofRevisions[0]!.reviewerId = BOB;
  }, "independent_reviewer"],
  ["no independent reviewer", (i) => {
    i.proofRevisions[0]!.reviewerId = "";
  }, "independent_reviewer"],
  ["future proof", (i) => {
    i.proofRevisions[0]!.recordedAt = at(3);
  }, "receipt_time"],
  ["proof before event end", (i) => {
    i.proofRevisions[0]!.recordedAt = at(-1);
  }, "receipt_time"],
  ["revision gap", (i) => {
    i.proofRevisions[0]!.revision = 2;
  }, "revision_chain"],
  ["incorrect predecessor", (i) => {
    i.proofRevisions[0]!.supersedesRevision = 1;
  }, "revision_chain"],
  ["duplicate revision", (i) => {
    i.proofRevisions.push(i.proofRevisions[0]!);
  }, "revision_chain"],
  ["omitted runner proof", (i) => {
    i.proofRevisions[0]!.records.pop();
  }, "invalid_proof_pair"],
  ["unrelated runner proof", (i) => {
    i.proofRevisions[0]!.records[1]!.actorId = "unrelated";
  }, "invalid_proof_pair"],
  ["duplicate runner proof", (i) => {
    i.proofRevisions[0]!.records[1]!.actorId = ALICE;
  }, "invalid_proof_pair"],
  ["duplicate notice", (i) => {
    i.notices.push(i.notices[0]!);
  }, "duplicate_result_notice"],
  ["unrelated notice recipient", (i) => {
    i.notices[0]!.actorId = "unrelated";
  }, "invalid_result_notice"],
  ["notice for missing revision", (i) => {
    i.notices[0]!.proofRevision = 2;
  }, "invalid_result_notice"],
  ["notice before proof", (i) => {
    i.notices[0]!.recordedAt = at(0);
  }, "notice_time"],
  ["future notice", (i) => {
    i.notices[0]!.recordedAt = at(3);
  }, "notice_time"],
  ["missing ledger", (i) => {
    i.reviews = undefined as unknown as [];
  }, "complete_duel_snapshot"],
  ["unrelated withdrawal", (i) => {
    i.closure = { kind: "withdrawal", actorId: "unrelated", recordedAt: at(1) };
  }, "closure"],
  ["future withdrawal", (i) => {
    i.closure = { kind: "withdrawal", actorId: ALICE, recordedAt: at(3) };
  }, "closure_time"],
];
for (const [name, change, reason] of invalid) {
  Deno.test(`duel: rejects ${name}`, () => bad(change, reason));
}

for (
  const now of [
    "2026-09-07",
    "2026-09-07T12:00:00",
    "2026-02-30T00:00:00Z",
    "2026-09-07T24:00:00Z",
    "2026-09-07T12:00:00+01:60",
    "2026-09-07T12:00:00.1234567Z",
    "infinity",
  ]
) {
  Deno.test(`duel: rejects ambiguous or invalid instant ${now}`, () =>
    bad((i) => {
      i.now = now;
    }, "instant"));
}

for (
  const chipSeconds of [NaN, Infinity, Number.MAX_SAFE_INTEGER + 1, "1200" as unknown as number]
) {
  Deno.test(`duel: malformed time ${chipSeconds} never selects a winner`, () => {
    assertEquals(
      evaluateDuel(input({
        proofRevisions: [proof({
          records: [record(ALICE), record(BOB, { chipSeconds })],
        })],
        notices: [],
      })).outcome,
      null,
    );
  });
}

Deno.test("duel: filing at equality or after deadline is rejected", () => {
  for (const filedAt of [at(170), at(170).replace("255Z", "256Z")]) {
    assertThrows(
      () =>
        evaluateDuel(
          input({
            now: at(171),
            reviews: [{ id: "case", proofRevision: 1, filedBy: BOB, filedAt, resolution: null }],
          }),
        ),
      DuelScoringError,
      "filing_window",
    );
  }
});

Deno.test("duel: self resolution and resolution at timeout are rejected", () => {
  for (
    const [reviewerId, decidedAt] of [[ALICE, at(4)], [BOB, at(4)], [REVIEWER, at(171)]] as const
  ) {
    assertThrows(
      () =>
        evaluateDuel(
          input({
            now: at(171),
            reviews: [{
              id: "case",
              proofRevision: 1,
              filedBy: BOB,
              filedAt: at(3),
              resolution: { reviewerId, decidedAt, decision: "uphold" },
            }],
          }),
        ),
      DuelScoringError,
    );
  }
});

Deno.test("duel: every unresolved case must finish; closing one does not clear another", () => {
  const result = evaluateDuel(input({
    now: at(170),
    reviews: [
      {
        id: "closed",
        proofRevision: 1,
        filedBy: ALICE,
        filedAt: at(3),
        resolution: { reviewerId: REVIEWER, decidedAt: at(4), decision: "uphold" },
      },
      { id: "open", proofRevision: 1, filedBy: BOB, filedAt: at(169), resolution: null },
    ],
  }));
  assertEquals(result.phase, "provisional");
  assertEquals(result.reviewDueAt, at(337));
});

Deno.test("duel: review may be filed after own notice while the other notice is pending", () => {
  const result = evaluateDuel(input({
    now: at(500),
    notices: notices().slice(0, 1),
    reviews: [
      { id: "case", proofRevision: 1, filedBy: ALICE, filedAt: at(200), resolution: null },
    ],
  }));
  assertEquals(result.phase, "provisional");
  assertEquals(result.outcome, { kind: "void", reason: "review_timeout" });
});

Deno.test("duel: cap never truncates a corrected result's dispute window", () => {
  for (const hours of [552, 552 + 1 / 3600, 719]) {
    const i = input({
      now: at(720),
      proofRevisions: [
        proof(),
        proof({
          revision: 2,
          supersedesRevision: 1,
          recordedAt: at(hours),
          records: [record(ALICE), record(BOB, { chipSeconds: 1100 })],
        }),
      ],
      notices: [...notices(), ...notices(2, hours)],
    });
    assertEquals(
      evaluateDuel(i).outcome,
      hours === 552
        ? { kind: "winner", winnerId: BOB, reason: "faster_chip" }
        : { kind: "void", reason: "finality_timeout" },
    );
  }
});

Deno.test("duel: late initial proof and cap-time corrections request support", () => {
  assertEquals(
    evaluateDuel(
      input({ now: at(72), notices: [], proofRevisions: [proof({ recordedAt: at(72) })] }),
    ).supportCorrectionRequired,
    true,
  );
  assertEquals(
    evaluateDuel(
      input({
        now: at(720),
        proofRevisions: [
          proof(),
          proof({ revision: 2, supersedesRevision: 1, recordedAt: at(720) }),
        ],
      }),
    ).supportCorrectionRequired,
    true,
  );
});

Deno.test("duel: finalized result survives later correction, injury and withdrawal", () => {
  const finalResult: DuelFinalResult = {
    version: DUEL_SCORING_VERSION,
    challengeId: AGREEMENT.id,
    termsDigest: AGREEMENT.terms_digest,
    proofRevision: 1,
    finalizedAt: at(170),
    outcome: { kind: "winner", winnerId: ALICE, reason: "faster_chip" } as const,
  };
  for (const kind of ["withdrawal", "injury", "account_deleted"] as const) {
    const i = input({
      now: at(300),
      finalResult,
      closure: { kind, actorId: ALICE, recordedAt: at(290) },
      proofRevisions: [
        proof(),
        proof({
          revision: 2,
          supersedesRevision: 1,
          recordedAt: at(280),
          records: [record(ALICE), record(BOB, { chipSeconds: 1100 })],
        }),
      ],
    });
    assertEquals(evaluateDuel(i).phase, "final");
    assertEquals(evaluateDuel(i).outcome, finalResult.outcome);
    assertEquals(evaluateDuel(i).proofRevision, 1);
    assertEquals(evaluateDuel(i).supportCorrectionRequired, true);
    assertThrows(
      () => evaluateDuel({ ...i, finalResult: { ...finalResult, challengeId: "other" } }),
      DuelScoringError,
    );
    assertThrows(
      () => evaluateDuel({ ...i, finalResult: { ...finalResult, termsDigest: "a".repeat(64) } }),
      DuelScoringError,
    );
  }
});

Deno.test("duel: persisted final outcomes are validated and projected without private extras", () => {
  const finalResult: DuelFinalResult = {
    version: DUEL_SCORING_VERSION,
    challengeId: AGREEMENT.id,
    termsDigest: AGREEMENT.terms_digest,
    proofRevision: 1,
    finalizedAt: at(170),
    outcome: {
      kind: "tie",
      reason: "equal_chip_seconds",
      sourceReference: "private",
    } as DuelOutcome,
  };
  assertEquals(evaluateDuel(input({ now: at(200), finalResult })).outcome, {
    kind: "tie",
    reason: "equal_chip_seconds",
  });
  for (
    const outcome of [null, { kind: "live_payout", reason: "anything" }, {
      kind: "winner",
      winnerId: "unrelated",
      reason: "faster_chip",
    }, { kind: "void", reason: "both_donate" }]
  ) {
    assertThrows(
      () =>
        evaluateDuel(input({
          now: at(200),
          finalResult: {
            ...finalResult,
            outcome: outcome as DuelOutcome,
          },
        })),
      DuelScoringError,
      "invalid_final_outcome",
    );
  }
});

Deno.test("duel: late withdrawal cannot bypass finality while a worker is delayed", () => {
  for (const hours of [720, 721]) {
    assertEquals(
      evaluateDuel(input({
        now: at(722),
        closure: {
          kind: "withdrawal",
          actorId: BOB,
          recordedAt: at(hours),
        },
      })).outcome,
      { kind: "winner", winnerId: ALICE, reason: "faster_chip" },
    );
  }
});

Deno.test("duel: no-proof result remains the same when a worker runs after the cap", () => {
  assertEquals(
    evaluateDuel(input({ now: at(800), proofRevisions: [], notices: notices(0, 72) })).outcome,
    { kind: "void", reason: "unresolved_proof" },
  );
});

Deno.test("duel: missing proof against a nonfinish, or both missing, is never a loss", () => {
  for (const status of ["dns", "dnf", "disqualified", "missing"] as const) {
    assertEquals(
      evaluateDuel(input({
        now: at(72),
        notices: notices(1, 72),
        proofRevisions: [proof({
          records: [
            record(ALICE, { status, chipSeconds: null }),
            record(BOB, { status: "missing", chipSeconds: null }),
          ],
        })],
      })).outcome,
      { kind: "void", reason: "unresolved_proof" },
    );
  }
});

Deno.test("duel: a correction chain cannot admit late initial proof", () => {
  const actual = evaluateDuel(input({
    now: at(101),
    notices: notices(0, 72),
    proofRevisions: [
      proof({ recordedAt: at(73) }),
      proof({ revision: 2, supersedesRevision: 1, recordedAt: at(100) }),
    ],
  }));
  assertEquals(actual.outcome, { kind: "void", reason: "unresolved_proof" });
  assertEquals(actual.proofRevision, 0);
  assertEquals(actual.supportCorrectionRequired, true);
});

Deno.test("duel: old notice cannot be created after a correction", () => {
  assertThrows(
    () =>
      evaluateDuel(
        input({
          now: at(102),
          proofRevisions: [
            proof(),
            proof({ revision: 2, supersedesRevision: 1, recordedAt: at(100) }),
          ],
          notices: notices(1, 101),
        }),
      ),
    DuelScoringError,
    "notice_time",
  );
});

Deno.test("duel: unresolved earlier review timeout survives a correction", () => {
  const actual = evaluateDuel(
    input({
      now: at(400),
      proofRevisions: [proof(), proof({ revision: 2, supersedesRevision: 1, recordedAt: at(171) })],
      notices: [...notices(), ...notices(2, 172)],
      reviews: [{
        id: "old-case",
        proofRevision: 1,
        filedBy: BOB,
        filedAt: at(169),
        resolution: null,
      }],
    }),
  );
  assertEquals(actual.phase, "ready_to_finalize");
  assertEquals(actual.outcome, { kind: "void", reason: "review_timeout" });
});

Deno.test("duel: calendar DST and leap day do not change elapsed review windows", () => {
  // Shift the entire fixture to straddle Chicago's spring/fall changes and leap day.
  for (
    const end of [
      "2026-10-31T03:11:18.360255Z",
      "2026-03-07T03:11:18.360255Z",
      "2028-02-28T03:11:18.360255Z",
    ]
  ) {
    const delta = Date.parse(end) - Date.parse(AGREEMENT.terms.event.ends_at);
    const shifted = JSON.parse(JSON.stringify(input({ now: at(170) })), (_key, value) => {
      if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T/.test(value)) return value;
      const fraction = value.split(".")[1]!.slice(0, 6);
      return new Date(Date.parse(value) + delta).toISOString().slice(0, 19) + `.${fraction}Z`;
    }) as DuelScoringInput;
    const actual = evaluateDuel(shifted);
    assertEquals(actual.phase, "ready_to_finalize");
    assertEquals(actual.disputeClosesAt, shifted.now);
    assertEquals(actual.outcome, { kind: "winner", winnerId: ALICE, reason: "faster_chip" });
  }
});
