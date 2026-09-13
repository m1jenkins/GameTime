"""Keep existing smoke consumers compatible while isolating custom previews."""
import importlib.util
import os
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def load_script(name, environment):
    with patch.dict(os.environ, environment, clear=True):
        spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / name)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module


class PreviewConfigurationTests(unittest.TestCase):
    def test_default_manifest_matches_existing_native_and_operator_consumers(self):
        smoke = load_script('beta-native-smoke.py', {})
        preview = load_script('beta-preview.py', {})
        for support in [smoke, preview.support]:
            self.assertEqual(support.MANIFEST, ROOT / 'tmp/beta-native-smoke.json')
            self.assertEqual(support.REPORT, ROOT / 'tmp/beta-native-smoke-report.json')
            self.assertEqual(support.CONTROLLER_PORT, 58339)

    def test_custom_preview_has_separate_credentials_and_resources(self):
        preview = load_script('beta-preview.py', {
            'GAMETIME_BETA_PREVIEW_PROJECT': 'gametime-test-preview',
            'GAMETIME_BETA_PREVIEW_PORT_BASE': '63320',
            'GAMETIME_BETA_PREVIEW_STACK': '/tmp/gametime-test-stack',
            'GAMETIME_BETA_PREVIEW_SIMULATOR': 'owned-test-simulator',
            'GAMETIME_BETA_PREVIEW_APP': '/tmp/owned-test-build/GameTime.app',
        })
        support = preview.support
        self.assertEqual(support.MANIFEST, ROOT / 'tmp/beta-native-smoke-gametime-test-preview.json')
        self.assertEqual(support.REPORT, ROOT / 'tmp/beta-native-smoke-report-gametime-test-preview.json')
        self.assertEqual(support.DB, 'postgresql://postgres:postgres@127.0.0.1:63322/postgres')
        self.assertEqual((support.API_PORT, support.CONTROLLER_PORT), (63321, 63339))
        self.assertEqual(support.STACK, Path('/tmp/gametime-test-stack'))
        self.assertEqual(support.OWNED_SIM, 'owned-test-simulator')
        self.assertEqual(preview.APP, Path('/tmp/owned-test-build/GameTime.app'))

    def test_custom_smoke_retains_native_tests_manifest_path(self):
        smoke = load_script('beta-native-smoke.py', {'GAMETIME_BETA_PREVIEW_PROJECT': 'gametime-test-preview'})
        self.assertEqual(smoke.MANIFEST, ROOT / 'tmp/beta-native-smoke.json')

    def test_project_mismatch_stops_before_creating_accounts(self):
        preview = load_script('beta-preview.py', {})
        with patch('sys.argv', ['beta-preview.py', '--owned-project', 'wrong-project', 'serve']), \
                patch.object(preview.support, 'Smoke') as smoke:
            with self.assertRaisesRegex(AssertionError, 'Owned project must match'):
                preview.main()
            smoke.assert_not_called()


if __name__ == '__main__':
    unittest.main()
