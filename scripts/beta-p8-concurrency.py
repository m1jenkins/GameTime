#!/usr/bin/env python3
"""Privacy1/S1 actual-session regression; only an explicitly owned local DB.

Adapts the P4 psql Held/contender/pg_blocking_pids harness. No server hooks.
Actor connections log in as authenticator, then SET LOCAL ROLE authenticated;
only fixtures and lock observations use the database owner. Failed assertions
are retained alongside successful controls instead of stopping the first race.
"""
import argparse
import json
import os
from pathlib import Path
import select
import subprocess
import time
from urllib.parse import urlparse
import uuid


def literal(value):
    return "'" + str(value).replace("'", "''") + "'"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--db-url', required=True)
    parser.add_argument('--auth-db-url', required=True)
    parser.add_argument('--owned-root', type=Path, required=True)
    parser.add_argument('--owned-project', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    config = (args.owned_root / 'supabase/config.toml').read_text()
    assert f'project_id = "{args.owned_project}"' in config
    admin, auth = map(urlparse, (args.db_url, args.auth_db_url))
    assert admin.hostname == auth.hostname == '127.0.0.1'
    assert admin.port == auth.port and f'port = {admin.port}' in config.split('[db]\n')[1].split('\n[')[0]
    assert admin.path == auth.path and admin.path in ('/postgres', '/p8_fresh')
    assert admin.username == 'postgres' and auth.username == 'authenticator'
    assert not args.output.exists(), 'Never overwrite failed evidence'
    env = {k: v for k, v in os.environ.items() if not k.startswith('PG')}
    processes, events, checks = [], [], []

    def record(kind, **detail):
        events.append(dict(order=len(events) + 1, kind=kind, **detail))

    def sql(source):
        result = subprocess.run(['psql', args.db_url, '-XqAt', '-v', 'ON_ERROR_STOP=1'],
                                input=source, text=True, capture_output=True, env=env, timeout=20)
        if result.returncode:
            raise RuntimeError(result.stderr)
        return result.stdout.strip()

    def value(source):
        return json.loads(sql(source).splitlines()[-1])

    def check(condition, label):
        checks.append(dict(pass_=bool(condition), label=label))
        print(('PASS ' if condition else 'FAIL ') + label, flush=True)

    class Session:
        def __init__(self, name, actor=None, role='authenticated', owner=False):
            self.name = 'p8_' + name + '_' + uuid.uuid4().hex[:8]
            self.p = subprocess.Popen(['psql', args.db_url if owner else args.auth_db_url,
                                       '-XqAt', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose'],
                                      stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                      text=True, env={**env, 'PGAPPNAME': self.name})
            processes.append(self.p)
            context = '' if owner else f'set local role {role};'
            if actor is not None:
                context += 'set local request.jwt.claims = ' + literal(json.dumps({'sub': actors[actor], 'session_id': sessions[actor]})) + ';'
            self.send("begin isolation level read committed; set local statement_timeout='15s'; " + context +
                      "select json_build_object('pid',pg_backend_pid(),'isolation',current_setting('transaction_isolation'),'session_user',session_user,'role',current_user);")
            meta = json.loads(self.receive().strip())
            self.pid = meta['pid']
            record('begin', name=self.name, **meta)

        def send(self, source):
            assert self.p.stdin
            self.pending = source
            self.p.stdin.write(source + "\n\\echo P8_BARRIER\n")
            self.p.stdin.flush()

        def receive(self):
            received = ''
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                if select.select([self.p.stdout], [], [], .1)[0]:
                    chunk = os.read(self.p.stdout.fileno(), 65536).decode()
                    received += chunk
                    if 'P8_BARRIER\n' in received:
                        output = received.split('P8_BARRIER\n')[0].strip()
                        record('barrier', name=self.name, output=output)
                        return output
                if self.p.poll() is not None:
                    error = self.p.stderr.read()
                    record('error', name=self.name, output=received.strip(), error=error)
                    return {'error': error}
            raise RuntimeError('Missing psql barrier: ' + self.name)

        def commit(self):
            if self.p.poll() is None:
                self.send('commit;')
                result = self.receive()
                assert not isinstance(result, dict), result
                record('commit', name=self.name)
                self.p.stdin.write('\\q\n')
                self.p.stdin.flush()
                self.p.communicate(timeout=5)

    def observe(session, blocker):
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            state = value(f"select coalesce((select jsonb_build_object('pid',pid,'state',state,'wait_event_type',wait_event_type,'wait_event',wait_event,'blockers',pg_blocking_pids(pid),'current_command',query={literal(session.pending)}) from pg_stat_activity where pid={session.pid}),'{{}}'::jsonb)")
            if blocker.pid in state.get('blockers', []) or (state.get('current_command') and state.get('state') == 'idle in transaction') or session.p.poll() is not None:
                record('observed', name=session.name, expected_blocker=blocker.pid, **state)
                return blocker.pid in state.get('blockers', [])
            time.sleep(.02)
        raise RuntimeError('Neither controlled wait nor completion: ' + session.name)

    def call(actor, query, role='authenticated'):
        session = Session('rpc', actor, role)
        session.send(query)
        result = session.receive()
        session.commit()
        return result if isinstance(result, dict) else json.loads(result) if result else None

    def denied(result, reason):
        return isinstance(result, dict) and '42501' in result.get('error', '') and reason in result['error']

    def command(payload, request=None):
        return f"select public.challenge_command_v1('{request or uuid.uuid4()}',{literal(json.dumps(payload))}::jsonb);"

    def mutate(actor, cid, op, **extra):
        revision = int(sql(f"select revision from app.challenge_lobbies_v1 where id='{cid}'"))
        return call(actor, command(dict(op=op, id=cid, revision=revision, **extra)))

    actors = [str(uuid.uuid4()) for _ in range(10)]
    sessions = [str(uuid.uuid4()) for _ in actors]
    actor_array = 'array[' + ','.join(literal(a) + '::uuid' for a in actors) + ']'
    early = dict(start_date='2026-10-03', days=1, timezone='UTC', amount_cents=100)
    later = dict(start_date='2026-10-10', days=1, timezone='UTC', amount_cents=100)
    create = dict(op='create', policy='friend_steps_goal_v1', config=later)
    failure = None
    try:
        record('server', version=sql('show server_version'), database=admin.path)
        for i, (actor, session) in enumerate(zip(actors, sessions)):
            sql(f"insert into auth.users(id) values('{actor}'); insert into public.profiles(id,handle,display_name,timezone) values('{actor}','p8{actor.replace('-', '')[:20]}','Fictional P8','UTC'); insert into auth.sessions(id,user_id) values('{session}','{actor}');")
        sql(f"select public.challenge_runtime_v1(true,true,true,{actor_array},'2026-10-01T12:00Z');")
        for i in range(10):
            call(i, command(dict(op='confirm_age', confirmed=True)))
            sql(f"select public.challenge_readiness_fixture_v1('{actors[i]}');")
        sql(f"insert into public.friendships(user_a,user_b,requested_by,status) values(least('{actors[0]}'::uuid,'{actors[1]}'::uuid),greatest('{actors[0]}'::uuid,'{actors[1]}'::uuid),'{actors[0]}','accepted');")
        cid = call(0, command(dict(op='create', policy='friend_steps_goal_v1', config=early)))['id']
        mutate(0, cid, 'target', target=100)
        mutate(0, cid, 'invite', username='p8' + actors[1].replace('-', '')[:20])
        mutate(1, cid, 'target', target=100)
        mutate(0, cid, 'select', actor_id=actors[1], selected=True)
        mutate(0, cid, 'freeze')
        digest = sql(f"select digest from app.challenge_agreements_v1 where challenge_id='{cid}'")
        for i in (0, 1):
            mutate(i, cid, 'consent', consent=True, digest=digest)
        sql(f"select public.challenge_runtime_v1(true,true,true,{actor_array},'2026-10-03T12:00Z');")
        for i in (0, 1):
            sql(f"select public.challenge_capture_fixture_v1('{uuid.uuid4()}','{cid}','{actors[i]}',200,'complete');")
        sql(f"select public.challenge_runtime_v1(true,true,true,{actor_array},'2026-10-06T12:00Z'); select public.challenge_process_v1('{cid}');")
        mutate(0, cid, 'review', notice_revision=1, reason='wrong_total')
        # Pause processing to establish that suspension, rather than a later worker,
        # closes admissions synchronously. No admission or authorization guard changes.
        sql(f"select public.challenge_runtime_v1(true,true,false,{actor_array},'2026-10-06T12:00Z');")

        def grant(index, capability):
            return call(None, f"select public.challenge_grant_operator_v1('{actors[index]}','{cid}','{capability}','2026-10-12T12:00Z');", 'service_role')

        def revoke(index, capability):
            return f"select public.challenge_revoke_operator_v1('{actors[index]}','{cid}','{capability}');"

        read = f"select public.challenge_operator_cases_v1('{cid}');"
        grant(2, 'review')
        grant(3, 'moderate')
        control = call(2, read)
        check(isinstance(control, list) and len(control) == 1 and control[0]['context']['fact']['value'] == 200, 'Privacy1 authorized case returns normalized fact 200')
        check(denied(call(3, read), 'challenge_operator_required'), 'Privacy1 moderate-only actor denied review data')
        check(denied(call(2, 'select * from app.challenge_reviews_v1;'), 'permission denied'), 'Privacy1 reviewer cannot read private table directly')

        # Revocation has updated the grant and is still uncommitted.
        for index, capability, query in [(2, 'review', read), (3, 'moderate', f"select public.challenge_operator_reports_v1('{cid}');")]:
            holder = Session(capability + '_revoker', role='service_role')
            holder.send(revoke(index, capability)); holder.receive()
            reader = Session(capability + '_reader', index); reader.send(query)
            check(observe(reader, holder), capability + ' reader waits behind grant revocation')
            holder.commit()
            result = reader.receive(); reader.commit()
            check(denied(result, 'challenge_operator_required'), capability + ' revocation-first returns 42501 without data')
        check(denied(call(2, read), 'challenge_operator_required'), 'Privacy1 committed revocation denies new read')

        # Reader authorization and data query finish before revocation begins.
        grant(2, 'review')
        reader = Session('read_first', 2); reader.send(read)
        check(isinstance(json.loads(reader.receive()), list), 'Privacy1 read-first transaction obtains authorized data')
        revoker = Session('revoke_second', role='service_role'); revoker.send(revoke(2, 'review'))
        waiting = observe(revoker, reader)
        check(waiting, 'Privacy1 read-first holds grant until commit')
        if not waiting:
            revoker.receive(); revoker.commit()
        reader.commit()
        if waiting:
            revoker.receive(); revoker.commit()

        # A table lock is a disposable-only deterministic barrier inside the real
        # RPC, after its guard/audit and before the case SELECT completes. It changes
        # timing only; the uninstrumented controls above exercise the same function.
        grant(2, 'review')
        barrier = Session('case_data_barrier', owner=True)
        barrier.send('lock table app.challenge_reviews_v1 in access exclusive mode;'); barrier.receive()
        reader = Session('case_data_wait', 2); reader.send(read)
        assert observe(reader, barrier)
        revoker = Session('revoke_during_data', role='service_role'); revoker.send(revoke(2, 'review'))
        waiting = observe(revoker, reader)
        check(waiting, 'Privacy1 revocation cannot overtake authorized context read')
        if not waiting:
            # On the baseline, let the real revoke COMMIT while the reader is
            # still held. This proves the missing transaction synchronization,
            # not unauthorized initial access: the reader was authorized first.
            revoker.receive(); revoker.commit()
        barrier.commit()
        result = reader.receive()
        check(not isinstance(result, dict) and json.loads(result)[0]['context']['fact']['value'] == 200, 'Privacy1 authorized in-flight context completes successfully')
        reader.commit()
        if waiting:
            revoker.receive(); revoker.commit()

        call(None, f"select public.challenge_grant_support_v1('{actors[4]}','2026-10-12T12:00Z');", 'service_role')

        def suspend(index, request=None):
            return f"select public.challenge_support_suspend_v1('{request or uuid.uuid4()}','{actors[index]}','unsafe_behavior');"

        # Suspension wins the profile, before the new friend draft is visible.
        request = str(uuid.uuid4())
        holder = Session('suspend_first', 4); holder.send(suspend(5)); holder.receive()
        entrant = Session('friend_wait', 5); entrant.send(command(create, request))
        check(observe(entrant, holder), 'S1 friend creation reaches profile wait behind suspension')
        check(call(9, command(create)).get('status') == 'lobby_open', 'S1 unrelated authorized creator completes during wait')
        holder.commit(); result = entrant.receive(); entrant.commit()
        check(denied(result, 'challenge_admission_paused'), 'S1 suspension-first rejects friend create after profile wait')
        state = value(f"select jsonb_build_object('suspended',(select suspended from app.challenge_suspensions_v1 where actor_id='{actors[5]}'),'drafts',(select count(*) from app.challenge_lobbies_v1 where creator_id='{actors[5]}'),'selected_active',(select count(*) from app.challenge_members_v1 where actor_id='{actors[5]}' and selected and exited_at is null),'requests',(select count(*) from app.challenge_requests_v1 where actor_id='{actors[5]}' and request_id='{request}'),'claims',(select count(*) from app.challenge_work_claims_v1 w join app.challenge_lobbies_v1 l on l.id=w.challenge_id where l.creator_id='{actors[5]}')); ")
        record('suspension_first_final', **state)
        check(state == dict(suspended=True, drafts=0, selected_active=0, requests=0, claims=0), 'S1 denied create has no draft/member/request/claim effects')
        check(denied(call(5, command(create)), 'challenge_admission_paused'), 'S1 nonoverlapping suspended create denied')

        # The existing personal path is the smallest disconfirming comparison.
        preview = call(8, f"select public.challenge_personal_preview_v1('personal_steps_goal_v1',{literal(json.dumps(later))}::jsonb,100);")
        holder = Session('personal_suspend', 4); holder.send(suspend(8)); holder.receive()
        entrant = Session('personal_wait', 8)
        entrant.send(command(dict(op='personal_commit', policy='personal_steps_goal_v1', config=later, target=100, digest=preview['digest'], consent=True)))
        check(observe(entrant, holder), 'S1 personal comparison waits behind suspension')
        holder.commit(); result = entrant.receive(); entrant.commit()
        check(denied(result, 'challenge_admission_paused'), 'S1 personal comparison rejects after wait')

        # Legitimate create-first completion: support must retry its old union,
        # then synchronously close the newly visible draft. Exact retry survives.
        request = str(uuid.uuid4())
        entrant = Session('create_first', 6); entrant.send(command(create, request))
        saved = json.loads(entrant.receive())
        check(saved['status'] == 'lobby_open', 'S1 authorized create-first succeeds')
        holder = Session('suspend_second', 4); holder.send(suspend(6))
        check(observe(holder, entrant), 'S1 suspension waits behind authorized create')
        entrant.commit(); result = holder.receive(); holder.commit()
        check(isinstance(result, dict) and '40001' in result.get('error', '') and 'challenge_retry_safety' in result['error'], 'S1 changed membership union requires explicit suspension retry')
        check(call(4, suspend(6)) == {'saved': True}, 'S1 fresh suspension retry succeeds')
        check(call(6, command(create, request)) == saved, 'S1 exact committed create retry survives suspension')
        detail = call(6, f"select public.challenge_detail_v1('{saved['id']}');")
        check(detail['status'] == 'cancelled', 'S1 suspended owner retains synchronously closed draft read')
        check(denied(call(6, command(create)), 'challenge_admission_paused'), 'S1 subsequent new create denied after successful suspension')
        check(call(7, command(create))['status'] == 'lobby_open', 'S1 nonoverlapping eligible create succeeds')
    except Exception as error:
        failure = str(error)
        raise
    finally:
        for process in processes:
            if process.poll() is None:
                process.kill()
            process.communicate(timeout=5)
        sql("select public.challenge_runtime_v1(false,false,false,'{}',null);")
        args.output.write_text(json.dumps(dict(checks=checks, passed=sum(c['pass_'] for c in checks), failed=sum(not c['pass_'] for c in checks), skipped=0, infrastructure_error=failure, events=events), indent=2) + '\n')
    raise SystemExit(1 if any(not c['pass_'] for c in checks) else 0)


if __name__ == '__main__':
    main()
