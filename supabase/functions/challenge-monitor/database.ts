import type { PostgrestConfig } from "../_shared/database.ts";
import { machineRpc } from "../_shared/challenge_machine.ts";

export interface ChallengeMonitorDatabase {
  read(): Promise<unknown>;
}

export function postgrestChallengeMonitorDatabase(
  config: PostgrestConfig,
): ChallengeMonitorDatabase {
  return {
    read: () => machineRpc(config, "challenge_machine_monitor_v1", {}),
  };
}
