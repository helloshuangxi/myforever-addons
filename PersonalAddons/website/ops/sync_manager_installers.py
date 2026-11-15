#!/usr/bin/env python3
"""Stage audited DMG/Setup and self-update feeds, preserving published bytes."""
import argparse
import copy
import datetime
import json
from pathlib import Path

from manager_installers import PACKAGE_ID, BASE, installer_filename, read_installer, read_update_package
from sync_manager_release import NAME, HOMEPAGE, PLATFORMS, render
from sync_release import ROOT, CHANNELS, apply, json_bytes, nonempty_strings, update_sitemap, version_key


def prepare(public, build, notes):
    public, build = Path(public), Path(build)
    manifest = json.loads((build / 'INSTALLERS.json').read_text())
    version = notes.get('version')
    version_key(version)
    date, channel = notes.get('published_at', ''), notes.get('channel')
    datetime.date.fromisoformat(date)
    if channel not in CHANNELS or manifest['version'] != version or manifest['package_id'] != PACKAGE_ID:
        raise ValueError('Installer version/channel/identity mismatch')
    if manifest['candidate'] or manifest['source_dirty'] or manifest['published'] or any(x['update_probe_fixture'] for x in manifest['artifacts']):
        raise ValueError('Release requires clean authorized build without probe entry points')
    if len(manifest['artifacts']) != 3 or {x['platform'] for x in manifest['artifacts']} != set(PLATFORMS):
        raise ValueError('All three installer platforms are required')
    changes = nonempty_strings(notes.get('changes'), 'changes')
    validation = nonempty_strings(notes.get('validation'), 'validation')
    folder = public / 'manager'
    catalog = json.loads((folder / 'releases.json').read_text())
    current = json.loads((folder / 'latest.json').read_text())
    if (catalog.get('name') != NAME or current.get('name') != NAME or current.get('homepage') != HOMEPAGE or
            catalog['latest'] != current['version'] or next(x for x in catalog['releases'] if x['version'] == catalog['latest']) != current):
        raise ValueError('Manager history and latest disagree')
    if version_key(version) < version_key(current['version']):
        raise ValueError('Refusing to downgrade manager release')
    catalog = copy.deepcopy(catalog)
    output, downloads, feeds = {}, [], []
    for artifact in sorted(manifest['artifacts'], key=lambda x: ['osx-arm64', 'win-x64', 'osx-x64'].index(x['platform'])):
        rid = artifact['platform']
        filename = installer_filename(version, channel, rid)
        if artifact['installer'] != filename or artifact['feed'] != 'updates/' + rid or artifact['version'] != version:
            raise ValueError('Installer manifest paths mismatch')
        raw, digest = read_installer(build / filename, rid)
        if digest != artifact['sha256'] or len(raw) != artifact['size_bytes']:
            raise ValueError('Installer build checksum mismatch')
        relative = 'manager/downloads/' + filename
        output[relative] = raw
        output[relative + '.sha256'] = (digest + '  ' + filename + '\n').encode()
        downloads.append({'platform': rid, 'format': 'setup' if rid == 'win-x64' else 'dmg', 'filename': filename,
                          'url': BASE + 'downloads/' + filename, 'size_bytes': len(raw), 'sha256': digest})
        feed_name = 'releases.' + rid + '.json'
        feed_bytes = (build / artifact['feed'] / feed_name).read_bytes()
        assets = json.loads(feed_bytes)['Assets']
        update_name = f'{PACKAGE_ID}-{version}-{rid}-full.nupkg'
        if len(assets) != 1 or assets[0].get('FileName') != update_name:
            raise ValueError('Unexpected update feed member')
        update, update_digest = read_update_package(build / artifact['feed'] / update_name, version, rid)
        if any(assets[0].get(k) != v for k, v in {'PackageId': PACKAGE_ID, 'Version': version, 'Type': 'Full',
              'Size': len(update), 'SHA256': update_digest.upper()}.items()):
            raise ValueError('Feed checksum/identity does not match update package')
        feed_root = 'manager/updates/' + rid + '/'
        output[feed_root + update_name] = update
        output[feed_root + feed_name] = feed_bytes
        feeds.append({'platform': rid, 'feed_url': 'https://afabiaoge.xyz/' + feed_root + feed_name,
                      'package': {'filename': update_name, 'url': 'https://afabiaoge.xyz/' + feed_root + update_name,
                                  'size_bytes': len(update), 'sha256': update_digest}})
    release = {'schema_version': 1, 'name': NAME, 'display_name': '我的无限 · 插件管理器', 'homepage': HOMEPAGE,
               'version': version, 'channel': channel, 'published_at': date, 'changes': changes, 'validation': validation,
               'requirements': {k: v[2] for k, v in PLATFORMS.items()}, 'downloads': downloads,
               'source': {'repository': 'https://github.com/helloshuangxi/myforever-addons', 'commit': manifest['source_commit']},
               'self_update': {'package_id': PACKAGE_ID, 'feeds': feeds}}
    prior = next((x for x in catalog['releases'] if x['version'] == version), None)
    if prior and prior != release:
        raise ValueError('Published installer version is immutable')
    for name, raw in output.items():
        destination = public / name
        if any(p.is_symlink() for p in [destination, *destination.parents] if p == public or public in p.parents):
            raise ValueError('Symlink in installer output path')
        if destination.exists() and destination.read_bytes() != raw and not name.endswith('.json'):
            raise ValueError('Refusing to overwrite immutable release artifact')
    catalog['latest'] = version
    catalog['releases'] = sorted([release] + [x for x in catalog['releases'] if x['version'] != version], key=lambda x: version_key(x['version']), reverse=True)
    output.update({'manager/latest.json': json_bytes(release), 'manager/releases.json': json_bytes(catalog),
                   'manager/index.html': render((folder / 'index.html').read_text(), catalog).encode(),
                   'sitemap.xml': update_sitemap((public / 'sitemap.xml').read_text(), {HOMEPAGE: date}).encode()})
    return {k: v for k, v in output.items() if not (public / k).exists() or (public / k).read_bytes() != v}, release


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', required=True, type=Path)
    parser.add_argument('--notes', required=True, type=Path)
    parser.add_argument('--public', default=ROOT / 'public', type=Path)
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    updates, release = prepare(args.public, args.build, json.loads(args.notes.read_text()))
    if not args.dry_run:
        apply(args.public, updates)
    print(json.dumps({'status': 'dry-run' if args.dry_run else 'synced', 'version': release['version'],
                      'changed_files': list(updates)}, indent=2))


if __name__ == '__main__':
    main()
