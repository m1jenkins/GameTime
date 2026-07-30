import { assertEquals } from "@std/assert";
import { type Bytes } from "./bytes.ts";
import {
  type MarkDeviceReceiptVerifiedArgs,
  type PostgrestConfig,
  postgrestDatabase,
  type RecordMetricBatchArgs,
  type RegisterDeviceKeyArgs,
} from "./database.ts";
import { HttpFailure, respond } from "./http.ts";

const CONFIG: PostgrestConfig = {
  url: "https://database.example.test",
  serviceRoleKey: "sb_secret_test",
  authorizationBearer: false,
};

const KEY_ID: Bytes = new Uint8Array(32).fill(0x11);
const PUBLIC_KEY: Bytes = (() => {
  const key = new Uint8Array(65);
  key[0] = 0x04;
  key.fill(0x22, 1);
  return key;
})();
const RECEIPT: Bytes = new Uint8Array([0x30, 0x80, 0x01, 0x02]);
const RECEIPT_SHA256: Bytes = new Uint8Array(32).fill(0x33);

const REGISTRATION: RegisterDeviceKeyArgs = {
  userId: "11111111-1111-1111-1111-111111111111",
  keyId: KEY_ID,
  publicKey: PUBLIC_KEY,
  receipt: RECEIPT,
  environment: "production",
};

const MARKER: MarkDeviceReceiptVerifiedArgs = {
  keyId: KEY_ID,
  receiptSha256: RECEIPT_SHA256,
};

const METRIC_BATCH: RecordMetricBatchArgs = {
  userId: REGISTRATION.userId,
  contestId: "22222222-2222-2222-2222-222222222222",
  clientBatchId: "33333333-3333-3333-3333-333333333333",
  payloadDigest: new Uint8Array(32).fill(0x44),
  observedAt: "2026-08-03T03:00:00.000Z",
  observations: [
    {
      metric: "steps",
      bucket_start: "2026-08-03T02:00:00.000Z",
      value: 9_876_543.21,
      provenance: "device",
      sample_count: 1,
      source_bundle_id: "com.example.private-health-sentinel",
      device_model: "Private Health Model",
    },
  ],
  keyId: KEY_ID,
  signCount: 7,
};

async function captureFailure(action: () => Promise<unknown>): Promise<HttpFailure> {
  let failure: unknown;
  try {
    await action();
  } catch (error) {
    failure = error;
  }
  assertEquals(failure instanceof HttpFailure, true);
  if (!(failure instanceof HttpFailure)) throw new Error("expected HttpFailure");
  return failure;
}

Deno.test("the PostgREST device adapter parses server timestamps and sends scoped RPCs", async () => {
  const originalFetch = globalThis.fetch;
  const requests: Array<{
    url: string;
    method: string | undefined;
    headers: Headers;
    body: Record<string, unknown>;
  }> = [];

  try {
    globalThis.fetch = (input, init) => {
      const url = String(input);
      requests.push({
        url,
        method: init?.method,
        headers: new Headers(init?.headers),
        body: JSON.parse(String(init?.body)) as Record<string, unknown>,
      });
      const timestamp = url.endsWith("/register_device_key")
        ? "2026-07-26T01:02:03.456789+00:00"
        : "2026-07-26T01:02:04.987654+00:00";
      return Promise.resolve(
        new Response(JSON.stringify(timestamp), {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
      );
    };

    const database = postgrestDatabase(CONFIG);
    const registered = await database.registerDeviceKey(REGISTRATION);
    const verifiedAt = await database.markDeviceReceiptVerified(MARKER);

    assertEquals(
      registered.receiptReceivedAt,
      new Date("2026-07-26T01:02:03.456Z"),
    );
    assertEquals(verifiedAt, new Date("2026-07-26T01:02:04.987Z"));
    assertEquals(requests.length, 2);

    const registration = requests[0]!;
    assertEquals(
      registration.url,
      "https://database.example.test/rest/v1/rpc/register_device_key",
    );
    assertEquals(registration.method, "POST");
    assertEquals(registration.headers.get("apikey"), "sb_secret_test");
    assertEquals(registration.headers.get("authorization"), null);
    assertEquals(registration.body, {
      p_user_id: REGISTRATION.userId,
      p_key_id: `\\x${"11".repeat(32)}`,
      p_public_key: `\\x04${"22".repeat(64)}`,
      p_attestation_receipt: "\\x30800102",
      p_environment: "production",
    });

    const marker = requests[1]!;
    assertEquals(
      marker.url,
      "https://database.example.test/rest/v1/rpc/mark_device_receipt_verified",
    );
    assertEquals(marker.method, "POST");
    assertEquals(marker.body, {
      p_key_id: `\\x${"11".repeat(32)}`,
      p_receipt_sha256: `\\x${"33".repeat(32)}`,
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("the active-actor adapter calls only the service assertion RPC", async () => {
  const originalFetch = globalThis.fetch;
  let request:
    | {
      url: string;
      method: string | undefined;
      headers: Headers;
      body: Record<string, unknown>;
    }
    | undefined;

  try {
    globalThis.fetch = (input, init) => {
      request = {
        url: String(input),
        method: init?.method,
        headers: new Headers(init?.headers),
        body: JSON.parse(String(init?.body)) as Record<string, unknown>,
      };
      return Promise.resolve(new Response(null, { status: 204 }));
    };

    await postgrestDatabase(CONFIG).assertActiveActor(REGISTRATION.userId);

    assertEquals(
      request?.url,
      "https://database.example.test/rest/v1/rpc/assert_active_actor",
    );
    assertEquals(request?.method, "POST");
    assertEquals(request?.headers.get("apikey"), "sb_secret_test");
    assertEquals(request?.headers.get("authorization"), null);
    assertEquals(request?.body, { p_user_id: REGISTRATION.userId });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("the active-actor adapter maps a deleted account to a private 403", async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = () =>
      Promise.resolve(
        new Response(
          JSON.stringify({
            code: "42501",
            message: `account ${REGISTRATION.userId} was deleted`,
          }),
          {
            status: 403,
            headers: { "content-type": "application/json" },
          },
        ),
      );

    const failure = await captureFailure(
      () => postgrestDatabase(CONFIG).assertActiveActor(REGISTRATION.userId),
    );
    assertEquals(failure.kind, "forbidden");
    assertEquals(failure.message, "this account is not active");
    assertEquals(failure.message.includes(REGISTRATION.userId), false);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("metric RPC failures discard raw health detail before logging", async () => {
  const originalFetch = globalThis.fetch;
  const originalWarn = console.warn;
  const originalError = console.error;
  const warnings: string[] = [];
  const errors: string[] = [];
  const priorValue = "9876543.21";
  const revisedValue = "1234567.89";
  const source = "com.example.private-health-sentinel";

  try {
    globalThis.fetch = () =>
      Promise.resolve(
        new Response(
          JSON.stringify({
            code: "23001",
            message: `bucket 2026-08-03T02:00:00Z of steps from ${source} ` +
              `already stands at ${priorValue}; a figure cannot be revised ` +
              `down to ${revisedValue}`,
          }),
          {
            status: 422,
            headers: { "content-type": "application/json" },
          },
        ),
      );
    console.warn = (...values: unknown[]) => {
      warnings.push(values.map(String).join(" "));
    };
    console.error = (...values: unknown[]) => {
      errors.push(values.map(String).join(" "));
    };

    const database = postgrestDatabase(CONFIG);
    const failure = await captureFailure(
      () => database.recordMetricBatch(METRIC_BATCH),
    );
    assertEquals(failure.kind, "rejected");
    assertEquals(
      failure.message,
      "the evidence was refused by a rule of this contest",
    );
    assertEquals(failure.detail, undefined);

    const response = await respond("ingest-metrics", async () => {
      await database.recordMetricBatch(METRIC_BATCH);
      return new Response(null, { status: 204 });
    });
    const observableText = [
      failure.message,
      failure.detail ?? "",
      await response.text(),
      ...warnings,
      ...errors,
    ].join("|");

    assertEquals(response.status, 422);
    assertEquals(warnings, []);
    assertEquals(errors, []);
    assertEquals(observableText.includes(priorValue), false);
    assertEquals(observableText.includes(revisedValue), false);
    assertEquals(observableText.includes(source), false);
  } finally {
    globalThis.fetch = originalFetch;
    console.warn = originalWarn;
    console.error = originalError;
  }
});

Deno.test("registration refuses a missing receipt capture timestamp", async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = () =>
      Promise.resolve(
        new Response("null", {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
      );

    const failure = await captureFailure(
      () => postgrestDatabase(CONFIG).registerDeviceKey(REGISTRATION),
    );
    assertEquals(failure.kind, "internal");
    assertEquals(failure.message, "the request could not be processed");
    assertEquals(failure.detail?.includes("register_device_key"), true);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("the receipt marker refuses an invalid verification timestamp", async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = () =>
      Promise.resolve(
        new Response(JSON.stringify("not-a-timestamp"), {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
      );

    const failure = await captureFailure(
      () => postgrestDatabase(CONFIG).markDeviceReceiptVerified(MARKER),
    );
    assertEquals(failure.kind, "internal");
    assertEquals(failure.message, "the request could not be processed");
    assertEquals(failure.detail?.includes("mark_device_receipt_verified"), true);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("receipt-marker database refusals expose no private candidate detail", async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = () =>
      Promise.resolve(
        new Response(
          JSON.stringify({
            code: "22023",
            message: "private receipt digest belongs to key deadbeef",
          }),
          {
            status: 400,
            headers: { "content-type": "application/json" },
          },
        ),
      );

    const failure = await captureFailure(
      () => postgrestDatabase(CONFIG).markDeviceReceiptVerified(MARKER),
    );
    assertEquals(failure.kind, "internal");
    assertEquals(failure.message, "the request could not be processed");
    assertEquals(failure.message.includes("deadbeef"), false);
    assertEquals(failure.message.includes("receipt"), false);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
