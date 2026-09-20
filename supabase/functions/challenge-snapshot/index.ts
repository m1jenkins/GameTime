import { dataApiConfig, requireEnv } from "../_shared/env.ts";
import { postgrestChallengeSnapshotDatabase } from "./database.ts";
import { createChallengeSnapshotHandler } from "./handler.ts";

export const handler = createChallengeSnapshotHandler({
  workerSecret: requireEnv("GAMETIME_CHALLENGE_WORKER_SECRET"),
  monitorSecret: requireEnv("GAMETIME_CHALLENGE_MONITOR_SECRET"),
  database: postgrestChallengeSnapshotDatabase(dataApiConfig()),
});

if (import.meta.main) Deno.serve(handler);
