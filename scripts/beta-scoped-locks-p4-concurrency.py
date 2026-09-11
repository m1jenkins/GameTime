#!/usr/bin/env python3
"""Focused real-session races for Prompt 4 on a task-owned disposable DB."""
import argparse
from collections.abc import Callable
import json
import os
from pathlib import Path
import select
import subprocess
import time
import uuid


def literal(value: object) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def cleanup_owned(
    processes: list[subprocess.Popen[str]],
    disable_gates: Callable[[], subprocess.CompletedProcess[str]],
) -> None:
    # A timed-out contender can still hold the shared gate. Close our sessions
    # before asking the database for the exclusive gate used by shutdown.
    for process in processes:
        if process.poll() is None:
            process.kill()
    try:
        for process in processes:
            process.communicate(timeout=5)
    finally:
        result = disable_gates()
        if result.returncode != 0:
            raise RuntimeError("Could not disable owned Prompt 4 gates: " + result.stderr.strip())
    print("Owned Prompt 4 gates disabled; fictional rows remain only in the disposable database.", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db-url", required=True)
    parser.add_argument("--owned-root", required=True, type=Path)
    parser.add_argument("--owned-project", required=True)
    args = parser.parse_args()
    config = (args.owned_root / "supabase/config.toml").read_text()
    assert f'project_id = "{args.owned_project}"' in config
    assert "127.0.0.1:59432" in args.db_url
    owned_processes: list[subprocess.Popen[str]] = []

    def sql(source: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["psql", args.db_url, "-XqAt", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=sqlstate"],
            input=source,
            text=True,
            capture_output=True,
            check=check,
            timeout=20,
        )

    def value(source: str) -> str:
        return sql(source).stdout.strip()

    def json_value(source: str) -> object:
        lines = [line for line in value(source).splitlines() if line]
        return json.loads(lines[-1])

    def auth(actor: str, session: str, source: str) -> str:
        claims = json.dumps({"sub": actor, "session_id": session})
        return (
            "begin; select set_config('request.jwt.claims',"
            + literal(claims)
            + ",true); set local role authenticated; "
            + source
            + "; commit;"
        )

    def command(actor: str, session: str, request: str, payload: dict[str, object]) -> str:
        return auth(
            actor,
            session,
            f"select public.challenge_command_v1('{request}',{literal(json.dumps(payload))}::jsonb)::text",
        )

    class Held:
        def __init__(self, source: str):
            self.process = subprocess.Popen(
                ["psql", args.db_url, "-XqAt", "-v", "ON_ERROR_STOP=1"],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1,
            )
            owned_processes.append(self.process)
            assert self.process.stdin and self.process.stdout
            self.process.stdin.write("begin; " + source + "; select 1;\n")
            self.process.stdin.flush()
            deadline = time.monotonic() + 10
            ready = False
            while time.monotonic() < deadline:
                if not select.select([self.process.stdout], [], [], 0.25)[0]:
                    continue
                if self.process.stdout.readline().strip() == "1":
                    ready = True
                    break
            if not ready:
                self.process.kill()
                raise RuntimeError("could not establish owned test lock")

        def release(self, extra: str = "") -> None:
            assert self.process.stdin
            self.process.stdin.write(extra + "; commit;\n\\q\n")
            self.process.stdin.flush()
            _, error = self.process.communicate(timeout=15)
            assert self.process.returncode == 0, error

    def contender(source: str, name: str) -> subprocess.Popen[str]:
        process = subprocess.Popen(
            ["psql", args.db_url, "-XqAt", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=sqlstate"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env={**os.environ, "PGAPPNAME": name},
        )
        owned_processes.append(process)
        assert process.stdin
        process.stdin.write(source)
        process.stdin.close()
        process.stdin = None
        return process

    def blocked(names: list[str]) -> bool:
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            count = value(
                "select count(*) from pg_stat_activity where application_name in ("
                + ",".join(map(literal, names))
                + ") and cardinality(pg_blocking_pids(pid))>0"
            )
            if int(count) == len(names):
                return True
            time.sleep(0.02)
        return False

    actors = [str(uuid.uuid4()) for _ in range(30)]
    sessions = [str(uuid.uuid4()) for _ in actors]
    checks: list[str] = []

    def check(condition: bool, label: str) -> None:
        assert condition, label
        checks.append(label)
        print("PASS: " + label, flush=True)

    actor_array = "array[" + ",".join(literal(actor) + "::uuid" for actor in actors) + "]"
    later = {"start_date": "2026-10-20", "days": 1, "timezone": "UTC", "amount_cents": 100}
    due = {"start_date": "2026-10-03", "days": 1, "timezone": "UTC", "amount_cents": 100}

    def create_payload(config_value: dict[str, object]) -> dict[str, object]:
        return {"op": "create", "config": config_value}

    def create(actor_index: int, config_value: dict[str, object] = later) -> str:
        output = json_value(
            command(
                actors[actor_index],
                sessions[actor_index],
                str(uuid.uuid4()),
                create_payload(config_value),
            )
        )
        assert isinstance(output, dict)
        return str(output["id"])

    try:
        for index, (actor, session) in enumerate(zip(actors, sessions), 1):
            sql(
                f"insert into auth.users(id) values('{actor}');"
                f"insert into public.profiles(id,handle,display_name,timezone) values('{actor}','p4race{index:02d}{uuid.uuid4().hex[:8]}','Fictional P4','UTC');"
                f"insert into auth.sessions(id,user_id) values('{session}','{actor}');"
            )
        sql(f"insert into public.friendships(user_a,user_b,requested_by,status) values(least('{actors[3]}'::uuid,'{actors[4]}'::uuid),greatest('{actors[3]}'::uuid,'{actors[4]}'::uuid),'{actors[3]}','accepted');")
        sql(f"select public.challenge_runtime_v1(true,true,true,{actor_array},'2026-10-01T00:00Z');")
        for actor, session in zip(actors, sessions):
            sql(command(actor, session, str(uuid.uuid4()), {"op": "confirm_age", "confirmed": True}))

        # An unrelated actor completes while the first actor scope is held.
        held = Held(f"select app.challenge_lock_v1('actor','{actors[0]}')")
        waiting_name = "p4_actor_wait_" + uuid.uuid4().hex
        free_name = "p4_actor_free_" + uuid.uuid4().hex
        waiting = contender(command(actors[0], sessions[0], str(uuid.uuid4()), create_payload(later)), waiting_name)
        free = contender(command(actors[1], sessions[1], str(uuid.uuid4()), create_payload(later)), free_name)
        try:
            check(blocked([waiting_name]), "same-actor work waits on its actor scope")
            free_output, free_error = free.communicate(timeout=5)
            check(free.returncode == 0 and free_output.strip() and not free_error, "an unrelated account proceeds while another actor is locked")
        finally:
            held.release()
        waiting_output, waiting_error = waiting.communicate(timeout=20)
        check(waiting.returncode == 0 and waiting_output.strip() and not waiting_error, "waiting actor work completes after its scope is released")

        # The same durable request races behind one actor lock and commits once.
        request = str(uuid.uuid4())
        source = command(actors[2], sessions[2], request, create_payload(later))
        names = ["p4_exact_" + uuid.uuid4().hex for _ in range(2)]
        held = Held(f"select app.challenge_lock_v1('actor','{actors[2]}')")
        contenders = [contender(source, name) for name in names]
        try:
            check(blocked(names), "same-actor exact requests both wait on one actor scope")
        finally:
            held.release()
        results = [process.communicate(timeout=20) for process in contenders]
        check(all(process.returncode == 0 for process in contenders) and results[0][0] == results[1][0], "same-actor exact retries return one stable response")
        check(value(f"select count(*) from app.challenge_requests_v1 where actor_id='{actors[2]}' and request_id='{request}'") == "1", "same-actor exact race stores one receipt")

        # Two members racing one challenge serialize and one observes stale revision.
        challenge = create(3)
        revision = int(value(f"select revision from app.challenge_lobbies_v1 where id='{challenge}'"))
        invite = {"op": "invite", "id": challenge, "revision": revision, "username": value(f"select handle from public.profiles where id='{actors[4]}'")}
        sql(command(actors[3], sessions[3], str(uuid.uuid4()), invite))
        revision = int(value(f"select revision from app.challenge_lobbies_v1 where id='{challenge}'"))
        configure = {"op": "configure", "id": challenge, "revision": revision, "config": later}
        target = {"op": "target", "id": challenge, "revision": revision, "target": 100}
        names = ["p4_challenge_" + uuid.uuid4().hex for _ in range(2)]
        held = Held(f"select app.challenge_lock_v1('challenge','{challenge}')")
        contenders = [
            contender(command(actors[3], sessions[3], str(uuid.uuid4()), configure), names[0]),
            contender(command(actors[4], sessions[4], str(uuid.uuid4()), target), names[1]),
        ]
        try:
            check(blocked(names), "same-challenge member mutations share one challenge scope")
        finally:
            held.release()
        results = [process.communicate(timeout=20) for process in contenders]
        check(sorted(process.returncode == 0 for process in contenders) == [False, True] and any("40001" in error for _, error in results), "same-challenge race yields one commit and one explicit stale retry")

        # Fill nineteen redemptions, then race the twentieth place on one link.
        link_challenge = create(5)
        link_result = json_value(command(actors[5], sessions[5], str(uuid.uuid4()), {"op": "issue_link", "id": link_challenge}))
        assert isinstance(link_result, dict)
        token = link_result["token"]
        link_id = link_result["id"]
        for index in range(6, 25):
            sql(command(actors[index], sessions[index], str(uuid.uuid4()), {"op": "redeem_link", "token": token}))
        names = ["p4_link_" + uuid.uuid4().hex for _ in range(2)]
        held = Held(f"select 1 from app.challenge_links_v1 where id='{link_id}' for update")
        contenders = [
            contender(command(actors[index], sessions[index], str(uuid.uuid4()), {"op": "redeem_link", "token": token}), name)
            for index, name in zip((25, 26), names)
        ]
        try:
            check(blocked(names), "same-link final-slot requests both wait on the link row")
        finally:
            held.release()
        results = [process.communicate(timeout=20) for process in contenders]
        check(sorted(process.returncode == 0 for process in contenders) == [False, True] and any("42501" in error for _, error in results), "same-link race admits exactly the twentieth account")
        check(value(f"select count(*) from app.challenge_redemptions_v1 where link_id='{link_id}'") == "20", "same-link race preserves the twenty-account ceiling")

        # Revocation that wins the session-row lock denies the waiting request.
        name = "p4_session_" + uuid.uuid4().hex
        held = Held(f"select 1 from auth.sessions where id='{sessions[27]}' for update")
        revoked = contender(command(actors[27], sessions[27], str(uuid.uuid4()), create_payload(later)), name)
        try:
            check(blocked([name]), "request waits behind an in-flight session revocation")
        finally:
            held.release(f"update auth.sessions set not_after=clock_timestamp() where id='{sessions[27]}'")
        _, error = revoked.communicate(timeout=20)
        check(revoked.returncode != 0 and "42501" in error, "revoked session cannot commit after waiting")

        # A worker skips a separately claimed challenge and completes unrelated work.
        first_due = create(28, due)
        second_due = create(29, due)
        sql(f"select public.challenge_runtime_v1(true,true,true,{actor_array},'2026-10-04T00:00Z');")
        held = Held(f"select app.challenge_lock_v1('challenge','{first_due}')")
        run_one = str(uuid.uuid4())
        worker = contender(f"select public.challenge_run_batch_v1('{run_one}',1)::text", "p4_worker_" + uuid.uuid4().hex)
        try:
            output, error = worker.communicate(timeout=10)
            claimed = json.loads(output)["processed"]
            check(worker.returncode == 0 and not error and len(claimed) == 1 and claimed[0]["id"] == second_due, "worker skips an independently claimed challenge and completes another")
        finally:
            held.release()
        run_two = str(uuid.uuid4())
        second = json.loads(value(f"select public.challenge_run_batch_v1('{run_two}',1)::text"))
        check(len(second["processed"]) == 1 and second["processed"][0]["id"] == first_due, "released challenge is claimed by an independent worker completion")
    finally:
        cleanup_owned(
            owned_processes,
            lambda: sql("select public.challenge_runtime_v1(false,false,false,'{}',null)", check=False),
        )

    print(json.dumps({"evidence": "real concurrent SQL sessions on task-owned disposable DB", "count": len(checks), "checks": checks}, indent=2))


if __name__ == "__main__":
    main()
