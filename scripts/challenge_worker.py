"""A bounded worker pass with durable invocation and claim identities.

Each RPC is its own committed database transaction. A transport retry replays
the exact request body; the server-side invocation or claim receipt decides
whether the retry is new work or an exact duplicate.
"""
from concurrent.futures import ThreadPoolExecutor

DEFAULT_RPC_ATTEMPTS = 3
DEFAULT_SCOPE = {"version": "challenge_worker_scope_v1", "kind": "due"}


def _rpc_exact(rpc, name, payload, attempts=DEFAULT_RPC_ATTEMPTS):
    """Retry one exact RPC a bounded number of times, then re-raise."""
    last_error = None
    for _ in range(attempts):
        try:
            return rpc(name, payload)
        except Exception as error:  # transport and server failures are bounded
            last_error = error
    raise last_error


def _transport_result(claim, error):
    """Return only an approved transport classification, never the raw error."""
    code = "transport_timeout" if isinstance(error, TimeoutError) else "transport_error"
    return {"id": claim["id"], "claim_token": claim["claim_token"],
            "request_failed": code}


def run_once(rpc, run_id, limit=20, scope=None, max_rpc_attempts=DEFAULT_RPC_ATTEMPTS):
    """Prepare and dispatch a scoped invocation, then complete each claim.

    ``scope=None`` retains the historical claim RPC for callers that are
    replaying an older local fixture. The current CLI passes ``DEFAULT_SCOPE``
    so new work always persists invocation parameters before dispatch.
    """
    if scope is None:
        batch = _rpc_exact(rpc, "challenge_claim_batch_v1", {
            "p_run_id": str(run_id), "p_limit": limit,
        }, max_rpc_attempts)
    else:
        _rpc_exact(rpc, "challenge_prepare_worker_invocation_v1", {
            "p_invocation_id": str(run_id), "p_scope": scope, "p_limit": limit,
        }, max_rpc_attempts)
        batch = _rpc_exact(rpc, "challenge_dispatch_worker_invocation_v1", {
            "p_invocation_id": str(run_id),
        }, max_rpc_attempts)

    claims = batch.get("claims", [])

    def complete(claim):
        # The token is also the completion request identity. A lost response can
        # be retried without applying lifecycle effects twice. Transport failures
        # are isolated to the item; later runs recover abandoned leases.
        try:
            return _rpc_exact(rpc, "challenge_complete_claim_v1", {
                "p_id": claim["id"], "p_claim_token": claim["claim_token"],
            }, max_rpc_attempts)
        except Exception as error:
            return _transport_result(claim, error)
    # Callers use a five-second network timeout. Five lanes avoid abandoning
    # later items behind one failed call. Expired tokens still fail closed.
    with ThreadPoolExecutor(max_workers=5) as workers:
        processed = list(workers.map(complete, claims))
    dispatch_failed = batch.get("status") in {"failed", "disabled"}
    return {"run_id": str(run_id), "processed": processed,
            "failed_count": sum("error_code" in item or "request_failed" in item
                                 for item in processed) + int(dispatch_failed),
            "server_time": batch.get("server_time"),
            "status": batch.get("status", "dispatched")}


def snapshot_once(rpc, invocation_id, challenge_id,
                  max_rpc_attempts=DEFAULT_RPC_ATTEMPTS):
    """Prepare and dispatch one delayed community snapshot invocation."""
    _rpc_exact(rpc, "challenge_prepare_community_snapshot_invocation_v1", {
        "p_invocation_id": str(invocation_id), "p_id": str(challenge_id),
    }, max_rpc_attempts)
    return _rpc_exact(rpc, "challenge_dispatch_community_snapshot_invocation_v1", {
        "p_invocation_id": str(invocation_id),
    }, max_rpc_attempts)
