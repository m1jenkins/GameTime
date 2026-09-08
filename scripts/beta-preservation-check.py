#!/usr/bin/env python3
"""Read-only original checkout and database identity verification for b7."""
import hashlib
import json
from pathlib import Path
import subprocess
from datetime import datetime, timezone

ROOT=Path(__file__).resolve().parents[1]
EVIDENCE=ROOT/'docs/evidence/beta-finish-line-b7'
source=json.loads((EVIDENCE/'inherited-sources.json').read_text())
ORIGINAL=Path(source['source'])
assert ROOT.resolve()!=ORIGINAL.resolve() and ROOT.resolve()!=Path('/Users/user/firstmate-workspace/projects/gametime-beta').resolve()
assert subprocess.check_output(['git','rev-parse','--show-toplevel'],cwd=ROOT,text=True).strip()==str(ROOT)
head=subprocess.check_output(['git','-C',str(ORIGINAL),'rev-parse','HEAD'],text=True).strip()
status=subprocess.check_output(['git','-C',str(ORIGINAL),'status','--porcelain=v1','--untracked-files=all'])
failures=[]
if head!=source['head']:failures.append('Original HEAD changed')
if status!=(EVIDENCE/'original-status.txt').read_bytes():failures.append('Original exact porcelain status changed')
for entry in source['files']:
    original=ORIGINAL/entry['path']
    if not original.is_file() or hashlib.sha256(original.read_bytes()).hexdigest()!=entry['sha256']:
        failures.append('Original bytes changed: '+entry['path'])
identity=subprocess.check_output(['docker','inspect','--format','{{.Id}} {{.Created}} {{.State.StartedAt}} {{json .Mounts}}','supabase_db_gametime'])
if identity!=(EVIDENCE/'original-database-identity.txt').read_bytes():failures.append('Original database container/volume/start identity changed')
report={'checked_at':datetime.now(timezone.utc).isoformat(),'original_head':head,'source_files_checked':len(source['files']),'source_status_matches':status==(EVIDENCE/'original-status.txt').read_bytes(),'database_identity_matches':identity==(EVIDENCE/'original-database-identity.txt').read_bytes(),'failures':failures,'limit':'Read-only byte/status/container identity verification; not a content snapshot or proof of unrelated external database activity.'}
(EVIDENCE/'preservation-final.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
raise SystemExit(bool(failures))
