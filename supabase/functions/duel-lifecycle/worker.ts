/** Local-only operational orchestration. No HTTP handler, schedule or push delivery.
 * The database samples time after locks; private SQL clock seams inject test time.
 */
import { evaluateDuel } from "../_shared/duel_scoring.ts";
import type { DuelScoringDecision, DuelScoringInput } from "../_shared/duel_scoring.ts";

export type CommitStatus = DuelScoringDecision["phase"] | "stale";
export interface DuelLifecycleDatabase {
  load(challengeId: string): Promise<DuelScoringInput | null>;
  commit(
    input: DuelScoringInput,
    decision: DuelScoringDecision,
  ): Promise<CommitStatus>;
  settle(challengeId: string): Promise<unknown>;
}

/** Bounded optimistic retry. A later run safely resumes after any failed call. */
export async function runDuelLifecycle(
  database: DuelLifecycleDatabase,
  challengeId: string,
): Promise<CommitStatus | "inactive"> {
  for (let attempt = 0; attempt < 4; attempt++) {
    const input = await database.load(challengeId);
    if (input === null) return "inactive";
    if (input.agreement.id !== challengeId) {
      throw new Error("duel_snapshot_identity_mismatch");
    }
    const decision = evaluateDuel(input);
    const status = await database.commit(input, decision);
    if (status === "stale") continue;
    if (status === "final") await database.settle(challengeId);
    return status;
  }
  return "stale";
}
