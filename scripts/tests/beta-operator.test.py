#!/usr/bin/env python3
"""Focused local CLI recovery/configuration regressions; no network required."""
import concurrent.futures
import importlib.util
import json
import subprocess
from pathlib import Path
import sys
import tempfile
import unittest
import uuid
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'scripts'))
spec = importlib.util.spec_from_file_location('operator_cli', ROOT/'scripts/beta-operator.py')
cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)/'journal'
        self.body = {'p_request_id': str(uuid.uuid4()), 'p_subject': str(uuid.uuid4()), 'p_reason': 'username'}
        self.actor = str(uuid.uuid4())

    def tearDown(self):
        self.temp.cleanup()

    def save(self, **changes):
        values = dict(directory=self.directory, project='gametime-test', port=64421,
                      actor=self.actor, name='challenge_support_suspend_v1', body=self.body)
        values.update(changes)
        return cli.journal_request(**values)

    def test_reopen_preserves_exact_body_and_permissions(self):
        first = self.save()
        self.assertEqual(self.save(), first)
        self.assertEqual(json.loads(first), self.body)
        path = next(self.directory.glob('*.json'))
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.directory.stat().st_mode & 0o777, 0o700)
        self.assertEqual(set(json.loads(path.read_text())), {'version', 'project', 'port', 'actor_id', 'rpc', 'body'})

    def test_same_id_cannot_switch_actor_target_rpc_or_body(self):
        self.save()
        for changes in [dict(actor=str(uuid.uuid4())), dict(port=64431), dict(project='gametime-other'),
                        dict(name='challenge_appeal_v1'), dict(body=dict(self.body, p_reason='unsafe_behavior'))]:
            with self.subTest(changes=changes), self.assertRaises(cli.LocalError):
                self.save(**changes)
        self.assertEqual(json.loads(self.save()), self.body)

    def test_concurrent_first_save_never_replaces_request(self):
        with concurrent.futures.ThreadPoolExecutor(4) as pool:
            results = list(pool.map(lambda _: self.save(), range(8)))
        self.assertEqual(len(set(results)), 1)
        self.assertEqual(len(list(self.directory.iterdir())), 1)

    def test_corrupt_record_does_not_get_overwritten(self):
        self.save()
        path = next(self.directory.glob('*.json'))
        path.write_text('{')
        with self.assertRaises(ValueError):
            self.save()
        self.assertEqual(path.read_text(), '{')

    def test_public_directory_and_symlink_are_rejected(self):
        self.directory.mkdir(mode=0o755)
        with self.assertRaises(cli.LocalError):
            self.save()
        self.directory.rmdir()
        self.directory.symlink_to(self.temp.name, target_is_directory=True)
        with self.assertRaises(cli.LocalError):
            self.save()

    def test_public_credentials_and_symlink_are_rejected(self):
        path = Path(self.temp.name)/'credentials.json'
        path.write_text('{}'); path.chmod(0o644)
        with self.assertRaises(cli.LocalError):
            cli.private_json(path)
        path.chmod(0o600)
        link = Path(self.temp.name)/'link.json'; link.symlink_to(path)
        with self.assertRaises(OSError):
            cli.private_json(link)

    def test_invalid_arguments_never_echo_pasted_credentials(self):
        secret = 'fictional-secret-must-not-be-printed'
        for command in [['--password', secret, 'status'],
                        ['suspend', '--subject', secret, '--reason', 'username', '--request-id', str(uuid.uuid4())]]:
            result = subprocess.run([sys.executable, str(ROOT/'scripts/beta-operator.py'),
                                     '--owned-project', 'gametime-test', '--credentials-file', 'unused',
                                     *command], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertNotIn(secret, result.stdout + result.stderr)
            self.assertIn('Invalid arguments', result.stderr)

    def test_incomplete_cursor_has_no_rpc(self):
        parser = cli.parser_for_cli()
        for extra in [['--before', '2026-10-01T00:00:00Z'], ['--before-id', str(uuid.uuid4())]]:
            args = parser.parse_args(['--owned-project', 'gametime-test', '--credentials-file', 'unused', 'support-reports', *extra])
            with self.assertRaises(cli.LocalError):
                cli.operation(args)

    def admin_args(self, command='grant', extra=None):
        result = ['--owned-project', 'gametime-test', '--credentials-file', 'unused',
                  '--administrator', command, '--actor', self.actor,
                  '--request-id', self.body['p_request_id']]
        if command in ['grant', 'revoke']:
            result += ['--challenge', str(uuid.uuid4()), '--capability', 'review']
        if command in ['grant', 'grant-support']:
            result += ['--expires', '2026-10-10T12:00:00Z']
        return result + (extra or [])

    def test_administrator_requests_are_explicitly_versioned_and_journaled(self):
        for command in ['grant', 'revoke', 'grant-support', 'revoke-support']:
            with self.subTest(command=command):
                args = cli.parser_for_cli().parse_args(self.admin_args(command))
                rpc, body = cli.operation(args)
                self.assertEqual(rpc, 'challenge_admin_request_v2')
                self.assertEqual(body['p_payload']['version'], 'challenge_admin_request_v2')
                self.assertEqual(body['p_payload']['actor_id'], self.actor)
                self.assertEqual(body['p_request_id'], self.body['p_request_id'])
                directory = self.directory/command
                encoded = cli.journal_request(directory, 'gametime-test', 64421, None, rpc, body,
                                              authority='administrator')
                saved = json.loads((directory/(body['p_request_id']+'.json')).read_text())
                self.assertEqual(saved, {'version': 2, 'project': 'gametime-test', 'port': 64421,
                                        'authority': 'administrator', 'rpc': rpc, 'body': encoded})
                for change in [dict(project='gametime-other'), dict(port=64422),
                               dict(body=dict(body, p_payload=dict(body['p_payload'], actor_id=str(uuid.uuid4())))),
                               dict(name='challenge_grant_operator_v1')]:
                    values = dict(directory=directory, project='gametime-test', port=64421,
                                  actor=None, name=rpc, body=body, authority='administrator')
                    values.update(change)
                    with self.assertRaises(cli.LocalError):
                        cli.journal_request(**values)
                with self.assertRaises(cli.LocalError):
                    cli.journal_request(directory, 'gametime-test', 64421, self.actor, rpc, body)

    def test_administrator_requires_uuid_and_journal_before_dispatch(self):
        for command in ['grant', 'revoke', 'grant-support', 'revoke-support']:
            argv = self.admin_args(command)
            pos = argv.index('--request-id')
            with self.subTest(command=command), patch('sys.stderr'), self.assertRaises(SystemExit):
                cli.parser_for_cli().parse_args(argv[:pos]+argv[pos+2:])
            config = {'project_id': 'gametime-test', 'api_port': 64421,
                      'role': 'administrator', 'api_key': 'fictional-secret'}
            with patch.object(sys, 'argv', ['beta-operator.py', *argv]), \
                 patch.object(cli, 'private_json', return_value=config), \
                 patch.object(cli, 'request') as dispatch:
                with self.assertRaisesRegex(cli.LocalError, 'Provide --journal-dir'):
                    cli.main()
                dispatch.assert_not_called()

    def test_administrator_journal_exists_before_http_and_excludes_credentials(self):
        config = {'project_id': 'gametime-test', 'api_port': 64421,
                  'role': 'administrator', 'api_key': 'fictional-service-secret'}
        credentials = Path(self.temp.name)/'admin.json'
        credentials.write_text(json.dumps(config)); credentials.chmod(0o600)
        argv = self.admin_args('grant-support')
        argv[argv.index('unused')] = str(credentials)
        argv = ['--journal-dir', str(self.directory), *argv]
        def dispatch(port, path, body, headers):
            saved = json.loads(next(self.directory.glob('*.json')).read_text())
            self.assertEqual(saved['body'], body)
            self.assertEqual(saved['port'], port)
            self.assertEqual('/rest/v1/rpc/'+saved['rpc'], path)
            self.assertNotIn(config['api_key'], json.dumps(saved))
            raise OSError('simulated lost response')
        with patch.object(sys, 'argv', ['beta-operator.py', *argv]), patch.object(cli, 'request', side_effect=dispatch):
            with self.assertRaises(OSError):
                cli.main()
        self.assertEqual(len(list(self.directory.glob('*.json'))), 1)


if __name__ == '__main__':
    unittest.main()
