import type { PostgrestConfig } from "./database.ts";

export async function serviceRpc(
  config: PostgrestConfig,
  name: string,
  args: Readonly<Record<string, unknown>>,
): Promise<unknown> {
  const headers: Record<string, string> = {
    "content-type": "application/json",
    "accept": "application/json",
    "apikey": config.serviceRoleKey,
  };
  if (config.authorizationBearer !== false) {
    headers.authorization = `Bearer ${config.serviceRoleKey}`;
  }

  let response: Response;
  try {
    response = await fetch(`${config.url}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers,
      body: JSON.stringify(args),
    });
  } catch {
    throw new Error(`${name} is unavailable`);
  }
  const body = await response.text();
  if (!response.ok) {
    throw new Error(`${name} failed with status ${response.status}`);
  }
  return body === "" ? null : JSON.parse(body);
}

export function oneServiceRow(
  value: unknown,
  name: string,
): Record<string, unknown> {
  const candidate = Array.isArray(value) ? value[0] : value;
  if (
    candidate === null ||
    typeof candidate !== "object" ||
    Array.isArray(candidate)
  ) {
    throw new Error(`${name} returned an unexpected shape`);
  }
  return candidate as Record<string, unknown>;
}

export function requiredServiceString(
  row: Record<string, unknown>,
  field: string,
  prefix?: string,
): string {
  const value = row[field];
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > 255 ||
    (prefix !== undefined && !value.startsWith(prefix))
  ) {
    throw new Error(`service RPC returned an invalid ${field}`);
  }
  return value;
}
