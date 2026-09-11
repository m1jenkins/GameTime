import subprocess, pathlib, re, json, time
root=pathlib.Path('/private/tmp/gametime-p4-final-20260911')
logs=root/'sql';logs.mkdir(exist_ok=True)
url='postgresql://postgres:postgres@127.0.0.1:59422/postgres'
subprocess.run(['psql',url,'-XqAt','-v','ON_ERROR_STOP=1','-c','create extension if not exists pgtap with schema extensions; create extension if not exists dblink with schema extensions;','-f','supabase/seed.sql'],check=True,stdout=subprocess.DEVNULL,timeout=30)
results=[]
for path in sorted(pathlib.Path('supabase/tests').glob('*.test.sql')):
 start=time.monotonic()
 with (logs/(path.stem+'.log')).open('w') as out:
  try:r=subprocess.run(['psql',url,'-XqAt','-v','ON_ERROR_STOP=1','-c','set search_path=public,extensions','-f',str(path)],stdout=out,stderr=out,timeout=120);code=r.returncode
  except subprocess.TimeoutExpired:code=124
 text=(logs/(path.stem+'.log')).read_text()
 failures=[line for line in text.splitlines() if re.match(r'not ok|.*ERROR:|.*Looks like you',line)]
 plans=re.findall(r'^1\.\.(\d+)',text,re.M)
 assertions=len(re.findall(r'^ok \d+',text,re.M))+len(re.findall(r'^not ok \d+',text,re.M))
 skips=[line for line in text.splitlines() if re.search(r'# (?:SKIP|TODO)',line,re.I)]
 passed=code==0 and not failures and bool(plans) and assertions==int(plans[-1])
 item=dict(file=str(path),exit_code=code,assertions=assertions,passed=passed,skips=skips,failures=failures,seconds=time.monotonic()-start)
 results.append(item);print(path.name, 'PASS' if passed else 'FAIL',assertions,flush=True)
 (root/'sql-results.json').write_text(json.dumps(results,indent=2))
print(json.dumps({'files':len(results),'assertions':sum(x['assertions'] for x in results),'failures':[x['file'] for x in results if not x['passed']],'skips':sum(len(x['skips']) for x in results)},indent=2))
raise SystemExit(any(not x['passed'] for x in results))
