import type { PostgrestConfig } from "../_shared/database.ts";
import { serviceRpc } from "../_shared/service_rpc.ts";
import type { DuelScoringInput } from "../_shared/duel_scoring.ts";
import type { CommitStatus, DuelLifecycleDatabase } from "./worker.ts";

/** Deliberately restricted to the explicitly selected local fictional stack. */
export function localDuelLifecycleDatabase(
  config: PostgrestConfig,
): DuelLifecycleDatabase {
  const url = new URL(config.url);
  if (
    url.protocol !== "http:" ||
    !["127.0.0.1", "localhost", "[::1]"].includes(url.hostname)
  ) {
    throw new Error("duel_lifecycle_requires_loopback");
  }
  return {
    async load(challengeId) {
      const input = await serviceRpc(config, "load_duel_lifecycle_v1", {
        p_challenge_id: challengeId,
      });
      if (input === null) return null;
      if (typeof input !== "object" || Array.isArray(input)) {
        throw new Error("duel_invalid_snapshot");
      }
      // The pure evaluator validates the complete versioned input before commit.
      return input as DuelScoringInput;
    },
    async commit(input, decision) {
      const status = await serviceRpc(config, "commit_duel_lifecycle_v1", {
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
      ) throw new Error("duel_invalid_commit_status");
      return status as CommitStatus;
    },
    settle(challengeId) {
      return serviceRpc(config, "settle_duel_simulation_v1", {
        p_challenge_id: challengeId,
      });
    },
  };
}
