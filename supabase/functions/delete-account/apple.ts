import type { AppleTokenRevoker } from "./handler.ts";

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
  // Never surface Apple's response body: it may contain provider diagnostics
  // that are not useful to the app and should not be logged or echoed.
  throw new Error(`${label} failed with status ${response.status}`);
}

export function createAppleTokenRevoker(
  config: AppleTokenRevocationConfig,
  fetcher: FetchLike = fetch,
): AppleTokenRevoker {
  return {
    async revokeAuthorizationCode(code) {
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
      const token = typeof refreshToken === "string"
        ? refreshToken
        : typeof accessToken === "string"
        ? accessToken
        : undefined;
      if (token === undefined) {
        throw new Error("Apple did not return a revocable token");
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
          token,
        }),
      });
      requireSuccess(revokeResponse, "Apple token revocation");
    },
  };
}
