#!/usr/bin/env python3
"""Friends Phase 4: run FriendsNativeSmokeTests against a disposable stack.

Usage:
  scripts/friends-native-smoke.py --stack <dir> --simulator <udid> \
    --derived-data <absolute dir> [--result <absolute .xcresult path>]

The stack must be a running disposable friends stack, for example one kept by
scripts/friends-local-verify.sh --keep-stack: a project ID that starts with
"gametime-friends-", a loopback API and email sign-in enabled in its copied
config. This applies the settings proposed for hosted in Phase 5, creates four
fictional local accounts (21+ confirmed, one with a mixed-case username), and
writes their sign-in details to a mode-0600 manifest at tmp/friends-native-smoke.json
for the app's own FriendsStore and friend client to use. The manifest is always
removed and the accounts signed out afterwards. No hosted URL, Health data,
payment or notification is used.
"""
import argparse
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import urllib.error
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'tmp/friends-native-smoke.json'
SETTINGS = ROOT / 'scripts/fixtures/friends-build1-settings.sql'


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--stack', required=True, type=Path)
    parser.add_argument('--simulator', required=True)
    parser.add_argument('--derived-data', required=True, type=Path)
    parser.add_argument('--result', type=Path)
    args = parser.parse_args()
    assert args.derived_data.is_absolute(), 'Use an absolute, task-owned derived data path'
    assert args.result is None or args.result.is_absolute(), 'Use an absolute result bundle path'
    config = (args.stack / 'supabase/config.toml').read_text()
    project = re.search(r'^project_id\s*=\s*"([^"]+)"', config, re.M)
    assert project and project.group(1).startswith('gametime-friends-'), 'Only a disposable friends stack'
    status = json.loads(subprocess.check_output(
        ['supabase', 'status', '--workdir', str(args.stack), '-o', 'json'], stderr=subprocess.DEVNULL))
    api, db = status['API_URL'], status['DB_URL']
    assert re.fullmatch(r'http://127\.0\.0\.1:\d+', api), 'Loopback API only'
    assert re.search(r'@127\.0\.0\.1:\d+/postgres$', db), 'Loopback database only'
    service = {'apikey': status['SERVICE_ROLE_KEY'], 'authorization': 'Bearer ' + status['SERVICE_ROLE_KEY']}
    publishable = status['PUBLISHABLE_KEY']

    def http(method, path, body, headers):
        request = urllib.request.Request(api + path, method=method,
                                         data=None if body is None else json.dumps(body).encode(),
                                         headers={'content-type': 'application/json', **headers})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                raw = response.read()
                return response.status, json.loads(raw) if raw else None
        except urllib.error.HTTPError as error:
            raw = error.read()
            return error.code, json.loads(raw) if raw else None

    def sql(statement):
        subprocess.run(['psql', db, '-XqAt', '-v', 'ON_ERROR_STOP=1'], input=statement, text=True,
                       capture_output=True, check=True)

    assert not MANIFEST.exists(), 'Another friends native run owns the manifest; remove it only after checking'
    sql(SETTINGS.read_text())
    code, _ = http('POST', '/rest/v1/rpc/challenge_real_health_runtime_v1',
                   {'p_admission_enabled': True, 'p_ingestion_enabled': True, 'p_processing_enabled': True}, service)
    assert code < 300, 'real-activity runtime'

    password = secrets.token_urlsafe(24) + 'aA9'
    actors = []
    try:
        for label in ['ana', 'Ben', 'cal', 'looker']:
            email = f'friends-native-{uuid.uuid4().hex}@example.invalid'
            code, created = http('POST', '/auth/v1/admin/users',
                                 {'email': email, 'password': password, 'email_confirm': True}, service)
            assert code < 300, 'fictional account created'
            code, session = http('POST', '/auth/v1/token?grant_type=password',
                                 {'email': email, 'password': password}, {'apikey': publishable})
            assert code < 300, 'fictional account signed in'
            actor = {'id': created['id'], 'email': email, 'username': label + 'Native' + uuid.uuid4().hex[:8]}
            actors.append(actor)
            as_actor = {'apikey': publishable, 'authorization': 'Bearer ' + session['access_token']}
            code, _ = http('POST', '/rest/v1/profiles', {'id': actor['id'], 'handle': actor['username'],
                           'display_name': 'Fictional ' + label.title(), 'timezone': 'UTC'},
                           {**as_actor, 'prefer': 'return=minimal'})
            assert code == 201, 'profile saved'
            code, _ = http('POST', '/rest/v1/rpc/challenge_command_v1', {'p_request_id': str(uuid.uuid4()),
                           'p_payload': {'op': 'confirm_age', 'confirmed': True}}, as_actor)
            assert code < 300, 'age confirmed'
        MANIFEST.parent.mkdir(exist_ok=True)
        descriptor = os.open(MANIFEST, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, 'w') as stream:
            json.dump({'url': api, 'key': publishable, 'password': password, 'actors': actors}, stream)
        command = ['xcodebuild', 'test', '-project', 'ios/GameTime/GameTime.xcodeproj', '-scheme', 'GameTime',
                   '-configuration', 'Debug', '-destination', f'platform=iOS Simulator,id={args.simulator}',
                   '-derivedDataPath', str(args.derived_data), '-parallel-testing-enabled', 'NO',
                   '-only-testing:GameTimeTests/FriendsNativeSmokeTests', 'CODE_SIGNING_ALLOWED=NO']
        if args.result:
            command += ['-resultBundlePath', str(args.result)]
        return subprocess.run(command, cwd=ROOT).returncode
    finally:
        MANIFEST.unlink(missing_ok=True)
        if actors:
            ids = ','.join("'" + str(uuid.UUID(a['id'])) + "'" for a in actors)
            sql(f'delete from auth.sessions where user_id in ({ids}); '
                f'delete from auth.refresh_tokens where user_id::uuid in ({ids});')
        print('Friends native smoke cleanup: manifest removed; fictional sessions revoked.', flush=True)


if __name__ == '__main__':
    raise SystemExit(main())
