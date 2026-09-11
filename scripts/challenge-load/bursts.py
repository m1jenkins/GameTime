#!/usr/bin/env python3
"""Simultaneous foreground sessions and a 250-person community admission storm."""
from __future__ import annotations
import argparse,concurrent.futures,json,threading,time
from oracles import load_live,check_preflight,postflight,response_errors
from lab import Lab,save,digest
from runner import Client,percentile
from fixtures import q

def run(lab,name,kind):
    destination=lab.data/name;destination.mkdir(mode=0o700)
    live=load_live(lab);receipt=check_preflight(lab,live);client=Client(lab)
    people=100 if kind=='foreground' else 250
    barrier=threading.Barrier(people+1,timeout=30)
    events=[];lock=threading.Lock();responses={};errors=[];stop=threading.Event()
    started=time.monotonic();unix=time.time()
    event_file=(destination/'events.jsonl').open('x',buffering=1)
    def invoke(number):
        actor=number if kind=='foreground' else 100+number
        barrier.wait()
        if kind=='foreground':
            # Matches the native sequential sections plus access/catalog refresh shape.
            requests=[('section_'+section,'challenge_section_v1',{'p_section':section,'p_limit':10}) for section in ['action','active','upcoming','history']]
            requests += [('access','challenge_access_status_v1',{}),('catalog','challenge_community_catalog_v1',{})]
        else:
            requests=[('join','challenge_command_v1',{'p_request_id':lab.uid('join-'+name,actor),'p_payload':{'op':'join_community','id':live['community'],'digest':live['community_digest'],'consent':True}})]
        for label,operation,payload in requests:
            if stop.is_set():return
            dispatch=time.monotonic()-started
            sample,body=client.request(operation,payload,actor)
            violations=response_errors(lab,live,label,payload,actor,body) if kind=='foreground' and sample['status']==200 else []
            if violations:stop.set()
            event={'actor_ordinal':actor,'operation':label,'dispatch_seconds':dispatch,'finish_seconds':time.monotonic()-started,
                   'oracle_failures':violations,
                   'expected_capacity':isinstance(body,dict) and body.get('message')=='challenge_capacity' and sample['code']=='23505',**sample}
            with lock:
                events.append(event);event_file.write(json.dumps(event,separators=(',',':'))+'\n')
                if kind=='join':responses[actor]=(sample,body,payload)
    with concurrent.futures.ThreadPoolExecutor(max_workers=people) as executor:
        futures=[executor.submit(invoke,n) for n in range(people)]
        try:barrier.wait()
        except threading.BrokenBarrierError:errors.append('foreground_generator_barrier_failed')
        for future in futures:
            try:future.result(timeout=120)
            except Exception as e:errors.append(type(e).__name__)
    event_file.close()
    accepted=[e for e in events if e['status']==200]
    expected_capacity=[e for e in events if e['expected_capacity']] if kind=='join' else []
    unexpected=[e for e in events if e['status']!=200 and e not in expected_capacity]
    oracles={'response_invariants':not any(e['oracle_failures'] for e in events)}
    if kind=='join' and not errors:
        oracles['exactly_100_admissions']=len(accepted)==100
        oracles['exactly_150_capacity_refusals']=len(expected_capacity)==150
        count=int(lab.sql('select count(*) from app.challenge_members_v1 where challenge_id=%s and exited_at is null;'%q(live['community']),'storm-roster'))
        oracles['capacity_never_widened']=count==100
        replay_checks=[]
        for actor,(sample,body,payload) in sorted(responses.items()):
            if sample['status']==200:
                replay_sample,replay=client.request('challenge_command_v1',payload,actor)
                replay_checks.append(replay_sample['status']==200 and replay==body)
        oracles['all_winners_exact_retry']=len(replay_checks)==100 and all(replay_checks)
        journal_count=int(lab.sql('select count(*) from app.challenge_requests_v1 where request_id in (%s);'%','.join(q(lab.uid('join-'+name,n)) for n in range(100,350)),'storm-journal'))
        oracles['one_journal_per_admitted_request']=journal_count==100
    else:
        oracles['100_distinct_sessions_completed_six_calls']=len(events)==600 and len({e['actor_ordinal'] for e in events})==100
    offered=people*(6 if kind=='foreground' else 1)
    try:postflight(lab,receipt,destination/'postflight.json');oracles['postflight']=True
    except Exception as error:oracles['postflight']=False;errors.append('postflight_'+type(error).__name__)
    summary={'kind':kind,'parent':lab.m['parent'],'project':lab.m['project'],'start_unix':unix,'finish_unix':time.time(),
      'preflight_sha256':digest(lab.data/('preflight-'+str(live['accounts'])+'.json')),'harness_sha256':digest(__file__),
      'offered_sessions':people,'offered_requests':offered,'completed_requests':len(events),'generator_dropped_requests':offered-len(events),
      'accepted':len(accepted),'expected_capacity_refusals':len(expected_capacity),'unexpected_failures':len(unexpected),'generator_errors':errors,
      'oracles':oracles,'session_first_arrival_spread_seconds':max((e['dispatch_seconds'] for e in events if e['operation'] in ('section_action','join')),default=0)-min((e['dispatch_seconds'] for e in events if e['operation'] in ('section_action','join')),default=0),
      'latency_seconds':{'p50':percentile([e['seconds'] for e in events],.5),'p95':percentile([e['seconds'] for e in events],.95),'p99':percentile([e['seconds'] for e in events],.99)},
      'passed':not errors and not unexpected and all(oracles.values())}
    save(destination/'summary.json',summary);print(json.dumps(summary))
    if not summary['passed']:raise SystemExit(1)

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('run_root');parser.add_argument('kind',choices=['foreground','join']);parser.add_argument('--name',required=True)
    args=parser.parse_args()
    if not args.name.replace('-','').isalnum():raise ValueError('simple burst name required')
    run(Lab(args.run_root),args.name,args.kind)
if __name__=='__main__':main()
