#!/usr/bin/env python3
"""Exercise desktop release identity and archive safety using isolated tiny fixtures."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile

import sync_manager_release as sync


class ManagerReleaseTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix='mfm-site-test-')
        self.addCleanup(directory.cleanup)
        self.base = Path(directory.name)
        self.public = self.base / 'public'
        (self.public / 'manager').mkdir(parents=True)
        shutil.copy2(sync.ROOT / 'public/manager/index.html', self.public / 'manager/index.html')
        shutil.copy2(sync.ROOT / 'public/sitemap.xml', self.public / 'sitemap.xml')
        self.notes = {'version': '0.1.0', 'channel': 'trial', 'published_at': '2026-11-07',
                      'changes': ['Isolated fixture; never publish.'], 'validation': ['Synthetic signatures only.']}
        self.packages = {platform: self.package(platform) for platform in sync.PLATFORMS}

    def package(self, platform, version='0.1.0', extra=None, payload=b'fixture', identity=None, executable_mode=0o755, wrong_arch=False):
        path = self.base / (platform + '.zip')
        with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
            z.writestr('manager-release.json', json.dumps(identity or {'name': sync.NAME, 'version': version, 'platform': platform}))
            z.writestr('README.txt', 'fixture instructions')
            z.writestr('LICENSE.txt', 'fixture license')
            if platform == 'win-x64':
                header = bytearray(200)
                header[:2] = b'MZ'
                struct.pack_into('<I', header, 60, 128)
                header[128:132] = b'PE\0\0'
                struct.pack_into('<H', header, 132, 0x14c if wrong_arch else 0x8664)
                z.writestr('MyForeverManager.exe', bytes(header) + payload)
            else:
                prefix = 'MyForeverManager.app/Contents/'
                arch = 0x100000c if platform == 'osx-arm64' else 0x1000007
                if wrong_arch:
                    arch = 0x1000007 if platform == 'osx-arm64' else 0x100000c
                member = zipfile.ZipInfo(prefix + 'MacOS/MyForeverManager')
                member.create_system = 3
                member.external_attr = (stat.S_IFREG | executable_mode) << 16
                z.writestr(member, b'\xcf\xfa\xed\xfe' + struct.pack('<I', arch) + payload)
                z.writestr(prefix + 'Info.plist', plistlib.dumps({'CFBundleExecutable': sync.NAME, 'CFBundleShortVersionString': version}))
                z.writestr(prefix + 'MacOS/runtime.dylib', b'fixture runtime')
            if extra:
                z.writestr(*extra)
        return path

    def snapshot(self):
        return {str(p.relative_to(self.public)): hashlib.sha256(p.read_bytes()).hexdigest() for p in self.public.rglob('*') if p.is_file()}

    def sync(self):
        updates, release = sync.prepare(self.public, self.packages, self.notes)
        sync.apply(self.public, updates)
        return release

    def test_first_release_and_idempotence(self):
        release = self.sync()
        paths, latest = sync.verify_catalog(self.public)
        self.assertEqual(latest, release)
        self.assertEqual(len(paths), 3)
        self.assertEqual(sync.prepare(self.public, self.packages, self.notes)[0], {})
        html = (self.public / 'manager/index.html').read_text()
        self.assertEqual(html.count('data-platform='), 3)
        for record in release['downloads']:
            self.assertIn(record['sha256'], html)
            self.assertIn(record['filename'], html)

    def test_new_version_retains_old_packages(self):
        old = self.sync()
        old_files = {x['filename']: (self.public / 'manager/downloads' / x['filename']).read_bytes() for x in old['downloads']}
        self.notes['version'] = '0.1.1'
        self.packages = {platform: self.package(platform, version='0.1.1') for platform in sync.PLATFORMS}
        self.sync()
        paths, latest = sync.verify_catalog(self.public)
        self.assertEqual(latest['version'], '0.1.1')
        self.assertEqual(len(paths), 6)
        for name, raw in old_files.items():
            self.assertEqual((self.public / 'manager/downloads' / name).read_bytes(), raw)
        self.assertIn('v0.1.0', (self.public / 'manager/index.html').read_text())

    def test_same_version_different_bytes_rejected(self):
        self.sync()
        before = self.snapshot()
        self.package('win-x64', payload=b'changed')
        with self.assertRaisesRegex(ValueError, 'different archive hash'):
            sync.prepare(self.public, self.packages, self.notes)
        self.assertEqual(self.snapshot(), before)

    def test_preexisting_package_not_overwritten(self):
        destination = self.public / 'manager/downloads' / sync.package_filename('0.1.0', 'trial', 'win-x64')
        destination.parent.mkdir()
        destination.write_bytes(b'preexisting')
        with self.assertRaisesRegex(ValueError, 'immutable manager package'):
            sync.prepare(self.public, self.packages, self.notes)
        self.assertEqual(destination.read_bytes(), b'preexisting')

    def test_downgrade_rejected(self):
        self.sync()
        with self.assertRaisesRegex(ValueError, 'older manager version'):
            sync.prepare(self.public, self.packages, dict(self.notes, version='0.0.9'))

    def test_validation_channel_date_and_platform_required(self):
        for field in ('validation', 'changes', 'channel', 'published_at'):
            notes = copy.deepcopy(self.notes)
            del notes[field]
            with self.subTest(field=field), self.assertRaises(ValueError):
                sync.prepare(self.public, self.packages, notes)
        with self.assertRaisesRegex(ValueError, 'All three'):
            sync.prepare(self.public, {'win-x64': self.packages['win-x64']}, self.notes)

    def test_identity_and_architecture_rejected(self):
        with self.assertRaisesRegex(ValueError, 'release identity mismatch'):
            sync.read_package(self.package('win-x64', version='0.9.0'), '0.1.0', 'win-x64')
        for platform in sync.PLATFORMS:
            with self.subTest(platform=platform), self.assertRaisesRegex(ValueError, 'x64|architecture'):
                sync.read_package(self.package(platform, wrong_arch=True), '0.1.0', platform)

    def test_mac_executable_permissions_required(self):
        with self.assertRaisesRegex(ValueError, 'executable permissions'):
            sync.read_package(self.package('osx-arm64', executable_mode=0o644), '0.1.0', 'osx-arm64')

    def test_unsafe_paths_rejected(self):
        unsafe = ('../outside', '/outside', 'a/../outside', 'a\\outside', 'a:stream', 'a/thing.',
                  'WTF/private', 'a/SavedVariables/private', 'a/.env', 'settings.json', '__MACOSX/secret', 'README.txt',
                  'a//b', 'a/./b', 'CON.txt', 'a/invalid?file')
        for name in unsafe:
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'Unsafe'):
                sync.read_package(self.package('win-x64', extra=(name, 'data')), '0.1.0', 'win-x64')

    def test_symlink_and_case_collision_rejected(self):
        symlink = zipfile.ZipInfo('link')
        symlink.create_system = 3
        symlink.external_attr = (stat.S_IFLNK | 0o777) << 16
        for extra in ((symlink, '/outside'), ('readme.TXT', 'collision')):
            with self.subTest(extra=extra), self.assertRaisesRegex(ValueError, 'Unsafe'):
                sync.read_package(self.package('win-x64', extra=extra), '0.1.0', 'win-x64')

    def test_file_directory_collision_rejected(self):
        with self.assertRaisesRegex(ValueError, 'collision'):
            sync.read_package(self.package('win-x64', extra=('README.txt/file', 'data')), '0.1.0', 'win-x64')

    def test_verifier_rejects_manifest_checksum_and_page_changes(self):
        self.sync()
        metadata = self.public / 'manager/latest.json'
        original = metadata.read_bytes()
        data = json.loads(original)
        data['downloads'][0]['sha256'] = '0' * 64
        metadata.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, 'disagree'):
            sync.verify_catalog(self.public)
        metadata.write_bytes(original)
        page = self.public / 'manager/index.html'
        original_page = page.read_bytes()
        page.write_text(page.read_text().replace('下载 v0.1.0', '下载 v0.0.9'))
        with self.assertRaisesRegex(ValueError, 'Stale'):
            sync.verify_catalog(self.public)
        page.write_bytes(original_page)
        checksum = next((self.public / 'manager/downloads').glob('*.sha256'))
        checksum.write_text('wrong')
        with self.assertRaisesRegex(ValueError, 'checksum'):
            sync.verify_catalog(self.public)

    def test_dry_run_writes_nothing(self):
        notes = self.base / 'notes.json'
        notes.write_text(json.dumps(self.notes))
        before = self.snapshot()
        command = [sys.executable, str(sync.ROOT / 'ops/sync_manager_release.py'), '--public', str(self.public),
                   '--windows', str(self.packages['win-x64']), '--mac-arm64', str(self.packages['osx-arm64']),
                   '--mac-x64', str(self.packages['osx-x64']), '--notes', str(notes), '--dry-run']
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['status'], 'dry-run')
        self.assertEqual(self.snapshot(), before)

    def test_validation_text_is_html_escaped(self):
        self.notes['validation'] = ['<script>alert("test")</script>']
        self.sync()
        html = (self.public / 'manager/index.html').read_text()
        self.assertIn('&lt;script&gt;', html)
        self.assertNotIn('<script>alert', html)


if __name__ == '__main__':
    unittest.main(verbosity=2)
