import type { PostgrestConfig } from "../_shared/database.ts";
import { machineRpc } from "../_shared/challenge_machine.ts";

export interface ChallengeSnapshotDatabase {
  dispatch(invocationId: string): Promise<unknown>;
}

export function postgrestChallengeSnapshotDatabase(
  config: PostgrestConfig,
): ChallengeSnapshotDatabase {
  return {
    dispatch: (invocationId) =>
      machineRpc(
        config,
        "challenge_machine_snapshot_dispatch_v1",
        { p_invocation_id: invocationId },
      ),
  };
}
