#!/usr/bin/env python3
"""Verify publication links, release identity, archive integrity and allowlisted files."""
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import urlsplit, unquote
import hashlib
import json
import re
import zipfile
import argparse

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--public', type=Path, default=Path(__file__).resolve().parents[1] / 'public')
root = parser.parse_args().public

class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids, self.urls = set(), []
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs:
            assert attrs['id'] not in self.ids, f"Duplicate ID: {attrs['id']}"
            self.ids.add(attrs['id'])
        self.urls.extend(attrs[k] for k in ('href', 'src') if attrs.get(k))

from sync_release import read_package, version_key, render_portal
from sync_manager_release import verify_catalog as verify_manager_catalog

# Resolve each page relative to its own directory, including /professions/.
pages = {}
for document_path in root.rglob('*.html'):
    page = Page()
    page.feed(document_path.read_text())
    pages[document_path.resolve()] = page
for document_path, parsed_page in pages.items():
    for url in parsed_page.urls:
        parts = urlsplit(url)
        if parts.scheme or parts.netloc:
            continue
        destination = (root / unquote(parts.path.lstrip('/')) if parts.path.startswith('/')
                       else document_path.parent / unquote(parts.path)) if parts.path else document_path
        if destination.is_dir():
            destination /= 'index.html'
        destination = destination.resolve()
        assert destination.is_relative_to(root.resolve()), f'Public link escapes root: {url}'
        assert destination.is_file(), f'Missing link: {url}'
        if parts.fragment and destination in pages:
            assert parts.fragment in pages[destination].ids, f'Missing anchor: {url}'

html = (root / 'index.html').read_text()
page = pages[(root / 'index.html').resolve()]
registered_packages = set()
verified_releases = {}

def verify_catalog(folder, addon, homepage, expected_buttons, detail_path=None):
    current = json.loads((folder / 'latest.json').read_text())
    catalog = json.loads((folder / 'releases.json').read_text())
    assert current['name'] == addon and current['homepage'] == homepage, 'Release identity mismatch'
    assert catalog.get('name', addon) == addon, 'Catalog identity mismatch'
    assert current['automatic_install'] is False
    assert catalog['latest'] == current['version']
    assert len({r['version'] for r in catalog['releases']}) == len(catalog['releases'])
    assert next(r for r in catalog['releases'] if r['version'] == catalog['latest']) == current
    document = (detail_path or folder / 'index.html').read_text()
    for entry in catalog['releases']:
        version_key(entry['version'])
        if not entry.get('download'):
            continue
        assert entry.get('name', addon) == addon and entry.get('homepage', homepage) == homepage
        record = entry['download']
        filename = addon + '-' + entry['version'] + ('-Trial' if entry['channel'] == 'trial' else '') + '.zip'
        assert entry['channel'] in ('trial', 'stable')
        assert record['filename'] == filename, 'Download identity mismatch'
        assert record['url'] == 'https://afabiaoge.xyz/downloads/' + filename, 'Download URL mismatch'
        relative = 'downloads/' + filename
        assert relative not in registered_packages, 'Duplicate registered package'
        registered_packages.add(relative)
        archive_path = root / relative
        raw, version, interface, digest = read_package(archive_path, addon)
        assert len(raw) == record['size_bytes'] and digest == record['sha256'], 'Archive digest mismatch'
        assert version == entry['version'] and interface == entry['compatibility']['interface'], 'TOC identity mismatch'
        assert archive_path.with_name(filename + '.sha256').read_text() == digest + '  ' + filename + '\n'
    info = current['download']
    buttons = re.findall(r'<a\b[^>]*href="([^"]+\.zip)"[^>]*\bdownload[^>]*>(.*?)</a>', document, re.S)
    assert len(buttons) == expected_buttons, 'Unexpected download button count'
    expected_href = '/downloads/' + info['filename']
    for href, label in buttons:
        assert href == expected_href, 'Stale download URL'
        assert 'v' + current['version'] in re.sub(r'<[^>]*>', '', label), 'Stale download label'
    assert info['sha256'] in document and f"v{current['version']}" in document
    verified_releases[addon] = {'version': current['version'], 'package_bytes': info['size_bytes'], 'sha256': info['sha256']}
    return current

latest = verify_catalog(root, 'MyForeverChat', 'https://afabiaoge.xyz/', 3, root / 'chat/index.html')
professions = root / 'professions'
if professions.exists():
    profession_latest = verify_catalog(professions, 'MyForeverProfessions', 'https://afabiaoge.xyz/professions/', 2)
else:
    raise AssertionError('Two-add-on portal requires professions metadata')
portal = {'MyForeverChat': latest, 'MyForeverProfessions': profession_latest}
if (root / 'navigator').exists():
    portal['MyForeverNavigator'] = verify_catalog(root / 'navigator', 'MyForeverNavigator', 'https://afabiaoge.xyz/navigator/', 2)
if (root / 'targets').exists():
    portal['MyForeverTargets'] = verify_catalog(root / 'targets', 'MyForeverTargets', 'https://afabiaoge.xyz/targets/', 2)
assert render_portal(html, portal) == html, 'Stale or mismatched portal cards'
assert len(re.findall(r'<article\b[^>]*\bdata-addon=', html)) == len(portal), 'Portal must contain exactly one card per add-on'
assert len(re.findall(r'<a\b[^>]*href="[^"]+\.zip"[^>]*\bdownload', html)) == len(portal), 'Portal must expose one download per add-on'
manager_packages, manager_latest = verify_manager_catalog(root)
registered_packages.update(manager_packages)
assert {p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file() and p.suffix.lower() == '.zip'} == registered_packages, 'Unregistered or missing ZIP in public files'
info = latest['download']
screenshots = list((root / 'assets').glob('chat-*.jpg'))
assert {'chat-overview.jpg', 'chat-settings.jpg', 'chat-emotes.jpg', 'chat-actions.jpg', 'chat-groups-0.9.jpg', 'chat-channels-0.9.jpg'} <= {p.name for p in screenshots}
profession_screenshots = list((root / 'assets').glob('professions-*.jpg'))
assert {'professions-overview.jpg', 'professions-materials.jpg', 'professions-trainers.jpg'} <= {p.name for p in profession_screenshots}
for image in screenshots + profession_screenshots:
    assert image.read_bytes().startswith(b'\xff\xd8'), f'Incorrect JPEG: {image}'
config_path = root / 'community-config.json'
if config_path.exists():
    config = json.loads(config_path.read_text())
    author, donation = config.get('author', {}), config.get('donation', {})
    asset_urls = [author.get('avatar_url'), donation.get('qr_url')]
    assert donation.get('enabled', False) in (True, False) and isinstance(donation.get('enabled', False), bool), 'Donation enabled must be boolean'
    amounts = donation.get('amounts', {})
    assert isinstance(amounts, dict), 'Donation amount mapping must be an object'
    if donation.get('enabled'):
        for amount in ('1', '5', '20', '100'):
            assert (isinstance(amounts.get(amount, {}), dict) and amounts.get(amount, {}).get('qr_url')) or donation.get('qr_url'), 'Enabled donations require a real QR for every listed amount'
    for amount, value in amounts.items():
        assert re.fullmatch(r'\d+(?:\.\d{1,2})?', amount) and float(amount) > 0, 'Invalid donation amount'
        assert isinstance(value, dict), 'Donation amount entry must be an object'
        asset_urls.append(value.get('qr_url'))
    for asset_url in filter(None, asset_urls):
        assert isinstance(asset_url, str), 'Asset URL must be text'
        parsed = urlsplit(asset_url)
        path = unquote(parsed.path)
        assert not parsed.scheme and not parsed.netloc and not parsed.query and not parsed.fragment, 'Asset must use a relative public path'
        assert path.startswith('assets/') and '\\' not in path and '..' not in Path(path).parts, 'Unsafe dynamic asset path'
        asset = root / path
        assert asset.suffix.lower() in {'.jpg', '.jpeg', '.png', '.webp'} and asset.is_file(), 'Missing or unsafe dynamic image'
        signature = asset.read_bytes()[:12]
        extension = asset.suffix.lower()
        assert (extension in {'.jpg', '.jpeg'} and signature.startswith(b'\xff\xd8')) or (extension == '.png' and signature.startswith(b'\x89PNG\r\n\x1a\n')) or (extension == '.webp' and signature.startswith(b'RIFF') and signature[8:12] == b'WEBP'), 'Dynamic image encoding differs from extension'
for file in root.rglob('*'):
    assert file.suffix.lower() not in {'.py', '.sqlite', '.sqlite3', '.db', '.key', '.pem', '.sql'}, f'Private backend file in public: {file}'
    assert file.name not in {'community', 'ops', 'abuse.key'}, f'Private backend path in public: {file}'
    assert not file.is_symlink(), f'Public symlink: {file}'
    assert not file.name.startswith('.'), f'Hidden public file: {file}'
print(json.dumps({'status': 'passed', 'version': latest['version'], 'links': len(page.urls), 'screenshots': len(screenshots), 'profession_screenshots': len(profession_screenshots), 'package_bytes': info['size_bytes'], 'sha256': info['sha256'], 'addons': verified_releases, 'manager_version': manager_latest['version'] if manager_latest else None}, indent=2))
