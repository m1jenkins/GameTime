/** Manual local runner; never registers a schedule or sends external notices.
 * Supply DUEL_LOCAL_SERVICE_ROLE_KEY from the explicitly selected local stack.
 * Run with --config supabase/functions/deno.json and allow only local network.
 */
import { localDuelLifecycleDatabase } from "../supabase/functions/duel-lifecycle/database.ts";
import { runDuelLifecycle } from "../supabase/functions/duel-lifecycle/worker.ts";

if (
  Deno.args.length < 1 || Deno.args.length > 100 ||
  Deno.args.some((id) =>
    !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(id)
  )
) {
  throw new Error("Pass between 1 and 100 explicit fictional duel UUIDs.");
}
const serviceRoleKey = Deno.env.get("DUEL_LOCAL_SERVICE_ROLE_KEY");
if (!serviceRoleKey) {
  throw new Error(
    "Set DUEL_LOCAL_SERVICE_ROLE_KEY for the selected local stack.",
  );
}
const database = localDuelLifecycleDatabase({
  url: Deno.env.get("DUEL_LOCAL_URL") ?? "http://127.0.0.1:54321",
  serviceRoleKey,
});
let failed = false;
for (const id of new Set(Deno.args)) {
  try {
    const status = await runDuelLifecycle(database, id);
    console.log(JSON.stringify({ challengeId: id, status }));
    failed ||= status === "stale";
  } catch (error) {
    failed = true;
    console.error(JSON.stringify({
      challengeId: id,
      error: error instanceof Error ? error.message : "duel_worker_failed",
    }));
  }
}
if (failed) Deno.exit(1);
