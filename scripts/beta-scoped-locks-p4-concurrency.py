#!/usr/bin/env python3
"""Focused real-session races for Prompt 4 on a task-owned disposable DB."""
import argparse
from collections.abc import Callable
import json
import os
from pathlib import Path
import re
import select
import subprocess
import time
from urllib.parse import urlparse
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
    address = urlparse(args.db_url)
    assert address.hostname == '127.0.0.1'
    db_section = config.split('[db]\n',1)[1].split('\n[',1)[0]
    assert address.port == int(re.search(r'^port = (\d+)$',db_section,re.M).group(1))
    assert address.path == '/postgres' and address.username == 'postgres'
    owned_processes: list[subprocess.Popen[str]] = []

    def sql(source: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["psql", args.db_url, "-XqAt", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=sqlstate"],
            input=source,
            text=True,
            capture_output=True,
            check=check,
            timeout=20,
            env={k: v for k, v in os.environ.items() if not k.startswith('PG')},
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
            received = ''
            while time.monotonic() < deadline:
                if not select.select([self.process.stdout], [], [], 0.25)[0]:
                    continue
                received += os.read(self.process.stdout.fileno(), 4096).decode()
                if '1' in received.splitlines():
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

    actors = [str(uuid.uuid4()) for _ in range(48)]
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
            check(json_value(auth(actors[0], sessions[0], 'select public.challenge_access_status_v1()'))['age_confirmed'],
                  "ordinary reads proceed while the same actor mutation scope is held")
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

        # Revocation wins a link row and denies a waiting new redemption.
        fresh_link = json_value(command(actors[5],sessions[5],str(uuid.uuid4()),{'op':'issue_link','id':link_challenge}))
        held = Held(f"select 1 from app.challenge_links_v1 where id='{fresh_link['id']}' for update")
        name = 'p4_link_revoke_' + uuid.uuid4().hex
        revoke_waiter = contender(command(actors[30], sessions[30], str(uuid.uuid4()), {'op':'redeem_link','token':fresh_link['token']}), name)
        try:
            check(blocked([name]), 'redemption waits behind link revocation')
        finally:
            held.release(f"select set_config('app.challenge_write_v1','on',true); update app.challenge_links_v1 set revoked_at=app.challenge_now_v1() where id='{fresh_link['id']}'")
        _, error = revoke_waiter.communicate(timeout=20)
        check(revoke_waiter.returncode != 0 and '42501' in error, 'revoked link rejects waiting redemption')
        check(value(f"select count(*) from app.challenge_redemptions_v1 where link_id='{fresh_link['id']}'")=='0','revocation denial occurred below capacity with no redemption effect')

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

        # Concurrent admissions by the same actor cannot exceed three unsettled.
        preview = json_value(auth(actors[31],sessions[31],
            f"select public.challenge_personal_preview_v1('personal_steps_goal_v1',{literal(json.dumps(later))}::jsonb,100)"))
        sql(f"select public.challenge_readiness_fixture_v1('{actors[31]}')")
        payload = {'op':'personal_commit','policy':'personal_steps_goal_v1','config':later,'target':100,'consent':True,'digest':preview['digest']}
        contenders = [contender(command(actors[31],sessions[31],str(uuid.uuid4()),payload),'p4_admit_'+uuid.uuid4().hex) for _ in range(4)]
        results = [p.communicate(timeout=20) for p in contenders]
        check(sum(p.returncode == 0 for p in contenders)==3 and sum('23505' in error for _,error in results)==1,
              'four conflicting personal admissions reserve exactly three unsettled slots')

        # Consent competes with reopening the same persisted agreement revision.
        def mutate(index, cid, op, **extra):
            revision = int(value(f"select revision from app.challenge_lobbies_v1 where id='{cid}'"))
            return json_value(command(actors[index],sessions[index],str(uuid.uuid4()),{'op':op,'id':cid,'revision':revision,**extra}))
        consent_challenge = create(32)
        sql(f"insert into public.friendships(user_a,user_b,requested_by,status) values(least('{actors[32]}'::uuid,'{actors[33]}'::uuid),greatest('{actors[32]}'::uuid,'{actors[33]}'::uuid),'{actors[32]}','accepted')")
        mutate(32,consent_challenge,'invite',username=value(f"select handle from public.profiles where id='{actors[33]}'"))
        mutate(32,consent_challenge,'target',target=100)
        mutate(33,consent_challenge,'target',target=100)
        mutate(32,consent_challenge,'select',actor_id=actors[33],selected=True)
        mutate(32,consent_challenge,'freeze')
        sql(f"select public.challenge_readiness_fixture_v1('{actors[33]}')")
        digest = value(f"select digest from app.challenge_agreements_v1 where challenge_id='{consent_challenge}'")
        revision = int(value(f"select revision from app.challenge_lobbies_v1 where id='{consent_challenge}'"))
        held = Held(f"select app.challenge_lock_v1('challenge','{consent_challenge}')")
        names = ['p4_consent_'+uuid.uuid4().hex for _ in range(2)]
        contenders = [contender(command(actors[i],sessions[i],str(uuid.uuid4()),{'op':op,'id':consent_challenge,'revision':revision,**extra}),name)
                      for i,op,extra,name in [(32,'reopen',{},names[0]),(33,'consent',{'consent':True,'digest':digest},names[1])]]
        try:
            check(blocked(names),'consent and reopen wait on the same agreement scope')
        finally: held.release()
        results = [p.communicate(timeout=20) for p in contenders]
        check(sum(p.returncode==0 for p in contenders)==1 and any('40001' in error for _,error in results),
              'consent/reopen race has one commit and one stale revision')

        # Different callers on different challenges conflict through the entrant
        # profile: a creator's freeze versus that entrant's community admission.
        cross = create(35)
        sql(f"insert into public.friendships(user_a,user_b,requested_by,status) values(least('{actors[35]}'::uuid,'{actors[36]}'::uuid),greatest('{actors[35]}'::uuid,'{actors[36]}'::uuid),'{actors[35]}','accepted')")
        mutate(35,cross,'invite',username=value(f"select handle from public.profiles where id='{actors[36]}'"))
        mutate(35,cross,'target',target=100)
        mutate(36,cross,'target',target=100)
        mutate(35,cross,'select',actor_id=actors[36],selected=True)
        for index in (35,36): sql(f"select public.challenge_readiness_fixture_v1('{actors[index]}')")
        preview = json_value(auth(actors[36],sessions[36],f"select public.challenge_personal_preview_v1('personal_steps_goal_v1',{literal(json.dumps(later))}::jsonb,100)"))
        payload = {'op':'personal_commit','policy':'personal_steps_goal_v1','config':later,'target':100,'consent':True,'digest':preview['digest']}
        for _ in range(2): sql(command(actors[36],sessions[36],str(uuid.uuid4()),payload))
        community = value(f"select public.challenge_publish_community_fixture_v1('{uuid.uuid4()}','{actors[47]}',{literal(json.dumps(later))}::jsonb,100,2,250,true)")
        digest = value(f"select digest from app.challenge_agreements_v1 where challenge_id='{community}'")
        revision = int(value(f"select revision from app.challenge_lobbies_v1 where id='{cross}'"))
        held = Held(f"select 1 from public.profiles where id='{actors[36]}' for update")
        names = ['p4_cross_admission_'+uuid.uuid4().hex for _ in range(2)]
        contenders = [contender(command(actors[i],sessions[i],str(uuid.uuid4()),payload),name) for i,payload,name in [
            (35,{'op':'freeze','id':cross,'revision':revision},names[0]),
            (36,{'op':'join_community','id':community,'digest':digest,'consent':True},names[1])]]
        try: check(blocked(names),'different callers coordinate cross-challenge admission on the entrant profile')
        finally: held.release()
        results = [p.communicate(timeout=20) for p in contenders]
        check(sum(p.returncode==0 for p in contenders)==1 and any('23505' in error for _,error in results),
              'cross-challenge freeze/join race preserves three-unsettled admission limit')
        check(value(f"select count(*) from app.challenge_slots_v1 where actor_id='{actors[36]}'")=='3','conflicting admissions leave exactly three entrant slots')

        # An actual operator suspension commits while personal admission waits
        # on that profile, after the admission's initial eligibility read.
        suspended_challenge = create(37)
        sql(f"select public.challenge_grant_operator_v1('{actors[47]}','{suspended_challenge}','moderate','2026-10-05T00:00Z'); select public.challenge_readiness_fixture_v1('{actors[37]}')")
        preview = json_value(auth(actors[37],sessions[37],f"select public.challenge_personal_preview_v1('personal_steps_goal_v1',{literal(json.dumps(later))}::jsonb,100)"))
        payload = {'op':'personal_commit','policy':'personal_steps_goal_v1','config':later,'target':100,'consent':True,'digest':preview['digest']}
        moderation = {'op':'suspend','id':suspended_challenge,'actor_id':actors[37],'reason':'unsafe_behavior'}
        held = Held(f"select set_config('request.jwt.claims',{literal(json.dumps({'sub':actors[47],'session_id':sessions[47]}))},true); set local role authenticated; select public.challenge_operator_action_v1('{uuid.uuid4()}',{literal(json.dumps(moderation))}::jsonb)")
        name = 'p4_suspend_admit_'+uuid.uuid4().hex
        suspended = contender(command(actors[37],sessions[37],str(uuid.uuid4()),payload),name)
        try: check(blocked([name]),'personal admission waits behind an uncommitted operator suspension')
        finally: held.release()
        _,error = suspended.communicate(timeout=20)
        check(suspended.returncode!=0 and '42501' in error,'personal admission rechecks suspension after its profile wait')

        # Reciprocal invitations require both profile rows in one UUID order.
        left,right = create(38),create(39)
        sql(f"insert into public.friendships(user_a,user_b,requested_by,status) values(least('{actors[38]}'::uuid,'{actors[39]}'::uuid),greatest('{actors[38]}'::uuid,'{actors[39]}'::uuid),'{actors[38]}','accepted')")
        low = min(actors[38],actors[39])
        held = Held(f"select 1 from public.profiles where id='{low}' for update")
        names = ['p4_reciprocal_'+uuid.uuid4().hex for _ in range(2)]
        contenders = [contender(command(actors[i],sessions[i],str(uuid.uuid4()),{'op':'invite','id':cid,'revision':1,'username':value(f"select handle from public.profiles where id='{actors[j]}'")}),name)
                      for i,j,cid,name in [(38,39,left,names[0]),(39,38,right,names[1])]]
        try: check(blocked(names),'reciprocal invites wait on the same lowest profile first')
        finally: held.release()
        results = [p.communicate(timeout=20) for p in contenders]
        check(all(p.returncode==0 for p in contenders),'reciprocal invitations complete without an inverted profile deadlock')

        # Use wall time: a fictional clock is fenced and cannot advance while a
        # request holds the shared gate. Only this synthetic lobby has a short cutoff.
        cutoff = create(40)
        cutoff_community = community
        cutoff_digest = value(f"select digest from app.challenge_agreements_v1 where challenge_id='{cutoff_community}'")
        sql(f"select public.challenge_runtime_v1(true,true,true,{actor_array},null); select public.challenge_readiness_fixture_v1('{actors[41]}'); select set_config('app.challenge_write_v1','on',false); update app.challenge_lobbies_v1 set starts_at=clock_timestamp()+interval '800 milliseconds' where id in('{cutoff}','{cutoff_community}')")
        held = Held(f"select app.challenge_lock_many_v1('challenge',array['{cutoff}'::uuid,'{cutoff_community}'::uuid])")
        names = ['p4_cutoff_'+uuid.uuid4().hex for _ in range(2)]
        contenders = [contender(command(actors[i],sessions[i],str(uuid.uuid4()),payload),name) for i,payload,name in [
            (40,{'op':'issue_link','id':cutoff},names[0]),
            (41,{'op':'join_community','id':cutoff_community,'digest':cutoff_digest,'consent':True},names[1])]]
        try:
            check(blocked(names),'link issuance and join both reach their challenge wait before cutoff')
            time.sleep(1)
        finally: held.release()
        results = [p.communicate(timeout=20) for p in contenders]
        check(all(p.returncode!=0 for p in contenders) and '42501' in results[0][1] and '55000' in results[1][1],
              'link issuance and community join refresh time after waiting past their cutoff')
        sql(f"select public.challenge_runtime_v1(true,true,true,{actor_array},'2026-10-01T00:00Z'); select set_config('app.challenge_write_v1','on',false); update app.challenge_lobbies_v1 set starts_at='2026-10-20T00:00Z' where id in('{cutoff}','{cutoff_community}')")

        # A worker skips a durable row owned by another claiming transaction.
        first_due = create(28, due)
        second_due = create(29, due)
        sql(f"select public.challenge_runtime_v1(true,true,true,{actor_array},'2026-10-04T00:00Z');")
        held = Held(f"select 1 from app.challenge_work_claims_v1 where challenge_id='{first_due}' for update")
        run_one = str(uuid.uuid4())
        worker = contender(f"select public.challenge_claim_batch_v1('{run_one}',1)::text", "p4_worker_" + uuid.uuid4().hex)
        try:
            output, error = worker.communicate(timeout=10)
            claimed = json.loads(output)["claims"]
            check(worker.returncode == 0 and not error and len(claimed) == 1 and claimed[0]["id"] == second_due, "worker skips a concurrently locked durable claim row")
        finally:
            held.release()
        run_two = str(uuid.uuid4())
        second = json_value(f"select public.challenge_claim_batch_v1('{run_two}',1)")['claims']
        check(len(second)==1 and second[0]['id']==first_due, 'another committed claim skips the live lease and owns independent work')

        def complete(claim):
            return f"select public.challenge_complete_claim_v1('{claim['id']}','{claim['claim_token']}')"
        held = Held(f"select app.challenge_lock_v1('challenge','{first_due}')")
        name = 'p4_complete_wait_'+uuid.uuid4().hex
        first_completion = contender(complete(second[0]), name)
        try:
            check(blocked([name]),'completion waits only on its own busy challenge')
            check(json_value(complete(claimed[0]))['status']=='cancelled','independent worker completion commits while another completion waits')
        finally: held.release()
        output, error = first_completion.communicate(timeout=20)
        check(first_completion.returncode==0 and not error and json.loads(output)['status']=='cancelled','waiting independent completion commits after its challenge is released')
        check(json_value(complete(second[0]))==json.loads(output),'duplicate completion returns its exact saved response')

        # Materialize new due work, recover an abandoned lease, and fence its old token.
        sql(f"select public.challenge_runtime_v1(true,true,true,{actor_array},'2026-10-01T00:00Z');")
        abandoned = create(34,due)
        sql(f"select public.challenge_runtime_v1(true,true,true,{actor_array},'2026-10-04T00:00Z');")
        old = json_value(f"select public.challenge_claim_batch_v1('{uuid.uuid4()}',1)")['claims'][0]
        sql(f"update app.challenge_work_claims_v1 set lease_expires_at=clock_timestamp()-interval '1 second' where challenge_id='{abandoned}'")
        check(json_value('select public.challenge_operations_status_v1()')['abandoned_count']==1,'abandoned claims are visible to operations')
        new = json_value(f"select public.challenge_claim_batch_v1('{uuid.uuid4()}',1)")['claims'][0]
        check(new['id']==abandoned and new['claim_token']!=old['claim_token'] and new['attempt']==2,'expired claim receives a new token and incremented attempt')
        stale = sql(complete(old),check=False)
        check(stale.returncode!=0 and '55000' in stale.stderr,'stale worker cannot apply a recovered claim')
        held = Held(f"select app.challenge_lock_v1('challenge','{abandoned}')")
        names = ['p4_duplicate_'+uuid.uuid4().hex for _ in range(2)]
        contenders = [contender(complete(new),name) for name in names]
        try: check(blocked(names),'duplicate completions serialize on one challenge')
        finally: held.release()
        results = [p.communicate(timeout=20) for p in contenders]
        check(all(p.returncode==0 for p in contenders) and results[0][0]==results[1][0], 'concurrent duplicate completions return one exact result')
        check(value(f"select revision from app.challenge_lobbies_v1 where id='{abandoned}'")=='2','duplicate completion changes lifecycle revision only once')

        revisions = value("select jsonb_object_agg(id,revision) from app.challenge_lobbies_v1 where status='cancelled'")
        for _ in range(4):
            check(json_value(f"select public.challenge_claim_batch_v1('{uuid.uuid4()}',50)")['claims']==[], 'repeated poll excludes all cancelled work')
        check(value("select jsonb_object_agg(id,revision) from app.challenge_lobbies_v1 where status='cancelled'")==revisions,'cancelled revisions remain unchanged across repeated polls')

        # Pausing the control plane cannot block an ordinary read on its gate.
        held = Held('select app.challenge_gate_v1(true)')
        try:
            check(json_value(auth(actors[0],sessions[0],'select public.challenge_access_status_v1()'))['age_confirmed'], 'ordinary read proceeds while the exclusive control-plane gate is held')
        finally: held.release()
        sql(f"select public.challenge_grant_operator_v1('{actors[47]}','{community}','moderate','2026-10-05T00:00Z')")
        check(json_value(auth(actors[47],sessions[47],f"select public.challenge_operator_close_v1('{uuid.uuid4()}','{community}')"))['status']=='cancelled',
              'owned community closes through the operator API after the races')
    finally:
        cleanup_owned(
            owned_processes,
            lambda: sql("select public.challenge_runtime_v1(false,false,false,'{}',null)", check=False),
        )

    print(json.dumps({"evidence": "real concurrent SQL sessions on task-owned disposable DB", "count": len(checks), "checks": checks}, indent=2))


if __name__ == "__main__":
    main()
