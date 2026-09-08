#!/usr/bin/env python3
"""Real multi-session SQL races on the b7-owned disposable project only.
Fictional SQL-role actors are not native/Auth-server or physical-device evidence.
No resets, hosted connections, raw Health inputs or legacy deletions.
"""
import argparse
import json
import os
from pathlib import Path
import select
import subprocess
import time
import uuid

DB = 'postgresql://postgres:postgres@127.0.0.1:58322/postgres'
STACK = Path('/tmp/gametime-finish-b7-stack')
ROOT = Path(__file__).resolve().parents[1]

def literal(value):
    return "'" + str(value).replace("'", "''") + "'"

def sql(source, check=True):
    return subprocess.run(['psql', DB, '-XqAt', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=sqlstate'], input=source, text=True, capture_output=True, check=check)

def value(source):
    return sql(source).stdout.strip()

def auth(actor, session, source):
    claims = json.dumps({'sub': actor, 'session_id': session})
    return f"begin; select set_config('request.jwt.claims',{literal(claims)},true); set local role authenticated; {source}; commit;"

def call(actor, session, request, payload):
    return auth(actor, session, f"select public.challenge_command_v1('{request}',{literal(json.dumps(payload))}::jsonb)->>'status'")

class Held:
    def __init__(self, source):
        self.process = subprocess.Popen(['psql', DB, '-XqAt', '-v', 'ON_ERROR_STOP=1'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
        self.process.stdin.write('begin; '+source+';\n'); self.process.stdin.flush()
        if not select.select([self.process.stdout], [], [], 10)[0] or self.process.stdout.readline().strip() != '1':
            self.process.kill(); raise RuntimeError('Could not establish owned lock')
    def release(self, extra=''):
        self.process.stdin.write(extra+'; commit;\n\\q\n'); self.process.stdin.flush()
        _, err = self.process.communicate(timeout=15)
        assert self.process.returncode == 0, err

def contender(source, name):
    env = os.environ.copy(); env['PGAPPNAME'] = name
    process = subprocess.Popen(['psql', DB, '-XqAt', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=sqlstate'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    process.stdin.write(source); process.stdin.close(); process.stdin = None
    return process

def blocked(names):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        n = value('select count(*) from pg_stat_activity where application_name in ('+','.join(map(literal,names))+') and cardinality(pg_blocking_pids(pid))>0;')
        if int(n) == len(names): return True
        time.sleep(0.02)
    return False

def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--owned-project', required=True)
    args = parser.parse_args()
    assert args.owned_project == 'gametime-finish-b7'
    assert 'project_id = "gametime-finish-b7"' in (STACK/'supabase/config.toml').read_text()
    assert value('select not admission and not fixtures and not processing and cardinality(actors)=0 from app.challenge_runtime_v1 where singleton;') == 't', 'Owned native/preview run must finish first'
    actors = [str(uuid.uuid4()) for _ in range(24)]
    sessions = [str(uuid.uuid4()) for _ in actors]
    checks = []
    def check(condition, label):
        assert condition, label
        checks.append(label); print('PASS: '+label, flush=True)
    actor_array = 'array['+','.join(literal(a)+'::uuid' for a in actors)+']'
    def clock(admission=True):
        sql(f"select public.challenge_runtime_v1({str(admission).lower()},true,true,{actor_array},'2026-10-01T00:00Z');")
    try:
        for a,s in zip(actors,sessions):
            sql(f"insert into auth.users(id) values('{a}'); insert into public.profiles(id,handle,display_name,timezone) values('{a}','raceb7_{uuid.uuid4().hex[:12]}','Fictional race','UTC'); insert into auth.sessions(id,user_id) values('{s}','{a}');")
        clock()
        for a,s in zip(actors,sessions):
            sql(f"select public.challenge_readiness_fixture_v1('{a}');")
            sql(auth(a,s,f"select public.challenge_confirm_age_v1('{uuid.uuid4()}',true)"))
        config = {'start_date':'2026-10-03','days':1,'timezone':'UTC','amount_cents':100}
        a,s = actors[0],sessions[0]
        def personal():
            preview = value(auth(a,s,f"select public.challenge_personal_preview_v1('personal_steps_goal_v1',{literal(json.dumps(config))}::jsonb,100)->>'digest'" )).splitlines()[-1]
            return {'op':'personal_commit','policy':'personal_steps_goal_v1','config':config,'target':100,'digest':preview,'consent':True}
        for _ in range(2): sql(call(a,s,str(uuid.uuid4()),personal()))
        payloads = [personal(),personal()]; requests = [str(uuid.uuid4()),str(uuid.uuid4())]
        sources = [call(a,s,r,p) for r,p in zip(requests,payloads)]
        names = ['beta_b7_admission_'+uuid.uuid4().hex for _ in sources]
        hold = Held('select 1 from app.challenge_runtime_v1 where singleton for update')
        children = [contender(source,name) for source,name in zip(sources,names)]
        try: check(blocked(names), 'both admission requests actually wait on the shared lock')
        finally: hold.release()
        results = [child.communicate(timeout=20) for child in children]
        check(sorted(child.returncode == 0 for child in children) == [False,True], 'only one of the simultaneous third/fourth commitments admits')
        winner = next(i for i,c in enumerate(children) if c.returncode == 0)
        check('23505' in results[1-winner][1], 'losing admission has the capacity SQLSTATE')
        check(value(f"select count(*) from app.challenge_slots_v1 where actor_id='{a}';") == '3', 'aggregate three-slot bound persists')
        clock(False)
        check(sql(sources[winner],False).returncode == 0, 'exact winning request recovers while admission is paused')
        changed = dict(payloads[winner],target=101)
        check('22023' in sql(call(a,s,requests[winner],changed),False).stderr, 'changed payload cannot reuse an admitted request')
        clock()
        created = value(auth(a,s,f"select public.challenge_mutate_v1('{uuid.uuid4()}',{literal(json.dumps({'op':'create','config':config}))}::jsonb)->>'id'")).splitlines()[-1]
        token = value(auth(a,s,f"select public.challenge_issue_link_v1('{uuid.uuid4()}','{created}')->>'token'")).splitlines()[-1]
        for i in range(1,20): sql(call(actors[i],sessions[i],str(uuid.uuid4()),{'op':'redeem_link','token':token}))
        names = ['beta_b7_redemption_'+uuid.uuid4().hex for _ in range(2)]
        hold = Held('select 1 from app.challenge_runtime_v1 where singleton for update')
        children = [contender(call(actors[i],sessions[i],str(uuid.uuid4()),{'op':'redeem_link','token':token}),name) for i,name in zip([20,21],names)]
        try: check(blocked(names), 'both final-link-slot requests actually overlap')
        finally: hold.release()
        results = [child.communicate(timeout=20) for child in children]
        check(sorted(child.returncode == 0 for child in children) == [False,True], 'exactly one twentieth unique account redeems')
        check(value(f"select count(*) from app.challenge_redemptions_v1 r join app.challenge_links_v1 l on l.id=r.link_id where l.challenge_id='{created}';") == '20', 'link ceiling remains twenty under concurrency')
        check(value(f"select count(*) from public.friendships where user_a='{a}' or user_b='{a}';") == '0', 'redemption creates no friendship')
        check(value(f"select count(*) from app.challenge_slots_v1 where challenge_id='{created}';") == '0', 'redemption creates no participation slot')
        check(value(f"select count(*) from app.challenge_members_v1 where challenge_id='{created}' and selected;") == '1', 'only the creator is selected after redemptions')
        # Session deletion wins while the challenge request waits on its share lock.
        i = 23; request = str(uuid.uuid4()); name = 'beta_b7_revocation_'+uuid.uuid4().hex
        hold = Held(f"select 1 from auth.sessions where id='{sessions[i]}' for update")
        child = contender(call(actors[i],sessions[i],request,{'op':'create','config':config}),name)
        try: check(blocked([name]), 'request waits behind actual session revocation')
        finally: hold.release(f"delete from auth.sessions where id='{sessions[i]}'")
        _, err = child.communicate(timeout=20)
        check(child.returncode != 0 and '42501' in err, 'revoked session cannot commit waiting request')
        check(value(f"select count(*) from app.challenge_requests_v1 where request_id='{request}';") == '0', 'revocation leaves no committed mutation receipt')
        output = ROOT/'tmp/beta-concurrency-report.json'; output.parent.mkdir(exist_ok=True)
        output.write_text(json.dumps({'evidence':'real concurrent SQL sessions; fictional SQL-role actors','checks':checks,'count':len(checks)},indent=2)+'\n')
    finally:
        sql("select public.challenge_discovery_fixture_v1(false); select public.challenge_runtime_v1(false,false,false,'{}',null);")
        sql('delete from auth.sessions where user_id=any('+actor_array+');')
        print('Owned gates disabled and fictional race sessions revoked; no legacy rows deleted.',flush=True)
if __name__ == '__main__': main()
