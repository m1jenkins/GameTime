#!/usr/bin/env python3
"""P9 entry point for P8's owned/populated local migration verifier.

Preserves the original P8 default selection. P9 names its own ordered forward
set explicitly; no hosted credentials, existing development project or resets.
"""
from pathlib import Path
import runpy
import sys

root = Path(__file__).resolve().parents[1]
forward = [
    "20260920010824_challenge_real_health_ingest_v1.sql",
    "20260920015606_challenge_real_health_metrics_v1.sql",
    "20260920020431_challenge_real_health_metric_contracts_v1.sql",
    "20260920022108_challenge_real_health_privacy_v1.sql",
    "20260920023500_challenge_real_health_worker_v1.sql",
    "20260920042634_challenge_signal_health_binding_v1.sql",
    "20260920050238_challenge_exercise_credit_v2.sql",
]
if "--forward-migration" not in sys.argv:
    for name in forward:
        sys.argv.extend(["--forward-migration", str(root / "supabase/migrations" / name)])
runpy.run_path(str(root / "scripts/p8-real-health-verify.py"), run_name="__main__")
