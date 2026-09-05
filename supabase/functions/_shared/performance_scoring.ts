/** Pure Phase 3(b) decisions over a complete private server snapshot.
 * No ambient clock, I/O, result publication, slot release or financial action.
 * Source authenticity, grants and atomic snapshots belong to the DB boundary.
 */
export const PERFORMANCE_SCORING_VERSION = "performance-fixture-official-5k-v1";
export const PERFORMANCE_POLICY_VERSION = "performance-commitment-fixture-5k-v1";
export const PERFORMANCE_POLICY_V1 = Object.freeze({
  "source": "fixture_official_5k_v1",
  "sport": "outdoor_running",
  "distance_meters": 5000,
  "timing_basis": "organizer_chip",
  "precision_ms": 1000,
  "comparator": "lt",
  "target_min_seconds": 1,
  "target_max_seconds": 86400,
  "duration_basis": "elapsed_utc",
  "minimum_duration_hours": 672,
  "maximum_duration_hours": 2160,
  "start_within_hours": 720,
  "attempt_window": "start_inclusive_finish_exclusive",
  "attempts": "multiple_nominated_events",
  "success": "any_qualifying_attempt",
  "slower_later_attempt": "does_not_undo_success",
  "milestones": "not_qualifying_proof",
  "results_after_deadline_hours": 72,
  "dispute_after_durable_notice_hours": 168,
  "review_after_filing_hours": 168,
  "finality_after_deadline_hours": 720,
  "miss": "complete_confirmed_attempt_set_or_explicit_no_attempt_acknowledgement_after_review",
  "missing_or_ambiguous_proof": "review_then_inconclusive_zero_consequence",
  "review_timeout": "inconclusive_zero_consequence",
  "corrections": "append_only_no_automatic_new_consequence",
  "prestart_cancellation": "zero_consequence",
  "withdrawal_or_injury": "zero_consequence",
  "account_deletion": "close_unfinalized_zero_consequence_retain_agreement",
  "mode": "simulated",
  "currency": "USD",
  "commitment_cents": 2000,
  "fee_cents": 0,
  "forfeiture_recipient": "unselected",
  "payee": null,
  "confirmed_miss_disposition": "simulated_loss_no_payee_no_transfer",
  "redeemable": false,
  "consent_version": "performance-commitment-simulated-consent-v1",
});
export class PerformanceScoringError extends Error {
  override name = "PerformanceScoringError";
}
function requireFact(value: unknown, message: string): asserts value {
  if (!value) throw new PerformanceScoringError(message);
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
  requireFact(
    Number.isFinite(ms) && new Date(ms).toISOString() === local,
    "invalid_instant",
  );
  const hours = Number(parts[5] ?? 0);
  const minutes = Number(parts[6] ?? 0);
  requireFact(hours <= 23 && minutes <= 59, "invalid_instant_offset");
  const offset = BigInt(hours * 60 + minutes) * 60n * MICROSECOND *
    (parts[4] === "-" ? -1n : 1n);
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

export interface PerformanceAgreement {
  id: string;
  actor_id: string;
  created_at: string;
  terms_digest: string;
  status: "open" | "cancelled" | "withdrawn";
  closed_at: string | null;
  close_reason: "cancel" | "withdrawal" | "injury" | "account_deleted" | null;
  terms: {
    agreement_version: number;
    actor_id: string;
    policy_version: string;
    policy: Record<string, unknown>;
    target_ms: number;
    starts_at: string;
    deadline_at: string;
    results_due_at: string;
    finality_due_at: string;
    display_timezone: string;
  };
  consent: {
    commitment_id: string;
    actor_id: string;
    accepted_at: string;
    policy_version: string;
    terms_digest: string;
  };
}
export interface PerformanceAttempt {
  id: string;
  commitment_id: string;
  event_id: string;
  bib: string;
  nominated_at: string;
  event: {
    id: string;
    starts_at: string;
    ends_at: string;
    source: string;
    distance_meters: number;
  };
}
export interface PerformanceRecord {
  source: string;
  event_id: string;
  distance_meters: number;
  timing_basis: string;
  precision_ms: number;
  published_bib: string | null;
  status: "finished" | "dns" | "dnf" | "disqualified" | "missing" | "ambiguous";
  chip_seconds: number | null;
  started_at: string | null;
  finished_at: string | null;
}
export interface PerformanceProofRevision {
  commitment_id: string;
  revision: number;
  attempt_id: string;
  source_id: string;
  supersedes_revision: number | null;
  reviewer_id: string;
  recorded_at: string;
  source: {
    id: string;
    commitment_id: string;
    attempt_id: string;
    captured_at: string;
    document: PerformanceRecord;
  };
}
export interface PerformanceNotice {
  proofRevision: number;
  actorId: string;
  recordedAt: string;
}
export interface PerformanceReview {
  id: string;
  proofRevision: number;
  filedBy: string;
  filedAt: string;
  resolution: {
    reviewerId: string;
    decidedAt: string;
    decision: "uphold" | "inconclusive";
  } | null;
}
export type PerformanceOutcome =
  | { kind: "success"; reason: "strict_target_met"; attemptId: string }
  | { kind: "miss"; reason: "confirmed_attempt_set" | "explicit_no_attempts" }
  | {
    kind: "inconclusive";
    reason:
      | "unresolved_proof"
      | "review_timeout"
      | "review_inconclusive"
      | "finality_timeout";
  }
  | {
    kind: "closed";
    reason: "cancel" | "withdrawal" | "injury" | "account_deleted";
  };
export interface PerformanceFinalResult {
  version: typeof PERFORMANCE_SCORING_VERSION;
  commitmentId: string;
  termsDigest: string;
  proofRevision: number;
  finalizedAt: string;
  outcome: PerformanceOutcome;
}
export interface PerformanceScoringInput {
  agreement: PerformanceAgreement;
  attempts: PerformanceAttempt[];
  confirmation: {
    commitment_id: string;
    recorded_at: string;
    kind: "complete_set" | "no_attempts";
    attempt_ids: string[];
  } | null;
  proofRevisions: PerformanceProofRevision[];
  now: string;
  // These durable lifecycle records are fixture inputs until Phase 3(e).
  notices: PerformanceNotice[];
  reviews: PerformanceReview[];
  finalResult: PerformanceFinalResult | null;
}
export interface PerformanceScoringDecision {
  version: typeof PERFORMANCE_SCORING_VERSION;
  commitmentId: string;
  termsDigest: string;
  proofRevision: number;
  phase:
    | "scheduled"
    | "active"
    | "awaiting_proof"
    | "provisional"
    | "ready_to_finalize"
    | "final";
  outcome: PerformanceOutcome | null;
  disputeClosesAt: string | null;
  reviewDueAt: string | null;
  supportCorrectionRequired: boolean;
}

/** Strict target validation is deliberately separate from agreement validation. */
function attemptResult(
  a: PerformanceAttempt,
  r: PerformanceRecord,
  target: number,
): boolean | null {
  if (
    r.source !== "fixture_official_5k_v1" || r.event_id !== a.event_id ||
    r.distance_meters !== 5000 || r.timing_basis !== "organizer_chip" ||
    r.precision_ms !== 1000 ||
    r.published_bib !== a.bib
  ) return null;
  if (["dns", "dnf", "disqualified"].includes(r.status)) {
    return r.chip_seconds === null && r.started_at === null &&
        r.finished_at === null
      ? false
      : null;
  }
  if (
    r.status !== "finished" || !Number.isInteger(r.chip_seconds) ||
    r.chip_seconds === null || r.chip_seconds <= 0 || r.chip_seconds > 86400 ||
    r.started_at === null || r.finished_at === null
  ) return null;
  const start = instant(r.started_at);
  const finish = instant(r.finished_at);
  if (
    start < instant(a.event.starts_at) || finish > instant(a.event.ends_at) ||
    finish - start !== BigInt(r.chip_seconds) * MICROSECOND
  ) return null;
  return r.chip_seconds * 1000 < target;
}

export function evaluatePerformanceCommitment(
  input: PerformanceScoringInput,
): PerformanceScoringDecision {
  const a = input.agreement;
  const t = a.terms;
  const c = a.consent;
  const created = instant(a.created_at);
  const start = instant(t.starts_at);
  const end = instant(t.deadline_at);
  const cutoff = instant(t.results_due_at);
  const cap = instant(t.finality_due_at);
  const now = instant(input.now);
  requireFact(
    nonempty(a.id) && nonempty(a.actor_id) &&
      /^[a-f0-9]{64}$/.test(a.terms_digest),
    "invalid_agreement_binding",
  );
  requireFact(
    t.agreement_version === 1 && t.actor_id === a.actor_id &&
      t.policy_version === PERFORMANCE_POLICY_VERSION &&
      Object.keys(t.policy).length ===
        Object.keys(PERFORMANCE_POLICY_V1).length &&
      Object.entries(PERFORMANCE_POLICY_V1).every(([k, v]) => t.policy[k] === v),
    "unsupported_performance_policy",
  );
  requireFact(
    Number.isInteger(t.target_ms) && t.target_ms >= 1000 &&
      t.target_ms <= 86400000 &&
      t.target_ms % 1000 === 0,
    "invalid_strict_target",
  );
  requireFact(
    start > created && start <= created + 720n * HOUR &&
      end - start >= 672n * HOUR &&
      end - start <= 2160n * HOUR && cutoff === end + 72n * HOUR &&
      cap === end + 720n * HOUR &&
      now >= created,
    "invalid_agreement_window",
  );
  requireFact(nonempty(t.display_timezone), "invalid_display_timezone");
  requireFact(
    c.commitment_id === a.id && c.actor_id === a.actor_id &&
      instant(c.accepted_at) === created &&
      c.policy_version === t.policy_version &&
      c.terms_digest === a.terms_digest,
    "invalid_owner_consent",
  );
  requireFact(
    Array.isArray(input.attempts) && input.attempts.length <= 32 &&
      Array.isArray(input.proofRevisions) &&
      Array.isArray(input.notices) && Array.isArray(input.reviews) &&
      input.confirmation !== undefined &&
      input.finalResult !== undefined,
    "complete_performance_snapshot_required",
  );
  const attempts = new Map<string, PerformanceAttempt>();
  const events = new Set<string>();
  for (const attempt of input.attempts) {
    const e = attempt.event;
    const nominated = instant(attempt.nominated_at);
    requireFact(
      nonempty(attempt.id) && !attempts.has(attempt.id) && !events.has(e.id) &&
        attempt.commitment_id === a.id && attempt.event_id === e.id &&
        nonempty(e.id) &&
        /^[A-Za-z0-9-]{1,32}$/.test(attempt.bib),
      "invalid_attempt_binding",
    );
    requireFact(
      e.source === "fixture_official_5k_v1" && e.distance_meters === 5000,
      "unsupported_attempt_event",
    );
    requireFact(
      nominated >= created && nominated <= now &&
        nominated < instant(e.starts_at) &&
        instant(e.starts_at) >= start && instant(e.starts_at) >= created &&
        instant(e.ends_at) < end &&
        instant(e.ends_at) > instant(e.starts_at) &&
        instant(e.ends_at) - instant(e.starts_at) <= 24n * HOUR,
      "invalid_nominated_window",
    );
    attempts.set(attempt.id, attempt);
    events.add(e.id);
  }
  const confirmation = input.confirmation;
  if (confirmation !== null) {
    const at = instant(confirmation.recorded_at);
    const ids = [...attempts.keys()].sort();
    requireFact(
      confirmation.commitment_id === a.id && at >= end && at < cutoff &&
        at <= now &&
        Array.isArray(confirmation.attempt_ids) &&
        JSON.stringify(confirmation.attempt_ids) === JSON.stringify(ids) &&
        confirmation.kind ===
          (ids.length === 0 ? "no_attempts" : "complete_set"),
      "invalid_attempt_confirmation",
    );
  }
  const revisions = [...input.proofRevisions].sort((x, y) => x.revision - y.revision);
  const previous = new Map<string, number>();
  const sources = new Set<string>();
  const firstAt = new Map<string, bigint>();
  let admittedRevisions = 0;
  const times = new Map<number, bigint>([[0, cutoff]]);
  const latest = new Map<string, PerformanceProofRevision>();
  let round = 0;
  let previousTime = created;
  for (const [i, r] of revisions.entries()) {
    const attempt = attempts.get(r.attempt_id);
    const s = r.source;
    const at = instant(r.recorded_at);
    requireFact(
      attempt && r.commitment_id === a.id && r.revision === i + 1 &&
        r.supersedes_revision === (previous.get(r.attempt_id) ?? null) &&
        nonempty(r.reviewer_id) &&
        r.reviewer_id !== a.actor_id && nonempty(s.id) && !sources.has(s.id) &&
        r.source_id === s.id &&
        s.commitment_id === a.id && s.attempt_id === attempt.id,
      "invalid_proof_revision_binding",
    );
    requireFact(
      instant(s.captured_at) >= instant(attempt.event.ends_at) &&
        instant(s.captured_at) <= at &&
        at >= previousTime && at <= now,
      "invalid_proof_receipt_time",
    );
    requireFact(
      ["finished", "dns", "dnf", "disqualified", "missing", "ambiguous"]
        .includes(
          s.document.status,
        ),
      "unsupported_official_status",
    );
    previous.set(attempt.id, r.revision);
    sources.add(s.id);
    previousTime = at;
    if (!firstAt.has(attempt.id)) firstAt.set(attempt.id, at);
    if (firstAt.get(attempt.id)! < cutoff && at < cap) {
      latest.set(attempt.id, r);
      admittedRevisions += 1;
      times.set(r.revision, at > cutoff ? at : cutoff);
      round = r.revision;
    }
  }
  const candidate = (
    state: Map<string, PerformanceProofRevision>,
  ): PerformanceOutcome => {
    let allMissed = attempts.size > 0;
    for (const attempt of attempts.values()) {
      const proof = state.get(attempt.id);
      const result = proof ? attemptResult(attempt, proof.source.document, t.target_ms) : null;
      if (result === true) {
        return {
          kind: "success",
          reason: "strict_target_met",
          attemptId: attempt.id,
        };
      }
      allMissed &&= result === false;
    }
    if (confirmation?.kind === "no_attempts") {
      return { kind: "miss", reason: "explicit_no_attempts" };
    }
    if (confirmation?.kind === "complete_set" && allMissed) {
      return { kind: "miss", reason: "confirmed_attempt_set" };
    }
    return { kind: "inconclusive", reason: "unresolved_proof" };
  };
  const decision = (
    phase: PerformanceScoringDecision["phase"],
    outcome: PerformanceOutcome | null,
    dispute: bigint | null = null,
    review: bigint | null = null,
    selectedRound = round,
    support = revisions.length !== admittedRevisions,
  ): PerformanceScoringDecision => ({
    version: PERFORMANCE_SCORING_VERSION,
    commitmentId: a.id,
    termsDigest: a.terms_digest,
    proofRevision: selectedRound,
    phase,
    outcome,
    disputeClosesAt: dispute === null ? null : timestamp(dispute),
    reviewDueAt: review === null ? null : timestamp(review),
    supportCorrectionRequired: support,
  });
  if (input.finalResult !== null) {
    const f = input.finalResult;
    const at = instant(f.finalizedAt);
    requireFact(
      f.version === PERFORMANCE_SCORING_VERSION && f.commitmentId === a.id &&
        f.termsDigest === a.terms_digest &&
        at >= created && at <= now && Number.isInteger(f.proofRevision) &&
        f.proofRevision >= 0 &&
        f.proofRevision <= revisions.length &&
        (f.proofRevision === 0 ||
          instant(revisions[f.proofRevision - 1]!.recorded_at) <= at),
      "invalid_final_result_binding",
    );
    const o = f.outcome;
    requireFact(
      (o.kind === "success" && o.reason === "strict_target_met" &&
        attempts.has(o.attemptId)) ||
        (o.kind === "miss" &&
          ["confirmed_attempt_set", "explicit_no_attempts"].includes(
            o.reason,
          )) ||
        (o.kind === "inconclusive" &&
          [
            "unresolved_proof",
            "review_timeout",
            "review_inconclusive",
            "finality_timeout",
          ]
            .includes(o.reason)) ||
        (o.kind === "closed" &&
          ["cancel", "withdrawal", "injury", "account_deleted"].includes(
            o.reason,
          )),
      "invalid_final_outcome",
    );
    return decision(
      "final",
      o,
      null,
      null,
      f.proofRevision,
      revisions.length > f.proofRevision,
    );
  }
  requireFact(
    ["open", "cancelled", "withdrawn"].includes(a.status) &&
      (a.status === "open") === (a.closed_at === null) &&
      (a.closed_at === null) === (a.close_reason === null),
    "invalid_agreement_closure",
  );
  if (a.closed_at !== null) {
    const at = instant(a.closed_at);
    requireFact(
      at >= created && at <= now &&
        (a.status === "cancelled" ? at < start : at >= start) &&
        ["cancel", "withdrawal", "injury", "account_deleted"].includes(
          a.close_reason!,
        ),
      "invalid_agreement_closure",
    );
    return decision("ready_to_finalize", {
      kind: "closed",
      reason: a.close_reason!,
    });
  }
  const notices = new Map<number, bigint>();
  for (const n of input.notices) {
    const at = instant(n.recordedAt);
    const earliest = times.get(n.proofRevision);
    const next = [...times.entries()].find(([r]) => r > n.proofRevision);
    requireFact(
      earliest !== undefined && !notices.has(n.proofRevision) &&
        n.actorId === a.actor_id &&
        at >= earliest && at <= now && at < cap &&
        (!next || at <= instant(revisions[next[0] - 1]!.recorded_at)),
      "invalid_result_notice",
    );
    notices.set(n.proofRevision, at);
  }
  let reviewDue: bigint | null = null;
  let timeout = false;
  let inconclusive = false;
  const caseIds = new Set<string>();
  for (const review of input.reviews) {
    const at = instant(review.filedAt);
    const notice = notices.get(review.proofRevision);
    requireFact(
      nonempty(review.id) && !caseIds.has(review.id) &&
        review.filedBy === a.actor_id &&
        notice !== undefined &&
        at >= notice && at < notice + 168n * HOUR && at < cap && at <= now,
      "invalid_review_case",
    );
    caseIds.add(review.id);
    const due = at + 168n * HOUR;
    if (review.resolution === null) {
      timeout ||= now >= due;
      reviewDue = reviewDue === null || due < reviewDue ? due : reviewDue;
    } else {
      const resolved = instant(review.resolution.decidedAt);
      requireFact(
        nonempty(review.resolution.reviewerId) &&
          review.resolution.reviewerId !== a.actor_id &&
          resolved >= at && resolved < due && resolved < cap &&
          resolved <= now &&
          ["uphold", "inconclusive"].includes(review.resolution.decision),
        "invalid_review_resolution",
      );
      inconclusive ||= review.resolution.decision === "inconclusive";
    }
  }
  const notice = notices.get(round);
  const deadline = notice === undefined ? null : notice + 168n * HOUR;
  if (now < start) return decision("scheduled", null);
  if (now < end) return decision("active", null);
  if (now < cutoff) return decision("awaiting_proof", null);
  let outcome = candidate(latest);
  if (inconclusive) {
    outcome = { kind: "inconclusive", reason: "review_inconclusive" };
  } else if (timeout) {
    outcome = { kind: "inconclusive", reason: "review_timeout" };
  }
  if (now >= cap) {
    if (
      !inconclusive && !timeout &&
      (deadline === null || deadline > cap || reviewDue !== null)
    ) {
      outcome = { kind: "inconclusive", reason: "finality_timeout" };
    }
    return decision("ready_to_finalize", outcome, deadline, reviewDue);
  }
  return decision(
    deadline !== null && now >= deadline &&
      (reviewDue === null || timeout || inconclusive)
      ? "ready_to_finalize"
      : "provisional",
    outcome,
    deadline,
    reviewDue,
  );
}
