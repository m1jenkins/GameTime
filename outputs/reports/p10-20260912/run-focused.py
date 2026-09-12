from pathlib import Path
import os,subprocess,re,json
root=Path('/private/tmp/gametime-p10-20260912')
log=Path('/private/tmp/gametime-p10-audit-20260912')
files=['493_challenge_entry','497_challenge_operations','498_challenge_admission_context','502_challenge_session_lock_expiry','504_challenge_durable_claims','506_challenge_private_community','507_challenge_community_guards','508_challenge_community_progress']
report=[]
for name in files:
 p=root/'supabase/tests'/f'{name}.test.sql'
 r=subprocess.run(['psql','-X','-qAt','-h','127.0.0.1','-p','59822','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-f',str(p)],env={**os.environ,'PGPASSWORD':'postgres'},capture_output=True,text=True,timeout=120)
 (log/f'{name}.log').write_text(r.stdout+r.stderr)
 cases=re.findall(r'^(?:not )?ok (\d+)\b.*$',r.stdout,re.M)
 plans=re.findall(r'^1\.\.(\d+)$',r.stdout,re.M)
 failed=bool(re.search(r'^not ok |^Bail out!|#\s*(?:SKIP|TODO)\b',r.stdout,re.M|re.I))
 passed=r.returncode==0 and len(plans)==1 and len(cases)==int(plans[0]) and list(map(int,cases))==list(range(1,len(cases)+1)) and not failed
 report.append({'file':str(p.relative_to(root)),'exit_code':r.returncode,'assertions':len(cases),'passed':passed,'skips':0 if passed else 'inspect log'})
 print(name,passed,len(cases),flush=True)
(root/'outputs/reports/p10-20260912/focused-sql.json').write_text(json.dumps(report,indent=2)+'\n')
assert all(r['passed'] for r in report),report
