export type PushEnvironment = "development" | "production";

export interface ApnsCredentials {
  readonly teamId: string;
  readonly keyId: string;
  readonly privateKeyPem: string;
}

export interface LeadLossPush {
  readonly deviceToken: string;
  readonly environment: PushEnvironment;
  readonly bundleId: string;
  readonly contestId: string;
  readonly snapshotId: string;
}

export interface PushResult {
  readonly outcome: "delivered" | "retry" | "permanent_failure";
  readonly statusCode: number;
  readonly reason?: string;
}

export interface PushTransport {
  send(message: LeadLossPush): Promise<PushResult>;
}

const PERMANENT_REASONS = new Set([
  "BadDeviceToken",
  "BadTopic",
  "DeviceTokenNotForTopic",
  "MissingDeviceToken",
  "TopicDisallowed",
  "Unregistered",
]);

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function utf8(value: string): Uint8Array {
  return new TextEncoder().encode(value);
}

function buffer(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  ) as ArrayBuffer;
}

function privateKeyBytes(pem: string): Uint8Array {
  const body = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replaceAll(/\s/g, "");
  if (body === "") throw new Error("APNs private key is empty");
  try {
    return Uint8Array.from(atob(body), (character) => character.charCodeAt(0));
  } catch {
    throw new Error("APNs private key is not valid PEM");
  }
}

function boundedReason(value: unknown): string | undefined {
  if (typeof value !== "string" || value.length === 0) return undefined;
  return value.slice(0, 120);
}

export function leadLossPayload(message: LeadLossPush): Record<string, unknown> {
  return {
    aps: {
      alert: {
        title: "You lost the lead",
        body: "The standings changed. Open GameTime to see where you rank.",
      },
      sound: "default",
      category: "GAMETIME_LEAD_LOST",
      "thread-id": `contest-${message.contestId}`,
    },
    route: "standings",
    contest_id: message.contestId,
    snapshot_id: message.snapshotId,
  };
}

export class ApnsTokenTransport implements PushTransport {
  readonly #credentials: ApnsCredentials;
  readonly #fetch: typeof fetch;
  readonly #now: () => Date;
  #privateKey?: CryptoKey;
  #providerToken?: { value: string; issuedAt: number };

  constructor(
    credentials: ApnsCredentials,
    fetchImplementation: typeof fetch = fetch,
    now: () => Date = () => new Date(),
  ) {
    if (!/^[A-Z0-9]{10}$/.test(credentials.teamId)) {
      throw new Error("APNs team id must be ten uppercase alphanumerics");
    }
    if (!/^[A-Z0-9]{10}$/.test(credentials.keyId)) {
      throw new Error("APNs key id must be ten uppercase alphanumerics");
    }
    this.#credentials = credentials;
    this.#fetch = fetchImplementation;
    this.#now = now;
  }

  async send(message: LeadLossPush): Promise<PushResult> {
    const host = message.environment === "development"
      ? "https://api.sandbox.push.apple.com"
      : "https://api.push.apple.com";
    const response = await this.#fetch(`${host}/3/device/${message.deviceToken}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${await this.#token()}`,
        "content-type": "application/json",
        "apns-topic": message.bundleId,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-expiration": "0",
        "apns-collapse-id": `lead-lost-${message.snapshotId}`,
      },
      body: JSON.stringify(leadLossPayload(message)),
    });

    if (response.status === 200) {
      return { outcome: "delivered", statusCode: response.status };
    }

    let reason: string | undefined;
    try {
      reason = boundedReason((await response.json() as { reason?: unknown }).reason);
    } catch {
      // APNs can return an empty/non-JSON intermediary failure. The status is
      // enough to decide whether it is retryable.
    }

    const permanent = (reason !== undefined && PERMANENT_REASONS.has(reason)) ||
      (response.status >= 400 && response.status < 500 && response.status !== 429);
    return {
      outcome: permanent ? "permanent_failure" : "retry",
      statusCode: response.status,
      reason,
    };
  }

  async #token(): Promise<string> {
    const issuedAt = Math.floor(this.#now().getTime() / 1000);
    if (
      this.#providerToken !== undefined &&
      issuedAt - this.#providerToken.issuedAt < 50 * 60
    ) {
      return this.#providerToken.value;
    }

    const header = base64Url(utf8(JSON.stringify({
      alg: "ES256",
      kid: this.#credentials.keyId,
    })));
    const claims = base64Url(utf8(JSON.stringify({
      iss: this.#credentials.teamId,
      iat: issuedAt,
    })));
    const signingInput = `${header}.${claims}`;
    const signature = new Uint8Array(
      await crypto.subtle.sign(
        { name: "ECDSA", hash: "SHA-256" },
        await this.#key(),
        buffer(utf8(signingInput)),
      ),
    );
    const value = `${signingInput}.${base64Url(signature)}`;
    this.#providerToken = { value, issuedAt };
    return value;
  }

  async #key(): Promise<CryptoKey> {
    if (this.#privateKey !== undefined) return this.#privateKey;
    this.#privateKey = await crypto.subtle.importKey(
      "pkcs8",
      buffer(privateKeyBytes(this.#credentials.privateKeyPem)),
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["sign"],
    );
    return this.#privateKey;
  }
}
