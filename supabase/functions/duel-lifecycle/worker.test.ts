import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { AGREEMENT, at, input, notices, proof } from "../_test/duel_scoring_fixtures.ts";
import { runDuelLifecycle } from "./worker.ts";
import { localDuelLifecycleDatabase } from "./database.ts";
import type { DuelLifecycleDatabase } from "./worker.ts";

Deno.test("worker reloads after stale full snapshot and settles only committed final", async () => {
  let loads = 0;
  let commits = 0;
  let settlements = 0;
  const database: DuelLifecycleDatabase = {
    load: () =>
      Promise.resolve(
        (++loads,
          input({
            now: at(180),
            proofRevisions: [proof()],
            notices: notices(),
          })),
      ),
    commit: (_input, decision) => {
      assertEquals(decision.phase, "ready_to_finalize");
      return Promise.resolve(++commits === 1 ? "stale" : "final");
    },
    settle: () => Promise.resolve(++settlements),
  };
  assertEquals(await runDuelLifecycle(database, AGREEMENT.id), "final");
  assertEquals([loads, commits, settlements], [2, 2, 1]);
});
Deno.test("worker bounds contention and never settles an uncommitted result", async () => {
  let loads = 0;
  const database: DuelLifecycleDatabase = {
    load: () => Promise.resolve((++loads, input())),
    commit: () => Promise.resolve("stale"),
    settle: () => {
      throw new Error("must not settle");
    },
  };
  assertEquals(await runDuelLifecycle(database, AGREEMENT.id), "stale");
  assertEquals(loads, 4);
});
Deno.test("worker rerun recovers a settlement failure after final commit", async () => {
  let settlements = 0;
  const database: DuelLifecycleDatabase = {
    load: () =>
      Promise.resolve(
        input({ now: at(180), proofRevisions: [proof()], notices: notices() }),
      ),
    commit: () => Promise.resolve("final"),
    settle: () => {
      if (++settlements === 1) throw new Error("temporary");
      return Promise.resolve(null);
    },
  };
  await assertRejects(
    () => runDuelLifecycle(database, AGREEMENT.id),
    Error,
    "temporary",
  );
  assertEquals(await runDuelLifecycle(database, AGREEMENT.id), "final");
  assertEquals(settlements, 2);
});
Deno.test("worker rejects mismatched identity and skips unaccepted invitations", async () => {
  const database: DuelLifecycleDatabase = {
    load: () => Promise.resolve(input()),
    commit: () => {
      throw new Error("must not commit");
    },
    settle: () => {
      throw new Error("must not settle");
    },
  };
  await assertRejects(
    () => runDuelLifecycle(database, "another-duel"),
    Error,
    "identity_mismatch",
  );
  assertEquals(
    await runDuelLifecycle(
      { ...database, load: () => Promise.resolve(null) },
      AGREEMENT.id,
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
      () => localDuelLifecycleDatabase({ url, serviceRoleKey: "fixture" }),
      Error,
      "requires_loopback",
    );
  }
});
