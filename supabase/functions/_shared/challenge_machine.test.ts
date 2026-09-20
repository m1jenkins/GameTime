import { assertEquals } from "@std/assert";
import { machineBody, machineRpc } from "./challenge_machine.ts";

const UUID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";

function request(body: string): Request {
  return new Request("http://localhost/challenge-worker", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body,
  });
}

Deno.test("machine body accepts only the exact invocation or empty monitor object", async () => {
  assertEquals(await machineBody(request(`{"invocation_id":"${UUID}"}`), "invocation"), {
    invocationId: UUID,
  });
  assertEquals(await machineBody(request("{}"), "monitor"), {});
  assertEquals(
    await machineBody(
      request(`{"invocation_id":"${UUID}","invocation_id":"${UUID}"}`),
      "invocation",
    ),
    null,
  );
  assertEquals(await machineBody(request(`{"invocation_id":"${UUID}"}`), "monitor"), null);
  assertEquals(
    await machineBody(request(`{"invocation_id":"${UUID}","scope":{}}`), "invocation"),
    null,
  );
});

Deno.test("machine RPC retries exact bytes with service credential only in adapter", async () => {
  const calls: { url: string; body: string; key: string | null }[] = [];
  const fetcher: typeof fetch = (_input, init) => {
    const headers = new Headers(init?.headers);
    calls.push({
      url: String(_input),
      body: String(init?.body),
      key: headers.get("apikey"),
    });
    return Promise.resolve(
      calls.length === 1
        ? Response.json({ detail: "private" }, { status: 503 })
        : Response.json({ status: "empty" }),
    );
  };
  const result = await machineRpc(
    { url: "http://localhost:54321", serviceRoleKey: "private-service-key" },
    "challenge_machine_monitor_v1",
    {},
    fetcher,
  );
  assertEquals(result, { status: "empty" });
  assertEquals(calls, [
    {
      url: "http://localhost:54321/rest/v1/rpc/challenge_machine_monitor_v1",
      body: "{}",
      key: "private-service-key",
    },
    {
      url: "http://localhost:54321/rest/v1/rpc/challenge_machine_monitor_v1",
      body: "{}",
      key: "private-service-key",
    },
  ]);
});
