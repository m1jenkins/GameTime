/**
 * POST /attest-device          registers one App Attest key against one account
 * POST /attest-device/challenge issues the challenge that registration binds to
 *
 * Registration runs once per app install. The client generates a key in the
 * Secure Enclave, asks Apple to attest it, and sends the attestation object
 * here; the response records the verified environment and, when iOS 27
 * supplies them, category/build signals for the conformance log. What is left
 * behind is a row in `device_attestations` that every later ingest is checked
 * against.
 *
 * Two routes in one function rather than two functions, because they are one
 * exchange: the challenge is meaningless on its own and the client always makes
 * both calls back to back.
 *
 * ---------------------------------------------------------------------------
 * The challenge, and why it is derived rather than stored
 * ---------------------------------------------------------------------------
 * An attestation is bound to a challenge so that a captured one cannot be
 * replayed. The usual shape is a table of server-issued single-use nonces, and
 * this does not have one: the challenge is an HMAC over the caller's account id
 * and a coarse time window, keyed by a dedicated server secret. That makes it
 * verifiable without state, unguessable without the secret, and bound to the
 * one account that may present it. Keeping it independent from access-token
 * verification also works with hosted Supabase's asymmetric signing keys and
 * avoids turning public JWKS material into challenge key material.
 *
 * What a stored nonce would add is single use, and here that is already covered
 * from the other side: `key_id` is a primary key, so a replayed attestation is a
 * re-registration of a key that already exists, and `register_device_key()`
 * refuses that for anyone but the key's original owner. The replay a stored
 * nonce prevents is therefore a replay that cannot achieve anything.
 *
 * The trade it does make is a window in which one challenge is valid more than
 * once for one account. Since all that window permits is that account
 * re-registering its own key, it costs nothing.
 */

import {
  AttestationError,
  type AttestEnvironment,
  base64ToBytes,
  verifyAttestation,
} from "../_shared/appattest.ts";
import { ReceiptVerificationError, verifyAppAttestReceipt } from "../_shared/appattest_receipt.ts";
import { type Bytes, utf8 } from "../_shared/bytes.ts";
import {
  asCborBytes,
  asCborBytesArray,
  asCborMap,
  asCborText,
  CborError,
  decodeCbor,
} from "../_shared/cbor.ts";
import type { Database, ReceiptVerificationDatabase } from "../_shared/database.ts";
import {
  HttpFailure,
  jsonResponse,
  parseJsonObject,
  readBody,
  requirePost,
  requireString,
  respond,
} from "../_shared/http.ts";
import { type AccessTokenVerifier, AuthError, bearerToken } from "../_shared/jwt.ts";

/** Current Apple receipts put the encoded registration near 8 KiB. */
export const MAX_BODY_BYTES = 64 * 1024;
export const MAX_RECEIPT_BYTES = 32 * 1024;

/**
 * How long a challenge stays valid. Ten minutes covers a user who is prompted
 * for a permission mid-flow and answers slowly.
 */
export const CHALLENGE_WINDOW_SECONDS = 600;

export interface AttestDeviceDeps {
  readonly database: Database & ReceiptVerificationDatabase;
  readonly appId: string;
  /** Apple App Attestation Root CA, used only for the attestation x5c chain. */
  readonly rootCertificatePem: string;
  /** Apple Root CA G3, used independently for the receipt PKCS#7 chain. */
  readonly receiptRootCertificatePem: string;
  readonly allowedEnvironments: readonly AttestEnvironment[];
  readonly verifyToken: AccessTokenVerifier;
  /** Independent HMAC key for the derived D47 challenge. */
  readonly challengeSecret: string;
  /** Injectable so the suites can drive the challenge window. */
  readonly now?: () => Date;
  /** Test seam; production always uses the independent PKCS#7 verifier. */
  readonly verifyReceipt?: typeof verifyAppAttestReceipt;
}

/**
 * The bytes a client hashes into its attestation's client data.
 *
 * Exported because the client obtains the same value from the challenge route,
 * and because a challenge whose construction lives only inside the verifier is
 * one nobody can test.
 */
export async function challengeFor(
  userId: string,
  secret: string,
  at: Date,
): Promise<Bytes> {
  const window = Math.floor(at.getTime() / 1000 / CHALLENGE_WINDOW_SECONDS);
  const key = await crypto.subtle.importKey(
    "raw",
    utf8(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign(
    "HMAC",
    key,
    utf8(`gametime.appattest.v1:${userId}:${window}`),
  );
  return new Uint8Array(mac);
}

/** Narrows a CBOR attestation object to the three fields the verifier reads. */
function openAttestationObject(bytes: Bytes) {
  try {
    const outer = asCborMap(decodeCbor(bytes), "attestation object");
    const statement = asCborMap(outer["attStmt"], "attStmt");
    const receipt = asCborBytes(statement["receipt"], "receipt");
    if (receipt.length === 0 || receipt.length > MAX_RECEIPT_BYTES) {
      throw new CborError(
        `receipt must contain 1 to ${MAX_RECEIPT_BYTES} bytes`,
      );
    }
    return {
      fmt: asCborText(outer["fmt"], "fmt"),
      authenticatorData: asCborBytes(outer["authData"], "authData"),
      x5c: asCborBytesArray(statement["x5c"], "x5c"),
      receipt,
    };
  } catch (error) {
    if (error instanceof CborError) {
      throw new HttpFailure(
        "bad_request",
        "the attestation is not a well-formed attestation object",
        error.message,
      );
    }
    throw error;
  }
}

/** Reads a base64 field, refusing rather than faulting on bad input. */
function decodeBase64Field(
  body: Record<string, unknown>,
  field: string,
  maxLength: number,
): Bytes {
  const encoded = requireString(body, field, maxLength);
  try {
    return base64ToBytes(encoded, field);
  } catch (error) {
    if (error instanceof AttestationError) {
      throw new HttpFailure("bad_request", `${field} is not valid base64`);
    }
    throw error;
  }
}

async function callerOf(
  request: Request,
  verifyToken: AccessTokenVerifier,
  at: Date,
): Promise<{ userId: string }> {
  try {
    return await verifyToken(bearerToken(request), at);
  } catch (error) {
    if (error instanceof AuthError) {
      // One message for every way a token can be unacceptable. Which check
      // refused it is not the caller's business.
      throw new HttpFailure("unauthorized", "sign in again", error.message);
    }
    throw error;
  }
}

export function createAttestDeviceHandler(
  deps: AttestDeviceDeps,
): (request: Request) => Promise<Response> {
  const clock = deps.now ?? (() => new Date());
  const verifyReceipt = deps.verifyReceipt ?? verifyAppAttestReceipt;

  return (request) =>
    respond("attest-device", async () => {
      requirePost(request);

      const isChallenge = new URL(request.url).pathname.replace(/\/+$/, "")
        .endsWith("/challenge");

      const at = clock();
      const caller = await callerOf(request, deps.verifyToken, at);

      if (isChallenge) {
        const challenge = await challengeFor(caller.userId, deps.challengeSecret, at);
        return jsonResponse(200, {
          challenge: btoa(String.fromCharCode(...challenge)),
          expiresInSeconds: CHALLENGE_WINDOW_SECONDS,
        });
      }

      const body = parseJsonObject(await readBody(request, MAX_BODY_BYTES));

      // base64ToBytes raises an AttestationError, which `respond` would turn
      // into a 500 — a malformed field is a bad request, not a server fault.
      const keyId = decodeBase64Field(body, "keyId", 128);
      const attestationObject = decodeBase64Field(body, "attestation", MAX_BODY_BYTES);

      // The current window and the one before it, so a request that straddles a
      // boundary is not refused for arriving a second late.
      const challenges = await Promise.all([
        challengeFor(caller.userId, deps.challengeSecret, at),
        challengeFor(
          caller.userId,
          deps.challengeSecret,
          new Date(at.getTime() - CHALLENGE_WINDOW_SECONDS * 1000),
        ),
      ]);

      const document = openAttestationObject(attestationObject);

      let verified;
      let lastError: unknown;
      for (const challenge of challenges) {
        try {
          verified = await verifyAttestation({
            ...document,
            keyId,
            clientData: challenge,
            appId: deps.appId,
            rootCertificatePem: deps.rootCertificatePem,
            allowedEnvironments: deps.allowedEnvironments,
            at,
          });
          break;
        } catch (error) {
          if (!(error instanceof AttestationError)) throw error;
          lastError = error;
        }
      }

      if (verified === undefined) {
        // One message for every way an attestation can fail. Naming the check
        // that refused it is a map of what to try next.
        throw new HttpFailure(
          "unauthorized",
          "the attestation could not be verified",
          String(lastError),
        );
      }

      // Registration is deliberately the first receipt operation. It stores
      // the untrusted bytes in the private quarantine and returns the
      // immutable time those exact bytes first arrived. No verifier failure
      // can therefore make a rejected receipt disappear.
      const registration = await deps.database.registerDeviceKey({
        userId: caller.userId,
        keyId,
        publicKey: verified.publicKey,
        receipt: document.receipt,
        environment: verified.environment,
      });

      let verifiedReceipt;
      try {
        verifiedReceipt = await verifyReceipt({
          receipt: document.receipt,
          appId: deps.appId,
          publicKey: verified.publicKey,
          receiptRootCertificatePem: deps.receiptRootCertificatePem,
          receivedAt: registration.receiptReceivedAt,
          expectedTypes: ["ATTEST"],
        });
      } catch (error) {
        if (!(error instanceof ReceiptVerificationError)) throw error;
        // One public answer for signature, chain, payload, freshness, App ID,
        // and key-binding failures. The durable candidate remains quarantined.
        throw new HttpFailure(
          "unauthorized",
          "the receipt could not be verified",
          error.message,
        );
      }

      // This RPC owns the timestamp and marks only the row whose current
      // receipt still has this digest. It is the sole path out of quarantine.
      await deps.database.markDeviceReceiptVerified({
        keyId,
        receiptSha256: verifiedReceipt.receiptSha256,
      });

      return jsonResponse(200, {
        registered: true,
        environment: verified.environment,
        ...(verified.validationCategory === undefined
          ? {}
          : { validationCategory: verified.validationCategory }),
        ...(verified.bundleVersion === undefined ? {} : { bundleVersion: verified.bundleVersion }),
      });
    });
}
