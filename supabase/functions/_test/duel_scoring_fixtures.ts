/** Fictional fixtures; the agreement is the real Phase 1B local RPC capture. */
import capturedAgreement from "../../../ios/GameTime/GameTimeTests/Fixtures/duel-agreement-v1.json" with {
  type: "json",
};
import type {
  DuelOfficialRecord,
  DuelOutcome,
  DuelProofRevision,
  DuelResultNotice,
  DuelScoringDecision,
  DuelScoringInput,
} from "../_shared/duel_scoring.ts";

export const ALICE = capturedAgreement.terms.creator_id;
export const BOB = capturedAgreement.terms.invitee_id;
export const REVIEWER = "fictional-independent-reviewer";
export const AGREEMENT = capturedAgreement;

/** Hours after event end, retaining its .360255 microsecond component. */
export function at(hours: number): string {
  const ms = Date.parse(AGREEMENT.terms.event.ends_at) + hours * 3_600_000;
  return new Date(ms).toISOString().replace(".360Z", ".360255Z");
}

export function record(
  actorId: string,
  overrides: Partial<DuelOfficialRecord> = {},
): DuelOfficialRecord {
  const bib = actorId === ALICE ? "fictional-bib-11" : "fictional-bib-22";
  return {
    actorId,
    status: "finished",
    source: "fixture_official_5k_v1",
    sourceReference: "fixture://fictional-local-5k/results/revision-1",
    eventId: AGREEMENT.terms.event.id,
    course: "fixture_course_5k_v1",
    wave: "fixture_common_wave_v1",
    distanceMeters: 5000,
    timingBasis: "organizer_chip",
    precisionSeconds: 1,
    mappedBib: bib,
    publishedBib: bib,
    identityConfirmed: true,
    chipSeconds: actorId === ALICE ? 1200 : 1250,
    ...overrides,
  };
}

export function proof(overrides: Partial<DuelProofRevision> = {}): DuelProofRevision {
  return {
    revision: 1,
    supersedesRevision: null,
    recordedAt: at(1),
    reviewerId: REVIEWER,
    records: [record(ALICE), record(BOB)],
    ...overrides,
  };
}

export function notices(revision = 1, hours = 2): DuelResultNotice[] {
  return [ALICE, BOB].map((actorId) => ({
    proofRevision: revision,
    actorId,
    recordedAt: at(hours),
  }));
}

export function input(overrides: Partial<DuelScoringInput> = {}): DuelScoringInput {
  return {
    agreement: structuredClone(AGREEMENT),
    now: at(2),
    proofRevisions: [proof()],
    notices: notices(),
    reviews: [],
    closure: null,
    finalResult: null,
    ...overrides,
  };
}

interface Fixture {
  readonly name: string;
  readonly input: DuelScoringInput;
  readonly phase: DuelScoringDecision["phase"];
  readonly outcome: DuelOutcome | null;
  readonly proofRevision?: number;
}

const win: DuelOutcome = { kind: "winner", winnerId: ALICE, reason: "faster_chip" };
const fixtures: Fixture[] = [
  {
    name: "accepted pair before start",
    input: input({
      now: at(-3),
      proofRevisions: [],
      notices: [],
    }),
    phase: "scheduled",
    outcome: null,
  },
  {
    name: "exact start opens event",
    input: input({ now: AGREEMENT.terms.event.starts_at, proofRevisions: [], notices: [] }),
    phase: "active",
    outcome: null,
  },
  {
    name: "exact end waits for proof",
    input: input({ now: at(0), proofRevisions: [], notices: [] }),
    phase: "awaiting_proof",
    outcome: null,
  },
  { name: "lower whole-second chip time", input: input(), phase: "provisional", outcome: win },
  {
    name: "equal published seconds tie",
    input: input({
      proofRevisions: [proof({
        records: [record(ALICE), record(BOB, { chipSeconds: 1200 })],
      })],
    }),
    phase: "provisional",
    outcome: { kind: "tie", reason: "equal_chip_seconds" },
  },
  {
    name: "one second wins without rounding",
    input: input({
      proofRevisions: [proof({
        records: [record(ALICE, { chipSeconds: 1249 }), record(BOB)],
      })],
    }),
    phase: "provisional",
    outcome: win,
  },
  {
    name: "no durable notice cannot finalize",
    input: input({ now: at(500), notices: [] }),
    phase: "provisional",
    outcome: win,
  },
  {
    name: "one notice cannot finalize",
    input: input({ now: at(500), notices: notices().slice(0, 1) }),
    phase: "provisional",
    outcome: win,
  },
  {
    name: "later participant notice anchors both windows",
    input: input({ now: at(170), notices: [notices()[0]!, notices(1, 3)[1]!] }),
    phase: "provisional",
    outcome: win,
  },
  {
    name: "one microsecond before dispute cutoff",
    input: input({ now: at(170).replace("255Z", "254Z") }),
    phase: "provisional",
    outcome: win,
  },
  {
    name: "dispute cutoff equality permits finalization",
    input: input({ now: at(170) }),
    phase: "ready_to_finalize",
    outcome: win,
  },
  {
    name: "missing notices reach hard finality cap",
    input: input({ now: at(720), notices: [] }),
    phase: "ready_to_finalize",
    outcome: { kind: "void", reason: "finality_timeout" },
  },
  {
    name: "settled review window survives delayed worker",
    input: input({ now: at(720) }),
    phase: "ready_to_finalize",
    outcome: win,
  },
  {
    name: "no records before cutoff",
    input: input({ now: at(72).replace("255Z", "254Z"), proofRevisions: [], notices: [] }),
    phase: "awaiting_proof",
    outcome: null,
  },
  {
    name: "no records at exact cutoff become void candidate",
    input: input({ now: at(72), proofRevisions: [], notices: notices(0, 72) }),
    phase: "provisional",
    outcome: { kind: "void", reason: "unresolved_proof" },
    proofRevision: 0,
  },
  {
    name: "no records finalizes only after review window",
    input: input({ now: at(240), proofRevisions: [], notices: notices(0, 72) }),
    phase: "ready_to_finalize",
    outcome: { kind: "void", reason: "unresolved_proof" },
    proofRevision: 0,
  },
  {
    name: "initial result at cutoff is too late",
    input: input({ now: at(72), proofRevisions: [proof({ recordedAt: at(72) })], notices: [] }),
    phase: "provisional",
    outcome: { kind: "void", reason: "unresolved_proof" },
    proofRevision: 0,
  },
  {
    name: "initial result one microsecond before cutoff counts",
    input: input({
      now: at(72),
      proofRevisions: [proof({ recordedAt: at(72).replace("255Z", "254Z") })],
      notices: notices(1, 72),
    }),
    phase: "provisional",
    outcome: win,
  },
];

for (const status of ["dns", "dnf", "disqualified"] as const) {
  for (const actor of [ALICE, BOB]) {
    fixtures.push({
      name: `${status} independently confirmed for ${actor === ALICE ? "creator" : "invitee"}`,
      input: input({
        proofRevisions: [proof({
          records: [ALICE, BOB].map((id) =>
            record(id, id === actor ? { status, chipSeconds: null } : {})
          ),
        })],
      }),
      phase: "provisional",
      outcome: { kind: "winner", winnerId: actor === ALICE ? BOB : ALICE, reason: "only_finisher" },
    });
  }
  for (const other of ["dns", "dnf", "disqualified"] as const) {
    fixtures.push({
      name: `both nonfinish ${status}/${other}`,
      input: input({
        proofRevisions: [proof({
          records: [
            record(ALICE, { status, chipSeconds: null }),
            record(BOB, { status: other, chipSeconds: null }),
          ],
        })],
      }),
      phase: "provisional",
      outcome: { kind: "void", reason: "both_nonfinish" },
    });
  }
}

const unresolved: [string, Partial<DuelOfficialRecord>][] = [
  ["missing organizer entry", { status: "missing", chipSeconds: null }],
  ["ambiguous organizer identity", { status: "ambiguous", chipSeconds: null }],
  ["wrong bib", { publishedBib: "fictional-wrong-bib" }],
  ["unconfirmed identity", { identityConfirmed: false }],
  ["missing bib mapping", { mappedBib: null }],
  ["duplicate bib for the pair", {
    mappedBib: "fictional-bib-11",
    publishedBib: "fictional-bib-11",
  }],
  ["wrong event", { eventId: "fictional-other-event" }],
  ["disputed course", { course: "fictional-other-course" }],
  ["wrong wave", { wave: "fictional-other-wave" }],
  ["wrong distance", { distanceMeters: 4999 }],
  ["gun time cannot replace chip time", { timingBasis: "organizer_gun" }],
  ["Garmin cannot replace official source", { source: "garmin" }],
  ["organizer pilot policy has no adapter", { source: "organizer_chip_5k_v1" }],
  ["missing source reference", { sourceReference: null }],
  ["different published precision", { precisionSeconds: 0.1 }],
  ["fractional chip time is not rounded", { chipSeconds: 1199.9 }],
  ["zero chip time", { chipSeconds: 0 }],
  ["negative chip time", { chipSeconds: -100 }],
  ["time exceeds event window", { chipSeconds: 7201 }],
  ["nonfinish with conflicting time", { status: "dnf", chipSeconds: 1250 }],
];
for (const [name, fields] of unresolved) {
  for (const hours of [2, 72]) {
    fixtures.push({
      name: `${name} ${hours === 2 ? "awaits proof" : "never becomes a loss"}`,
      input: input({
        now: at(hours),
        proofRevisions: [proof({ records: [record(ALICE), record(BOB, fields)] })],
        notices: hours === 2 ? [] : notices(1, 72),
      }),
      phase: hours === 2 ? "awaiting_proof" : "provisional",
      outcome: hours === 2 ? null : { kind: "void", reason: "unresolved_proof" },
    });
  }
}

const correction = proof({
  revision: 2,
  supersedesRevision: 1,
  recordedAt: at(100),
  records: [record(ALICE, { chipSeconds: 1300 }), record(BOB)],
});
const correctedWin: DuelOutcome = { kind: "winner", winnerId: BOB, reason: "faster_chip" };
fixtures.push(
  {
    name: "correction after proof cutoff changes provisional result",
    input: input({
      now: at(101),
      proofRevisions: [proof(), correction],
      notices: [...notices(), ...notices(2, 101)],
    }),
    phase: "provisional",
    outcome: correctedWin,
    proofRevision: 2,
  },
  {
    name: "old notices do not finalize corrected result",
    input: input({ now: at(500), proofRevisions: [proof(), correction] }),
    phase: "provisional",
    outcome: correctedWin,
    proofRevision: 2,
  },
  {
    name: "correction grants seven full days",
    input: input({
      now: at(268),
      proofRevisions: [proof(), correction],
      notices: [...notices(), ...notices(2, 101)],
    }),
    phase: "provisional",
    outcome: correctedWin,
    proofRevision: 2,
  },
  {
    name: "corrected deadline permits finalization",
    input: input({
      now: at(269),
      proofRevisions: [proof(), correction],
      notices: [...notices(), ...notices(2, 101)],
    }),
    phase: "ready_to_finalize",
    outcome: correctedWin,
    proofRevision: 2,
  },
  {
    name: "late correction cannot shorten seven days to fit cap",
    input: input({
      now: at(720),
      proofRevisions: [proof(), { ...correction, recordedAt: at(600) }],
      notices: [...notices(), ...notices(2, 601)],
    }),
    phase: "ready_to_finalize",
    outcome: { kind: "void", reason: "finality_timeout" },
    proofRevision: 2,
  },
  {
    name: "correction received at cap requires support and preserves earlier result",
    input: input({
      now: at(720),
      proofRevisions: [proof(), { ...correction, recordedAt: at(720) }],
    }),
    phase: "ready_to_finalize",
    outcome: win,
    proofRevision: 1,
  },
  {
    name: "invalid correction does not fall back to old valid proof",
    input: input({
      now: at(101),
      proofRevisions: [proof(), {
        ...correction,
        records: [record(ALICE), record(BOB, { identityConfirmed: false })],
      }],
      notices: [...notices(), ...notices(2, 101)],
    }),
    phase: "provisional",
    outcome: { kind: "void", reason: "unresolved_proof" },
    proofRevision: 2,
  },
);

const review = {
  id: "fictional-case-1",
  proofRevision: 1,
  filedBy: BOB,
  filedAt: at(169),
  resolution: null,
};
fixtures.push(
  {
    name: "timely case pauses finalization",
    input: input({ now: at(170), reviews: [review] }),
    phase: "provisional",
    outcome: win,
  },
  {
    name: "review still open one microsecond before timeout",
    input: input({ now: at(337).replace("255Z", "254Z"), reviews: [review] }),
    phase: "provisional",
    outcome: win,
  },
  {
    name: "review timeout at equality voids",
    input: input({ now: at(337), reviews: [review] }),
    phase: "ready_to_finalize",
    outcome: { kind: "void", reason: "review_timeout" },
  },
  {
    name: "early resolution still waits for filing deadline",
    input: input({
      now: at(100),
      reviews: [
        {
          ...review,
          filedAt: at(3),
          resolution: { reviewerId: REVIEWER, decidedAt: at(4), decision: "uphold" },
        },
      ],
    }),
    phase: "provisional",
    outcome: win,
  },
  {
    name: "resolved case permits finalization after filing deadline",
    input: input({
      now: at(170),
      reviews: [
        {
          ...review,
          resolution: { reviewerId: REVIEWER, decidedAt: at(169.5), decision: "uphold" },
        },
      ],
    }),
    phase: "ready_to_finalize",
    outcome: win,
  },
  {
    name: "review void has no winner",
    input: input({
      now: at(170),
      reviews: [
        { ...review, resolution: { reviewerId: REVIEWER, decidedAt: at(169.5), decision: "void" } },
      ],
    }),
    phase: "ready_to_finalize",
    outcome: { kind: "void", reason: "review_void" },
  },
  {
    name: "correction cannot erase open old review",
    input: input({
      now: at(280),
      proofRevisions: [proof(), { ...correction, recordedAt: at(171) }],
      notices: [...notices(), ...notices(2, 172)],
      reviews: [review],
    }),
    phase: "provisional",
    outcome: correctedWin,
    proofRevision: 2,
  },
);

for (const kind of ["injury", "event_cancelled", "account_deleted"] as const) {
  fixtures.push({
    name: `${kind} ends simulated play without a loss`,
    input: input({
      closure: {
        kind,
        actorId: kind === "event_cancelled" ? null : ALICE,
        recordedAt: at(1),
      },
    }),
    phase: "ready_to_finalize",
    outcome: { kind: "void", reason: kind },
  });
}
for (const actorId of [ALICE, BOB]) {
  fixtures.push(
    {
      name: `${actorId} withdraws before start`,
      input: input({
        now: at(-3),
        proofRevisions: [],
        notices: [],
        closure: { kind: "withdrawal", actorId, recordedAt: at(-3) },
      }),
      phase: "ready_to_finalize",
      outcome: { kind: "void", reason: "prestart_withdrawal" },
    },
    {
      name: `${actorId} withdraws at start`,
      input: input({
        now: AGREEMENT.terms.event.starts_at,
        proofRevisions: [],
        notices: [],
        closure: { kind: "withdrawal", actorId, recordedAt: AGREEMENT.terms.event.starts_at },
      }),
      phase: "ready_to_finalize",
      outcome: { kind: "withdrawn_no_contest", reason: "participant_withdrew" },
    },
  );
}

export const DUEL_SCORING_FIXTURES: readonly Fixture[] = fixtures;
