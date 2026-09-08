#!/usr/bin/env python3
"""Foreground, fictional local preview; owns only b7 stack actors and Simulator.
No automatic consent, external network, source enabling, or legacy data cleanup.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import threading
import uuid
import http.client
import plistlib

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('beta_preview_support',ROOT/'scripts/beta-native-smoke.py')
support=importlib.util.module_from_spec(spec);spec.loader.exec_module(support)
APP=Path('/tmp/gametime-finish-b7-derived/Build/Products/Debug-iphonesimulator/GameTime.app')
BUNDLE='com.mjenkins.gametime.staging'

def manifest():
    value=json.loads(support.MANIFEST.read_text())
    assert value['url']=='http://127.0.0.1:58339'
    assert value.get('controllerKind') == 'preview', 'Use the foreground preview, not a test controller'
    return value

def validate_app(app):
    assert app.is_absolute() and app.is_dir(),'Choose an absolute Debug Simulator app path; see docs/BETA_REAL_VALIDATION_HANDOFF.md'
    info=plistlib.loads((app/'Info.plist').read_bytes())
    assert info.get('CFBundleIdentifier')==BUNDLE and info.get('DTPlatformName')=='iphonesimulator','Only the local Simulator app can be previewed'

def open_actor(number):
    value=manifest();actor=value['actors'][number-1]
    app=Path(value.get('appPath',str(APP)))
    validate_app(app)
    subprocess.run(['xcrun','simctl','install',support.OWNED_SIM,str(app)],check=True)
    subprocess.run(['xcrun','simctl','terminate',support.OWNED_SIM,BUNDLE],capture_output=True)
    env=os.environ.copy()
    env.update(SIMCTL_CHILD_GAMETIME_BETA_LOCAL_URL=value['url'],SIMCTL_CHILD_GAMETIME_BETA_LOCAL_KEY=value['key'],SIMCTL_CHILD_GAMETIME_BETA_LOCAL_EMAIL=actor['email'],SIMCTL_CHILD_GAMETIME_BETA_LOCAL_PASSWORD=value['password'])
    subprocess.run(['xcrun','simctl','launch',support.OWNED_SIM,BUNDLE,'--beta-challenges-local'],env=env,check=True)
    print(f'Fictional account {number} ready. Tap Sign in, then confirm age if asked. No consent was submitted.', flush=True)

def accounts():
    for i,actor in enumerate(manifest()['actors'],1):
        print(f'{i}: {actor["username"]}  ({actor["id"]})'+(' — independent operator' if i==7 else ''), flush=True)

def control(body):
    value=manifest();conn=http.client.HTTPConnection('127.0.0.1',58339,timeout=30)
    try:
        conn.request('POST','/__beta/control',json.dumps(body),{'Content-Type':'application/json','X-Beta-Control':value['controlToken']})
        response=conn.getresponse();data=response.read();assert response.status==200,'Local fixture action failed'
        print(data.decode())
    finally:conn.close()

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--owned-project',required=True,choices=['gametime-finish-b7'])
    sub=parser.add_subparsers(dest='command',required=True)
    serve=sub.add_parser('serve');serve.add_argument('--no-open',action='store_true');serve.add_argument('--app',type=Path,default=APP,help='Absolute Debug Simulator app bundle; retained for account switching')
    op=sub.add_parser('open');op.add_argument('--actor',type=int,choices=range(1,8),default=1)
    sub.add_parser('accounts')
    clock=sub.add_parser('clock');clock.add_argument('--to',required=True);clock.add_argument('--pause-admission',action='store_true');clock.add_argument('--pause-processing',action='store_true')
    progress=sub.add_parser('progress');progress.add_argument('--challenge',type=uuid.UUID,required=True);progress.add_argument('--actor',type=int,choices=range(1,8),required=True);progress.add_argument('--value',required=True,help='Canonical integer, or unknown; fictional values only')
    process=sub.add_parser('process');process.add_argument('--challenge',type=uuid.UUID,required=True)
    latest=sub.add_parser('latest');latest.add_argument('--actor',type=int,choices=range(1,8),default=1)
    sub.add_parser('lose-next-response')
    args=parser.parse_args()
    if args.command=='serve':
        validate_app(args.app)
        smoke=support.Smoke();server=support.ThreadingHTTPServer(('127.0.0.1',58339),support.Handler);server.smoke=smoke
        stopped=threading.Event();running=False
        for name in [signal.SIGINT,signal.SIGTERM]:signal.signal(name,lambda *_:stopped.set())
        try:
            smoke.setup()
            value=json.loads(support.MANIFEST.read_text());value['controllerKind']='preview';value['appPath']=str(args.app.resolve())
            support.MANIFEST.write_text(json.dumps(value))
            threading.Thread(target=server.serve_forever,daemon=True).start();running=True
            print('Local fictional preview active at October 1, 2026, 12:00 UTC. Keep this foreground terminal open.',flush=True)
            accounts()
            if not args.no_open:open_actor(1)
            while not stopped.wait(1):pass
        finally:
            if running:server.shutdown()
            server.server_close();smoke.cleanup()
            print('Preview stopped: fixture gates off, only preview sessions revoked. Database and historical rows retained.',flush=True)
        return
    if args.command=='open':open_actor(args.actor)
    elif args.command=='accounts':accounts()
    elif args.command=='clock':control({'action':'clock','now':args.to,'admission':not args.pause_admission,'processing':not args.pause_processing})
    elif args.command=='progress':control({'action':'capture','id':str(args.challenge),'actor':manifest()['actors'][args.actor-1]['id'],'value':None if args.value=='unknown' else int(args.value)})
    elif args.command=='process':control({'action':'process','id':str(args.challenge)})
    elif args.command=='latest':control({'action':'latest','actor':manifest()['actors'][args.actor-1]['id']})
    elif args.command=='lose-next-response':control({'action':'lose','rpc':'challenge_command_v1'})
if __name__=='__main__':main()
