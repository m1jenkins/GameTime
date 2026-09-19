#!/usr/bin/env python3
"""HTTP authorization for the aggregate review monitor on a newly owned stack.

Uses the committed review-monitor-upgrade-before.sql fictional seed. The private
connection JSON names owner, db/auth/rest ports and the fresh local JWT secret.
Never accepts a host or hosted credential; inspect owner labels and loopback
bindings before reading or creating fictional Auth actors. Prints labels only.
"""
import argparse
import base64
import hashlib
import hmac
import http.client
import json
import os
from pathlib import Path
import secrets
import stat
import subprocess
import time
import uuid

KEYS = {
    'server_time', 'evaluated_at', 'monitoring_state', 'outstanding_review_count',
    'reviews_without_eligible_operator_count', 'earliest_review_resolve_by',
    'next_review_grant_expires_at', 'pending_appeal_count',
    'appeals_without_eligible_operator_count', 'oldest_pending_appeal_at',
    'next_appeal_grant_expires_at',
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--connection-file', required=True, type=Path)
    parser.add_argument('--sample-output', required=True, type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    assert not args.connection_file.is_symlink()
    assert stat.S_IMODE(args.connection_file.stat().st_mode) & 0o077 == 0
    config = json.loads(args.connection_file.read_text())
    owner = config['owner']
    assert owner.startswith('gametime-review-monitor-')
    assert all(c.isalnum() or c == '-' for c in owner)
    ports = [config[k+'_port'] for k in ('db', 'auth', 'rest')]
    assert len(set(ports)) == 3 and all(type(p) is int and 1024 <= p <= 65535 for p in ports)
    containers = json.loads(subprocess.check_output(['docker', 'inspect', *[owner+'-'+k for k in ('db', 'auth', 'rest')]]))
    for row, port, inner in zip(containers, ports, (5432, 9999, 3000)):
        assert row['Config']['Labels']['owner'] == owner and row['State']['Running']
        assert row['HostConfig']['PortBindings'] == {str(inner)+'/tcp': [{'HostIp': '127.0.0.1', 'HostPort': str(port)}]}

    def jwt(role):
        def enc(value):
            return base64.urlsafe_b64encode(json.dumps(value, separators=(',', ':')).encode()).decode().rstrip('=')
        data = enc({'alg': 'HS256', 'typ': 'JWT'})+'.'+enc({'role': role, 'iss': 'supabase', 'iat': int(time.time()), 'exp': int(time.time())+3600})
        signature = hmac.new(config['jwt'].encode(), data.encode(), hashlib.sha256).digest()
        return data+'.'+base64.urlsafe_b64encode(signature).decode().rstrip('=')

    def local_http(port, path, body, token=None):
        conn = http.client.HTTPConnection('127.0.0.1', port, timeout=10)
        headers = {'Content-Type': 'application/json'}
        if token:
            headers['Authorization'] = 'Bearer '+token
        try:
            conn.request('POST', path, json.dumps(body), headers)
            response = conn.getresponse()
            raw = response.read()
            return response.status, json.loads(raw) if raw else None
        finally:
            conn.close()

    def sql(statement):
        result = subprocess.run(['docker', 'exec', '-i', owner+'-db', 'psql', '-XAt', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1'], input=statement, text=True, capture_output=True)
        assert result.returncode == 0, 'Owned fixture SQL failed'
        return result.stdout.strip()

    checks = 0
    def check(ok, label):
        nonlocal checks
        assert ok, label
        checks += 1
        print('PASS: '+label, flush=True)

    service = jwt('service_role')
    def rpc(name, body=None, token=service):
        return local_http(config['rest_port'], '/rpc/'+name, body or {}, token)

    sql("notify pgrst, 'reload schema';")
    # Bounded schema-cache readiness, never retries a mutation.
    for _ in range(30):
        status, snapshot = rpc('challenge_local_review_status_v1')
        if status == 200:
            break
        time.sleep(0.1)
    check(status == 200, 'service HTTP read succeeds')
    check(set(snapshot) == KEYS, 'response has only the exact operational allowlist')
    check(snapshot['outstanding_review_count'] == 3 and snapshot['pending_appeal_count'] == 2, 'saved case counts match SQL fixture')
    check(snapshot['reviews_without_eligible_operator_count'] == 1 and snapshot['appeals_without_eligible_operator_count'] == 0, 'scope and independent support match SQL')
    args.sample_output.write_text(json.dumps(snapshot, indent=2, sort_keys=True)+'\n')
    check(rpc('challenge_local_review_status_v1', token=None)[0] == 401, 'anonymous HTTP read denied')
    check(rpc('challenge_local_review_status_v1', token=jwt('anon'))[0] == 401, 'anonymous JWT read denied')

    password = secrets.token_urlsafe(32)
    email = 'monitor-'+uuid.uuid4().hex+'@example.invalid'
    status, actor = local_http(config['auth_port'], '/admin/users', {'email': email, 'password': password, 'email_confirm': True}, service)
    check(status == 200, 'fictional Auth actor created on owned stack')
    actor_id = str(uuid.UUID(actor['id']))
    sql(f"insert into public.profiles(id,handle,display_name,timezone) values('{actor_id}','monitor{uuid.uuid4().hex[:12]}','Fictional monitor','UTC');")
    status, session = local_http(config['auth_port'], '/token?grant_type=password', {'email': email, 'password': password})
    check(status == 200, 'real local Auth session established')
    human = session['access_token']
    try:
        check(rpc('challenge_local_review_status_v1', token=human)[0] == 403, 'ordinary authenticated HTTP read denied')
        challenge = sql("select id from review_monitor_upgrade.ids where name='review_b';")
        status, _ = rpc('challenge_grant_operator_v1', {'p_actor': actor_id, 'p_id': challenge, 'p_capability': 'review', 'p_expires': '2026-10-14T12:00:00Z'})
        check(status in (200, 204), 'existing scoped grant used without modifying its API')
        check(rpc('challenge_local_review_status_v1', token=human)[0] == 403, 'scoped reviewer cannot read service monitor')
        check(rpc('challenge_local_review_status_v1')[1]['reviews_without_eligible_operator_count'] == 0, 'actual active scoped reviewer changes service projection')
        status, _ = rpc('challenge_grant_support_v1', {'p_actor': actor_id, 'p_expires': '2026-10-14T12:00:00Z'})
        check(status in (200, 204), 'existing independent support grant used')
        check(rpc('challenge_local_review_status_v1', token=human)[0] == 403, 'global support cannot read service monitor')
        sql("select public.challenge_runtime_v1(false,true,false,'{}','2026-10-13T12:00Z');")
        status, paused = rpc('challenge_local_review_status_v1')
        check(status == 200 and paused['monitoring_state'] == 'paused' and paused['outstanding_review_count'] == 3, 'paused hidden worker set still shows saved reviews over HTTP')
        sql("select public.challenge_runtime_v1(false,false,false,'{}',null);")
        status, disabled = rpc('challenge_local_review_status_v1')
        check(status == 200 and disabled['monitoring_state'] == 'disabled' and disabled['pending_appeal_count'] == 2, 'disabled monitoring cannot appear healthy-empty')
        check(set(disabled) == KEYS, 'redaction allowlist preserved while disabled')
    finally:
        # End only this test session; do not operate other stack users/sessions.
        conn = http.client.HTTPConnection('127.0.0.1', config['auth_port'], timeout=10)
        conn.request('POST', '/logout', headers={'Authorization': 'Bearer '+human})
        response = conn.getresponse()
        response.read()
        conn.close()
        check(response.status == 204, 'test Auth session ended')
    print(f'{checks} HTTP checks passed')


if __name__ == '__main__':
    main()
