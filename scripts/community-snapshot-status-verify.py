#!/usr/bin/env python3
"""Verify snapshot status on a new disposable local stack, then remove that stack.

Copies only config, migrations and SQL tests; never inherits linkage or secrets.
No reset, hosted target, scheduler, alert, or existing project is used.
Logs stay in the printed temporary directory; local credentials remain private.
"""
from http.client import HTTPConnection
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
RPC = 'challenge_community_snapshot_status_v1'
KEYS = set(('server_time capture_authorization snapshot_age_clock snapshot_clock_now '
            'capture_status last_capture_at capture_age_seconds pending_invocation_prepared_at '
            'last_attempt_at last_attempt_status last_attempt_error_code last_successful_invocation_at').split())


def main():
    os.umask(0o077)
    base = int(os.environ.get('SNAPSHOT_VERIFY_PORT_BASE', '58340'))
    assert 10240 <= base <= 65520
    for port in range(base, base + 10):
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', port))
    target = Path(tempfile.mkdtemp(prefix='gametime-snapshot-status-'))
    print(f'Owned verification directory: {target}', flush=True)
    project = target.name
    (target / 'supabase').mkdir()
    for name in ('migrations', 'tests'):
        shutil.copytree(ROOT / 'supabase' / name, target / 'supabase' / name)
    config = (ROOT / 'supabase/config.toml').read_text()
    config = re.sub(r'^project_id\s*=.*$', f'project_id = "{project}"', config, count=1, flags=re.M)
    for old, offset in ((54320, 0), (54321, 1), (54322, 2), (54323, 3), (54324, 4), (54329, 9)):
        config = config.replace(str(old), str(base + offset))
    config = config.replace('sql_paths = ["./seed.sql"]', 'sql_paths = []')
    config = config.replace('[auth.external.apple]\nenabled = true', '[auth.external.apple]\nenabled = false')
    # Fictional local password login only; admin creation confirms without email.
    config = re.sub(r'(\[auth.email\][\s\S]*?enable_signup = )false', r'\g<1>true', config, count=1)
    (target / 'supabase/config.toml').write_text(config)
    env = dict(os.environ, DO_NOT_TRACK='1')
    # Local stack commands have no reason to inherit hosted or provider credentials.
    for key in list(env):
        if key.startswith(('SUPABASE_', 'STRIPE_', 'OPENAI_')):
            env.pop(key)
    checks = []
    network = project + '-network'
    networks = subprocess.check_output(['docker', 'network', 'ls', '-q'], text=True).split()
    inventory = json.loads(subprocess.check_output(['docker', 'network', 'inspect', *networks], text=True))
    used = [ipaddress.ip_network(c['Subnet']) for n in inventory for c in (n.get('IPAM', {}).get('Config') or []) if c.get('Subnet')]
    subnet = next((ipaddress.ip_network(f'10.247.{i}.0/24') for i in range(256)
                   if not any(ipaddress.ip_network(f'10.247.{i}.0/24').overlaps(n) for n in used if n.version == 4)), None)
    if subnet is None:
        raise RuntimeError('No unused disposable test subnet')

    def check(condition, label):
        if not condition:
            raise AssertionError(label)
        checks.append(label)
        print('PASS: ' + label, flush=True)

    def command(args, log):
        result = subprocess.run(args, env=env, cwd=target, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, timeout=600)
        output = result.stdout
        if log == 'start.log':
            output = '\n'.join('[redacted local connection setting]' if re.search(
                r'key|secret|token|password|postgresql://', line, re.I) else line for line in output.splitlines()) + '\n'
        (target / log).write_text(output)
        result.check_returncode()

    def sql(statement):
        result = subprocess.run(['docker', 'exec', '-i', 'supabase_db_' + project,
                                 'psql', '-XqAt', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'],
                                input=statement, text=True, capture_output=True, check=False)
        if result.returncode:
            (target / 'sql-error.log').write_text(result.stderr)
            raise AssertionError('SQL failed; inspect private sql-error.log')
        return result.stdout.strip()

    def digest():
        return sql((ROOT / 'supabase/tests/fixtures/community-status-digest.inc').read_text()
                   + '\nselect pg_temp.data_digest();')

    subprocess.run(['docker', 'network', 'create', '--subnet', str(subnet),
                    '--label', 'gametime.snapshot-status.owner=' + project,
                    '--opt', 'com.docker.network.bridge.host_binding_ipv4=127.0.0.1', network],
                   check=True, capture_output=True)
    try:
        command(['supabase', 'start', '--workdir', str(target), '--network-id', network, '-x',
                 'edge-runtime,studio,imgproxy,mailpit,storage-api,vector,postgres-meta,realtime,logflare'], 'start.log')
        # Historical migration jobs are outside this test; no job may run while
        # fixtures exist. Disable only on the newly owned empty local project.
        sql('select cron.alter_job(jobid, active:=false) from cron.job;')
        command(['supabase', 'test', 'db', '--local', '--workdir', str(target), '--network-id', network,
                 'supabase/tests/508_challenge_community_progress.test.sql',
                 'supabase/tests/509_challenge_local_worker_recovery.test.sql',
                 'supabase/tests/515_challenge_community_snapshot_status.test.sql'], 'sql-tests.log')
        print((target / 'sql-tests.log').read_text()[-1800:], flush=True)
        result = subprocess.run(['supabase', 'status', '--workdir', str(target), '-o', 'json'], env=env,
                                capture_output=True, text=True, check=True)
        keys = json.loads(result.stdout)
        # Never print or persist keys in evidence.
        service, anon = keys['SERVICE_ROLE_KEY'], keys['ANON_KEY']

        def http(method, path, body, token, expected):
            conn = HTTPConnection('127.0.0.1', base + 1, timeout=15)
            headers = {'apikey': anon, 'Content-Type': 'application/json'}
            if token:
                headers['Authorization'] = 'Bearer ' + token
            try:
                conn.request(method, path, json.dumps(body) if body is not None else None, headers)
                response = conn.getresponse()
                raw = response.read()
                assert response.status == expected, (path.split('?')[0], response.status, expected)
                return json.loads(raw) if raw else None
            finally:
                conn.close()

        def rpc(name, body, expected=200):
            return http('POST', '/rest/v1/rpc/' + name, body, service, expected)

        fixture = (ROOT / 'supabase/tests/fixtures/challenge-fixture.inc').read_text()
        cohort = sql('begin;\n' + fixture + """
insert into beta_ids values('community',public.challenge_publish_community_fixture_v1(pg_temp.br(93000),pg_temp.ba(40),'{"start_date":"2026-10-03","days":1,"timezone":"UTC","amount_cents":100}',100,2,250,true));
select public.challenge_discovery_fixture_v1(true);
do $$declare i integer; c uuid:=(select id from beta_ids where name='community');begin
 for i in 1..4 loop
  perform pg_temp.login_beta(i);
  perform public.challenge_join_community_v1(pg_temp.br(93100+i),jsonb_build_object('op','join_community','id',c,'digest',public.challenge_community_catalog_v1()->0->>'digest','consent',true));
 end loop;
 perform set_config('role','none',true);
end $$;
select id from beta_ids where name='community';
commit;
""").splitlines()[-1]
        uuid.UUID(cohort)

        def observe(method='POST'):
            before = digest()
            if method == 'GET':
                value = http('GET', '/rest/v1/rpc/' + RPC + '?p_id=' + cohort, None, service, 200)
            else:
                value = rpc(RPC, {'p_id': cohort})
            check(digest() == before, 'HTTP status read leaves every application/Auth row and sequence unchanged')
            check(set(value) == KEYS, 'HTTP response contains only allowlisted timestamp, age and bounded code fields')
            return value

        def clock(value):
            sql("select public.challenge_runtime_v1(false,true,false,array(select id from public.profiles where id::text like 'bf000000-%')," + ("'" + value + "'" if value else 'null') + ');')

        def dispatch():
            inv = str(uuid.uuid4())
            rpc('challenge_prepare_community_snapshot_invocation_v1', {'p_invocation_id': inv, 'p_id': cohort})
            rpc('challenge_dispatch_community_snapshot_invocation_v1', {'p_invocation_id': inv})
            return inv

        value = observe()
        check(value['capture_status'] == 'missing' and value['last_attempt_status'] == 'none', 'HTTP missing capture and attempt')
        dispatch()
        first = observe('GET')
        check(first['capture_age_seconds'] == 0 and first['snapshot_age_clock'] == 'fixture', 'HTTP first capture uses the explicit fixture clock')
        check(first['last_attempt_status'] == 'checked', 'HTTP first invocation is checked')
        clock('2026-10-01T12:01:00Z')
        inv = dispatch()
        throttled = observe()
        check(throttled['last_capture_at'] == first['last_capture_at'] and throttled['capture_age_seconds'] == 60, 'HTTP throttling does not refresh capture')
        check(throttled['last_successful_invocation_at'] > first['last_successful_invocation_at'], 'HTTP throttling advances only invocation time')
        clock('2026-10-01T14:00:00Z')
        rpc('challenge_dispatch_community_snapshot_invocation_v1', {'p_invocation_id': inv})
        stale = observe()
        check(stale['capture_age_seconds'] == 7200 and stale['last_attempt_at'] == throttled['last_attempt_at'], 'HTTP replay preserves stale capture and original attempt')
        check(stale['capture_authorization'] == 'enabled', 'HTTP paused processing and admission still allow capture')
        # Error injection exists only in this disposable DB and contains a leak sentinel.
        sql("""create function app.snapshot_test_fail() returns trigger language plpgsql as $$begin raise exception 'PRIVATE_HEALTH_RAW_RESPONSE' using errcode='23514';end $$;
create trigger snapshot_test_fail before insert on app.challenge_community_snapshots_v1 for each row execute function app.snapshot_test_fail();""")
        dispatch()
        failed = observe()
        check(failed['last_attempt_status'] == 'failed' and failed['last_attempt_error_code'] == '23514'
              and failed['last_successful_invocation_at'] == throttled['last_successful_invocation_at']
              and failed['capture_age_seconds'] == 7200, 'HTTP failure preserves capture age and prior success with SQLSTATE only')
        check('PRIVATE_HEALTH' not in json.dumps(failed), 'HTTP raw failure stays private')
        sql('drop trigger snapshot_test_fail on app.challenge_community_snapshots_v1; drop function app.snapshot_test_fail();')
        rpc('challenge_discovery_fixture_v1', {'p_enabled': False}, 204)
        dispatch()
        disabled = observe()
        check(disabled['capture_authorization'] == 'discovery_disabled' and disabled['last_attempt_status'] == 'disabled', 'HTTP disabled discovery is visible')
        check(sql(f"select joined is null from app.challenge_community_snapshots_v1 where challenge_id='{cohort}';") == 't', 'HTTP under-five capture never stores a count')
        clock(None)
        ahead = observe()
        check(ahead['snapshot_age_clock'] == 'server', 'HTTP current server clock is labeled separately')
        clock('2026-10-01T11:59:00Z')
        ahead = observe()
        check(ahead['snapshot_age_clock'] == 'fixture' and ahead['capture_status'] == 'ahead_of_clock'
              and ahead['capture_age_seconds'] is None, 'HTTP fixture clock rewind is not zero age')
        sql('alter table app.challenge_runtime_v1 disable trigger challenge_guard; delete from app.challenge_runtime_v1; alter table app.challenge_runtime_v1 enable trigger challenge_guard;')
        unavailable = observe()
        check(unavailable['capture_authorization'] == 'runtime_unavailable' and unavailable['capture_age_seconds'] is None
              and unavailable['last_capture_at'] == first['last_capture_at'], 'HTTP missing runtime retains capture and unknown age')
        before_denials = digest()
        for token in (None, anon):
            denied = http('POST', '/rest/v1/rpc/' + RPC, {'p_id': cohort}, token, 401)
            check(denied['code'] == '42501', 'HTTP anonymous caller denied')
        check(digest() == before_denials, 'HTTP anonymous denials leave existing data unchanged')
        # Actual local Auth user/token, rather than a forged authenticated JWT.
        password = uuid.uuid4().hex + 'Aa1!'
        email = uuid.uuid4().hex + '@example.test'
        http('POST', '/auth/v1/admin/users', {'email': email, 'password': password, 'email_confirm': True}, service, 200)
        session = http('POST', '/auth/v1/token?grant_type=password', {'email': email, 'password': password}, anon, 200)
        before_denials = digest()
        denied = http('POST', '/rest/v1/rpc/' + RPC, {'p_id': cohort}, session['access_token'], 403)
        check(denied['code'] == '42501' and digest() == before_denials, 'HTTP authenticated caller denied without data changes')
        check(http('POST', '/rest/v1/rpc/' + RPC, {'p_id': None}, service, 400)['code'] == '22023', 'HTTP null selection denied')
        check(http('POST', '/rest/v1/rpc/' + RPC, {'p_id': str(uuid.uuid4())}, service, 403)['code'] == '42501', 'HTTP unpublished selection unavailable')
        # Stable projection also works in an actual read-only database transaction.
        check(sql(f"begin read only; set local role service_role; select public.{RPC}('{cohort}')->>'capture_authorization'; commit;") == 'runtime_unavailable', 'service projection works in read-only transaction')
        (target / 'sanitized-example.json').write_text(json.dumps(stale, indent=2) + '\n')
        (target / 'http-checks.json').write_text(json.dumps({'checks': checks, 'passed': len(checks)}, indent=2) + '\n')
        print(f'HTTP checks passed: {len(checks)}', flush=True)
    finally:
        command(['supabase', 'stop', '--workdir', str(target), '--no-backup'], 'stop.log')
        remaining = json.loads(subprocess.check_output(['docker', 'network', 'inspect', network], text=True))[0]
        assert remaining['Labels']['gametime.snapshot-status.owner'] == project and not remaining['Containers']
        subprocess.run(['docker', 'network', 'rm', network], check=True, capture_output=True)
        print(f'Owned disposable stack removed. Logs: {target}', flush=True)


if __name__ == '__main__':
    main()
