#!/usr/bin/env python3
"""Isolated multi-add-on release transitions; never modify or deploy the live tree."""
import copy
from datetime import date, timedelta
import hashlib
import json
import re
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
import zipfile

import sync_professions_release as sync
import sync_release as chat


class ProfessionsReleaseTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix='mfp-release-test-')
        self.addCleanup(temp.cleanup)
        self.base = Path(temp.name)
        self.public = self.base / 'public'
        shutil.copytree(sync.ROOT / 'public', self.public)
        self.old = json.loads((self.public / 'professions/latest.json').read_text())
        self.chat_latest = (self.public / 'latest.json').read_bytes()
        self.chat_catalog = (self.public / 'releases.json').read_bytes()
        major, minor, patch = sync.version_key(self.old['version'])
        self.version = f'{major}.{minor}.{patch + 1}'
        # A fixture release must be later than the copied site's current dates;
        # historical hardcoded dates would correctly be kept from backdating it.
        dates = re.findall(r'<lastmod>(\d{4}-\d{2}-\d{2})</lastmod>', (self.public/'sitemap.xml').read_text())
        self.profession_date = (date.fromisoformat(max(dates)) + timedelta(days=1)).isoformat()
        self.chat_date = (date.fromisoformat(self.profession_date) + timedelta(days=1)).isoformat()
        self.notes = {'version': self.version, 'published_at': self.profession_date, 'channel': 'trial',
                      'compatibility': {'product': '国服魔兽世界：无限', 'client': '1.60.1'},
                      'changes': ['仅临时测试，不能发布。'], 'validation': ['脚本测试不是游戏实测。']}

    def package(self, version=None, content='TEST', extra=None, addon=sync.ADDON):
        path = self.base / 'fixture.zip'
        with zipfile.ZipFile(path, 'w') as z:
            z.writestr(f'{addon}/{addon}.toc', f'## Version: {version or self.version}\n## Interface: 16001\n')
            z.writestr(f'{addon}/Test.lua', content)
            if extra:
                z.writestr(*extra)
        return path

    def snapshot(self):
        return {str(p.relative_to(self.public)): hashlib.sha256(p.read_bytes()).hexdigest() for p in self.public.rglob('*') if p.is_file()}

    def verify(self):
        return subprocess.run([sys.executable, str(sync.ROOT/'ops/verify_site.py'), '--public', str(self.public)], capture_output=True, text=True)

    def test_transition_idempotence_and_chat_independence(self):
        package = self.package()
        updates, release = sync.prepare(self.public, package, self.notes)
        sync.apply(self.public, updates)
        self.assertEqual((self.public/'latest.json').read_bytes(), self.chat_latest)
        self.assertEqual((self.public/'releases.json').read_bytes(), self.chat_catalog)
        catalog = json.loads((self.public/'professions/releases.json').read_text())
        self.assertIn(self.old, catalog['releases'])
        self.assertEqual(catalog['latest'], self.version)
        self.assertEqual(release, json.loads((self.public/'professions/latest.json').read_text()))
        self.assertEqual(sync.prepare(self.public, package, self.notes)[0], {})
        check = self.verify()
        self.assertEqual(check.returncode, 0, check.stderr)

    def test_first_public_release(self):
        package = self.package()
        catalog = json.loads((self.public/'professions/releases.json').read_text())
        for record in catalog['releases']:
            p = self.public/'downloads'/record['download']['filename']
            p.unlink(); p.with_name(p.name+'.sha256').unlink()
        (self.public/'professions/latest.json').unlink()
        (self.public/'professions/releases.json').unlink()
        updates, _ = sync.prepare(self.public, package, self.notes)
        sync.apply(self.public, updates)
        self.assertEqual(len(json.loads((self.public/'professions/releases.json').read_text())['releases']), 1)
        self.assertEqual(self.verify().returncode, 0)

    def test_dry_run_does_not_write(self):
        package = self.package()
        notes = self.base/'notes.json'; notes.write_text(json.dumps(self.notes))
        before = self.snapshot()
        result = subprocess.run([sys.executable, str(sync.ROOT/'ops/sync_professions_release.py'), '--public', str(self.public), '--zip', str(package), '--notes', str(notes), '--dry-run'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['status'], 'dry-run')
        self.assertEqual(self.snapshot(), before)

    def test_immutable_package_and_release(self):
        package = self.package()
        sync.apply(self.public, sync.prepare(self.public, package, self.notes)[0])
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, 'different archive hash'):
            sync.prepare(self.public, self.package(content='changed'), self.notes)
        self.assertEqual(before, self.snapshot())
        major, minor, patch = sync.version_key(self.version)
        newer = f'{major}.{minor}.{patch + 1}'
        notes = dict(self.notes, version=newer)
        (self.public/'downloads'/f'{sync.ADDON}-{newer}-Trial.zip').write_bytes(b'preexisting')
        with self.assertRaisesRegex(ValueError, 'immutable package'):
            sync.prepare(self.public, self.package(version=newer), notes)

    def test_notes_and_identity_rejected(self):
        package = self.package()
        for key in ('validation', 'channel', 'compatibility'):
            notes = copy.deepcopy(self.notes); notes.pop(key)
            with self.subTest(key=key), self.assertRaises(ValueError):
                sync.prepare(self.public, package, notes)
        with self.assertRaisesRegex(ValueError, 'older version'):
            sync.prepare(self.public, self.package(version='0.0.0'), dict(self.notes, version='0.0.0'))
        with self.assertRaisesRegex(ValueError, 'unexpected add-on root'):
            sync.prepare(self.public, self.package(addon='MyForeverChat'), self.notes)
        current = json.loads((self.public/'professions/latest.json').read_text())
        current['name'] = 'MyForeverChat'
        (self.public/'professions/latest.json').write_text(json.dumps(current))
        with self.assertRaisesRegex(ValueError, 'identity mismatch'):
            sync.prepare(self.public, self.package(), self.notes)

    def test_private_traversal_duplicate_and_symlink_members(self):
        for name in ('../secret', '/absolute', 'WTF/Account/test.lua', 'MyForeverProfessions/SavedVariables/test.lua', 'MyForeverProfessions/../secret', 'MyForeverProfessions/.env', 'MyForeverProfessions/Test.lua'):
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'Unsafe'):
                sync.prepare(self.public, self.package(extra=(name, 'TEST')), self.notes)
        info = zipfile.ZipInfo('MyForeverProfessions/link'); info.create_system = 3; info.external_attr = (stat.S_IFLNK | 0o777) << 16
        with self.assertRaisesRegex(ValueError, 'Unsafe'):
            sync.prepare(self.public, self.package(extra=(info, '/outside')), self.notes)

    def test_metadata_and_checksum_mismatch_block_verifier(self):
        p = self.public/'professions/latest.json'
        original = p.read_bytes(); data=json.loads(original); data['download']['filename']='MyForeverChat-0.9.0-Trial.zip';p.write_text(json.dumps(data))
        self.assertNotEqual(self.verify().returncode, 0)
        p.write_bytes(original)
        sidecar = self.public/'downloads'/(self.old['download']['filename']+'.sha256');sidecar.write_text('wrong')
        self.assertNotEqual(self.verify().returncode, 0)

    def test_sitemap_updates_only_target_when_order_reversed(self):
        path=self.public/'sitemap.xml'; text=path.read_text()
        import re
        entries=re.findall(r'<url>.*?</url>', text, re.S)
        self.assertGreaterEqual(len(entries), 3)
        manager_entries = [entry for entry in entries if '<loc>https://afabiaoge.xyz/manager/</loc>' in entry]
        path.write_text(re.sub(r'<url>.*</url>', ''.join(reversed(entries)), text, flags=re.S))
        changes,_=sync.prepare(self.public,self.package(),self.notes)
        sync.apply(self.public,changes)
        current=json.loads(self.chat_latest)
        changes,_=chat.prepare(self.public,self.public/'downloads'/current['download']['filename'],current)
        sync.apply(self.public,changes)
        final=path.read_text()
        self.assertIn('<loc>https://afabiaoge.xyz/professions/</loc><lastmod>' + self.profession_date + '</lastmod>',final)
        self.assertEqual(len(re.findall(r'<url>.*?</url>', final, re.S)), len(entries))
        for manager_entry in manager_entries:
            self.assertIn(manager_entry, final)

    def test_both_publish_orders_keep_other_addon_and_portal_current(self):
        original = self.base/'original-site'
        shutil.copytree(self.public, original)
        initial_portal_date = re.search(r'<loc>https://afabiaoge.xyz/</loc><lastmod>([^<]+)</lastmod>',
                                       (original/'sitemap.xml').read_text())[1]
        for order in (('chat', 'professions'), ('professions', 'chat')):
            with self.subTest(order=order):
                shutil.rmtree(self.public)
                shutil.copytree(original, self.public)
                for kind in order:
                    if kind == 'chat':
                        other_files = [self.public/'professions/latest.json', self.public/'professions/releases.json', self.public/'professions/index.html']
                        current = json.loads(self.chat_latest)
                        major, minor, patch = chat.version_key(current['version'])
                        version = f'{major}.{minor}.{patch + 1}'
                        notes = dict(self.notes, version=version, published_at=self.chat_date)
                        package = self.package(version=version, addon='MyForeverChat')
                        operation = chat
                    else:
                        other_files = [self.public/'latest.json', self.public/'releases.json', self.public/'chat/index.html']
                        notes, package, operation = self.notes, self.package(), sync
                    before = {p:p.read_bytes() for p in other_files}
                    operation.apply(self.public, operation.prepare(self.public, package, notes)[0])
                    for p, raw in before.items():
                        self.assertEqual(p.read_bytes(), raw)
                    portal = (self.public/'index.html').read_text()
                    self.assertEqual(portal.count('class="addon-card"'), 4)
                    navigator = json.loads((self.public/'navigator/latest.json').read_text())
                    self.assertIn('data-addon="MyForeverNavigator"', portal)
                    self.assertIn('/downloads/' + navigator['download']['filename'], portal)
                    targets = json.loads((self.public/'targets/latest.json').read_text())
                    self.assertEqual((self.public/'targets/latest.json').read_bytes(), (original/'targets/latest.json').read_bytes())
                    self.assertIn('data-addon="MyForeverTargets"', portal)
                    self.assertIn('/downloads/' + targets['download']['filename'], portal)
                    for addon, metadata in [('MyForeverChat', 'latest.json'), ('MyForeverProfessions', 'professions/latest.json')]:
                        latest = json.loads((self.public/metadata).read_text())
                        card = re.search(r'<article class="addon-card" data-addon="' + addon + r'">(.*?)</article>', portal, re.S)[1]
                        self.assertIn('v' + latest['version'], card)
                        self.assertIn(latest['published_at'], card)
                        self.assertIn(f"{latest['download']['size_bytes'] / 1024:.1f} KiB", card)
                        self.assertIn('href="/downloads/' + latest['download']['filename'] + '"', card)
                        other_addon = 'MyForeverProfessions' if addon == 'MyForeverChat' else 'MyForeverChat'
                        self.assertNotIn(other_addon, card)
                # Repeating both releases in either order cannot undo the portal
                # date, duplicate cards, or alter an unrelated detail page.
                for kind in ('chat', 'professions', 'chat', 'professions'):
                    operation = chat if kind == 'chat' else sync
                    metadata = 'latest.json' if kind == 'chat' else 'professions/latest.json'
                    current = json.loads((self.public/metadata).read_text())
                    package = self.public/'downloads'/current['download']['filename']
                    self.assertEqual(operation.prepare(self.public, package, current)[0], {})
                sitemap = (self.public/'sitemap.xml').read_text()
                self.assertIn('<loc>https://afabiaoge.xyz/</loc><lastmod>' + max(initial_portal_date, self.chat_date) + '</lastmod>', sitemap)
                self.assertIn('<loc>https://afabiaoge.xyz/chat/</loc><lastmod>' + self.chat_date + '</lastmod>', sitemap)
                self.assertIn('<loc>https://afabiaoge.xyz/professions/</loc><lastmod>' + self.profession_date + '</lastmod>', sitemap)
                result = self.verify()
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_or_duplicate_portal_marker_has_no_partial_write(self):
        path = self.public/'index.html'
        original = path.read_text()
        for text in (original.replace('<!-- release:catalog:start -->', ''),
                     original + '<!-- release:catalog:start --><!-- release:catalog:end -->',
                     original.replace('<!-- release:catalog:start -->', '<!-- release:catalog:start --><!-- release:catalog:start -->')):
            path.write_text(text)
            before = self.snapshot()
            with self.assertRaisesRegex(ValueError, 'release marker'):
                sync.prepare(self.public, self.package(), self.notes)
            self.assertEqual(self.snapshot(), before)
        path.write_text(original)

    def test_stale_portal_download_is_rejected(self):
        path = self.public/'index.html'
        original = path.read_text()
        path.write_text(original.replace('/downloads/' + self.old['download']['filename'], '/downloads/' + json.loads(self.chat_latest)['download']['filename']))
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('portal cards', result.stderr)

    def test_symlink_output_rejected(self):
        package=self.package(); target=self.public/'downloads'/f'{sync.ADDON}-{self.version}-Trial.zip'
        target.symlink_to(package)
        with self.assertRaisesRegex(ValueError,'symlink'):
            sync.prepare(self.public,package,self.notes)


if __name__ == '__main__':
    unittest.main(verbosity=2)
