import { toHex } from "../_shared/bytes.ts";
import type { PostgrestConfig } from "../_shared/database.ts";
import { HttpFailure } from "../_shared/http.ts";
import type { RealHealthIngestArgs, RealHealthReadinessArgs } from "./handler.ts";

/**
 * Refusals the RPCs raise only after their exact replay found no saved
 * response. For an update built while its challenge was scheduled, active or
 * syncing, as the app requires, none can reverse: the frozen terms, status or
 * membership no longer take it, the revision is taken or past its cutoff, or
 * the request ID holds other bytes. (Only a community lobby still open past its
 * start can later begin taking updates.) The client may stop retrying these;
 * every other refusal, including an early clock or a serialization failure,
 * carries no reason and stays retryable.
 */
const PERMANENT_REFUSALS: Readonly<Record<string, string>> = {
  challenge_real_health_binding_invalid: "challenge_closed",
  challenge_invalid_real_health_revision: "revision_not_accepted",
  challenge_request_conflict: "request_conflict",
};

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
    const { code, message } = (result ?? {}) as { code?: unknown; message?: unknown };
    if (code === "42501" || code === "28000") {
      throw new HttpFailure(
        "forbidden",
        "We couldn’t accept this update. Sign in again and try again.",
      );
    }
    const reason = code === "22023" && typeof message === "string" &&
        Object.hasOwn(PERMANENT_REFUSALS, message)
      ? PERMANENT_REFUSALS[message]
      : undefined;
    if (reason) {
      throw new HttpFailure(
        "rejected",
        "This challenge can’t take this activity update. Refresh your challenge to see what we saved.",
        undefined,
        reason,
      );
    }
    if (typeof code === "string" && ["22023", "23514", "23505", "23001", "40001"].includes(code)) {
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
