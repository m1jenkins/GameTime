#!/usr/bin/env python3
"""Production Swift-client HTTP acceptance on the b7-owned disposable stack.
No hosted target, mail, Health inputs or pre-existing Simulator control.
Secrets stay in an ignored, mode-0600 manifest and are removed on cleanup.
"""
import argparse
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
STACK = Path('/tmp/gametime-finish-b7-stack')
DB = 'postgresql://postgres:postgres@127.0.0.1:58322/postgres'
MANIFEST = ROOT / 'tmp/beta-native-smoke.json'
REPORT = ROOT / 'tmp/beta-native-smoke-report.json'
OWNED_SIM = '72A3249A-2DE0-4695-AF41-DCD2743B4666'

def sql(statement):
    return subprocess.run(['psql', DB, '-XAt', '-v', 'ON_ERROR_STOP=1'], input=statement, text=True, capture_output=True, check=True).stdout.strip()

def local_http(method, path, headers, body=None):
    conn = http.client.HTTPConnection('127.0.0.1', 58321, timeout=30)
    try:
        conn.request(method, path, body, headers)
        res = conn.getresponse()
        return res.status, res.read()
    finally:
        conn.close()

class Smoke:
    def __init__(self):
        assert 'project_id = "gametime-finish-b7"' in (STACK/'supabase/config.toml').read_text()
        settings = json.loads(subprocess.check_output(['supabase', 'status', '--workdir', str(STACK), '-o', 'json'], stderr=subprocess.DEVNULL))
        assert settings['API_URL'] == 'http://127.0.0.1:58321' and settings['DB_URL'] == DB
        self.key = settings['PUBLISHABLE_KEY']
        self.admin = {'apikey': settings['SERVICE_ROLE_KEY'], 'Authorization': 'Bearer '+settings['SERVICE_ROLE_KEY'], 'Content-Type': 'application/json'}
        self.password = secrets.token_urlsafe(28)
        self.control = secrets.token_urlsafe(32)
        self.actors = []
        self.trace = []
        self.lose = None
        self.owned = False
    def setup(self):
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
            sql(f"select public.challenge_readiness_fixture_v1('{actor['id']}');")
        MANIFEST.parent.mkdir(exist_ok=True)
        with MANIFEST.open('x') as stream:
            os.chmod(MANIFEST,0o600)
            json.dump({'url':'http://127.0.0.1:58339','key':self.key,'controlToken':self.control,'password':self.password,'actors':self.actors},stream)
    def clock(self, value, admission=True, processing=True):
        # Caller values are parsed before SQL interpolation.
        from datetime import datetime
        datetime.fromisoformat(value.replace('Z','+00:00'))
        ids=','.join("'"+a['id']+"'::uuid" for a in self.actors)
        sql(f"select public.challenge_runtime_v1({str(admission).lower()},true,{str(processing).lower()},array[{ids}],'{value}');")
    def control_call(self, body):
        action=body['action']
        if action=='lose':
            assert body['rpc']=='challenge_mutate_v1'
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
        elif action=='snapshot':
            return {'trace':self.trace}
        else:
            raise ValueError('Unknown control')
        return {'ok':True}
    def cleanup(self):
        if self.owned:
            sql("select public.challenge_runtime_v1(false,false,false,'{}',null);")
        for actor in self.actors:
            # Only this run's fictional actors, never another effort's sessions.
            local_http('PUT','/auth/v1/admin/users/'+actor['id'],self.admin,json.dumps({'password':secrets.token_urlsafe(48),'ban_duration':'876000h'}))
            sql(f"delete from auth.sessions where user_id='{actor['id']}'; delete from auth.refresh_tokens where user_id='{actor['id']}';")
        MANIFEST.unlink(missing_ok=True)
        REPORT.parent.mkdir(exist_ok=True)
        REPORT.write_text(json.dumps({'evidence':'authenticated production Swift client to fictional local backend','trace':self.trace,'gates_off':True,'actors_revoked':len(self.actors)},indent=2)+'\n')

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
    parser=argparse.ArgumentParser();parser.add_argument('--simulator',required=True)
    args=parser.parse_args();assert args.simulator==OWNED_SIM,'Only b7-owned Simulator is allowed'
    smoke=Smoke(); server=ThreadingHTTPServer(('127.0.0.1',58339),Handler);server.smoke=smoke
    running=False
    try:
        smoke.setup();threading.Thread(target=server.serve_forever,daemon=True).start();running=True
        result=subprocess.run(['xcodebuild','test','-project','ios/GameTime/GameTime.xcodeproj','-scheme','GameTime','-configuration','Debug','-destination',f'platform=iOS Simulator,id={OWNED_SIM}','-derivedDataPath','/tmp/gametime-finish-b7-derived','-parallel-testing-enabled','NO','-only-testing:GameTimeTests/ChallengeV1NativeSmokeTests','-only-testing:GameTimeTests/ChallengeV1NativeTests','-only-testing:GameTimeTests/WeeklySocialRefreshAuthRaceTests','-only-testing:GameTimeUITests/ChallengeV1UITests','CODE_SIGNING_ALLOWED=NO'],cwd=ROOT)
        return result.returncode
    finally:
        if running:server.shutdown()
        server.server_close();smoke.cleanup()
        print('B7 cleanup: source/admission/processing off; fictional sessions revoked; report tmp/beta-native-smoke-report.json',flush=True)
if __name__=='__main__':
    raise SystemExit(main())
