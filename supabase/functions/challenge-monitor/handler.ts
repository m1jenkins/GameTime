import {
  machineAuthorized,
  machineBody,
  machineCount,
  machineJson,
  machineRecord,
  machineState,
  machineTime,
  requireDistinctMachineSecrets,
} from "../_shared/challenge_machine.ts";
import type { ChallengeMonitorDatabase } from "./database.ts";

const MONITOR_STATES = [
  "unconfigured",
  "disabled",
  "paused",
  "unavailable",
  "empty",
  "available",
  "failed",
];
const PROCESSING_STATES = [
  "unconfigured",
  "available",
  "empty",
  "failed",
  "disabled",
  "paused",
  "failure",
  "healthy_empty",
  "healthy_backlog",
  "unavailable",
];
const HEARTBEAT_STATES = ["healthy_empty", "healthy_backlog", "paused", "disabled", "failed"];
const REVIEW_STATES = ["available", "disabled", "paused", "unavailable"];
const CAPTURE_STATES = [
  "unconfigured",
  "unavailable",
  "paused",
  "disabled",
  "enabled",
  "cohort_unavailable",
  "runtime_unavailable",
  "fixtures_disabled",
  "discovery_disabled",
  "source_unavailable",
];
const SNAPSHOT_STATES = ["unavailable", "missing", "clock_unavailable", "clock_ahead", "recorded"];
const ATTEMPT_STATES = ["none", "checked", "failed"];

export interface ChallengeMonitorDependencies {
  readonly workerSecret: string;
  readonly monitorSecret: string;
  readonly database: ChallengeMonitorDatabase;
}

function copyCount(
  source: Record<string, unknown>,
  target: Record<string, unknown>,
  key: string,
): void {
  const value = machineCount(source[key]);
  if (value !== null) target[key] = value;
}

function copyTime(
  source: Record<string, unknown>,
  target: Record<string, unknown>,
  key: string,
): void {
  const value = machineTime(source[key]);
  if (value !== null) target[key] = value;
}

function copyBoolean(
  source: Record<string, unknown>,
  target: Record<string, unknown>,
  key: string,
): void {
  if (typeof source[key] === "boolean") target[key] = source[key];
}

function workerView(value: unknown): Record<string, unknown> | null {
  const source = machineRecord(value);
  if (source === null) return null;
  const result: Record<string, unknown> = {};
  const state = machineState(source.processing_state, PROCESSING_STATES);
  if (state !== null) result.processing_state = state;
  const heartbeat = machineState(source.heartbeat_status, HEARTBEAT_STATES);
  if (heartbeat !== null) result.heartbeat_status = heartbeat;
  for (const key of ["admission_paused", "processing_paused"]) copyBoolean(source, result, key);
  for (
    const key of [
      "due_count",
      "retry_count",
      "dead_letter_count",
      "abandoned_count",
      "failed_count",
      "heartbeat_age_seconds",
      "recent_failure_count",
    ]
  ) copyCount(source, result, key);
  copyTime(source, result, "last_heartbeat_at");
  return result;
}

function reviewView(value: unknown): Record<string, unknown> | null {
  const source = machineRecord(value);
  if (source === null) return null;
  const result: Record<string, unknown> = {};
  const state = machineState(source.monitoring_state, REVIEW_STATES);
  if (state !== null) result.monitoring_state = state;
  for (
    const key of [
      "outstanding_review_count",
      "reviews_without_eligible_operator_count",
      "pending_appeal_count",
      "appeals_without_eligible_operator_count",
    ]
  ) copyCount(source, result, key);
  for (
    const key of [
      "earliest_review_resolve_by",
      "next_review_grant_expires_at",
      "oldest_pending_appeal_at",
      "next_appeal_grant_expires_at",
    ]
  ) copyTime(source, result, key);
  return result;
}

function snapshotView(value: unknown): Record<string, unknown> | null {
  const source = machineRecord(value);
  if (source === null) return null;
  const result: Record<string, unknown> = {};
  const capture = machineState(source.capture_state, CAPTURE_STATES);
  if (capture !== null) result.capture_state = capture;
  const state = machineState(source.snapshot_state, SNAPSHOT_STATES);
  if (state !== null) result.snapshot_state = state;
  const attempt = machineState(source.last_attempt_state, ATTEMPT_STATES);
  if (attempt !== null) result.last_attempt_state = attempt;
  for (
    const key of [
      "last_capture_at",
      "last_prepared_wall_at",
      "last_attempt_wall_at",
      "last_successful_invocation_wall_at",
    ]
  ) copyTime(source, result, key);
  copyCount(source, result, "capture_age_seconds");
  return result;
}

function monitorView(value: unknown): Record<string, unknown> | null {
  const source = machineRecord(value);
  const state = machineState(source?.state, MONITOR_STATES);
  if (source === null || state === null) return null;
  return {
    state,
    ...(machineTime(source.observed_at) === null ? {} : { observed_at: source.observed_at }),
    worker: workerView(source.worker),
    reviews: reviewView(source.reviews),
    snapshot: snapshotView(source.snapshot),
  };
}

export function createChallengeMonitorHandler(
  deps: ChallengeMonitorDependencies,
): (request: Request) => Promise<Response> {
  requireDistinctMachineSecrets(deps.workerSecret, deps.monitorSecret);
  return async (request) => {
    if (request.method !== "POST") return machineJson(405, { error: "method_not_allowed" });
    if (!machineAuthorized(request, "x-gametime-monitor-secret", deps.monitorSecret)) {
      return machineJson(401, { error: "unauthorized" });
    }
    const body = await machineBody(request, "monitor");
    if (body === null) return machineJson(400, { error: "bad_request" });
    try {
      const result = monitorView(await deps.database.read());
      return result === null
        ? machineJson(503, { state: "unavailable" })
        : machineJson(200, result);
    } catch {
      return machineJson(503, { state: "unavailable" });
    }
  };
}
