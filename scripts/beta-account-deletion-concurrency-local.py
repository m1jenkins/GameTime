#!/usr/bin/env python3
"""Focused local-only races between Beta deletion and ordinary lifecycle work.

This is intentionally a disposable PostgreSQL/Auth test, not an operator tool
or worker. It mints fictional actors only, verifies actual concurrent database
sessions, then disables its own runtime gate and revokes only its own sessions.
"""
import argparse
import json
import os
from pathlib import Path
import select
import subprocess
import time
from typing import Optional
import uuid


def quoted(value: object) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db-container", required=True)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    if not args.db_container.startswith("gametime-account-deletion-20260914-"):
        raise RuntimeError("refusing a database outside this local task")
    args.report.parent.mkdir(parents=True, exist_ok=True)

    owned: list[subprocess.Popen[str]] = []
    checks: list[str] = []
    actors = [str(uuid.uuid4()) for _ in range(10)]
    sessions = [str(uuid.uuid4()) for _ in actors]

    def command(app_name: Optional[str] = None) -> list[str]:
        prefix = ["docker", "exec", "-i"]
        if app_name:
            prefix += ["-e", "PGAPPNAME=" + app_name]
        return prefix + [
            args.db_container, "psql", "-XqAt", "-v", "ON_ERROR_STOP=1",
            "-U", "postgres", "-d", "postgres",
        ]

    def sql(source: str, *, check: bool = True) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(command(), input=source, text=True, capture_output=True, timeout=30)
        # Docker can briefly refuse a second local CLI client while the two
        # contenders are being spawned. Retry only that transport error; never
        # retry a database operation or its durable request.
        if "Cannot connect to the Docker daemon" in result.stderr:
            time.sleep(0.1)
            result = subprocess.run(command(), input=source, text=True, capture_output=True, timeout=30)
        if check and result.returncode:
            raise RuntimeError(result.stderr.strip() or "local SQL failed")
        return result

    def value(source: str) -> str:
        lines = sql(source).stdout.strip().splitlines()
        return lines[-1] if lines else ""

    def auth(actor: str, session: str, source: str) -> str:
        claims = json.dumps({"sub": actor, "session_id": session}, separators=(",", ":"))
        return (
            "begin; select set_config('request.jwt.claims'," + quoted(claims)
            + ",true); set local role authenticated; " + source + "; commit;"
        )

    def authenticated_command(actor_index: int, payload: dict[str, object]) -> dict[str, object]:
        source = auth(
            actors[actor_index], sessions[actor_index],
            "select public.challenge_mutate_v1(" + quoted(uuid.uuid4()) + "::uuid,"
            + quoted(json.dumps(payload, separators=(",", ":"))) + "::jsonb)::text",
        )
        output = value(source)
        decoded = json.loads(output)
        if not isinstance(decoded, dict):
            raise RuntimeError("unexpected challenge response")
        return decoded

    def revision(challenge: str) -> int:
        return int(value("select revision from app.challenge_lobbies_v1 where id=" + quoted(challenge) + "::uuid"))

    def mutate(actor_index: int, challenge: str, operation: str, **extra: object) -> dict[str, object]:
        payload: dict[str, object] = {
            "op": operation, "id": challenge, "revision": revision(challenge),
        }
        payload.update(extra)
        return authenticated_command(actor_index, payload)

    def group(indices: list[int]) -> str:
        config = {"start_date": "2026-10-03", "days": 1, "timezone": "UTC", "amount_cents": 100}
        created = authenticated_command(indices[0], {"op": "create", "config": config})
        challenge = str(created["id"])
        for member in indices[1:]:
            handle = value("select handle from public.profiles where id=" + quoted(actors[member]) + "::uuid")
            mutate(indices[0], challenge, "invite", username=handle)
            mutate(member, challenge, "target", target=100)
            mutate(indices[0], challenge, "select", actor_id=actors[member], selected=True)
        mutate(indices[0], challenge, "target", target=100)
        mutate(indices[0], challenge, "freeze")
        digest = value("select digest from app.challenge_agreements_v1 where challenge_id=" + quoted(challenge) + "::uuid")
        for member in indices:
            mutate(member, challenge, "consent", consent=True, digest=digest)
        return challenge

    def runtime(now: str) -> None:
        ids = "array[" + ",".join(quoted(actor) + "::uuid" for actor in actors) + "]"
        sql("select public.challenge_runtime_v1(true,true,true," + ids + "," + quoted(now) + "::timestamptz)")

    class Held:
        def __init__(self, source: str, name: str):
            self.process = subprocess.Popen(
                command(name), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, text=True, bufsize=1,
            )
            owned.append(self.process)
            assert self.process.stdin and self.process.stdout
            self.process.stdin.write("begin; " + source + "; select 'ready';\n")
            self.process.stdin.flush()
            deadline = time.monotonic() + 10
            received = ""
            while time.monotonic() < deadline:
                if not select.select([self.process.stdout], [], [], 0.2)[0]:
                    continue
                received += os.read(self.process.stdout.fileno(), 4096).decode()
                if "ready" in received:
                    return
            self.process.kill()
            raise RuntimeError("could not establish owned local lock")

        def release(self) -> None:
            assert self.process.stdin
            self.process.stdin.write("commit;\\q\n")
            self.process.stdin.flush()
            _, stderr = self.process.communicate(timeout=20)
            if self.process.returncode:
                raise RuntimeError(stderr.strip() or "owned lock release failed")

    def contender(source: str, name: str) -> subprocess.Popen[str]:
        process = subprocess.Popen(
            command(name), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True,
        )
        owned.append(process)
        assert process.stdin
        process.stdin.write(source)
        process.stdin.close()
        process.stdin = None
        return process

    def blocked(names: list[str]) -> bool:
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            query = (
                "select count(*) from pg_stat_activity where application_name in ("
                + ",".join(quoted(name) for name in names)
                + ") and cardinality(pg_blocking_pids(pid)) > 0"
            )
            if int(value(query)) == len(names):
                return True
            time.sleep(0.03)
        return False

    def check(condition: bool, label: str) -> None:
        if not condition:
            raise AssertionError(label)
        checks.append(label)
        print("PASS: " + label, flush=True)

    def deletion_call(actor_index: int, request: str, receipt: str, subject: str) -> str:
        return (
            "begin; select public.challenge_begin_account_deletion_v1("
            + quoted(actors[actor_index]) + "::uuid," + quoted(request) + "::uuid,"
            + quoted(receipt) + "," + quoted(subject) + "); commit;"
        )

    try:
        for index, (actor, session) in enumerate(zip(actors, sessions), 1):
            sql(
                "insert into auth.users(id) values(" + quoted(actor) + "::uuid);"
                "insert into public.profiles(id,handle,display_name,timezone) values("
                + quoted(actor) + "::uuid," + quoted("deletionrace" + str(index) + uuid.uuid4().hex[:8])
                + ",'Fictional deletion race','UTC');"
                "insert into auth.sessions(id,user_id) values(" + quoted(session) + "::uuid,"
                + quoted(actor) + "::uuid);"
            )
        for left in range(5):
            for right in range(left + 1, 5):
                sql(
                    "insert into public.friendships(user_a,user_b,requested_by,status) values(least("
                    + quoted(actors[left]) + "::uuid," + quoted(actors[right]) + "::uuid),greatest("
                    + quoted(actors[left]) + "::uuid," + quoted(actors[right]) + "::uuid),"
                    + quoted(actors[left]) + "::uuid,'accepted')"
                )
        runtime("2026-10-01T12:00Z")
        for actor, session in zip(actors, sessions):
            sql(auth(actor, session, "select public.challenge_confirm_age_v1(" + quoted(uuid.uuid4()) + "::uuid,true)"))
            sql("select public.challenge_readiness_metric_fixture_v1(" + quoted(actor) + "::uuid,'steps')")

        # Set up a three-member review and a two-member due final before
        # scheduling the races. These use the normal authenticated transport.
        review_challenge = group([0, 1, 2])
        final_challenge = group([3, 4])
        runtime("2026-10-03T12:00Z")
        for actor_index in (3, 4):
            sql(
                "select public.challenge_capture_fixture_v1(" + quoted(uuid.uuid4())
                + "::uuid," + quoted(final_challenge) + "::uuid," + quoted(actors[actor_index])
                + "::uuid,100,'complete')"
            )
        runtime("2026-10-06T12:00Z")
        sql("select public.challenge_process_v1(" + quoted(review_challenge) + "::uuid)")
        sql("select public.challenge_process_v1(" + quoted(final_challenge) + "::uuid)")
        check(value("select status from app.challenge_lobbies_v1 where id=" + quoted(review_challenge) + "::uuid") == "review",
              "fictional review challenge reached its normal notice stage")
        check(value("select status from app.challenge_lobbies_v1 where id=" + quoted(final_challenge) + "::uuid") == "review",
              "fictional finalization challenge reached its normal notice stage")

        # Admission starts under a shared gate and blocks on the target actor.
        # Deletion then waits exclusively; when the actor lock is released the
        # completed admission is immediately reconciled by accepted deletion.
        existing_community = value(
            "select coalesce((select capacity.challenge_id::text from app.challenge_community_capacity_v1 capacity "
            "join app.challenge_lobbies_v1 lobby on lobby.id=capacity.challenge_id "
            "where lobby.status='published_open' order by capacity.challenge_id limit 1),'')"
        )
        community = existing_community or value(
            "select public.challenge_publish_community_fixture_v1(" + quoted(uuid.uuid4())
            + "::uuid," + quoted(actors[9]) + "::uuid,"
            + "'{\"start_date\":\"2026-10-10\",\"days\":1,\"timezone\":\"UTC\",\"amount_cents\":100}'::jsonb,100,2,6,true)"
        )
        sql("select public.challenge_discovery_fixture_v1(true)")
        community_digest = value("select digest from app.challenge_agreements_v1 where challenge_id=" + quoted(community) + "::uuid")
        actor_lock = Held("select app.challenge_lock_v1('actor'," + quoted(actors[5]) + "::uuid)", "deletion-race-admission-lock")
        admission_name = "dar-" + uuid.uuid4().hex
        delete_admission_name = "dda-" + uuid.uuid4().hex
        admission_receipt = "local_admission_" + uuid.uuid4().hex
        admission = contender(
            auth(actors[5], sessions[5], "select public.challenge_join_community_v1(" + quoted(uuid.uuid4())
                 + "::uuid," + quoted(json.dumps({"op": "join_community", "id": community, "digest": community_digest, "consent": True}, separators=(",", ":"))) + "::jsonb)"),
            admission_name,
        )
        delete_after_admission = contender(
            deletion_call(5, str(uuid.uuid4()), admission_receipt, "fictional-apple-race-admission"),
            delete_admission_name,
        )
        try:
            check(blocked([admission_name, delete_admission_name]),
                  "real admission and deletion sessions wait behind the same owned actor/gate scopes")
        finally:
            actor_lock.release()
        admission_output, admission_error = admission.communicate(timeout=30)
        deletion_output, deletion_error = delete_after_admission.communicate(timeout=30)
        check((admission.returncode == 0 and admission_output.strip() and not admission_error)
              or (admission.returncode != 0 and "challenge_session_required" in admission_error),
              "the raced admission either commits before acceptance or is denied by the accepted tombstone")
        check(delete_after_admission.returncode == 0 and deletion_output.strip() and not deletion_error,
              "the competing durable deletion acceptance committed exactly once")
        check(value("select count(*) from app.challenge_members_v1 where challenge_id=" + quoted(community)
                    + "::uuid and actor_id=" + quoted(actors[5]) + "::uuid and exited_at is null") == "0",
              "accepted deletion leaves no active membership from the admission race")
        stale = sql(auth(
            actors[5], sessions[5],
            "select public.challenge_mutate_v1(" + quoted(uuid.uuid4()) + "::uuid,"
            "'{\"op\":\"create\",\"config\":{\"start_date\":\"2026-10-20\",\"days\":1,\"timezone\":\"UTC\",\"amount_cents\":100}}'::jsonb)"
        ), check=False)
        check(stale.returncode != 0 and "challenge_session_required" in stale.stderr,
              "the raced actor's stale ordinary session is denied after acceptance")

        # An accepted deletion may retain the narrow receipt review right. Race
        # it with a due lifecycle final: either review wins and holds the case,
        # or final wins and the receipt accurately reports that review is gone.
        review_receipt = "local_review_" + uuid.uuid4().hex
        sql(deletion_call(0, str(uuid.uuid4()), review_receipt, "fictional-apple-race-review"))
        review_notice = value("select revision from app.challenge_notices_v1 where challenge_id=" + quoted(review_challenge) + "::uuid")
        runtime("2026-10-09T12:00Z")
        review_gate = Held("select app.challenge_gate_v1(true)", "deletion-race-review-gate")
        review_name = "drr-" + uuid.uuid4().hex
        process_name = "drf-" + uuid.uuid4().hex
        review = contender(
            "begin; select public.challenge_account_deletion_file_review_v1(" + quoted(review_receipt)
            + "," + quoted(uuid.uuid4()) + "::uuid," + quoted(review_challenge) + "::uuid,"
            + review_notice + ",'wrong_total'); commit;", review_name,
        )
        process = contender(
            "begin; select public.challenge_process_v1(" + quoted(review_challenge) + "::uuid); commit;", process_name,
        )
        try:
            check(blocked([review_name, process_name]),
                  "receipt review and lifecycle finalization concurrently wait behind the deletion gate")
        finally:
            review_gate.release()
        review_output, review_error = review.communicate(timeout=30)
        process_output, process_error = process.communicate(timeout=30)
        final_exists = value("select exists(select 1 from app.challenge_finals_v1 where challenge_id=" + quoted(review_challenge) + "::uuid)") == "t"
        check(process.returncode == 0 and not process_error,
              "concurrent lifecycle finalization returns a defined lifecycle state")
        check((review.returncode == 0 and not final_exists) or (review.returncode != 0 and final_exists and "challenge_deletion_review_unavailable" in review_error),
              "review/finalization race preserves either the filed review hold or the already-final result")

        # Finally, race an ordinary finalization against deletion itself. The
        # winner may choose the normal score or the safe void, but neither can
        # rewrite the persisted final and the deleted actor remains exited.
        final_receipt = "local_final_" + uuid.uuid4().hex
        final_gate = Held("select app.challenge_gate_v1(true)", "deletion-race-final-gate")
        delete_final_name = "ddf-" + uuid.uuid4().hex
        final_name = "dfp-" + uuid.uuid4().hex
        delete_final = contender(
            deletion_call(3, str(uuid.uuid4()), final_receipt, "fictional-apple-race-final"), delete_final_name,
        )
        final_process = contender(
            "begin; select public.challenge_process_v1(" + quoted(final_challenge) + "::uuid); commit;", final_name,
        )
        try:
            check(blocked([delete_final_name, final_name]),
                  "deletion and due finalization concurrently wait behind the exclusive gate")
        finally:
            final_gate.release()
        delete_final_output, delete_final_error = delete_final.communicate(timeout=30)
        final_output, final_error = final_process.communicate(timeout=30)
        check(delete_final.returncode == 0 and delete_final_output.strip() and not delete_final_error,
              "the concurrent deletion request completes once")
        check(final_process.returncode == 0 and final_output.strip() and not final_error,
              "the concurrent finalization request completes once")
        check(value("select count(*) from app.challenge_finals_v1 where challenge_id=" + quoted(final_challenge) + "::uuid") == "1",
              "deletion/finalization race leaves exactly one immutable final")
        before = value("select row(result,revision)::text from app.challenge_finals_v1 where challenge_id=" + quoted(final_challenge) + "::uuid")
        sql("select public.challenge_process_v1(" + quoted(final_challenge) + "::uuid)")
        after = value("select row(result,revision)::text from app.challenge_finals_v1 where challenge_id=" + quoted(final_challenge) + "::uuid")
        check(before == after, "post-race lifecycle retries cannot rewrite the final")
        check(value("select count(*) from app.challenge_members_v1 where challenge_id=" + quoted(final_challenge)
                    + "::uuid and actor_id=" + quoted(actors[3]) + "::uuid and exited_at is null") == "0",
              "the finalized race leaves the deleted actor non-participating")

        args.report.write_text(json.dumps({
            "evidence": "real concurrent PostgreSQL sessions on one task-owned loopback DB; all actors/providers are fictional",
            "checks": checks,
            "limits": [
                "No hosted credentials, real Apple revocation, Stripe call, Health access, device hardware, deployment, or user data.",
                "Community is exercised only through the existing explicit fixture-only configuration.",
            ],
            "cleanup": "runtime disabled and only newly minted fictional Auth sessions revoked",
        }, indent=2) + "\n")
    finally:
        for process in owned:
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=5)
        try:
            sql("select public.challenge_runtime_v1(false,false,false,array[]::uuid[],clock_timestamp())", check=False)
            sql("delete from auth.sessions where user_id = any(array[" + ",".join(quoted(actor) + "::uuid" for actor in actors) + "])", check=False)
        except Exception:
            pass


if __name__ == "__main__":
    main()
