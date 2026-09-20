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
import type { ChallengeSnapshotDatabase } from "./database.ts";

const STATES = [
  "checked",
  "busy",
  "paused",
  "disabled",
  "unavailable",
  "unconfigured",
  "failed",
  "empty",
];
const CAPTURE_STATES = [
  "enabled",
  "cohort_unavailable",
  "runtime_unavailable",
  "fixtures_disabled",
  "discovery_disabled",
  "source_unavailable",
];

export interface ChallengeSnapshotDependencies {
  readonly workerSecret: string;
  readonly monitorSecret: string;
  readonly database: ChallengeSnapshotDatabase;
}

export function createChallengeSnapshotHandler(
  deps: ChallengeSnapshotDependencies,
): (request: Request) => Promise<Response> {
  requireDistinctMachineSecrets(deps.workerSecret, deps.monitorSecret);
  return async (request) => {
    if (request.method !== "POST") return machineJson(405, { error: "method_not_allowed" });
    if (!machineAuthorized(request, "x-gametime-worker-secret", deps.workerSecret)) {
      return machineJson(401, { error: "unauthorized" });
    }
    const body = await machineBody(request, "invocation");
    if (!body || !("invocationId" in body)) return machineJson(400, { error: "bad_request" });
    try {
      const result = machineRecord(await deps.database.dispatch(body.invocationId));
      const status = machineState(result?.status, STATES);
      if (!result || status === null) return machineJson(503, { status: "unavailable" });
      // "checked" means the invocation ran, not that a fresh capture exists.
      return machineJson(200, {
        status,
        ...(machineTime(result.server_time) === null ? {} : { server_time: result.server_time }),
        ...(machineTime(result.last_capture_at) === null
          ? {}
          : { last_capture_at: result.last_capture_at }),
        ...(machineCount(result.capture_age_seconds) === null
          ? {}
          : { capture_age_seconds: result.capture_age_seconds }),
        ...(machineTime(result.last_successful_invocation_wall_at) === null
          ? {}
          : { last_successful_invocation_wall_at: result.last_successful_invocation_wall_at }),
        ...(machineState(result.capture_state, CAPTURE_STATES) === null
          ? {}
          : { capture_state: result.capture_state }),
      });
    } catch {
      return machineJson(503, { status: "unavailable" });
    }
  };
}
