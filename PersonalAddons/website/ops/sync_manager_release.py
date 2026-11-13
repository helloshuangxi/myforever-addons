#!/usr/bin/env python3
"""Audit and publish desktop manager packages without changing add-on versions.

Dry runs never write or connect. Published package bytes are immutable.
"""
from __future__ import annotations

import argparse
import copy
import datetime as dt
import hashlib
import html
import io
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import stat
import struct
import subprocess
import sys
import zipfile

from sync_release import ROOT, CHANNELS, apply, json_bytes, marked, nonempty_strings, update_sitemap, version_key

NAME = 'MyForeverManager'
HOMEPAGE = 'https://afabiaoge.xyz/manager/'
PLATFORMS = {
    'win-x64': ('Windows', '64 位 · Intel / AMD', 'Windows 10 / 11 64 位'),
    'osx-arm64': ('macOS · Apple 芯片', 'M 系列 Mac', 'macOS 14 或更新版本 · Apple silicon'),
    'osx-x64': ('macOS · Intel', 'Intel 处理器 Mac', 'macOS 14 或更新版本 · Intel'),
}
PRIVATE = re.compile(r'^(?:WTF|SavedVariables|backups?|node_modules|ops|settings\.json|config\.json|\.env.*|\.git|\.DS_Store|__MACOSX)$', re.I)
MAX_ARCHIVE = 300 * 1024 * 1024
MAX_EXPANDED = 650 * 1024 * 1024


def package_filename(version, channel, platform):
    return f'{NAME}-{version}' + ('-Trial' if channel == 'trial' else '') + f'-{platform}.zip'


def read_package(path, version, platform):
    """Check portable package boundaries and executable identity before publishing."""
    version_key(version)
    if platform not in PLATFORMS:
        raise ValueError('Unknown manager platform')
    path = Path(path)
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= MAX_ARCHIVE:
        raise ValueError('Missing, linked, empty or oversized manager package')
    raw = path.read_bytes()
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        entries = archive.infolist()
        if not 1 <= len(entries) <= 10000 or sum(x.file_size for x in entries) > MAX_EXPANDED:
            raise ValueError('Manager package exceeds extraction limits')
        seen, files = set(), set()
        for entry in entries:
            name = entry.filename
            parts = PurePosixPath(name).parts
            normalized = name.rstrip('/').casefold()
            mode = (entry.external_attr >> 16) & 0o170000
            if (not parts or name.startswith('/') or '\\' in name or ':' in name or '\x00' in name
                    or '/'.join(parts) != name.rstrip('/')
                    or any(p in ('.', '..') or p.rstrip(' .') != p or PRIVATE.fullmatch(p) or p.startswith('.')
                           or any(ord(c) < 32 or c in '<>"|?*' for c in p)
                           or re.match(r'^(?:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)', p, re.I) for p in parts)
                    or normalized in seen or mode not in (0, stat.S_IFREG, stat.S_IFDIR)
                    or entry.flag_bits & 1):
                raise ValueError('Unsafe manager ZIP member: ' + name)
            if any('/'.join(parts[:i]).casefold() in files for i in range(1, len(parts))):
                raise ValueError('Manager ZIP file/directory collision')
            if not entry.is_dir():
                if any(s.startswith(normalized + '/') for s in seen):
                    raise ValueError('Manager ZIP file/directory collision')
                files.add(normalized)
            seen.add(normalized)
        required = {'manager-release.json', 'README.txt', 'LICENSE.txt'}
        names = {x.filename for x in entries if not x.is_dir()}
        if not required <= names:
            raise ValueError('Manager package requires release identity, README and license')
        if archive.getinfo('manager-release.json').file_size > 4096:
            raise ValueError('Oversized manager release identity')
        identity = json.loads(archive.read('manager-release.json'))
        if identity != {'name': NAME, 'version': version, 'platform': platform}:
            raise ValueError('Manager package release identity mismatch')
        if platform == 'win-x64':
            executable = 'MyForeverManager.exe'
            if executable not in names:
                raise ValueError('Missing Windows executable')
            with archive.open(executable) as stream:
                header = stream.read(4096)
            if header[:2] != b'MZ' or len(header) < 64:
                raise ValueError('Invalid Windows executable signature')
            pe_offset = struct.unpack_from('<I', header, 60)[0]
            if pe_offset + 6 > len(header) or header[pe_offset:pe_offset + 4] != b'PE\0\0' or struct.unpack_from('<H', header, pe_offset + 4)[0] != 0x8664:
                raise ValueError('Windows executable must target x64')
            if any(n.startswith('MyForeverManager.app/') for n in names):
                raise ValueError('Wrong platform bundle')
        else:
            bundle = 'MyForeverManager.app/Contents/'
            executable = bundle + 'MacOS/MyForeverManager'
            if executable not in names or bundle + 'Info.plist' not in names:
                raise ValueError('Missing macOS app bundle')
            with archive.open(executable) as stream:
                header = stream.read(8)
            if len(header) != 8 or header[:4] != b'\xcf\xfa\xed\xfe':
                raise ValueError('Invalid macOS executable signature')
            cpu = struct.unpack_from('<I', header, 4)[0]
            if cpu != (0x100000c if platform == 'osx-arm64' else 0x1000007):
                raise ValueError('macOS executable architecture mismatch')
            executable_mode = archive.getinfo(executable).external_attr >> 16
            if not executable_mode & 0o111:
                raise ValueError('macOS launcher must preserve executable permissions')
            if archive.getinfo(bundle + 'Info.plist').file_size > 1024 * 1024:
                raise ValueError('Oversized app plist')
            plist = plistlib.loads(archive.read(bundle + 'Info.plist'))
            if plist.get('CFBundleExecutable') != 'MyForeverManager' or plist.get('CFBundleShortVersionString') != version:
                raise ValueError('macOS app identity mismatch')
        # Read all members for CRC verification, not only the launcher.
        if archive.testzip() is not None:
            raise ValueError('Corrupt manager ZIP member')
    return raw, hashlib.sha256(raw).hexdigest()


def render(document, catalog):
    release = next(x for x in catalog['releases'] if x['version'] == catalog['latest'])
    esc = html.escape
    cards = []
    for record in release['downloads']:
        title, subtitle, requirement = PLATFORMS[record['platform']]
        href = '/manager/downloads/' + record['filename']
        cards.append(f'''<article class="manager-download-card" data-platform="{record['platform']}">
<p class="manager-platform-note">{esc(subtitle)}</p><h3>{esc(title)}</h3>
<p class="manager-system">{esc(requirement)}</p>
<a class="button" href="{href}" download>下载 v{esc(release['version'])} {CHANNELS[release['channel']]} <span aria-hidden="true">↓</span></a>
<p class="download-meta">ZIP · {record['size_bytes'] / (1024 * 1024):.1f} MiB · {esc(release['published_at'])}</p>
<details class="manager-digest"><summary>校验下载文件</summary><p>SHA-256</p><code>{record['sha256']}</code><a href="{href}.sha256">下载校验文件</a></details>
</article>''')
    changes = '<ul>' + ''.join('<li>' + esc(x) + '</li>' for x in release['changes']) + '</ul>'
    validation = ''.join('<p>' + esc(x) + '</p>' for x in release['validation'])
    history = []
    for entry in catalog['releases']:
        if entry['version'] == release['version']:
            continue
        downloads = ' · '.join('<a href="/manager/downloads/' + esc(x['filename']) + '">' + esc(PLATFORMS[x['platform']][0]) + '</a>' for x in entry['downloads'])
        history.append('<details><summary>v' + esc(entry['version']) + ' · ' + esc(entry['published_at']) + '</summary><ul>' + ''.join('<li>' + esc(x) + '</li>' for x in entry['changes']) + '</ul><p>' + downloads + '</p></details>')
    blocks = {'downloads': '\n'.join(cards), 'version': f'v{esc(release["version"])} · {CHANNELS[release["channel"]]}',
              'changes': changes, 'validation': validation, 'history': '\n'.join(history) or '<p>这是管理器的首个公开试用版本。</p>'}
    for name, value in blocks.items():
        document = marked(document, 'manager-' + name, value)
    return document


def prepare(public, packages, notes):
    public = Path(public)
    folder = public / 'manager'
    for path in (public, folder, folder / 'downloads'):
        if path.is_symlink():
            raise ValueError('Manager output directory cannot be a symlink')
    version = notes.get('version')
    version_key(version)
    channel, date = notes.get('channel'), notes.get('published_at', '')
    if channel not in CHANNELS:
        raise ValueError('Manager channel must explicitly be trial or stable')
    dt.date.fromisoformat(date)
    changes = nonempty_strings(notes.get('changes'), 'changes')
    validation = nonempty_strings(notes.get('validation'), 'validation')
    if set(packages) != set(PLATFORMS):
        raise ValueError('All three manager platforms must be provided')
    latest_path, catalog_path = folder / 'latest.json', folder / 'releases.json'
    if latest_path.exists() != catalog_path.exists():
        raise ValueError('Manager latest and history must exist together')
    if latest_path.exists():
        current = json.loads(latest_path.read_text())
        catalog = json.loads(catalog_path.read_text())
        if current.get('name') != NAME or current.get('homepage') != HOMEPAGE or catalog.get('name') != NAME:
            raise ValueError('Manager release identity mismatch')
        entries = catalog['releases']
        if len({x['version'] for x in entries}) != len(entries) or catalog['latest'] != current['version'] or next((x for x in entries if x['version'] == catalog['latest']), None) != current:
            raise ValueError('Manager latest and history disagree')
        if version_key(version) < version_key(catalog['latest']):
            raise ValueError('Refusing an older manager version as latest')
    else:
        catalog = {'schema_version': 1, 'name': NAME, 'latest': version, 'releases': []}
    prior = next((x for x in catalog['releases'] if x['version'] == version), None)
    if prior and (prior['published_at'] != date or prior['channel'] != channel):
        raise ValueError('Published manager date and channel are immutable')
    downloads, output = [], {}
    for platform in PLATFORMS:
        raw, digest = read_package(packages[platform], version, platform)
        filename = package_filename(version, channel, platform)
        relative = 'manager/downloads/' + filename
        destination = public / relative
        if prior and next((x['sha256'] for x in prior['downloads'] if x['platform'] == platform), None) != digest:
            raise ValueError('Manager version already exists with a different archive hash')
        if destination.exists() and hashlib.sha256(destination.read_bytes()).hexdigest() != digest:
            raise ValueError('Refusing to overwrite immutable manager package')
        record = {'platform': platform, 'filename': filename, 'url': HOMEPAGE + 'downloads/' + filename, 'size_bytes': len(raw), 'sha256': digest}
        downloads.append(record)
        output[relative] = raw
        output[relative + '.sha256'] = (digest + '  ' + filename + '\n').encode()
    release = {'schema_version': 1, 'name': NAME, 'display_name': '我的无限 · 插件管理器', 'homepage': HOMEPAGE,
               'version': version, 'channel': channel, 'published_at': date, 'changes': changes, 'validation': validation,
               'requirements': {key: value[2] for key, value in PLATFORMS.items()}, 'downloads': downloads}
    catalog['latest'] = version
    catalog['releases'] = sorted([release] + [x for x in catalog['releases'] if x['version'] != version], key=lambda x: version_key(x['version']), reverse=True)
    output.update({'manager/latest.json': json_bytes(release), 'manager/releases.json': json_bytes(catalog),
                   'manager/index.html': render((folder / 'index.html').read_text(), catalog).encode(),
                   'sitemap.xml': update_sitemap((public / 'sitemap.xml').read_text(), {HOMEPAGE: date}).encode()})
    for relative in output:
        if (public / relative).is_symlink():
            raise ValueError('Manager output cannot be a symlink: ' + relative)
    return {name: value for name, value in output.items() if not (public / name).exists() or (public / name).read_bytes() != value}, release


def verify_catalog(public):
    """Return package paths only after verifying all registered manager releases."""
    public = Path(public)
    folder = public / 'manager'
    if not (folder / 'latest.json').exists():
        if (folder / 'releases.json').exists() or list(folder.rglob('*.zip')):
            raise ValueError('Manager packages/history require latest metadata')
        return set(), None
    current = json.loads((folder / 'latest.json').read_text())
    catalog = json.loads((folder / 'releases.json').read_text())
    if current.get('name') != NAME or current.get('homepage') != HOMEPAGE or catalog.get('name') != NAME or catalog['latest'] != current['version']:
        raise ValueError('Manager catalog identity mismatch')
    entries = catalog['releases']
    if len({x['version'] for x in entries}) != len(entries) or next((x for x in entries if x['version'] == catalog['latest']), None) != current:
        raise ValueError('Manager latest and history disagree')
    registered = set()
    for release in entries:
        version_key(release['version'])
        if release['channel'] not in CHANNELS or release['name'] != NAME or release['homepage'] != HOMEPAGE:
            raise ValueError('Manager history identity mismatch')
        nonempty_strings(release.get('validation'), 'validation')
        records = release['downloads']
        if len(records) != len(PLATFORMS) or {x['platform'] for x in records} != set(PLATFORMS):
            raise ValueError('Manager history must have all three platforms')
        for record in records:
            filename = package_filename(release['version'], release['channel'], record['platform'])
            relative = 'manager/downloads/' + filename
            if record['filename'] != filename or record['url'] != HOMEPAGE + 'downloads/' + filename or relative in registered:
                raise ValueError('Manager download identity mismatch')
            raw, digest = read_package(public / relative, release['version'], record['platform'])
            if record['size_bytes'] != len(raw) or record['sha256'] != digest:
                raise ValueError('Manager archive digest mismatch')
            if (public / (relative + '.sha256')).read_text() != digest + '  ' + filename + '\n':
                raise ValueError('Manager checksum file mismatch')
            registered.add(relative)
    document = (folder / 'index.html').read_text()
    if render(document, catalog) != document:
        raise ValueError('Stale manager page/downloads/validation')
    return registered, current


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--windows', required=True, type=Path)
    parser.add_argument('--mac-arm64', required=True, type=Path)
    parser.add_argument('--mac-x64', required=True, type=Path)
    parser.add_argument('--notes', required=True, type=Path)
    parser.add_argument('--public', type=Path, default=ROOT / 'public')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--dry-run', action='store_true')
    mode.add_argument('--publish', action='store_true')
    args = parser.parse_args()
    try:
        packages = {'win-x64': args.windows, 'osx-arm64': args.mac_arm64, 'osx-x64': args.mac_x64}
        updates, release = prepare(args.public.absolute(), packages, json.loads(args.notes.read_text()))
        if not args.dry_run:
            apply(args.public.absolute(), updates)
        print(json.dumps({'status': 'dry-run' if args.dry_run else 'synced', 'name': NAME, 'version': release['version'],
                          'changed_files': list(updates), 'downloads': release['downloads']}, ensure_ascii=False, indent=2))
        if args.publish:
            for script, extra in [('verify_site.py', []), ('deploy.py', ['--execute']), ('verify_live.py', [])]:
                subprocess.run([sys.executable, str(ROOT / 'ops' / script), '--public', str(args.public.absolute()), *extra], check=True)
    except (ValueError, KeyError, TypeError, OSError, zipfile.BadZipFile) as error:
        parser.exit(1, 'Manager release sync failed: ' + str(error) + '\n')


if __name__ == '__main__':
    main()
