/** Manual local runner; never registers a schedule or sends external notices.
 * Supply PERFORMANCE_LOCAL_SERVICE_ROLE_KEY from the explicitly selected local stack.
 * Run with --config supabase/functions/deno.json and allow only local network.
 */
import { localPerformanceLifecycleDatabase } from "../supabase/functions/performance-lifecycle/database.ts";
import { runPerformanceLifecycle } from "../supabase/functions/performance-lifecycle/worker.ts";

if (
  Deno.args.length < 1 || Deno.args.length > 100 ||
  Deno.args.some((id) => !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(id))
) {
  throw new Error("Pass between 1 and 100 explicit fictional performance UUIDs.");
}
const serviceRoleKey = Deno.env.get("PERFORMANCE_LOCAL_SERVICE_ROLE_KEY");
if (!serviceRoleKey) {
  throw new Error(
    "Set PERFORMANCE_LOCAL_SERVICE_ROLE_KEY for the selected local stack.",
  );
}
const database = localPerformanceLifecycleDatabase({
  url: Deno.env.get("PERFORMANCE_LOCAL_URL") ?? "http://127.0.0.1:54321",
  serviceRoleKey,
});
let failed = false;
for (const id of new Set(Deno.args)) {
  try {
    const status = await runPerformanceLifecycle(database, id);
    console.log(JSON.stringify({ commitmentId: id, status }));
    failed ||= status === "stale";
  } catch (error) {
    failed = true;
    console.error(JSON.stringify({
      commitmentId: id,
      error: error instanceof Error ? error.message : "performance_worker_failed",
    }));
  }
}
if (failed) Deno.exit(1);
