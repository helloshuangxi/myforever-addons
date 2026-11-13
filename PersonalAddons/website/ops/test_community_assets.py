#!/usr/bin/env python3
"""Verify dynamic community images and donation activation gates in temporary sites."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class CommunityAssetTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='mfc-assets-test-')
        self.addCleanup(self.temp.cleanup)
        self.public = Path(self.temp.name) / 'public'
        shutil.copytree(ROOT / 'public', self.public)
        current_config = json.loads((self.public / 'community-config.json').read_text())
        self.config = {'author': {'avatar_url': current_config['author']['avatar_url']}, 'donation': {'enabled': False, 'qr_url': '', 'amounts': {}}}

    def verify(self):
        (self.public / 'community-config.json').write_text(json.dumps(self.config))
        return subprocess.run([sys.executable, str(ROOT / 'ops/verify_site.py'), '--public', str(self.public)], capture_output=True, text=True)

    def test_disabled_donations_allow_empty_qr(self):
        self.assertEqual(self.verify().returncode, 0)

    def test_enabled_donations_require_each_amount(self):
        self.config['donation']['enabled'] = True
        self.assertNotEqual(self.verify().returncode, 0)
        # Existing local image is only a validator fixture, never a real payment code.
        self.config['donation']['amounts'] = {'1': {'qr_url': 'assets/chat-overview.jpg'}}
        self.assertNotEqual(self.verify().returncode, 0)
        self.config['donation']['qr_url'] = 'assets/chat-overview.jpg'
        self.assertEqual(self.verify().returncode, 0)

    def test_external_traversal_and_script_images_are_rejected(self):
        for url in ['https://external.example/code.png', '//external.example/code.png', 'assets/../index.html', 'assets/%2e%2e/index.html', 'script.js', 'assets/missing.png', 'data:image/png;base64,aaaa']:
            with self.subTest(url=url):
                self.config['author']['avatar_url'] = url
                self.assertNotEqual(self.verify().returncode, 0)

    def test_mixed_native_qr_images_and_style_metadata(self):
        self.config['donation'] = {'enabled': True, 'qr_presentation': 'alipay-screenshot', 'provider': '支付宝', 'amounts': {amount: {'qr_url': 'assets/donation-' + amount + ('.png' if amount == '20' else '.jpg')} for amount in ('1', '5', '20', '100')}}
        self.assertEqual(self.verify().returncode, 0)
        (self.public / 'assets/bad-encoding.png').write_bytes(b'not a PNG')
        self.config['donation']['amounts']['20']['qr_url'] = 'assets/bad-encoding.png'
        self.assertNotEqual(self.verify().returncode, 0)

    def test_private_database_cannot_enter_public(self):
        (self.public / 'suggestions.sqlite3').write_bytes(b'PRIVATE FIXTURE')
        self.assertNotEqual(self.verify().returncode, 0)

if __name__ == '__main__':
    unittest.main(verbosity=2)
