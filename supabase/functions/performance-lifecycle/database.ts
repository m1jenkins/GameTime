import type { PostgrestConfig } from "../_shared/database.ts";
import { serviceRpc } from "../_shared/service_rpc.ts";
import type { PerformanceScoringInput } from "../_shared/performance_scoring.ts";
import type { CommitStatus, PerformanceLifecycleDatabase } from "./worker.ts";

/** Deliberately restricted to the explicitly selected local fictional stack. */
export function localPerformanceLifecycleDatabase(
  config: PostgrestConfig,
): PerformanceLifecycleDatabase {
  const url = new URL(config.url);
  if (
    url.protocol !== "http:" ||
    !["127.0.0.1", "localhost", "[::1]"].includes(url.hostname)
  ) {
    throw new Error("performance_lifecycle_requires_loopback");
  }
  return {
    async load(commitmentId) {
      const input = await serviceRpc(config, "load_commitment_lifecycle_v1", {
        p_commitment_id: commitmentId,
      });
      if (input === null) return null;
      if (typeof input !== "object" || Array.isArray(input)) {
        throw new Error("performance_invalid_snapshot");
      }
      // The pure evaluator validates the complete versioned input before commit.
      return input as PerformanceScoringInput;
    },
    async commit(input, decision) {
      const status = await serviceRpc(config, "commit_commitment_lifecycle_v1", {
        p_input: input,
        p_decision: decision,
      });
      if (
        typeof status !== "string" || ![
          "stale",
          "scheduled",
          "active",
          "awaiting_proof",
          "provisional",
          "ready_to_finalize",
          "final",
        ].includes(status)
      ) throw new Error("performance_invalid_commit_status");
      return status as CommitStatus;
    },
    settle(commitmentId) {
      return serviceRpc(config, "settle_commitment_simulation_v1", {
        p_commitment_id: commitmentId,
      });
    },
  };
}
