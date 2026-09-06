import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { notice, performanceFixture, proof } from "../_test/performance_scoring_fixtures.ts";
function input() {
  const value = performanceFixture();
  proof(value, 0, 359);
  notice(value);
  value.now = "2026-12-11T12:00:00.123456Z";
  return value;
}
import { runPerformanceLifecycle } from "./worker.ts";
import { localPerformanceLifecycleDatabase } from "./database.ts";
import type { PerformanceLifecycleDatabase } from "./worker.ts";

Deno.test("worker reloads after stale full snapshot and settles only committed final", async () => {
  let loads = 0;
  let commits = 0;
  let settlements = 0;
  const database: PerformanceLifecycleDatabase = {
    load: () =>
      Promise.resolve(
        (++loads, input()),
      ),
    commit: (_input, decision) => {
      assertEquals(decision.phase, "ready_to_finalize");
      return Promise.resolve(++commits === 1 ? "stale" : "final");
    },
    settle: () => Promise.resolve(++settlements),
  };
  assertEquals(await runPerformanceLifecycle(database, performanceFixture().agreement.id), "final");
  assertEquals([loads, commits, settlements], [2, 2, 1]);
});
Deno.test("worker bounds contention and never settles an uncommitted result", async () => {
  let loads = 0;
  const database: PerformanceLifecycleDatabase = {
    load: () => Promise.resolve((++loads, input())),
    commit: () => Promise.resolve("stale"),
    settle: () => {
      throw new Error("must not settle");
    },
  };
  assertEquals(await runPerformanceLifecycle(database, performanceFixture().agreement.id), "stale");
  assertEquals(loads, 4);
});
Deno.test("worker rerun recovers a settlement failure after final commit", async () => {
  let settlements = 0;
  const database: PerformanceLifecycleDatabase = {
    load: () =>
      Promise.resolve(
        input(),
      ),
    commit: () => Promise.resolve("final"),
    settle: () => {
      if (++settlements === 1) throw new Error("temporary");
      return Promise.resolve(null);
    },
  };
  await assertRejects(
    () => runPerformanceLifecycle(database, performanceFixture().agreement.id),
    Error,
    "temporary",
  );
  assertEquals(await runPerformanceLifecycle(database, performanceFixture().agreement.id), "final");
  assertEquals(settlements, 2);
});
Deno.test("worker rejects mismatched identity and handles unavailable input", async () => {
  const database: PerformanceLifecycleDatabase = {
    load: () => Promise.resolve(input()),
    commit: () => {
      throw new Error("must not commit");
    },
    settle: () => {
      throw new Error("must not settle");
    },
  };
  await assertRejects(
    () => runPerformanceLifecycle(database, "another-performance"),
    Error,
    "identity_mismatch",
  );
  assertEquals(
    await runPerformanceLifecycle(
      { ...database, load: () => Promise.resolve(null) },
      performanceFixture().agreement.id,
    ),
    "inactive",
  );
});
Deno.test("operational adapter refuses hosted endpoints", () => {
  for (
    const url of [
      "https://example.supabase.co",
      "http://localhost.example.com",
      "https://localhost",
    ]
  ) {
    assertThrows(
      () => localPerformanceLifecycleDatabase({ url, serviceRoleKey: "fixture" }),
      Error,
      "requires_loopback",
    );
  }
});
