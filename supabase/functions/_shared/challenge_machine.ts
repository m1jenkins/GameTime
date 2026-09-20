/** Fixed, private Cron-to-Edge request and PostgREST helpers. */
import type { PostgrestConfig } from "./database.ts";

export const MACHINE_RPC_TIMEOUT_MS = 5_000;
export const MACHINE_RPC_ATTEMPTS = 3;
const MAX_BODY_BYTES = 256;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const INVOCATION_BODY =
  /^\s*\{\s*"invocation_id"\s*:\s*"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"\s*\}\s*$/i;

export type MachineErrorCategory = "timeout" | "unavailable";

export class MachineRpcError extends Error {
  constructor(readonly category: MachineErrorCategory) {
    super(category);
  }
}

function sameSecret(left: string, right: string): boolean {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  let difference = a.length ^ b.length;
  for (let i = 0; i < Math.max(a.length, b.length); i += 1) {
    difference |= (a[i] ?? 0) ^ (b[i] ?? 0);
  }
  return difference === 0;
}

export function requireMachineSecret(secret: string): string {
  if (secret.length < 32 || secret.length > 256) {
    throw new Error("machine dispatch secret must contain 32 to 256 characters");
  }
  return secret;
}

export function requireDistinctMachineSecrets(worker: string, monitor: string): void {
  requireMachineSecret(worker);
  requireMachineSecret(monitor);
  if (sameSecret(worker, monitor)) {
    throw new Error("worker and monitor dispatch secrets must be distinct");
  }
}

export function machineAuthorized(request: Request, header: string, secret: string): boolean {
  const supplied = request.headers.get(header) ?? "";
  return supplied.length <= 256 && sameSecret(supplied, secret);
}

export function machineJson(status: number, body: Readonly<Record<string, unknown>>): Response {
  return Response.json(body, {
    status,
    headers: { "cache-control": "no-store" },
  });
}

/** Return only an exact object; never reflect malformed request text. */
export async function machineBody(
  request: Request,
  kind: "invocation" | "monitor",
): Promise<{ invocationId: string } | Record<string, never> | null> {
  if (
    !/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(
      request.headers.get("content-type") ?? "",
    )
  ) return null;
  const declared = request.headers.get("content-length");
  if (declared !== null && (!/^\d+$/.test(declared) || Number(declared) > MAX_BODY_BYTES)) {
    return null;
  }
  let bytes: Uint8Array;
  try {
    const reader = request.body?.getReader();
    if (reader === undefined) return null;
    const chunks: Uint8Array[] = [];
    let length = 0;
    while (true) {
      const item = await reader.read();
      if (item.done) break;
      length += item.value.length;
      if (length > MAX_BODY_BYTES) {
        await reader.cancel();
        return null;
      }
      chunks.push(item.value);
    }
    bytes = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.length;
    }
  } catch {
    return null;
  }
  if (bytes.length === 0 || bytes.length > MAX_BODY_BYTES) return null;
  let value: string;
  try {
    value = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    return null;
  }
  if (kind === "monitor") return /^\s*\{\s*\}\s*$/.test(value) ? {} : null;
  const match = INVOCATION_BODY.exec(value);
  return match?.[1] && UUID.test(match[1]) ? { invocationId: match[1].toLowerCase() } : null;
}

/** Each call is a separate committed RPC. Retries replay exact argument bytes. */
export async function machineRpc(
  config: PostgrestConfig,
  name: string,
  args: Readonly<Record<string, unknown>>,
  fetcher: typeof fetch = fetch,
  deadlineAt = Number.POSITIVE_INFINITY,
): Promise<unknown> {
  const body = JSON.stringify(args);
  let last: MachineRpcError = new MachineRpcError("unavailable");
  for (let attempt = 0; attempt < MACHINE_RPC_ATTEMPTS; attempt += 1) {
    const remaining = deadlineAt - Date.now();
    if (remaining <= 0) throw new MachineRpcError("timeout");
    try {
      const response = await fetcher(`${config.url}/rest/v1/rpc/${name}`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "accept": "application/json",
          "apikey": config.serviceRoleKey,
          ...(config.authorizationBearer === false ? {} : {
            "authorization": `Bearer ${config.serviceRoleKey}`,
          }),
        },
        body,
        signal: AbortSignal.timeout(Math.min(MACHINE_RPC_TIMEOUT_MS, remaining)),
      });
      if (!response.ok) throw new MachineRpcError("unavailable");
      return await response.json();
    } catch (error) {
      last = error instanceof DOMException && error.name === "TimeoutError"
        ? new MachineRpcError("timeout")
        : error instanceof MachineRpcError
        ? error
        : new MachineRpcError("unavailable");
    }
  }
  throw last;
}

export function machineRecord(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

export function machineCount(value: unknown, maximum = 1_000_000): number | null {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 &&
      value <= maximum
    ? value
    : null;
}

export function machineTime(value: unknown): string | null {
  return typeof value === "string" && value.length <= 40 &&
      /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/.test(value) &&
      Number.isFinite(Date.parse(value))
    ? value
    : null;
}

export function machineState(value: unknown, allowed: readonly string[]): string | null {
  return typeof value === "string" && allowed.includes(value) ? value : null;
}
