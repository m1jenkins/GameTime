import { assertEquals, assertRejects } from "@std/assert";
import { MachineRpcError } from "../_shared/challenge_machine.ts";
import { postgrestChallengeWorkerDatabase } from "./database.ts";

const INVOCATION = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const RUN = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
const CHALLENGE = "cccccccc-cccc-cccc-cccc-cccccccccccc";
const CLAIM = "dddddddd-dddd-dddd-dddd-dddddddddddd";
const CONFIG = { url: "http://localhost:54321", serviceRoleKey: "private-service-key" };

Deno.test("worker adapter replays exact dispatch and completion after lost responses", async () => {
  const calls: Record<string, string[]> = {};
  const fetcher: typeof fetch = (input, init) => {
    const name = String(input).split("/").at(-1) ?? "";
    const bodies = calls[name] ??= [];
    bodies.push(String(init?.body));
    const headers = new Headers(init?.headers);
    assertEquals(headers.get("apikey"), CONFIG.serviceRoleKey);
    if (bodies.length === 1) return Promise.reject(new TypeError("response lost: private payload"));
    return Promise.resolve(Response.json({ status: "saved" }));
  };
  const database = postgrestChallengeWorkerDatabase(CONFIG, fetcher);
  const deadline = Date.now() + 50_000;
  assertEquals(await database.dispatch(INVOCATION, RUN, deadline), { status: "saved" });
  assertEquals(await database.complete(INVOCATION, RUN, CHALLENGE, CLAIM, deadline), {
    status: "saved",
  });
  assertEquals(calls.challenge_machine_worker_dispatch_v1, [
    JSON.stringify({ p_invocation_id: INVOCATION, p_run_token: RUN }),
    JSON.stringify({ p_invocation_id: INVOCATION, p_run_token: RUN }),
  ]);
  assertEquals(calls.challenge_machine_complete_v1, [
    JSON.stringify({
      p_invocation_id: INVOCATION,
      p_run_token: RUN,
      p_id: CHALLENGE,
      p_claim_token: CLAIM,
    }),
    JSON.stringify({
      p_invocation_id: INVOCATION,
      p_run_token: RUN,
      p_id: CHALLENGE,
      p_claim_token: CLAIM,
    }),
  ]);
});

Deno.test("worker adapter stops after three timeouts and honors the global deadline", async () => {
  let calls = 0;
  const timeout: typeof fetch = () => {
    calls++;
    return Promise.reject(new DOMException("private", "TimeoutError"));
  };
  const database = postgrestChallengeWorkerDatabase(CONFIG, timeout);
  const error = await assertRejects(
    () => database.dispatch(INVOCATION, RUN, Date.now() + 50_000),
    MachineRpcError,
  );
  assertEquals(error.category, "timeout");
  assertEquals(calls, 3);

  calls = 0;
  const waitsForAbort: typeof fetch = (_input, init) => {
    calls++;
    const signal = init?.signal;
    return new Promise<Response>((_resolve, reject) => {
      signal?.addEventListener("abort", () => reject(signal.reason), { once: true });
    });
  };
  const bounded = postgrestChallengeWorkerDatabase(CONFIG, waitsForAbort);
  const started = Date.now();
  const deadlineError = await assertRejects(
    () => bounded.dispatch(INVOCATION, RUN, Date.now() + 30),
    MachineRpcError,
  );
  assertEquals(deadlineError.category, "timeout");
  assertEquals(calls, 1);
  assertEquals(Date.now() - started < 1_000, true);
});
