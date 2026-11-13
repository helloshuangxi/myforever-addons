#!/usr/bin/env python3
"""Synchronize an existing audited add-on ZIP and truthful release notes.

No network unless --publish; --dry-run performs no writes.
"""
from __future__ import annotations
import argparse
import copy
import datetime as dt
import hashlib
import html
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MARKERS = ('hero-download', 'updates-summary', 'latest', 'checksum', 'validation', 'history', 'footer', 'download-dock')
CHANNELS = {'trial': '试用版', 'stable': '正式版'}
PRIVATE = re.compile(r'^(?:WTF|SavedVariables|backups?|\.git|\.env.*|\.DS_Store|__MACOSX)$', re.I)


def version_key(value):
    if not isinstance(value, str) or not re.fullmatch(r'(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)', value):
        raise ValueError('Version must contain three numeric components, for example 0.8.1')
    return tuple(map(int, value.split('.')))


def read_package(path, addon='MyForeverChat'):
    if addon not in ('MyForeverChat', 'MyForeverProfessions', 'MyForeverNavigator', 'MyForeverTargets'):
        raise ValueError('Unsupported add-on identity')
    raw = path.read_bytes()
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        seen = set()
        for item in archive.infolist():
            name = item.filename
            parts = PurePosixPath(name).parts
            if (not name or '\\' in name or '\x00' in name or name.startswith('/')
                    or re.match(r'^[A-Za-z]:', name) or '..' in parts
                    or any(PRIVATE.fullmatch(part) for part in parts)
                    or stat.S_ISLNK(item.external_attr >> 16) or name in seen):
                raise ValueError('Unsafe or duplicate ZIP entry: ' + name)
            seen.add(name)
            companion = addon == 'MyForeverChat' and name in {'MyForeverChat-表情包制作器.html', '安装使用说明.txt', 'LICENSE.txt'}
            if (not parts or parts[0] != addon) and not companion:
                raise ValueError('ZIP contains an unexpected add-on root: ' + name)
        if sum(x.file_size for x in archive.infolist()) > 100 * 1024 * 1024:
            raise ValueError('Uncompressed ZIP exceeds 100 MiB review limit')
        if archive.testzip() is not None:
            raise ValueError('ZIP integrity check failed')
        try:
            toc = archive.read(f'{addon}/{addon}.toc').decode('utf-8-sig')
        except KeyError as error:
            raise ValueError('ZIP does not contain the expected add-on TOC: ' + addon) from error
        def field(name):
            values = re.findall(r'^##\s*' + name + r':\s*(.*?)\s*$', toc, re.M)
            if len(values) != 1:
                raise ValueError('TOC must contain exactly one ' + name)
            return values[0]
        version = field('Version')
        version_key(version)
        interface = field('Interface')
        if not interface.isdigit():
            raise ValueError('TOC Interface must be an integer')
    return raw, version, int(interface), hashlib.sha256(raw).hexdigest()


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode()


def plain(value):
    return html.unescape(re.sub(r'<[^>]*>', '', value)).strip()


def marked(document, name, body):
    if any(document.count(f'<!-- release:{name}:{edge} -->') != 1 for edge in ('start', 'end')):
        raise ValueError('Expected exactly one release marker: ' + name)
    pattern = r'<!-- release:' + name + r':start -->.*?<!-- release:' + name + r':end -->'
    result, count = re.subn(pattern, lambda _: f'<!-- release:{name}:start -->{body}<!-- release:{name}:end -->', document, flags=re.S)
    if count != 1:
        raise ValueError('Expected exactly one release marker: ' + name)
    return result


def add_markers(document):
    if '<!-- release:' in document:
        for name in MARKERS:
            for edge in ('start', 'end'):
                if document.count(f'<!-- release:{name}:{edge} -->') != 1:
                    raise ValueError('Incomplete or duplicate release markers: ' + name)
        return document
    patterns = {
        'hero-download': r'(<a class="button" href="downloads/[^\"]+\.zip"[^>]*>.*?</a>\s*<p class="download-meta">.*?</p>)',
        'updates-summary': r'(<p>当前最新为 v[^<]+</p>)',
        'latest': r'(<article class="latest-release">.*?</article>)',
        'checksum': r'(<div class="checksum">.*?</div>)',
        'validation': r'(?<=<h3 class="validation-heading">当前验证范围</h3>)(.*?)(?=</div>)',
        'history': r'(?<=<div class="history"><h3>之前的版本</h3>)(.*?)(?=</div>)',
        'footer': r'(<a href="#updates">v\d+\.\d+\.\d+ · \d{4}</a>)',
        'download-dock': r'(<a class="latest-download-dock".*?</a>)',
    }
    for name, pattern in patterns.items():
        document, count = re.subn(pattern, lambda m: f'<!-- release:{name}:start -->{m[1]}<!-- release:{name}:end -->', document, flags=re.S)
        if count != 1:
            raise ValueError('Cannot initialize template marker; inspect HTML: ' + name)
    return document


def bootstrap_catalog(public, document, latest):
    path = public / 'releases.json'
    if path.exists():
        catalog = json.loads(path.read_text())
    else:
        current = copy.deepcopy(latest)
        validation = re.search(r'<h3 class="validation-heading">当前验证范围</h3>(.*?)</div>', document, re.S)
        current['validation'] = [plain(s) for s in re.findall(r'<p>(.*?)</p>', validation[1], re.S)] if validation else []
        package = re.search(r'<p class="package-meta">ZIP · [^·<]+ · (.*?)</p>', document)
        if package:
            current['package_note'] = plain(package[1])
        catalog = {'schema_version': 1, 'latest': latest['version'], 'releases': [current]}
        history = re.search(r'<div class="history"><h3>之前的版本</h3>(.*?)</div>', document, re.S)
        if not history:
            raise ValueError('Cannot bootstrap existing version history')
        for match in re.finditer(r'<details><summary><span>v([^<]+)</span><span>([^<]+)</span></summary>(.*?)</details>', history[1], re.S):
            version_key(match[1])
            date = match[2] if re.fullmatch(r'\d{4}-\d{2}-\d{2}', match[2]) else None
            catalog['releases'].append({'version': match[1], 'published_at': date, 'changes': [plain(x) for x in re.findall(r'<p>(.*?)</p>', match[3], re.S)]})
    versions = [x['version'] for x in catalog['releases']]
    if len(versions) != len(set(versions)) or catalog['latest'] not in versions:
        raise ValueError('Release catalog has duplicate versions or an invalid latest pointer')
    if catalog['latest'] != latest['version']:
        raise ValueError('latest.json and releases.json disagree; repair the catalog before syncing')
    return catalog


def nonempty_strings(value, field):
    if not isinstance(value, list) or not value or any(not isinstance(x, str) or not x.strip() for x in value):
        raise ValueError(field + ' must be a nonempty array of truthful text strings')
    return [x.strip() for x in value]


def portal_releases(public, replacement):
    releases = {}
    for addon, relative in (('MyForeverChat', 'latest.json'), ('MyForeverProfessions', 'professions/latest.json'), ('MyForeverNavigator', 'navigator/latest.json'), ('MyForeverTargets', 'targets/latest.json')):
        if addon in ('MyForeverNavigator', 'MyForeverTargets') and replacement['name'] != addon and not (public / relative).exists():
            continue
        release = replacement if replacement['name'] == addon else json.loads((public / relative).read_text())
        if release.get('name') != addon:
            raise ValueError('Portal release identity mismatch: ' + addon)
        filename = addon + '-' + release['version'] + ('-Trial' if release['channel'] == 'trial' else '') + '.zip'
        if release['channel'] not in CHANNELS or release['download']['filename'] != filename or release['download']['url'] != 'https://afabiaoge.xyz/downloads/' + filename:
            raise ValueError('Portal download identity mismatch: ' + addon)
        releases[addon] = release
    return releases


def render_portal(document, releases):
    descriptions = {
        'MyForeverChat': ('微信式聊天', '把私聊、频道和社区群聊整理在熟悉的聊天窗口里，查看记录，及时回复。', '/chat/'),
        'MyForeverProfessions': ('商业技能助手', '查看专业进度、训练推荐与材料缺口，用不同专业图标寻找附近训练师。', '/professions/'),
        'MyForeverNavigator': ('世界向导', '启用 Questie 扩展 NPC 目录，按用途搜索导航；支持任务目标与交付地点、收藏和个人地点。', '/navigator/'),
        'MyForeverTargets': ('目标选择', '把友方、敌方和敌人的目标放进紧凑血条，查看相关效果，点击选择目标或设置焦点。', '/targets/'),
    }
    esc = html.escape
    cards = []
    for addon, (title, description, detail_url) in descriptions.items():
        if addon not in releases:
            continue
        release = releases[addon]
        version, download = release['version'], release['download']
        label = CHANNELS[release['channel']]
        cards.append(f'''<article class="addon-card" data-addon="{addon}">
  <p class="addon-code">{addon}</p>
  <h2>{title}</h2>
  <p class="addon-description">{description}</p>
  <p class="addon-version">v{esc(version)} · {label} · {esc(release['published_at'])} · {download['size_bytes'] / 1024:.1f} KiB</p>
  <div class="addon-actions"><a class="button" href="/downloads/{esc(download['filename'])}" download aria-label="下载{title} v{esc(version)} {label}">下载 v{esc(version)} {label}</a><a class="text-link" href="{detail_url}">功能与安装说明 <span aria-hidden="true">↗</span></a></div>
</article>''')
    return marked(document, 'catalog', '\n' + '\n'.join(cards) + '\n')


def update_sitemap(sitemap, dates):
    namespace = '{http://www.sitemaps.org/schemas/sitemap/0.9}'
    tree = ET.fromstring(sitemap)
    for url, requested in dates.items():
        dt.date.fromisoformat(requested)
        matches = [u for u in tree if u.findtext(namespace + 'loc') == url]
        if len(matches) != 1 or matches[0].find(namespace + 'lastmod') is None:
            raise ValueError('Expected one sitemap lastmod for ' + url)
        old_date = matches[0].findtext(namespace + 'lastmod')
        dt.date.fromisoformat(old_date)
        # A same-version resync must not roll a newer portal date backwards.
        date = max(old_date, requested)
        pattern = r'(<url>\s*<loc>' + re.escape(url) + r'</loc>\s*<lastmod>)' + re.escape(old_date) + r'(</lastmod>)'
        sitemap, count = re.subn(pattern, lambda m: m[1] + date + m[2], sitemap)
        if count != 1:
            raise ValueError('Unsupported sitemap element formatting for ' + url)
    return sitemap


def render(document, catalog):
    current = next(x for x in catalog['releases'] if x['version'] == catalog['latest'])
    esc = html.escape
    version = current['version']
    label = CHANNELS[current['channel']]
    date = dt.date.fromisoformat(current['published_at'])
    download = current['download']
    href = '/downloads/' + download['filename']
    def button(light=False):
        css = 'button button-light' if light else 'button'
        return f'<a class="{css}" href="{esc(href)}" download>下载最新版 v{version} {label} <span aria-hidden="true">↗</span></a>'
    compatibility = current['compatibility']
    hero = button() + f'\n      <p class="download-meta">{date.isoformat()} 更新 · {download["size_bytes"] / 1024:.1f} KiB<br>适配 {esc(compatibility["client"])} / Interface {compatibility["interface"]}</p>'
    changes = ''.join('<li>' + esc(x) + '</li>' for x in current['changes'])
    package_note = ' · ' + esc(current['package_note']) if current.get('package_note') else ''
    latest = f'<article class="latest-release"><h3>v{version}</h3><p class="release-date">{date.year} 年 {date.month} 月 {date.day} 日 · 最新{label}</p><ul>{changes}</ul>{button(True)}<p class="package-meta">ZIP · {download["size_bytes"]:,} 字节{package_note}</p></article>'
    history = []
    for entry in catalog['releases']:
        if entry['version'] == version:
            continue
        history.append('<details><summary><span>v' + esc(entry['version']) + '</span><span>' + esc(entry.get('published_at') or '早期版本') + '</span></summary>' + ''.join('<p>' + esc(x) + '</p>' for x in entry['changes']) + '</details>')
    values = {
        'hero-download': hero,
        'updates-summary': f'<p>当前最新为 v{version} {label}。下载后按安装步骤替换插件文件，即可更新。</p>',
        'latest': latest,
        'checksum': '<div class="checksum"><span>SHA-256</span><code>' + download['sha256'] + '</code></div>',
        'validation': ''.join('<p>' + esc(x) + '</p>' for x in current['validation']),
        'history': '\n  ' + '\n  '.join(history) + '\n  ',
        'footer': f'<a href="#updates">v{version} · {date.year}</a>',
        'download-dock': f'<a class="latest-download-dock" href="{esc(href)}" download aria-label="下载最新版 MyForeverChat v{version} {label}，{download["size_bytes"] / 1024:.1f} KiB">\n  <span class="download-dock-title">下载最新版</span>\n  <span class="download-dock-meta">v{version} {label} · {download["size_bytes"] / 1024:.1f} KiB</span>\n  <span class="download-dock-arrow" aria-hidden="true">↓</span>\n</a>',
    }
    for name, value in values.items():
        document = marked(document, name, value)
    return document


def prepare(public, package, notes):
    if public.is_symlink():
        raise ValueError('Public root cannot be a symlink')
    raw, version, interface, digest = read_package(package)
    current = json.loads((public / 'latest.json').read_text())
    if (public / 'chat').is_symlink():
        raise ValueError('Chat detail directory cannot be a symlink')
    document = (public / 'chat/index.html').read_text()
    catalog = bootstrap_catalog(public, document, current)
    if version_key(version) < version_key(catalog['latest']):
        raise ValueError('Refusing to mark an older version as latest; rollback is not supported')
    prior = next((r for r in catalog['releases'] if r['version'] == version), None)
    if prior and prior.get('download', {}).get('sha256') != digest:
        raise ValueError('Version already exists with a different archive hash (or lacks a verified archive)')
    if notes.get('version', version) != version:
        raise ValueError('Notes version differs from package TOC')
    channel = notes.get('channel')
    if channel not in CHANNELS:
        raise ValueError('Notes channel must explicitly be trial or stable')
    date = notes.get('published_at', '')
    dt.date.fromisoformat(date)
    if prior and (prior['published_at'] != date or prior['channel'] != channel):
        raise ValueError('Existing release date/channel are immutable; use a new version for promotion')
    compatibility = copy.deepcopy(notes.get('compatibility', {}))
    if not all(isinstance(compatibility.get(k), str) and compatibility[k].strip() for k in ('product', 'client')):
        raise ValueError('Notes compatibility must state product and verified client version')
    if compatibility.get('interface', interface) != interface:
        raise ValueError('Notes Interface differs from package TOC')
    compatibility['interface'] = interface
    filename = f'MyForeverChat-{version}' + ('-Trial' if channel == 'trial' else '') + '.zip'
    destination = public / 'downloads' / filename
    if destination.is_symlink() or (destination.parent.exists() and destination.parent.is_symlink()):
        raise ValueError('Download destination cannot be a symlink')
    if destination.exists() and hashlib.sha256(destination.read_bytes()).hexdigest() != digest:
        raise ValueError('Refusing to overwrite an immutable package with different bytes')
    # Reuse identity and installation guidance; never inherit an older version\'s validation claims.
    release = {key: copy.deepcopy(current[key]) for key in ('schema_version', 'name', 'display_name', 'homepage', 'installation', 'automatic_install')}
    release.update(version=version, channel=channel, published_at=date, compatibility=compatibility,
                   changes=nonempty_strings(notes.get('changes'), 'changes'),
                   validation=nonempty_strings(notes.get('validation', prior.get('validation') if prior else None), 'validation'))
    note = notes.get('package_note', prior.get('package_note') if prior else None)
    if note:
        if not isinstance(note, str):
            raise ValueError('package_note must be plain text')
        release['package_note'] = note
    release['download'] = {'url': current['homepage'].rstrip('/') + '/downloads/' + filename, 'filename': filename, 'size_bytes': len(raw), 'sha256': digest}
    catalog['latest'] = version
    catalog['releases'] = sorted([release] + [r for r in catalog['releases'] if r['version'] != version], key=lambda r: version_key(r['version']), reverse=True)
    releases = portal_releases(public, release)
    portal_date = max(r['published_at'] for r in releases.values())
    sitemap = update_sitemap((public / 'sitemap.xml').read_text(), {
        'https://afabiaoge.xyz/': portal_date, 'https://afabiaoge.xyz/chat/': date})
    output = {'index.html': render_portal((public / 'index.html').read_text(), releases).encode(),
              'chat/index.html': render(add_markers(document), catalog).encode(), 'latest.json': json_bytes(release), 'releases.json': json_bytes(catalog), 'sitemap.xml': sitemap.encode(), 'downloads/' + filename: raw, 'downloads/' + filename + '.sha256': (digest + '  ' + filename + '\n').encode()}
    for relative in output:
        if (public / relative).is_symlink():
            raise ValueError('Managed output cannot be a symlink: ' + relative)
    return {name: value for name, value in output.items() if not (public / name).exists() or (public / name).read_bytes() != value}, release


def apply(public, updates):
    old = {name: (public / name).read_bytes() if (public / name).exists() else None for name in updates}
    with tempfile.TemporaryDirectory(prefix='myforeverchat-sync-', dir=public.parent) as temporary:
        staging = Path(temporary)
        for name, raw in updates.items():
            path = staging / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
        committed = []
        try:
            for name in updates:
                path = public / name
                path.parent.mkdir(parents=True, exist_ok=True)
                os.replace(staging / name, path)
                committed.append(name)
        except Exception:
            for name in reversed(committed):
                path = public / name
                if old[name] is None:
                    path.unlink()
                else:
                    path.write_bytes(old[name])
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--zip', required=True, type=Path, dest='package')
    parser.add_argument('--notes', required=True, type=Path, help='JSON with published_at, channel, compatibility, changes, validation')
    parser.add_argument('--public', type=Path, default=ROOT / 'public')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--dry-run', action='store_true')
    mode.add_argument('--publish', action='store_true', help='After local sync, verify, deploy, and verify the public website')
    args = parser.parse_args()
    try:
        updates, release = prepare(args.public.absolute(), args.package, json.loads(args.notes.read_text()))
        if not args.dry_run:
            apply(args.public.absolute(), updates)
        print(json.dumps({'status': 'dry-run' if args.dry_run else 'synced', 'version': release['version'], 'channel': release['channel'], 'changed_files': list(updates), 'sha256': release['download']['sha256']}, ensure_ascii=False, indent=2))
        if args.publish:
            for script, extra in [('verify_site.py', []), ('deploy.py', ['--execute']), ('verify_live.py', [])]:
                subprocess.run([sys.executable, str(ROOT / 'ops' / script), '--public', str(args.public.absolute()), *extra], check=True)
    except (ValueError, KeyError, OSError, zipfile.BadZipFile, ET.ParseError) as error:
        parser.exit(1, 'Release sync failed: ' + str(error) + '\n')


if __name__ == '__main__':
    main()
