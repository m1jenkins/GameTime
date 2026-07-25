/**
 * Who is calling.
 *
 * Every attested endpoint verifies the token in code. Hosted Supabase projects
 * can issue ES256 or RS256 access tokens from the project's injected JWKS;
 * local and legacy projects can still use their HS256 secret. The configured
 * key source chooses the algorithm — the untrusted token never does — which is
 * the line that prevents algorithm-confusion bugs.
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

/** The public verification keys Supabase injects into hosted Edge Functions. */
export type SupabaseJsonWebKey = JsonWebKey & {
  /** JWK set selector metadata; WebCrypto's narrower JsonWebKey omits it. */
  readonly kid?: string;
};

export interface JsonWebKeySet {
  readonly keys: readonly SupabaseJsonWebKey[];
}

/** Supported access-token trust sources. */
export type AccessTokenVerification =
  & (
    | { readonly kind: "legacy-hs256"; readonly secret: string }
    | { readonly kind: "jwks"; readonly jwks: JsonWebKeySet }
  )
  & {
    /**
     * Hosted handlers always set both claim bindings. They remain optional
     * only for the local/test string shorthand retained below.
     */
    readonly expectedIssuer?: string;
    readonly expectedAudience?: string;
  };

/** A handler-ready verifier with its key material closed over. */
export type AccessTokenVerifier = (
  token: string,
  now?: Date,
) => Promise<CallerIdentity>;

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

function legacyVerification(secret: string): AccessTokenVerification {
  if (secret.length < 32) {
    throw new AuthError("the configured JWT secret is too short to be genuine");
  }
  return { kind: "legacy-hs256", secret };
}

function signingInput(header: string, payload: string): Uint8Array<ArrayBuffer> {
  return utf8(`${header}.${payload}`);
}

async function verifyLegacySignature(
  verification: Extract<AccessTokenVerification, { kind: "legacy-hs256" }>,
  algorithm: unknown,
  signature: Uint8Array<ArrayBuffer>,
  input: Uint8Array<ArrayBuffer>,
): Promise<boolean> {
  if (algorithm !== "HS256") {
    throw new AuthError(
      `the configured legacy key accepts only HS256, this token says ${JSON.stringify(algorithm)}`,
    );
  }

  const key = await crypto.subtle.importKey(
    "raw",
    utf8(verification.secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
  return await crypto.subtle.verify("HMAC", key, signature, input);
}

function verificationJwk(
  jwks: JsonWebKeySet,
  kid: unknown,
  algorithm: unknown,
): SupabaseJsonWebKey {
  if (typeof kid !== "string" || kid.length === 0 || kid.length > 200) {
    throw new AuthError("an asymmetric JWT must name a key id");
  }
  if (algorithm !== "ES256" && algorithm !== "RS256") {
    throw new AuthError(
      `the configured JWKS accepts only ES256 or RS256, this token says ${
        JSON.stringify(algorithm)
      }`,
    );
  }

  const candidates = jwks.keys.filter((key) =>
    key.kid === kid &&
    (key.alg === undefined || key.alg === algorithm) &&
    (key.use === undefined || key.use === "sig") &&
    (key.key_ops === undefined || key.key_ops.includes("verify"))
  );
  if (candidates.length !== 1) {
    throw new AuthError("the JWT key id does not select exactly one trusted key");
  }
  const key = candidates[0]!;
  if (
    (algorithm === "ES256" &&
      (key.kty !== "EC" || key.crv !== "P-256" || key.x === undefined ||
        key.y === undefined)) ||
    (algorithm === "RS256" && (key.kty !== "RSA" || key.n === undefined || key.e === undefined))
  ) {
    throw new AuthError("the selected JWT key does not match its algorithm");
  }
  return key;
}

async function verifyJwksSignature(
  verification: Extract<AccessTokenVerification, { kind: "jwks" }>,
  header: Record<string, unknown>,
  signature: Uint8Array<ArrayBuffer>,
  input: Uint8Array<ArrayBuffer>,
): Promise<boolean> {
  const algorithm = header["alg"];
  const jwk = verificationJwk(verification.jwks, header["kid"], algorithm);

  try {
    if (algorithm === "ES256") {
      if (signature.length !== 64) {
        throw new AuthError("an ES256 JWT signature must be 64 bytes");
      }
      const key = await crypto.subtle.importKey(
        "jwk",
        jwk,
        { name: "ECDSA", namedCurve: "P-256" },
        false,
        ["verify"],
      );
      return await crypto.subtle.verify(
        { name: "ECDSA", hash: "SHA-256" },
        key,
        signature,
        input,
      );
    }

    const key = await crypto.subtle.importKey(
      "jwk",
      jwk,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["verify"],
    );
    return await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, signature, input);
  } catch (error) {
    if (error instanceof AuthError) throw error;
    throw new AuthError(`the selected JWT verification key is unusable: ${error}`);
  }
}

function callerFromClaims(
  claims: Record<string, unknown>,
  now: Date,
  verification: AccessTokenVerification,
): CallerIdentity {
  const exp = claims["exp"];
  if (typeof exp !== "number" || !Number.isSafeInteger(exp)) {
    throw new AuthError("the JWT has no expiry or it is not an integer");
  }
  const nowSeconds = Math.floor(now.getTime() / 1000);
  if (nowSeconds >= exp) {
    throw new AuthError("the JWT has expired");
  }

  const nbf = claims["nbf"];
  if (nbf !== undefined && (typeof nbf !== "number" || !Number.isSafeInteger(nbf))) {
    throw new AuthError("the JWT has an invalid not-before time");
  }
  if (typeof nbf === "number" && nowSeconds < nbf) {
    throw new AuthError("the JWT is not valid yet");
  }

  if (
    verification.expectedIssuer !== undefined &&
    claims["iss"] !== verification.expectedIssuer
  ) {
    throw new AuthError("the JWT was not issued by this Supabase project");
  }

  if (verification.expectedAudience !== undefined) {
    const aud = claims["aud"];
    const audienceMatches = typeof aud === "string"
      ? aud === verification.expectedAudience
      : Array.isArray(aud) &&
        aud.every((entry) => typeof entry === "string") &&
        aud.includes(verification.expectedAudience);
    if (!audienceMatches) {
      throw new AuthError("the JWT is not an authenticated-user access token");
    }
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

/**
 * Verifies a Supabase access token and returns the caller.
 *
 * A string configuration is retained as shorthand for local/tests using the
 * legacy HS256 secret. Hosted code passes the injected JWKS explicitly.
 */
export async function verifyAccessToken(
  token: string,
  configured: AccessTokenVerification | string,
  now: Date = new Date(),
): Promise<CallerIdentity> {
  const verification = typeof configured === "string" ? legacyVerification(configured) : configured;

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
  const signature = base64UrlToBytes(signatureSegment, "the JWT signature");
  const input = signingInput(headerSegment, payloadSegment);
  const valid = verification.kind === "legacy-hs256"
    ? await verifyLegacySignature(verification, header["alg"], signature, input)
    : await verifyJwksSignature(verification, header, signature, input);
  if (!valid) {
    throw new AuthError("the JWT signature does not verify");
  }

  return callerFromClaims(
    decodeJson(payloadSegment, "the JWT payload"),
    now,
    verification,
  );
}

function validateConfiguredJwks(jwks: JsonWebKeySet): void {
  if (jwks.keys.length === 0) {
    throw new AuthError("the configured Supabase JWKS contains no keys");
  }

  for (const [index, candidate] of (jwks.keys as readonly unknown[]).entries()) {
    if (candidate === null || typeof candidate !== "object" || Array.isArray(candidate)) {
      throw new AuthError(`the configured Supabase JWKS key ${index} is not an object`);
    }
    const key = candidate as Record<string, unknown>;
    if (typeof key["kid"] !== "string" || key["kid"].length === 0) {
      throw new AuthError(`the configured Supabase JWKS key ${index} has no key id`);
    }
    if (typeof key["kty"] !== "string" || key["kty"].length === 0) {
      throw new AuthError(`the configured Supabase JWKS key ${index} has no key type`);
    }
    if (key["alg"] !== undefined && typeof key["alg"] !== "string") {
      throw new AuthError(`the configured Supabase JWKS key ${index} has an invalid algorithm`);
    }
    if (key["use"] !== undefined && typeof key["use"] !== "string") {
      throw new AuthError(`the configured Supabase JWKS key ${index} has an invalid use`);
    }
    if (
      key["key_ops"] !== undefined &&
      (!Array.isArray(key["key_ops"]) ||
        !key["key_ops"].every((operation) => typeof operation === "string"))
    ) {
      throw new AuthError(`the configured Supabase JWKS key ${index} has invalid operations`);
    }
  }
}

/** Closes over configuration once at module load for handler dependency injection. */
export function createAccessTokenVerifier(
  configured: AccessTokenVerification | string,
): AccessTokenVerifier {
  // Validate a legacy secret before the first request rather than at first use.
  const verification = typeof configured === "string" ? legacyVerification(configured) : configured;
  if (verification.kind === "jwks") validateConfiguredJwks(verification.jwks);
  return (token, now = new Date()) => verifyAccessToken(token, verification, now);
}
