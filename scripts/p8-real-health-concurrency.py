#!/usr/bin/env python3
"""Race the installed P8 steps-ingress snapshot in one owned local stack.

The driver never reads or prints credentials. It finds the successful synthetic
HTTP row already present in the manifest-owned database, then uses independent
`psql` processes inside that same labeled container. Its receipt records only
request ids, outcomes, and counts.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import threading
import time
import uuid

CLEANUPS = []


def command(argv, source=None, check=True):
    result = subprocess.run(argv, input=source, text=True, capture_output=True, timeout=30)
    if check and result.returncode:
        raise RuntimeError(result.stderr.strip() or "command failed")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    if args.manifest.stat().st_mode & 0o077:
        raise RuntimeError("manifest must be mode 0600")
    owner, db = manifest["owner"], manifest["db"]
    inspected = json.loads(command(["docker", "container", "inspect", db]).stdout)[0]
    if inspected["Config"]["Labels"].get("owner") != owner:
        raise RuntimeError("refusing unowned database")
    expected = {"5432/tcp": [{"HostIp": "127.0.0.1", "HostPort": str(manifest["db_port"])}]}
    if inspected["HostConfig"]["PortBindings"] != expected:
        raise RuntimeError("database is not numeric-loopback only")
    receipts = Path(manifest["receipt_dir"])
    output = receipts / ("p8-real-health-concurrency-" + uuid.uuid4().hex + ".json")

    def sql(source, check=True):
        return command(["docker", "exec", "-i", db, "psql", "-XqAt", "-v", "ON_ERROR_STOP=1",
                        "-U", "postgres", "-d", "postgres"], source, check)

    context_sql = """
      select json_build_object(
        'request_id', request.request_id,
        'payload', request.payload,
        'session_id', session.id,
        'session_not_after', session.not_after,
        'key_id', encode(request.device_key_id, 'hex'),
        'counter', device.sign_count,
        'latest_revision', coalesce((select max(fact.revision) from app.challenge_real_health_facts_v1 fact
          where fact.challenge_id = (request.payload ->> 'challenge_id')::uuid
            and fact.actor_id = request.actor_id), 0)
      )
      from app.challenge_real_health_requests_v1 request
      join app.challenge_lobbies_v1 lobby on lobby.id = (request.payload ->> 'challenge_id')::uuid
      join public.device_attestations device on device.key_id = request.device_key_id
      join auth.sessions session on session.user_id = request.actor_id
      where (session.not_after is null or session.not_after > clock_timestamp())
        and request.payload ->> 'source_policy_version' = 'apple_watch_steps_v1'
        and (request.payload ->> 'revision')::integer = 1
        and request.payload -> 'previous_revision' = 'null'::jsonb
        and lobby.status in ('scheduled', 'active', 'syncing')
      order by request.recorded_at desc limit 1;
    """
    row = sql(context_sql).stdout.strip()
    if not row:
        raise RuntimeError("no committed real-health HTTP row is available for the race")
    context = json.loads(row)
    payload = context["payload"]
    if payload.get("revision") != 1 or payload.get("previous_revision") is not None or context["latest_revision"] < 1:
        raise RuntimeError("latest committed row is not a revision-one race parent")
    original_clock = sql("select pg_get_functiondef('app.challenge_real_health_now_v1()'::regprocedure);").stdout
    def close_real_runtime():
        sql("select public.challenge_real_health_runtime_v1(false,false,false);")
    def restore_all():
        try:
            original = context["session_not_after"]
            if original is None:
                sql("update auth.sessions set not_after = null where id = '%s'::uuid;" % context["session_id"])
            else:
                sql("update auth.sessions set not_after = '%s'::timestamptz where id = '%s'::uuid;" %
                    (original.replace("'", "''"), context["session_id"]))
        finally:
            try:
                sql(original_clock)
            finally:
                close_real_runtime()
    sql("select public.challenge_real_health_runtime_v1(true,true,true);")
    CLEANUPS.append(restore_all)
    # Keep the signed observation/query timestamps untouched, but run the
    # correction at that signed logical source instant.  HTTP restores its
    # temporary clock, whereas a correction still has to be evaluated inside
    # the original frozen agreement window.  The definition is restored on
    # every exit path below.
    signed_now = payload["queried_through_at"]
    sql("create or replace function app.challenge_real_health_now_v1() returns timestamptz language sql stable set search_path='' as $$ select '%s'::timestamptz $$;" % signed_now)

    def call_for(request_id, counter, revision, previous, expires="clock_timestamp() + interval '1 hour'"):
        body = dict(payload)
        body.update(request_id=str(request_id), revision=revision, previous_revision=previous)
        encoded = json.dumps(body, separators=(",", ":"), sort_keys=True).replace("'", "''")
        return """
          with p as (select '%s'::jsonb as body)
          select public.challenge_real_health_ingest_v1(
            '%s'::uuid, body, '%s'::uuid, %s,
            decode('%s','hex'), %d,
            extensions.digest(convert_to(body::text,'UTF8'),'sha256'), false
          ) from p;
        """ % (encoded, request_id, context["session_id"], expires, context["key_id"], counter)

    def session_restore():
        original = context["session_not_after"]
        if original is None:
            sql("update auth.sessions set not_after = null where id = '%s'::uuid;" % context["session_id"])
        else:
            sql("update auth.sessions set not_after = '%s'::timestamptz where id = '%s'::uuid;" %
                (original.replace("'", "''"), context["session_id"]))

    def blocked_session_case(name, expires, mutation, revision):
        """Hold the exact session row, then release it into an invalid state.

        The ingest routine takes that row with FOR SHARE.  A separate session
        holding FOR UPDATE therefore proves that its wall-clock/session check
        happens after the wait rather than before it.
        """
        request_id = uuid.uuid4()
        counter = int(sql("select sign_count from public.device_attestations where key_id = decode('%s','hex');" % context["key_id"]).stdout.strip()) + 1
        holder_sql = """
          begin;
          select 1 from auth.sessions where id = '%s'::uuid for update;
          select pg_sleep(1.5);
          %s
          commit;
        """ % (context["session_id"], mutation)
        holder = subprocess.Popen(
            ["docker", "exec", "-i", db, "psql", "-XqAt", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        holder.stdin.write(holder_sql)
        holder.stdin.close()
        holder.stdin = None
        time.sleep(0.15)
        result = {}
        thread = threading.Thread(target=lambda: result.update(value=sql(call_for(
            request_id, counter, revision, revision - 1, expires), check=False)))
        thread.start()
        time.sleep(0.35)
        blocked = thread.is_alive()
        holder_stdout, holder_stderr = holder.communicate(timeout=10)
        thread.join(10)
        if thread.is_alive():
            raise RuntimeError(name + " contender did not finish")
        contender = result["value"]
        outcome = {"code": contender.returncode, "stdout": contender.stdout.strip(), "stderr": contender.stderr.strip(),
                   "blocked_on_session": blocked, "holder_code": holder.returncode}
        session_restore()
        facts = int(sql("select count(*) from app.challenge_real_health_facts_v1 where request_id = '%s'::uuid;" % request_id).stdout.strip())
        if holder.returncode or not blocked or contender.returncode == 0 or "challenge_real_health_session_required" not in contender.stderr or facts:
            raise RuntimeError(name + " did not reject after the session-row wait")
        return outcome

    before = int(sql("select count(*) from app.challenge_real_health_facts_v1 where request_id <> '%s'::uuid;" % context["request_id"]).stdout.strip())
    first, second = uuid.uuid4(), uuid.uuid4()
    outcomes = {}
    barrier = threading.Barrier(3)

    def race(name, statement):
        barrier.wait()
        result = sql(statement, check=False)
        outcomes[name] = {"code": result.returncode, "stdout": result.stdout.strip(), "stderr": result.stderr.strip()}

    correction_revision = int(context["latest_revision"]) + 1
    threads = [threading.Thread(target=race, args=("first", call_for(first, int(context["counter"]) + 1, correction_revision, correction_revision - 1))),
               threading.Thread(target=race, args=("second", call_for(second, int(context["counter"]) + 2, correction_revision, correction_revision - 1)))]
    for thread in threads: thread.start()
    barrier.wait()
    for thread in threads: thread.join(20)
    if any(thread.is_alive() for thread in threads):
        raise RuntimeError("CAS race did not finish")
    successes = [name for name, value in outcomes.items() if value["code"] == 0]
    after = int(sql("select count(*) from app.challenge_real_health_facts_v1 where request_id in ('%s'::uuid,'%s'::uuid);" % (first, second)).stdout.strip())
    if len(successes) != 1 or after != 1:
        binding = sql("""
          select json_build_object(
            'lobby', json_build_object('starts_at', lobby.starts_at, 'ends_at', lobby.ends_at,
              'status', lobby.status, 'source', lobby.real_source_policy_version,
              'agreement_version', lobby.agreement_version),
            'agreement_config', agreement.terms -> 'config',
            'consent_present', exists(select 1 from app.challenge_consents_v1 consent
              where consent.challenge_id = lobby.id and consent.actor_id = '%s'::uuid
                and consent.version = lobby.agreement_version and consent.digest = agreement.digest))
          from app.challenge_lobbies_v1 lobby
          left join app.challenge_agreements_v1 agreement
            on agreement.challenge_id = lobby.id and agreement.version = lobby.agreement_version
          where lobby.id = '%s'::uuid;
        """ % (payload["actor_id"], payload["challenge_id"])).stdout.strip()
        failure = {"parent_request_id": context["request_id"], "cas_requests": [str(first), str(second)],
                   "cas": {key: outcomes[key] for key in ("first", "second")}, "fact_count": after,
                   "binding_context": json.loads(binding) if binding else None}
        output.write_text(json.dumps(failure, sort_keys=True, indent=2) + "\n")
        output.chmod(0o600)
        sql(original_clock)
        close_real_runtime()
        raise RuntimeError("same-parent CAS did not produce exactly one committed replacement; receipt saved")

    winner = first if successes[0] == "first" else second
    winner_counter = int(context["counter"]) + (1 if winner == first else 2)
    recovery = {}
    barrier = threading.Barrier(3)
    threads = [threading.Thread(target=race, args=("recovery_one", call_for(winner, winner_counter, correction_revision, correction_revision - 1))),
               threading.Thread(target=race, args=("recovery_two", call_for(winner, winner_counter, correction_revision, correction_revision - 1)))]
    for thread in threads: thread.start()
    barrier.wait()
    for thread in threads: thread.join(20)
    recovery = {key: outcomes[key] for key in ("recovery_one", "recovery_two")}
    if any(value["code"] != 0 for value in recovery.values()) or recovery["recovery_one"]["stdout"] != recovery["recovery_two"]["stdout"]:
        sql(original_clock)
        close_real_runtime()
        raise RuntimeError("exact concurrent recovery did not return one identical committed receipt")
    # Both cases must wait on the session row.  The first validates the passed
    # token expiry against wall time after that wait; the second changes the
    # session's not_after value while the same lock is held.
    try:
        expiry = blocked_session_case(
            "token_expiry", "clock_timestamp() + interval '0.2 seconds'", "select 1;", correction_revision + 1)
        revoked = blocked_session_case(
            "session_revocation", "clock_timestamp() + interval '1 hour'",
            "update auth.sessions set not_after = clock_timestamp() where id = '%s'::uuid;" % context["session_id"], correction_revision + 1)
    finally:
        # Do not leave a test-only session mutation or source-clock override in
        # the shared manifest-owned database, including after a failed race.
        session_restore()
        sql(original_clock)
        close_real_runtime()
    receipt = {"parent_request_id": context["request_id"], "cas_requests": [str(first), str(second)],
               "winner": str(winner), "cas": {key: outcomes[key] for key in ("first", "second")},
               "recovery": recovery, "session_expiry": expiry, "session_revocation": revoked,
               "checks": {"one_cas_commit": True, "one_new_fact": True, "exact_recovery": True,
                          "expiry_checked_after_session_wait": True, "revocation_checked_after_session_wait": True}}
    output.write_text(json.dumps(receipt, sort_keys=True, indent=2) + "\n")
    output.chmod(0o600)
    print(json.dumps(receipt["checks"], sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print("error: " + str(error), file=sys.stderr)
        raise SystemExit(1)
    finally:
        # This outer finally covers every operation after the real runtime is
        # opened, including unexpected SQL, thread, and assertion failures.
        for cleanup in reversed(CLEANUPS):
            try:
                cleanup()
            except Exception as cleanup_error:
                print("error: cleanup failed: " + str(cleanup_error), file=sys.stderr)
