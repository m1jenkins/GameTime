import { assert, assertEquals, assertThrows } from "@std/assert";
import {
  evaluateWeeklyParticipant,
  evaluateWeeklySteps,
  WEEKLY_STEPS_POLICY_V1,
  WEEKLY_STEPS_POLICY_VERSION,
  WEEKLY_STEPS_SOURCE_VERSION,
  WEEKLY_STEPS_VERSION,
  type WeeklyParticipantInput,
  weeklyStepsConsentBinding,
  WeeklyStepsError,
  type WeeklyStepsInput,
  type WeeklyStepsRevision,
  type WeeklyStepsTerms,
} from "./weekly-steps.ts";

type Mutable<T> = { -readonly [K in keyof T]: T[K] extends object ? Mutable<T[K]> : T[K] };
type Input = Mutable<WeeklyStepsInput>;

function at(value: string, hours = 0, microseconds = 0): string {
  const ms = Date.parse(value) + hours * 3_600_000;
  return new Date(ms).toISOString().slice(0, 19) + `.${String(microseconds).padStart(6, "0")}Z`;
}

function fixture(count = 2, firstDate = "2026-09-07", offsets = [5, 5, 5, 5, 5, 5, 5, 5]): Input {
  const base = Date.parse(`${firstDate}T00:00:00Z`);
  const dates = Array.from(
    { length: 8 },
    (_, i) => new Date(base + i * 86_400_000).toISOString().slice(0, 10),
  );
  const starts = dates.map((date, i) =>
    `${date}T${String(offsets[i]).padStart(2, "0")}:00:00.000000Z`
  );
  const terms: WeeklyStepsTerms = {
    agreementVersion: 1,
    policy: { ...WEEKLY_STEPS_POLICY_V1 },
    creatorId: "alice",
    createdAt: at(starts[0]!, -24, 360255),
    timezone: "America/Chicago",
    startsAt: starts[0]!,
    endsAt: starts[7]!,
    uploadClosesAt: at(starts[7]!, 24),
    correctionsCloseAt: at(starts[7]!, 48),
    lifecycle: {
      noticeBy: at(starts[7]!, 72),
      filingWindowHours: 48,
      resolutionWindowHours: 72,
      finalityBy: at(starts[7]!, 216),
      simulationEntryCents: 2000,
      feeCents: 0,
      exitPolicy: "void_friend_refund_community_v1",
      retentionPolicy: "private_fictional_receipts_v1",
    },
    days: dates.slice(0, 7).map((date, i) => ({
      date,
      startsAt: starts[i]!,
      endsAt: starts[i + 1]!,
    })),
    participants: ["alice", "bob", "charlie", "dana", "erin", "frank"].slice(0, count)
      .map((participantId, i) => ({ participantId, targetSteps: 7000 + i * 700 })),
  };
  const agreement = { id: "weekly-fixture", termsDigest: "a".repeat(64), terms };
  return {
    agreement,
    consents: terms.participants.map((p) => ({
      agreementId: agreement.id,
      participantId: p.participantId,
      termsDigest: agreement.termsDigest,
      policyVersion: WEEKLY_STEPS_POLICY_VERSION,
      termsBinding: weeklyStepsConsentBinding(terms),
      acceptedAt: at(terms.startsAt, -1, 360255),
    })),
    revisions: [],
    now: terms.correctionsCloseAt,
  } as unknown as Input;
}

function reconsent(i: Input) {
  for (const c of i.consents) c.termsBinding = weeklyStepsConsentBinding(i.agreement.terms);
}

function dayRevision(i: Input, participantId: string, day = 0): WeeklyStepsRevision {
  return {
    agreementId: i.agreement.id,
    participantId,
    termsDigest: i.agreement.termsDigest,
    policyVersion: WEEKLY_STEPS_POLICY_VERSION,
    sourceVersion: WEEKLY_STEPS_SOURCE_VERSION,
    date: i.agreement.terms.days[day]!.date,
    revision: 1,
    previousRevision: null,
    receivedAt: at(i.agreement.terms.days[day]!.endsAt, 0, 1),
    status: "complete",
    steps: 1000,
  };
}

function populate(i: Input, successful: readonly string[] = []): Input {
  i.revisions = i.agreement.terms.participants.flatMap((p) =>
    i.agreement.terms.days.map((_, day) => ({
      ...dayRevision(i, p.participantId, day),
      steps: successful.includes(p.participantId) ? p.targetSteps / 7 : 0,
    }))
  );
  return i;
}

function decision(i: Input) {
  const before = JSON.stringify(i);
  const result = evaluateWeeklySteps(i);
  assertEquals(JSON.stringify(i), before, "does not mutate its private input");
  assertEquals(evaluateWeeklySteps(JSON.parse(before)), result, "deterministic JSON replay");
  assertEquals(result.version, WEEKLY_STEPS_VERSION);
  assertEquals(result.final, false, "qualification is never persisted finality");
  return result;
}

for (const count of [2, 3, 4, 5]) {
  for (let successes = 0; successes < 2 ** count; successes++) {
    Deno.test(`weekly steps: ${count} participants, success set ${successes}`, () => {
      const i = fixture(count);
      const names = i.agreement.terms.participants.filter((_, n) => successes & (1 << n))
        .map((p) => p.participantId);
      const result = decision(populate(i, names));
      assertEquals(
        result.groupOutcome,
        names.length === 0 ? "none_met" : names.length === count ? "all_met" : "some_met",
      );
      for (const p of result.participants) {
        assertEquals(p.qualification, names.includes(p.participantId) ? "met" : "confirmed_miss");
        assertEquals(p.completeDayCount, 7);
      }
    });
  }
}

for (const count of [0, 1, 6]) {
  Deno.test(`weekly steps: rejects ${count} participants`, () => {
    assertThrows(
      () => evaluateWeeklySteps(fixture(count)),
      WeeklyStepsError,
      "invalid_frozen_roster",
    );
  });
}

for (const state of ["missing", "incomplete", "revoked", "query_failed"] as const) {
  for (const steps of [0, 1_000_000]) {
    Deno.test(`weekly steps: ${state} (${steps}) cannot imply a miss or confirmed success`, () => {
      const i = populate(fixture());
      const r = i.revisions[0]!;
      r.status = state;
      r.steps = state === "incomplete" ? steps : null;
      const result = decision(i);
      assertEquals(result.participants[0]!.qualification, "unresolved");
      assertEquals(result.groupOutcome, "unresolved");
      assertEquals(result.participants[0]!.observedSteps, state === "incomplete" ? steps : 0);
      assertEquals(result.participants[0]!.qualifyingSteps, 0);
    });
  }
}

Deno.test("weekly steps: absent day differs from an explicitly complete zero", () => {
  const i = populate(fixture());
  assertEquals(decision(i).participants[0]!.qualification, "confirmed_miss");
  i.revisions.shift();
  assertEquals(decision(i).participants[0]!.qualification, "unresolved");
});

Deno.test("weekly steps: proven cumulative target can be met with other incomplete dates", () => {
  const i = fixture();
  i.revisions = [{ ...dayRevision(i, "alice"), steps: 7000 }];
  assertEquals(decision(i).participants[0]!.qualification, "met");
  assertEquals(decision(i).groupOutcome, "unresolved");
});

Deno.test("weekly steps: a rest day never creates a daily-goal requirement", () => {
  const i = populate(fixture());
  i.revisions[6]!.steps = 7000;
  assertEquals(decision(i).participants[0]!.qualification, "met");
});

for (
  const [start, offsets, duration] of [
    ["2026-03-02", [6, 6, 6, 6, 6, 6, 6, 5], 167],
    ["2026-10-26", [5, 5, 5, 5, 5, 5, 5, 6], 169],
  ] as const
) {
  Deno.test(`weekly steps: DST week has ${duration} elapsed hours and seven frozen dates`, () => {
    const i = fixture(5, start, [...offsets]);
    const t = i.agreement.terms;
    assertEquals((Date.parse(t.endsAt) - Date.parse(t.startsAt)) / 3_600_000, duration);
    assertEquals(decision(populate(i)).groupOutcome, "none_met");
  });
}

Deno.test("weekly steps: explicit offset clock and travel leave the frozen week unchanged", () => {
  const i = fixture();
  const before = decision(i);
  i.now = "2026-09-15T22:00:00.000000-07:00";
  assertEquals(decision(i), before);
  i.agreement.terms.timezone = "America/Los_Angeles";
  reconsent(i);
  assertThrows(() => decision(i), WeeklyStepsError, "invalid_day_boundary");
});

Deno.test("weekly steps: boundary clock retains microseconds; no premature miss", () => {
  const i = populate(fixture());
  i.now = at(i.agreement.terms.uploadClosesAt, -1 / 3600, 999999);
  assertEquals(decision(i).participants[0]!.qualification, "pending");
  i.now = i.agreement.terms.uploadClosesAt;
  assertEquals(decision(i).participants[0]!.qualification, "confirmed_miss");
  assertEquals(decision(i).phase, "awaiting_observations");
  i.now = at(i.agreement.terms.correctionsCloseAt, -1 / 3600, 999999);
  assertEquals(decision(i).phase, "awaiting_observations");
  i.now = i.agreement.terms.correctionsCloseAt;
  assertEquals(decision(i).phase, "review_required");
});

Deno.test("weekly steps: scheduled, active, and ended decisions never finalize", () => {
  const i = fixture();
  i.now = at(i.agreement.terms.startsAt, -1 / 3600, 999999);
  assertEquals(decision(i).phase, "scheduled");
  i.now = i.agreement.terms.startsAt;
  assertEquals(decision(i).phase, "active");
  i.now = i.agreement.terms.endsAt;
  assertEquals(decision(i).phase, "awaiting_observations");
  i.now = at(i.agreement.terms.endsAt, 10000);
  assertEquals(decision(i).phase, "review_required");
});

for (
  const [oldSteps, newSteps, outcome] of [[7000, 0, "confirmed_miss"], [0, 7000, "met"]] as const
) {
  Deno.test(`weekly steps: correction ${oldSteps} -> ${newSteps} recomputes qualification`, () => {
    const i = populate(fixture());
    i.revisions[0]!.steps = oldSteps;
    i.revisions.push({
      ...i.revisions[0]!,
      revision: 2,
      previousRevision: 1,
      receivedAt: at(i.agreement.terms.endsAt, 30, 360255),
      steps: newSteps,
    });
    assertEquals(decision(i).participants[0]!.qualification, outcome);
  });
}

Deno.test("weekly steps: revoked latest revision removes an earlier provisional met", () => {
  const i = populate(fixture());
  i.revisions[0]!.steps = 7000;
  i.revisions.push({
    ...i.revisions[0]!,
    revision: 2,
    previousRevision: 1,
    receivedAt: at(i.agreement.terms.endsAt, 30),
    status: "revoked",
    steps: null,
  });
  assertEquals(decision(i).participants[0]!.qualification, "unresolved");
});

for (const lateBy of [-1, 0, 1]) {
  Deno.test(`weekly steps: initial upload cutoff ${lateBy} microseconds`, () => {
    const i = fixture();
    const cutoff = i.agreement.terms.uploadClosesAt;
    const receivedAt = lateBy < 0 ? at(cutoff, -1 / 3600, 999999) : at(cutoff, 0, lateBy);
    i.revisions = [{ ...dayRevision(i, "alice"), steps: 7000, receivedAt }];
    const result = decision(i);
    assertEquals(result.participants[0]!.qualification, lateBy < 0 ? "met" : "unresolved");
    assertEquals(result.lateRevisionCount, lateBy < 0 ? 0 : 1);
  });
  Deno.test(`weekly steps: correction cutoff ${lateBy} microseconds`, () => {
    const i = fixture();
    const first = { ...dayRevision(i, "alice"), steps: 7000 };
    const cutoff = i.agreement.terms.correctionsCloseAt;
    i.now = at(cutoff, 1);
    const receivedAt = lateBy < 0 ? at(cutoff, -1 / 3600, 999999) : at(cutoff, 0, lateBy);
    i.revisions = [first, { ...first, revision: 2, previousRevision: 1, steps: 0, receivedAt }];
    const result = decision(i);
    assertEquals(result.participants[0]!.qualification, lateBy < 0 ? "unresolved" : "met");
    assertEquals(result.lateRevisionCount, lateBy < 0 ? 0 : 1);
  });
}

Deno.test("weekly steps: late initial cannot be laundered into an admitted correction", () => {
  const i = fixture();
  const first = {
    ...dayRevision(i, "alice"),
    receivedAt: i.agreement.terms.uploadClosesAt,
    steps: 7000,
  };
  i.revisions = [first, {
    ...first,
    revision: 2,
    previousRevision: 1,
    receivedAt: at(first.receivedAt, 1),
  }];
  assertEquals(decision(i).participants[0]!.qualification, "unresolved");
  assertEquals(decision(i).lateRevisionCount, 2);
});

Deno.test("weekly steps: complete zero at exact day end is valid", () => {
  const i = fixture();
  i.revisions = [{
    ...dayRevision(i, "alice"),
    receivedAt: i.agreement.terms.days[0]!.endsAt,
    steps: 0,
  }];
  assertEquals(decision(i).participants[0]!.completeDayCount, 1);
});

Deno.test("weekly steps: consent binding is independent of object key insertion order", () => {
  const i = fixture();
  const reversed = Object.fromEntries(Object.entries(i.agreement.terms).reverse());
  assertEquals(
    weeklyStepsConsentBinding(reversed as unknown as WeeklyStepsTerms),
    i.consents[0]!.termsBinding,
  );
});

Deno.test("weekly steps: input ledger order does not change outcomes or leak raw observations", () => {
  const i = populate(fixture(5), ["bob", "dana"]);
  const result = decision(i);
  i.revisions.reverse();
  i.consents.reverse();
  assertEquals(decision(i), result);
  const json = JSON.stringify(result);
  for (
    const forbidden of [
      "receivedAt",
      "previousRevision",
      "termsBinding",
      "sourceVersion",
      "date",
      "acceptedAt",
    ]
  ) {
    assert(!json.includes(`"${forbidden}"`), forbidden);
  }
});

const invalid: [string, (i: Input) => void, string][] = [
  ["duplicate participant", (i) => {
    i.agreement.terms.participants[1]!.participantId = "alice";
  }, "invalid_frozen_roster"],
  ["creator outside roster", (i) => {
    i.agreement.terms.creatorId = "stranger";
  }, "invalid_frozen_roster"],
  ["changed roster", (i) => {
    i.agreement.terms.participants[1]!.participantId = "charlie";
  }, "matching_consent"],
  ["changed target", (i) => {
    i.agreement.terms.participants[1]!.targetSteps = 8000;
  }, "matching_consent"],
  ["changed display zone", (i) => {
    i.agreement.terms.timezone = "US/Central";
  }, "matching_consent"],
  ["missing consent", (i) => {
    i.consents.pop();
  }, "requires_every_consent"],
  ["duplicate consent", (i) => {
    i.consents[1] = structuredClone(i.consents[0]!);
  }, "requires_every_consent"],
  ["wrong actor consent", (i) => {
    i.consents[1]!.participantId = "charlie";
  }, "matching_consent"],
  ["stale digest", (i) => {
    i.consents[1]!.termsDigest = "b".repeat(64);
  }, "matching_consent"],
  ["stale version", (i) => {
    i.consents[1]!.policyVersion = "old";
  }, "matching_consent"],
  ["wrong agreement consent", (i) => {
    i.consents[1]!.agreementId = "other";
  }, "matching_consent"],
  ["accept at start", (i) => {
    i.consents[1]!.acceptedAt = i.agreement.terms.startsAt;
  }, "invalid_consent_time"],
  ["accept before creation", (i) => {
    i.consents[1]!.acceptedAt = at(i.agreement.terms.createdAt, -1);
  }, "invalid_consent_time"],
  ["duplicate dates", (i) => {
    i.agreement.terms.days[1]!.date = i.agreement.terms.days[0]!.date;
  }, "date_sequence"],
  ["day gap", (i) => {
    i.agreement.terms.days[1]!.startsAt = i.agreement.terms.days[2]!.startsAt;
  }, "day_boundary"],
  ["day fraction", (i) => {
    i.agreement.terms.days[0]!.startsAt = at(i.agreement.terms.startsAt, 0, 1);
  }, "day_boundary"],
  ["wrong week end", (i) => {
    i.agreement.terms.endsAt = at(i.agreement.terms.endsAt, 1);
  }, "week_end"],
  ["unknown zone", (i) => {
    i.agreement.terms.timezone = "America/Fictional";
  }, "invalid_timezone"],
  ["numeric zone", (i) => {
    i.agreement.terms.timezone = "-05:00";
  }, "invalid_timezone"],
  ["retroactive start", (i) => {
    i.agreement.terms.createdAt = i.agreement.terms.startsAt;
  }, "deadlines"],
  ["wrong upload cutoff", (i) => {
    i.agreement.terms.uploadClosesAt = at(i.agreement.terms.uploadClosesAt, 0, 1);
  }, "deadlines"],
  ["short correction window", (i) => {
    i.agreement.terms.correctionsCloseAt = i.agreement.terms.uploadClosesAt;
  }, "deadlines"],
  ["foreign revision actor", (i) => {
    i.revisions[0]!.participantId = "stranger";
  }, "revision_binding"],
  ["foreign revision agreement", (i) => {
    i.revisions[0]!.agreementId = "foreign";
  }, "revision_binding"],
  ["wrong source", (i) => {
    i.revisions[0]!.sourceVersion = "healthkit_nonmanual_daily_v1";
  }, "revision_binding"],
  ["wrong proof policy", (i) => {
    i.revisions[0]!.policyVersion = "official_5k_v1";
  }, "revision_binding"],
  ["changed proof digest", (i) => {
    i.revisions[0]!.termsDigest = "b".repeat(64);
  }, "revision_binding"],
  ["out-of-window date", (i) => {
    i.revisions[0]!.date = "2026-09-06";
  }, "outside_week"],
  ["duplicate revision", (i) => {
    i.revisions.push(structuredClone(i.revisions[0]!));
  }, "revision_chain"],
  ["missing predecessor", (i) => {
    i.revisions[0]!.revision = 2;
  }, "revision_chain"],
  ["wrong predecessor", (i) => {
    i.revisions[0]!.previousRevision = 0;
  }, "revision_chain"],
  ["future observation", (i) => {
    i.revisions[0]!.receivedAt = at(i.now, 0, 1);
  }, "observation_time"],
  ["pre-day observation", (i) => {
    i.revisions[0]!.receivedAt = at(i.agreement.terms.startsAt, -1);
  }, "observation_time"],
  ["premature complete day", (i) => {
    i.revisions[0]!.receivedAt = at(i.agreement.terms.days[0]!.endsAt, -1 / 3600, 999999);
  }, "premature_day_completeness"],
  ["revoked carrying steps", (i) => {
    i.revisions[0]!.status = "revoked";
  }, "observation_steps"],
  ["complete lacking value", (i) => {
    i.revisions[0]!.steps = null;
  }, "observation_steps"],
];
for (const [name, change, reason] of invalid) {
  Deno.test(`weekly steps: rejects ${name}`, () => {
    const i = populate(fixture());
    change(i);
    assertThrows(() => evaluateWeeklySteps(i), WeeklyStepsError, reason);
  });
}

for (const value of [-1, 0, 0.5, NaN, Infinity, Number.MAX_SAFE_INTEGER, 1_000_001]) {
  Deno.test(`weekly steps: rejects target ${value}`, () => {
    const i = fixture();
    i.agreement.terms.participants[0]!.targetSteps = value;
    assertThrows(() => evaluateWeeklySteps(i), WeeklyStepsError, "invalid_target_steps");
  });
}
for (const value of [-1, 0.5, NaN, Infinity, Number.MAX_SAFE_INTEGER, 1_000_001]) {
  Deno.test(`weekly steps: rejects observation ${value}`, () => {
    const i = populate(fixture());
    i.revisions[0]!.steps = value;
    assertThrows(() => evaluateWeeklySteps(i), WeeklyStepsError, "invalid_observation_steps");
  });
}

for (
  const now of [
    "2026-09-16",
    "2026-09-16T05:00:00",
    "2026-02-30T05:00:00Z",
    "2026-09-16T05:00:00.1234567Z",
    "2026-09-16T24:00:00Z",
    "2026-09-16T05:00:60Z",
    "2026-09-16T05:00:00+24:00",
    "2026-09-16T05:00:00+01:60",
  ]
) {
  Deno.test(`weekly steps: rejects malformed clock ${now}`, () => {
    const i = fixture();
    i.now = now;
    assertThrows(() => evaluateWeeklySteps(i), WeeklyStepsError, "invalid_instant");
  });
}

Deno.test("weekly steps: frozen policy rejects live mode, alternate units and injected fields", () => {
  for (
    const delta of [{ mode: "live" }, { unit: "minutes" }, { source: "apple" }, {
      maximumTarget: 2_000_000,
    }, { extra: true }]
  ) {
    const i = fixture();
    Object.assign(i.agreement.terms.policy, delta);
    reconsent(i);
    assertThrows(() => evaluateWeeklySteps(i), WeeklyStepsError, "unsupported_weekly_policy");
  }
});

Deno.test("weekly steps: bounds are inclusive parser bounds without a recommended target", () => {
  const i = fixture();
  i.agreement.terms.participants[0]!.targetSteps = 1;
  i.agreement.terms.participants[1]!.targetSteps = 1_000_000;
  reconsent(i);
  i.revisions = [
    { ...dayRevision(i, "alice"), steps: 1 },
    { ...dayRevision(i, "bob"), steps: 1_000_000 },
  ];
  assertEquals(decision(i).groupOutcome, "all_met");
});

Deno.test("weekly steps: per-day revisions retain microseconds and require monotonic receipt order", () => {
  const i = fixture();
  const first = { ...dayRevision(i, "alice"), receivedAt: at(i.agreement.terms.endsAt, 0, 360255) };
  i.revisions = [first, {
    ...first,
    revision: 2,
    previousRevision: 1,
    receivedAt: at(i.agreement.terms.endsAt, 0, 360254),
  }];
  assertThrows(() => evaluateWeeklySteps(i), WeeklyStepsError, "receipts_out_of_order");
  i.revisions[1]!.receivedAt = first.receivedAt;
  assertEquals(decision(i).participants[0]!.completeDayCount, 1);
});

function participantFixture(): WeeklyParticipantInput {
  const i = populate(fixture(2), ["alice"]);
  return {
    agreementId: i.agreement.id,
    termsDigest: i.agreement.termsDigest,
    policyVersion: WEEKLY_STEPS_POLICY_VERSION,
    participantId: "alice",
    targetSteps: 7000,
    days: i.agreement.terms.days,
    revisions: i.revisions.filter((r) => r.participantId === "alice"),
    now: i.now,
    uploadClosesAt: i.agreement.terms.uploadClosesAt,
    correctionsCloseAt: i.agreement.terms.correctionsCloseAt,
  };
}

Deno.test("weekly steps: shared primitive agrees with validated friend decisions", () => {
  const i = participantFixture();
  const result = evaluateWeeklyParticipant(i);
  assertEquals(result.qualification, "met");
  assertEquals(result.observedSteps, 7000);
  assertEquals(result.qualifyingSteps, 7000);
  assertEquals(result.completeDayCount, 7);
  assertEquals(result.lateRevisionCount, 0);
});

Deno.test("weekly steps: shared primitive binds separate community policy without granting consent", () => {
  const i = participantFixture();
  i.policyVersion = "weekly-community-steps-fixture-v1";
  i.revisions = i.revisions.map((r) => ({ ...r, policyVersion: i.policyVersion }));
  assertEquals(evaluateWeeklyParticipant(i).qualification, "met");
  // This helper only qualifies one participant; the friend entry point remains 2–5.
  assertThrows(() => evaluateWeeklySteps(fixture(6)), WeeklyStepsError, "invalid_frozen_roster");
});

for (
  const delta of [
    { participantId: "bob" },
    { agreementId: "foreign" },
    { termsDigest: "b".repeat(64) },
    { policyVersion: "weekly-community-steps-fixture-v1" },
  ]
) {
  Deno.test(`weekly steps: shared primitive rejects cross-contract rows ${JSON.stringify(delta)}`, () => {
    const i = participantFixture();
    Object.assign(i, delta);
    assertThrows(() => evaluateWeeklyParticipant(i), WeeklyStepsError, "invalid_revision_binding");
  });
}

Deno.test("weekly steps: malformed snapshot collections fail with policy errors", () => {
  const cases: ((i: Input) => void)[] = [
    (i) => {
      Object.assign(i.agreement.terms, { days: [null, ...i.agreement.terms.days.slice(1)] });
    },
    (i) => {
      Object.assign(i.agreement.terms, { participants: [null, i.agreement.terms.participants[1]] });
    },
    (i) => {
      Object.assign(i, { consents: [null, i.consents[1]] });
    },
    (i) => {
      Object.assign(i, { revisions: [null] });
    },
    (i) => {
      Object.assign(i, { revisions: {} });
    },
    (i) => {
      Object.assign(i.agreement.terms, { policy: null });
    },
    (i) => {
      Object.assign(i.agreement.terms, { lifecycle: null });
    },
  ];
  for (const change of cases) {
    const i = fixture();
    change(i);
    assertThrows(() => evaluateWeeklySteps(i), WeeklyStepsError);
  }
});

Deno.test("weekly steps: lifecycle changes require matching terms and never shorten review", () => {
  for (
    const delta of [
      { filingWindowHours: 24 },
      { resolutionWindowHours: 24 },
      { simulationEntryCents: 3000 },
      { feeCents: 1 },
      { exitPolicy: "miss_on_exit" },
      { retentionPolicy: "public" },
      { noticeBy: "2026-09-17T05:00:00.000001Z" },
      { finalityBy: "2026-09-22T05:00:00.000000Z" },
    ]
  ) {
    const i = fixture();
    Object.assign(i.agreement.terms.lifecycle, delta);
    assertThrows(() => evaluateWeeklySteps(i), WeeklyStepsError, "unsupported_weekly_lifecycle");
  }
});

Deno.test("weekly steps: a Tuesday calendar cannot replace the agreed Monday week", () => {
  assertThrows(
    () => evaluateWeeklySteps(fixture(2, "2026-09-08")),
    WeeklyStepsError,
    "week_must_start_monday",
  );
});

Deno.test("weekly steps: revisions are bounded and cannot skip to an arbitrary sequence", () => {
  const i = populate(fixture());
  i.revisions[0]!.revision = 129;
  assertThrows(() => evaluateWeeklySteps(i), WeeklyStepsError, "invalid_revision_number");
  const helper = participantFixture();
  helper.revisions = Array.from({ length: 897 }, () => helper.revisions[0]!);
  assertThrows(() => evaluateWeeklyParticipant(helper), WeeklyStepsError, "too_many_revisions");
});
