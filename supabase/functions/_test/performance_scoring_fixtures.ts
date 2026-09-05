import {
  PERFORMANCE_POLICY_V1,
  PERFORMANCE_POLICY_VERSION,
  type PerformanceProofRevision,
  type PerformanceScoringInput,
} from "../_shared/performance_scoring.ts";

export function performanceFixture(): PerformanceScoringInput {
  const id = "commitment-one";
  const actor = "runner-one";
  const digest = "a".repeat(64);
  return {
    agreement: {
      id,
      actor_id: actor,
      created_at: "2026-10-01T12:00:00.123456Z",
      terms_digest: digest,
      status: "open",
      closed_at: null,
      close_reason: null,
      terms: {
        agreement_version: 1,
        actor_id: actor,
        policy_version: PERFORMANCE_POLICY_VERSION,
        policy: { ...PERFORMANCE_POLICY_V1 },
        target_ms: 360000,
        starts_at: "2026-10-02T12:00:00.123456Z",
        deadline_at: "2026-12-01T12:00:00.123456Z",
        results_due_at: "2026-12-04T12:00:00.123456Z",
        finality_due_at: "2026-12-31T12:00:00.123456Z",
        display_timezone: "America/Chicago",
      },
      consent: {
        commitment_id: id,
        actor_id: actor,
        accepted_at: "2026-10-01T12:00:00.123456Z",
        policy_version: PERFORMANCE_POLICY_VERSION,
        terms_digest: digest,
      },
    },
    attempts: [1, 2].map((n) => ({
      id: `attempt-${n}`,
      commitment_id: id,
      event_id: `event-${n}`,
      bib: `bib-${n}`,
      nominated_at: "2026-10-01T13:00:00.123456Z",
      event: {
        id: `event-${n}`,
        starts_at: `2026-10-0${n + 2}T12:00:00.123456Z`,
        ends_at: `2026-10-0${n + 2}T14:00:00.123456Z`,
        source: "fixture_official_5k_v1",
        distance_meters: 5000,
      },
    })),
    confirmation: null,
    proofRevisions: [],
    now: "2026-12-04T12:00:00.123456Z",
    notices: [],
    reviews: [],
    finalResult: null,
  };
}
export function proof(
  input: PerformanceScoringInput,
  attemptIndex: number,
  seconds: number,
  at = "2026-11-01T12:00:00.123456Z",
): PerformanceProofRevision {
  const attempt = input.attempts[attemptIndex]!;
  const revision = input.proofRevisions.length + 1;
  const previous = input.proofRevisions.filter((p) => p.attempt_id === attempt.id).at(-1);
  const sourceId = `source-${revision}`;
  const finish = new Date(Date.parse(attempt.event.starts_at) + seconds * 1000).toISOString()
    .replace(".123Z", ".123456Z");
  const result: PerformanceProofRevision = {
    commitment_id: input.agreement.id,
    revision,
    attempt_id: attempt.id,
    source_id: sourceId,
    supersedes_revision: previous?.revision ?? null,
    reviewer_id: "independent-reviewer",
    recorded_at: at,
    source: {
      id: sourceId,
      commitment_id: input.agreement.id,
      attempt_id: attempt.id,
      captured_at: at,
      document: {
        source: "fixture_official_5k_v1",
        event_id: attempt.event_id,
        distance_meters: 5000,
        timing_basis: "organizer_chip",
        precision_ms: 1000,
        published_bib: attempt.bib,
        status: "finished",
        chip_seconds: seconds,
        started_at: attempt.event.starts_at,
        finished_at: finish,
      },
    },
  };
  input.proofRevisions.push(result);
  return result;
}
export function confirm(input: PerformanceScoringInput) {
  input.confirmation = {
    commitment_id: input.agreement.id,
    recorded_at: input.agreement.terms.deadline_at,
    kind: input.attempts.length ? "complete_set" : "no_attempts",
    attempt_ids: input.attempts.map((a) => a.id).sort(),
  };
}
export function notice(input: PerformanceScoringInput, at = input.agreement.terms.results_due_at) {
  input.notices.push({
    proofRevision: input.proofRevisions.length,
    actorId: input.agreement.actor_id,
    recordedAt: at,
  });
}
