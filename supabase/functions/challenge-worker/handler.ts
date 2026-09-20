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
import type { ChallengeWorkerDatabase } from "./database.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const WORKER_PASS_MS = 50_000;
const MAX_CLAIMS = 20;
const LANES = 5;
const STATES = [
  "running",
  "busy",
  "completed",
  "paused",
  "disabled",
  "unavailable",
  "unconfigured",
  "failed",
  "empty",
  "pending",
] as const;

interface Claim {
  readonly id: string;
  readonly claimToken: string;
}

export interface ChallengeWorkerDependencies {
  readonly workerSecret: string;
  readonly monitorSecret: string;
  readonly database: ChallengeWorkerDatabase;
  readonly runToken?: () => string;
}

function claimsFrom(value: unknown): Claim[] | null {
  if (!Array.isArray(value) || value.length > MAX_CLAIMS) return null;
  const claims: Claim[] = [];
  for (const item of value) {
    const record = machineRecord(item);
    if (
      !record || typeof record.id !== "string" || !UUID.test(record.id) ||
      typeof record.claim_token !== "string" || !UUID.test(record.claim_token)
    ) return null;
    claims.push({ id: record.id, claimToken: record.claim_token });
  }
  return claims;
}

function safeResult(value: unknown): Record<string, unknown> | null {
  const record = machineRecord(value);
  const status = machineState(record?.status, STATES);
  if (!record || status === null) return null;
  return {
    status,
    ...(machineCount(record.completed_count, MAX_CLAIMS) === null ? {} : {
      completed_count: record.completed_count,
    }),
    ...(machineCount(record.failed_count, MAX_CLAIMS) === null ? {} : {
      failed_count: record.failed_count,
    }),
    ...(machineCount(record.pending_count, MAX_CLAIMS) === null ? {} : {
      pending_count: record.pending_count,
    }),
    ...(machineTime(record.server_time) === null ? {} : { server_time: record.server_time }),
  };
}

export function createChallengeWorkerHandler(
  deps: ChallengeWorkerDependencies,
): (request: Request) => Promise<Response> {
  requireDistinctMachineSecrets(deps.workerSecret, deps.monitorSecret);
  return async (request) => {
    if (request.method !== "POST") return machineJson(405, { error: "method_not_allowed" });
    if (!machineAuthorized(request, "x-gametime-worker-secret", deps.workerSecret)) {
      return machineJson(401, { error: "unauthorized" });
    }
    const body = await machineBody(request, "invocation");
    if (!body || !("invocationId" in body)) return machineJson(400, { error: "bad_request" });

    const runToken = deps.runToken?.() ?? crypto.randomUUID();
    if (!UUID.test(runToken)) return machineJson(503, { status: "unavailable" });
    const deadlineAt = Date.now() + WORKER_PASS_MS;
    let dispatched: Record<string, unknown> | null;
    try {
      dispatched = machineRecord(
        await deps.database.dispatch(body.invocationId, runToken, deadlineAt),
      );
    } catch {
      return machineJson(503, { status: "unavailable", error_categories: ["dispatch"] });
    }
    const dispatchStatus = machineState(dispatched?.status, STATES);
    if (!dispatched || dispatchStatus === null) {
      return machineJson(503, { status: "unavailable", error_categories: ["response"] });
    }
    if (dispatchStatus === "completed") {
      const saved = safeResult(dispatched.result);
      return saved === null
        ? machineJson(503, { status: "unavailable", error_categories: ["response"] })
        : machineJson(200, saved);
    }
    if (dispatchStatus !== "running") {
      const safe = safeResult(dispatched);
      return safe === null
        ? machineJson(503, { status: "unavailable", error_categories: ["response"] })
        : machineJson(200, safe);
    }
    const claims = claimsFrom(dispatched.claims);
    if (claims === null) {
      return machineJson(503, { status: "unavailable", error_categories: ["response"] });
    }

    let next = 0;
    let transportFailures = 0;
    const lane = async () => {
      while (next < claims.length && Date.now() < deadlineAt) {
        const claim = claims[next++];
        if (!claim) break;
        try {
          await deps.database.complete(
            body.invocationId,
            runToken,
            claim.id,
            claim.claimToken,
            deadlineAt,
          );
        } catch {
          // The durable receipt, not this HTTP response, decides whether an
          // exact completion retry was already applied.
          transportFailures += 1;
        }
      }
    };
    await Promise.all(Array.from({ length: Math.min(LANES, claims.length) }, () => lane()));
    if (Date.now() >= deadlineAt) {
      return machineJson(503, { status: "unavailable", error_categories: ["timeout"] });
    }
    try {
      const finished = safeResult(
        await deps.database.finish(body.invocationId, runToken, deadlineAt),
      );
      if (finished === null) {
        return machineJson(503, { status: "unavailable", error_categories: ["response"] });
      }
      return machineJson(200, {
        ...finished,
        ...(transportFailures > 0 ? { error_categories: ["completion_transport"] } : {}),
      });
    } catch {
      return machineJson(503, { status: "unavailable", error_categories: ["finish"] });
    }
  };
}
