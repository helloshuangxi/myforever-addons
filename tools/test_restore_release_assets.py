import tempfile
from pathlib import Path
import unittest

import restore_release_assets as restore


class RestorePaths(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        previous = restore.PUBLIC
        restore.PUBLIC = Path(temporary.name) / 'public'
        self.addCleanup(setattr, restore, 'PUBLIC', previous)

    def item(self, folder, name):
        return {'url': 'https://afabiaoge.xyz/' + folder + '/' + name,
                'filename': name, 'size_bytes': 10, 'sha256': 'a' * 64}

    def test_supported_installers_and_architecture_feeds(self):
        for folder, name in [('downloads', 'Addon.zip'), ('manager/downloads', 'Manager.dmg'),
                             ('manager/downloads', 'Manager.exe'), ('manager/downloads', 'Old.zip'),
                             ('manager/updates/osx-arm64', 'App.nupkg'), ('manager/updates/win-x64', 'App.nupkg')]:
            with self.subTest(folder=folder, name=name):
                path, _, _ = restore.validated_download(self.item(folder, name))
                self.assertTrue(path.is_relative_to(restore.PUBLIC))

    def test_private_wrong_platform_and_wrong_extension_paths_rejected(self):
        for folder, name in [('WTF', 'App.zip'), ('downloads', 'App.exe'), ('manager/downloads', 'App.nupkg'),
                             ('manager/updates/other', 'App.nupkg'), ('manager/updates/osx-arm64', 'App.exe'),
                             ('manager/downloads/../../WTF', 'App.dmg')]:
            with self.subTest(folder=folder, name=name), self.assertRaises(ValueError):
                restore.validated_download(self.item(folder, name))

    def test_wrong_host_query_fragment_and_filename_rejected(self):
        base = self.item('manager/downloads', 'App.dmg')
        for url in [base['url'].replace('https:', 'http:'), base['url'].replace('afabiaoge.xyz', 'other.example'),
                    base['url'] + '?redirect=x', base['url'] + '#x', base['url'].replace('App.dmg', 'Other.dmg')]:
            with self.subTest(url=url), self.assertRaises(ValueError):
                restore.validated_download(dict(base, url=url))

    def test_symlink_under_public_rejected(self):
        restore.PUBLIC.mkdir()
        (restore.PUBLIC / 'manager').symlink_to(restore.PUBLIC / 'outside', target_is_directory=True)
        with self.assertRaises(ValueError):
            restore.validated_download(self.item('manager/downloads', 'App.dmg'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
