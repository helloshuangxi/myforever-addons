#!/usr/bin/env python3
"""Navigator release transitions in disposable copies; never publish fixtures."""
import copy
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

import sync_navigator_release as sync
import sync_professions_release as professions
import sync_release as chat


class NavigatorReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='navigator-release-test-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.public = self.base / 'public'
        shutil.copytree(sync.ROOT / 'public', self.public)
        self.old = json.loads((self.public / 'navigator/latest.json').read_text())
        major, minor, patch = sync.version_key(self.old['version'])
        self.version = f'{major}.{minor}.{patch + 1}'
        self.notes = {'version': self.version, 'channel': 'trial', 'published_at': '2026-11-09',
                      'compatibility': {'product': '国服魔兽世界：无限', 'client': '1.60.1'},
                      'changes': ['临时目录测试，不发布。'], 'validation': ['发布脚本模拟，不是游戏验证。']}

    def package(self, version=None, content='TEST ONLY', extra=None):
        path = self.base / 'fixture.zip'
        with zipfile.ZipFile(path, 'w') as archive:
            # Version immutability compares complete ZIP bytes, including dates.
            # Recreating identical fixtures must not depend on the wall clock.
            def write(name, value):
                archive.writestr(zipfile.ZipInfo(name, (2026, 11, 8, 0, 0, 0)), value)
            write('MyForeverNavigator/MyForeverNavigator.toc', f'## Version: {version or self.version}\n## Interface: 16001\n')
            write('MyForeverNavigator/Test.lua', content)
            if extra:
                write(*extra)
        return path

    def snapshot(self):
        return {str(p.relative_to(self.public)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in self.public.rglob('*') if p.is_file()}

    def test_transition_repeat_and_other_addons_unchanged(self):
        before = self.snapshot()
        changes, release = sync.prepare(self.public, self.package(), self.notes)
        sync.apply(self.public, changes)
        self.assertEqual(json.loads((self.public / 'navigator/latest.json').read_text()), release)
        catalog = json.loads((self.public / 'navigator/releases.json').read_text())
        self.assertIn(self.old, catalog['releases'])
        self.assertEqual(catalog['latest'], self.version)
        portal = (self.public / 'index.html').read_text()
        self.assertEqual(portal.count('data-addon="MyForeverNavigator"'), 1)
        self.assertIn(f'/downloads/MyForeverNavigator-{self.version}-Trial.zip', portal)
        detail = (self.public / 'navigator/index.html').read_text()
        self.assertEqual(detail.count(f'/downloads/MyForeverNavigator-{self.version}-Trial.zip'), 2)
        self.assertEqual(sync.prepare(self.public, self.package(), self.notes)[0], {})
        after = self.snapshot()
        for path, digest in before.items():
            if path in {'latest.json','releases.json','chat/index.html','professions/index.html','professions/latest.json','professions/releases.json'} or path.startswith('downloads/'):
                self.assertEqual(after[path], digest, path)

    def test_other_release_syncs_keep_navigator_card(self):
        expected = (self.public / 'navigator/latest.json').read_bytes()
        for operation, relative in ((chat, 'latest.json'), (professions, 'professions/latest.json')):
            current = json.loads((self.public / relative).read_text())
            changes, _ = operation.prepare(self.public, self.public / 'downloads' / current['download']['filename'], current)
            sync.apply(self.public, changes)
            self.assertEqual((self.public / 'navigator/latest.json').read_bytes(), expected)
            self.assertEqual((self.public / 'index.html').read_text().count('data-addon="MyForeverNavigator"'), 1)

    def test_dry_run_never_writes(self):
        notes = self.base / 'notes.json'
        notes.write_text(json.dumps(self.notes))
        before = self.snapshot()
        result = subprocess.run([sys.executable, str(sync.ROOT / 'ops/sync_navigator_release.py'),
                                 '--public', str(self.public), '--zip', str(self.package()), '--notes', str(notes), '--dry-run'],
                                check=True, capture_output=True, text=True)
        self.assertEqual(json.loads(result.stdout)['status'], 'dry-run')
        self.assertEqual(before, self.snapshot())

    def test_first_release_bootstrap(self):
        (self.public / 'navigator/latest.json').unlink()
        (self.public / 'navigator/releases.json').unlink()
        changes, release = sync.prepare(self.public, self.package(), self.notes)
        self.assertEqual(release['name'], 'MyForeverNavigator')
        self.assertEqual(len(json.loads(changes['navigator/releases.json'])['releases']), 1)

    def test_immutable_versions_and_files(self):
        sync.apply(self.public, sync.prepare(self.public, self.package(), self.notes)[0])
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, 'different archive hash'):
            sync.prepare(self.public, self.package(content='DIFFERENT'), self.notes)
        self.assertEqual(self.snapshot(), before)
        filename = self.public / 'downloads' / f'MyForeverNavigator-{self.version}-Trial.zip'
        filename.write_bytes(b'wrong contents')
        # The existing release hash still matches the proposed fixture but destination bytes do not.
        with self.assertRaisesRegex(ValueError, 'immutable package'):
            sync.prepare(self.public, self.package(), self.notes)

    def test_unsafe_packages_and_unverified_notes_rejected(self):
        for name in ('../secret', 'MyForeverNavigator/WTF/a.lua', 'MyForeverNavigator/SavedVariables/a.lua', 'OtherAddon/a.lua'):
            with self.subTest(path=name), self.assertRaises(ValueError):
                sync.prepare(self.public, self.package(extra=(name, 'private')), self.notes)
        notes = copy.deepcopy(self.notes)
        notes.pop('validation')
        with self.assertRaisesRegex(ValueError, 'validation'):
            sync.prepare(self.public, self.package(), notes)

    def test_symlink_output_rejected(self):
        package = self.package()
        target = self.public / 'downloads' / f'MyForeverNavigator-{self.version}-Trial.zip'
        target.symlink_to(package)
        with self.assertRaisesRegex(ValueError, 'symlink'):
            sync.prepare(self.public, package, self.notes)


if __name__ == '__main__':
    unittest.main(verbosity=2)
