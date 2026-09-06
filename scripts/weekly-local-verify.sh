#!/usr/bin/env bash
# Reproduce the portable weekly acceptance in a fresh, disposable local stack.
# Never uses the source checkout's Supabase project, .env, linked project or DB.
# Requires Docker, Supabase CLI, psql, Deno, Swift and Python 3. No hosted calls,
# scheduler registration beyond historical migrations, notifications or money.
# Usage: scripts/weekly-local-verify.sh [--keep-stack]
# WEEKLY_VERIFY_PORT_BASE (default 57320) reserves base..base+9 on loopback.
# Source and logs remain in the printed temporary directory after completion.
set -euo pipefail

keep_stack=0
case "${1:-}" in
  '') ;;
  --keep-stack) keep_stack=1 ;;
  *) echo "usage: $0 [--keep-stack]" >&2; exit 2 ;;
esac
if (( $# > 1 )); then echo "too many arguments" >&2; exit 2; fi
for tool in git docker supabase psql deno swift python3; do
  command -v "$tool" >/dev/null || { echo "missing required tool: $tool" >&2; exit 1; }
done
source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
if ! git -C "$source_root" diff --quiet HEAD -- supabase scripts ios/GameTimeCore; then
  echo "Commit the portable test inputs before running a reproducible verification." >&2
  exit 1
fi
port_base="${WEEKLY_VERIFY_PORT_BASE:-57320}"
if [[ ! "$port_base" =~ ^[0-9]{5}$ ]] || (( port_base < 10240 || port_base > 65520 )); then
  echo "WEEKLY_VERIFY_PORT_BASE must be an integer from 10240 through 65520" >&2
  exit 2
fi
verification_root="$(mktemp -d /tmp/gametime-weekly-verify.XXXXXXXX)"
project_name="$(basename "$verification_root" | tr '[:upper:]' '[:lower:]')"
export DO_NOT_TRACK=1

# Copy only inputs needed by the portable gate. No credentials, build outputs,
# hosted linkage or runtime state are inherited. Reject occupied local ports
# before Supabase can create anything.
python3 - "$source_root" "$verification_root" "$project_name" "$port_base" <<'PY'
from pathlib import Path
import hashlib, json, shutil, socket, subprocess, sys
source, target = map(Path, sys.argv[1:3])
project, base = sys.argv[3], int(sys.argv[4])
for port in range(base, base + 10):
    with socket.socket() as sock:
        try:
            sock.bind(('127.0.0.1', port))
        except OSError:
            raise SystemExit(f'Port {port} is occupied; choose another WEEKLY_VERIFY_PORT_BASE.')
# Git's tracked inventory includes intentional public test certificates while
# excluding local .env files, keys, build products and linked-project state.
tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=source).decode().split('\0')
manifest = []
for rel in tracked:
    if not rel.startswith(('supabase/', 'scripts/', 'ios/GameTimeCore/')):
        continue
    original = source / rel
    if original.is_symlink() or not original.is_file():
        raise SystemExit(f'Refusing nonregular test input: {rel}')
    destination = target / rel
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(original, destination)
    manifest.append({'path': rel, 'source_sha256': hashlib.sha256(destination.read_bytes()).hexdigest()})
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source).decode().strip()
config = target / 'supabase/config.toml'
text = config.read_text()
import re
text = re.sub(r'^project_id\s*=.*$', f'project_id = "{project}"', text, count=1, flags=re.M)
for old, offset in ((54320,0),(54321,1),(54322,2),(54323,3),(54324,4),(54329,9)):
    text = text.replace(str(old), str(base + offset))
config.write_text(text)
for entry in manifest:
    entry['sha256'] = hashlib.sha256((target / entry['path']).read_bytes()).hexdigest()
(target / 'input-manifest.json').write_text(json.dumps({'source_head': head, 'project': project, 'port_base': base, 'inputs': manifest}, indent=2) + '\n')
PY

started=0
cleanup() {
  result=$?
  trap - EXIT
  if (( started && ! keep_stack )); then
    if ! supabase stop --workdir "$verification_root" --no-backup >"$verification_root/stop.log" 2>&1; then
      echo "Disposable stack cleanup failed; inspect $verification_root/stop.log" >&2
      if (( result == 0 )); then result=1; fi
    fi
  fi
  echo "Verification inputs and logs: $verification_root"
  exit "$result"
}
trap cleanup EXIT
echo "Disposable project: $project_name; database port: $((port_base + 2))"
echo "Verification inputs and logs: $verification_root"
started=1
if ! supabase start --workdir "$verification_root" -x edge-runtime,studio,imgproxy,mailpit,storage-api,vector >"$verification_root/start.log" 2>&1; then
  tail -n 60 "$verification_root/start.log" >&2
  exit 1
fi
cd "$verification_root"
if ! ./scripts/test-all.sh >portable.log 2>&1; then
  tail -n 100 portable.log >&2
  exit 1
fi
tail -n 12 portable.log
if ! deno run --config supabase/functions/deno.json --allow-run=psql \
  --allow-read=scripts/examples scripts/weekly-lifecycle-local-smoke.ts \
  "$((port_base + 2))" >lifecycle.log 2>&1; then
  tail -n 100 lifecycle.log >&2
  exit 1
fi
tail -n 12 lifecycle.log
echo "Portable weekly acceptance and persisted lifecycle smoke passed. This does not establish device, human, hosted or pilot acceptance."
