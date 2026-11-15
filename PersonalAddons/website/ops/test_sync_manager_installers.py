#!/usr/bin/env python3
"""Isolated installer/feed release regressions; no network or real app execution."""
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import struct
import tempfile
import unittest
import zipfile

import sync_manager_installers as sync
import sync_manager_release as legacy
from manager_installers import read_update_package
from test_sync_manager_release import ManagerReleaseTests


class InstallerTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='manager-installers-test-')
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.public, self.build = self.base / 'public', self.base / 'build'
        (self.public / 'manager').mkdir(parents=True)
        self.build.mkdir()
        shutil.copy2(sync.ROOT / 'public/manager/index.html', self.public / 'manager/index.html')
        shutil.copy2(sync.ROOT / 'public/sitemap.xml', self.public / 'sitemap.xml')
        fixtures = ManagerReleaseTests()
        fixtures.base = self.base
        notes = {'version': '0.4.0', 'published_at': '2026-11-14', 'channel': 'trial', 'changes': ['Old fixture'], 'validation': ['Not real binaries']}
        output, _ = legacy.prepare(self.public, {rid: fixtures.package(rid, '0.4.0') for rid in legacy.PLATFORMS}, notes)
        sync.apply(self.public, output)
        self.notes = dict(notes, version='0.5.0', published_at='2026-11-15')
        manifest = {'name': 'MyForeverManager', 'version': '0.5.0', 'package_id': 'MyForeverManagerApp',
                    'candidate': False, 'source_dirty': False, 'published': False, 'source_commit': 'f' * 40, 'artifacts': []}
        for rid in legacy.PLATFORMS:
            pe = bytearray(200); pe[:2] = b'MZ'; struct.pack_into('<I', pe, 60, 128); pe[128:132] = b'PE\0\0'; struct.pack_into('<H', pe, 132, 0x8664)
            filename = sync.installer_filename('0.5.0', 'trial', rid)
            raw = bytes(pe) if rid == 'win-x64' else b'koly' + bytes(508)
            (self.build / filename).write_bytes(raw)
            folder = self.build / 'updates' / rid; folder.mkdir(parents=True)
            name = f'MyForeverManagerApp-0.5.0-{rid}-full.nupkg'
            with zipfile.ZipFile(folder / name, 'w') as archive:
                archive.writestr('MyForeverManagerApp.nuspec', '<package><metadata><id>MyForeverManagerApp</id><version>0.5.0</version><channel>'+rid+'</channel><rid>'+rid+'</rid></metadata></package>')
                prefix = 'lib/app/'
                identity = {'name': 'MyForeverManager', 'version': '0.5.0', 'platform': rid}
                if rid == 'win-x64':
                    archive.writestr(prefix + 'manager-release.json', json.dumps(identity))
                    archive.writestr(prefix + 'MyForeverManager.exe', pe)
                else:
                    archive.writestr(prefix + 'Contents/Resources/manager-release.json', json.dumps(identity))
                    archive.writestr(prefix + 'Contents/MacOS/MyForeverManager', b'\xcf\xfa\xed\xfe' + struct.pack('<I', 0x100000c if rid == 'osx-arm64' else 0x1000007))
                    archive.writestr(prefix + 'Contents/Info.plist', plistlib.dumps({'CFBundleVersion': '0.5.0', 'CFBundleIdentifier': 'xyz.afabiaoge.manager'}))
            package = (folder / name).read_bytes()
            feed = {'Assets': [{'PackageId': 'MyForeverManagerApp', 'Version': '0.5.0', 'Type': 'Full', 'FileName': name,
                                'Size': len(package), 'SHA256': hashlib.sha256(package).hexdigest().upper()}]}
            (folder / f'releases.{rid}.json').write_text(json.dumps(feed))
            manifest['artifacts'].append({'platform': rid, 'version': '0.5.0', 'installer': filename,
                'feed': 'updates/' + rid, 'update_probe_fixture': False, 'size_bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()})
        self.manifest = manifest
        self.write_manifest()

    def write_manifest(self):
        (self.build / 'INSTALLERS.json').write_text(json.dumps(self.manifest))

    def stage(self):
        output, release = sync.prepare(self.public, self.build, self.notes)
        sync.apply(self.public, output)
        return release

    def test_installer_release_preserves_legacy_and_is_idempotent(self):
        old = {p.name: p.read_bytes() for p in (self.public / 'manager/downloads').glob('*.zip')}
        release = self.stage()
        paths, latest = legacy.verify_catalog(self.public)
        self.assertEqual(latest, release)
        self.assertEqual(len(paths), 9)
        self.assertEqual(sync.prepare(self.public, self.build, self.notes)[0], {})
        for name, raw in old.items(): self.assertEqual((self.public / 'manager/downloads' / name).read_bytes(), raw)
        self.assertEqual(latest['downloads'][0]['platform'], 'osx-arm64')

    def test_candidate_dirty_and_probe_builds_rejected(self):
        for field in ('candidate', 'source_dirty', 'published'):
            self.manifest[field] = True; self.write_manifest()
            with self.assertRaises(ValueError): sync.prepare(self.public, self.build, self.notes)
            self.manifest[field] = False
        self.manifest['artifacts'][0]['update_probe_fixture'] = True; self.write_manifest()
        with self.assertRaises(ValueError): sync.prepare(self.public, self.build, self.notes)

    def test_same_version_changed_notes_rejected(self):
        self.stage()
        with self.assertRaisesRegex(ValueError, 'immutable'):
            sync.prepare(self.public, self.build, dict(self.notes, changes=['Changed after publication']))

    def test_existing_installer_never_overwritten(self):
        name = self.manifest['artifacts'][0]['installer']
        (self.public / 'manager/downloads' / name).write_bytes(b'original')
        with self.assertRaisesRegex(ValueError, 'immutable'): sync.prepare(self.public, self.build, self.notes)

    def test_wrong_feed_hash_rejected(self):
        p = self.build / 'updates/osx-arm64/releases.osx-arm64.json'
        data = json.loads(p.read_text()); data['Assets'][0]['SHA256'] = '0' * 64; p.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, 'checksum'): sync.prepare(self.public, self.build, self.notes)

    def test_wrong_feed_path_and_missing_platform_rejected(self):
        p = self.build / 'updates/osx-arm64/releases.osx-arm64.json'
        data = json.loads(p.read_text()); data['Assets'][0]['FileName'] = '../other.nupkg'; p.write_text(json.dumps(data))
        with self.assertRaises(ValueError): sync.prepare(self.public, self.build, self.notes)
        self.manifest['artifacts'].pop(); self.write_manifest()
        with self.assertRaises(ValueError): sync.prepare(self.public, self.build, self.notes)

    def test_active_feed_tampering_detected(self):
        self.stage()
        p = self.public / 'manager/updates/osx-arm64/releases.osx-arm64.json'
        data = json.loads(p.read_text()); data['Assets'][0]['Version'] = '0.5.1'; p.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, 'Active update feed'): legacy.verify_catalog(self.public)

    def test_private_or_traversing_update_content_rejected(self):
        path = next((self.build / 'updates/win-x64').glob('*.nupkg'))
        for name in ('lib/app/settings.json', '../escape.txt'):
            with zipfile.ZipFile(path, 'a') as archive: archive.writestr(name, 'fixture')
            with self.assertRaisesRegex(ValueError, 'Unsafe update member'): read_update_package(path, '0.5.0', 'win-x64')

    def test_installer_and_package_hash_tampering_detected(self):
        self.stage()
        p = self.public / ('manager/downloads/' + self.manifest['artifacts'][0]['installer'])
        p.write_bytes(p.read_bytes() + b'changed')
        with self.assertRaises(ValueError): legacy.verify_catalog(self.public)


if __name__ == '__main__':
    unittest.main(verbosity=2)
