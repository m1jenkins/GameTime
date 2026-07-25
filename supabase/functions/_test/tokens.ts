/**
 * Mints Supabase-shaped access tokens for the suites.
 *
 * Lives under `_test` for the same reason the App Attest fixtures do: nothing a
 * deployed function imports should be able to sign a token.
 */

import { utf8 } from "../_shared/bytes.ts";

/** The local stack's JWT secret shape: at least 32 characters. */
export const TEST_JWT_SECRET = "super-secret-jwt-token-with-at-least-32-characters-long";
export const TEST_CHALLENGE_SECRET = "separate-app-attest-challenge-secret-for-tests";
export const TEST_AUTH_ISSUER = "http://127.0.0.1:54321/auth/v1";

function toBase64Url(bytes: Uint8Array<ArrayBuffer>): string {
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

export interface TokenOptions {
  readonly secret?: string;
  readonly role?: string;
  readonly expiresAt?: number;
  readonly notBefore?: number;
  /** Overrides the header, for the algorithm-confusion cases. */
  readonly algorithm?: string;
  /** Replaces the whole payload, for the missing-claim cases. */
  readonly claims?: Record<string, unknown>;
}

export async function mintAccessToken(
  userId: string | null,
  options: TokenOptions = {},
): Promise<string> {
  const secret = options.secret ?? TEST_JWT_SECRET;
  const header = { alg: options.algorithm ?? "HS256", typ: "JWT" };

  const claims = options.claims ?? {
    aud: "authenticated",
    iss: TEST_AUTH_ISSUER,
    role: options.role ?? "authenticated",
    exp: options.expiresAt ?? Math.floor(Date.now() / 1000) + 3600,
    iat: Math.floor(Date.now() / 1000),
    ...(userId === null ? {} : { sub: userId }),
    ...(options.notBefore === undefined ? {} : { nbf: options.notBefore }),
  };

  const encodedHeader = toBase64Url(utf8(JSON.stringify(header)));
  const encodedClaims = toBase64Url(utf8(JSON.stringify(claims)));

  const key = await crypto.subtle.importKey(
    "raw",
    utf8(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, utf8(`${encodedHeader}.${encodedClaims}`)),
  );

  return `${encodedHeader}.${encodedClaims}.${toBase64Url(signature)}`;
}
