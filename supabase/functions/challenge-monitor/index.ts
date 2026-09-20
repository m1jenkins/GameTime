import { dataApiConfig, requireEnv } from "../_shared/env.ts";
import { postgrestChallengeMonitorDatabase } from "./database.ts";
import { createChallengeMonitorHandler } from "./handler.ts";

export const handler = createChallengeMonitorHandler({
  workerSecret: requireEnv("GAMETIME_CHALLENGE_WORKER_SECRET"),
  monitorSecret: requireEnv("GAMETIME_CHALLENGE_MONITOR_SECRET"),
  database: postgrestChallengeMonitorDatabase(dataApiConfig()),
});

if (import.meta.main) Deno.serve(handler);
