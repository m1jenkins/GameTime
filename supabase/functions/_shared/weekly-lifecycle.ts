/** Fictional local orchestration only. No endpoint, scheduler, delivery or live source. */
import {
  evaluateWeeklyParticipant,
  evaluateWeeklySteps,
  type WeeklyStepsAgreement,
  type WeeklyStepsConsent,
  weeklyStepsConsentBinding,
  type WeeklyStepsDay,
  type WeeklyStepsRevision,
} from "./weekly-steps.ts";

interface Participant {
  actor_id: string;
  target_steps: number;
  accepted_at: string | null;
  exited_at: string | null;
}
interface Qualification {
  participantId: string;
  qualification: "met" | "confirmed_miss" | "unresolved" | "refund";
}
interface Notice {
  revision: number;
  source_count: number;
  recorded_at: string;
  file_by: string;
  resolve_by: string;
  qualifications: Qualification[];
}
interface ReviewCase {
  id: string;
  actor_id: string;
  notice_revision: number;
  resolution: null | { decision: "upheld" | "void"; recorded_at: string };
}
export interface WeeklyLifecycleInput {
  agreement: WeeklyStepsAgreement;
  mode: "friend" | "community";
  version: number;
  status: string;
  joinBy: string;
  capacity: number;
  now: string;
  participants: Participant[];
  consents: WeeklyStepsConsent[];
  revisions: WeeklyStepsRevision[];
  notices: Notice[];
  cases: ReviewCase[];
  exits: { actor_id: string; kind: string; recorded_at: string }[];
  result: null | { qualifications: Qualification[]; reason: string; recorded_at: string };
}
export interface WeeklyLifecycleDecision {
  version: "weekly-lifecycle-v1";
  agreementId: string;
  termsDigest: string;
  phase: "scheduled" | "active" | "awaiting_observations" | "review" | "notice" | "final";
  qualifications: Qualification[];
  reason: string;
}
function micro(value: string): bigint {
  const match = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,6}))?(Z|[+-]\d{2}:\d{2})$/.exec(
    value,
  );
  if (!match) throw new Error("weekly_invalid_instant");
  const ms = Date.parse(`${match[1]}${match[3]}`);
  if (!Number.isFinite(ms)) throw new Error("weekly_invalid_instant");
  return BigInt(ms) * 1000n + BigInt((match[2] ?? "").padEnd(6, "0"));
}

/** The DB supplies a complete private snapshot; untrusted clients cannot call commit. */
export function evaluateWeeklyLifecycle(input: WeeklyLifecycleInput): WeeklyLifecycleDecision {
  const terms = input.agreement.terms;
  const now = micro(input.now);
  const accepted = input.participants.filter((p) => p.accepted_at !== null);
  const decision = (
    phase: WeeklyLifecycleDecision["phase"],
    reason: string,
    qualifications: Qualification[] = [],
  ): WeeklyLifecycleDecision => ({
    version: "weekly-lifecycle-v1",
    agreementId: input.agreement.id,
    termsDigest: input.agreement.termsDigest,
    phase,
    qualifications,
    reason,
  });
  const refunds = accepted.map((p): Qualification => ({
    participantId: p.actor_id,
    qualification: "refund",
  }));
  if (input.result) return decision("final", input.result.reason, input.result.qualifications);
  if (input.mode === "friend" && (input.exits.length > 0 || input.status === "closed")) {
    return decision("final", "safe_group_exit", refunds);
  }
  if (now < micro(input.joinBy)) return decision("scheduled", "acceptance_open");
  if (
    (input.mode === "friend" && accepted.length !== input.capacity) ||
    (input.mode === "community" &&
      accepted.filter((p) => p.exited_at === null || micro(p.exited_at) >= micro(input.joinBy))
          .length < 2 &&
      input.notices.length === 0)
  ) return decision("final", "minimum_or_consent_missing", refunds);
  if (now < micro(terms.startsAt)) return decision("scheduled", "waiting_for_week");
  if (now < micro(terms.endsAt)) return decision("active", "week_open");
  if (now <= micro(terms.uploadClosesAt)) {
    return decision("awaiting_observations", "upload_window_open");
  }
  const latest = input.notices.at(-1);
  const needsNotice = !latest || latest.source_count !== input.revisions.length;
  if (needsNotice && now > micro(terms.lifecycle.noticeBy)) {
    return decision("final", "notice_window_unavailable", refunds);
  }
  let qualifications: Qualification[];
  if (input.mode === "friend") {
    const evaluated = evaluateWeeklySteps({
      agreement: input.agreement,
      consents: input.consents,
      revisions: input.revisions,
      now: input.now,
    });
    qualifications = evaluated.participants.map((p) => ({
      participantId: p.participantId,
      qualification: p.qualification === "pending" ? "unresolved" : p.qualification,
    }));
  } else {
    // Community has an independently frozen service-owned target/capacity. SQL
    // validates calendar, identical target and exact consent; shared helper
    // rechecks participant/source/revision boundaries without widening W1A.
    const community = terms as unknown as {
      commonTargetSteps: number;
      policy: { version: string };
      days: WeeklyStepsDay[];
    };
    if (
      community.policy.version !== "weekly-community-steps-fixture-v1" ||
      !Number.isSafeInteger(community.commonTargetSteps) || community.commonTargetSteps < 1 ||
      community.commonTargetSteps > 1_000_000 || input.capacity < 2 || input.capacity > 30 ||
      accepted.length > input.capacity ||
      new Set(accepted.map((p) => p.actor_id)).size !== accepted.length
    ) throw new Error("weekly_community_contract_mismatch");
    qualifications = accepted.map((p) => {
      if (p.target_steps !== community.commonTargetSteps) {
        throw new Error("weekly_community_target_mismatch");
      }
      const consent = input.consents.filter((c) => c.participantId === p.actor_id);
      if (
        consent.length !== 1 || consent[0]?.agreementId !== input.agreement.id ||
        consent[0]?.termsDigest !== input.agreement.termsDigest ||
        consent[0]?.policyVersion !== community.policy.version ||
        consent[0]?.termsBinding !== weeklyStepsConsentBinding(terms) ||
        micro(consent[0].acceptedAt) < micro(terms.createdAt) ||
        micro(consent[0].acceptedAt) > now ||
        micro(consent[0].acceptedAt) >= micro(input.joinBy)
      ) throw new Error("weekly_community_consent_mismatch");
      const value = evaluateWeeklyParticipant({
        agreementId: input.agreement.id,
        termsDigest: input.agreement.termsDigest,
        policyVersion: community.policy.version,
        participantId: p.actor_id,
        targetSteps: p.target_steps,
        days: community.days,
        revisions: input.revisions.filter((r) => r.participantId === p.actor_id),
        now: input.now,
        uploadClosesAt: terms.uploadClosesAt,
        correctionsCloseAt: terms.correctionsCloseAt,
      });
      return {
        participantId: p.actor_id,
        qualification: p.exited_at !== null
          ? "refund"
          : value.qualification === "pending"
          ? "unresolved"
          : value.qualification,
      };
    });
  }
  if (needsNotice) return decision("notice", "saved_provisional", qualifications);
  if (now <= micro(terms.correctionsCloseAt)) return decision("review", "corrections_open");
  if (input.notices.some((n) => now < micro(n.file_by))) {
    return decision("review", "filing_window_open");
  }
  const unresolved = input.cases.filter((k) => k.resolution === null);
  if (
    unresolved.some((k) => {
      const notice = input.notices.find((n) => n.revision === k.notice_revision);
      if (!notice) throw new Error("weekly_case_notice_missing");
      return now < micro(notice.resolve_by);
    })
  ) return decision("review", "independent_review_open");
  const refundActors = new Set([
    ...input.exits.map((x) => x.actor_id),
    ...input.cases.filter((k) => k.resolution?.decision === "void" || k.resolution === null)
      .map((k) => k.actor_id),
  ]);
  qualifications = qualifications.map((q) =>
    refundActors.has(q.participantId) || q.qualification === "unresolved"
      ? { ...q, qualification: "refund" }
      : q
  );
  if (input.mode === "friend" && qualifications.some((q) => q.qualification === "refund")) {
    return decision("final", "unresolved_group_refund", refunds);
  }
  return decision("final", "review_complete", qualifications);
}

export interface WeeklyLifecycleDatabase {
  load(id: string): Promise<WeeklyLifecycleInput | null>;
  commit(input: WeeklyLifecycleInput, decision: WeeklyLifecycleDecision): Promise<string>;
  settle(id: string): Promise<unknown>;
}
export async function runWeeklyLifecycle(
  database: WeeklyLifecycleDatabase,
  id: string,
): Promise<string> {
  for (let attempt = 0; attempt < 4; attempt++) {
    const input = await database.load(id);
    if (!input) return "inactive";
    if (input.agreement.id !== id) throw new Error("weekly_snapshot_identity_mismatch");
    const decision = evaluateWeeklyLifecycle(input);
    const result = await database.commit(input, decision);
    if (result === "stale") continue;
    if (result === "final") await database.settle(id);
    return result;
  }
  return "stale";
}
