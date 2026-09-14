import { assertEquals } from "@std/assert";
import { createAccessTokenVerifier } from "../_shared/jwt.ts";
import { mintAccessToken, TEST_JWT_SECRET } from "../_test/tokens.ts";
import {
  type AccountDeletionDatabase,
  type AccountDeletionStatus,
  createDeleteAccountHandler,
  type DeleteAccountDeps,
  type StripeCustomerDeleter,
} from "./handler.ts";

const USER = "11111111-1111-1111-1111-111111111111";
const SESSION = "22222222-2222-4222-8222-222222222222";
const REQUEST = "33333333-3333-4333-8333-333333333333";
const RECEIPT = "receipt_secret_for_local_deletion_test_123";
const pending: AccountDeletionStatus = { state: "pending_provider" };
const closing: AccountDeletionStatus = { state: "pending_account_close" };
const complete: AccountDeletionStatus = { state: "completed" };
const expired: AccountDeletionStatus = { state: "expired" };

async function signedToken(): Promise<string> {
  return await mintAccessToken(USER, {
    claims: {
      aud: "authenticated",
      role: "authenticated",
      sub: USER,
      session_id: SESSION,
      exp: Math.floor(Date.now() / 1000) + 3600,
    },
  });
}

async function request(
  body: Record<string, unknown>,
  token?: string | null,
): Promise<Request> {
  const resolvedToken = token === null ? undefined : token ?? await signedToken();
  return new Request("https://example.test/delete-account", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(resolvedToken === undefined ? {} : { authorization: `Bearer ${resolvedToken}` }),
    },
    body: JSON.stringify(body),
  });
}

function deletionBody(
  operation?: "resume" | "status",
  includesAppleCode = true,
): Record<string, unknown> {
  if (operation === "status") return { operation, deletionReceipt: RECEIPT };
  return {
    ...(operation === undefined ? {} : { operation }),
    deletionRequestId: REQUEST,
    deletionReceipt: RECEIPT,
    ...(includesAppleCode ? { appleAuthorizationCode: "fresh-code" } : {}),
  };
}

function deps(
  calls: string[],
  options: {
    readonly subject?: string;
    readonly live?: boolean;
    readonly begin?: AccountDeletionStatus;
    readonly recovered?: AccountDeletionStatus;
    readonly providerFailure?: boolean;
    readonly providerBindingFailure?: boolean;
    readonly completed?: AccountDeletionStatus;
  } = {},
): DeleteAccountDeps {
  const database: AccountDeletionDatabase = {
    providerIdentity(ownerId) {
      calls.push(`identity:${ownerId}`);
      return Promise.resolve({ appleSubject: "apple-subject", stripeCustomerId: "cus_test" });
    },
    assertLiveSession(ownerId, sessionId) {
      calls.push(`session:${ownerId}:${sessionId}`);
      if (options.live === false) return Promise.reject(new Error("stale"));
      return Promise.resolve();
    },
    begin(ownerId, requestId, receipt, subject, stripeCustomerId) {
      calls.push(`begin:${ownerId}:${requestId}:${receipt}:${subject}:${stripeCustomerId}`);
      return Promise.resolve(options.begin ?? pending);
    },
    recovery(receipt) {
      calls.push(`recovery:${receipt}`);
      return Promise.resolve({
        actorId: USER,
        requestId: REQUEST,
        state: options.recovered?.state ?? pending.state,
      });
    },
    providerRecovery(receipt, subject) {
      calls.push(`binding:${receipt}:${subject}`);
      if (options.providerBindingFailure) return Promise.reject(new Error("wrong subject"));
      return Promise.resolve({ actorId: USER, requestId: REQUEST, stripeCustomerId: "cus_test" });
    },
    providerComplete(ownerId, requestId, receipt, subject) {
      calls.push(`provider-complete:${ownerId}:${requestId}:${receipt}:${subject}`);
      return Promise.resolve(closing);
    },
    complete(ownerId, requestId, receipt) {
      calls.push(`complete:${ownerId}:${requestId}:${receipt}`);
      return Promise.resolve(options.completed ?? complete);
    },
    status(receipt) {
      calls.push(`status:${receipt}`);
      return Promise.resolve(options.recovered ?? complete);
    },
    advance(receipt) {
      calls.push(`advance:${receipt}`);
      return Promise.resolve(options.recovered ?? complete);
    },
    fileReview(receipt, requestId, challengeId, noticeRevision, reason) {
      calls.push(`review:${receipt}:${requestId}:${challengeId}:${noticeRevision}:${reason}`);
      return Promise.resolve({ saved: true });
    },
    fileAppeal(receipt, requestId) {
      calls.push(`appeal:${receipt}:${requestId}`);
      return Promise.resolve({ saved: true });
    },
  };
  const stripe: StripeCustomerDeleter = {
    deleteTestCustomer(customerId) {
      calls.push(`stripe:${customerId}`);
      return options.providerFailure
        ? Promise.reject(new Error("lost response"))
        : Promise.resolve();
    },
  };
  return {
    database,
    apple: {
      exchangeAuthorizationCode(code) {
        calls.push(`apple-exchange:${code}`);
        return Promise.resolve({ subject: options.subject ?? "apple-subject" });
      },
      revoke(authorization) {
        calls.push(`apple-revoke:${authorization.subject}`);
        return Promise.resolve();
      },
    },
    stripe,
    verifyToken: createAccessTokenVerifier(TEST_JWT_SECRET),
  };
}

Deno.test("binds Apple proof and a live session before durable deletion acceptance", async () => {
  const calls: string[] = [];
  const response = await createDeleteAccountHandler(deps(calls))(await request(deletionBody()));

  assertEquals(response.status, 200);
  assertEquals(await response.json(), { deleted: true, deletion: complete });
  assertEquals(calls, [
    `identity:${USER}`,
    `session:${USER}:${SESSION}`,
    "apple-exchange:fresh-code",
    `begin:${USER}:${REQUEST}:${RECEIPT}:apple-subject:cus_test`,
    `binding:${RECEIPT}:apple-subject`,
    "apple-revoke:apple-subject",
    "stripe:cus_test",
    `provider-complete:${USER}:${REQUEST}:${RECEIPT}:apple-subject`,
    `complete:${USER}:${REQUEST}:${RECEIPT}`,
  ]);
});

Deno.test("refuses a wrong Apple actor without accepting, revoking, or charging the caller", async () => {
  const calls: string[] = [];
  const response = await createDeleteAccountHandler(
    deps(calls, { subject: "other-apple-subject" }),
  )(
    await request(deletionBody()),
  );
  assertEquals(response.status, 403);
  assertEquals(calls, [
    `identity:${USER}`,
    `session:${USER}:${SESSION}`,
    "apple-exchange:fresh-code",
  ]);
});

Deno.test("refuses a signed but stale session before Apple proof or acceptance", async () => {
  const calls: string[] = [];
  const response = await createDeleteAccountHandler(deps(calls, { live: false }))(
    await request(deletionBody()),
  );
  assertEquals(response.status, 401);
  assertEquals(calls, [`identity:${USER}`, `session:${USER}:${SESSION}`]);
});

Deno.test("reports provider ambiguity as pending while preserving the accepted exact request", async () => {
  const calls: string[] = [];
  const response = await createDeleteAccountHandler(deps(calls, { providerFailure: true }))(
    await request(deletionBody()),
  );
  assertEquals(response.status, 202);
  assertEquals(await response.json(), { deleted: false, deletion: pending });
  assertEquals(calls.slice(-2), ["apple-revoke:apple-subject", "stripe:cus_test"]);
});

Deno.test("resume after a provider response loss completes the saved request without an authenticated session", async () => {
  const calls: string[] = [];
  const response = await createDeleteAccountHandler(deps(calls))(
    await request(deletionBody("resume"), null),
  );
  assertEquals(response.status, 200);
  assertEquals(calls.slice(0, 2), [`recovery:${RECEIPT}`, "apple-exchange:fresh-code"]);
  assertEquals(calls.at(-1), `complete:${USER}:${REQUEST}:${RECEIPT}`);
});

Deno.test("resume after provider commit loss advances final close without another Apple exchange", async () => {
  const calls: string[] = [];
  const response = await createDeleteAccountHandler(deps(calls, { recovered: closing }))(
    await request(deletionBody("resume", false), null),
  );
  assertEquals(response.status, 200);
  assertEquals(calls, [
    `recovery:${RECEIPT}`,
    `complete:${USER}:${REQUEST}:${RECEIPT}`,
  ]);
});

Deno.test("completed response recovery uses the receipt and never repeats provider effects", async () => {
  const calls: string[] = [];
  const response = await createDeleteAccountHandler(deps(calls, { recovered: complete }))(
    await request(deletionBody("resume", false), null),
  );
  assertEquals(response.status, 200);
  assertEquals(calls, [`recovery:${RECEIPT}`, `advance:${RECEIPT}`]);
});

Deno.test("an expired receipt is a terminal 410 and never becomes a new deletion", async () => {
  const calls: string[] = [];
  const response = await createDeleteAccountHandler(deps(calls, { recovered: expired }))(
    await request(deletionBody("status"), null),
  );
  assertEquals(response.status, 410);
  assertEquals(await response.json(), { deleted: true, deletion: expired });
  assertEquals(calls, [`advance:${RECEIPT}`]);
});

Deno.test("resume rejects a different Apple actor rather than calling any provider cleanup", async () => {
  const calls: string[] = [];
  const response = await createDeleteAccountHandler(
    deps(calls, { subject: "different-subject", providerBindingFailure: true }),
  )(
    await request(deletionBody("resume"), null),
  );
  assertEquals(response.status, 403);
  assertEquals(calls, [
    `recovery:${RECEIPT}`,
    "apple-exchange:fresh-code",
    `binding:${RECEIPT}:different-subject`,
  ]);
});

Deno.test("a receipt can file a saved review after ordinary Auth access ends", async () => {
  const calls: string[] = [];
  const challengeId = "44444444-4444-4444-8444-444444444444";
  const response = await createDeleteAccountHandler(deps(calls))(
    await request({
      operation: "review",
      deletionReceipt: RECEIPT,
      deletionRequestId: REQUEST,
      challengeId,
      noticeRevision: 1,
      reason: "wrong_total",
    }, null),
  );
  assertEquals(response.status, 200);
  assertEquals(calls, [
    `advance:${RECEIPT}`,
    `review:${RECEIPT}:${REQUEST}:${challengeId}:1:wrong_total`,
  ]);
});
