#!/usr/bin/env python3
"""Bounded actual-session races on the P11 manifest-owned local database.

Run only after the P11 acceptance runner has closed dispatch, disabled every
job and stopped its Edge router. This script opens a worker-only schedule with
dummy local Vault credentials and an unreachable loopback endpoint, then closes
it. Temporary SQL function timing patches are restored on every exit path.
"""
import argparse
import base64
import hashlib
import hmac
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import threading
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen
import uuid

ROOT = Path(__file__).resolve().parents[1]
P11_PATH = ROOT / "scripts/p11-local-scheduling-verify.py"
COMPLETE_SIGNATURE = "public.challenge_machine_complete_v1(uuid,uuid,uuid,uuid)"
PROCESSING_SIGNATURE = "app.challenge_machine_processing_state_v1()"
UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
DUMMY_WORKER_SECRET = "w" * 40
DUMMY_MONITOR_SECRET = "m" * 40


def load_p11():
    spec = importlib.util.spec_from_file_location("p11_local_scheduling_verify", P11_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("P11 owned-stack helper is unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def literal(value):
    return "'" + str(value).replace("'", "''") + "'"


def jwt(secret):
    def encoded(value):
        return base64.urlsafe_b64encode(json.dumps(value, separators=(",", ":")).encode()).rstrip(b"=")
    header = encoded({"alg": "HS256", "typ": "JWT"})
    payload = encoded({"role": "service_role", "aud": "authenticated", "exp": int(time.time()) + 600})
    signed = header + b"." + payload
    signature = base64.urlsafe_b64encode(hmac.new(secret.encode(), signed, hashlib.sha256).digest()).rstrip(b"=")
    return (signed + b"." + signature).decode()


class RaceStack:
    def __init__(self, manifest_path):
        self.p11 = load_p11()
        self.manifest, self.base = self.p11.load_manifest(manifest_path)
        if self.manifest["state"] not in ("forward_applied", "bounded_complete"):
            raise RuntimeError("P11 race requires the forward-applied disposable stack")
        self.p11.P8.inspect_owned(self.base, "container", self.base["db"])
        self.p11.P8.check_loopback(self.base, self.base["db"], "5432/tcp", self.base["db_port"])
        self.p11.P8.check_loopback(self.base, self.base["rest"], "3000/tcp", self.base["rest_port"])
        if self.p11.active_jobs(self.base):
            raise RuntimeError("all Cron jobs must be inactive during P11 races")
        self.db = self.base["db"]
        self.processes = []

    def sql(self, source):
        return self.p11.P8.sql(self.base, source)

    def require_closed_dispatch(self):
        closed = self.sql("""
          select count(*) from app.challenge_schedule_config_v1 where singleton
            and not worker_enabled and not snapshot_enabled and not monitor_enabled
            and edge_base_url is null and worker_secret_id is null
            and monitor_secret_id is null and community_id is null
        """)
        if closed != "1":
            raise RuntimeError("P11 race requires closed local dispatch configuration")

    def open_dummy_dispatch(self):
        self.sql("""
          with worker as (
            select vault.create_secret(%s,'p11-race-worker-'||gen_random_uuid(),
              'disposable local P11 race credential') as id
          ), monitor as (
            select vault.create_secret(%s,'p11-race-monitor-'||gen_random_uuid(),
              'disposable local P11 race credential') as id
          )
          update app.challenge_schedule_config_v1 set
            edge_base_url='http://127.0.0.1:1/functions/v1',
            worker_secret_id=(select id from worker),
            monitor_secret_id=(select id from monitor),
            worker_enabled=true,snapshot_enabled=false,monitor_enabled=false,
            community_id=null where singleton
        """ % (literal(DUMMY_WORKER_SECRET), literal(DUMMY_MONITOR_SECRET)))
        if self.sql("select app.challenge_schedule_state_v1('worker')") != "available":
            raise RuntimeError("P11 dummy worker schedule did not become available")

    def close_dummy_dispatch(self):
        # The P11 runner's close helper deletes the two referenced disposable
        # Vault rows and restores the default-off config in one transaction.
        self.p11.close_local_dispatch(self.base)

    def psql(self, source, *, app="p11-race", timeout=15):
        result = subprocess.run([
            "docker", "exec", "-e", "PGAPPNAME=" + app, "-i", self.db,
            "psql", "-XqAt", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=sqlstate",
            "-U", "postgres", "-d", "postgres",
        ], input=source, text=True, capture_output=True, timeout=timeout)
        return result

    def spawn(self, source, app):
        process = subprocess.Popen([
            "docker", "exec", "-e", "PGAPPNAME=" + app, "-i", self.db,
            "psql", "-XqAt", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=sqlstate",
            "-U", "postgres", "-d", "postgres",
        ], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.processes.append(process)
        assert process.stdin is not None
        process.stdin.write(source)
        process.stdin.close()
        process.stdin = None
        return process

    @staticmethod
    def collect(process, timeout=15):
        out, err = process.communicate(timeout=timeout)
        return process.returncode, out.strip(), err.strip()

    def wait_activity(self, prefix, number, *, blocked=False, timeout=4):
        condition = "cardinality(pg_blocking_pids(pid))>0" if blocked else "wait_event_type='Timeout'"
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            count = int(self.sql(
                "select count(*) from pg_stat_activity where application_name like " +
                literal(prefix + "%") + " and state='active' and " + condition
            ))
            if count >= number:
                return True
            time.sleep(0.04)
        return False

    def close(self):
        for process in self.processes:
            if process.poll() is None:
                process.kill()
        for process in self.processes:
            try:
                process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()


def json_result(result):
    if result.returncode:
        raise RuntimeError("owned SQL RPC failed")
    lines = [line for line in result.stdout.splitlines() if line.strip()]
    return json.loads(lines[-1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    stack = RaceStack(args.manifest)
    original_processing = None
    original_complete = None
    dummy_dispatch_opened = False
    checks = {}
    try:
        stack.require_closed_dispatch()
        # Cleanup must run even if a connection drops after the SQL commits.
        dummy_dispatch_opened = True
        stack.open_dummy_dispatch()
        original_processing = stack.sql("select pg_get_functiondef(" + literal(PROCESSING_SIGNATURE) + "::regprocedure)")
        original_complete = stack.sql("select pg_get_functiondef(" + literal(COMPLETE_SIGNATURE) + "::regprocedure)")
        if not original_processing or not original_complete:
            raise RuntimeError("P11 machine SQL definitions are unavailable")
        # The local operating gate remains untouched. This bounded test-only
        # function patch permits a prepared invocation to acquire its run row.
        stack.sql("create or replace function app.challenge_machine_processing_state_v1() returns text "
                  "language sql stable set search_path='' as $$select 'available'::text$$")

        before = int(stack.sql("select queued_count from app.challenge_schedule_ticks_v1 where kind='worker'"))
        stack.sql("update app.challenge_schedule_ticks_v1 set last_queued_at=null where kind='worker'")
        barrier = threading.Barrier(3)
        outcomes = []

        def tick():
            barrier.wait()
            outcomes.append(stack.psql("select app.challenge_cron_tick_v1('worker');", app="p11-tick"))

        threads = [threading.Thread(target=tick) for _ in range(2)]
        for thread in threads:
            thread.start()
        barrier.wait()
        for thread in threads:
            thread.join(12)
        if (any(thread.is_alive() for thread in threads) or len(outcomes) != 2
                or any(row.returncode for row in outcomes)):
            raise RuntimeError("simultaneous local ticks failed")
        after = int(stack.sql("select queued_count from app.challenge_schedule_ticks_v1 where kind='worker'"))
        if after != before + 1:
            raise RuntimeError("simultaneous ticks queued more than one worker request")
        invocation = stack.sql("select invocation_id from app.challenge_machine_runs_v1 "
                               "where kind='worker' and state<>'finished'")
        if not UUID_RE.fullmatch(invocation):
            raise RuntimeError("simultaneous ticks did not leave one prepared worker invocation")
        checks["simultaneous_ticks_one_invocation"] = True

        tokens = [str(uuid.uuid4()), str(uuid.uuid4())]
        barrier = threading.Barrier(3)
        dispatches = {}

        def dispatch(index):
            barrier.wait()
            dispatches[index] = stack.psql(
                "select public.challenge_machine_worker_dispatch_v1(" + literal(invocation) +
                "::uuid," + literal(tokens[index]) + "::uuid)", app="p11-edge-" + str(index))

        threads = [threading.Thread(target=dispatch, args=(index,)) for index in range(2)]
        for thread in threads:
            thread.start()
        barrier.wait()
        for thread in threads:
            thread.join(12)
        if any(thread.is_alive() for thread in threads) or len(dispatches) != 2:
            raise RuntimeError("concurrent Edge dispatches did not finish")
        values = {index: json_result(result) for index, result in dispatches.items()}
        winners = [index for index, result in values.items() if result.get("status") == "running"]
        if len(winners) != 1 or sorted(result.get("status") for result in values.values()) != ["busy", "running"]:
            raise RuntimeError("concurrent Edge requests did not fence one run")
        winner = winners[0]
        replay = json_result(stack.psql(
            "select public.challenge_machine_worker_dispatch_v1(" + literal(invocation) +
            "::uuid," + literal(tokens[winner]) + "::uuid)"))
        attempts = int(stack.sql("select dispatch_attempts from app.challenge_worker_invocations_v1 where id=" +
                                 literal(invocation) + "::uuid"))
        if replay.get("claims") != values[winner].get("claims") or attempts != 1:
            raise RuntimeError("lost dispatch response did not reuse saved claim receipt")
        checks["concurrent_edge_one_run_exact_dispatch_receipt"] = True

        marker = re.compile(
            r"(select\s+\*\s+into\s+run\s+from\s+app[.]challenge_machine_runs_v1\s+"
            r"where\s+invocation_id\s*=\s*p_invocation_id\s+and\s+kind\s*=\s*'worker'\s+for\s+share\s*;)",
            re.IGNORECASE,
        )
        patched, replacements = marker.subn(r"\1 perform pg_sleep(2.8);", original_complete, count=1)
        if replacements != 1:
            raise RuntimeError("cannot locate the exact completion row lock to test")
        stack.sql(patched)
        false_id, false_claim = str(uuid.uuid4()), str(uuid.uuid4())
        calls = [stack.spawn(
            "select public.challenge_machine_complete_v1(" + literal(invocation) + "::uuid," +
            literal(tokens[winner]) + "::uuid," + literal(false_id) + "::uuid," +
            literal(false_claim) + "::uuid)", "p11-share-" + str(index)) for index in range(5)]
        if not stack.wait_activity("p11-share-", 5, timeout=3):
            raise RuntimeError("five concurrent completions did not hold shared machine row locks")
        finish = stack.spawn(
            "select public.challenge_machine_finish_v1(" + literal(invocation) + "::uuid," +
            literal(tokens[winner]) + "::uuid)", "p11-finish-wait")
        if not stack.wait_activity("p11-finish-wait", 1, blocked=True, timeout=2):
            raise RuntimeError("finish did not wait behind five shared completion locks")
        for call in calls:
            code, _out, err = stack.collect(call)
            if code == 0 or "42501" not in err:
                raise RuntimeError("test completion did not reject its unselected claim")
        code, finish_out, _err = stack.collect(finish)
        if code:
            raise RuntimeError("finish did not resume after shared completion locks")
        finish_result = json.loads(finish_out)
        finish_state = stack.sql("select state from app.challenge_machine_runs_v1 where invocation_id=" +
                                 literal(invocation) + "::uuid")
        if finish_result.get("status") == "pending":
            if finish_state != "running":
                raise RuntimeError("pending finish unexpectedly changed the machine run")
            # The operating fixture may leave real claimed items pending. The
            # lock race is complete; close only this disposable machine row so
            # later independent tests can create their own unfinished row.
            stack.sql("update app.challenge_machine_runs_v1 set state='finished',run_token=null,"
                      "lease_expires_at=null,finished_at=clock_timestamp(),"
                      "result=app.challenge_machine_worker_result_v1(invocation_id) where invocation_id=" +
                      literal(invocation) + "::uuid")
        elif finish_state != "finished":
            raise RuntimeError("finish did not commit after shared completions")
        checks["five_shared_locks_fence_finish"] = True
        stack.sql(original_complete)

        # A separate test-only invocation carries one already committed
        # completion receipt. Two independent Edge-style RPC sessions must
        # replay that exact receipt, without creating a second ledger row.
        synthetic_invocation = str(uuid.uuid4())
        synthetic_id = str(uuid.uuid4())
        synthetic_claim = str(uuid.uuid4())
        synthetic_run = str(uuid.uuid4())
        setup = """
          begin;
          select set_config('app.challenge_write_v1','on',true);
          insert into app.challenge_worker_invocations_v1
           (id,scope,scope_digest,limit_count,state,claim_response,dispatch_attempts,
            prepared_at,dispatched_at,updated_at)
          values (%s::uuid,'{"version":"challenge_worker_scope_v1","kind":"due"}'::jsonb,
            repeat('0',64),20,'dispatched',
            jsonb_build_object('status','dispatched','claims',
              jsonb_build_array(jsonb_build_object('id',%s::uuid,'claim_token',%s::uuid))),
            1,clock_timestamp(),clock_timestamp(),clock_timestamp());
          insert into app.challenge_machine_runs_v1(invocation_id,kind) values(%s::uuid,'worker');
          insert into app.challenge_worker_runs_v1(id,payload,result,recorded_at)
           values(%s::uuid,jsonb_build_object('version','challenge_complete_claim_v1','id',%s::uuid),
             jsonb_build_object('id',%s::uuid,'claim_token',%s::uuid,'status','not_due'),
             clock_timestamp());
          commit;
        """ % tuple(map(literal, (synthetic_invocation, synthetic_id, synthetic_claim,
                                  synthetic_invocation, synthetic_claim, synthetic_id,
                                  synthetic_id, synthetic_claim)))
        stack.sql(setup)
        fake_dispatch = json_result(stack.psql(
            "select public.challenge_machine_worker_dispatch_v1(" + literal(synthetic_invocation) +
            "::uuid," + literal(synthetic_run) + "::uuid)"))
        if fake_dispatch.get("status") != "running" or len(fake_dispatch.get("claims", [])) != 1:
            raise RuntimeError("synthetic saved claim was not dispatched for receipt replay")
        barrier = threading.Barrier(3)
        completions = {}

        def complete(index):
            barrier.wait()
            completions[index] = stack.psql(
                "select public.challenge_machine_complete_v1(" + literal(synthetic_invocation) +
                "::uuid," + literal(synthetic_run) + "::uuid," + literal(synthetic_id) +
                "::uuid," + literal(synthetic_claim) + "::uuid)", app="p11-receipt-" + str(index))

        threads = [threading.Thread(target=complete, args=(index,)) for index in range(2)]
        for thread in threads:
            thread.start()
        barrier.wait()
        for thread in threads:
            thread.join(12)
        if any(thread.is_alive() for thread in threads) or len(completions) != 2:
            raise RuntimeError("concurrent receipt replay did not finish")
        receipt_values = [json_result(completions[index]) for index in range(2)]
        receipt_count = int(stack.sql("select count(*) from app.challenge_worker_runs_v1 where id=" +
                                      literal(synthetic_claim) + "::uuid"))
        if receipt_values[0] != receipt_values[1] or receipt_count != 1:
            raise RuntimeError("concurrent completion did not return one exact committed receipt")
        fake_finish = json_result(stack.psql(
            "select public.challenge_machine_finish_v1(" + literal(synthetic_invocation) +
            "::uuid," + literal(synthetic_run) + "::uuid)"))
        if fake_finish.get("status") != "completed":
            raise RuntimeError("synthetic receipt run did not finish")
        checks["concurrent_completion_one_exact_receipt"] = True

        # A fresh invocation is required after the prior one finishes.
        stack.sql("update app.challenge_schedule_ticks_v1 set last_queued_at=null where kind='worker'")
        stack.sql("select app.challenge_cron_tick_v1('worker')")
        second = stack.sql("select invocation_id from app.challenge_machine_runs_v1 "
                           "where kind='worker' and state<>'finished'")
        if not UUID_RE.fullmatch(second) or second == invocation:
            raise RuntimeError("fresh tick did not prepare a new invocation")
        old_token, new_token = str(uuid.uuid4()), str(uuid.uuid4())
        initial = json_result(stack.psql(
            "select public.challenge_machine_worker_dispatch_v1(" + literal(second) +
            "::uuid," + literal(old_token) + "::uuid)"))
        if initial.get("status") != "running":
            raise RuntimeError("new invocation did not acquire its first run fence")
        stack.sql("update app.challenge_machine_runs_v1 set lease_expires_at=clock_timestamp()-interval '1 second' "
                  "where invocation_id=" + literal(second) + "::uuid")
        holder = stack.spawn(
            "begin; select public.challenge_machine_worker_dispatch_v1(" + literal(second) +
            "::uuid," + literal(new_token) + "::uuid); select pg_sleep(1.8); commit;",
            "p11-takeover-holder")
        if not stack.wait_activity("p11-takeover-holder", 1, timeout=2):
            raise RuntimeError("lease takeover did not hold the machine row")
        stale = stack.spawn(
            "select public.challenge_machine_complete_v1(" + literal(second) + "::uuid," +
            literal(old_token) + "::uuid," + literal(false_id) + "::uuid," +
            literal(false_claim) + "::uuid)", "p11-stale-wait")
        if not stack.wait_activity("p11-stale-wait", 1, blocked=True, timeout=1.5):
            raise RuntimeError("old completion did not wait behind lease takeover")
        holder_code, _holder_out, _holder_err = stack.collect(holder)
        stale_code, _stale_out, stale_err = stack.collect(stale)
        if holder_code or stale_code == 0 or "55000" not in stale_err:
            raise RuntimeError("stale completion was not rejected after its row wait")
        checks["takeover_blocks_stale_completion"] = True

        proconfig = stack.sql("select array_to_string(proconfig,',') from pg_proc where oid=" +
                              literal("public.challenge_machine_worker_dispatch_v1(uuid,uuid)") + "::regprocedure")
        if "lock_timeout=4s" not in proconfig or "statement_timeout=5s" not in proconfig:
            raise RuntimeError("machine RPC lacks the 4s/5s database timeout bounds")
        locked = stack.spawn(
            "begin; select 1 from app.challenge_machine_runs_v1 where invocation_id=" +
            literal(second) + "::uuid for update; select pg_sleep(5.3); commit;",
            "p11-postgrest-holder")
        if not stack.wait_activity("p11-postgrest-holder", 1, timeout=2):
            raise RuntimeError("PostgREST lock holder did not acquire the row")
        token = jwt(stack.base["jwt_secret"])
        request = Request("http://127.0.0.1:" + str(stack.base["rest_port"]) +
                          "/rpc/challenge_machine_worker_dispatch_v1",
                          data=json.dumps({"p_invocation_id": second, "p_run_token": str(uuid.uuid4())}).encode(),
                          headers={"Authorization": "Bearer " + token,
                                   "Content-Type": "application/json"}, method="POST")
        started = time.monotonic()
        try:
            with urlopen(request, timeout=8) as response:
                status = response.status
                body = json.load(response)
        except HTTPError as error:
            status = error.code
            body = json.load(error)
        elapsed = time.monotonic() - started
        held_code, _held_out, _held_err = stack.collect(locked)
        if held_code or status < 400 or body.get("code") != "55P03" or not 3.5 <= elapsed <= 5.8:
            raise RuntimeError("actual PostgREST RPC did not stop at the bounded database lock timeout")
        checks["postgrest_lock_timeout_four_seconds"] = True

        receipt = Path(stack.manifest["receipt_dir"]) / ("p11-machine-concurrency-" + uuid.uuid4().hex + ".json")
        receipt.write_text(json.dumps({"checks": checks, "postgrest_lock_elapsed_seconds": round(elapsed, 2)},
                                      sort_keys=True, indent=2) + "\n")
        receipt.chmod(0o600)
        print(json.dumps(checks, sort_keys=True))
    finally:
        try:
            stack.close()
        finally:
            # Restore each definition even if process cleanup or the other
            # restoration fails. Both patches are confined to this stack.
            try:
                try:
                    if original_complete is not None:
                        stack.sql(original_complete)
                finally:
                    if original_processing is not None:
                        stack.sql(original_processing)
            finally:
                if dummy_dispatch_opened:
                    stack.close_dummy_dispatch()


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print("error: " + str(error), file=sys.stderr)
        raise SystemExit(1)
