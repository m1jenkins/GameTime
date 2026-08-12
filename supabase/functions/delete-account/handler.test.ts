import { assertEquals } from "@std/assert";
import { createAccessTokenVerifier } from "../_shared/jwt.ts";
import { mintAccessToken, TEST_JWT_SECRET } from "../_test/tokens.ts";
import {
  type AccountDeletionDatabase,
  type AccountDeletionProviderIds,
  createDeleteAccountHandler,
  type DeleteAccountDeps,
  type StripeCustomerDeleter,
} from "./handler.ts";

const USER = "11111111-1111-1111-1111-111111111111";

function request(body: Record<string, unknown>, token?: string): Promise<Request> {
  return (async () =>
    new Request("https://example.test/delete-account", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(token === undefined
          ? { authorization: `Bearer ${await mintAccessToken(USER)}` }
          : { authorization: `Bearer ${token}` }),
      },
      body: JSON.stringify(body),
    }))();
}

function deps(
  calls: string[],
  providerIds: AccountDeletionProviderIds = { stripeCustomerId: "cus_test" },
): DeleteAccountDeps {
  const database: AccountDeletionDatabase = {
    providerIds(ownerId) {
      calls.push(`provider:${ownerId}`);
      return Promise.resolve(providerIds);
    },
    deleteAccount(ownerId) {
      calls.push(`delete:${ownerId}`);
      return Promise.resolve();
    },
  };
  const stripe: StripeCustomerDeleter = {
    deleteTestCustomer(customerId) {
      calls.push(`stripe:${customerId}`);
      return Promise.resolve();
    },
  };
  return {
    database,
    apple: {
      revokeAuthorizationCode(code) {
        calls.push(`apple:${code}`);
        return Promise.resolve();
      },
    },
    stripe,
    verifyToken: createAccessTokenVerifier(TEST_JWT_SECRET),
  };
}

Deno.test("deletes only after fresh Apple and provider cleanup", async () => {
  const calls: string[] = [];
  const handler = createDeleteAccountHandler(deps(calls));

  const response = await handler(
    await request({ appleAuthorizationCode: "fresh-code" }),
  );

  assertEquals(response.status, 200);
  assertEquals(await response.json(), { deleted: true });
  assertEquals(calls, [
    `provider:${USER}`,
    "apple:fresh-code",
    "stripe:cus_test",
    `delete:${USER}`,
  ]);
});

Deno.test("allows an account without a Stripe Customer", async () => {
  const calls: string[] = [];
  const handler = createDeleteAccountHandler(deps(calls, {}));
  const response = await handler(
    await request({ appleAuthorizationCode: "fresh-code" }),
  );

  assertEquals(response.status, 200);
  assertEquals(calls, [
    `provider:${USER}`,
    "apple:fresh-code",
    `delete:${USER}`,
  ]);
});

Deno.test("does not expose the service operation without a valid request", async () => {
  const calls: string[] = [];
  const handler = createDeleteAccountHandler(deps(calls));
  assertEquals(
    (await handler(await request({}))).status,
    400,
  );
  assertEquals(calls, []);
});

Deno.test("refuses a missing caller before reading deletion input", async () => {
  const calls: string[] = [];
  const handler = createDeleteAccountHandler(deps(calls));
  const response = await handler(
    await request({ appleAuthorizationCode: "fresh-code" }, "not-a-jwt"),
  );
  assertEquals(response.status, 401);
  assertEquals(calls, []);
});
