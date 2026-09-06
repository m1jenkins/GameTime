/** Local-only operational orchestration. No HTTP handler, schedule or push delivery.
 * The database samples time after locks; private SQL clock seams inject test time.
 */
import { evaluatePerformanceCommitment } from "../_shared/performance_scoring.ts";
import type {
  PerformanceScoringDecision,
  PerformanceScoringInput,
} from "../_shared/performance_scoring.ts";

export type CommitStatus = PerformanceScoringDecision["phase"] | "stale";
export interface PerformanceLifecycleDatabase {
  load(commitmentId: string): Promise<PerformanceScoringInput | null>;
  commit(
    input: PerformanceScoringInput,
    decision: PerformanceScoringDecision,
  ): Promise<CommitStatus>;
  settle(commitmentId: string): Promise<unknown>;
}

/** Bounded optimistic retry. A later run safely resumes after any failed call. */
export async function runPerformanceLifecycle(
  database: PerformanceLifecycleDatabase,
  commitmentId: string,
): Promise<CommitStatus | "inactive"> {
  for (let attempt = 0; attempt < 4; attempt++) {
    const input = await database.load(commitmentId);
    if (input === null) return "inactive";
    if (input.agreement.id !== commitmentId) {
      throw new Error("performance_snapshot_identity_mismatch");
    }
    const decision = evaluatePerformanceCommitment(input);
    const status = await database.commit(input, decision);
    if (status === "stale") continue;
    if (status === "final") await database.settle(commitmentId);
    return status;
  }
  return "stale";
}
