#!/usr/bin/env python3
"""Minimal owner-operated CLI for the task-owned local Beta project.
Never accepts a hosted URL/key. Authenticated operators need explicit scopes;
service credentials are used only for local monitoring, worker and grants.
"""
import argparse
import getpass
import http.client
import json
import os
from pathlib import Path
import subprocess
import uuid
from challenge_worker import run_once

ROOT=Path(__file__).resolve().parents[1]
STACK=Path('/tmp/gametime-finish-b7-stack')

def request(path, body, headers, timeout=30):
    conn=http.client.HTTPConnection('127.0.0.1',58321,timeout=timeout)
    try:
        conn.request('POST',path,json.dumps(body),headers)
        response=conn.getresponse(); raw=response.read(); data=json.loads(raw) if raw else None
        if not 200<=response.status<300:
            raise RuntimeError('Local operation rejected: '+str(data.get('code',response.status) if isinstance(data,dict) else response.status))
        return data
    finally:conn.close()

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--owned-project',required=True)
    parser.add_argument('--local-actor',type=int,choices=range(1,8),help='Use an active fictional preview account; never a hosted account')
    parser.add_argument('--email',help='Local operator email; password is prompted without logging')
    sub=parser.add_subparsers(dest='command',required=True)
    sub.add_parser('status')
    run=sub.add_parser('run-once');run.add_argument('--run-id',required=True,type=uuid.UUID);run.add_argument('--limit',type=int,default=20,choices=range(1,51))
    grant=sub.add_parser('grant');grant.add_argument('--actor',required=True,type=uuid.UUID);grant.add_argument('--challenge',required=True,type=uuid.UUID);grant.add_argument('--capability',required=True,choices=['review','moderate']);grant.add_argument('--expires',required=True)
    for name in ['cases','reports']:
        p=sub.add_parser(name);p.add_argument('--challenge',required=True,type=uuid.UUID)
    resolve=sub.add_parser('resolve');resolve.add_argument('--challenge',required=True,type=uuid.UUID);resolve.add_argument('--review',required=True,type=uuid.UUID);resolve.add_argument('--decision',required=True,choices=['upheld','exclude']);resolve.add_argument('--request-id',required=True,type=uuid.UUID)
    for name in ['remove','suspend']:
        p=sub.add_parser(name);p.add_argument('--challenge',required=True,type=uuid.UUID);p.add_argument('--subject',required=True,type=uuid.UUID);p.add_argument('--reason',required=True,choices=['username','unwanted_contact','unsafe_behavior']);p.add_argument('--request-id',required=True,type=uuid.UUID)
    close=sub.add_parser('close-community');close.add_argument('--challenge',required=True,type=uuid.UUID);close.add_argument('--request-id',required=True,type=uuid.UUID)
    pub=sub.add_parser('publish-fixture');pub.add_argument('--operator',required=True,type=uuid.UUID);pub.add_argument('--config-file',required=True,type=Path);pub.add_argument('--target',required=True,type=int);pub.add_argument('--minimum',required=True,type=int);pub.add_argument('--capacity',required=True,type=int);pub.add_argument('--request-id',required=True,type=uuid.UUID);pub.add_argument('--fictional',action='store_true',required=True)
    args=parser.parse_args()
    assert args.owned_project=='gametime-finish-b7'
    assert 'project_id = "gametime-finish-b7"' in (STACK/'supabase/config.toml').read_text()
    settings=json.loads(subprocess.check_output(['supabase','status','--workdir',str(STACK),'-o','json'],stderr=subprocess.DEVNULL))
    assert settings['API_URL']=='http://127.0.0.1:58321' and settings['DB_URL']=='postgresql://postgres:postgres@127.0.0.1:58322/postgres'
    service=args.command in ['status','run-once','grant','publish-fixture']
    session=None
    if service:
        key=settings['SERVICE_ROLE_KEY'];headers={'apikey':key,'Authorization':'Bearer '+key,'Content-Type':'application/json'}
    else:
        key=settings['PUBLISHABLE_KEY'];headers={'apikey':key,'Content-Type':'application/json'}
        expected=None
        if args.local_actor:
            manifest=json.loads((ROOT/'tmp/beta-native-smoke.json').read_text())
            assert manifest['url']=='http://127.0.0.1:58339'
            actor=manifest['actors'][args.local_actor-1];email=actor['email'];password=manifest['password'];expected=actor['id']
        else:
            if not args.email:parser.error('Choose --local-actor or provide the local --email')
            email=args.email;password=getpass.getpass('Local operator password: ')
        session=request('/auth/v1/token?grant_type=password',{'email':email,'password':password},headers)
        if expected:assert session['user']['id']==expected
        headers['Authorization']='Bearer '+session['access_token']
    try:
        c=args.command
        if c=='run-once':
            print(json.dumps(run_once(lambda name,body: request('/rest/v1/rpc/'+name,body,headers,timeout=5),args.run_id,args.limit,scope={"version":"challenge_worker_scope_v1","kind":"due"}),indent=2))
            return
        if c=='status':name='challenge_operations_status_v1';body={}
        elif c=='grant':name='challenge_grant_operator_v1';body={'p_actor':str(args.actor),'p_id':str(args.challenge),'p_capability':args.capability,'p_expires':args.expires}
        elif c in ['cases','reports']:name='challenge_operator_'+c+'_v1';body={'p_id':str(args.challenge)}
        elif c=='close-community':name='challenge_operator_close_v1';body={'p_request_id':str(args.request_id),'p_id':str(args.challenge)}
        elif c=='publish-fixture':
            name='challenge_publish_community_fixture_v1';body={'p_request_id':str(args.request_id),'p_operator':str(args.operator),'p_config':json.loads(args.config_file.read_text()),'p_target':args.target,'p_minimum':args.minimum,'p_capacity':args.capacity,'p_fixture_only':True}
        else:
            name='challenge_operator_action_v1';payload={'op':c,'id':str(args.challenge)}
            if c=='resolve':payload.update(review_id=str(args.review),decision=args.decision)
            else:payload.update(actor_id=str(args.subject),reason=args.reason)
            body={'p_request_id':str(args.request_id),'p_payload':payload}
        print(json.dumps(request('/rest/v1/rpc/'+name,body,headers),indent=2))
    finally:
        if session:
            # End only this CLI's session, not another native user's session.
            conn=http.client.HTTPConnection('127.0.0.1',58321,timeout=30)
            try:
                conn.request('POST','/auth/v1/logout?scope=local','{}',headers);response=conn.getresponse();response.read()
                if response.status!=204:raise RuntimeError('Local operator logout failed')
            finally:conn.close()
if __name__=='__main__':main()
