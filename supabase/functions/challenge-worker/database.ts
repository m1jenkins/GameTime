import type { PostgrestConfig } from "../_shared/database.ts";
import { machineRpc } from "../_shared/challenge_machine.ts";

export interface ChallengeWorkerDatabase {
  dispatch(invocationId: string, runToken: string, deadlineAt: number): Promise<unknown>;
  complete(
    invocationId: string,
    runToken: string,
    challengeId: string,
    claimToken: string,
    deadlineAt: number,
  ): Promise<unknown>;
  finish(invocationId: string, runToken: string, deadlineAt: number): Promise<unknown>;
}

export function postgrestChallengeWorkerDatabase(
  config: PostgrestConfig,
  fetcher: typeof fetch = fetch,
): ChallengeWorkerDatabase {
  return {
    dispatch: (invocationId, runToken, deadlineAt) =>
      machineRpc(
        config,
        "challenge_machine_worker_dispatch_v1",
        {
          p_invocation_id: invocationId,
          p_run_token: runToken,
        },
        fetcher,
        deadlineAt,
      ),
    complete: (invocationId, runToken, challengeId, claimToken, deadlineAt) =>
      machineRpc(
        config,
        "challenge_machine_complete_v1",
        {
          p_invocation_id: invocationId,
          p_run_token: runToken,
          p_id: challengeId,
          p_claim_token: claimToken,
        },
        fetcher,
        deadlineAt,
      ),
    finish: (invocationId, runToken, deadlineAt) =>
      machineRpc(
        config,
        "challenge_machine_finish_v1",
        {
          p_invocation_id: invocationId,
          p_run_token: runToken,
        },
        fetcher,
        deadlineAt,
      ),
  };
}
