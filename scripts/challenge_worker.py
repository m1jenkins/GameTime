"""A bounded worker pass. Each RPC is its own committed database transaction."""
from concurrent.futures import ThreadPoolExecutor


def run_once(rpc, run_id, limit=20):
    batch = rpc("challenge_claim_batch_v1", {"p_run_id": str(run_id), "p_limit": limit})
    def complete(claim):
        # The token is also the completion request identity. A lost response can
        # be retried without applying lifecycle effects twice. Transport failures
        # are isolated to the item; later runs recover abandoned leases.
        try:
            return rpc("challenge_complete_claim_v1", {
                "p_id": claim["id"], "p_claim_token": claim["claim_token"],
            })
        except Exception as error:
            return {"id": claim["id"], "claim_token": claim["claim_token"],
                    "request_failed": type(error).__name__}
    # Callers use a five-second network timeout. Five lanes avoid abandoning
    # later items behind one failed call. Expired tokens still fail closed.
    with ThreadPoolExecutor(max_workers=5) as workers:
        processed = list(workers.map(complete, batch["claims"]))
    return {"run_id": str(run_id), "processed": processed,
            "failed_count": sum("error_code" in item or "request_failed" in item for item in processed),
            "server_time": batch["server_time"]}
