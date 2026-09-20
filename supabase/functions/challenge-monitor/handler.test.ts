import { assertEquals, assertThrows } from "@std/assert";
import { createChallengeMonitorHandler } from "./handler.ts";
import type { ChallengeMonitorDatabase } from "./database.ts";

const WORKER = "worker-secret-long-enough-for-local-tests-123";
const MONITOR = "monitor-secret-long-enough-for-local-tests-456";

function request(body: unknown, secret = MONITOR): Request {
  return new Request("http://localhost/challenge-monitor", {
    method: "POST",
    headers: { "content-type": "application/json", "x-gametime-monitor-secret": secret },
    body: JSON.stringify(body),
  });
}

Deno.test("monitor is read-only, rejects caller scope, and strips identities and people counts", async () => {
  let reads = 0;
  const handler = createChallengeMonitorHandler({
    workerSecret: WORKER,
    monitorSecret: MONITOR,
    database: {
      read: () => {
        reads++;
        return Promise.resolve({
          state: "paused",
          observed_at: "2026-09-20T10:00:00Z",
          cohort_id: "private",
          worker: {
            processing_state: "paused",
            due_count: 4,
            processing_paused: true,
            failure_codes: [{ code: "secret" }],
          },
          reviews: { monitoring_state: "paused", outstanding_review_count: 2, actor_id: "private" },
          snapshot: { snapshot_state: "missing", capture_state: "enabled", member_count: 3 },
        });
      },
    },
  });
  assertEquals((await handler(request({}, WORKER))).status, 401);
  assertEquals((await handler(request({ rpc: "challenge_recover_failed_item_v1" }))).status, 400);
  assertEquals((await handler(request({ cohort_id: "other" }))).status, 400);
  assertEquals(reads, 0);
  const response = await handler(request({}));
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    state: "paused",
    observed_at: "2026-09-20T10:00:00Z",
    worker: { processing_state: "paused", due_count: 4, processing_paused: true },
    reviews: { monitoring_state: "paused", outstanding_review_count: 2 },
    snapshot: { snapshot_state: "missing", capture_state: "enabled" },
  });
  assertEquals(reads, 1);
  assertThrows(() =>
    createChallengeMonitorHandler({
      workerSecret: WORKER,
      monitorSecret: WORKER,
      database: {} as ChallengeMonitorDatabase,
    })
  );
});

Deno.test("monitor preserves an explicitly unconfigured worker state", async () => {
  const handler = createChallengeMonitorHandler({
    workerSecret: WORKER,
    monitorSecret: MONITOR,
    database: {
      read: () =>
        Promise.resolve({
          state: "unconfigured",
          worker: { processing_state: "unconfigured", due_count: 0 },
          reviews: { monitoring_state: "unavailable" },
          snapshot: { capture_state: "unconfigured", snapshot_state: "unavailable" },
        }),
    },
  });
  assertEquals(await (await handler(request({}))).json(), {
    state: "unconfigured",
    worker: { processing_state: "unconfigured", due_count: 0 },
    reviews: { monitoring_state: "unavailable" },
    snapshot: { capture_state: "unconfigured", snapshot_state: "unavailable" },
  });
});
