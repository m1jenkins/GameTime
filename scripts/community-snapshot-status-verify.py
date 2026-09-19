#!/usr/bin/env python3
"""Focused SQL/HTTP verification on a newly created, owned disposable stack.

Uses cached Supabase Postgres/Auth/PostgREST images; never reads project secrets,
uses a retained database, or contacts a hosted target. All runtime actors and
signed JWTs are fictional. Postgres and PostgREST publish only on numeric loopback.
"""
import argparse
import base64
import hashlib
import hmac
import http.client
import json
import ipaddress
import os
from pathlib import Path
import re
import secrets
import socket
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
DB_IMAGE = 'public.ecr.aws/supabase/postgres:17.6.1.143'
AUTH_IMAGE = 'public.ecr.aws/supabase/gotrue:v2.192.0'
REST_IMAGE = 'public.ecr.aws/supabase/postgrest:v14.14'
RPC = 'challenge_community_snapshot_status_v1'
KEYS = {'observed_wall_at', 'reference_clock', 'snapshot_reference_at',
        'capture_state', 'snapshot_state', 'last_capture_at', 'capture_age_seconds',
        'last_prepared_wall_at', 'last_attempt_wall_at', 'last_attempt_state',
        'last_attempt_error_code', 'last_successful_invocation_wall_at'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence-dir', type=Path, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    args.evidence_dir.mkdir(parents=True, exist_ok=False)
    owner = 'gametime-snapshot-status-' + uuid.uuid4().hex[:12]
    db, rest, auth = [owner + suffix for suffix in ('-db', '-rest', '-auth')]
    owned = []
    checks = []
    secret, password = secrets.token_hex(32), secrets.token_hex(24)
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        db_port = sock.getsockname()[1]
    if port == db_port:
        raise RuntimeError('Port allocation collision; retry the verification')
    env = dict(os.environ, DO_NOT_TRACK='1', POSTGRES_PASSWORD=password, PGPASSWORD=password, GOTRUE_JWT_SECRET=secret,
               GOTRUE_DB_DRIVER='postgres', GOTRUE_DB_DATABASE_URL=f'postgres://supabase_auth_admin:{password}@{db}:5432/postgres',
               GOTRUE_SITE_URL='http://127.0.0.1', API_EXTERNAL_URL='http://127.0.0.1',
               PGRST_DB_URI=f'postgres://authenticator:{password}@{db}:5432/postgres',
               PGRST_JWT_SECRET=secret, PGRST_DB_SCHEMAS='public', PGRST_DB_ANON_ROLE='anon')

    def command(argv, *, source=None, label=None, check=True):
        result = subprocess.run(argv, input=source, text=True, capture_output=True, env=env, timeout=120)
        if label:
            # These private receipts may contain fixture data; only summary/example
            # files are intended for publication. Never print environment/secrets.
            (args.evidence_dir / label).write_text(result.stdout + result.stderr)
        if check and result.returncode:
            (args.evidence_dir / 'last-command-failure.log').write_text(result.stdout + result.stderr)
            raise RuntimeError('Local command failed; inspect private receipt: ' + str(label or argv[0]))
        return result

    def sql(source, label=None):
        return command(['docker', 'exec', '-i', db, 'psql', '-XqAt', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'], source=source, label=label).stdout.strip()

    def check(condition, label):
        if not condition:
            raise AssertionError(label)
        checks.append(label)
        print('PASS: ' + label, flush=True)

    def token(role):
        def b64(data):
            return base64.urlsafe_b64encode(data).rstrip(b'=').decode()
        payload = {'role': role, 'exp': int(time.time()) + 3600}
        if role == 'authenticated':
            payload.update(sub='bf000000-0000-0000-0000-000000000001', session_id='ba000000-0000-0000-0000-000000000001')
        body = b64(b'{"alg":"HS256","typ":"JWT"}') + '.' + b64(json.dumps(payload).encode())
        return body + '.' + b64(hmac.new(secret.encode(), body.encode(), hashlib.sha256).digest())

    def request(name, body, role='service_role', method='POST', expected=200):
        conn = http.client.HTTPConnection('127.0.0.1', port, timeout=10)
        headers = {'Content-Type': 'application/json'}
        if role is not None:
            headers['Authorization'] = 'Bearer ' + token(role)
        path = '/rpc/' + name
        if method == 'GET':
            path += '?p_id=' + body['p_id']
        try:
            conn.request(method, path, None if method == 'GET' else json.dumps(body), headers)
            response = conn.getresponse()
            raw = response.read()
            if response.status != expected:
                raise AssertionError(f'{name}: HTTP {response.status}, expected {expected}')
            return json.loads(raw) if raw else None
        finally:
            conn.close()

    def digest():
        return sql("""do $$declare t record; d text; begin
 create temp table content_digest(name text, digest text);
 for t in select schemaname,tablename from pg_tables where schemaname in ('app','public','auth') order by 1,2 loop
 execute format('select md5(coalesce(string_agg(row_to_json(r)::text,'''' order by row_to_json(r)::text),'''')) from %I.%I r',t.schemaname,t.tablename) into d;
 insert into content_digest values(t.schemaname||'.'||t.tablename,d);
 end loop; end$$;
 select md5(string_agg(name||digest,'' order by name)) from content_digest;""")

    try:
        for image in [DB_IMAGE, AUTH_IMAGE, REST_IMAGE]:
            command(['docker', 'image', 'inspect', image])
        network_ids = command(['docker', 'network', 'ls', '-q']).stdout.split()
        networks = json.loads(command(['docker', 'network', 'inspect', *network_ids]).stdout)
        occupied = [ipaddress.ip_network(c['Subnet']) for n in networks for c in (n.get('IPAM', {}).get('Config') or []) if c.get('Subnet') and ':' not in c['Subnet']]
        subnet = next(str(candidate) for candidate in ipaddress.ip_network('10.252.0.0/16').subnets(new_prefix=24) if not any(candidate.overlaps(n) for n in occupied))
        command(['docker', 'network', 'create', '--subnet', subnet, '--label', 'owner=' + owner, owner])
        owned.append(('network', owner))
        owned.append(('container', db))
        command(['docker', 'run', '-d', '--name', db, '--label', 'owner=' + owner,
                 '--network', owner, '-p', f'127.0.0.1:{db_port}:5432', '-e', 'POSTGRES_PASSWORD', DB_IMAGE,
                 'postgres', '-D', '/etc/postgresql', '-c', 'cron.launch_active_jobs=off',
                 '-c', 'cron.database_name=postgres', '-c', 'listen_addresses=*'], label='db-start.log')
        ready = False
        for _ in range(60):
            probe = command(['docker', 'exec', '-e', 'PGPASSWORD', db, 'psql', '-h', '127.0.0.1', '-XAt', '-U', 'postgres', '-d', 'postgres',
                             '-c', "select to_regclass('auth.users') is not null"], check=False)
            if probe.returncode == 0 and probe.stdout.strip() == 't':
                ready = True
                break
            time.sleep(0.5)
        check(ready, 'owned database initialized')
        db_info = json.loads(command(['docker', 'inspect', db]).stdout)[0]
        check(db_info['HostConfig']['PortBindings'] == {'5432/tcp': [{'HostIp': '127.0.0.1', 'HostPort': str(db_port)}]}, 'database bound only to numeric loopback')
        # Bootstrap creates roles but leaves service passwords to the operator.
        command(['docker', 'exec', '-i', db, 'psql', '-XqAt', '-v', 'ON_ERROR_STOP=1', '-U', 'supabase_admin', '-d', 'postgres'], source=f"alter role supabase_auth_admin password '{password}'; alter role authenticator password '{password}';")
        owned.append(('container', auth))
        command(['docker', 'run', '--name', auth, '--label', 'owner=' + owner, '--network', owner,
                 '-e', 'GOTRUE_JWT_SECRET', '-e', 'GOTRUE_DB_DRIVER', '-e', 'GOTRUE_DB_DATABASE_URL',
                 '-e', 'GOTRUE_SITE_URL', '-e', 'API_EXTERNAL_URL', AUTH_IMAGE, 'auth', 'migrate'], label='auth-migrate.log')
        migrations = sorted((ROOT / 'supabase/migrations').glob('*.sql'))
        manifest = []
        for migration in migrations:
            sql('begin;\n' + migration.read_text() + '\ncommit;', label=migration.name + '.log')
            manifest.append({'path': str(migration.relative_to(ROOT)), 'sha256': hashlib.sha256(migration.read_bytes()).hexdigest()})
        advisor = command(['supabase', 'db', 'advisors', '--db-url', f'postgresql://postgres:{password}@127.0.0.1:{db_port}/postgres?sslmode=disable', '--type', 'security', '--level', 'warn', '--fail-on', 'error'], label='security-advisor.log', check=False)
        check(advisor.returncode == 0, 'explicit-loopback security advisor passed')
        check(sql("show cron.launch_active_jobs") == 'off', 'historical cron disabled from first database start')
        check(sql('select count(*) from cron.job_run_details') == '0', 'no cron execution')
        sql('create extension if not exists pgtap with schema extensions; create extension if not exists dblink with schema extensions;')
        command(['docker', 'cp', str(ROOT / 'supabase/tests'), db + ':/tmp/tests'])
        tap_counts = {}
        for name in ['494_challenge_safety', '506_challenge_private_community', '507_challenge_community_guards',
                     '508_challenge_community_progress', '509_challenge_local_worker_recovery',
                     '518_challenge_community_snapshot_status']:
            result = command(['docker', 'exec', db, 'psql', '-XqAt', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres', '-f', '/tmp/tests/' + name + '.test.sql'], label=name + '.tap')
            assertions = re.findall(r'^(?:not )?ok (\d+)\b', result.stdout, re.M)
            plan = re.findall(r'^1\.\.(\d+)$', result.stdout, re.M)
            check(len(plan) == 1 and list(map(int, assertions)) == list(range(1, int(plan[-1]) + 1))
                  and not re.search(r'^not ok|#\s*(?:SKIP|TODO)|ERROR:', result.stdout + result.stderr, re.M | re.I), name + ' pgTAP passed')
            tap_counts[name] = int(plan[-1])
        # Supported SQL fixtures commit only in this new disposable database.
        fixture = (ROOT / 'supabase/tests/fixtures/challenge-fixture.inc').read_text()
        sql('begin;\n' + fixture + """
 select public.challenge_publish_community_fixture_v1(pg_temp.br(80900),pg_temp.ba(40),
 '{"start_date":"2026-10-03","days":1,"timezone":"UTC","amount_cents":100}',100,2,250,true);
 select public.challenge_discovery_fixture_v1(true);
 do $$declare n integer; c uuid:=(select challenge_id from app.challenge_community_publications_v1);begin
 for n in 1..4 loop
 perform pg_temp.login_beta(n);
 perform public.challenge_join_community_v1(pg_temp.br(80910+n),jsonb_build_object('op','join_community','id',c,'digest',public.challenge_community_catalog_v1()->0->>'digest','consent',true));
 end loop; perform set_config('role','none',true);end$$;
 commit;
 """, label='http-fixtures.log')
        cid = sql('select challenge_id from app.challenge_community_publications_v1')
        owned.append(('container', rest))
        command(['docker', 'run', '-d', '--name', rest, '--label', 'owner=' + owner, '--network', owner,
                 '-p', f'127.0.0.1:{port}:3000', '-e', 'PGRST_DB_URI', '-e', 'PGRST_JWT_SECRET',
                 '-e', 'PGRST_DB_SCHEMAS', '-e', 'PGRST_DB_ANON_ROLE', REST_IMAGE], label='rest-start.log')
        info = json.loads(command(['docker', 'inspect', rest]).stdout)[0]
        check(info['HostConfig']['PortBindings'] == {'3000/tcp': [{'HostIp': '127.0.0.1', 'HostPort': str(port)}]}, 'HTTP bound only to numeric loopback')
        for i in range(30):
            try:
                request(RPC, {'p_id': cid})
                break
            except (OSError, AssertionError):
                if i == 29:
                    raise
                time.sleep(0.2)

        def status():
            before = digest()
            value = request(RPC, {'p_id': cid})
            check(set(value) == KEYS, 'HTTP exact privacy allowlist')
            check(digest() == before, 'HTTP read leaves all app/public/auth rows unchanged')
            return value

        missing = status()
        check(missing['snapshot_state'] == 'missing' and missing['last_attempt_state'] == 'none', 'HTTP missing capture and attempt')
        before = digest()
        for role, code in [(None, 401), ('anon', 401), ('authenticated', 403)]:
            request(RPC, {'p_id': cid}, role=role, expected=code)
        check(digest() == before, 'HTTP unauthorized calls denied without row changes')
        request(RPC, {'p_id': None}, expected=400)
        check(request(RPC, {'p_id': str(uuid.uuid4())})['capture_state'] == 'cohort_unavailable', 'HTTP unknown cohort unavailable')

        def invoke():
            invocation = str(uuid.uuid4())
            request('challenge_prepare_community_snapshot_invocation_v1', {'p_invocation_id': invocation, 'p_id': cid})
            request('challenge_dispatch_community_snapshot_invocation_v1', {'p_invocation_id': invocation})
            return invocation

        invocation = invoke()
        first = status()
        check(first['capture_age_seconds'] == 0 and first['reference_clock'] == 'fixture'
              and first['last_attempt_state'] == 'checked', 'HTTP first actual capture')
        check(sql(f"select joined is null from app.challenge_community_snapshots_v1 where challenge_id='{cid}'") == 't', 'four-member capture retains null count')
        sql("select public.challenge_runtime_v1(false,true,false,array(select id from public.profiles where id::text like 'bf000000-%'),'2026-10-01T14:00Z')")
        request('challenge_dispatch_community_snapshot_invocation_v1', {'p_invocation_id': invocation})
        stale = status()
        check(stale['capture_age_seconds'] == 7200 and stale['last_capture_at'] == first['last_capture_at']
              and stale['last_attempt_wall_at'] == first['last_attempt_wall_at'], 'HTTP delayed replay leaves stale capture and attempt unchanged')
        (args.evidence_dir / 'sanitized-example.json').write_text(json.dumps(stale, indent=2) + '\n')
        sql("select public.challenge_runtime_v1(false,true,false,array(select id from public.profiles where id::text like 'bf000000-%'),'2026-10-01T12:14:59Z')")
        invoke()
        throttled = status()
        check(throttled['capture_age_seconds'] == 899 and throttled['last_capture_at'] == first['last_capture_at']
              and throttled['last_successful_invocation_wall_at'] != first['last_successful_invocation_wall_at'], 'HTTP throttle success does not refresh capture')
        check(throttled['capture_state'] == 'enabled', 'HTTP capture authorization independent of processing and admission')
        sql("""create function app.snapshot_test_failure() returns trigger language plpgsql as $$begin raise exception 'raw secret must not escape' using errcode='23514'; end$$;
 create trigger snapshot_test_failure before insert on app.challenge_community_snapshots_v1 for each row execute function app.snapshot_test_failure();
 select public.challenge_runtime_v1(false,true,false,array(select id from public.profiles where id::text like 'bf000000-%'),'2026-10-01T14:00Z');""")
        invoke()
        failed = status()
        check(failed['last_attempt_state'] == 'failed' and failed['last_attempt_error_code'] == '23514'
              and failed['capture_age_seconds'] == 7200 and failed['last_successful_invocation_wall_at'] == throttled['last_successful_invocation_wall_at'], 'HTTP failure preserves capture and successful invocation')
        sql('drop trigger snapshot_test_failure on app.challenge_community_snapshots_v1; drop function app.snapshot_test_failure(); select public.challenge_discovery_fixture_v1(false);')
        check(status()['capture_state'] == 'discovery_disabled', 'HTTP discovery disabled')
        invoke()
        check(status()['last_attempt_error_code'] == '42501', 'HTTP disabled dispatch has bounded failure')
        sql("select public.challenge_runtime_v1(false,true,false,'{}','2026-10-01T11:00Z')")
        reversed_clock = status()
        check(reversed_clock['snapshot_state'] == 'clock_ahead' and reversed_clock['capture_age_seconds'] is None, 'HTTP backward fixture clock cannot produce fresh zero')
        sql('select public.challenge_runtime_v1(false,false,false,\'{}\',null);')
        disabled = status()
        check(disabled['capture_state'] == 'fixtures_disabled' and disabled['reference_clock'] == 'wall'
              and disabled['snapshot_reference_at'] == disabled['observed_wall_at']
              and disabled['last_capture_at'] == first['last_capture_at'], 'HTTP disabled fixtures preserve capture and explicitly switch reference clock')
        sql("begin; select set_config('app.challenge_write_v1','on',true); alter table app.challenge_runtime_v1 disable trigger challenge_guard; delete from app.challenge_runtime_v1; alter table app.challenge_runtime_v1 enable trigger challenge_guard; commit;")
        unavailable = status()
        check(unavailable['capture_state'] == 'runtime_unavailable' and unavailable['capture_age_seconds'] is None
              and unavailable['last_capture_at'] == first['last_capture_at'], 'HTTP missing runtime retains capture without age')
        before = digest()
        check(request(RPC, {'p_id': cid}, method='GET')['capture_state'] == 'runtime_unavailable', 'HTTP GET read-only transaction works')
        sql(f"begin read only; set local role service_role; select public.{RPC}('{cid}'); commit;")
        check(digest() == before, 'GET and SQL READ ONLY leave all rows unchanged')
        summary = {'source_head': command(['git', '-C', str(ROOT), 'rev-parse', 'HEAD']).stdout.strip(),
                   'owner': owner, 'images': [DB_IMAGE, AUTH_IMAGE, REST_IMAGE],
                   'migrations_applied': len(migrations), 'migration_inputs': manifest,
                   'sql_assertions': tap_counts, 'checks': checks,
                   'security_advisor_exit': advisor.returncode,
                   'test_inputs': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__), *sorted((ROOT / 'supabase/tests').glob('*.test.sql')), *sorted((ROOT / 'supabase/tests/fixtures').glob('*.inc'))]},
                   'baseline_limits': [],
                   'scope': 'Local SQL and signed-JWT PostgREST checks; no hosted, gateway, real Auth sign-in, scheduler, alerts or P7 acceptance.'}
        (args.evidence_dir / 'verification.json').write_text(json.dumps(summary, indent=2) + '\n')
    finally:
        for kind, name in reversed(owned):
            info = command(['docker', kind, 'inspect', name], check=False)
            if info.returncode == 0:
                row = json.loads(info.stdout)[0]
                labels = row['Config']['Labels'] if kind == 'container' else row['Labels']
                if labels.get('owner') != owner:
                    raise RuntimeError('Refusing cleanup of unowned resource')
                if kind == 'container':
                    command(['docker', 'logs', name], label=name + '.log', check=False)
                command(['docker', 'rm', '-fv', name] if kind == 'container' else ['docker', 'network', 'rm', name])
        print('Owned disposable stack removed; private evidence: ' + str(args.evidence_dir), flush=True)


if __name__ == '__main__':
    main()
