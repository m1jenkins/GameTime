import { assertEquals, assertThrows } from "@std/assert";
import { createChallengeWorkerHandler } from "./handler.ts";
import type { ChallengeWorkerDatabase } from "./database.ts";

const WORKER = "worker-secret-long-enough-for-local-tests-123";
const MONITOR = "monitor-secret-long-enough-for-local-tests-456";
const INVOCATION = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const RUN = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";

function request(body: unknown, secret = WORKER): Request {
  return new Request("http://localhost/challenge-worker", {
    method: "POST",
    headers: { "content-type": "application/json", "x-gametime-worker-secret": secret },
    body: JSON.stringify(body),
  });
}

Deno.test("worker authenticates and rejects caller selected operations before database access", async () => {
  let calls = 0;
  const handler = createChallengeWorkerHandler({
    workerSecret: WORKER,
    monitorSecret: MONITOR,
    database: {
      dispatch: () => {
        calls++;
        return Promise.resolve({ status: "empty" });
      },
      complete: () => {
        calls++;
        return Promise.resolve({});
      },
      finish: () => {
        calls++;
        return Promise.resolve({ status: "completed" });
      },
    },
  });
  assertEquals((await handler(request({ invocation_id: INVOCATION }, ""))).status, 401);
  assertEquals((await handler(request({ invocation_id: INVOCATION }, MONITOR))).status, 401);
  assertEquals((await handler(request({ invocation_id: INVOCATION, rpc: "drop" }))).status, 400);
  assertEquals((await handler(request({ scope: { kind: "all" } }))).status, 400);
  assertEquals((await handler(request({ invocation_id: "invalid" }))).status, 400);
  assertEquals(calls, 0);
  assertThrows(() =>
    createChallengeWorkerHandler({
      workerSecret: WORKER,
      monitorSecret: WORKER,
      database: {} as ChallengeWorkerDatabase,
    })
  );
});

Deno.test("worker completes fixed saved claims in five lanes and fences each completion", async () => {
  const claims = Array.from({ length: 20 }, (_, i) => ({
    id: `00000000-0000-0000-0000-${String(i).padStart(12, "0")}`,
    claim_token: `11111111-1111-1111-1111-${String(i).padStart(12, "0")}`,
  }));
  let active = 0;
  let maximum = 0;
  const completed: string[] = [];
  let finishSaw = 0;
  const handler = createChallengeWorkerHandler({
    workerSecret: WORKER,
    monitorSecret: MONITOR,
    runToken: () => RUN,
    database: {
      dispatch: (id, token) => {
        assertEquals([id, token], [INVOCATION, RUN]);
        return Promise.resolve({ status: "running", claims, server_time: "2026-09-20T10:00:00Z" });
      },
      complete: async (id, token, challengeId, claimToken) => {
        assertEquals([id, token], [INVOCATION, RUN]);
        assertEquals(claimToken, claims.find((c) => c.id === challengeId)?.claim_token);
        active++;
        maximum = Math.max(maximum, active);
        await new Promise((resolve) => setTimeout(resolve, 1));
        completed.push(challengeId);
        active--;
      },
      finish: (id, token) => {
        assertEquals([id, token], [INVOCATION, RUN]);
        finishSaw = completed.length;
        return Promise.resolve({
          status: "completed",
          completed_count: 20,
          failed_count: 0,
          server_time: "2026-09-20T10:00:01Z",
          claim_token: "private",
        });
      },
    },
  });
  const response = await handler(request({ invocation_id: INVOCATION }));
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    status: "completed",
    completed_count: 20,
    failed_count: 0,
    server_time: "2026-09-20T10:00:01Z",
  });
  assertEquals(maximum, 5);
  assertEquals(finishSaw, 20);
});

Deno.test("worker returns saved summary without completing claims again", async () => {
  let completions = 0;
  const handler = createChallengeWorkerHandler({
    workerSecret: WORKER,
    monitorSecret: MONITOR,
    database: {
      dispatch: () =>
        Promise.resolve({
          status: "completed",
          result: { status: "completed", completed_count: 2, failed_count: 0, claims: ["secret"] },
        }),
      complete: () => {
        completions++;
        return Promise.resolve({});
      },
      finish: () => {
        throw new Error("should not finish");
      },
    },
  });
  assertEquals(await (await handler(request({ invocation_id: INVOCATION }))).json(), {
    status: "completed",
    completed_count: 2,
    failed_count: 0,
  });
  assertEquals(completions, 0);
});

Deno.test("worker masks errors and rejects unexpected claim shapes", async () => {
  const handler = createChallengeWorkerHandler({
    workerSecret: WORKER,
    monitorSecret: MONITOR,
    database: {
      dispatch: () =>
        Promise.resolve({ status: "running", claims: [{ id: "private", claim_token: "private" }] }),
      complete: () => Promise.resolve({}),
      finish: () => Promise.resolve({ status: "completed" }),
    },
  });
  const response = await handler(request({ invocation_id: INVOCATION }));
  assertEquals(response.status, 503);
  assertEquals(JSON.stringify(await response.json()).includes("private"), false);
  const failed = createChallengeWorkerHandler({
    workerSecret: WORKER,
    monitorSecret: MONITOR,
    database: {
      dispatch: () => Promise.reject(new Error("private payload or credential")),
      complete: () => Promise.resolve({}),
      finish: () => Promise.resolve({ status: "completed" }),
    },
  });
  const error = await failed(request({ invocation_id: INVOCATION }));
  assertEquals(error.status, 503);
  assertEquals(JSON.stringify(await error.json()).includes("private"), false);
});

Deno.test("one completion transport failure does not abandon later claims", async () => {
  const claims = [0, 1, 2, 3, 4, 5].map((i) => ({
    id: `00000000-0000-0000-0000-${String(i).padStart(12, "0")}`,
    claim_token: `11111111-1111-1111-1111-${String(i).padStart(12, "0")}`,
  }));
  const seen: string[] = [];
  const handler = createChallengeWorkerHandler({
    workerSecret: WORKER,
    monitorSecret: MONITOR,
    runToken: () => RUN,
    database: {
      dispatch: () => Promise.resolve({ status: "running", claims }),
      complete: (_invocation, _run, id) => {
        seen.push(id);
        return id === claims[0]?.id
          ? Promise.reject(new Error("private SQL text"))
          : Promise.resolve({ status: "done" });
      },
      finish: () =>
        Promise.resolve({
          status: "pending",
          completed_count: 5,
          failed_count: 0,
          pending_count: 1,
          error_code: "private",
        }),
    },
  });
  const response = await handler(request({ invocation_id: INVOCATION }));
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    status: "pending",
    completed_count: 5,
    failed_count: 0,
    pending_count: 1,
    error_categories: ["completion_transport"],
  });
  assertEquals(seen.length, 6);
});
