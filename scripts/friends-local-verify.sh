#!/usr/bin/env bash
# Friends TestFlight Phase 4: verify friends, the four friend goals and the
# Personal goals over HTTP against a fresh, disposable local stack configured
# with the settings proposed for hosted gametime-p11b in Phase 5.
#
# Never uses the source checkout's Supabase project, .env, linked project or
# database, and never calls a hosted URL. Actors are fictional local Auth
# users. Requires Docker, Supabase CLI, psql, Deno and Python 3.
#
# Usage: scripts/friends-local-verify.sh [--keep-stack]
# FRIENDS_VERIFY_PORT_BASE (default 57540) reserves base..base+9 on loopback.
# With --keep-stack the stack stays up; rerun only the driver with
#   deno run --config <dir>/supabase/functions/deno.json -A \
#     <dir>/scripts/friends-local-http.ts <dir>
# Source and logs remain in the printed temporary directory.
set -euo pipefail

keep_stack=0
case "${1:-}" in
  '') ;;
  --keep-stack) keep_stack=1 ;;
  *) echo "usage: $0 [--keep-stack]" >&2; exit 2 ;;
esac
if (( $# > 1 )); then echo "too many arguments" >&2; exit 2; fi
for tool in git docker supabase psql deno python3; do
  command -v "$tool" >/dev/null || { echo "missing required tool: $tool" >&2; exit 1; }
done
source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
if ! git -C "$source_root" diff --quiet HEAD -- supabase scripts; then
  echo "Commit the test inputs before running a reproducible verification." >&2
  exit 1
fi
port_base="${FRIENDS_VERIFY_PORT_BASE:-57540}"
if [[ ! "$port_base" =~ ^[0-9]{5}$ ]] || (( port_base < 10240 || port_base > 65520 )); then
  echo "FRIENDS_VERIFY_PORT_BASE must be an integer from 10240 through 65520" >&2
  exit 2
fi
# Resolve /tmp's symlink so Deno's read permission matches the files it opens.
verification_root="$(cd "$(mktemp -d /tmp/gametime-friends-verify.XXXXXXXX)" && pwd -P)"
project_name="$(basename "$verification_root" | tr '[:upper:]' '[:lower:]')"
export DO_NOT_TRACK=1

# Copy only tracked supabase/ and scripts/ inputs, pin a unique project ID and
# ports, and refuse occupied ports before anything is created.
python3 - "$source_root" "$verification_root" "$project_name" "$port_base" <<'PY'
from pathlib import Path
import hashlib, json, re, shutil, socket, subprocess, sys
source, target = map(Path, sys.argv[1:3])
project, base = sys.argv[3], int(sys.argv[4])
for port in range(base, base + 10):
    with socket.socket() as sock:
        try:
            sock.bind(('127.0.0.1', port))
        except OSError:
            raise SystemExit(f'Port {port} is occupied; choose another FRIENDS_VERIFY_PORT_BASE.')
tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=source).decode().split('\0')
manifest = []
for rel in tracked:
    if not rel.startswith(('supabase/', 'scripts/')):
        continue
    original = source / rel
    if original.is_symlink() or not original.is_file():
        raise SystemExit(f'Refusing nonregular test input: {rel}')
    destination = target / rel
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(original, destination)
    manifest.append({'path': rel, 'sha256': hashlib.sha256(destination.read_bytes()).hexdigest()})
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source).decode().strip()
config = target / 'supabase/config.toml'
text = config.read_text()
text = re.sub(r'^project_id\s*=.*$', f'project_id = "{project}"', text, count=1, flags=re.M)
for old, offset in ((54320,0),(54321,1),(54322,2),(54323,3),(54324,4),(54329,9)):
    text = text.replace(str(old), str(base + offset))
# Hosted build 1 is Apple sign-in only. This disposable copy alone lets the
# driver's admin-created fictional accounts sign in with a password.
text, count = re.subn(r'(\[auth\.email\]\n(?:#[^\n]*\n)*)enable_signup = false', r'\1enable_signup = true', text, count=1)
if count != 1:
    raise SystemExit('Unexpected [auth.email] section in supabase/config.toml')
config.write_text(text)
(target / 'input-manifest.json').write_text(json.dumps(
    {'source_head': head, 'project': project, 'port_base': base, 'inputs': manifest}, indent=2) + '\n')
PY

started=0
passed=0
owned_network="supabase_network_${project_name}"
cleanup() {
  result=$?
  trap - EXIT
  # Anything that stops before the last line, even with status 0, failed.
  if (( ! passed && result == 0 )); then result=1; fi
  if (( started && ! keep_stack )); then
    if ! supabase stop --workdir "$verification_root" --no-backup >"$verification_root/stop.log" 2>&1; then
      echo "Disposable stack cleanup failed; inspect $verification_root/stop.log" >&2
      if (( result == 0 )); then result=1; fi
    fi
  fi
  if (( ! keep_stack )) && docker network inspect "$owned_network" >/dev/null 2>&1; then
    network_owner="$(docker network inspect "$owned_network" --format '{{index .Labels "com.supabase.cli.project"}}')"
    if [[ "$network_owner" != "$project_name" ]] || ! docker network rm "$owned_network" >"$verification_root/network-stop.log" 2>&1; then
      echo "Disposable network cleanup failed; inspect $verification_root/network-stop.log" >&2
      if (( result == 0 )); then result=1; fi
    fi
  fi
  echo "Verification inputs and logs: $verification_root"
  exit "$result"
}
trap cleanup EXIT
python3 - "$project_name" <<'PY'
import ipaddress, json, subprocess, sys
project = sys.argv[1]
network = f'supabase_network_{project}'
ids = subprocess.check_output(['docker', 'network', 'ls', '-q'], text=True).split()
details = json.loads(subprocess.check_output(['docker', 'network', 'inspect', *ids], text=True)) if ids else []
used = [ipaddress.ip_network(config['Subnet']) for item in details
        for config in item['IPAM'].get('Config') or [] if config.get('Subnet')]
for candidate in ipaddress.ip_network('10.253.0.0/16').subnets(new_prefix=24):
    if any(candidate.overlaps(existing) for existing in used):
        continue
    created = subprocess.run(['docker', 'network', 'create', '--subnet', str(candidate),
                              '--label', f'com.docker.compose.project={project}',
                              '--label', f'com.supabase.cli.project={project}', network],
                             capture_output=True, text=True)
    if created.returncode == 0:
        print(f'Disposable Docker network: {network} ({candidate})')
        break
else:
    raise SystemExit('Could not reserve an unused Docker subnet for this disposable project.')
PY
echo "Disposable project: $project_name; API port: $((port_base + 1)); database port: $((port_base + 2))"
echo "Verification inputs and logs: $verification_root"
started=1
if ! supabase start --workdir "$verification_root" -x edge-runtime,studio,imgproxy,mailpit,storage-api,vector,realtime >"$verification_root/start.log" 2>&1; then
  tail -n 60 "$verification_root/start.log" >&2
  exit 1
fi
cd "$verification_root"
if ! deno run --config supabase/functions/deno.json \
  --allow-run=supabase,psql --allow-net=127.0.0.1 --allow-read="$verification_root" \
  --allow-env scripts/friends-local-http.ts "$verification_root" >friends.log 2>&1; then
  tail -n 100 friends.log >&2
  exit 1
fi
tail -n 20 friends.log
passed=1
echo "Friends Phase 4 local HTTP verification passed. This does not establish device, human, hosted or TestFlight acceptance."
