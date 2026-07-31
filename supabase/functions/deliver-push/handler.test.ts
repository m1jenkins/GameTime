import { assertEquals } from "@std/assert";
import { leadLossPayload, type PushResult, type PushTransport } from "./apns.ts";
import type { PushDeliveryClaim, PushDeliveryDatabase } from "./database.ts";
import { createDeliverPushHandler } from "./handler.ts";

const SECRET = "a-test-dispatch-secret-that-is-long-enough";
const CLAIM: PushDeliveryClaim = {
  delivery_id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
  intent_id: 1,
  attempt_count: 1,
  device_token: "ab".repeat(32),
  environment: "development",
  bundle_id: "com.mjenkins.gametime.staging",
  contest_id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
  snapshot_id: "cccccccc-cccc-cccc-cccc-cccccccccccc",
  event_type: "contest_lead_lost",
};

function request(secret = SECRET): Request {
  return new Request("https://example.test/deliver-push", {
    method: "POST",
    headers: { "x-gametime-dispatch-secret": secret },
  });
}

function dependencies(
  outcome: PushResult = { outcome: "delivered", statusCode: 200 },
) {
  const records: unknown[] = [];
  const sent: unknown[] = [];
  const database: PushDeliveryDatabase = {
    claim: () => Promise.resolve([CLAIM]),
    record: (deliveryId, leaseOwner, result) => {
      records.push({ deliveryId, leaseOwner, result });
      return Promise.resolve();
    },
  };
  const transport: PushTransport = {
    send: (message) => {
      sent.push(message);
      return Promise.resolve(outcome);
    },
  };
  return {
    records,
    sent,
    handler: createDeliverPushHandler({
      deploymentEnvironment: "staging",
      dispatchSecret: SECRET,
      database,
      transport,
      leaseOwner: () => "dddddddd-dddd-dddd-dddd-dddddddddddd",
    }),
  };
}

Deno.test("rejects a missing or incorrect dispatch secret", async () => {
  const { handler } = dependencies();
  assertEquals((await handler(request(""))).status, 401);
  assertEquals((await handler(request("not-the-secret"))).status, 401);
});

Deno.test("sends a claimed lead-loss notification and records delivery", async () => {
  const { handler, sent, records } = dependencies();
  const response = await handler(request());

  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    claimed: 1,
    delivered: 1,
    retrying: 0,
    permanently_failed: 0,
  });
  assertEquals(sent, [{
    deviceToken: CLAIM.device_token,
    environment: CLAIM.environment,
    bundleId: CLAIM.bundle_id,
    contestId: CLAIM.contest_id,
    snapshotId: CLAIM.snapshot_id,
  }]);
  assertEquals(records, [{
    deliveryId: CLAIM.delivery_id,
    leaseOwner: "dddddddd-dddd-dddd-dddd-dddddddddddd",
    result: { outcome: "delivered", statusCode: 200 },
  }]);
});

Deno.test("records a transport exception for retry without leaking detail", async () => {
  const records: unknown[] = [];
  const handler = createDeliverPushHandler({
    deploymentEnvironment: "staging",
    dispatchSecret: SECRET,
    database: {
      claim: () => Promise.resolve([CLAIM]),
      record: (deliveryId, leaseOwner, result) => {
        records.push({ deliveryId, leaseOwner, result });
        return Promise.resolve();
      },
    },
    transport: {
      send: () => Promise.reject(new Error(`token ${CLAIM.device_token}`)),
    },
    leaseOwner: () => "dddddddd-dddd-dddd-dddd-dddddddddddd",
  });

  assertEquals((await handler(request())).status, 200);
  assertEquals(records, [{
    deliveryId: CLAIM.delivery_id,
    leaseOwner: "dddddddd-dddd-dddd-dddd-dddddddddddd",
    result: {
      outcome: "retry",
      statusCode: 503,
      reason: "TransportUnavailable",
    },
  }]);
});

Deno.test("refuses to start outside the staging deployment", () => {
  let error: unknown;
  try {
    createDeliverPushHandler({
      deploymentEnvironment: "production",
      dispatchSecret: SECRET,
      database: {
        claim: () => Promise.resolve([]),
        record: () => Promise.resolve(),
      },
      transport: {
        send: () => Promise.resolve({ outcome: "delivered", statusCode: 200 }),
      },
    });
  } catch (caught) {
    error = caught;
  }
  assertEquals(
    error instanceof Error ? error.message : null,
    "deliver-push is restricted to the staging environment",
  );
});

Deno.test("never sends a production claim from the staging worker", async () => {
  const records: unknown[] = [];
  const sent: unknown[] = [];
  const productionClaim: PushDeliveryClaim = {
    ...CLAIM,
    environment: "production",
    bundle_id: "com.mjenkins.gametime",
  };
  const handler = createDeliverPushHandler({
    deploymentEnvironment: "staging",
    dispatchSecret: SECRET,
    database: {
      claim: () => Promise.resolve([productionClaim]),
      record: (deliveryId, leaseOwner, result) => {
        records.push({ deliveryId, leaseOwner, result });
        return Promise.resolve();
      },
    },
    transport: {
      send: (message) => {
        sent.push(message);
        return Promise.resolve({ outcome: "delivered", statusCode: 200 });
      },
    },
    leaseOwner: () => "dddddddd-dddd-dddd-dddd-dddddddddddd",
  });

  const response = await handler(request());
  assertEquals(await response.json(), {
    claimed: 1,
    delivered: 0,
    retrying: 0,
    permanently_failed: 1,
  });
  assertEquals(sent, []);
  assertEquals(records, [{
    deliveryId: productionClaim.delivery_id,
    leaseOwner: "dddddddd-dddd-dddd-dddd-dddddddddddd",
    result: {
      outcome: "permanent_failure",
      statusCode: 400,
      reason: "EnvironmentMismatch",
    },
  }]);
});

Deno.test("payload deep-links to standings and contains no activity total", () => {
  const payload = leadLossPayload({
    deviceToken: CLAIM.device_token,
    environment: CLAIM.environment,
    bundleId: CLAIM.bundle_id,
    contestId: CLAIM.contest_id,
    snapshotId: CLAIM.snapshot_id,
  });
  assertEquals(payload, {
    aps: {
      alert: {
        title: "You lost the lead",
        body: "The standings changed. Open GameTime to see where you rank.",
      },
      sound: "default",
      category: "GAMETIME_LEAD_LOST",
      "thread-id": `contest-${CLAIM.contest_id}`,
    },
    route: "standings",
    contest_id: CLAIM.contest_id,
    snapshot_id: CLAIM.snapshot_id,
  });
});
