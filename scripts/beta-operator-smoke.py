#!/usr/bin/env python3
"""Focused actual CLI/Auth/PostgREST checks on newly owned loopback resources.

The private connection file is produced by task-owned resource setup; this runner
never starts/stops Docker services or uses a retained preview stack. It checks
ownership/publishes before admitting actors. Only fictional supported fixture
operations prepare challenges; human decisions always execute CLI subprocesses.
"""
import argparse
import hashlib
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys
import threading
import uuid

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('operator_cli', ROOT/'scripts/beta-operator.py')
cli_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli_module)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--connection-file', required=True, type=Path)
    parser.add_argument('--work-dir', required=True, type=Path)
    parser.add_argument('--evidence-dir', required=True, type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    args.work_dir.mkdir(mode=0o700, parents=True, exist_ok=False)
    args.evidence_dir.mkdir(mode=0o700, parents=True, exist_ok=False)
    config = cli_module.private_json(args.connection_file)
    owner = config['owner']
    assert owner.startswith('gametime-p11a-operator-') and config['project_id'] == owner
    ports = [config[k] for k in ['api_port', 'db_port', 'auth_port', 'rest_port']]
    assert len(set(ports)) == 4 and all(type(p) is int and 1024 <= p <= 65535 for p in ports)
    db = owner + '-db'
    containers = json.loads(subprocess.check_output(['docker', 'inspect', db, owner+'-auth', owner+'-rest']))
    bindings = []
    for row, port, inner in zip(containers, ports[1:], [5432, 9999, 3000]):
        assert row['Config']['Labels']['owner'] == owner and row['State']['Running']
        assert row['HostConfig']['PortBindings'] == {str(inner)+'/tcp': [{'HostIp': '127.0.0.1', 'HostPort': str(port)}]}
        bindings.append({'id': row['Id'], 'name': row['Name'], 'created': row['Created'], 'ports': row['HostConfig']['PortBindings']})
    trace, checks, outputs, secrets_seen = [], [], [], [config['anon'], config['service']]
    loss = {'request': None, 'committed': False}

    def local_http(port, method, path, headers, body=None):
        conn = http.client.HTTPConnection('127.0.0.1', port, timeout=15)
        try:
            conn.request(method, path, body, headers)
            response = conn.getresponse()
            return response.status, response.read()
        finally:
            conn.close()

    class Proxy(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_POST(self):
            body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
            if self.path.startswith('/auth/v1/'):
                port, path = config['auth_port'], self.path[len('/auth/v1'):]
            elif self.path.startswith('/rest/v1/rpc/'):
                port, path = config['rest_port'], self.path[len('/rest/v1'):]
            else:
                self.send_error(404)
                return
            headers = {k: v for k, v in self.headers.items() if k.lower() not in ['host', 'content-length']}
            status, raw = local_http(port, 'POST', path, headers, body)
            data = json.loads(body)
            rid = data.get('p_request_id')
            trace.append({'path': self.path, 'request_id': rid, 'body_sha256': hashlib.sha256(body).hexdigest(), 'status': status})
            if self.path.startswith('/auth/v1/token') and status == 200:
                session = json.loads(raw)
                secrets_seen.extend([session['access_token'], session['refresh_token']])
            if rid and rid == loss['request'] and 200 <= status < 300:
                loss.update(request=None, committed=True)
                self.close_connection = True
                self.connection.shutdown(socket.SHUT_RDWR)
                return
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

    server = ThreadingHTTPServer(('127.0.0.1', config['api_port']), Proxy)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    def check(value, label):
        if not value:
            raise AssertionError(label)
        checks.append(label)
        print('PASS: ' + label, flush=True)

    def sql(statement):
        result = subprocess.run(['docker', 'exec', '-i', db, 'psql', '-XAt', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'], input=statement, text=True, capture_output=True)
        if result.returncode:
            # Test SQL never includes credentials. Keep errors private, not in stdout.
            (args.evidence_dir/'sql-failure.txt').write_text(result.stderr)
            raise AssertionError('Fixture or audit SQL failed; inspect private sql-failure.txt')
        return result.stdout.strip()

    def rpc(name, body, headers, expected=200):
        status, raw = local_http(config['api_port'], 'POST', '/rest/v1/rpc/'+name, headers, json.dumps(body))
        assert status == expected, (name, status, expected)
        return json.loads(raw) if raw else None

    def write_private(path, value):
        with path.open('x') as stream:
            json.dump(value, stream)

    admin_headers = {'apikey': config['service'], 'Authorization': 'Bearer '+config['service'], 'Content-Type': 'application/json'}
    common = {'project_id': owner, 'api_port': config['api_port']}
    admin_path = args.work_dir/'administrator.json'
    write_private(admin_path, dict(common, role='administrator', api_key=config['service']))
    journal = args.work_dir/'journal'
    actors, auth = [], []
    owned_fixtures = False

    def cli(*command, actor=None, error=None, credentials=None, administrator=None):
        path = credentials or (args.work_dir/f'human-{actor}.json' if actor is not None else admin_path)
        argv = [sys.executable, str(ROOT/'scripts/beta-operator.py'), '--owned-project', owner,
                '--credentials-file', str(path), '--journal-dir', str(journal)]
        if (actor is None) if administrator is None else administrator:
            argv += ['--administrator']
        audit_before = sql('select count(*) from app.challenge_operator_audit_v1;') if error and error != 'could not be confirmed' else None
        result = subprocess.run(argv+list(command), capture_output=True, text=True, timeout=45)
        outputs.extend([result.stdout, result.stderr])
        if error:
            check(result.returncode != 0 and error in result.stderr, 'CLI denial: '+command[0]+' / '+error)
            if audit_before is not None:
                check(sql('select count(*) from app.challenge_operator_audit_v1;') == audit_before, 'Denied action leaves operator audit unchanged: '+command[0])
            return None
        assert result.returncode == 0, ('CLI failed', command[0], result.stderr)
        return json.loads(result.stdout)

    def clock(value):
        ids = ','.join("'"+a['id']+"'::uuid" for a in actors)
        sql(f"select public.challenge_runtime_v1(true,true,true,array[{ids}],'{value}');")

    def mutate(i, cid, op, **fields):
        if cid:
            detail = rpc('challenge_detail_v1', {'p_id': cid}, auth[i])
            fields.update(id=cid, revision=detail['revision'])
        return rpc('challenge_command_v1', {'p_request_id': str(uuid.uuid4()), 'p_payload': dict(op=op, **fields)}, auth[i])

    def grant(actor, cid=None, capability='moderate', expiry='2026-10-10T12:00:00Z'):
        command = ['grant' if cid else 'grant-support', '--actor', actors[actor]['id'], '--expires', expiry]
        if cid:
            command += ['--challenge', cid, '--capability', capability]
        cli(*command)

    def recovery(command, actor, after_commit=None):
        rid = str(uuid.uuid4())
        command = [*command, '--request-id', rid]
        loss.update(request=rid, committed=False)
        cli(*command, actor=actor, error='could not be confirmed')
        check(loss['committed'], 'Committed response deliberately lost: '+command[0])
        before = sql(f"select count(*) from app.challenge_requests_v1 where actor_id='{actors[actor]['id']}' and request_id='{rid}';")
        audit_before = sql(f"select count(*) from app.challenge_operator_audit_v1 where id='{rid}';")
        check(before == '1', 'Receipt exists before retry: '+command[0])
        if after_commit:
            after_commit()
        receipt = cli(*command, actor=actor)
        check(receipt == {'saved': True} or command[0] == 'close-community' and receipt['status'] == 'cancelled', 'Exact CLI retry returns original receipt: '+command[0])
        check(sql(f"select count(*) from app.challenge_operator_audit_v1 where id='{rid}';") == audit_before, 'Retry adds no audit action: '+command[0])
        rows = [r for r in trace if r['request_id'] == rid]
        check(len(rows) == 2 and rows[0]['body_sha256'] == rows[1]['body_sha256'], 'Retry sends identical HTTP bytes: '+command[0])
        check((journal/(rid+'.json')).stat().st_mode & 0o777 == 0o600, 'Private recovery file: '+command[0])
        return rid, command

    try:
        # Inspect/probe before any fictional account exists in this run.
        probes = []
        for port in ports:
            with socket.create_connection(('127.0.0.1', port), 2):
                probes.append({'address': '127.0.0.1', 'port': port, 'reachable': True})
        addresses = subprocess.check_output(['ifconfig'], text=True)
        import re
        lan = sorted(set(re.findall(r'\binet (\d+\.\d+\.\d+\.\d+)', addresses)) - {'127.0.0.1'})
        for address in lan:
            for port in ports:
                try:
                    with socket.create_connection((address, port), 0.3):
                        raise AssertionError('Nonloopback listener is reachable; no actors admitted')
                except (ConnectionRefusedError, TimeoutError, OSError) as error:
                    probes.append({'address': address, 'port': port, 'reachable': False, 'result': type(error).__name__})
        (args.evidence_dir/'pre-actor-bindings.json').write_text(json.dumps({'containers': bindings, 'proxy': server.server_address, 'probes': probes}, indent=2))
        check(sql('select not admission and not fixtures and not processing and cardinality(actors)=0 from app.challenge_runtime_v1 where singleton;') == 't', 'Owned fixture runtime starts closed')
        password = secrets.token_urlsafe(28)
        secrets_seen.append(password)
        for i in range(7):
            email = 'p11a-'+uuid.uuid4().hex+'@example.invalid'
            status, raw = local_http(config['api_port'], 'POST', '/auth/v1/admin/users', admin_headers, json.dumps({'email': email, 'password': password, 'email_confirm': True}))
            assert status < 300, ('Auth user creation', status)
            actor = {'id': str(uuid.UUID(json.loads(raw)['id'])), 'email': email, 'username': 'p11a_'+uuid.uuid4().hex[:12]}
            actors.append(actor)
            sql(f"insert into public.profiles(id,handle,display_name,timezone) values('{actor['id']}','{actor['username']}','Fictional operator check','UTC');")
            write_private(args.work_dir/f'human-{i}.json', dict(common, role='human', api_key=config['anon'], actor_id=actor['id'], email=email, password=password))
            status, raw = local_http(config['api_port'], 'POST', '/auth/v1/token?grant_type=password', {'apikey': config['anon'], 'Content-Type': 'application/json'}, json.dumps({'email': email, 'password': password}))
            assert status == 200, ('Auth login', status)
            auth.append({'apikey': config['anon'], 'Authorization': 'Bearer '+json.loads(raw)['access_token'], 'Content-Type': 'application/json'})
        owned_fixtures = True
        clock('2026-10-01T12:00:00Z')
        for actor in actors:
            sql(f"select public.challenge_readiness_metric_fixture_v1('{actor['id']}','steps');")
        a, b = actors[0]['id'], actors[1]['id']
        sql(f"insert into public.friendships(user_a,user_b,requested_by,status) values(least('{a}'::uuid,'{b}'::uuid),greatest('{a}'::uuid,'{b}'::uuid),'{a}','accepted');")
        for i in range(7):
            mutate(i, None, 'confirm_age', confirmed=True)
        settings = {'start_date': '2026-10-03', 'days': 1, 'timezone': 'UTC', 'amount_cents': 100}
        cid = mutate(0, None, 'create', config=settings)['id']
        mutate(0, cid, 'target', target=100)
        mutate(0, cid, 'invite', username=actors[1]['username'])
        mutate(1, cid, 'target', target=100)
        mutate(0, cid, 'select', actor_id=b, selected=True)
        mutate(0, cid, 'freeze')
        for i in [0, 1]:
            detail = rpc('challenge_detail_v1', {'p_id': cid}, auth[i])
            mutate(i, cid, 'consent', consent=True, digest=detail['agreement']['digest'])
        clock('2026-10-03T12:00:00Z')
        for i in [0, 1]:
            sql(f"select public.challenge_capture_fixture_v1('{uuid.uuid4()}','{cid}','{actors[i]['id']}',200,'complete');")
        clock('2026-10-06T12:00:00Z')
        sql(f"select public.challenge_process_v1('{cid}');")
        mutate(0, cid, 'review', notice_revision=1, reason='wrong_total')
        cli('cases', '--challenge', cid, actor=6, error='42501')
        grant(6, cid, 'review')
        cases = cli('cases', '--challenge', cid, actor=6)
        check(len(cases) == 1 and cases[0]['context']['fact']['value'] == 200 and 'participants' not in cases[0]['context'], 'Scoped review exposes only agreed case context')
        other = str(uuid.uuid4())
        cli('cases', '--challenge', other, actor=6, error='42501')
        cli('reports', '--challenge', cid, actor=6, error='42501')
        cli('grant', '--actor', a, '--challenge', cid, '--capability', 'review', '--expires', '2026-10-10T12:00:00Z', error='22023')
        rid, command = recovery(['resolve', '--challenge', cid, '--review', cases[0]['id'], '--decision', 'upheld'], 6,
            lambda: cli('revoke', '--actor', actors[6]['id'], '--challenge', cid, '--capability', 'review'))
        cli('cases', '--challenge', cid, actor=6, error='42501')
        cli('resolve', '--challenge', cid, '--review', cases[0]['id'], '--decision', 'upheld', '--request-id', str(uuid.uuid4()), actor=6, error='42501')
        conflict = rpc('challenge_operator_action_v1', {'p_request_id': rid, 'p_payload': {'op': 'resolve', 'id': cid, 'review_id': cases[0]['id'], 'decision': 'exclude'}}, auth[6], expected=400)
        check(conflict['code'] == '22023', 'Server rejects changed payload under committed request identity')
        cli(*command, actor=5, error='Saved request differs')
        changed = ['exclude' if v == 'upheld' else v for v in command]
        cli(*changed, actor=6, error='Saved request differs')
        check(sql(f"select operator_id='{actors[6]['id']}' from app.challenge_resolutions_v1 where review_id='{cases[0]['id']}';") == 't', 'Resolution records the authenticated independent reviewer')
        # Moderator visibility requires actual report scope, never inferred global scope.
        scoped = str(uuid.uuid4()); global_report = str(uuid.uuid4())
        rpc('challenge_report_scoped_v1', {'p_request_id': scoped, 'p_id': cid, 'p_subject': b, 'p_reason': 'username'}, auth[0])
        rpc('challenge_report_v1', {'p_request_id': global_report, 'p_subject': b, 'p_reason': 'unwanted_contact'}, auth[0])
        grant(5, cid)
        obsolete = rpc('challenge_operator_action_v1', {'p_request_id': str(uuid.uuid4()), 'p_payload': {'op': 'suspend', 'id': cid, 'actor_id': b, 'reason': 'username'}}, auth[5], expected=403)
        check(obsolete['code'] == '42501', 'Actual obsolete moderator suspension RPC remains denied')
        reports = cli('reports', '--challenge', cid, actor=5)
        check([r['id'] for r in reports] == [scoped], 'Moderator sees exact scoped report and excludes global report')
        cli('reports', '--challenge', other, actor=5, error='42501')
        cli('remove', '--challenge', other, '--subject', b, '--reason', 'username', '--request-id', str(uuid.uuid4()), actor=5, error='42501')
        cli('support-reports', actor=5, error='42501')
        cli('support-appeals', actor=5, error='42501')
        cli('suspend', '--subject', b, '--reason', 'username', '--request-id', str(uuid.uuid4()), actor=5, error='42501')
        cli('suspend', '--challenge', cid, '--subject', b, '--reason', 'username', '--request-id', str(uuid.uuid4()), actor=5, error='Invalid arguments')
        recovery(['remove', '--challenge', cid, '--subject', b, '--reason', 'username'], 5)
        check(sql(f"select exited_at is not null from app.challenge_members_v1 where challenge_id='{cid}' and actor_id='{b}';") == 't' and sql(f"select count(*) from app.challenge_suspensions_v1 where actor_id='{b}';") == '0', 'Removal exits only its challenge; no global suspension')
        cli('revoke', '--actor', actors[5]['id'], '--challenge', cid, '--capability', 'moderate')
        cli('reports', '--challenge', cid, actor=5, error='42501')
        grant(5, cid, expiry='2026-10-06T12:01:00Z')
        grant(6, cid, 'review', expiry='2026-10-06T12:01:00Z')
        clock('2026-10-06T12:01:00Z')
        cli('reports', '--challenge', cid, actor=5, error='42501')
        cli('cases', '--challenge', cid, actor=6, error='42501')
        cli('remove', '--challenge', cid, '--subject', a, '--reason', 'username', '--request-id', str(uuid.uuid4()), actor=5, error='42501')
        cli('grant-support', '--actor', actors[4]['id'], '--expires', '2026-10-20T12:00:00Z', error='22023')
        grant(4)
        all_reports = cli('support-reports', actor=4)
        check({scoped, global_report} <= {r['id'] for r in all_reports}, 'Separate global support sees both scoped and global reports')
        cursor = next(r for r in all_reports if r['id'] == scoped)
        paged = cli('support-reports', '--before', cursor['created_at'], '--before-id', cursor['id'], actor=4)
        check(scoped not in {r['id'] for r in paged} and len(paged) <= 100, 'Global reports accept paired keyset cursor')
        before_trace = len(trace)
        cli('support-reports', '--before', cursor['created_at'], actor=4, error='Provide both')
        check(len(trace) == before_trace, 'Incomplete cursor rejected before authentication or RPC')
        cli('cases', '--challenge', cid, actor=4, error='42501')
        cli('suspend', '--subject', actors[4]['id'], '--reason', 'username', '--request-id', str(uuid.uuid4()), actor=4, error='22023')
        # Suspension ends active participation. The reviewed two-person group
        # already finalized after removal, so use a new active agreement here.
        third = actors[2]['id']
        sql(f"insert into public.friendships(user_a,user_b,requested_by,status) values(least('{a}'::uuid,'{third}'::uuid),greatest('{a}'::uuid,'{third}'::uuid),'{a}','accepted');")
        live = mutate(0, None, 'create', config=dict(settings, start_date='2026-10-09'))['id']
        mutate(0, live, 'target', target=100)
        mutate(0, live, 'invite', username=actors[2]['username'])
        mutate(2, live, 'target', target=100)
        mutate(0, live, 'select', actor_id=third, selected=True)
        mutate(0, live, 'freeze')
        for i in [0, 2]:
            detail = rpc('challenge_detail_v1', {'p_id': live}, auth[i])
            mutate(i, live, 'consent', consent=True, digest=detail['agreement']['digest'])
        recovery(['suspend', '--subject', a, '--reason', 'unsafe_behavior'], 4,
            lambda: cli('revoke-support', '--actor', actors[4]['id']))
        cli('support-reports', actor=4, error='42501')
        cli('suspend', '--subject', b, '--reason', 'username', '--request-id', str(uuid.uuid4()), actor=4, error='42501')
        grant(4)
        status = rpc('challenge_access_status_v1', {}, auth[0])
        check(status['suspended'] is True, 'Suspended live HTTP session can read access status')
        own = rpc('challenge_detail_v1', {'p_id': live}, auth[0])
        check(own['social_hidden'] and [m['actor_id'] for m in own['members']] == [a], 'Suspended HTTP detail retains only own member')
        check(own['agreement']['terms'] is None, 'Suspended HTTP detail hides friend roster terms')
        history = rpc('challenge_section_v1', {'p_section': 'history'}, auth[0])
        check(any(row['id'] == live for row in history['rows']), 'Suspended HTTP session can page own history')
        denied = rpc('challenge_command_v1', {'p_request_id': str(uuid.uuid4()), 'p_payload': {'op': 'create', 'config': dict(settings, start_date='2026-10-09')}}, auth[0], expected=403)
        check(denied['message'] == 'challenge_admission_paused', 'Suspended HTTP session cannot start a new friend challenge')
        denied = rpc('challenge_command_v1', {'p_request_id': str(uuid.uuid4()), 'p_payload': {'op': 'personal_commit'}}, auth[0], expected=403)
        check(denied['message'] == 'challenge_admission_paused', 'Suspended HTTP session cannot start a personal commitment')
        appeal_id, _ = recovery(['appeal'], 0)
        check(any(r['id'] == appeal_id for r in cli('own-appeals', actor=0)), 'Appellant reads own filed appeal')
        check(any(r['id'] == appeal_id for r in cli('support-appeals', actor=4)), 'Support reads pending appeal')
        cli('resolve-appeal', '--appeal', appeal_id, '--decision', 'reinstate', '--request-id', str(uuid.uuid4()), actor=4, error='42501')
        cli('resolve-appeal', '--appeal', appeal_id, '--decision', 'reinstate', '--request-id', str(uuid.uuid4()), actor=0, error='42501')
        grant(3)
        recovery(['resolve-appeal', '--appeal', appeal_id, '--decision', 'reinstate'], 3,
            lambda: cli('revoke-support', '--actor', actors[3]['id']))
        check(sql(f"select not suspended from app.challenge_suspensions_v1 where actor_id='{a}';") == 't' and sql(f"select exited_at is not null from app.challenge_members_v1 where challenge_id='{live}' and actor_id='{a}';") == 't', 'Independent reinstatement preserves ended membership')
        check(any(r['decision'] == 'reinstate' for r in cli('own-appeals', actor=0)), 'Own appeal shows independent decision')
        # Exercise the second decision value with another independent actor.
        cli('suspend', '--subject', b, '--reason', 'username', '--request-id', str(uuid.uuid4()), actor=4)
        appeal2 = str(uuid.uuid4())
        cli('appeal', '--request-id', appeal2, actor=1)
        grant(3)
        cli('resolve-appeal', '--appeal', appeal2, '--decision', 'upheld', '--request-id', str(uuid.uuid4()), actor=3)
        check(sql(f"select suspended from app.challenge_suspensions_v1 where actor_id='{b}';") == 't', 'Independent upheld decision keeps suspension')
        grant(3, expiry='2026-10-06T12:02:00Z')
        clock('2026-10-06T12:02:00Z')
        cli('support-appeals', actor=3, error='42501')
        cli('resolve-appeal', '--appeal', appeal_id, '--decision', 'upheld', '--request-id', str(uuid.uuid4()), actor=3, error='42501')
        settings['start_date'] = '2026-10-09'
        settings_path = args.work_dir/'community.json'; write_private(settings_path, settings)
        community = cli('publish-fixture', '--operator', actors[6]['id'], '--config-file', str(settings_path), '--target', '100', '--minimum', '2', '--capacity', '6', '--request-id', str(uuid.uuid4()), '--fictional')
        sql('select public.challenge_discovery_fixture_v1(true);')
        check(any(row['id'] == community for row in rpc('challenge_community_catalog_v1', {}, auth[0])), 'Active HTTP actor can discover the published community')
        check(rpc('challenge_community_catalog_v1', {}, auth[1]) == [], 'Suspended HTTP actor cannot discover the same community')
        digest = sql(f"select digest from app.challenge_agreements_v1 where challenge_id='{community}';")
        denied = rpc('challenge_join_community_v1', {'p_request_id': str(uuid.uuid4()), 'p_payload': {'op': 'join_community', 'id': community, 'digest': digest, 'consent': True}}, auth[1], expected=403)
        check(denied['message'] == 'challenge_admission_paused', 'Suspended HTTP actor cannot join with a valid known community digest')
        sql('select public.challenge_discovery_fixture_v1(false);')
        grant(6, community)
        cli('close-community', '--challenge', community, '--request-id', str(uuid.uuid4()), actor=5, error='42501')
        recovery(['close-community', '--challenge', community], 6)
        # Live grants do not override suspension for fresh privileged actions.
        grant(5, cid, 'review')
        grant(5, cid, 'moderate')
        grant(5)
        cli('suspend', '--subject', actors[5]['id'], '--reason', 'unsafe_behavior', '--request-id', str(uuid.uuid4()), actor=4)
        cli('cases', '--challenge', cid, actor=5, error='42501')
        cli('reports', '--challenge', cid, actor=5, error='42501')
        cli('support-reports', actor=5, error='42501')
        cli('support-appeals', actor=5, error='42501')
        cli('suspend', '--subject', actors[2]['id'], '--reason', 'username', '--request-id', str(uuid.uuid4()), actor=5, error='42501')
        # Both CLI and actual HTTP separate administration from human authority.
        cli('grant-support', '--actor', a, '--expires', '2026-10-10T12:00:00Z', actor=6, error='Use --administrator')
        cli('support-reports', error='Use --administrator')
        cli('grant-support', '--actor', a, '--expires', '2026-10-10T12:00:00Z', actor=6, administrator=True, error='Credential role does not match')
        for name, body in [
            ('challenge_grant_operator_v1', {'p_actor': actors[6]['id'], 'p_id': cid, 'p_capability': 'review', 'p_expires': '2026-10-10T12:00:00Z'}),
            ('challenge_revoke_operator_v1', {'p_actor': actors[6]['id'], 'p_id': cid, 'p_capability': 'review'}),
            ('challenge_grant_support_v1', {'p_actor': actors[6]['id'], 'p_expires': '2026-10-10T12:00:00Z'}),
            ('challenge_revoke_support_v1', {'p_actor': actors[6]['id']})]:
            result = rpc(name, body, auth[6], expected=403)
            check(result['code'] == '42501', 'Actual human HTTP cannot administer: '+name)
        check(sql(f"select count(*)>0 from app.challenge_operator_audit_v1 where operator_id in ('{actors[4]['id']}','{actors[5]['id']}','{actors[6]['id']}') and payload->>'op' in ('read_global_reports','read_reports','read_cases');") == 't', 'Allowed reads write operator audit')
        # The original independently held session still works after CLI logouts.
        check(rpc('challenge_own_appeals_v1', {}, auth[0])[0]['decision'] == 'reinstate', 'CLI local logout preserves another live session')
        actor_ids = ','.join("'"+a['id']+"'" for a in actors)
        check(sql(f"select count(*) from auth.sessions where user_id in ({actor_ids});") == str(len(auth)), 'Every CLI sign-in session ended; only seven harness sessions remain')
        # The HTTP token is still signed and unexpired; server-side session
        # expiry/revocation must immediately deny even permitted own reads.
        suspended = actors[1]['id']
        sql(f"update auth.sessions set not_after=clock_timestamp() where user_id='{suspended}';")
        denied = rpc('challenge_access_status_v1', {}, auth[1], expected=403)
        check(denied['message'] == 'challenge_session_required', 'Expired session rejects a suspended actor with a still-valid JWT')
        sql(f"update auth.sessions set not_after=null where user_id='{suspended}';")
        check(rpc('challenge_access_status_v1', {}, auth[1])['suspended'], 'Restored live session retains permitted suspended access')
        logout_status, _ = local_http(config['api_port'], 'POST', '/auth/v1/logout?scope=local', auth[1], '{}')
        check(logout_status == 204, 'Actual Auth logout revokes the suspended harness session')
        denied = rpc('challenge_own_appeals_v1', {}, auth[1], expected=403)
        check(denied['message'] == 'challenge_session_required', 'Revoked session rejects a stale JWT on own appeal history')
        artifacts = '\n'.join(outputs) + '\n'.join(p.read_text() for p in journal.glob('*.json')) + json.dumps(trace)
        check(not any(secret in artifacts for secret in secrets_seen), 'CLI output, HTTP trace and recovery records contain no test credentials or tokens')
        check(not any(key in p.read_text() for p in journal.glob('*.json') for key in ['password', 'api_key', 'access_token', 'refresh_token', 'Authorization', 'Bearer ']), 'Recovery records exclude credential fields')
        check(cli('status')['server_time'] is not None, 'Existing local status command remains usable')
    finally:
        if owned_fixtures:
            sql('select public.challenge_runtime_v1(false,false,false,array[]::uuid[],null);')
        for headers in auth:
            local_http(config['api_port'], 'POST', '/auth/v1/logout?scope=local', headers, '{}')
        server.shutdown(); server.server_close(); thread.join()
        (args.evidence_dir/'http-trace.json').write_text(json.dumps(trace, indent=2))
        (args.evidence_dir/'results.json').write_text(json.dumps({'checks': checks, 'count': len(checks), 'proxy_stopped': True, 'fixtures_closed': owned_fixtures}, indent=2))
    print('Completed '+str(len(checks))+' checks; own proxy stopped and fixture runtime closed.', flush=True)


if __name__ == '__main__':
    main()
