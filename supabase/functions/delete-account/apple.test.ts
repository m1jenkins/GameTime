import { assertEquals, assertRejects } from "@std/assert";
import { createAppleTokenRevoker } from "./apple.ts";

function identityToken(subject: string): string {
  const payload = btoa(JSON.stringify({ sub: subject }))
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
  return `header.${payload}.signature`;
}

Deno.test("Apple exchange returns only a bound subject and keeps the revocation token private", async () => {
  const calls: Array<{ readonly url: string; readonly body: string }> = [];
  const apple = createAppleTokenRevoker(
    { clientId: "local.client", clientSecret: "local-secret" },
    async (input, init) => {
      calls.push({ url: String(input), body: String(init?.body) });
      if (String(input).endsWith("/auth/token")) {
        return Response.json({
          id_token: identityToken("fictional-apple-subject"),
          refresh_token: "private-local-refresh-token",
        });
      }
      return new Response(null, { status: 200 });
    },
  );

  const authorization = await apple.exchangeAuthorizationCode("fictional-code");
  assertEquals(authorization, { subject: "fictional-apple-subject" });
  await apple.revoke(authorization);
  assertEquals(calls.length, 2);
  assertEquals(calls[1]?.url, "https://appleid.apple.com/auth/revoke");
  assertEquals(calls[1]?.body.includes("private-local-refresh-token"), true);
});

Deno.test("Apple exchange rejects a token without a usable subject", async () => {
  const apple = createAppleTokenRevoker(
    { clientId: "local.client", clientSecret: "local-secret" },
    async () => Response.json({ id_token: identityToken(""), refresh_token: "token" }),
  );
  await assertRejects(
    () => apple.exchangeAuthorizationCode("fictional-code"),
    Error,
    "subject",
  );
});
