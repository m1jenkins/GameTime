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


if __name__ == '__main__':
    unittest.main()
