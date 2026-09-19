#!/usr/bin/env python3
"""Focused session-lock regressions on an explicitly owned disposable local DB.

Fictional SQL-role actors exercise actual RPCs, not HTTP or physical activity.
Retains fictional history; revokes only sessions minted by this invocation.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import time
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--owned-project', required=True)
    parser.add_argument('--stack', type=Path, required=True)
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    config = (args.stack / 'supabase/config.toml').read_text()
    assert args.owned_project == 'gametime-p11a-operator-suspension-20260919', 'Only this explicitly owned disposable lab'
    assert re.search(r'^project_id\s*=\s*"' + re.escape(args.owned_project) + r'"$', config, re.M)
    db_section = config.split('[db]', 1)[1].split('\n[', 1)[0]
    assert re.search(r'^port\s*=\s*' + str(args.port) + r'\s*$', db_section, re.M)
    assert 10240 <= args.port <= 65535
    assert args.port not in {54322, 56322, 57322, 58322, 59322, 60322, 61322, 62322}, 'Retained DBs are never regression targets'
    assert not args.report.exists(), 'Never overwrite an earlier result'
    spec = importlib.util.spec_from_file_location('session_regression_support', '/private/tmp/gametime-suspended-account-access/scripts/beta-concurrency.py')
    support = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(support)
    support.DB = f'postgresql://postgres@127.0.0.1:{args.port}/postgres'
    assert support.value('select not admission and not fixtures and not processing and cardinality(actors)=0 from app.challenge_runtime_v1 where singleton;') == 't'
    records, exits, sessions = [], [], []

    def sql(query, check=True):
        result = support.sql(query, False)
        exits.append({'command': ['psql', 'owned loopback database', '-XqAt', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=sqlstate'], 'exit_code': result.returncode})
        if check and result.returncode:
            raise RuntimeError('Regression setup query failed: ' + result.stderr)
        return result

    def value(query):
        return sql(query).stdout.strip()

    actor, initial, request = [str(uuid.uuid4()) for _ in range(3)]
    sessions.append(initial)
    payload = {'op': 'create', 'config': {'start_date': '2026-10-03', 'days': 1, 'timezone': 'UTC', 'amount_cents': 100}}
    try:
        sql(f"insert into auth.users(id) values('{actor}'); insert into public.profiles(id,handle,display_name,timezone) values('{actor}','expiry_{uuid.uuid4().hex[:12]}','Fictional session regression','UTC'); insert into auth.sessions(id,user_id) values('{initial}','{actor}');")
        sql(f"select public.challenge_runtime_v1(true,true,true,array['{actor}'::uuid],'2026-10-01T00:00Z'); select public.challenge_readiness_fixture_v1('{actor}');")
        sql(support.auth(actor, initial, f"select public.challenge_confirm_age_v1('{uuid.uuid4()}',true)"))
        command = f"select public.challenge_command_v1('{request}',{support.literal(json.dumps(payload))}::jsonb)"
        receipt = json.loads(value(support.auth(actor, initial, command)).splitlines()[-1])
        challenge = receipt['id']
        sql(f"begin; select set_config('app.challenge_write_v1','on',true); insert into app.challenge_suspensions_v1 values('{actor}',true,'{uuid.uuid4()}','username',clock_timestamp()); commit;")
        # Paused admission is deliberate: exact committed-request recovery must
        # still authenticate without changing the saved agreement or request.
        sql("select public.challenge_discovery_fixture_v1(false); select public.challenge_runtime_v1(false,false,false,'{}',null);")
        for endpoint in ['detail', 'exact_recovery']:
            for mode in ['live', 'already_expired', 'wait_expired', 'wait_live', 'deletion_wins', 'missing']:
                session = str(uuid.uuid4()); sessions.append(session)
                if mode != 'missing':
                    seconds = -1 if mode == 'already_expired' else 3 if mode == 'wait_expired' else 60
                    sql(f"insert into auth.sessions(id,user_id,not_after) values('{session}','{actor}',clock_timestamp()+interval '{seconds} seconds');")
                inner = f"select public.challenge_detail_v1('{challenge}')" if endpoint == 'detail' else command
                query = support.auth(actor, session, inner)
                waiting, unchanged, expired = False, None, None
                if mode in ['wait_expired', 'wait_live', 'deletion_wins']:
                    before = value(f"select jsonb_build_object('xmin',xmin::text,'not_after',not_after) from auth.sessions where id='{session}';")
                    hold = support.Held(f"select 1 from auth.sessions where id='{session}' for update")
                    name = 'gametime_d9_session_' + uuid.uuid4().hex
                    child = support.contender(query, name)
                    try:
                        waiting = support.blocked([name])
                        assert waiting, 'Must observe a real session lock wait'
                        if mode == 'wait_expired':
                            deadline = time.monotonic() + 10
                            while value(f"select clock_timestamp()>=not_after from auth.sessions where id='{session}';") != 't':
                                assert time.monotonic() < deadline
                                time.sleep(0.05)
                            expired = True
                    finally:
                        hold.release(f"delete from auth.sessions where id='{session}'" if mode == 'deletion_wins' else '')
                        exits.append({'command': 'psql held-session transaction', 'exit_code': hold.process.returncode})
                    stdout, stderr = child.communicate(timeout=15)
                    code = child.returncode
                    exits.append({'command': 'psql waiting ' + endpoint + ' ' + mode, 'exit_code': code})
                    if mode != 'deletion_wins':
                        unchanged = before == value(f"select jsonb_build_object('xmin',xmin::text,'not_after',not_after) from auth.sessions where id='{session}';")
                        assert unchanged, 'Elapsed-expiry test must release an unchanged row'
                else:
                    result = sql(query, False)
                    stdout, stderr, code = result.stdout, result.stderr, result.returncode
                expected_success = mode in ['live', 'wait_live']
                returned = json.loads(stdout.strip().splitlines()[-1]) if code == 0 else None
                response_matches = returned == receipt if endpoint == 'exact_recovery' else isinstance(returned, dict) and returned.get('id') == challenge
                passed = code == 0 and response_matches if expected_success else code != 0 and '42501' in stderr
                record = {'endpoint': endpoint, 'mode': mode, 'expected': 'same authorized response' if expected_success else '42501', 'exit_code': code, 'passed': passed, 'actual_lock_wait': waiting, 'session_row_unchanged': unchanged, 'expiry_observed_before_release': expired}
                records.append(record)
                print(('PASS ' if passed else 'FAIL ') + endpoint + ': ' + mode, flush=True)
        assert value(f"select count(*) from app.challenge_requests_v1 where actor_id='{actor}' and request_id='{request}';") == '1'
    finally:
        sql("select public.challenge_discovery_fixture_v1(false); select public.challenge_runtime_v1(false,false,false,'{}',null);")
        sql('delete from auth.sessions where user_id=' + support.literal(actor) + ' and id in (' + ','.join(map(support.literal, sessions)) + ');')
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps({'evidence': 'Actual PostgreSQL RPCs and concurrent row locks; fictional SQL-role actor; no HTTP or physical-device acceptance', 'owned_project': args.owned_project, 'port': args.port, 'records': records, 'command_exits': exits, 'passed': sum(r['passed'] for r in records), 'failed': sum(not r['passed'] for r in records), 'cleanup': 'All challenge gates disabled, only newly minted actor sessions revoked; fictional history retained'}, indent=2) + '\n')
    assert len(records) == 12 and all(r['passed'] for r in records), 'Session lock regression failed; retained report has exact outcomes'


if __name__ == '__main__':
    main()
