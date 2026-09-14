#!/usr/bin/env python3
"""Local-only operator CLI; never use hosted or real participant credentials.

Each credential file names one owned project and a numeric loopback API port.
Administrator files contain role=administrator and api_key (local service key).
Human files contain role=human, api_key (public key), actor_id and email; password
is prompted, or supplied in this private file for fictional automation only.
Human mutations require a private journal directory and an explicit request UUID.
Repeat the same command to recover after response loss, even after a new sign-in.
"""
import argparse
import getpass
import http.client
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
import uuid
from challenge_worker import run_once

ADMIN = {'status', 'run-once', 'grant', 'revoke', 'grant-support',
         'revoke-support', 'publish-fixture'}
REASONS = ['username', 'unwanted_contact', 'unsafe_behavior']


class LocalError(Exception):
    pass


def private_json(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd) as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise LocalError('Use an owned private file (mode 0600), then try again.')
        return json.load(stream)


def wire(body):
    return json.dumps(body, sort_keys=True, separators=(',', ':'), allow_nan=False)


def request(port, path, body, headers, timeout=30):
    conn = http.client.HTTPConnection('127.0.0.1', port, timeout=timeout)
    try:
        conn.request('POST', path, body, headers)
        response = conn.getresponse()
        raw = response.read()
        if not 200 <= response.status < 300:
            try:
                code = json.loads(raw).get('code', '')
            except (ValueError, AttributeError):
                code = ''
            code = code if isinstance(code, str) and re.fullmatch(r'(?:[0-9A-Z]{5}|PGRST[0-9]{3})', code) else str(response.status)
            raise LocalError('Local operation rejected (' + code + '). Check the account, grant and request before retrying.')
        return json.loads(raw) if raw else None
    finally:
        conn.close()


class LocalParser(argparse.ArgumentParser):
    def error(self, message):
        # argparse normally echoes invalid values, including an accidentally
        # pasted credential. Do not put command-line values into diagnostics.
        self.exit(2, 'Invalid arguments. Use --help to check required options and values.\n')


def parser_for_cli():
    parser = LocalParser(description=__doc__)
    parser.add_argument('--owned-project', required=True)
    parser.add_argument('--credentials-file', required=True, type=Path)
    parser.add_argument('--administrator', action='store_true', help='Explicitly select service administration; cannot perform human decisions')
    parser.add_argument('--journal-dir', type=Path, help='Private durable request directory; retain for exact recovery')
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('status')
    run = sub.add_parser('run-once')
    run.add_argument('--run-id', required=True, type=uuid.UUID)
    run.add_argument('--limit', type=int, default=20, choices=range(1, 51))
    for name in ['grant', 'revoke', 'grant-support', 'revoke-support']:
        p = sub.add_parser(name)
        p.add_argument('--actor', required=True, type=uuid.UUID)
        if name in ['grant', 'revoke']:
            p.add_argument('--challenge', required=True, type=uuid.UUID)
            p.add_argument('--capability', required=True, choices=['review', 'moderate'])
        if name in ['grant', 'grant-support']:
            p.add_argument('--expires', required=True)
    for name in ['cases', 'reports']:
        p = sub.add_parser(name)
        p.add_argument('--challenge', required=True, type=uuid.UUID)
    p = sub.add_parser('support-reports')
    p.add_argument('--before', help='created_at of the last row; pair with --before-id')
    p.add_argument('--before-id', type=uuid.UUID)
    sub.add_parser('support-appeals')
    sub.add_parser('own-appeals')
    for name in ['resolve', 'remove', 'suspend', 'close-community', 'resolve-appeal', 'appeal']:
        p = sub.add_parser(name)
        p.add_argument('--request-id', required=True, type=uuid.UUID)
        if name in ['resolve', 'remove', 'close-community']:
            p.add_argument('--challenge', required=True, type=uuid.UUID)
        if name == 'resolve':
            p.add_argument('--review', required=True, type=uuid.UUID)
            p.add_argument('--decision', required=True, choices=['upheld', 'exclude'])
        if name == 'resolve-appeal':
            p.add_argument('--appeal', required=True, type=uuid.UUID)
            p.add_argument('--decision', required=True, choices=['upheld', 'reinstate'])
        if name in ['remove', 'suspend']:
            p.add_argument('--subject', required=True, type=uuid.UUID)
            p.add_argument('--reason', required=True, choices=REASONS)
    pub = sub.add_parser('publish-fixture')
    pub.add_argument('--operator', required=True, type=uuid.UUID)
    pub.add_argument('--config-file', required=True, type=Path)
    for field in ['target', 'minimum', 'capacity']:
        pub.add_argument('--' + field, required=True, type=int)
    pub.add_argument('--request-id', required=True, type=uuid.UUID)
    pub.add_argument('--fictional', action='store_true', required=True)
    return parser


def operation(args):
    c = args.command
    if c == 'status':
        return 'challenge_operations_status_v1', {}
    if c in ['grant', 'revoke', 'grant-support', 'revoke-support']:
        body = {'p_actor': str(args.actor)}
        if c in ['grant', 'revoke']:
            body.update(p_id=str(args.challenge), p_capability=args.capability)
        if c in ['grant', 'grant-support']:
            body['p_expires'] = args.expires
        return 'challenge_' + c.replace('-', '_') + ('_v1' if 'support' in c else '_operator_v1'), body
    if c in ['cases', 'reports']:
        return 'challenge_operator_' + c + '_v1', {'p_id': str(args.challenge)}
    if c == 'support-reports':
        if (args.before is None) != (args.before_id is None):
            raise LocalError('Provide both --before and --before-id, or neither, then try again.')
        return 'challenge_support_reports_v1', {'p_before': args.before, 'p_before_id': str(args.before_id) if args.before_id else None}
    if c in ['support-appeals', 'own-appeals']:
        return 'challenge_' + c.replace('-', '_') + '_v1', {}
    body = {'p_request_id': str(args.request_id)}
    if c == 'suspend':
        # No challenge/moderator fallback. Server requires the separate support grant.
        return 'challenge_support_suspend_v1', dict(body, p_subject=str(args.subject), p_reason=args.reason)
    if c == 'resolve-appeal':
        return 'challenge_resolve_appeal_v1', dict(body, p_appeal=str(args.appeal), p_decision=args.decision)
    if c == 'appeal':
        return 'challenge_appeal_v1', body
    if c == 'close-community':
        return 'challenge_operator_close_v1', dict(body, p_id=str(args.challenge))
    if c == 'publish-fixture':
        return 'challenge_publish_community_fixture_v1', dict(body, p_operator=str(args.operator), p_config=json.loads(args.config_file.read_text()), p_target=args.target, p_minimum=args.minimum, p_capacity=args.capacity, p_fixture_only=True)
    payload = {'op': c, 'id': str(args.challenge)}
    if c == 'resolve':
        payload.update(review_id=str(args.review), decision=args.decision)
    else:
        payload.update(actor_id=str(args.subject), reason=args.reason)
    return 'challenge_operator_action_v1', dict(body, p_payload=payload)


def journal_request(directory, project, port, actor, name, body):
    """Persist only locally constructed, credential-free mutation fields.

    Publish atomically with no replacement; concurrent invocations agree on the
    same record before either may send. fsync the file and parent before HTTP.
    The record is immutable even after success: server receipts own recovery.
    """
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise LocalError('Use an owned private journal directory (mode 0700), then try again.')
    path = directory / (str(uuid.UUID(body['p_request_id'])) + '.json')
    record = {'version': 1, 'project': project, 'port': port, 'actor_id': actor,
              'rpc': name, 'body': wire(body)}
    # The request filename is actor-independent so switching accounts fails
    # closed in this journal instead of silently creating a second action.
    fd, temporary = tempfile.mkstemp(prefix='.pending-', dir=directory)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(wire(record) + '\n')
            stream.flush()
            os.fsync(stream.fileno())
        try:
            os.link(temporary, path)
        except FileExistsError:
            pass
        saved = private_json(path)
        if saved != record:
            raise LocalError('Saved request differs in account, target or action. Restore the original command and credentials to recover it.')
        directory_fd = os.open(directory, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
        return saved['body']
    finally:
        os.unlink(temporary)


def main():
    parser = parser_for_cli()
    args = parser.parse_args()
    service = args.command in ADMIN
    if service != args.administrator:
        raise LocalError('Use --administrator only for administrator commands; use human credentials for decisions.')
    config = private_json(args.credentials_file)
    if set(config) - {'project_id', 'api_port', 'role', 'api_key', 'actor_id', 'email', 'password'}:
        raise LocalError('Unknown local credential fields. Check the documented file format and try again.')
    if not re.fullmatch(r'gametime-[a-z0-9-]+', args.owned_project) or config['project_id'] != args.owned_project:
        raise LocalError('Owned project does not match. Check the local credential file and try again.')
    port = config['api_port']
    if type(port) is not int or not 1024 <= port <= 65535:
        raise LocalError('Use a numeric local API port from 1024 to 65535.')
    if config['role'] != ('administrator' if service else 'human'):
        raise LocalError('Credential role does not match. Use a separate administrator or human file.')
    if service and any(k in config for k in ['actor_id', 'email', 'password']):
        raise LocalError('Keep human credentials out of the administrator file.')
    key = config['api_key']
    headers = {'apikey': key, 'Content-Type': 'application/json'}
    if service:
        headers['Authorization'] = 'Bearer ' + key
    name, body = operation(args) if args.command != 'run-once' else (None, None)
    encoded = wire(body)
    if not service and 'p_request_id' in body:
        if not args.journal_dir:
            raise LocalError('Provide --journal-dir to save this request before sending it.')
        encoded = journal_request(args.journal_dir, args.owned_project, port,
                                  str(uuid.UUID(config['actor_id'])), name, body)
    session = None
    try:
        if not service:
            session = request(port, '/auth/v1/token?grant_type=password', wire({
                'email': config['email'], 'password': config.get('password') or getpass.getpass('Local fictional operator password: ')}), headers)
            headers['Authorization'] = 'Bearer ' + session['access_token']
            if session['user']['id'] != str(uuid.UUID(config['actor_id'])):
                raise LocalError('Signed-in account differs from the saved identity. Use the original account to recover.')
        if args.command == 'run-once':
            result = run_once(lambda rpc, payload: request(port, '/rest/v1/rpc/' + rpc, wire(payload), headers, timeout=5), args.run_id, args.limit,
                              scope={'version': 'challenge_worker_scope_v1', 'kind': 'due'})
        else:
            result = request(port, '/rest/v1/rpc/' + name, encoded, headers)
        print(json.dumps(result, indent=2))
    finally:
        if session:
            try:
                request(port, '/auth/v1/logout?scope=local', '{}', headers)
            except Exception:
                print('Local sign-out could not be confirmed. End this CLI session before reusing the account.', file=sys.stderr)


if __name__ == '__main__':
    try:
        main()
    except LocalError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
    except (OSError, ValueError, KeyError, TypeError, EOFError, http.client.HTTPException):
        print('Local operation could not be confirmed. Check the private configuration and connection; repeat the exact saved command for human mutations. Administrator grants have no receipt: inspect grant state before reissuing.', file=sys.stderr)
        sys.exit(1)
