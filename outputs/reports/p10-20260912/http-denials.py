import base64,hashlib,hmac,json,os,subprocess,time,urllib.request,urllib.error
from pathlib import Path
root=Path('/private/tmp/gametime-p10-20260912')
settings=json.loads(subprocess.check_output(['supabase','status','--workdir','/private/tmp/gametime-p10-audit-20260912','-o','json'],stderr=subprocess.DEVNULL,env={**os.environ,'DO_NOT_TRACK':'1'}))
assert settings['API_URL']=='http://127.0.0.1:59821'
assert settings['DB_URL']=='postgresql://postgres:postgres@127.0.0.1:59822/postgres'
metadata=json.loads(subprocess.check_output(['psql','-X','-qAt','-h','127.0.0.1','-p','59822','-U','postgres','-d','postgres','-c',"select json_agg(json_build_object('name',proname,'args',proargnames[1:pronargs], 'service',has_function_privilege('service_role',oid,'EXECUTE'))) from pg_proc where pronamespace='public'::regnamespace and starts_with(proname,'challenge_')"],env={**os.environ,'PGPASSWORD':'postgres'}))
def b64(v): return base64.urlsafe_b64encode(v).rstrip(b'=')
def token():
 payload={'role':'authenticated','aud':'authenticated','iss':settings['API_URL']+'/auth/v1','sub':'00000000-0000-4000-8000-000000000010','session_id':'00000000-0000-4000-8000-000000000011','iat':int(time.time()),'exp':int(time.time())+600}
 msg=b'.'.join(b64(json.dumps(p).encode()) for p in [{'alg':'HS256','typ':'JWT'},payload])
 return (msg+b'.'+b64(hmac.new(settings['JWT_SECRET'].encode(),msg,hashlib.sha256).digest())).decode()
auth=token()
results=[]
def check(name,role,body=None,path=None,extra=None,codes=('42501',)):
 headers={'apikey':settings['ANON_KEY'],'Authorization':'Bearer '+(settings['ANON_KEY'] if role=='anon' else auth),'Content-Type':'application/json',**(extra or {})}
 req=urllib.request.Request(settings['API_URL']+(path or '/rest/v1/rpc/'+name),data=None if path else json.dumps(body or {}).encode(),headers=headers,method='GET' if path else 'POST')
 try:
  with urllib.request.urlopen(req,timeout=5) as response: status=response.status;data=json.loads(response.read())
 except urllib.error.HTTPError as error: status=error.code;data=json.loads(error.read())
 code=data.get('code') if isinstance(data,dict) else None
 passed=status in (400,401,403,404,406) and code in codes
 results.append({'case':name,'role':role,'status':status,'code':code,'passed':passed})
for f in metadata:
 body={p:None for p in f['args'] or []}
 check(f['name'],'anon',body)
 if f['service']: check(f['name'],'authenticated',body)
for name,body in [('challenge_detail_v1',{'p_id':'00000000-0000-4000-8000-000000000012'}),('challenge_operator_cases_v1',{'p_id':'00000000-0000-4000-8000-000000000012'}),('challenge_support_reports_v1',{})]:
 check(name,'authenticated',body)
check('private_app_schema','authenticated',path='/rest/v1/challenge_lobbies_v1?select=*',extra={'Accept-Profile':'app'},codes=('PGRST106',))
check('no_public_challenge_table','authenticated',path='/rest/v1/challenge_lobbies_v1?select=*',codes=('PGRST205',))
(root/'outputs/reports/p10-20260912/http-denials.json').write_text(json.dumps(results,indent=2)+'\n')
print(json.dumps({'checks':len(results),'passed':sum(x['passed'] for x in results),'failures':[x for x in results if not x['passed']]}))
assert all(x['passed'] for x in results)
