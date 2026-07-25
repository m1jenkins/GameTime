import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { AuthError, bearerToken, verifyAccessToken } from "./jwt.ts";
import { mintAccessToken, TEST_JWT_SECRET } from "../_test/tokens.ts";

const USER = "11111111-1111-1111-1111-111111111111";

Deno.test("accepts a well-formed access token", async () => {
  const token = await mintAccessToken(USER);
  const caller = await verifyAccessToken(token, TEST_JWT_SECRET);
  assertEquals(caller.userId, USER);
  assertEquals(caller.role, "authenticated");
});

Deno.test("refuses a token signed with a different secret", async () => {
  const token = await mintAccessToken(USER, {
    secret: "a-different-secret-that-is-also-long-enough",
  });
  await assertRejects(
    () => verifyAccessToken(token, TEST_JWT_SECRET),
    AuthError,
    "signature does not verify",
  );
});

Deno.test("refuses a token whose payload was edited after signing", async () => {
  // The attack the signature exists to stop: take your own token and change
  // `sub` to somebody else's, so their evidence gets written under your device.
  const token = await mintAccessToken(USER);
  const [header, _payload, signature] = token.split(".") as [string, string, string];
  const forged = btoa(JSON.stringify({
    aud: "authenticated",
    role: "authenticated",
    exp: Math.floor(Date.now() / 1000) + 3600,
    sub: "22222222-2222-2222-2222-222222222222",
  })).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");

  await assertRejects(
    () => verifyAccessToken(`${header}.${forged}.${signature}`, TEST_JWT_SECRET),
    AuthError,
    "signature does not verify",
  );
});

Deno.test("refuses alg:none and any algorithm but HS256", async () => {
  // Algorithm confusion: the token names the algorithm, so a verifier that
  // believes it can be told to check nothing at all.
  for (const algorithm of ["none", "HS512", "RS256", "ES256"]) {
    const token = await mintAccessToken(USER, { algorithm });
    await assertRejects(
      () => verifyAccessToken(token, TEST_JWT_SECRET),
      AuthError,
      "only HS256",
    );
  }
});

Deno.test("refuses an expired token, and one that is not valid yet", async () => {
  const nowSeconds = Math.floor(Date.now() / 1000);

  const expired = await mintAccessToken(USER, { expiresAt: nowSeconds - 1 });
  await assertRejects(
    () => verifyAccessToken(expired, TEST_JWT_SECRET),
    AuthError,
    "expired",
  );

  const future = await mintAccessToken(USER, { notBefore: nowSeconds + 600 });
  await assertRejects(
    () => verifyAccessToken(future, TEST_JWT_SECRET),
    AuthError,
    "not valid yet",
  );

  // And the clock is injectable, so the same token verifies at a time it covers.
  assertEquals(
    (await verifyAccessToken(
      future,
      TEST_JWT_SECRET,
      new Date((nowSeconds + 900) * 1000),
    )).userId,
    USER,
  );
});

Deno.test("refuses a token with no expiry at all", async () => {
  const token = await mintAccessToken(USER, {
    claims: { role: "authenticated", sub: USER },
  });
  await assertRejects(
    () => verifyAccessToken(token, TEST_JWT_SECRET),
    AuthError,
    "no expiry",
  );
});

Deno.test("refuses the anon and service_role keys", async () => {
  // Both are HS256 tokens signed with the same project secret, so the signature
  // check passes for both. The role claim is what tells them apart from a user,
  // and the publishable one is printed in every client bundle.
  for (const role of ["anon", "service_role"]) {
    const token = await mintAccessToken(null, {
      claims: { role, exp: Math.floor(Date.now() / 1000) + 3600 },
    });
    await assertRejects(
      () => verifyAccessToken(token, TEST_JWT_SECRET),
      AuthError,
      "only an authenticated user",
    );
  }
});

Deno.test("refuses an authenticated token with no account id", async () => {
  const token = await mintAccessToken(null);
  await assertRejects(
    () => verifyAccessToken(token, TEST_JWT_SECRET),
    AuthError,
    "no account id",
  );
});

Deno.test("refuses a subject that is not a uuid", async () => {
  const token = await mintAccessToken("not-a-uuid");
  await assertRejects(
    () => verifyAccessToken(token, TEST_JWT_SECRET),
    AuthError,
    "no account id",
  );
});

Deno.test("refuses malformed tokens and a short secret", async () => {
  await assertRejects(
    () => verifyAccessToken("a.b", TEST_JWT_SECRET),
    AuthError,
    "three segments",
  );
  await assertRejects(
    () => verifyAccessToken("!!!.!!!.!!!", TEST_JWT_SECRET),
    AuthError,
    "base64url",
  );

  const token = await mintAccessToken(USER);
  await assertRejects(
    () => verifyAccessToken(token, "too-short"),
    AuthError,
    "too short to be genuine",
  );
});

Deno.test("reads a bearer token out of the Authorization header", () => {
  const withHeader = (value: string | null) =>
    new Request("https://example.test/", {
      headers: value === null ? {} : { authorization: value },
    });

  assertEquals(bearerToken(withHeader("Bearer abc.def.ghi")), "abc.def.ghi");
  assertEquals(bearerToken(withHeader("bearer abc.def.ghi")), "abc.def.ghi");

  assertThrows(() => bearerToken(withHeader(null)), AuthError, "missing");
  assertThrows(() => bearerToken(withHeader("abc.def.ghi")), AuthError, "not a bearer");
  assertThrows(() => bearerToken(withHeader("Basic abc")), AuthError, "not a bearer");
});
