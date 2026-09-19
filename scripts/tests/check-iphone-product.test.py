#!/usr/bin/env python3
"""Mutation regressions for active iPhone source/packaging boundaries."""
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('iphone_product', ROOT / 'scripts/check-iphone-product.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class IPhoneProductTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='gametime-iphone-guard-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        # Exact current source inputs, never DerivedData/cache or a retained lab.
        paths = subprocess.check_output(['git', 'ls-files', '-z', 'ios'], cwd=ROOT).decode().split('\0')
        for name in paths:
            source = ROOT / name
            if source.is_file() and (source.suffix in checker.SOURCE_SUFFIXES | {'.plist', '.entitlements', '.xcconfig', '.xcscheme', '.pbxproj'}):
                if '/cache/' in name:
                    continue
                dest = self.root / name
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, dest)
        self.project = self.root / 'ios/GameTime/GameTime.xcodeproj/project.pbxproj'
        self.objects = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(self.project)]))['objects']
        self.app = next(key for key, value in self.objects.items() if value.get('name') == 'GameTime' and value.get('isa') == 'PBXNativeTarget')

    def save(self):
        self.project.write_text(json.dumps({'objects': self.objects}))

    def rejected(self, message):
        with self.assertRaisesRegex(ValueError, message):
            checker.check_project(self.root)

    def test_current_candidate_has_only_iphone_targets_and_healthkit(self):
        result = checker.check_project(ROOT)
        self.assertEqual(result['targets'], ['GameTime', 'GameTimeTests', 'GameTimeUITests'])
        self.assertEqual(len(result['schemes']), 3)
        self.assertGreater(result['source_files'], 100)

    def test_debug_only_connectivity_is_rejected(self):
        (self.root / 'ios/GameTime/GameTime/Added.swift').write_text('#if DEBUG\nimport WatchConnectivity\n#endif\n')
        self.rejected('Watch runtime source')

    def test_release_exclusion_cannot_mask_active_coordinator(self):
        self.objects['EXTRA_CONFIG'] = {'buildSettings': {'EXCLUDED_SOURCE_FILE_NAMES': ['Added.swift']}}
        self.save()
        (self.root / 'ios/GameTime/GameTime/Added.swift').write_text('let session = WCSession.default\n')
        self.rejected('Watch runtime source')

    def test_standalone_watch_target_is_rejected_without_iphone_dependency(self):
        self.objects['WATCH'] = {'isa': 'PBXNativeTarget', 'name': 'GameTimeWatch'}
        self.save()
        self.rejected('Watch reference in active project')

    def test_renamed_watch_target_cannot_hide_device_family(self):
        self.objects['EXTRA_CONFIG'] = {'buildSettings': {'TARGETED_DEVICE_FAMILY': 4}}
        self.save()
        self.rejected('Watch device family')

    def test_copy_phase_is_rejected(self):
        self.objects['COPY'] = {'isa': 'PBXCopyFilesBuildPhase', 'dstPath': '$(CONTENTS_FOLDER_PATH)/Watch', 'files': ['BUILD']}
        self.objects['BUILD'] = {'fileRef': 'WATCH_PRODUCT'}
        self.objects['WATCH_PRODUCT'] = {'path': 'Companion.watchkitapp'}
        self.objects[self.app]['buildPhases'].append('COPY')
        self.save()
        self.rejected('Watch reference in active project')

    def test_watch_embedding_directory_is_rejected_even_with_generic_product_name(self):
        self.objects['COPY'] = {'isa': 'PBXCopyFilesBuildPhase', 'dstPath': '$(CONTENTS_FOLDER_PATH)/Watch', 'files': []}
        self.save()
        self.rejected('Watch embedding copy phase')

    def test_explicit_source_outside_synchronized_folder_is_inspected(self):
        external = self.root / 'ios/GameTime/Extra.swift'
        external.write_text('let session = WCSession.default\n')
        self.objects['EXTRA'] = {'isa': 'PBXFileReference', 'path': 'Extra.swift', 'sourceTree': 'SOURCE_ROOT'}
        self.objects['BUILD'] = {'fileRef': 'EXTRA'}
        self.objects['SOURCES'] = {'isa': 'PBXSourcesBuildPhase', 'files': ['BUILD']}
        self.objects[self.app]['buildPhases'].append('SOURCES')
        self.save()
        self.rejected('Watch runtime source')

    def test_restored_watch_scheme_is_rejected(self):
        path = self.root / 'ios/GameTime/GameTime.xcodeproj/xcshareddata/xcschemes/Restored.xcscheme'
        path.write_text('<Scheme><BuildableReference BlueprintName="GameTimeWatch" /></Scheme>')
        self.rejected('Watch build/launch')

    def test_unknown_launch_buildable_is_rejected(self):
        path = self.root / 'ios/GameTime/GameTime.xcodeproj/xcshareddata/xcschemes/Restored.xcscheme'
        path.write_text('<Scheme><BuildableReference BlueprintIdentifier="REMOVED" /></Scheme>')
        self.rejected('Unknown scheme buildable')

    def test_configuration_linker_dependency_is_rejected(self):
        (self.root / 'ios/GameTime/Configuration/Extra.xcconfig').write_text('OTHER_LDFLAGS = -framework WatchConnectivity\n')
        self.rejected('Watch reference in active configuration')

    def test_healthkit_capability_cannot_be_removed(self):
        path = self.root / 'ios/GameTime/GameTime/GameTime.entitlements'
        path.write_bytes(plistlib.dumps({}))
        self.rejected('HealthKit capability missing')

    def test_historical_sources_remain_inert(self):
        (self.root / 'ios/GameTime/GameTimeWatch').mkdir(exist_ok=True)
        (self.root / 'ios/GameTime/GameTimeWatch/Old.swift').write_text('import WatchConnectivity\n')
        checker.check_project(self.root)

    def test_embedded_watch_directory_is_rejected(self):
        app = self.root / 'Fixture.app'
        (app / 'Watch').mkdir(parents=True)
        (app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleSupportedPlatforms': ['iPhoneSimulator'], 'NSHealthShareUsageDescription': 'Fixture'}))
        with self.assertRaisesRegex(ValueError, 'Watch payload'):
            checker.check_app(app)

    def test_release_executable_rejects_fixture_launch_markers(self):
        app = self.root / 'Release.app'
        app.mkdir()
        (app / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleSupportedPlatforms': ['iPhoneOS'],
            'CFBundleExecutable': 'GameTime',
            'GAMETIME_ENV': 'release',
            'NSHealthShareUsageDescription': 'Health access',
        }))
        executable = app / 'GameTime'
        with mock.patch.object(checker.subprocess, 'check_output', return_value='HealthKit.framework/HealthKit'):
            for marker in (b'--fixture-mode', b'--fixture-demo-interactive', b'--demo-interactive'):
                with self.subTest(marker=marker):
                    executable.write_bytes(bytes.fromhex('cffaedfe') + marker)
                    with self.assertRaisesRegex(ValueError, 'Fixture launch marker'):
                        checker.check_app(app)
            executable.write_bytes(bytes.fromhex('cffaedfe') + b'ordinary-release-entry')
            self.assertTrue(checker.check_app(app)['healthkit_linked'])


if __name__ == '__main__':
    unittest.main()
