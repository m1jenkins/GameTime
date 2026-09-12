import pathlib,subprocess,json,time,os
root=pathlib.Path('/private/tmp/gametime-p5-20260911');url='postgresql://postgres:postgres@127.0.0.1:59622/postgres';stack=str(root/'stack');env={k:v for k,v in os.environ.items() if not k.startswith('PG')}
checks=[]
commands=[]
for i in (1,2):
 commands.append((f'p4-races-final-{i}', ['python3','scripts/beta-scoped-locks-p4-concurrency.py','--db-url',url,'--owned-root',stack,'--owned-project','gametime-p5-20260911']))
 commands.append((f'p5-races-final-{i}', ['python3','scripts/beta-p5-pagination-races.py','--db-url',url,'--owned-root',stack,'--owned-project','gametime-p5-20260911']))
commands += [
 ('direct-lint',['psql',url,'-XqAt','-v','ON_ERROR_STOP=1','-f','outputs/reports/p4-20260911/direct-lint.sql']),
 ('advisors',['supabase','db','advisors','--db-url',url,'--type','all','--fail-on','error']),
 ('cli-lint',['supabase','db','lint','--db-url',url,'--schema','app,public','--fail-on','error'])]
for name,cmd in commands:
 start=time.monotonic()
 with (root/(name+'.log')).open('w') as out:
  try: code=subprocess.run(cmd,stdout=out,stderr=out,env=env,timeout=180).returncode
  except subprocess.TimeoutExpired:code=124
 checks.append({'name':name,'command':cmd,'exit_code':code,'seconds':time.monotonic()-start});(root/'final-command-results.json').write_text(json.dumps(checks,indent=2));print(name,code,flush=True)
 # A correctness failure stops this group; CLI advisor issues are recorded only.
 if code and 'races' in name:raise SystemExit(code)
