#!/usr/bin/env python3
"""Synchronize the separate targets release without changing the chat release.

--dry-run does not write or connect. --publish explicitly verifies and deploys.
"""
from __future__ import annotations
import argparse
import copy
import datetime as dt
import hashlib
import html
import json
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile

from sync_release import ROOT, CHANNELS, apply, json_bytes, marked, nonempty_strings, read_package, version_key, portal_releases, render_portal, update_sitemap

ADDON = 'MyForeverTargets'
HOMEPAGE = 'https://afabiaoge.xyz/targets/'
IDENTITY = {
    'schema_version': 1, 'name': ADDON, 'display_name': '我的无限 · 目标选择',
    'homepage': HOMEPAGE,
    'installation': '完整退出游戏，将 MyForeverTargets 文件夹放入 _forever_/Interface/AddOns/，保留 WTF，然后重新启动游戏。',
    'automatic_install': False,
}


def render(document, catalog):
    release = next(r for r in catalog['releases'] if r['version'] == catalog['latest'])
    esc = html.escape
    version, download = release['version'], release['download']
    label = CHANNELS[release['channel']]
    href = '/downloads/' + download['filename']
    button = f'<a class="button" href="{esc(href)}" download>下载 v{version} {label} <span aria-hidden="true">↗</span></a>'
    compatibility = release['compatibility']
    meta = f'<p class="download-meta">{release["published_at"]} 发布 · {download["size_bytes"] / 1024:.1f} KiB<br>适配 {esc(compatibility["client"])} / Interface {compatibility["interface"]}</p>'
    latest = f'<article class="latest-release"><h3>v{version} · {label}</h3><p class="release-date">{release["published_at"]}</p><ul>' + ''.join('<li>' + esc(x) + '</li>' for x in release['changes']) + '</ul>' + button + f'<p class="package-meta">ZIP · {download["size_bytes"]:,} 字节 · {esc(release.get("package_note", ""))}</p></article>'
    history = []
    for entry in catalog['releases']:
        if entry['version'] != version:
            history.append('<details><summary><span>v' + esc(entry['version']) + '</span><span>' + esc(entry['published_at']) + '</span></summary>' + ''.join('<p>' + esc(x) + '</p>' for x in entry['changes']) + '</details>')
    blocks = {'hero-download': button + meta, 'latest': latest,
              'checksum': '<div class="checksum"><span>SHA-256</span><code>' + download['sha256'] + '</code></div>',
              'validation': ''.join('<p>' + esc(x) + '</p>' for x in release['validation']),
              'history': '\n'.join(history) or '<p>这是目标选择首次公开发布；此前版本仅用于本机试用。</p>'}
    for name, value in blocks.items():
        document = marked(document, name, value)
    return document


def prepare(public, package, notes):
    public = Path(public)
    folder = public / 'targets'
    for path in (public, folder, public / 'downloads'):
        if path.is_symlink():
            raise ValueError('Managed directory cannot be a symlink: ' + str(path))
    raw, version, interface, digest = read_package(package, ADDON)
    latest_path, catalog_path = folder / 'latest.json', folder / 'releases.json'
    if latest_path.exists() != catalog_path.exists():
        raise ValueError('Targets latest and catalog must exist together')
    if latest_path.exists():
        current = json.loads(latest_path.read_text())
        catalog = json.loads(catalog_path.read_text())
        if current.get('name') != ADDON or current.get('homepage') != HOMEPAGE or catalog.get('name') != ADDON:
            raise ValueError('Targets release identity mismatch')
        entries = catalog['releases']
        versions = [r['version'] for r in entries]
        if len(versions) != len(set(versions)) or catalog['latest'] != current['version'] or next((r for r in entries if r['version'] == catalog['latest']), None) != current:
            raise ValueError('Targets latest and catalog disagree')
        if version_key(version) < version_key(catalog['latest']):
            raise ValueError('Refusing to mark an older version as latest')
    else:
        catalog = {'schema_version': 1, 'name': ADDON, 'latest': version, 'releases': []}
    prior = next((r for r in catalog['releases'] if r['version'] == version), None)
    if prior and prior.get('download', {}).get('sha256') != digest:
        raise ValueError('Version already exists with a different archive hash')
    if notes.get('version', version) != version:
        raise ValueError('Notes version differs from package TOC')
    channel = notes.get('channel')
    if channel not in CHANNELS:
        raise ValueError('Notes channel must explicitly be trial or stable')
    date = notes.get('published_at', '')
    dt.date.fromisoformat(date)
    if prior and (prior['published_at'] != date or prior['channel'] != channel):
        raise ValueError('Existing release date/channel are immutable')
    compatibility = copy.deepcopy(notes.get('compatibility', {}))
    if not all(isinstance(compatibility.get(k), str) and compatibility[k].strip() for k in ('product', 'client')):
        raise ValueError('Notes compatibility must state product and verified client version')
    if compatibility.get('interface', interface) != interface:
        raise ValueError('Notes Interface differs from package TOC')
    compatibility['interface'] = interface
    filename = f'{ADDON}-{version}' + ('-Trial' if channel == 'trial' else '') + '.zip'
    destination = public / 'downloads' / filename
    if destination.exists() and hashlib.sha256(destination.read_bytes()).hexdigest() != digest:
        raise ValueError('Refusing to overwrite an immutable package with different bytes')
    release = copy.deepcopy(IDENTITY)
    release.update(version=version, channel=channel, published_at=date, compatibility=compatibility,
                   changes=nonempty_strings(notes.get('changes'), 'changes'),
                   validation=nonempty_strings(notes.get('validation', prior.get('validation') if prior else None), 'validation'))
    note = notes.get('package_note', prior.get('package_note') if prior else None)
    if note:
        if not isinstance(note, str):
            raise ValueError('package_note must be plain text')
        release['package_note'] = note
    release['download'] = {'url': 'https://afabiaoge.xyz/downloads/' + filename, 'filename': filename, 'size_bytes': len(raw), 'sha256': digest}
    catalog['latest'] = version
    catalog['releases'] = sorted([release] + [r for r in catalog['releases'] if r['version'] != version], key=lambda r: version_key(r['version']), reverse=True)
    output = {'targets/index.html': render((folder / 'index.html').read_text(), catalog).encode(),
              'targets/latest.json': json_bytes(release), 'targets/releases.json': json_bytes(catalog),
              'downloads/' + filename: raw, 'downloads/' + filename + '.sha256': (digest + '  ' + filename + '\n').encode()}
    releases = portal_releases(public, release)
    output['index.html'] = render_portal((public / 'index.html').read_text(), releases).encode()
    portal_date = max(r['published_at'] for r in releases.values())
    output['sitemap.xml'] = update_sitemap((public / 'sitemap.xml').read_text(), {
        'https://afabiaoge.xyz/': portal_date, HOMEPAGE: date}).encode()
    for relative in output:
        if (public / relative).is_symlink():
            raise ValueError('Managed output cannot be a symlink: ' + relative)
    return {name: value for name, value in output.items() if not (public / name).exists() or (public / name).read_bytes() != value}, release


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--zip', required=True, type=Path, dest='package')
    parser.add_argument('--notes', required=True, type=Path)
    parser.add_argument('--public', type=Path, default=ROOT / 'public')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--dry-run', action='store_true')
    mode.add_argument('--publish', action='store_true')
    args = parser.parse_args()
    try:
        updates, release = prepare(args.public.absolute(), args.package, json.loads(args.notes.read_text()))
        if not args.dry_run:
            apply(args.public.absolute(), updates)
        print(json.dumps({'status': 'dry-run' if args.dry_run else 'synced', 'name': ADDON, 'version': release['version'], 'changed_files': list(updates), 'sha256': release['download']['sha256']}, ensure_ascii=False, indent=2))
        if args.publish:
            for script, extra in [('verify_site.py', []), ('deploy.py', ['--execute']), ('verify_live.py', [])]:
                subprocess.run([sys.executable, str(ROOT / 'ops' / script), '--public', str(args.public.absolute()), *extra], check=True)
    except (ValueError, KeyError, OSError, zipfile.BadZipFile, ET.ParseError) as error:
        parser.exit(1, 'Targets release sync failed: ' + str(error) + '\n')


if __name__ == '__main__':
    main()
