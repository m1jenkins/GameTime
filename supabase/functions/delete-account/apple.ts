import type { AppleAuthorization, AppleTokenRevoker } from "./handler.ts";

const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";

export interface AppleTokenRevocationConfig {
  readonly clientId: string;
  readonly clientSecret: string;
}

type FetchLike = (
  input: string | URL | Request,
  init?: RequestInit,
) => Promise<Response>;

function formBody(values: Record<string, string>): string {
  return new URLSearchParams(values).toString();
}

function requireSuccess(response: Response, label: string): void {
  if (response.ok) return;
  throw new Error(`${label} failed with status ${response.status}`);
}

function tokenSubject(idToken: unknown): string {
  if (typeof idToken !== "string") throw new Error("Apple did not return an identity token");
  const parts = idToken.split(".");
  const payloadSegment = parts[1];
  if (
    parts.length !== 3 || payloadSegment === undefined || payloadSegment.length === 0 ||
    payloadSegment.length > 4096
  ) {
    throw new Error("Apple identity token is invalid");
  }
  try {
    const padded = payloadSegment.replace(/-/g, "+").replace(/_/g, "/") +
      "=".repeat((4 - payloadSegment.length % 4) % 4);
    const payload = JSON.parse(
      new TextDecoder().decode(Uint8Array.from(atob(padded), (value) => value.charCodeAt(0))),
    ) as Record<string, unknown>;
    const subject = payload["sub"];
    if (typeof subject !== "string" || subject.length === 0 || subject.length > 255) {
      throw new Error("Apple identity token has no subject");
    }
    return subject;
  } catch (error) {
    if (error instanceof Error) throw error;
    throw new Error("Apple identity token is invalid");
  }
}

export function createAppleTokenRevoker(
  config: AppleTokenRevocationConfig,
  fetcher: FetchLike = fetch,
): AppleTokenRevoker {
  const revocationTokens = new WeakMap<AppleAuthorization, string>();
  return {
    async exchangeAuthorizationCode(code): Promise<AppleAuthorization> {
      const tokenResponse = await fetcher(APPLE_TOKEN_URL, {
        method: "POST",
        headers: {
          "content-type": "application/x-www-form-urlencoded",
          "accept": "application/json",
        },
        body: formBody({
          client_id: config.clientId,
          client_secret: config.clientSecret,
          code,
          grant_type: "authorization_code",
        }),
      });
      requireSuccess(tokenResponse, "Apple authorization validation");
      const tokenBody = await tokenResponse.json() as Record<string, unknown>;
      const refreshToken = tokenBody["refresh_token"];
      const accessToken = tokenBody["access_token"];
      const revokeToken = typeof refreshToken === "string"
        ? refreshToken
        : typeof accessToken === "string"
        ? accessToken
        : undefined;
      if (revokeToken === undefined) throw new Error("Apple did not return a revocable token");
      const authorization: AppleAuthorization = Object.freeze({
        subject: tokenSubject(tokenBody["id_token"]),
      });
      // The opaque provider token is deliberately not a response property: it
      // cannot reach a receipt, JSON body, or error/log formatter.
      revocationTokens.set(authorization, revokeToken);
      return authorization;
    },
    async revoke(authorization): Promise<void> {
      const revokeToken = revocationTokens.get(authorization);
      if (typeof revokeToken !== "string" || revokeToken.length === 0) {
        throw new Error("Apple authorization cannot be revoked");
      }
      const revokeResponse = await fetcher(APPLE_REVOKE_URL, {
        method: "POST",
        headers: {
          "content-type": "application/x-www-form-urlencoded",
          "accept": "application/json",
        },
        body: formBody({
          client_id: config.clientId,
          client_secret: config.clientSecret,
          token: revokeToken,
        }),
      });
      requireSuccess(revokeResponse, "Apple token revocation");
    },
  };
}
