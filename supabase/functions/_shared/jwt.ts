/**
 * Who is calling.
 *
 * Supabase verifies a function's JWT at the gateway when `verify_jwt` is on,
 * and this verifies it again. That is not redundancy for its own sake: the
 * gateway check is a per-function configuration flag, and the cost of it being
 * flipped — by a deploy, by a copied config, by someone debugging — is that an
 * ingest endpoint starts trusting an unsigned claim about whose evidence it is
 * writing. A verification that lives in the code cannot be turned off by
 * configuration, and the whole of M3 rests on knowing which account a
 * measurement belongs to.
 *
 * Only HS256 is accepted. Allowing the algorithm to be chosen by the token is
 * how algorithm-confusion bugs happen, and "none" is the degenerate case of it.
 */

import { utf8 } from "./bytes.ts";

export class AuthError extends Error {
  override readonly name = "AuthError";
}

/** The claims this codebase relies on. */
export interface CallerIdentity {
  /** The account id: `auth.uid()` on the database side. */
  readonly userId: string;
  readonly role: string;
  readonly expiresAt: number;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function base64UrlToBytes(value: string, what: string): Uint8Array<ArrayBuffer> {
  // A JWT segment is base64url with the padding stripped, which `atob` will not
  // take, so it is translated rather than fed in raw.
  const padded = value.replaceAll("-", "+").replaceAll("_", "/") +
    "=".repeat((4 - (value.length % 4)) % 4);
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(padded)) {
    throw new AuthError(`${what} is not base64url`);
  }
  try {
    const raw = atob(padded);
    const out = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
    return out;
  } catch {
    throw new AuthError(`${what} is not base64url`);
  }
}

function decodeJson(segment: string, what: string): Record<string, unknown> {
  let text: string;
  try {
    // `fatal: true` rejects malformed UTF-8 rather than substituting U+FFFD,
    // and it does so with a bare TypeError — which has to become an AuthError
    // here or a malformed token surfaces as a 500 instead of a refusal.
    text = new TextDecoder("utf-8", { fatal: true })
      .decode(base64UrlToBytes(segment, what));
  } catch (error) {
    if (error instanceof AuthError) throw error;
    throw new AuthError(`${what} is not valid UTF-8`);
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new AuthError(`${what} is not JSON`);
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new AuthError(`${what} is not a JSON object`);
  }
  return parsed as Record<string, unknown>;
}

/** Pulls the bearer token out of an Authorization header. */
export function bearerToken(request: Request): string {
  const header = request.headers.get("authorization");
  if (header === null) {
    throw new AuthError("the Authorization header is missing");
  }
  const match = /^Bearer\s+(\S+)$/i.exec(header.trim());
  if (match === null) {
    throw new AuthError("the Authorization header is not a bearer token");
  }
  return match[1]!;
}

/**
 * Verifies an HS256 Supabase access token and returns the caller.
 *
 * `now` is injectable so that expiry can be tested without waiting an hour or
 * minting a token in the past, which is the same reasoning that made
 * `app.activate_due_contests()` take a clock.
 */
export async function verifyAccessToken(
  token: string,
  secret: string,
  now: Date = new Date(),
): Promise<CallerIdentity> {
  if (secret.length < 32) {
    // Supabase's own secret is at least 32 characters. A shorter one is a
    // misconfiguration, and failing loudly beats verifying against it.
    throw new AuthError("the configured JWT secret is too short to be genuine");
  }

  const parts = token.split(".");
  if (parts.length !== 3) {
    throw new AuthError(`a JWT has three segments, this has ${parts.length}`);
  }
  const [headerSegment, payloadSegment, signatureSegment] = parts as [
    string,
    string,
    string,
  ];

  const header = decodeJson(headerSegment, "the JWT header");
  if (header["alg"] !== "HS256") {
    throw new AuthError(
      `only HS256 tokens are accepted, this one says ${JSON.stringify(header["alg"])}`,
    );
  }

  const key = await crypto.subtle.importKey(
    "raw",
    utf8(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );

  const valid = await crypto.subtle.verify(
    "HMAC",
    key,
    base64UrlToBytes(signatureSegment, "the JWT signature"),
    utf8(`${headerSegment}.${payloadSegment}`),
  );
  if (!valid) {
    throw new AuthError("the JWT signature does not verify");
  }

  const claims = decodeJson(payloadSegment, "the JWT payload");

  const exp = claims["exp"];
  if (typeof exp !== "number") {
    throw new AuthError("the JWT has no expiry");
  }
  const nowSeconds = Math.floor(now.getTime() / 1000);
  if (nowSeconds >= exp) {
    throw new AuthError("the JWT has expired");
  }

  const nbf = claims["nbf"];
  if (typeof nbf === "number" && nowSeconds < nbf) {
    throw new AuthError("the JWT is not valid yet");
  }

  // A signed-in user's token carries role "authenticated". The project's
  // publishable key is also a valid HS256 token signed by the same secret, so
  // without this check it would authenticate as somebody — and the role is the
  // thing that distinguishes it.
  const role = claims["role"];
  if (role !== "authenticated") {
    throw new AuthError(
      `only an authenticated user may call this, not ${JSON.stringify(role)}`,
    );
  }

  const sub = claims["sub"];
  if (typeof sub !== "string" || !UUID.test(sub)) {
    throw new AuthError("the JWT carries no account id");
  }

  return { userId: sub, role, expiresAt: exp };
}
