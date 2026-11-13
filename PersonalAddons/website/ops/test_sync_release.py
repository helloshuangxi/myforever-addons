#!/usr/bin/env python3
"""Real release-transition tests; every fixture and modified site lives in TemporaryDirectory."""
import copy
import datetime as dt
import hashlib
import json
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile

import sync_release as sync


class ReleaseSyncTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='mfc-release-test-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.public = self.base / 'public'
        shutil.copytree(sync.ROOT / 'public', self.public)
        current = json.loads((self.public / 'latest.json').read_text())
        updates, _ = sync.prepare(self.public, self.public / 'downloads' / current['download']['filename'], current)
        sync.apply(self.public, updates)
        self.original = json.loads((self.public / 'releases.json').read_text())
        self.previous_version = current['version']
        major, minor, patch = sync.version_key(self.previous_version)
        self.new_version = f'{major}.{minor}.{patch + 1}'
        namespace = '{http://www.sitemaps.org/schemas/sitemap/0.9}'
        dates = [entry.findtext(namespace + 'lastmod') for entry in ET.fromstring((self.public / 'sitemap.xml').read_text())]
        next_date = (dt.date.fromisoformat(max(dates)) + dt.timedelta(days=1)).isoformat()
        self.notes = {'version': self.new_version, 'channel': 'trial', 'published_at': next_date,
                      'compatibility': {'product': '国服魔兽世界：无限', 'client': '1.60.1'},
                      'changes': ['仅供临时目录测试，不发布。'], 'validation': ['仅测试发布脚本，不代表游戏验证。']}

    def package(self, version=None, content='TEST ONLY', extra=None):
        version = version or self.new_version
        path = self.base / 'test-package.zip'
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('MyForeverChat/MyForeverChat.toc', f'## Version: {version}\n## Interface: 16001\n')
            archive.writestr('MyForeverChat/Test.lua', content)
            if extra:
                archive.writestr(*extra)
        return path

    def snapshot(self):
        return {str(p.relative_to(self.public)): hashlib.sha256(p.read_bytes()).hexdigest() for p in self.public.rglob('*') if p.is_file()}

    def test_transition_and_repeat_preserve_history(self):
        package = self.package()
        other_latest = (self.public/'professions/latest.json').read_bytes()
        other_catalog = (self.public/'professions/releases.json').read_bytes()
        other_page = (self.public/'professions/index.html').read_bytes()
        changes, release = sync.prepare(self.public, package, self.notes)
        sync.apply(self.public, changes)
        catalog = json.loads((self.public / 'releases.json').read_text())
        self.assertEqual(catalog['latest'], self.new_version)
        self.assertEqual(len(catalog['releases']), len(self.original['releases']) + 1)
        for old in self.original['releases']:
            self.assertIn(old, catalog['releases'])
        document = (self.public / 'chat/index.html').read_text()
        self.assertEqual(document.count(f'href="/downloads/MyForeverChat-{self.new_version}-Trial.zip"'), 3)
        self.assertEqual(document.count(f'<summary><span>v{self.previous_version}</span>'), 1)
        sitemap = (self.public / 'sitemap.xml').read_text()
        for url in ('https://afabiaoge.xyz/', 'https://afabiaoge.xyz/chat/'):
            self.assertIn(f'<loc>{url}</loc><lastmod>{self.notes["published_at"]}</lastmod>', sitemap)
        self.assertEqual(json.loads((self.public / 'latest.json').read_text()), release)
        self.assertEqual(release['homepage'], 'https://afabiaoge.xyz/')
        self.assertEqual((self.public/'professions/latest.json').read_bytes(), other_latest)
        self.assertEqual((self.public/'professions/releases.json').read_bytes(), other_catalog)
        self.assertEqual((self.public/'professions/index.html').read_bytes(), other_page)
        portal = (self.public/'index.html').read_text()
        self.assertEqual(portal.count(f'href="/downloads/MyForeverChat-{self.new_version}-Trial.zip"'), 1)
        self.assertIn('href="/chat/"', portal)
        self.assertEqual(sync.prepare(self.public, package, self.notes)[0], {})
        subprocess.run([sys.executable, str(sync.ROOT / 'ops/verify_site.py'), '--public', str(self.public)], check=True, capture_output=True)

    def test_dry_run_writes_nothing(self):
        package = self.package()
        notes = self.base / 'notes.json'
        notes.write_text(json.dumps(self.notes))
        before = self.snapshot()
        result = subprocess.run([sys.executable, str(sync.ROOT / 'ops/sync_release.py'), '--public', str(self.public), '--zip', str(package), '--notes', str(notes), '--dry-run'], check=True, capture_output=True, text=True)
        self.assertEqual(json.loads(result.stdout)['status'], 'dry-run')
        self.assertEqual(before, self.snapshot())
        self.assertFalse((self.public / f'downloads/MyForeverChat-{self.new_version}-Trial.zip').exists())

    def test_same_version_different_bytes_is_rejected(self):
        package = self.package()
        sync.apply(self.public, sync.prepare(self.public, package, self.notes)[0])
        before = self.snapshot()
        package = self.package(content='DIFFERENT TEST ONLY')
        with self.assertRaisesRegex(ValueError, 'different archive hash'):
            sync.prepare(self.public, package, self.notes)
        self.assertEqual(before, self.snapshot())

    def test_existing_filename_is_immutable(self):
        package = self.package()
        (self.public / f'downloads/MyForeverChat-{self.new_version}-Trial.zip').write_bytes(b'not-the-package')
        with self.assertRaisesRegex(ValueError, 'immutable package'):
            sync.prepare(self.public, package, self.notes)

    def test_older_version_and_unverified_notes_are_rejected(self):
        before = self.snapshot()
        notes = copy.deepcopy(self.notes)
        notes['version'] = '0.7.9'
        with self.assertRaisesRegex(ValueError, 'older version'):
            sync.prepare(self.public, self.package('0.7.9'), notes)
        notes = copy.deepcopy(self.notes)
        notes.pop('validation')
        with self.assertRaisesRegex(ValueError, 'validation'):
            sync.prepare(self.public, self.package(), notes)
        self.assertEqual(before, self.snapshot())

    def test_private_and_traversal_zip_entries_are_rejected(self):
        before = self.snapshot()
        for name in ['../secret.txt', '/tmp/secret', 'C:/secret', 'MyForeverChat\\..\\secret', 'WTF/Account/a.lua', 'MyForeverChat/SavedVariables/data.lua', 'MyForeverChat/.env']:
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'Unsafe'):
                sync.prepare(self.public, self.package(extra=(name, 'TEST ONLY')), self.notes)
        info = zipfile.ZipInfo('MyForeverChat/link')
        info.create_system = 3
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
        with self.assertRaisesRegex(ValueError, 'Unsafe'):
            sync.prepare(self.public, self.package(extra=(info, '../../secret')), self.notes)
        self.assertEqual(before, self.snapshot())

    def test_unregistered_test_zip_is_rejected_by_verifier(self):
        for relative in ['downloads/unregistered-test.zip', 'test.zip', 'assets/fixture.zip', 'downloads/TEST.ZIP']:
            with self.subTest(path=relative):
                path = self.public / relative
                shutil.copyfile(self.package(), path)
                result = subprocess.run([sys.executable, str(sync.ROOT / 'ops/verify_site.py'), '--public', str(self.public)], capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Unregistered', result.stderr)
                path.unlink()


if __name__ == '__main__':
    unittest.main(verbosity=2)
