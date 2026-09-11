#!/usr/bin/env python3
"""Deterministic SQL-session lock proofs, reusing existing Beta race interfaces."""
from __future__ import annotations
import argparse,json,os,pathlib,select,subprocess,time
from oracles import load_live
from lab import Lab,save,pg_environment,pg_arguments,identity_guard
from fixtures import q

def arguments(lab,name):return pg_arguments(lab.m['db_port'],name)+['-v','VERBOSITY=sqlstate']

class Held:
    def __init__(self,lab,sql,name):
        lab.check_owner()
        self.process=subprocess.Popen(arguments(lab,name),stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1,env=pg_environment())
        self.process.stdin.write(identity_guard(lab.cluster_id)+"begin; set local statement_timeout='10s'; "+sql+';\n');self.process.stdin.flush()
        if not select.select([self.process.stdout],[],[],10)[0] or self.process.stdout.readline().strip()!='1':
            self.process.terminate();self.process.communicate(timeout=5)
            raise RuntimeError('owned lock could not be established')

    def release(self,extra=''):
        self.process.stdin.write(extra+'; commit;\n\\q\n');self.process.stdin.flush()
        _,error=self.process.communicate(timeout=15)
        if self.process.returncode:raise RuntimeError('owned lock release failed SQLSTATE '+error.strip())

def contender(lab,actor,source,name):
    lab.check_owner()
    claims=json.dumps({'sub':lab.uid('actor',actor),'session_id':lab.uid('session',actor)})
    sql=identity_guard(lab.cluster_id)+"begin; set local statement_timeout='15s'; set local request.jwt.claims=%s; set local role authenticated; %s; commit;"%(q(claims),source)
    process=subprocess.Popen(arguments(lab,name),stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=pg_environment())
    process.started=time.monotonic()
    process.stdin.write(sql);process.stdin.close();process.stdin=None
    return process

def waiters(lab,names):
    deadline=time.monotonic()+8
    query="select coalesce(jsonb_agg(jsonb_build_object('pid',pid,'name',application_name,'wait_event_type',wait_event_type,'wait_event',wait_event,'blockers',pg_blocking_pids(pid))),'[]') from pg_stat_activity where application_name in (%s);"%','.join(map(q,names))
    while time.monotonic()<deadline:
        rows=json.loads(lab.sql(query,'race-waiters'))
        if len(rows)==len(names) and all(r['blockers'] for r in rows):return rows
        time.sleep(.05)
    raise AssertionError('all contenders must demonstrably block')

def finish(process):
    output,error=process.communicate(timeout=20)
    return {'exit_code':process.returncode,'sqlstate':error.strip(),'elapsed_seconds':time.monotonic()-process.started,
            'returned_rows':len(output.splitlines())}

def lock_graph(lab,prefix):
    return json.loads(lab.sql("select coalesce(jsonb_agg(jsonb_build_object('pid',pid,'name',application_name,'wait_event_type',wait_event_type,'wait_event',wait_event,'blockers',pg_blocking_pids(pid))),'[]') from pg_stat_activity where starts_with(application_name,%s);"%q(prefix),'race-full-graph'))

def run(lab,name):
    destination=lab.data/name;destination.mkdir(mode=0o700)
    started=time.time();records=[]
    live=load_live(lab)
    prefix='load-race-'+name
    # Unrelated challenge IDs, actors and session rows; only runtime is shared.
    holder=Held(lab,'select 1 from app.challenge_runtime_v1 where singleton for update',prefix+'-holder')
    names=[prefix+'-unrelated-'+str(i) for i in [1,2]]
    children=[]
    try:
        children=[contender(lab,i,"select public.challenge_detail_v1(%s)->>'status'"%q(live['personal'][str(i)]),n) for i,n in zip([1,2],names)]
        waiters(lab,names);graph=lock_graph(lab,prefix)
    finally:holder.release()
    results=[finish(p) for p in children]
    if not all(r['exit_code']==0 for r in results):raise AssertionError('unrelated canaries must complete')
    records.append({'proof':'unrelated actors/challenges wait on runtime','graph':graph,'results':results})
    # A session revoker ahead of the request forces that request to retain runtime while waiting.
    actor=1200 # isolated from the 0..99 foreground cohort and independent operator
    holder=Held(lab,"select 1 from auth.sessions where id=%s for update"%q(lab.uid('session',actor)),prefix+'-revoker')
    names=[prefix+'-session-waiter',prefix+'-runtime-canary']
    children=[]
    try:
        children.append(contender(lab,actor,"select public.challenge_access_status_v1()->>'admission'",names[0]))
        waiters(lab,[names[0]])
        children.append(contender(lab,1201,"select public.challenge_access_status_v1()->>'admission'",names[1]))
        waiters(lab,names);graph=lock_graph(lab,prefix)
    finally:
        # Expiring only this owned synthetic session models revocation without deleting other data.
        holder.release("update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id=%s"%q(lab.uid('session',actor)))
    results=[finish(p) for p in children]
    records.append({'proof':'session waiter holds runtime; winning revocation rejects request; unrelated canary then finishes','graph':graph,'results':results})
    save(destination/'partial-proof.json',{'records':records})
    # Restore the synthetic session solely for the continuing load, before leaving this check.
    lab.owner_sql("update auth.sessions set not_after=null where id=%s;"%q(lab.uid('session',actor)),'restore-race-session')
    if not (results[0]['exit_code']!=0 and '42501' in results[0]['sqlstate'] and results[1]['exit_code']==0):raise AssertionError('revocation ordering')
    if next(r for r in graph if r['name']==names[0])['pid'] not in next(r for r in graph if r['name']==names[1])['blockers']:
        raise AssertionError('unexpected competing load; isolated direct chain not established')
    save(destination/'proofs.json',{'started_unix':started,'finished_unix':time.time(),'parent':lab.m['parent'],
          'identity_method':'SQL-role authenticated requests with actual seeded auth.sessions; separate HTTP load covers gateway','records':records})
    print(json.dumps({'proofs':len(records),'passed':True,'elapsed_seconds':time.time()-started}))

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('run_root');parser.add_argument('--name',required=True)
    args=parser.parse_args()
    if not args.name.replace('-','').isalnum():raise ValueError('simple race name required')
    run(Lab(args.run_root),args.name)
if __name__=='__main__':main()
