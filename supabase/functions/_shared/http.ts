/**
 * Request and response shapes shared by both ingest endpoints.
 *
 * The rule these helpers exist to keep is that a client never learns anything
 * from an error that it could not have worked out anyway. A refusal says which
 * *kind* of thing went wrong so that the client can decide whether to retry,
 * and automatic logs record only bounded classification metadata. "Your
 * assertion counter is 4 but the server has 7" is both useful debugging detail
 * and a useful attack aid, so neither the response nor the log should contain
 * it.
 */

export type FailureKind =
  /** Malformed request. Retrying identically will not help. */
  | "bad_request"
  /** The caller is not who they claim, or the attestation did not verify. */
  | "unauthorized"
  /** Well-formed and authenticated, but not allowed. */
  | "forbidden"
  /** A rule about the contest or the ledger refused it. */
  | "rejected"
  /** Server-side. Retrying may help. */
  | "internal";

const STATUS: Record<FailureKind, number> = {
  bad_request: 400,
  unauthorized: 401,
  forbidden: 403,
  rejected: 422,
  internal: 500,
};

/** A refusal a handler means to return, as opposed to a bug. */
export class HttpFailure extends Error {
  override readonly name = "HttpFailure";
  readonly kind: FailureKind;
  /**
   * Private diagnostic context carried across adapters. It never reaches the
   * client and `respond` never emits it to automatic logs.
   */
  readonly detail: string | undefined;

  constructor(kind: FailureKind, message: string, detail?: string) {
    super(message);
    this.kind = kind;
    this.detail = detail;
  }
}

const JSON_HEADERS = {
  "content-type": "application/json; charset=utf-8",
  // These endpoints are called by a native client, never a browser, so there is
  // no origin to allow. Saying so explicitly keeps a permissive default from
  // arriving with a future copy-paste.
  "cache-control": "no-store",
} as const;

export function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

export function failureResponse(failure: HttpFailure): Response {
  return jsonResponse(STATUS[failure.kind], {
    error: failure.kind,
    message: failure.message,
  });
}

/**
 * Runs a handler body, turning refusals into responses and anything else into a
 * 500 that says nothing.
 *
 * An unexpected exception is a bug, and its message may quote a payload, a
 * connection string, or a row. Automatic logs therefore keep only a trusted
 * handler label and a bounded classification; the client gets the generic form.
 */
export async function respond(
  label: string,
  body: () => Promise<Response>,
): Promise<Response> {
  const logLabel = /^[a-z0-9][a-z0-9-]{0,63}$/.test(label) ? label : "edge-handler";
  try {
    return await body();
  } catch (error) {
    if (error instanceof HttpFailure) {
      if (error.detail !== undefined) {
        console.warn(`${logLabel}: ${error.kind}`);
      }
      return failureResponse(error);
    }
    console.error(`${logLabel}: unhandled exception`);
    return jsonResponse(500, {
      error: "internal",
      message: "the request could not be processed",
    });
  }
}

/** Requires POST, since both endpoints write. */
export function requirePost(request: Request): void {
  if (request.method !== "POST") {
    throw new HttpFailure("bad_request", `${request.method} is not supported here`);
  }
}

/**
 * Reads the body as bytes, bounded.
 *
 * Bytes rather than a parsed object, because the assertion is over the exact
 * bytes that arrived. Parsing and re-serialising would sign a different
 * document than the one the client signed — JSON has many encodings of one
 * value, and the client and the server would not agree on which.
 */
export async function readBody(
  request: Request,
  maxBytes: number,
): Promise<Uint8Array<ArrayBuffer>> {
  const declared = request.headers.get("content-length");
  if (declared !== null) {
    const length = Number(declared);
    if (!Number.isInteger(length) || length < 0) {
      throw new HttpFailure("bad_request", "the Content-Length header is not a length");
    }
    if (length > maxBytes) {
      throw new HttpFailure("bad_request", `the body may be at most ${maxBytes} bytes`);
    }
  }

  const buffer = await request.arrayBuffer();
  if (buffer.byteLength > maxBytes) {
    throw new HttpFailure("bad_request", `the body may be at most ${maxBytes} bytes`);
  }
  if (buffer.byteLength === 0) {
    throw new HttpFailure("bad_request", "the request has no body");
  }
  return new Uint8Array(buffer);
}

/** Parses bytes as a JSON object. */
export function parseJsonObject(
  bytes: Uint8Array<ArrayBuffer>,
): Record<string, unknown> {
  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    throw new HttpFailure("bad_request", "the body is not valid UTF-8");
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new HttpFailure("bad_request", "the body is not valid JSON");
  }

  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new HttpFailure("bad_request", "the body is not a JSON object");
  }
  return parsed as Record<string, unknown>;
}

// ---------------------------------------------------------------------------
// Field readers
// ---------------------------------------------------------------------------
// Each returns the value or throws a refusal naming the field. Written out
// rather than reached for from a validation library so that the failure text is
// the repo's own and a missing field cannot arrive as `undefined`.

export function requireString(
  body: Record<string, unknown>,
  field: string,
  maxLength = 4096,
): string {
  const value = body[field];
  if (typeof value !== "string" || value === "") {
    throw new HttpFailure("bad_request", `${field} must be a non-empty string`);
  }
  if (value.length > maxLength) {
    throw new HttpFailure("bad_request", `${field} is longer than ${maxLength} characters`);
  }
  return value;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function requireUuid(body: Record<string, unknown>, field: string): string {
  const value = requireString(body, field, 36);
  if (!UUID.test(value)) {
    throw new HttpFailure("bad_request", `${field} must be a UUID`);
  }
  return value.toLowerCase();
}

export function requireArray(
  body: Record<string, unknown>,
  field: string,
  maxLength: number,
): unknown[] {
  const value = body[field];
  if (!Array.isArray(value)) {
    throw new HttpFailure("bad_request", `${field} must be an array`);
  }
  if (value.length === 0) {
    throw new HttpFailure("bad_request", `${field} must not be empty`);
  }
  if (value.length > maxLength) {
    throw new HttpFailure("bad_request", `${field} may hold at most ${maxLength} entries`);
  }
  return value;
}
