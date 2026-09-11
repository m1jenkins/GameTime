#!/usr/bin/env python3
"""Short P4 comparison using P2's unchanged HTTP client and arrival accounting.

Only the two explicitly named, task-owned loopback stacks are accepted. The
baseline uses its original batch RPC; P4 uses the shipped claim/complete driver.
"""
import concurrent.futures
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import threading
import time
import uuid

from arrivals import execute
from runner import Client, percentile
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from challenge_worker import run_once

ROOT = Path('/private/tmp/gametime-p4-final-20260911')
NAMESPACE = uuid.UUID('6550acf2-4528-4587-83ae-8d2dfaaeb3a4')


class Connection:
    def __init__(self, port):
        self.process = subprocess.Popen(['psql', '-XqAt', '-v', 'ON_ERROR_STOP=1',
            f'postgresql://postgres:postgres@127.0.0.1:{port}/postgres'], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            env={k:v for k,v in os.environ.items() if not k.startswith('PG')})

    def query(self, sql):
        self.process.stdin.write(sql+';\n\\echo p4_end\n')
        self.process.stdin.flush()
        lines = []
        for line in self.process.stdout:
            if line.strip() == 'p4_end': return '\n'.join(lines).strip()
            lines.append(line.rstrip())
        raise RuntimeError(self.process.stderr.read())

    def close(self):
        self.process.stdin.close()
        self.process.wait(timeout=5)


class Lab:
    def __init__(self, lane):
        self.lane = lane
        stack = ROOT / ('baseline' if lane == 'baseline' else 'stack')
        project = 'gametime-p4-'+('baseline' if lane == 'baseline' else 'final')+'-20260911'
        assert f'project_id = "{project}"' in (stack/'supabase/config.toml').read_text()
        self.port = 59522 if lane == 'baseline' else 59422
        self.m = {'api_port': self.port-1, 'project':project}
        self.container = 'supabase_db_'+project
        log = (ROOT/('baseline-start.log' if lane == 'baseline' else 'start.log')).read_text()
        self.credentials = json.JSONDecoder().raw_decode(log[log.index('{\n  "ANON_KEY"'):])[0]
        self.db = Connection(self.port)

    def uid(self, kind, index): return str(uuid.uuid5(NAMESPACE, f'{kind}:{index}'))

    def seed(self):
        actors = [self.uid('actor',i) for i in range(100)]
        rows = ','.join(f"('{a}'::uuid,'{self.uid('session',i)}'::uuid,{i})" for i,a in enumerate(actors))
        self.db.query(f"""begin;
         create temp table p4_actors as select * from (values {rows}) v(id,session_id,n);
         insert into auth.users(id) select id from p4_actors;
         insert into public.profiles(id,handle,display_name,timezone) select id,'p4load'||n,'Fictional load','UTC' from p4_actors;
         insert into auth.sessions(id,user_id) select session_id,id from p4_actors;
         select public.challenge_runtime_v1(true,true,true,array(select id from p4_actors),'2026-10-01T00:00Z');
         select set_config('app.challenge_write_v1','on',true);
         insert into app.challenge_age_v1 select id,'age_21_v1','2026-10-01' from p4_actors;
         insert into app.challenge_access_v1 select id,'2026-10-01' from p4_actors;
         commit""")
        # The P2 repeated-cancelled-work fixture: one expired unfrozen draft per creator.
        rows = ','.join(f"('{self.uid('due-draft',i)}'::uuid,'{a}'::uuid)" for i,a in enumerate(actors))
        self.db.query(f"""begin; select set_config('app.challenge_write_v1','on',true);
         insert into app.challenge_lobbies_v1(id,creator_id,policy,config,starts_at,ends_at,status,created_at)
         select id,actor,'friend_steps_goal_v1',app.challenge_window_v1('{{"start_date":"2026-09-28","days":1,"timezone":"UTC","amount_cents":100}}','2026-09-25'),
          '2026-09-28','2026-09-29','lobby_open','2026-09-25' from (values {rows}) v(id,actor);
         insert into app.challenge_members_v1(challenge_id,actor_id,selected)
          select id,creator_id,true from app.challenge_lobbies_v1;
         commit""")


# Actual tuple owners, plus scoped advisory owners and wait starts. A sampled
# residence is bounded by the adjacent absent observations, not an exact timer.
SAMPLE = """with owners as materialized (
 select 'runtime' scope,unnest(pids) pid from extensions.pgrowlocks('app.challenge_runtime_v1')
 union all select 'session',unnest(pids) from extensions.pgrowlocks('auth.sessions')
 union all select 'advisory',pid from pg_locks where locktype='advisory' and granted
), active as materialized (select * from pg_stat_activity where datname=current_database() and pid<>pg_backend_pid())
select jsonb_build_object('at',extract(epoch from clock_timestamp()),
 'owners',(select coalesce(jsonb_agg(distinct jsonb_build_array(o.scope,o.pid,a.xact_start)),'[]') from owners o join active a using(pid) where a.xact_start is not null),
 'waits',(select coalesce(jsonb_agg(jsonb_build_object('pid',l.pid,'type',l.locktype,'wait_ms',extract(epoch from clock_timestamp()-l.waitstart)*1000)),'[]') from pg_locks l join active a using(pid) where not l.granted))"""


def run(lab, client, kind, label):
    destination = ROOT / (lab.lane+'-'+kind+'-'+label)
    destination.mkdir()
    stopped = threading.Event()
    samples = []
    def observe():
        connection = Connection(lab.port)
        try:
            while not stopped.is_set():
                samples.append(json.loads(connection.query(SAMPLE)))
                stopped.wait(.002)
        finally: connection.close()
    observer = threading.Thread(target=observe)
    observer.start()
    since = time.time()
    events = []
    start = time.monotonic()
    if kind == 'foreground':
        barrier = threading.Barrier(33)
        def foreground(actor):
            barrier.wait()
            rows = []
            for section in ('action','active','upcoming','history','access','catalog'):
                op = 'challenge_section_v1' if section not in ('access','catalog') else 'challenge_access_status_v1' if section=='access' else 'challenge_community_catalog_v1'
                payload = {'p_section':section,'p_limit':10} if op=='challenge_section_v1' else {}
                sample, _ = client.request(op,payload,actor)
                rows.append(dict(sample,operation=section,actor=actor))
            return rows
        with concurrent.futures.ThreadPoolExecutor(max_workers=32) as pool:
            futures = [pool.submit(foreground,i) for i in range(32)]
            barrier.wait()
            for future in futures: events.extend(future.result())
        elapsed = time.monotonic()-start
        result = {'completed':len(events),'failed':sum(e['status']!=200 for e in events),'elapsed_seconds':elapsed,'completed_rps':len(events)/elapsed}
    else:
        def perform(index):
            part = index%4
            if part == 1:
                begin = time.perf_counter()
                run_id = lab.uid('bench-worker',index)
                if lab.lane=='baseline':
                    sample, body = client.request('challenge_run_batch_v1',{'p_run_id':run_id,'p_limit':20},service=True)
                else:
                    body = run_once(lambda op,payload:client.require(op,payload,service=True),run_id,20)
                    sample = {'status':200,'seconds':time.perf_counter()-begin}
                return dict(sample,operation='worker',processed=len(body.get('processed',[])),oracle_failures=[] if body.get('failed_count')==0 else ['worker_failure'])
            op = 'challenge_operations_status_v1' if part==2 else 'challenge_section_v1'
            payload = {} if part==2 else {'p_section':'action' if part==0 else 'active','p_limit':10}
            sample,_ = client.request(op,payload,index%100,service=part==2)
            return dict(sample,operation='status' if part==2 else 'read')
        result,events = execute([(10,50)],32,perform,lambda event:None)
    stopped.set(); observer.join(timeout=10)
    assert not observer.is_alive()
    logs = subprocess.check_output(['docker','logs','--since',str(since),lab.container],stderr=subprocess.STDOUT,text=True)
    waits = [float(n) for n in re.findall(r'process \d+ acquired .*? after ([0-9.]+) ms',logs)]
    lock_lines = [line for line in logs.splitlines() if 'still waiting for' in line or 'acquired' in line or 'deadlock detected' in line]
    (destination/'lock-waits.log').write_text('\n'.join(lock_lines)+'\n')
    (destination/'events.json').write_text(json.dumps(events,indent=2))
    (destination/'locks.json').write_text(json.dumps(samples))
    result.update(http_p50_ms=percentile([e['seconds']*1000 for e in events if 'seconds' in e],.5),http_p95_ms=percentile([e['seconds']*1000 for e in events if 'seconds' in e],.95),
        lock_wait_count=len(waits),lock_wait_p95_ms=percentile(waits,.95),lock_wait_max_ms=max(waits,default=0),
        sampled_wait_count=sum(len(s['waits']) for s in samples),deadlocks=logs.count('deadlock detected'),worker_entries=sum(e.get('processed',0) for e in events))
    # Adjacent sampling times bound observed lock residence per transaction.
    active = {}; holds = []; previous = samples[0]['at'] if samples else 0
    for sample in samples:
        now = sample['at']; owners = {tuple(o) for o in sample['owners']}
        for key in list(active):
            if key not in owners:
                before,first,last = active.pop(key)
                holds.append({'scope':key[0],'lower_ms':(last-first)*1000,'upper_ms':(now-before)*1000})
        for key in owners:
            if key in active: active[key][2] = now
            else: active[key] = [previous,now,now]
        previous = now
    result['lock_residence'] = {scope:{'observed_transactions':len(rows),'lower_p95_ms':percentile([r['lower_ms'] for r in rows],.95),'upper_p95_ms':percentile([r['upper_ms'] for r in rows],.95)}
        for scope in ('runtime','session','advisory') if (rows:=[r for r in holds if r['scope']==scope])}
    result['sample_interval_p95_ms'] = percentile([(b['at']-a['at'])*1000 for a,b in zip(samples,samples[1:])],.95)
    if kind=='worker':
        result['fixture_postflight'] = json.loads(lab.db.query("""select jsonb_build_object(
         'cancelled', (select count(*) from app.challenge_lobbies_v1 where status='cancelled'),
         'remaining_due_inventory',(select count(*) from app.challenge_work_v1() where due_at<=app.challenge_now_v1()),
         'unique_completed_challenges',(select count(distinct id) from (
          select entry->>'id' id from app.challenge_worker_runs_v1 r cross join lateral jsonb_array_elements(coalesce(r.result->'processed','[]')) entry
          union all select result->>'id' from app.challenge_worker_runs_v1 where payload->>'version'='challenge_complete_claim_v1') processed))"""))
        if lab.lane=='p4':
            assert result['fixture_postflight']=={'cancelled':100,'remaining_due_inventory':0,'unique_completed_challenges':100}
    (destination/'summary.json').write_text(json.dumps(result,indent=2))
    print(lab.lane,kind,json.dumps(result),flush=True)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--label',required=True)
    args=parser.parse_args()
    assert re.fullmatch('[a-z0-9-]+',args.label)
    for lane in ('baseline','p4'):
        lab = Lab(lane)
        lab.seed()
        client = Client(lab)
        for kind in ('foreground','worker'): run(lab,client,kind,args.label)
        lab.db.query("select public.challenge_runtime_v1(false,false,false,'{}',null)")
        lab.db.close()


if __name__ == '__main__': main()
