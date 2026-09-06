/** Explicit-ID, loopback-only fictional worker. Never installs a schedule. */
import {
  runWeeklyLifecycle,
  type WeeklyLifecycleDatabase,
} from "../supabase/functions/_shared/weekly-lifecycle.ts";

const base = new URL(
  Deno.env.get("WEEKLY_LOCAL_URL") ?? "http://127.0.0.1:56321",
);
if (
  base.protocol !== "http:" ||
  !["127.0.0.1", "[::1]", "localhost"].includes(base.hostname) ||
  base.username || base.password || base.pathname !== "/" || base.search ||
  base.hash
) throw new Error("weekly_loopback_required");
const key = Deno.env.get("WEEKLY_LOCAL_SERVICE_ROLE_KEY");
if (!key) throw new Error("weekly_local_service_key_required");
if (
  Deno.args.length < 1 || Deno.args.length > 100 ||
  Deno.args.some((id) => !/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(id))
) throw new Error("Expected 1–100 explicit fictional weekly UUIDs");
async function rpc<T>(name: string, args: Record<string, unknown>): Promise<T> {
  const response = await fetch(new URL(`/rest/v1/rpc/${name}`, base), {
    method: "POST",
    redirect: "error",
    headers: {
      "Content-Type": "application/json",
      apikey: key!,
      Authorization: `Bearer ${key}`,
    },
    body: JSON.stringify(args),
    signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) {
    throw new Error(`weekly_rpc_failed:${name}:${response.status}`);
  }
  return await response.json() as T;
}
const database: WeeklyLifecycleDatabase = {
  load: (id) => rpc("load_weekly_lifecycle_v1", { p_challenge_id: id }),
  commit: (input, decision) =>
    rpc("commit_weekly_lifecycle_v1", { p_input: input, p_decision: decision }),
  settle: (id) => rpc("settle_weekly_simulation_v1", { p_challenge_id: id }),
};
let failed = false;
for (const id of new Set(Deno.args)) {
  try {
    const phase = await runWeeklyLifecycle(database, id);
    console.log(`${id}: ${phase}`);
    if (phase === "stale") failed = true;
  } catch (error) {
    failed = true;
    console.error(
      `${id}: ${error instanceof Error ? error.message : "weekly_worker_failed"}`,
    );
  }
}
if (failed) Deno.exitCode = 1;
