#!/usr/bin/env python3
"""Copy committed native inputs; remap only historical test-controller ports.

No database, Simulator, original checkout, or production Swift mutation. The
result is an isolated build directory for the b7-owned 5632x verification stack.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', default='HEAD')
    args = parser.parse_args()
    commit = subprocess.check_output(
        ['git', 'rev-parse', '--verify', args.candidate + '^{commit}'], cwd=ROOT, text=True).strip()
    archive = subprocess.check_output(['git', 'archive', commit, 'ios', 'scripts', 'supabase'], cwd=ROOT)
    destination = Path(tempfile.mkdtemp(prefix='gametime-finish-b7-legacy-native-')).resolve()
    with tarfile.open(fileobj=io.BytesIO(archive)) as bundle:
        for member in bundle.getmembers():
            assert (destination / member.name).resolve().is_relative_to(destination)
            assert not member.issym() and not member.islnk(), 'Native inputs must be independent files'
        bundle.extractall(destination)
    before = {str(p.relative_to(destination)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in destination.rglob('*') if p.is_file()}
    mappings = {
        'scripts/duel-native-local-smoke.py': ('5432', '5632'),
        'ios/GameTime/GameTimeTests/DuelNativeLocalSmokeTests.swift': ('5432', '5632'),
        'scripts/performance-commitment-native-smoke.py': ('5732', '5632'),
        'ios/GameTime/GameTimeTests/PerformanceCommitmentNativeSmokeTests.swift': ('5732', '5632'),
    }
    for name, (old, new) in mappings.items():
        path = destination / name
        source = path.read_text()
        assert old in source
        path.write_text(source.replace(old, new))
    after = {name: hashlib.sha256((destination / name).read_bytes()).hexdigest() for name in before}
    changed = [name for name in before if before[name] != after[name]]
    assert set(changed) == set(mappings)
    report = {'candidate': commit, 'directory': str(destination), 'ports': '56321/56322/56329',
              'scope': 'Only four test/controller port literals changed; all production inputs byte-identical',
              'files': [{'path': name, 'before_sha256': before[name], 'after_sha256': after[name]}
                        for name in sorted(before)]}
    (destination / 'b7-inputs.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'candidate': commit, 'directory': str(destination), 'changed': changed}, indent=2))


if __name__ == '__main__':
    main()
