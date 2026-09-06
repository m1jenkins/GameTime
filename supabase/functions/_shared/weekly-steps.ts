/**
 * W1A fictional weekly qualification only. No I/O, ambient clock, source
 * authentication, final result publication, or allocation. `complete` is a
 * test/server-fixture assertion: an ordinary health client cannot establish it.
 * Never adapt old Personal or official-5K terms into this policy.
 */
export const WEEKLY_STEPS_VERSION = "weekly-steps-qualification-v1";
export const WEEKLY_STEPS_POLICY_VERSION = "weekly-friend-steps-fixture-v1";
export const WEEKLY_STEPS_SOURCE_VERSION = "fixture_weekly_steps_v1";

/** Fixture parser bounds and timing choices, not launch or health recommendations. */
export const WEEKLY_STEPS_POLICY_V1 = Object.freeze(
  {
    version: WEEKLY_STEPS_POLICY_VERSION,
    source: WEEKLY_STEPS_SOURCE_VERSION,
    metric: "steps",
    unit: "whole_steps",
    mode: "fictional_nonredeemable",
    minParticipants: 2,
    maxParticipants: 5,
    participantCapacityAssumption: "includes_creator_unconfirmed",
    minimumTarget: 1,
    maximumTarget: 1_000_000,
    maximumDailySteps: 1_000_000,
    maximumRevisionsPerDay: 128,
    uploadHoursAfterEnd: 24,
    correctionHoursAfterEnd: 48,
    simulatedCentsEach: 2000,
    feeCentsEach: 0,
    outcomeRule: "individual_cumulative_gte_all_may_qualify",
    unresolvedRule: "group_void_no_simulated_loss",
    safeExitRule: "group_void_no_simulated_loss",
    finalityRule: "separate_notices_and_full_review_required",
  } as const,
);

export interface WeeklyStepsDay {
  date: string;
  startsAt: string;
  endsAt: string;
}

export interface WeeklyStepsTerms {
  agreementVersion: 1;
  policy: typeof WEEKLY_STEPS_POLICY_V1;
  creatorId: string;
  createdAt: string;
  timezone: string;
  startsAt: string;
  endsAt: string;
  uploadClosesAt: string;
  correctionsCloseAt: string;
  lifecycle: {
    noticeBy: string;
    filingWindowHours: 48;
    resolutionWindowHours: 72;
    finalityBy: string;
    simulationEntryCents: 2000;
    feeCents: 0;
    exitPolicy: "void_friend_refund_community_v1";
    retentionPolicy: "private_fictional_receipts_v1";
  };
  days: readonly WeeklyStepsDay[];
  participants: readonly { participantId: string; targetSteps: number }[];
}

export interface WeeklyStepsAgreement {
  id: string;
  termsDigest: string;
  terms: WeeklyStepsTerms;
}

export interface WeeklyStepsConsent {
  agreementId: string;
  participantId: string;
  termsDigest: string;
  policyVersion: string;
  /** Exact canonical full-terms binding; a digest alone cannot detect mutated caller input. */
  termsBinding: string;
  acceptedAt: string;
}

export type WeeklyStepsObservationStatus =
  | "complete"
  | "incomplete"
  | "missing"
  | "revoked"
  | "query_failed";

export interface WeeklyStepsRevision {
  agreementId: string;
  participantId: string;
  termsDigest: string;
  policyVersion: string;
  sourceVersion: string;
  date: string;
  /** Contiguous chain per participant/date, starting at one. */
  revision: number;
  previousRevision: number | null;
  receivedAt: string;
  status: WeeklyStepsObservationStatus;
  /** Only complete/incomplete observations carry steps; unavailable states require null. */
  steps: number | null;
}

export interface WeeklyStepsInput {
  agreement: WeeklyStepsAgreement;
  consents: readonly WeeklyStepsConsent[];
  /** Complete append-only ledgers from an authorized consistent source, not a user request. */
  revisions: readonly WeeklyStepsRevision[];
  now: string;
}

export type WeeklyStepsQualification = "pending" | "met" | "confirmed_miss" | "unresolved";
export type WeeklyStepsGroupOutcome =
  | "pending"
  | "all_met"
  | "some_met"
  | "none_met"
  | "unresolved";

export interface WeeklyStepsDecision {
  version: typeof WEEKLY_STEPS_VERSION;
  agreementId: string;
  termsDigest: string;
  phase: "scheduled" | "active" | "awaiting_observations" | "review_required";
  participants: {
    participantId: string;
    qualification: WeeklyStepsQualification;
    /** Display progress; incomplete totals do not establish qualification. */
    observedSteps: number;
    qualifyingSteps: number;
    completeDayCount: number;
  }[];
  groupOutcome: WeeklyStepsGroupOutcome;
  final: false;
  /** Late evidence is never silently admitted by calling it a correction. */
  lateRevisionCount: number;
}

export class WeeklyStepsError extends Error {
  override name = "WeeklyStepsError";
}

function fact(value: unknown, reason: string): asserts value {
  if (!value) throw new WeeklyStepsError(reason);
}

const MICROSECOND = 1_000_000n;
const HOUR = 3_600n * MICROSECOND;

/** Strict RFC3339 with all PostgreSQL microseconds retained. */
function instant(value: unknown): bigint {
  fact(typeof value === "string", "invalid_instant");
  const parts = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,6}))?(Z|([+-])(\d{2}):(\d{2}))$/
    .exec(value);
  fact(parts, "invalid_instant");
  const local = `${parts[1]}.000Z`;
  const ms = Date.parse(local);
  fact(Number.isFinite(ms) && new Date(ms).toISOString() === local, "invalid_instant");
  const hours = Number(parts[5] ?? 0);
  const minutes = Number(parts[6] ?? 0);
  fact(hours <= 23 && minutes <= 59, "invalid_instant_offset");
  const offset = BigInt(hours * 60 + minutes) * 60n * MICROSECOND *
    (parts[4] === "-" ? -1n : 1n);
  return BigInt(ms) * 1000n + BigInt((parts[2] ?? "").padEnd(6, "0")) - offset;
}

function identifier(value: unknown): value is string {
  return typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(value);
}

function integer(value: unknown, minimum: number, maximum: number): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= minimum &&
    value <= maximum;
}

function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value !== null && typeof value === "object") {
    return `{${
      Object.keys(value).sort().map((key) =>
        `${JSON.stringify(key)}:${canonical((value as Record<string, unknown>)[key])}`
      ).join(",")
    }}`;
  }
  fact(
    value === null || typeof value === "string" || typeof value === "boolean" ||
      (typeof value === "number" && Number.isFinite(value)),
    "invalid_terms_value",
  );
  return JSON.stringify(value);
}

/** Canonical serialization, not a signature, hash, authentication token, or consent authority. */
export function weeklyStepsConsentBinding(terms: WeeklyStepsTerms): string {
  return canonical(terms);
}

function dateMs(value: unknown): number {
  fact(typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value), "invalid_local_date");
  const ms = Date.parse(`${value}T00:00:00.000Z`);
  fact(
    Number.isFinite(ms) && new Date(ms).toISOString() === `${value}T00:00:00.000Z`,
    "invalid_local_date",
  );
  return ms;
}

function nextDate(value: string): string {
  return new Date(dateMs(value) + 86_400_000).toISOString().slice(0, 10);
}

function validateWindow(terms: WeeklyStepsTerms) {
  fact(
    typeof terms.timezone === "string" &&
      /^(?:UTC|[A-Za-z_]+\/[A-Za-z0-9_+\/-]+)$/.test(terms.timezone),
    "invalid_timezone",
  );
  let formatter: Intl.DateTimeFormat;
  try {
    formatter = new Intl.DateTimeFormat("en-US-u-ca-iso8601-nu-latn", {
      timeZone: terms.timezone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hourCycle: "h23",
    });
  } catch {
    throw new WeeklyStepsError("invalid_timezone");
  }
  function midnight(value: string, date: string): bigint {
    const time = instant(value);
    fact(time % MICROSECOND === 0n, "invalid_day_boundary");
    const fields = Object.fromEntries(
      formatter.formatToParts(new Date(Number(time / 1000n))).map((p) => [p.type, p.value]),
    );
    fact(
      `${fields.year}-${fields.month}-${fields.day}` === date &&
        fields.hour === "00" && fields.minute === "00" && fields.second === "00",
      "invalid_day_boundary",
    );
    return time;
  }
  fact(
    Array.isArray(terms.days) && terms.days.length === 7 &&
      terms.days.every((day) => day && typeof day === "object"),
    "invalid_week_days",
  );
  const first = terms.days[0]!;
  fact(new Date(dateMs(first.date)).getUTCDay() === 1, "week_must_start_monday");
  let expectedDate = first.date;
  let boundary = instant(terms.startsAt);
  for (const day of terms.days) {
    fact(day && day.date === expectedDate, "invalid_week_date_sequence");
    fact(midnight(day.startsAt, day.date) === boundary, "invalid_week_boundary_sequence");
    expectedDate = nextDate(day.date);
    const end = midnight(day.endsAt, expectedDate);
    fact(
      end > boundary && end - boundary >= 22n * HOUR && end - boundary <= 26n * HOUR,
      "unsupported_calendar_transition",
    );
    boundary = end;
  }
  fact(boundary === instant(terms.endsAt), "invalid_week_end");
}

function validateAgreement(input: WeeklyStepsInput) {
  const a = input.agreement;
  fact(a && identifier(a.id) && /^[0-9a-f]{64}$/.test(a.termsDigest), "invalid_agreement");
  const t = a.terms;
  fact(
    t && t.agreementVersion === 1 && canonical(t.policy) === canonical(WEEKLY_STEPS_POLICY_V1),
    "unsupported_weekly_policy",
  );
  fact(
    Array.isArray(t.participants) && t.participants.length >= 2 && t.participants.length <= 5 &&
      t.participants.every((p) => p && identifier(p.participantId)) &&
      new Set(t.participants.map((p) => p.participantId)).size === t.participants.length &&
      t.participants.some((p) => p.participantId === t.creatorId),
    "invalid_frozen_roster",
  );
  fact(
    t.participants.every((p) => integer(p.targetSteps, 1, WEEKLY_STEPS_POLICY_V1.maximumTarget)),
    "invalid_target_steps",
  );
  validateWindow(t);
  const created = instant(t.createdAt);
  const start = instant(t.startsAt);
  const end = instant(t.endsAt);
  const upload = instant(t.uploadClosesAt);
  const correction = instant(t.correctionsCloseAt);
  const now = instant(input.now);
  fact(
    created < start && created <= now && upload === end + 24n * HOUR &&
      correction === end + 48n * HOUR,
    "invalid_weekly_deadlines",
  );
  fact(
    t.lifecycle && instant(t.lifecycle.noticeBy) === end + 72n * HOUR &&
      instant(t.lifecycle.finalityBy) === end + 216n * HOUR &&
      t.lifecycle.filingWindowHours === 48 && t.lifecycle.resolutionWindowHours === 72 &&
      t.lifecycle.simulationEntryCents === 2000 && t.lifecycle.feeCents === 0 &&
      t.lifecycle.exitPolicy === "void_friend_refund_community_v1" &&
      t.lifecycle.retentionPolicy === "private_fictional_receipts_v1",
    "unsupported_weekly_lifecycle",
  );
  fact(
    Array.isArray(input.consents) && input.consents.length === t.participants.length &&
      new Set(input.consents.map((c) => c?.participantId)).size === t.participants.length,
    "requires_every_consent",
  );
  const binding = weeklyStepsConsentBinding(t);
  for (const c of input.consents) {
    fact(
      c && c.agreementId === a.id && t.participants.some((p) =>
        p.participantId === c.participantId
      ) &&
        c.termsDigest === a.termsDigest && c.policyVersion === WEEKLY_STEPS_POLICY_VERSION &&
        c.termsBinding === binding,
      "requires_matching_consent",
    );
    const accepted = instant(c.acceptedAt);
    fact(accepted >= created && accepted < start && accepted <= now, "invalid_consent_time");
  }
  return { a, t, start, end, upload, correction, now };
}

export interface WeeklyParticipantInput {
  agreementId: string;
  termsDigest: string;
  policyVersion: string;
  participantId: string;
  targetSteps: number;
  days: readonly WeeklyStepsDay[];
  revisions: readonly WeeklyStepsRevision[];
  now: string;
  uploadClosesAt: string;
  correctionsCloseAt: string;
}

/**
 * Common fictional qualification primitive for a separately validated community
 * contract. Caller must validate its own immutable calendar, roster and consents.
 * This does not widen the friend policy's two-to-five-person agreement boundary.
 */
export function evaluateWeeklyParticipant(input: WeeklyParticipantInput) {
  fact(
    input && identifier(input.agreementId) && identifier(input.participantId) &&
      /^[0-9a-f]{64}$/.test(input.termsDigest) && identifier(input.policyVersion),
    "invalid_participant_binding",
  );
  fact(integer(input.targetSteps, 1, WEEKLY_STEPS_POLICY_V1.maximumTarget), "invalid_target_steps");
  fact(
    Array.isArray(input.days) && input.days.length === 7 &&
      input.days.every((day) => day && typeof day === "object") &&
      new Set(input.days.map((d) => d.date)).size === 7,
    "invalid_week_days",
  );
  for (let index = 0; index < input.days.length; index++) {
    const day = input.days[index]!;
    dateMs(day.date);
    fact(instant(day.startsAt) < instant(day.endsAt), "invalid_day_boundary");
    if (index > 0) {
      fact(
        day.date === nextDate(input.days[index - 1]!.date) &&
          instant(day.startsAt) === instant(input.days[index - 1]!.endsAt),
        "invalid_week_boundary_sequence",
      );
    }
  }
  const now = instant(input.now);
  const upload = instant(input.uploadClosesAt);
  const correction = instant(input.correctionsCloseAt);
  const end = instant(input.days[6]!.endsAt);
  fact(upload === end + 24n * HOUR && correction === end + 48n * HOUR, "invalid_weekly_deadlines");
  fact(Array.isArray(input.revisions), "invalid_revisions");
  fact(input.revisions.length <= 7 * 128, "too_many_revisions");
  const chains = new Map<string, WeeklyStepsRevision[]>();
  for (const r of input.revisions) {
    fact(
      r && r.agreementId === input.agreementId && r.termsDigest === input.termsDigest &&
        r.policyVersion === input.policyVersion &&
        r.sourceVersion === WEEKLY_STEPS_SOURCE_VERSION &&
        r.participantId === input.participantId,
      "invalid_revision_binding",
    );
    const day = input.days.find((d) => d.date === r.date);
    fact(day, "revision_outside_week");
    fact(integer(r.revision, 1, 128), "invalid_revision_number");
    fact(
      ["complete", "incomplete", "missing", "revoked", "query_failed"].includes(r.status),
      "invalid_observation_status",
    );
    fact(
      (r.status === "complete" || r.status === "incomplete")
        ? integer(r.steps, 0, WEEKLY_STEPS_POLICY_V1.maximumDailySteps)
        : r.steps === null,
      "invalid_observation_steps",
    );
    const received = instant(r.receivedAt);
    fact(received >= instant(day.startsAt) && received <= now, "invalid_observation_time");
    fact(r.status !== "complete" || received >= instant(day.endsAt), "premature_day_completeness");
    const key = `${r.participantId}/${r.date}`;
    const chain = chains.get(key) ?? [];
    chain.push(r);
    chains.set(key, chain);
  }
  const latest = new Map<string, WeeklyStepsRevision>();
  let lateRevisionCount = 0;
  for (const [key, rows] of chains) {
    const chain = [...rows].sort((a, b) => a.revision - b.revision);
    let predecessor: WeeklyStepsRevision | undefined;
    let initialAdmitted = false;
    for (const r of chain) {
      fact(
        r.revision === (predecessor?.revision ?? 0) + 1 &&
          r.previousRevision === (predecessor?.revision ?? null),
        "invalid_revision_chain",
      );
      fact(
        !predecessor || instant(r.receivedAt) >= instant(predecessor.receivedAt),
        "revision_receipts_out_of_order",
      );
      const receipt = instant(r.receivedAt);
      if (!predecessor) initialAdmitted = receipt < upload;
      if (initialAdmitted && receipt < correction) latest.set(key, r);
      else lateRevisionCount++;
      predecessor = r;
    }
  }
  let observedSteps = 0;
  let qualifyingSteps = 0;
  let completeDayCount = 0;
  for (const day of input.days) {
    const r = latest.get(`${input.participantId}/${day.date}`);
    if (r?.status === "complete" || r?.status === "incomplete") observedSteps += r.steps!;
    if (r?.status === "complete") {
      qualifyingSteps += r.steps!;
      completeDayCount++;
    }
  }
  const qualification: WeeklyStepsQualification = qualifyingSteps >= input.targetSteps
    ? "met"
    : now < upload
    ? "pending"
    : completeDayCount === 7
    ? "confirmed_miss"
    : "unresolved";
  return {
    participantId: input.participantId,
    qualification,
    observedSteps,
    qualifyingSteps,
    completeDayCount,
    lateRevisionCount,
  };
}

export function evaluateWeeklySteps(input: WeeklyStepsInput): WeeklyStepsDecision {
  fact(input && typeof input === "object", "invalid_input");
  const { a, t, start, end, correction, now } = validateAgreement(input);
  fact(Array.isArray(input.revisions), "invalid_revisions");
  fact(input.revisions.length <= t.participants.length * 7 * 128, "too_many_revisions");
  fact(
    input.revisions.every((r) =>
      r && t.participants.some((p) => p.participantId === r.participantId)
    ),
    "invalid_revision_binding",
  );
  let lateRevisionCount = 0;
  const participants = [...t.participants].sort((a, b) =>
    a.participantId < b.participantId ? -1 : a.participantId > b.participantId ? 1 : 0
  ).map((p) => {
    const result = evaluateWeeklyParticipant({
      agreementId: a.id,
      termsDigest: a.termsDigest,
      policyVersion: WEEKLY_STEPS_POLICY_VERSION,
      participantId: p.participantId,
      targetSteps: p.targetSteps,
      days: t.days,
      revisions: input.revisions.filter((r) => r.participantId === p.participantId),
      now: input.now,
      uploadClosesAt: t.uploadClosesAt,
      correctionsCloseAt: t.correctionsCloseAt,
    });
    lateRevisionCount += result.lateRevisionCount;
    const { lateRevisionCount: _late, ...participant } = result;
    return participant;
  });
  const qualifications = participants.map((p) => p.qualification);
  const groupOutcome: WeeklyStepsGroupOutcome = qualifications.includes("unresolved")
    ? "unresolved"
    : qualifications.includes("pending")
    ? "pending"
    : qualifications.every((q) => q === "met")
    ? "all_met"
    : qualifications.some((q) => q === "met")
    ? "some_met"
    : "none_met";
  return {
    version: WEEKLY_STEPS_VERSION,
    agreementId: a.id,
    termsDigest: a.termsDigest,
    phase: now < start
      ? "scheduled"
      : now < end
      ? "active"
      : now < correction
      ? "awaiting_observations"
      : "review_required",
    participants,
    groupOutcome,
    final: false,
    lateRevisionCount,
  };
}
