import { assertEquals, assertStringIncludes } from "@std/assert";
import { ApnsTokenTransport, leadLossPayload, type LeadLossPush } from "./apns.ts";

const MESSAGE: LeadLossPush = {
  deviceToken: "ab".repeat(32),
  environment: "development",
  bundleId: "com.mjenkins.gametime.staging",
  contestId: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
  snapshotId: "cccccccc-cccc-cccc-cccc-cccccccccccc",
};

async function privateKeyPem(): Promise<string> {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const bytes = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", pair.privateKey),
  );
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return `-----BEGIN PRIVATE KEY-----\n${btoa(binary)}\n-----END PRIVATE KEY-----`;
}

async function transport(
  response: Response,
  requests: Array<{ url: string; init?: RequestInit }> = [],
): Promise<ApnsTokenTransport> {
  const fetchImplementation = ((
    input: string | URL | Request,
    init?: RequestInit,
  ) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
    requests.push({ url, init });
    return Promise.resolve(response);
  }) as typeof fetch;

  return new ApnsTokenTransport(
    {
      teamId: "TEAMID1234",
      keyId: "KEYID12345",
      privateKeyPem: await privateKeyPem(),
    },
    fetchImplementation,
    () => new Date("2026-07-30T20:00:00Z"),
  );
}

Deno.test("uses sandbox APNs with the staging topic and snapshot collapse id", async () => {
  const requests: Array<{ url: string; init?: RequestInit }> = [];
  const sender = await transport(new Response(null, { status: 200 }), requests);

  assertEquals(await sender.send(MESSAGE), {
    outcome: "delivered",
    statusCode: 200,
  });
  assertEquals(requests.length, 1);

  const request = requests[0];
  assertEquals(
    request?.url,
    `https://api.sandbox.push.apple.com/3/device/${MESSAGE.deviceToken}`,
  );
  const headers = new Headers(request?.init?.headers);
  assertEquals(headers.get("apns-topic"), MESSAGE.bundleId);
  assertEquals(headers.get("apns-push-type"), "alert");
  assertEquals(
    headers.get("apns-collapse-id"),
    `lead-lost-${MESSAGE.snapshotId}`,
  );
  assertStringIncludes(headers.get("authorization") ?? "", "bearer ");
  assertEquals(
    JSON.parse(String(request?.init?.body)),
    leadLossPayload(MESSAGE),
  );
});

Deno.test("classifies an unregistered APNs token as permanent", async () => {
  const sender = await transport(
    Response.json({ reason: "Unregistered" }, { status: 410 }),
  );

  assertEquals(await sender.send(MESSAGE), {
    outcome: "permanent_failure",
    statusCode: 410,
    reason: "Unregistered",
  });
});

Deno.test("classifies an APNs service failure for retry", async () => {
  const sender = await transport(
    Response.json({ reason: "ServiceUnavailable" }, { status: 503 }),
  );

  assertEquals(await sender.send(MESSAGE), {
    outcome: "retry",
    statusCode: 503,
    reason: "ServiceUnavailable",
  });
});
