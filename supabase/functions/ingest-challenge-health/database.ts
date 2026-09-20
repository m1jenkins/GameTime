import { toHex } from "../_shared/bytes.ts";
import type { PostgrestConfig } from "../_shared/database.ts";
import { HttpFailure } from "../_shared/http.ts";
import type { RealHealthIngestArgs, RealHealthReadinessArgs } from "./handler.ts";

/** No raw database messages or submitted health values reach logs or errors. */
export function realHealthDatabase(config: PostgrestConfig) {
  return async (args: RealHealthIngestArgs): Promise<unknown> => {
    const receipt = await call(config, "challenge_real_health_ingest_v1", args, {
      p_payload: args.payload,
    });
    if (
      Object.keys(receipt).sort().join(",") !==
        "accepted_at,challenge_id,request_id,revision,version" ||
      receipt.version !== "challenge_real_health_receipt_v1" ||
      receipt.challenge_id !== args.payload.challenge_id.toLowerCase() ||
      receipt.revision !== args.payload.revision
    ) throw new HttpFailure("internal", "We couldn’t confirm this update. Try again in a moment.");
    return receipt;
  };
}

export function realHealthReadinessDatabase(config: PostgrestConfig) {
  return async (args: RealHealthReadinessArgs): Promise<unknown> => {
    const receipt = await call(config, "challenge_real_health_readiness_v1", args, {
      p_actor_id: args.payload.actor_id,
      p_source_policy_version: args.payload.source_policy_version,
      p_observed_at: args.payload.observed_at,
      ...(args.payload.distance_mm === undefined
        ? {}
        : { p_distance_mm: args.payload.distance_mm }),
    });
    if (
      Object.keys(receipt).sort().join(",") !== "accepted_at,request_id,version" ||
      receipt.version !== "challenge_real_health_readiness_receipt_v1"
    ) {
      throw new HttpFailure("internal", "We couldn’t confirm this update. Try again in a moment.");
    }
    return receipt;
  };
}

async function call(
  config: PostgrestConfig,
  name: string,
  args: RealHealthIngestArgs | RealHealthReadinessArgs,
  fields: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  let response: Response;
  try {
    response = await fetch(`${config.url}/rest/v1/rpc/${name}`, {
      method: "POST",
      redirect: "error",
      headers: {
        "content-type": "application/json",
        "apikey": config.serviceRoleKey,
        ...(config.authorizationBearer === false ? {} : {
          "authorization": `Bearer ${config.serviceRoleKey}`,
        }),
      },
      body: JSON.stringify({
        p_request_id: args.payload.request_id,
        ...fields,
        p_session_id: args.sessionID,
        p_token_expires_at: args.tokenExpiresAt,
        p_device_key_id: args.keyID === null ? null : `\\x${toHex(args.keyID)}`,
        p_assertion_counter: args.signCount,
        p_payload_digest: `\\x${toHex(args.payloadDigest)}`,
        p_recovery_only: args.recoveryOnly,
      }),
    });
  } catch {
    throw new HttpFailure("internal", "We couldn’t save your activity. Try again in a moment.");
  }
  let result: unknown;
  try {
    result = await response.json();
  } catch {
    throw new HttpFailure("internal", "We couldn’t confirm this update. Try again in a moment.");
  }
  if (!response.ok) {
    const code = (result as { code?: string } | null)?.code;
    if (code === "42501" || code === "28000") {
      throw new HttpFailure(
        "forbidden",
        "We couldn’t accept this update. Sign in again and try again.",
      );
    }
    if (code && ["22023", "23514", "23505", "23001", "40001"].includes(code)) {
      throw new HttpFailure(
        "rejected",
        "This activity update couldn’t be saved. Refresh your challenge and try again.",
      );
    }
    throw new HttpFailure("internal", "We couldn’t save your activity. Try again in a moment.");
  }
  if (!result || typeof result !== "object" || Array.isArray(result)) {
    throw new HttpFailure("internal", "We couldn’t confirm this update. Try again in a moment.");
  }
  const receipt = result as Record<string, unknown>;
  if (
    receipt.request_id !== args.payload.request_id.toLowerCase() ||
    typeof receipt.accepted_at !== "string"
  ) {
    throw new HttpFailure("internal", "We couldn’t confirm this update. Try again in a moment.");
  }
  return receipt;
}
