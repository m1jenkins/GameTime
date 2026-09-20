import { dataApiConfig, requireEnv } from "../_shared/env.ts";
import { postgrestChallengeWorkerDatabase } from "./database.ts";
import { createChallengeWorkerHandler } from "./handler.ts";

export const handler = createChallengeWorkerHandler({
  workerSecret: requireEnv("GAMETIME_CHALLENGE_WORKER_SECRET"),
  monitorSecret: requireEnv("GAMETIME_CHALLENGE_MONITOR_SECRET"),
  database: postgrestChallengeWorkerDatabase(dataApiConfig()),
});

if (import.meta.main) Deno.serve(handler);
