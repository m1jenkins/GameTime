#!/usr/bin/env python3
"""Production Swift-client HTTP acceptance on an owned disposable stack.
No hosted target, mail, Health inputs or pre-existing Simulator control.
Secrets stay in an ignored, mode-0600 manifest and are removed on cleanup.
"""
import argparse
import signal
import hashlib
import http.client
import json
import os
from pathlib import Path
import secrets
import subprocess
import threading
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1]
OWNED_PROJECT = os.environ.get('GAMETIME_BETA_PREVIEW_PROJECT', 'gametime-finish-b7')
PORT_BASE = int(os.environ.get('GAMETIME_BETA_PREVIEW_PORT_BASE', '58320'))
API_PORT = PORT_BASE + 1
DB_PORT = PORT_BASE + 2
CONTROLLER_PORT = PORT_BASE + 19
STACK = Path(os.environ.get('GAMETIME_BETA_PREVIEW_STACK', f'/tmp/{OWNED_PROJECT}-stack'))
DB = f'postgresql://postgres:postgres@127.0.0.1:{DB_PORT}/postgres'
# Native and UI smoke tests read this established per-checkout location.
# The interactive preview scopes its own manifest separately.
MANIFEST = ROOT / 'tmp/beta-native-smoke.json'
REPORT = ROOT / 'tmp/beta-native-smoke-report.json'
OWNED_SIM = os.environ.get('GAMETIME_BETA_PREVIEW_SIMULATOR', '72A3249A-2DE0-4695-AF41-DCD2743B4666')

def sql(statement):
    return subprocess.run(['psql', DB, '-XAt', '-v', 'ON_ERROR_STOP=1'], input=statement, text=True, capture_output=True, check=True).stdout.strip()

def local_http(method, path, headers, body=None):
    conn = http.client.HTTPConnection('127.0.0.1', API_PORT, timeout=30)
    try:
        conn.request(method, path, body, headers)
        res = conn.getresponse()
        return res.status, res.read()
    finally:
        conn.close()

class Smoke:
    def __init__(self):
        assert f'project_id = "{OWNED_PROJECT}"' in (STACK/'supabase/config.toml').read_text()
        settings = json.loads(subprocess.check_output(['supabase', 'status', '--workdir', str(STACK), '-o', 'json'], stderr=subprocess.DEVNULL))
        assert settings['API_URL'] == f'http://127.0.0.1:{API_PORT}' and settings['DB_URL'] == DB
        self.key = settings['PUBLISHABLE_KEY']
        self.admin = {'apikey': settings['SERVICE_ROLE_KEY'], 'Authorization': 'Bearer '+settings['SERVICE_ROLE_KEY'], 'Content-Type': 'application/json'}
        self.password = secrets.token_urlsafe(28)
        self.control = secrets.token_urlsafe(32)
        self.actors = []
        self.trace = []
        self.lose = None
        self.owned = False
        self.manifest_owned = False
    def setup(self):
        assert not MANIFEST.exists(), 'An existing preview manifest requires scoped recovery before starting another run'
        assert sql('select not admission and not fixtures and not processing and cardinality(actors)=0 from app.challenge_runtime_v1 where singleton;') == 't'
        for i in range(7):
            email = f'beta-b7-{uuid.uuid4().hex}@example.invalid'
            status, raw = local_http('POST','/auth/v1/admin/users',self.admin,json.dumps({'email':email,'password':self.password,'email_confirm':True}))
            assert status < 300
            actor = str(uuid.UUID(json.loads(raw)['id']))
            handle = f'betab7_{uuid.uuid4().hex[:12]}'
            self.actors.append({'id':actor,'email':email,'username':handle})
            sql(f"insert into public.profiles(id,handle,display_name,timezone) values('{actor}','{handle}','Fictional B7 {i+1}','America/Chicago');")
        for actor in self.actors[1:6]:
            a,b=self.actors[0]['id'],actor['id']
            sql(f"insert into public.friendships(user_a,user_b,requested_by,status) values(least('{a}'::uuid,'{b}'::uuid),greatest('{a}'::uuid,'{b}'::uuid),'{a}','accepted');")
        self.owned = True
        self.clock('2026-10-01T12:00:00Z')
        for actor in self.actors:
            for metric in ['steps','exercise','distance','timed']:
                sql(f"select public.challenge_readiness_metric_fixture_v1('{actor['id']}','{metric}');")
        MANIFEST.parent.mkdir(exist_ok=True)
        with MANIFEST.open('x') as stream:
            self.manifest_owned = True
            os.chmod(MANIFEST,0o600)
            json.dump({'url':f'http://127.0.0.1:{CONTROLLER_PORT}','key':self.key,'controlToken':self.control,'password':self.password,'actors':self.actors},stream)
    def clock(self, value, admission=True, processing=True):
        # Caller values are parsed before SQL interpolation.
        from datetime import datetime
        datetime.fromisoformat(value.replace('Z','+00:00'))
        ids=','.join("'"+a['id']+"'::uuid" for a in self.actors)
        sql(f"select public.challenge_runtime_v1({str(admission).lower()},true,{str(processing).lower()},array[{ids}],'{value}');")
    def control_call(self, body):
        action=body['action']
        if action=='lose':
            assert body['rpc']=='challenge_command_v1'
            self.lose=body['rpc']
        elif action=='clock':
            self.clock(body['now'],body.get('admission',True),body.get('processing',True))
        elif action=='capture':
            cid=str(uuid.UUID(body['id'])); actor=str(uuid.UUID(body['actor']))
            assert actor in [a['id'] for a in self.actors]
            value=body['value']; assert value is None or type(value) is int and 0<=value<=1000000000
            state='unresolved' if value is None else 'complete'
            sql(f"select public.challenge_capture_fixture_v1('{uuid.uuid4()}','{cid}','{actor}',{'null' if value is None else value},'{state}');")
        elif action=='process':
            cid=str(uuid.UUID(body['id']))
            sql(f"select public.challenge_process_v1('{cid}');")
        elif action=='resolve':
            rid=str(uuid.UUID(body['review']))
            sql(f"select public.challenge_resolve_v1('{rid}','{self.actors[6]['id']}','upheld');")
        elif action=='resolve_challenge':
            cid=str(uuid.UUID(body['id']))
            rid=sql(f"select id from app.challenge_reviews_v1 where challenge_id='{cid}' order by filed_at desc limit 1;")
            sql(f"select public.challenge_resolve_v1('{str(uuid.UUID(rid))}','{self.actors[6]['id']}','upheld');")
        elif action=='community':
            cid = sql(f"select public.challenge_publish_community_fixture_v1('{uuid.uuid4()}','{self.actors[6]['id']}', '{{\"start_date\":\"2026-10-03\",\"days\":1,\"timezone\":\"UTC\",\"amount_cents\":100}}',100,2,6,true);")
            sql('select public.challenge_discovery_fixture_v1(true);')
        elif action=='unallow_actor':
            actor=str(uuid.UUID(body['actor']))
            assert actor in [a['id'] for a in self.actors]
            sql(f"select public.challenge_runtime_v1(admission,fixtures,processing,array_remove(actors,'{actor}'::uuid),fictional_now) from app.challenge_runtime_v1 where singleton;")
        elif action=='revoke_actor_sessions':
            actor=str(uuid.UUID(body['actor']))
            assert actor in [a['id'] for a in self.actors]
            sql(f"delete from auth.sessions where user_id='{actor}';")
        elif action=='latest':
            actor=str(uuid.UUID(body['actor']))
            assert actor in [a['id'] for a in self.actors]
            cid=sql(f"select id from app.challenge_lobbies_v1 where creator_id='{actor}' and status='lobby_open' order by created_at desc,id limit 1;")
            return {'id':cid}
        elif action=='snapshot':
            return {'trace':self.trace}
        else:
            raise ValueError('Unknown control')
        return {'ok':True}
    def cleanup(self):
        revoked = 0
        failures = []
        gates_off = False
        try:
            if self.owned:
                sql("select public.challenge_discovery_fixture_v1(false); select public.challenge_runtime_v1(false,false,false,'{}',null);")
            gates_off = sql('select not admission and not fixtures and not processing and cardinality(actors)=0 from app.challenge_runtime_v1 where singleton;') == 't'
            for actor in self.actors:
                # Only this run's fictional actors, never another effort's sessions.
                status, _ = local_http('PUT','/auth/v1/admin/users/'+actor['id'],self.admin,json.dumps({'password':secrets.token_urlsafe(48),'ban_duration':'876000h'}))
                sql(f"delete from auth.sessions where user_id='{actor['id']}'; delete from auth.refresh_tokens where user_id='{actor['id']}';")
                if status >= 300:
                    failures.append('fictional_actor_ban_failed')
                else:
                    revoked += 1
        finally:
            if self.manifest_owned:
                MANIFEST.unlink(missing_ok=True)
            REPORT.parent.mkdir(exist_ok=True)
            REPORT.write_text(json.dumps({'evidence':'authenticated production Swift client to fictional local backend','trace':self.trace,'gates_off':gates_off,'actors_revoked':revoked,'cleanup_failures':failures},indent=2)+'\n')
        assert gates_off and not failures and revoked == len(self.actors), 'Scoped fixture cleanup incomplete; inspect the report'

class Handler(BaseHTTPRequestHandler):
    def log_message(self,*_):
        pass
    def do_POST(self):
        smoke=self.server.smoke
        body=self.rfile.read(int(self.headers.get('Content-Length','0')))
        try:
            if self.path=='/__beta/control':
                if self.headers.get('X-Beta-Control') != smoke.control:
                    self.reply(403,b'{}'); return
                self.reply(200,json.dumps(smoke.control_call(json.loads(body))).encode()); return
            if not self.path.startswith(('/rest/v1/rpc/challenge_','/auth/v1/')):
                self.reply(403,b'{}'); return
            headers={k:v for k,v in self.headers.items() if k.lower() not in ('host','content-length','connection')}
            status,data=local_http('POST',self.path,headers,body)
            rpc=self.path.rsplit('/',1)[-1]
            if self.path.startswith('/auth/v1/'):
                smoke.trace.append({'auth_status':status})
            if self.path.startswith('/rest/v1/rpc/'):
                smoke.trace.append({'rpc':rpc,'status':status,'payload_sha256':hashlib.sha256(body).hexdigest()})
            if status<300 and smoke.lose==rpc:
                smoke.lose=None; self.reply(503,b'{"message":"response_lost"}'); return
            self.reply(status,data)
        except Exception:
            self.reply(500,b'{"message":"local_controller_failed"}')
    def reply(self,status,data):
        self.send_response(status); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--simulator',required=True);parser.add_argument('--native-only',action='store_true');parser.add_argument('--touch-only',choices=['2','6']);parser.add_argument('--accessibility',choices=['light','dark','large','compact','control','form-reference','tab-reference','scroll-reference'])
    parser.add_argument('--derived-data',type=Path,default=Path(f'/tmp/{OWNED_PROJECT}-derived'))
    parser.add_argument('--evidence-dir',type=Path,default=Path(f'/tmp/{OWNED_PROJECT}-evidence'))
    args=parser.parse_args();assert args.derived_data.is_absolute() and args.evidence_dir.is_absolute(),'Use absolute task-owned build/evidence paths'
    args.evidence_dir.mkdir(parents=True,exist_ok=True)
    assert args.simulator==OWNED_SIM,'Only the configured owned Simulator is allowed'
    smoke=Smoke(); server=ThreadingHTTPServer(('127.0.0.1',CONTROLLER_PORT),Handler);server.smoke=smoke
    running=False
    try:
        smoke.setup()
        if args.accessibility:
            manifest=json.loads(MANIFEST.read_text());manifest['accessibilityMode']=args.accessibility
            MANIFEST.write_text(json.dumps(manifest))
            subprocess.run(['xcrun','simctl','ui',OWNED_SIM,'appearance','dark' if args.accessibility=='dark' else 'light'],check=True)
            subprocess.run(['xcrun','simctl','ui',OWNED_SIM,'content_size','accessibility-extra-extra-extra-large' if args.accessibility=='large' else 'large'],check=True)
        threading.Thread(target=server.serve_forever,daemon=True).start();running=True
        command=['xcodebuild','test','-project','ios/GameTime/GameTime.xcodeproj','-scheme','GameTimeBetaLocal','-configuration','Debug','-destination',f'platform=iOS Simulator,id={OWNED_SIM}','-derivedDataPath',str(args.derived_data),'-parallel-testing-enabled','NO','-only-testing:GameTimeTests/ChallengeV1NativeSmokeTests','-only-testing:GameTimeTests/ChallengeV1NativeTests','-only-testing:GameTimeTests/ChallengePolicyTests','-only-testing:GameTimeTests/ChallengeSectionTests','-only-testing:GameTimeTests/WeeklySocialRefreshAuthRaceTests','CODE_SIGNING_ALLOWED=NO']
        assert sum([args.native_only,bool(args.touch_only),bool(args.accessibility)]) <= 1
        if args.accessibility:
            command=[x for x in command if not x.startswith('-only-testing:')]
            command.append('-only-testing:GameTimeUITests/ChallengeV1UITests/'+({'control':'testIsolatedDynamicTypeControl','form-reference':'testSystemFormDynamicTypeReference','tab-reference':'testSystemTabContrastReference','scroll-reference':'testSystemScrollDynamicTypeReference'}.get(args.accessibility,'testLocalAccessibilityPreparation')))
        elif args.touch_only:
            command=[x for x in command if not x.startswith('-only-testing:')]
            command.append('-only-testing:GameTimeUITests/ChallengeV1UITests/test'+('Two' if args.touch_only=='2' else 'Six')+'PersonTouchJourney')
        elif not args.native_only:command.append('-only-testing:GameTimeUITests/ChallengeV1UITests')
        result_path = args.evidence_dir / ('native-' + str(uuid.uuid4()) + '.xcresult')
        command += ['-resultBundlePath', str(result_path)]
        print('Preview result bundle: ' + str(result_path), flush=True)
        # A new process group belongs exclusively to this run. Never stop shared
        # Xcode or Simulator services when a failed audit stalls result reporting.
        env = os.environ.copy()
        env['TEST_RUNNER_GAMETIME_BETA_EXPECTED_LOCAL_URL'] = f'http://127.0.0.1:{CONTROLLER_PORT}'
        child = subprocess.Popen(command, cwd=ROOT, env=env, start_new_session=True)
        try:
            return child.wait(timeout=240 if args.accessibility else 1800)
        except subprocess.TimeoutExpired:
            print(f'Preview timeout: owned xcodebuild pid/pgid={child.pid}; result={result_path}', flush=True)
            os.killpg(child.pid, signal.SIGTERM)
            try:
                child.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait()
            return 124
    finally:
        if running:server.shutdown()
        server.server_close();smoke.cleanup()
        if args.accessibility:
            subprocess.run(['xcrun','simctl','ui',OWNED_SIM,'appearance','light'],check=True)
            subprocess.run(['xcrun','simctl','ui',OWNED_SIM,'content_size','large'],check=True)
        print(f'Preview cleanup: source/admission/processing off; fictional sessions revoked; report {REPORT}',flush=True)
if __name__=='__main__':
    raise SystemExit(main())
