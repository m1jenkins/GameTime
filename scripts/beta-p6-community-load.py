#!/usr/bin/env python3
"""Short authenticated HTTP community arrival check; owned disposable local DB only."""
import argparse, base64, concurrent.futures, hashlib, hmac, json, pathlib, subprocess, time, urllib.error, urllib.request, uuid

def main():
    p=argparse.ArgumentParser();p.add_argument('--root',type=pathlib.Path,required=True);p.add_argument('--key',required=True);args=p.parse_args()
    config=(args.root/'stack/supabase/config.toml').read_text()
    assert 'project_id = "gametime-p6-20260912"' in config and 'port = 59722' in config
    assert args.root.resolve()==pathlib.Path('/private/tmp/gametime-p6-20260912')
    db='postgresql://postgres:postgres@127.0.0.1:59722/postgres';url='http://127.0.0.1:59721/rest/v1/rpc/'
    def sql(s):
        return subprocess.check_output(['psql',db,'-XqAt','-v','ON_ERROR_STOP=1'],input=s,text=True,timeout=40).strip()
    actors=[str(uuid.uuid4()) for _ in range(256)];sessions=[str(uuid.uuid4()) for _ in actors];requests=[str(uuid.uuid4()) for _ in actors]
    q=lambda s:"'"+str(s).replace("'","''")+"'"
    seed=['begin;']
    seed+=['insert into auth.users(id) values '+','.join('('+q(a)+')' for a in actors)+';']
    seed+=['insert into public.profiles(id,handle,display_name,timezone) values '+','.join(f'({q(a)},{q("p6_"+a.replace("-","")[:16])},\'Fictional P6\',\'UTC\')' for a in actors)+';']
    seed+=['insert into auth.sessions(id,user_id) values '+','.join(f'({q(s)},{q(a)})' for s,a in zip(sessions,actors))+';']
    seed += [f"select public.challenge_runtime_v1(true,true,true,array[{q(actors[255])}]::uuid[],'2026-10-01T12:00Z');", "select public.challenge_discovery_fixture_v1(true);select set_config('app.challenge_write_v1','on',true);"]
    seed += ['insert into app.challenge_age_v1 values '+','.join(f"({q(a)},'age_21_v1','2026-10-01T12:00Z')" for a in actors)+';']
    seed += ['insert into app.challenge_access_v1 values '+','.join(f"({q(a)},'2026-10-01T12:00Z')" for a in actors)+';']
    seed += ['insert into app.challenge_readiness_v1(actor_id,recorded_at,source,metric) values '+','.join(f"({q(a)},'2026-10-01T12:00Z','fictional_steps_v1','steps')" for a in actors)+';']
    seed += [f"select public.challenge_publish_community_fixture_v1('{uuid.uuid4()}',{q(actors[255])},'{{\"start_date\":\"2026-10-03\",\"days\":1,\"timezone\":\"UTC\",\"amount_cents\":100}}',100,2,250,true);",'commit;']
    result=sql('\n'.join(seed));cid=result.splitlines()[-1]
    digest=sql(f"select digest from app.challenge_agreements_v1 where challenge_id={q(cid)}")
    def jwt(i):
        enc=lambda v:base64.urlsafe_b64encode(json.dumps(v,separators=(',',':')).encode()).decode().rstrip('=')
        body=enc({'alg':'HS256','typ':'JWT'})+'.'+enc({'sub':actors[i],'session_id':sessions[i],'role':'authenticated','aud':'authenticated','exp':int(time.time())+3600,'iat':int(time.time())})
        return body+'.'+base64.urlsafe_b64encode(hmac.new(b'super-secret-jwt-token-with-at-least-32-characters-long',body.encode(),hashlib.sha256).digest()).decode().rstrip('=')
    def call(i,name,body):
        req=urllib.request.Request(url+name,json.dumps(body).encode(),{'Content-Type':'application/json','apikey':args.key,'Authorization':'Bearer '+jwt(i)})
        start=time.monotonic()
        try:
            with urllib.request.urlopen(req,timeout=30) as r:code=r.status;data=json.load(r)
        except urllib.error.HTTPError as e:code=e.code;data=json.load(e)
        return dict(index=i,status=code,data=data,ms=(time.monotonic()-start)*1000)
    def join(i):return call(i,'challenge_command_v1',{'p_request_id':requests[i],'p_payload':{'op':'join_community','id':cid,'digest':digest,'consent':True}})
    results=[];start=time.monotonic()
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=25) as pool:results=list(pool.map(join,range(250)))
        seconds=time.monotonic()-start
        (args.root/'load-arrivals.json').write_text(json.dumps(results,indent=2))
        assert all(r['status']==200 and r['data']['revision']==1 for r in results),[r for r in results if r['status']!=200]
        assert sql(f"select reserved from app.challenge_community_capacity_v1 where challenge_id={q(cid)}")=='250'
        extra=join(250);assert extra['status']==400 and extra['data']['message']=='challenge_join_closed',extra
        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:retries=list(pool.map(join,[0]*10))
        assert all(r['data']==results[0]['data'] for r in retries)
        own=call(0,'challenge_detail_v1',{'p_id':cid});assert own['data']['counts']['joined'] is None and len(own['data']['members'])==1
        # A safe exit frees exactly one slot. Two independent arrivals race for it.
        leave=call(0,'challenge_command_v1',{'p_request_id':str(uuid.uuid4()),'p_payload':{'op':'leave','id':cid,'revision':1}});assert leave['status']==200,leave
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:last=list(pool.map(join,[250,251]))
        assert sorted(x['status'] for x in last)==[200,400],last
        assert sql(f"select reserved from app.challenge_community_capacity_v1 where challenge_id={q(cid)}")=='250'
        assert sql(f"select count(*) from app.challenge_slots_v1 where challenge_id={q(cid)}")== '251'
        assert sql(f"select count(*) from app.challenge_slots_v1 s join app.challenge_members_v1 m using(challenge_id,actor_id) where s.challenge_id={q(cid)} and m.exited_at is null")== '250'
        # Gateway error status must commit unsuccessful token-attempt quota.
        rejected=[call(254,'challenge_redeem_link_v1',{'p_request_id':str(uuid.uuid4()),'p_token':'f'*64}) for _ in range(21)]
        assert rejected[-1]['status']==429,rejected[-1]
        assert sql(f"select used from app.challenge_quotas_v1 where actor_id={q(actors[254])} and bucket='redemption'")=='20'
        times=sorted(r['ms'] for r in results)
        summary=dict(arrivals=250,concurrency=25,seconds=seconds,per_second=250/seconds,p50_ms=times[124],p95_ms=times[237],p99_ms=times[247],unexpected_errors=0,capacity_251_rejected=True,exact_retries=10,one_free_slot_race=True,http_failed_attempt_quota=True)
        (args.root/'load-summary.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary))
    finally:
        try:
            sql(f"begin;select app.challenge_gate_v1();select app.challenge_lock_v1('challenge',{q(cid)});select id from public.profiles where id in(select actor_id from app.challenge_members_v1 where challenge_id={q(cid)}) order by id for update;select set_config('app.challenge_write_v1','on',true);select app.challenge_finish_v1({q(cid)},app.challenge_evaluate_v1({q(cid)},true),'cancelled');commit;")
        finally:
            sql("select public.challenge_discovery_fixture_v1(false);select public.challenge_runtime_v1(false,false,false,'{}',null);")
            print('P6 gates disabled; fictional records retained.')
if __name__=='__main__':main()
