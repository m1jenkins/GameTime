#!/usr/bin/env python3
"""Authenticated open arrivals with bounded inflight work and durable drop accounting."""
from __future__ import annotations
import argparse, base64, collections, concurrent.futures, hashlib, hmac, http.client, json, math, pathlib, select, signal, threading, time
from lab import Lab, save, digest

def token(secret, actor, session):
    def encode(value):
        return base64.urlsafe_b64encode(json.dumps(value,separators=(',',':')).encode()).decode().rstrip('=')
    content=encode({'alg':'HS256','typ':'JWT'})+'.'+encode({'sub':actor,'session_id':session,'role':'authenticated','aud':'authenticated','iat':int(time.time()),'exp':int(time.time())+14400})
    return content+'.'+base64.urlsafe_b64encode(hmac.new(secret.encode(),content.encode(),hashlib.sha256).digest()).decode().rstrip('=')

class Client:
    def __init__(self,lab):
        self.lab=lab
        self.port=lab.m['api_port']
        if lab.credentials['API_URL']!='http://127.0.0.1:'+str(self.port):
            raise ValueError('foreign API refused')
        self.tokens={}
        self.local=threading.local()
        # Distinct namespace/session canary is independently authorized by the API's actual DB.
        sample,body=self.request('challenge_access_status_v1',{},actor=0)
        if sample['status']!=200 or not isinstance(body,dict) or body.get('age_confirmed') is not True or body.get('beta_access') is not True or body.get('suspended') is not False or not isinstance(body.get('server_time'),str):
            raise ValueError('independent API namespace/session identity failed')

    def request(self, operation, payload, actor=0, service=False):
        begin=time.perf_counter()
        # A foreground burst can create many worker connections which then sit idle.
        # Refresh idle connections before sending; never silently replay a mutation after transport failure.
        conn=getattr(self.local,'connection',None)
        stale=conn and conn.sock and bool(select.select([conn.sock],[],[],0)[0])
        if conn and (stale or time.monotonic()-getattr(self.local,'last_used',0)>30):
            self.local.connection.close()
            del self.local.connection
        if not hasattr(self.local,'connection'):
            self.local.connection=http.client.HTTPConnection('127.0.0.1',self.port,timeout=30)
        connection=self.local.connection
        self.local.last_used=time.monotonic()
        if service:
            bearer=self.lab.credentials['SERVICE_ROLE_KEY']
        else:
            if actor not in self.tokens:
                self.tokens[actor]=token(self.lab.credentials['JWT_SECRET'],self.lab.uid('actor',actor),self.lab.uid('session',actor))
            bearer=self.tokens[actor]
        try:
            connection.request('POST','/rest/v1/rpc/'+operation,json.dumps(payload,separators=(',',':')),
                {'apikey':self.lab.credentials['ANON_KEY'],'Authorization':'Bearer '+bearer,'Content-Type':'application/json'})
            response=connection.getresponse();raw=response.read();status=response.status
            self.local.last_used=time.monotonic()
            try: body=json.loads(raw)
            except (ValueError,UnicodeDecodeError):body=None
            code=body.get('code') if isinstance(body,dict) and status>=400 else None
            # The response is returned in memory for correctness checks; never persist raw payloads or tokens.
            sample={'status':status,'code':code,'bytes':len(raw),'seconds':time.perf_counter()-begin,
                    'response_sha256':hashlib.sha256(raw).hexdigest(),'service':service}
            return sample,body
        except (OSError,http.client.HTTPException) as e:
            connection.close();self.local.connection=http.client.HTTPConnection('127.0.0.1',self.port,timeout=30)
            return {'status':0,'code':type(e).__name__,'bytes':0,'seconds':time.perf_counter()-begin,'service':service},None

    def require(self,operation,payload,actor=0,service=False):
        sample,body=self.request(operation,payload,actor,service)
        if not 200<=sample['status']<300:
            raise RuntimeError('RPC preflight failed: '+json.dumps({'operation':operation,**sample}))
        return body

def percentile(values,p):
    if not values:return None
    values=sorted(values);return values[min(len(values)-1,math.ceil(len(values)*p)-1)]

def schedule(stages):
    """Absolute offsets; lag never changes the offered workload into closed-loop pacing."""
    offset=0.0
    for duration,rate in stages:
        for i in range(math.floor(duration*rate)):
            yield offset+i/rate
        offset+=duration

def mixed(lab,live,index,scenario,foreground_count=100):
    actor=(index//20+index*37)%foreground_count
    part=index%20
    request=lab.uid('request-'+scenario,index)
    if part==11:return 'cursor','challenge_section_v1',{'p_section':'history','p_limit':10},0,False
    if part in (0,1,2,3,8,10):
        section={0:'action',1:'active',2:'upcoming'}.get(part,'history')
        return 'section_'+section,'challenge_section_v1',{'p_section':section,'p_limit':10},actor,False
    if part in (4,5,9):
        actor%=100
        cid=live['personal'][str(actor)] if part==4 else live['friends'][str(actor//2)] if part==5 else live['history'][str(actor)]
        return 'detail','challenge_detail_v1',{'p_id':cid},actor,False
    if part==6:return 'catalog','challenge_community_catalog_v1',{},actor,False
    if part==7:return 'access','challenge_access_status_v1',{},actor,False
    if part==12:
        return 'link_exact_retry','challenge_issue_link_v1',{'p_request_id':live['link_request'],'p_id':live['pending']},0,False
    if part==13:return 'operator_reports','challenge_operator_reports_v1',{'p_id':live['friends']['0']},1999,False
    if part==14:return 'operator_cases','challenge_operator_cases_v1',{'p_id':live['history']['0']},1999,False
    if part==15:
        actor%=100
        return 'journal_exact_retry','challenge_confirm_age_v1',{'p_request_id':lab.uid('age-retry',actor),'p_confirmed':True},actor,False
    if part==16:return 'worker_discovery','challenge_operations_status_v1',{},0,True
    if part==17:return 'worker_batch','challenge_run_batch_v1',{'p_run_id':request,'p_limit':20},0,True
    if part==18:
        actor%=100
        return 'revision_write','challenge_capture_fixture_v1',{'p_request_id':request,'p_id':live['personal'][str(actor)],'p_actor':lab.uid('actor',actor),'p_value':None if index%3 else 99,'p_state':'deleted' if index%3 else 'complete'},0,True
    actor%=100
    return 'report_write','challenge_report_v1',{'p_request_id':request,'p_subject':lab.uid('actor',actor^1),'p_reason':'unwanted_contact'},actor,False

PROFILES={
    'smoke':[(10,2)],
    'ramp':[(60,5),(60,10),(120,25)],
    'spike':[(30,5),(60,25),(30,5)],
    'soak':[(7200,10)],
    'long-term':[(60,25),(60,75),(120,150)],
    'worker-contention':[(120,25)]}

def run(lab,name,profile,cap=100):
    from arrivals import execute
    from oracles import load_live,check_preflight,response_errors,postflight,structural
    if cap<1 or cap>1000:raise ValueError('inflight cap must be 1..1000')
    live=load_live(lab);receipt=check_preflight(lab,live);client=Client(lab)
    out=lab.data/name;out.mkdir(mode=0o700)
    stages=PROFILES[profile];stop=threading.Event();monitor_done=threading.Event();monitor_errors=[]
    old_handlers={sig:signal.signal(sig,lambda *_:stop.set()) for sig in (signal.SIGINT,signal.SIGTERM)}
    spec={'name':name,'profile':profile,'stages':stages,'max_inflight':cap,'parent':lab.m['parent'],'project':lab.m['project'],
          'fixture_accounts':live['accounts'],'authenticated_read_cohort':1000 if profile=='long-term' else 100,
          'harness_hashes':{p.name:digest(p) for p in pathlib.Path(__file__).parent.glob('*.py')},'preflight_sha256':digest(lab.data/('preflight-'+str(live['accounts'])+'.json')),'start_unix':time.time()}
    save(out/'spec.json',spec)
    events=open(out/'events.jsonl','x',buffering=1);cursor_lock=threading.Lock();cursor={}
    def perform(index):
        selection=20*index+[0,17,16,1][index%4] if profile=='worker-contention' else index
        label,op,payload,actor,service=mixed(lab,live,selection,name,1000 if profile=='long-term' else 100)
        held=label=='cursor'
        if held:
            cursor_lock.acquire()
            if cursor.get('next') and time.monotonic()-cursor['created']<90:payload=dict(payload,p_cursor=cursor['next'])
        begin=time.perf_counter()
        try:
            sample,body=client.request(op,payload,actor,service)
            oracle=response_errors(lab,live,label,payload,actor,body) if sample['status']==200 else []
            if held and sample['status']==200 and not oracle:
                ids={r['id'] for r in body['rows']}
                if payload.get('p_cursor'):
                    if ids.intersection(cursor['seen']) or body['projection_revision']!=cursor['snapshot']:oracle.append('cursor_progression')
                    cursor['seen'].update(ids)
                else:cursor.update(seen=ids,created=time.monotonic(),snapshot=body['projection_revision'])
                cursor['next']=body['next_cursor']
            recovery=None
            if sample['status']!=200 and label in ('revision_write','report_write','worker_batch') and sample['status'] in (0,500,504):
                replay,receipt_body=client.request(op,payload,actor,service)
                again,again_body=client.request(op,payload,actor,service)
                recovery={'attempts':2,'first_status':replay['status'],'second_status':again['status'],'exact_match':receipt_body==again_body}
                if replay['status']!=200 or again['status']!=200 or receipt_body!=again_body:oracle.append('unknown_commit_unreconciled')
                else:oracle+=response_errors(lab,live,label,payload,actor,receipt_body)
            return {'operation':label,'actor_ordinal':actor,'oracle_failures':oracle,'recovery':recovery,'total_attempt_seconds':time.perf_counter()-begin,**sample}
        finally:
            if held:cursor_lock.release()
    def monitor():
        while not monitor_done.wait(60):
            try:structural(lab)
            except Exception as error:
                monitor_errors.append({'error':type(error).__name__,'unix':time.time()});stop.set();return
    monitor_thread=threading.Thread(target=monitor,daemon=True);monitor_thread.start()
    try:result,records=execute(stages,cap,perform,lambda event:events.write(json.dumps(event,separators=(',',':'))+'\n'),stop)
    finally:
        monitor_done.set();monitor_thread.join(timeout=180);events.close()
        for sig,handler in old_handlers.items():signal.signal(sig,handler)
    result.update(spec);result['monitor_errors']=monitor_errors
    result['latency_seconds']={}
    for operation in sorted({e.get('operation') for e in records if e.get('operation')}):
        result['latency_seconds'][operation]={}
        for disposition in ['success','failure']:
            values=[e['seconds'] for e in records if e.get('operation')==operation and (e.get('status')==200)==(disposition=='success') and 'seconds' in e]
            result['latency_seconds'][operation][disposition]={'count':len(values),'p50':percentile(values,.5),'p95':percentile(values,.95),'p99':percentile(values,.99),'max':max(values) if values else None}
    try:postflight(lab,receipt,out/'postflight.json');result['postflight_passed']=True
    except Exception as error:result['postflight_passed']=False;result['postflight_error']=type(error).__name__
    result['capacity_pass']=result['capacity_pass'] and result['postflight_passed'] and not monitor_errors
    save(out/'summary.json',result);print(json.dumps(result),flush=True)
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run_root');parser.add_argument('profile',choices=PROFILES)
    parser.add_argument('--name',required=True);parser.add_argument('--max-inflight',type=int,default=100)
    args=parser.parse_args()
    if not args.name.replace('-','').replace('_','').isalnum():raise ValueError('simple scenario name required')
    result=run(Lab(args.run_root),args.name,args.profile,args.max_inflight)
    if not result['capacity_pass']:raise SystemExit(1)

if __name__=='__main__':main()
