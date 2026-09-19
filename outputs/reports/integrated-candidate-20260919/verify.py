#!/usr/bin/env python3
"""Private integrated-candidate verification; only newly owned loopback resources."""
import base64, hashlib, hmac, http.client, ipaddress, json, os, pathlib, re, secrets, socket, subprocess, sys, time, uuid
ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = pathlib.Path(os.environ['GAMETIME_INTEGRATION_EVIDENCE_DIR']).resolve()
OUT.mkdir(parents=True, exist_ok=True)
BASE = '9f116ac4954594a8d64467f78a6dca55d3cc2ce4'
os.umask(0o077)
class Lab:
 def __init__(self, kind):
  self.owner=('gametime-review-monitor-' if kind=='upgrade' else 'gametime-p11a-operator-')+'integration-'+uuid.uuid4().hex[:10]
  self.dir=OUT/kind; self.dir.mkdir(exist_ok=False)
  self.owned=[]; self.password=secrets.token_hex(24); self.jwt=secrets.token_hex(32)
  self.ports=[]
  for _ in range(4):
   with socket.socket() as s:s.bind(('127.0.0.1',0));self.ports.append(s.getsockname()[1])
  assert len(set(self.ports))==4
  self.env=dict(os.environ,DO_NOT_TRACK='1',PGPASSWORD=self.password,POSTGRES_PASSWORD=self.password)
  self.db=self.owner+'-db';self.results=[]
 def command(self,args,source=None,label=None,check=True,env=None):
  r=subprocess.run(args,input=source,text=True,capture_output=True,env=env or self.env,timeout=180)
  if label:(self.dir/label).write_text(r.stdout+r.stderr)
  if check and r.returncode:
   (self.dir/'failure.log').write_text(r.stdout+r.stderr)
   raise RuntimeError('command failed: '+str(label or args[0]))
  return r
 def sql(self,s,label=None):
  return self.command(['docker','exec','-i',self.db,'psql','-XqAt','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],source='set search_path=public,extensions;\n'+s,label=label).stdout.strip()
 def tap(self,s,label):
  r=self.command(['docker','exec','-i',self.db,'psql','-XqAt','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],source='set search_path=public,extensions;\n'+s,label=label,check=False)
  plan=re.findall(r'^1\.\.(\d+)$',r.stdout,re.M); nums=list(map(int,re.findall(r'^(?:not )?ok (\d+)\b',r.stdout,re.M)))
  valid=r.returncode==0 and len(plan)==1 and nums==list(range(1,int(plan[0])+1)) and not re.search(r'^not ok|#\s*(?:SKIP|TODO)|ERROR:',r.stdout+r.stderr,re.M|re.I)
  result={'label':label,'exit':r.returncode,'assertions':len(nums),'passed':bool(valid),'log_sha256':hashlib.sha256((r.stdout+r.stderr).encode()).hexdigest()}
  self.results.append(result);print(json.dumps(result),flush=True)
  assert valid,label
 def token(self,role):
  enc=lambda b:base64.urlsafe_b64encode(b).decode().rstrip('=')
  msg=enc(b'{"alg":"HS256","typ":"JWT"}')+'.'+enc(json.dumps({'role':role,'iss':'supabase','iat':int(time.time()),'exp':int(time.time())+86400}).encode())
  return msg+'.'+enc(hmac.new(self.jwt.encode(),msg.encode(),hashlib.sha256).digest())
 def start(self):
  ids=self.command(['docker','network','ls','-q']).stdout.split()
  nets=json.loads(self.command(['docker','network','inspect',*ids]).stdout)
  used=[ipaddress.ip_network(c['Subnet']) for n in nets for c in (n['IPAM'].get('Config') or []) if c.get('Subnet') and ':' not in c['Subnet']]
  subnet=next(str(n) for n in ipaddress.ip_network('10.252.0.0/16').subnets(new_prefix=24) if not any(n.overlaps(u) for u in used))
  network=self.owner+'-network'
  self.command(['docker','network','create','--subnet',subnet,'--label','owner='+self.owner,network]);self.owned.append(('network',network))
  self.owned.append(('container',self.db))
  self.command(['docker','run','-d','--name',self.db,'--label','owner='+self.owner,'--network',network,'-p',f'127.0.0.1:{self.ports[1]}:5432','-e','POSTGRES_PASSWORD','public.ecr.aws/supabase/postgres:17.6.1.143','postgres','-D','/etc/postgresql','-c','cron.launch_active_jobs=off','-c','listen_addresses=*'],label='db-start.log')
  for _ in range(60):
   r=self.command(['docker','exec','-e','PGPASSWORD',self.db,'psql','-h','127.0.0.1','-XqAt','-U','postgres','-c',"select to_regclass('auth.users') is not null"],check=False)
   if not r.returncode and r.stdout.strip()=='t':break
   time.sleep(.5)
  else:raise RuntimeError('database initialization timeout')
  self.command(['docker','exec','-i',self.db,'psql','-XqAt','-v','ON_ERROR_STOP=1','-U','supabase_admin','-d','postgres'],source=f"alter role supabase_auth_admin password '{self.password}'; alter role authenticator password '{self.password}';")
  self.env.update(GOTRUE_API_HOST='0.0.0.0',GOTRUE_API_PORT='9999',API_EXTERNAL_URL=f'http://127.0.0.1:{self.ports[0]}/auth/v1',GOTRUE_SITE_URL=f'http://127.0.0.1:{self.ports[0]}',GOTRUE_DB_DRIVER='postgres',GOTRUE_DB_DATABASE_URL=f'postgres://supabase_auth_admin:{self.password}@{self.db}:5432/postgres',GOTRUE_JWT_SECRET=self.jwt,GOTRUE_JWT_EXP='3600',GOTRUE_JWT_ADMIN_ROLES='service_role',GOTRUE_JWT_AUD='authenticated',GOTRUE_JWT_DEFAULT_GROUP_NAME='authenticated',GOTRUE_EXTERNAL_EMAIL_ENABLED='true',GOTRUE_MAILER_AUTOCONFIRM='true',GOTRUE_DISABLE_SIGNUP='false')
  opts=[a for k in self.env if k.startswith('GOTRUE_') or k=='API_EXTERNAL_URL' for a in ['-e',k]]
  self.owned.append(('container',self.owner+'-auth'))
  self.command(['docker','run','-d','--name',self.owner+'-auth','--label','owner='+self.owner,'--network',network,'-p',f'127.0.0.1:{self.ports[2]}:9999',*opts,'public.ecr.aws/supabase/gotrue:v2.192.0'],label='auth-start.log')
  for _ in range(60):
   try:
    c=http.client.HTTPConnection('127.0.0.1',self.ports[2],timeout=1);c.request('GET','/health');r=c.getresponse();r.read();c.close()
    if r.status==200:break
   except OSError:pass
   time.sleep(.5)
  else:raise RuntimeError('auth initialization timeout')
  self.sql('create extension if not exists pgtap with schema extensions; create extension if not exists dblink with schema extensions;')
  print('Fresh owned stack initialized: '+self.owner,flush=True)
 def migrate(self,paths):
  for p in paths:self.sql('begin;\n'+p.read_text()+'\ncommit;',p.name+'.log')
  print('Applied '+str(len(paths))+' migrations',flush=True)
 def rest(self):
  self.env.update(PGRST_DB_URI=f'postgres://authenticator:{self.password}@{self.db}:5432/postgres',PGRST_DB_SCHEMAS='public,graphql_public',PGRST_DB_EXTRA_SEARCH_PATH='public,extensions',PGRST_DB_ANON_ROLE='anon',PGRST_JWT_SECRET=self.jwt)
  opts=[a for k in self.env if k.startswith('PGRST_') for a in ['-e',k]]
  self.owned.append(('container',self.owner+'-rest'))
  self.command(['docker','run','-d','--name',self.owner+'-rest','--label','owner='+self.owner,'--network',self.owner+'-network','-p',f'127.0.0.1:{self.ports[3]}:3000',*opts,'public.ecr.aws/supabase/postgrest:v14.14'],label='rest-start.log')
  for _ in range(60):
   try:
    with socket.create_connection(('127.0.0.1',self.ports[3]),1):break
   except OSError:time.sleep(.2)
  conn={'owner':self.owner,'project_id':self.owner,'api_port':self.ports[0],'db_port':self.ports[1],'auth_port':self.ports[2],'rest_port':self.ports[3],'jwt':self.jwt,'anon':self.token('anon'),'service':self.token('service_role')}
  (self.dir/'connection.json').write_text(json.dumps(conn))
 def close(self):
  disposition={'owner':self.owner,'ports':self.ports,'removed':[]}
  try:
   self.sql("select public.challenge_discovery_fixture_v1(false); select public.challenge_runtime_v1(false,false,false,'{}',null); delete from auth.sessions;")
   disposition.update(cron_launch=self.sql('show cron.launch_active_jobs'),cron_runs=int(self.sql('select count(*) from cron.job_run_details')),sessions=int(self.sql('select count(*) from auth.sessions')),runtime_closed=self.sql('select not fixtures and not admission and not processing and not discovery and cardinality(actors)=0 from app.challenge_runtime_v1 where singleton')=='t')
  except Exception as e:disposition['precleanup_error']=type(e).__name__
  for kind,name in reversed(self.owned):
   r=self.command(['docker',kind,'inspect',name],check=False)
   if r.returncode:continue
   row=json.loads(r.stdout)[0];labels=row['Config']['Labels'] if kind=='container' else row['Labels'];assert labels['owner']==self.owner
   if kind=='container':self.command(['docker','logs',name],label=name+'.log',check=False)
   self.command(['docker','rm','-fv',name] if kind=='container' else ['docker','network','rm',name]);disposition['removed'].append(name)
  (self.dir/'connection.json').unlink(missing_ok=True)
  disposition['ports_closed']=[]
  for p in self.ports:
   try:
    with socket.create_connection(('127.0.0.1',p),.3):closed=False
   except OSError:closed=True
   disposition['ports_closed'].append(closed)
  (self.dir/'disposition.json').write_text(json.dumps(disposition,indent=2));(self.dir/'sql-results.json').write_text(json.dumps(self.results,indent=2))
  print('Owned resources removed: '+self.owner,flush=True)
def expand(p):return re.sub(r'^\\ir (.+)$',lambda m:expand(p.parent/m[1]),p.read_text(),flags=re.M)
migrations=sorted((ROOT/'supabase/migrations').glob('*.sql'))
baseline_names=set(subprocess.check_output(['git','-C',str(ROOT),'ls-tree','--name-only',BASE,'supabase/migrations/'],text=True).splitlines())
baseline=[p for p in migrations if str(p.relative_to(ROOT)) in baseline_names]
forward=[p for p in migrations if p not in baseline]
assert len(baseline)==81 and len(forward)==4
kind=sys.argv[1]
lab=Lab(kind)
try:
 lab.start()
 if kind=='upgrade':
  lab.migrate(baseline)
  before=expand(ROOT/'supabase/tests/fixtures/review-monitor-upgrade-before.sql')
  addition="""select public.challenge_publish_community_fixture_v1(pg_temp.br(99001),pg_temp.ba(40),'{"start_date":"2026-10-15","days":1,"timezone":"UTC","amount_cents":100}',100,2,250,true);
select public.challenge_discovery_fixture_v1(true);
select public.challenge_prepare_community_snapshot_invocation_v1(pg_temp.br(99002),(select challenge_id from app.challenge_community_publications_v1));
select public.challenge_dispatch_community_snapshot_invocation_v1(pg_temp.br(99002));
"""
  before=before.replace('create schema review_monitor_upgrade;',addition+'create schema review_monitor_upgrade;')
  (lab.dir/'upgrade-before.sql').write_text(before);lab.sql(before,'upgrade-before.log')
  lab.migrate(forward)
  after=expand(ROOT/'supabase/tests/fixtures/review-monitor-upgrade-after.sql')
  after=after.replace("where p.oid is null or (old.definition", "where old.oid<>'app.challenge_session_v1()'::regprocedure and (p.oid is null or (old.definition")
  after=after.replace("p.proacl,p.proconfig)),'all prior", "p.proacl,p.proconfig))),'all prior")
  extra="""select ok(not exists(select 1 from review_monitor_upgrade.functions old left join pg_proc p on p.oid=old.oid where p.oid is null or (old.proacl,old.proconfig) is distinct from (p.proacl,p.proconfig)),'all prior function privileges and search paths unchanged');
select ok((select definition<>pg_get_functiondef(oid) from review_monitor_upgrade.functions where oid='app.challenge_session_v1()'::regprocedure),'suspended session helper is the one intentional definition change');
select is((select count(*) from app.challenge_admin_requests_v2),0::bigint,'historical administrator operations are not backfilled');
select is(public.challenge_community_snapshot_status_v1((select challenge_id from app.challenge_community_publications_v1))->>'last_capture_at',(select to_jsonb(captured_at)#>>'{}' from app.challenge_community_snapshots_v1),'snapshot monitor projects preserved capture');
select is(public.challenge_community_snapshot_status_v1((select challenge_id from app.challenge_community_publications_v1))->>'capture_age_seconds','0','old capture age uses preserved fixture clock');
"""
  after=after.replace('-- The projection itself',extra+'-- The projection itself')
  (lab.dir/'upgrade-after.sql').write_text(after);lab.tap(after,'upgrade-after.tap')
  lab.rest();lab.command(['python3',str(ROOT/'scripts/beta-review-monitor-smoke.py'),'--connection-file',str(lab.dir/'connection.json'),'--sample-output',str(lab.dir/'review-sample.json')],label='review-http.log')
  print('Review/appeal Auth HTTP smoke passed',flush=True)
 elif kind=='combined':
  lab.migrate(migrations)
  for n in ['440','493','494','497','501','502','506','507','508','509','512','513','514','515','516','517','518']:
   paths=list((ROOT/'supabase/tests').glob(n+'_*.test.sql'));assert len(paths)==1
   lab.tap(expand(paths[0]),paths[0].name+'.tap')
  lab.rest();lab.command(['python3',str(ROOT/'scripts/beta-operator-smoke.py'),'--connection-file',str(lab.dir/'connection.json'),'--work-dir',str(lab.dir/'operator-work'),'--evidence-dir',str(lab.dir/'operator-evidence')],label='operator-http.log')
  print('Complete operator recovery Auth HTTP smoke passed',flush=True)
 elif kind=='concurrency':
  lab.migrate(migrations)
  deletion=(ROOT/'scripts/beta-account-deletion-concurrency-local.py').read_text().replace('not args.db_container.startswith("gametime-account-deletion-20260914-")', 'args.db_container != '+repr(lab.db))
  (lab.dir/'deletion-races.py').write_text(deletion)
  lab.command(['python3',str(lab.dir/'deletion-races.py'),'--db-container',lab.db,'--report',str(lab.dir/'deletion-races.json')],label='deletion-races.log')
  print('Affected deletion concurrency checks passed',flush=True)
  source=pathlib.Path(__file__).with_name('suspended-session-expiry.py').read_text()
  source=source.replace('gametime-p11a-operator-suspension-20260919',lab.owner).replace('/private/tmp/gametime-suspended-account-access',str(ROOT))
  (lab.dir/'suspended-session-expiry.py').write_text(source)
  (lab.dir/'supabase').mkdir()
  (lab.dir/'supabase/config.toml').write_text('project_id = "'+lab.owner+'"\n[db]\nport = '+str(lab.ports[1])+'\n')
  lab.command(['python3',str(lab.dir/'suspended-session-expiry.py'),'--owned-project',lab.owner,'--stack',str(lab.dir),'--port',str(lab.ports[1]),'--report',str(lab.dir/'suspended-session-expiry.json')],label='suspended-session-expiry.log')
  print('Suspended session lock-wait checks passed',flush=True)
 else:raise AssertionError('Unknown verification kind')
 advisor=lab.command(['supabase','db','advisors','--db-url',f'postgresql://postgres:{lab.password}@127.0.0.1:{lab.ports[1]}/postgres?sslmode=disable','--type','security','--level','warn','--fail-on','error'],label='security-advisor.log',check=False)
 (lab.dir/'advisor-result.json').write_text(json.dumps({'exit':advisor.returncode}));assert advisor.returncode==0
 (lab.dir/'source.json').write_text(json.dumps({'base':BASE,'head':subprocess.check_output(['git','-C',str(ROOT),'rev-parse','HEAD'],text=True).strip(),'migration_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in migrations}},indent=2))
finally:lab.close()
