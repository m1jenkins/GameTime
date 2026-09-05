/**
 * Phase 2(a): pure decisions for the existing simulated, fictional 5K policy.
 * No I/O, ambient clock, persistence, authorization, notifications or settlement.
 *
 * Callers must supply a complete, transactionally consistent private snapshot.
 * Reviewers, server receipt times, append-only revisions and durable notices must
 * eventually come from the narrow operator/worker boundary, never a client body.
 * This module checks their consistency; it cannot establish their authenticity.
 * Keep it separate from the legacy charity scoring engine and its obligations.
 */

export const DUEL_SCORING_VERSION = "duel-fixture-official-5k-v1";
export const DUEL_POLICY_VERSION = "duel-fixture-5k-v1";

/** Exact Phase 1A specification. A new policy requires a new evaluator version. */
export const DUEL_POLICY_V1 = Object.freeze({
  source: "fixture_official_5k_v1",
  sport: "outdoor_running",
  distance_meters: 5000,
  timing_basis: "organizer_chip",
  precision_seconds: 1,
  attempts: 1,
  handicap: "none",
  mode: "simulated",
  currency: "USD",
  stake_cents_each: 2000,
  fee_cents_each: 0,
  participant_count: 2,
  accept_within_hours: 72,
  accept_before_start_hours: 1,
  results_after_end_hours: 72,
  dispute_after_durable_notice_hours: 168,
  review_after_filing_hours: 168,
  finality_after_end_hours: 720,
  winner: "lower_valid_chip_seconds",
  tie: "return_both_zero_fee",
  confirmed_nonfinish: "qualifying_finisher_wins_after_review",
  both_nonfinish: "void_zero_consequence",
  missing_or_ambiguous_proof: "review_then_void_zero_consequence",
  prestart_cancellation: "creator_or_either_accepted_runner_zero_consequence",
  poststart_withdrawal: "withdrawn_no_contest_zero_consequence",
  injury_or_event_cancellation: "void_zero_consequence",
  settlement: "simulation_only_after_dispute_deadline_and_review",
  review_timeout: "void_zero_consequence",
  corrections: "append_only_no_automatic_new_consequence",
  consent_version: "duel-simulated-consent-v1",
});

/** Selected fields from get_duel_v1; the terms and digest are carried verbatim. */
export interface DuelScoringAgreement {
  readonly id: string;
  readonly terms_digest: string;
  readonly terms: {
    readonly agreement_version: number;
    readonly policy_version: string;
    readonly policy: Readonly<Record<string, unknown>>;
    readonly creator_id: string;
    readonly invitee_id: string;
    readonly created_at: string;
    readonly accept_by: string;
    readonly results_due_at: string;
    readonly finality_due_at: string;
    readonly event: {
      readonly id: string;
      readonly policy_version: string;
      readonly course: string;
      readonly wave: string;
      readonly starts_at: string;
      readonly ends_at: string;
    };
  };
  readonly participants: readonly {
    readonly challenge_id: string;
    readonly actor_id: string;
    readonly role: string;
    readonly accepted_at: string | null;
    readonly declined_at: string | null;
    readonly consent_policy_version: string | null;
    readonly consent_terms_digest: string | null;
  }[];
}

/** Private normalized reviewer facts. No participant upload is accepted here. */
export interface DuelOfficialRecord {
  readonly actorId: string;
  readonly status: "finished" | "dns" | "dnf" | "disqualified" | "missing" | "ambiguous";
  readonly source: string;
  readonly sourceReference: string | null;
  readonly eventId: string;
  readonly course: string;
  readonly wave: string;
  readonly distanceMeters: number;
  readonly timingBasis: string;
  readonly precisionSeconds: number;
  readonly mappedBib: string | null;
  readonly publishedBib: string | null;
  readonly identityConfirmed: boolean;
  readonly chipSeconds: number | null;
}

/** Each append replaces the complete pair's proof snapshot, including gaps. */
export interface DuelProofRevision {
  readonly revision: number;
  readonly supersedesRevision: number | null;
  readonly recordedAt: string;
  readonly reviewerId: string;
  readonly records: readonly DuelOfficialRecord[];
}

export interface DuelResultNotice {
  /** Zero denotes the no-proof result after the initial cutoff. */
  readonly proofRevision: number;
  readonly actorId: string;
  /** Durable in-app creation time, never an APNs delivery/acknowledgment time. */
  readonly recordedAt: string;
}

export interface DuelReviewCase {
  readonly id: string;
  readonly proofRevision: number;
  readonly filedBy: string;
  readonly filedAt: string;
  readonly resolution: {
    readonly reviewerId: string;
    readonly decidedAt: string;
    /** Corrected proof is a separate append; a resolution never edits a time. */
    readonly decision: "uphold" | "void";
  } | null;
}

export type DuelOutcome =
  | {
    readonly kind: "winner";
    readonly winnerId: string;
    readonly reason: "faster_chip" | "only_finisher";
  }
  | { readonly kind: "tie"; readonly reason: "equal_chip_seconds" }
  | { readonly kind: "withdrawn_no_contest"; readonly reason: "participant_withdrew" }
  | {
    readonly kind: "void";
    readonly reason:
      | "both_nonfinish"
      | "unresolved_proof"
      | "prestart_withdrawal"
      | "injury"
      | "event_cancelled"
      | "account_deleted"
      | "review_void"
      | "review_timeout"
      | "finality_timeout";
  };

export interface DuelFinalResult {
  readonly version: typeof DUEL_SCORING_VERSION;
  readonly challengeId: string;
  readonly termsDigest: string;
  readonly proofRevision: number;
  readonly finalizedAt: string;
  readonly outcome: DuelOutcome;
}

export interface DuelScoringInput {
  readonly agreement: DuelScoringAgreement;
  readonly now: string;
  readonly proofRevisions: readonly DuelProofRevision[];
  readonly notices: readonly DuelResultNotice[];
  readonly reviews: readonly DuelReviewCase[];
  /** Earliest authorized safe-exit event; blocking alone is not a result event. */
  readonly closure: {
    readonly kind: "withdrawal" | "injury" | "event_cancelled" | "account_deleted";
    readonly actorId: string | null;
    readonly recordedAt: string;
  } | null;
  /** Persisted final result, not a caller's proposed result. Never recomputed. */
  readonly finalResult: DuelFinalResult | null;
}

export interface DuelScoringDecision {
  readonly version: typeof DUEL_SCORING_VERSION;
  readonly challengeId: string;
  readonly termsDigest: string;
  readonly proofRevision: number;
  readonly phase:
    | "scheduled"
    | "active"
    | "awaiting_proof"
    | "provisional"
    | "ready_to_finalize"
    | "final";
  readonly outcome: DuelOutcome | null;
  readonly disputeClosesAt: string | null;
  readonly reviewDueAt: string | null;
  readonly supportCorrectionRequired: boolean;
}

export class DuelScoringError extends Error {
  override name = "DuelScoringError";
}

function requireFact(value: unknown, message: string): asserts value {
  if (!value) throw new DuelScoringError(message);
}

const HOUR = 3_600_000_000n;
const MICROSECOND = 1_000_000n;

/** Preserve PostgreSQL microseconds; Date.parse alone loses cutoff boundaries. */
function instant(value: string): bigint {
  requireFact(typeof value === "string", "invalid_instant");
  const parts = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,6}))?(Z|([+-])(\d{2}):(\d{2}))$/
    .exec(value);
  requireFact(parts, "invalid_instant");
  const local = `${parts[1]}.000Z`;
  const ms = Date.parse(local);
  requireFact(Number.isFinite(ms) && new Date(ms).toISOString() === local, "invalid_instant");
  const hours = Number(parts[5] ?? 0);
  const minutes = Number(parts[6] ?? 0);
  requireFact(hours <= 23 && minutes <= 59, "invalid_instant_offset");
  const offset = BigInt(hours * 60 + minutes) * 60n * MICROSECOND * (parts[4] === "-" ? -1n : 1n);
  return BigInt(ms) * 1000n + BigInt((parts[2] ?? "").padEnd(6, "0")) - offset;
}

function timestamp(value: bigint): string {
  const seconds = value >= 0n ? value / MICROSECOND : (value - MICROSECOND + 1n) / MICROSECOND;
  return new Date(Number(seconds * 1000n)).toISOString().slice(0, 19) +
    `.${String(value - seconds * MICROSECOND).padStart(6, "0")}Z`;
}

function nonempty(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function validateAgreement(a: DuelScoringAgreement) {
  const t = a.terms;
  const e = t.event;
  requireFact(nonempty(a.id) && /^[0-9a-f]{64}$/.test(a.terms_digest), "invalid_agreement_binding");
  requireFact(
    t.agreement_version === 1 && t.policy_version === DUEL_POLICY_VERSION &&
      e.policy_version === DUEL_POLICY_VERSION,
    "unsupported_duel_policy",
  );
  requireFact(
    t.policy && Object.keys(t.policy).length === Object.keys(DUEL_POLICY_V1).length &&
      Object.entries(DUEL_POLICY_V1).every(([key, value]) => t.policy[key] === value),
    "unsupported_duel_policy",
  );
  requireFact(
    nonempty(e.id) && e.course === "fixture_course_5k_v1" &&
      e.wave === "fixture_common_wave_v1",
    "unsupported_duel_event",
  );
  const actors = [t.creator_id, t.invitee_id];
  requireFact(actors.every(nonempty) && actors[0] !== actors[1], "invalid_duel_pair");
  const created = instant(t.created_at);
  const start = instant(e.starts_at);
  const end = instant(e.ends_at);
  const cutoff = instant(t.results_due_at);
  const cap = instant(t.finality_due_at);
  const acceptBy = instant(t.accept_by);
  requireFact(
    created < acceptBy && start < end && end <= created + 720n * HOUR &&
      acceptBy === (created + 72n * HOUR < start - HOUR ? created + 72n * HOUR : start - HOUR) &&
      cutoff === end + 72n * HOUR && cap === end + 720n * HOUR,
    "invalid_duel_deadlines",
  );
  requireFact(
    Array.isArray(a.participants) && a.participants.length === 2 &&
      new Set(a.participants.map((p) => p.actor_id)).size === 2,
    "invalid_duel_roster",
  );
  for (const p of a.participants) {
    requireFact(
      actors.includes(p.actor_id) && p.challenge_id === a.id &&
        p.role === (p.actor_id === t.creator_id ? "creator" : "invitee") &&
        p.accepted_at !== null && p.declined_at === null &&
        p.consent_terms_digest === a.terms_digest && p.consent_policy_version === t.policy_version,
      "duel_requires_matching_consents",
    );
    const accepted = instant(p.accepted_at);
    requireFact(
      accepted >= created && accepted < acceptBy &&
        (p.role !== "creator" || accepted === created),
      "invalid_duel_consent_time",
    );
  }
  return { actors, created, start, end, cutoff, cap };
}

function independent(reviewer: string, actors: readonly string[]) {
  requireFact(nonempty(reviewer) && !actors.includes(reviewer), "independent_reviewer_required");
}

/** Project only known fields even when a stored JSON object has extra keys. */
function finalOutcome(outcome: DuelOutcome, actors: readonly string[]): DuelOutcome {
  requireFact(outcome && typeof outcome === "object", "invalid_final_outcome");
  switch (outcome.kind) {
    case "winner":
      requireFact(
        actors.includes(outcome.winnerId) &&
          ["faster_chip", "only_finisher"].includes(outcome.reason),
        "invalid_final_outcome",
      );
      return { kind: "winner", winnerId: outcome.winnerId, reason: outcome.reason };
    case "tie":
      requireFact(outcome.reason === "equal_chip_seconds", "invalid_final_outcome");
      return { kind: "tie", reason: outcome.reason };
    case "withdrawn_no_contest":
      requireFact(outcome.reason === "participant_withdrew", "invalid_final_outcome");
      return { kind: "withdrawn_no_contest", reason: outcome.reason };
    case "void":
      requireFact(
        [
          "both_nonfinish",
          "unresolved_proof",
          "prestart_withdrawal",
          "injury",
          "event_cancelled",
          "account_deleted",
          "review_void",
          "review_timeout",
          "finality_timeout",
        ]
          .includes(outcome.reason),
        "invalid_final_outcome",
      );
      return { kind: "void", reason: outcome.reason };
    default:
      throw new DuelScoringError("invalid_final_outcome");
  }
}

function validRecord(r: DuelOfficialRecord, a: DuelScoringAgreement): boolean {
  const e = a.terms.event;
  if (r.status === "missing" || r.status === "ambiguous") return false;
  if (
    r.source !== DUEL_POLICY_V1.source || !nonempty(r.sourceReference) ||
    r.eventId !== e.id || r.course !== e.course || r.wave !== e.wave ||
    r.distanceMeters !== 5000 || r.timingBasis !== "organizer_chip" || r.precisionSeconds !== 1 ||
    r.identityConfirmed !== true || !nonempty(r.mappedBib) || r.mappedBib !== r.publishedBib
  ) return false;
  return r.status === "finished"
    ? Number.isSafeInteger(r.chipSeconds) && r.chipSeconds! > 0 &&
      BigInt(r.chipSeconds!) * MICROSECOND <= instant(e.ends_at) - instant(e.starts_at)
    : r.chipSeconds === null;
}

function compareProof(
  revision: DuelProofRevision | undefined,
  a: DuelScoringAgreement,
): DuelOutcome | null {
  if (!revision || !revision.records.every((r) => validRecord(r, a))) return null;
  const [left, right] = revision.records;
  requireFact(left && right, "invalid_proof_pair");
  if (left.mappedBib === right.mappedBib) return null;
  const finished = revision.records.filter((r) => r.status === "finished");
  if (finished.length === 0) return { kind: "void", reason: "both_nonfinish" };
  if (finished.length === 1) {
    return { kind: "winner", winnerId: finished[0]!.actorId, reason: "only_finisher" };
  }
  if (left.chipSeconds === right.chipSeconds) return { kind: "tie", reason: "equal_chip_seconds" };
  return {
    kind: "winner",
    winnerId: left.chipSeconds! < right.chipSeconds! ? left.actorId : right.actorId,
    reason: "faster_chip",
  };
}

/**
 * A decision to finalize is not a finalized result or a money-moving command.
 * The future worker must lock, recheck the input revision, and append separately.
 * A deadline is exclusive for submissions and inclusive for expiry/finality.
 */
export function evaluateDuel(input: DuelScoringInput): DuelScoringDecision {
  const a = input.agreement;
  const { actors, created, start, end, cutoff, cap } = validateAgreement(a);
  const now = instant(input.now);
  requireFact(now >= created, "clock_precedes_agreement");
  requireFact(
    Array.isArray(input.proofRevisions) && Array.isArray(input.notices) &&
      Array.isArray(input.reviews) && input.closure !== undefined &&
      input.finalResult !== undefined,
    "complete_duel_snapshot_required",
  );
  const revisions: DuelProofRevision[] = [...input.proofRevisions].sort((x, y) =>
    x.revision - y.revision
  );
  let previousTime = end;
  for (const [index, r] of revisions.entries()) {
    requireFact(
      r.revision === index + 1 && r.supersedesRevision === (index === 0 ? null : index),
      "invalid_proof_revision_chain",
    );
    const time = instant(r.recordedAt);
    requireFact(time >= previousTime && time <= now, "invalid_proof_receipt_time");
    previousTime = time;
    independent(r.reviewerId, actors);
    requireFact(
      Array.isArray(r.records) && r.records.length === 2 &&
        new Set(r.records.map((p) => p.actorId)).size === 2 &&
        r.records.every((p) => actors.includes(p.actorId)),
      "invalid_proof_pair",
    );
    requireFact(
      r.records.every((p) =>
        ["finished", "dns", "dnf", "disqualified", "missing", "ambiguous"].includes(p.status)
      ),
      "unsupported_official_status",
    );
  }

  const decision = (
    phase: DuelScoringDecision["phase"],
    outcome: DuelOutcome | null,
    proofRevision = 0,
    disputeClosesAt: string | null = null,
    reviewDueAt: string | null = null,
    supportCorrectionRequired = false,
  ): DuelScoringDecision => ({
    version: DUEL_SCORING_VERSION,
    challengeId: a.id,
    termsDigest: a.terms_digest,
    proofRevision,
    phase,
    outcome,
    disputeClosesAt,
    reviewDueAt,
    supportCorrectionRequired,
  });

  // A persisted final result is authoritative. Later proof can only request an
  // audited support case, never silently replace the result or create a debit.
  if (input.finalResult !== null) {
    const f = input.finalResult;
    const finalized = instant(f.finalizedAt);
    requireFact(
      f.version === DUEL_SCORING_VERSION && f.challengeId === a.id &&
        f.termsDigest === a.terms_digest && finalized >= created && finalized <= now &&
        Number.isInteger(f.proofRevision) && f.proofRevision >= 0 &&
        f.proofRevision <= revisions.length,
      "invalid_final_result_binding",
    );
    requireFact(
      f.proofRevision === 0 || instant(revisions[f.proofRevision - 1]!.recordedAt) <= finalized,
      "final_result_precedes_proof",
    );
    return decision(
      "final",
      finalOutcome(f.outcome, actors),
      f.proofRevision,
      null,
      null,
      revisions.some((r) => r.revision > f.proofRevision),
    );
  }

  if (input.closure !== null) {
    const c = input.closure;
    requireFact(
      ["withdrawal", "injury", "event_cancelled", "account_deleted"].includes(c.kind) &&
        (c.kind === "event_cancelled" ? c.actorId === null : actors.includes(c.actorId!)),
      "invalid_duel_closure",
    );
    const at = instant(c.recordedAt);
    requireFact(at >= created && at <= now, "invalid_duel_closure_time");
    // A delayed worker must not turn a post-cap exit into a different result.
    if (at < cap) {
      const outcome: DuelOutcome = c.kind === "withdrawal"
        ? at < start
          ? { kind: "void", reason: "prestart_withdrawal" }
          : { kind: "withdrawn_no_contest", reason: "participant_withdrew" }
        : { kind: "void", reason: c.kind };
      return decision("ready_to_finalize", outcome);
    }
  }

  const first = revisions[0];
  // Late initial results never become a proven loss. A correction requires an
  // admitted initial snapshot and must arrive strictly before the finality cap.
  const admitted = first && instant(first.recordedAt) < cutoff
    ? revisions.filter((r) => instant(r.recordedAt) < cap)
    : [];
  const latest = admitted.at(-1);
  const round = latest?.revision ?? 0;
  const result = compareProof(latest, a);
  const supportRequired = revisions.length > admitted.length;

  const noticeTimes = new Map<number, Map<string, bigint>>();
  for (const n of input.notices) {
    requireFact(
      Number.isInteger(n.proofRevision) && n.proofRevision >= 0 &&
        n.proofRevision <= admitted.length && actors.includes(n.actorId),
      "invalid_result_notice",
    );
    const r = admitted[n.proofRevision - 1];
    const earliest = r
      ? (compareProof(r, a)
        ? instant(r.recordedAt)
        : (instant(r.recordedAt) > cutoff ? instant(r.recordedAt) : cutoff))
      : cutoff;
    const at = instant(n.recordedAt);
    // A stale result must not gain a new notice after its correction exists.
    const next = admitted[n.proofRevision];
    requireFact(
      at >= earliest && at <= now && at < cap &&
        (!next || at <= instant(next.recordedAt)),
      "invalid_result_notice_time",
    );
    const pair = noticeTimes.get(n.proofRevision) ?? new Map<string, bigint>();
    requireFact(!pair.has(n.actorId), "duplicate_result_notice");
    pair.set(n.actorId, at);
    noticeTimes.set(n.proofRevision, pair);
  }
  const disputeDeadline = (revision: number): bigint | null => {
    const pair = noticeTimes.get(revision);
    if (pair?.size !== 2) return null;
    return [...pair.values()].reduce((x, y) => x > y ? x : y) + 168n * HOUR;
  };

  const ids = new Set<string>();
  let reviewDue: bigint | null = null;
  let reviewVoid = false;
  let reviewTimeout = false;
  for (const c of input.reviews) {
    requireFact(
      nonempty(c.id) && !ids.has(c.id) && actors.includes(c.filedBy),
      "invalid_review_case",
    );
    ids.add(c.id);
    const notice = noticeTimes.get(c.proofRevision)?.get(c.filedBy);
    const deadline = disputeDeadline(c.proofRevision);
    const filed = instant(c.filedAt);
    requireFact(
      notice !== undefined && filed >= notice && filed <= now && filed < cap &&
        (deadline === null || filed < deadline),
      "review_outside_filing_window",
    );
    const due = filed + 168n * HOUR;
    if (c.resolution !== null) {
      independent(c.resolution.reviewerId, actors);
      const resolved = instant(c.resolution.decidedAt);
      requireFact(
        resolved >= filed && resolved <= now && resolved < due && resolved < cap &&
          ["uphold", "void"].includes(c.resolution.decision),
        "invalid_review_resolution",
      );
      reviewVoid ||= c.resolution.decision === "void";
    } else {
      reviewTimeout ||= now >= due;
      reviewDue = reviewDue === null || due < reviewDue ? due : reviewDue;
    }
  }

  const deadline = disputeDeadline(round);
  const deadlineText = deadline === null ? null : timestamp(deadline);
  const reviewText = reviewDue === null ? null : timestamp(reviewDue);
  if (now < start) return decision("scheduled", null);
  if (now < end) return decision("active", null);
  if (now >= cap) {
    // Do not shorten a corrected result's full seven days to fit the cap.
    const resolved = deadline !== null && deadline <= cap && reviewDue === null;
    return decision(
      "ready_to_finalize",
      reviewVoid
        ? { kind: "void", reason: "review_void" }
        : reviewTimeout
        ? { kind: "void", reason: "review_timeout" }
        : resolved
        ? result ?? { kind: "void", reason: "unresolved_proof" }
        : { kind: "void", reason: "finality_timeout" },
      round,
      deadlineText,
      reviewText,
      supportRequired,
    );
  }
  if (result === null && now < cutoff) return decision("awaiting_proof", null, round);
  const outcome: DuelOutcome = reviewVoid
    ? { kind: "void", reason: "review_void" }
    : reviewTimeout
    ? { kind: "void", reason: "review_timeout" }
    : result ?? { kind: "void", reason: "unresolved_proof" };
  const canFinalize = deadline !== null && now >= deadline &&
    (reviewDue === null || reviewVoid || reviewTimeout);
  return decision(
    canFinalize ? "ready_to_finalize" : "provisional",
    outcome,
    round,
    deadlineText,
    reviewText,
    supportRequired,
  );
}
