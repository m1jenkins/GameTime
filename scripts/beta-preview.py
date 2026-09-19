#!/usr/bin/env python3
"""Foreground, fictional local preview; owns only its scoped stack actors and Simulator.
No automatic consent, external network, source enabling, or legacy data cleanup.
"""
import argparse
from datetime import date, datetime, time, timedelta, timezone
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
from zoneinfo import ZoneInfo

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('beta_preview_support',ROOT/'scripts/beta-native-smoke.py')
support=importlib.util.module_from_spec(spec);spec.loader.exec_module(support)
if support.OWNED_PROJECT != 'gametime-finish-b7':
    support.MANIFEST = ROOT / f'tmp/beta-native-smoke-{support.OWNED_PROJECT}.json'
    support.REPORT = ROOT / f'tmp/beta-native-smoke-report-{support.OWNED_PROJECT}.json'
APP=Path(os.environ.get(
    'GAMETIME_BETA_PREVIEW_APP',
    f'/tmp/{support.OWNED_PROJECT}-derived/Build/Products/Debug-iphonesimulator/GameTime.app',
))
BUNDLE='com.mjenkins.gametime.staging'

def manifest():
    value=json.loads(support.MANIFEST.read_text())
    assert value['url']==f'http://127.0.0.1:{support.CONTROLLER_PORT}'
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

def control(body, announce=True):
    value=manifest();conn=http.client.HTTPConnection('127.0.0.1',support.CONTROLLER_PORT,timeout=30)
    try:
        conn.request('POST','/__beta/control',json.dumps(body),{'Content-Type':'application/json','X-Beta-Control':value['controlToken']})
        response=conn.getresponse();data=response.read();assert response.status==200,'Local fixture action failed'
        result=json.loads(data)
        if announce:print(json.dumps(result))
        return result
    finally:conn.close()

def challenge_state(challenge, actor):
    # Read only the selected fictional challenge. Mutations still use the
    # preview controller and the actor's authenticated public review command.
    cid=str(uuid.UUID(str(challenge)));aid=str(uuid.UUID(str(actor)))
    row=support.sql(f"""select json_build_object(
      'creator_id',c.creator_id,'policy',c.policy,'status',c.status,'revision',c.revision,
      'config',c.config,'created_at',c.created_at,'starts_at',c.starts_at,'ends_at',c.ends_at,
      'target',(select target from app.challenge_members_v1 where challenge_id=c.id and actor_id='{aid}'),
      'slots',(select count(*) from app.challenge_slots_v1 where challenge_id=c.id),
      'consents',(select count(*) from app.challenge_consents_v1 where challenge_id=c.id and version=c.agreement_version),
      'facts',(select coalesce(json_agg(row_to_json(f) order by f.revision),'[]'::json) from app.challenge_facts_v1 f where f.challenge_id=c.id and f.actor_id='{aid}'),
      'notice',(select row_to_json(n) from app.challenge_notices_v1 n where n.challenge_id=c.id order by n.revision desc limit 1),
      'review',(select row_to_json(r) from app.challenge_reviews_v1 r where r.challenge_id=c.id and r.actor_id='{aid}' order by r.filed_at desc limit 1),
      'resolution',(select row_to_json(s) from app.challenge_reviews_v1 r join app.challenge_resolutions_v1 s on s.review_id=r.id where r.challenge_id=c.id and r.actor_id='{aid}' order by r.filed_at desc limit 1),
      'final',(select row_to_json(f) from app.challenge_finals_v1 f where f.challenge_id=c.id),
      'now',(select fictional_now from app.challenge_runtime_v1 where singleton)
    ) from app.challenge_lobbies_v1 c where c.id='{cid}';""")
    if not row:raise ValueError('Challenge was not found in the selected local stack')
    return json.loads(row)

def instant(value):
    return datetime.fromisoformat(value.replace('Z','+00:00')).astimezone(timezone.utc)

def stamp(value):
    return value.astimezone(timezone.utc).isoformat().replace('+00:00','Z')

def lifecycle_times(row, actor):
    if row['creator_id'] != actor or row['policy'] != 'personal_steps_goal_v1' or row['status'] != 'scheduled':
        raise ValueError('Choose a scheduled personal steps goal created by this fictional account')
    config=row['config'];zone=ZoneInfo(config['timezone']);start_day=date.fromisoformat(config['start_date'])
    if config['days'] != 1:
        raise ValueError('This walkthrough requires one full local-calendar-day challenge')
    start=datetime.combine(start_day,time.min,zone).astimezone(timezone.utc)
    end=datetime.combine(start_day+timedelta(days=1),time.min,zone).astimezone(timezone.utc)
    created=instant(row['created_at'])
    if not 2 <= (start_day-created.astimezone(zone).date()).days <= 30:
        raise ValueError('The scheduled day must start 2–30 local calendar days after creation')
    if instant(row['starts_at']) != start or instant(row['ends_at']) != end:
        raise ValueError('The saved window must run from local midnight to the next local midnight')
    target=row['target']
    if type(target) is not int or not 1 <= target < 1000000000:
        raise ValueError('Choose a steps target that can be crossed by a downward correction')
    if row['slots'] != 1 or row['consents'] != 1 or row['facts'] or row['notice'] or row['review'] or row['final']:
        raise ValueError('Use a fresh scheduled goal with one explicit consent and no lifecycle records')
    if row['now'] is None or instant(row['now']) >= start:
        raise ValueError('The preview clock must still be before this challenge starts')
    return {'activity':start+(end-start)/2,'sync':end+timedelta(hours=12),
            'correction':end+timedelta(hours=36),'notice':end+timedelta(hours=80),
            'target':target}

def file_review(challenge, actor_number, revision, notice_revision):
    value=manifest();actor=value['actors'][actor_number-1]
    status,raw=support.local_http('POST','/auth/v1/token?grant_type=password',
        {'apikey':value['key'],'Content-Type':'application/json'},
        json.dumps({'email':actor['email'],'password':value['password']}))
    if status != 200:raise RuntimeError(f'Fictional account sign-in failed (HTTP {status})')
    token=json.loads(raw)['access_token']
    status,raw=support.local_http('POST','/rest/v1/rpc/challenge_command_v1',
        {'apikey':value['key'],'Authorization':'Bearer '+token,'Content-Type':'application/json'},
        json.dumps({'p_request_id':str(uuid.uuid4()),'p_payload':{
            'op':'review','id':str(challenge),'revision':revision,
            'notice_revision':notice_revision,'reason':'wrong_total'}}))
    if status != 200:raise RuntimeError(f'Fictional account review failed (HTTP {status})')
    return json.loads(raw)

def lifecycle(challenge, actor_number):
    value=manifest();actor=value['actors'][actor_number-1]['id'];cid=str(challenge)
    row=challenge_state(cid,actor);times=lifecycle_times(row,actor)
    ids=','.join("'"+item['id']+"'::uuid" for item in value['actors'])
    open_count=int(support.sql(f"""select count(distinct c.id) from app.challenge_lobbies_v1 c
      join app.challenge_members_v1 m on m.challenge_id=c.id
      where m.actor_id=any(array[{ids}]) and c.status not in ('final','cancelled','void');"""))
    if open_count != 1:
        raise ValueError('Use a fresh preview with only this open challenge; the fictional clock is shared')
    def move(at):control({'action':'clock','now':stamp(at)},False)
    def process():control({'action':'process','id':cid},False)
    def check(status):
        saved=challenge_state(cid,actor)
        if saved['status'] != status:raise RuntimeError(f'Expected {status}, got {saved["status"]}')
        return saved
    target=times['target']
    move(times['activity']);process();check('active')
    control({'action':'capture','id':cid,'actor':actor,'value':target+1},False)
    row=check('active')
    if [(f['revision'],f['value']) for f in row['facts']] != [(1,target+1)] or instant(row['facts'][0]['recorded_at']) != times['activity']:
        raise RuntimeError('Activity update was not saved at the scheduled time')
    print(f'Activity: {stamp(times["activity"])} — {target+1} steps saved')
    move(times['sync']);process();check('syncing')
    move(times['correction'])
    control({'action':'capture','id':cid,'actor':actor,'value':target-1},False)
    row=check('syncing')
    if [(f['revision'],f['value']) for f in row['facts']] != [(1,target+1),(2,target-1)] or instant(row['facts'][1]['recorded_at']) != times['correction']:
        raise RuntimeError('Downward correction was not saved at the expected time')
    print(f'Correction: {stamp(times["correction"])} — {target-1} steps saved as revision 2')
    move(times['notice']);process();row=check('review')
    notice=row['notice'];notice_at=instant(notice['recorded_at']);review_by=instant(notice['review_by'])
    if notice_at != times['notice'] or review_by != notice_at+timedelta(hours=48):raise RuntimeError('Notice review window was shortened')
    own=notice['result']['participants'][actor]
    if own['status'] != 'missed':raise RuntimeError('Corrected total did not change the provisional result')
    print(f'Notice: {stamp(notice_at)} — provisional {own["status"]}; review by {stamp(review_by)}')
    filed_at=review_by-timedelta(hours=1)
    move(filed_at);file_review(cid,actor_number,row['revision'],notice['revision']);row=check('review')
    review=row['review']
    if review is None or instant(review['filed_at']) != filed_at or instant(review['resolve_by']) != filed_at+timedelta(hours=72):
        raise RuntimeError('Review resolution window was shortened')
    print(f'Review: {stamp(filed_at)} — filed by account {actor_number}; resolve by {stamp(instant(review["resolve_by"]))}')
    move(review_by);process();row=check('review')
    if row['final'] is not None:raise RuntimeError('Pending review finalized at its notice deadline')
    control({'action':'resolve_challenge','id':cid},False);process();row=check('final')
    if (row['resolution']['decision'] != 'upheld' or row['resolution']['operator_id'] != value['actors'][6]['id']
            or instant(row['resolution']['recorded_at']) >= instant(review['resolve_by'])):
        raise RuntimeError('Independent fictional review was not recorded')
    result=row['final']['result'];own=result['participants'][actor]
    if (instant(row['final']['recorded_at']) != review_by or result != notice['result']
            or result['simulation'] != 'nonredeemable' or own['status'] != 'missed' or own['returned_cents'] != 0):
        raise RuntimeError('Final simulated result did not match the corrected total')
    print(f'Final: {stamp(instant(row["final"]["recorded_at"]))} — corrected goal missed; $0 simulated return. No real money moved.')

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--owned-project',required=True)
    sub=parser.add_subparsers(dest='command',required=True)
    serve=sub.add_parser('serve');serve.add_argument('--no-open',action='store_true');serve.add_argument('--app',type=Path,default=APP,help='Absolute Debug Simulator app bundle; retained for account switching')
    op=sub.add_parser('open');op.add_argument('--actor',type=int,choices=range(1,8),default=1)
    sub.add_parser('accounts')
    clock=sub.add_parser('clock');clock.add_argument('--to',required=True);clock.add_argument('--pause-admission',action='store_true');clock.add_argument('--pause-processing',action='store_true')
    progress=sub.add_parser('progress');progress.add_argument('--challenge',type=uuid.UUID,required=True);progress.add_argument('--actor',type=int,choices=range(1,8),required=True);progress.add_argument('--value',required=True,help='Canonical integer, or unknown; fictional values only')
    process=sub.add_parser('process');process.add_argument('--challenge',type=uuid.UUID,required=True)
    latest=sub.add_parser('latest');latest.add_argument('--actor',type=int,choices=range(1,8),default=1)
    journey=sub.add_parser('lifecycle',help='Run one consented fictional one-day personal steps goal through final review')
    journey.add_argument('--challenge',type=uuid.UUID,required=True)
    journey.add_argument('--actor',type=int,choices=range(1,7),default=1)
    sub.add_parser('lose-next-response')
    args=parser.parse_args()
    assert args.owned_project == support.OWNED_PROJECT, 'Owned project must match GAMETIME_BETA_PREVIEW_PROJECT'
    if args.command=='serve':
        if not args.no_open:validate_app(args.app)
        smoke=support.Smoke();server=support.ThreadingHTTPServer(('127.0.0.1',support.CONTROLLER_PORT),support.Handler);server.smoke=smoke
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
    elif args.command=='lifecycle':lifecycle(args.challenge,args.actor)
    elif args.command=='lose-next-response':control({'action':'lose','rpc':'challenge_command_v1'})
if __name__=='__main__':main()
