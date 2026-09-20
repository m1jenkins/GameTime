import { assertEquals, assertThrows } from "@std/assert";
import { createChallengeSnapshotHandler } from "./handler.ts";
import type { ChallengeSnapshotDatabase } from "./database.ts";

const WORKER = "worker-secret-long-enough-for-local-tests-123";
const MONITOR = "monitor-secret-long-enough-for-local-tests-456";
const INVOCATION = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";

function request(body: unknown, secret = WORKER): Request {
  return new Request("http://localhost/challenge-snapshot", {
    method: "POST",
    headers: { "content-type": "application/json", "x-gametime-worker-secret": secret },
    body: JSON.stringify(body),
  });
}

Deno.test("snapshot uses only prepared invocation identity and worker credential", async () => {
  const ids: string[] = [];
  const handler = createChallengeSnapshotHandler({
    workerSecret: WORKER,
    monitorSecret: MONITOR,
    database: {
      dispatch: (id) => {
        ids.push(id);
        return Promise.resolve({
          status: "checked",
          last_capture_at: "2026-09-20T10:00:00Z",
          capture_age_seconds: 900,
          challenge_id: "private",
          member_count: 4,
        });
      },
    },
  });
  assertEquals((await handler(request({ invocation_id: INVOCATION }, MONITOR))).status, 401);
  assertEquals(
    (await handler(request({ invocation_id: INVOCATION, cohort_id: INVOCATION }))).status,
    400,
  );
  assertEquals(ids, []);
  const response = await handler(request({ invocation_id: INVOCATION }));
  assertEquals(await response.json(), {
    status: "checked",
    last_capture_at: "2026-09-20T10:00:00Z",
    capture_age_seconds: 900,
  });
  assertEquals(ids, [INVOCATION]);
  assertThrows(() =>
    createChallengeSnapshotHandler({
      workerSecret: WORKER,
      monitorSecret: WORKER,
      database: {} as ChallengeSnapshotDatabase,
    })
  );
});
