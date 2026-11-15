"""Shared installer/feed validation, usable on Mac and Linux without executing packages."""
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import stat
import struct
import xml.etree.ElementTree as ET
import zipfile

PACKAGE_ID = 'MyForeverManagerApp'
BASE = 'https://afabiaoge.xyz/manager/'
RIDS = {'osx-arm64', 'osx-x64', 'win-x64'}
MAX_SIZE = 300 * 1024 * 1024


def installer_filename(version, channel, platform):
    suffix = '-Setup.exe' if platform == 'win-x64' else '.dmg'
    return f'MyForeverManager-{version}' + ('-Trial' if channel == 'trial' else '') + f'-{platform}' + suffix


def read_installer(path, platform):
    path = Path(path)
    if platform not in RIDS or path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= MAX_SIZE:
        raise ValueError('Missing, linked or oversized installer')
    raw = path.read_bytes()
    if platform == 'win-x64':
        if len(raw) < 64 or raw[:2] != b'MZ':
            raise ValueError('Invalid Windows Setup header')
        offset = struct.unpack_from('<I', raw, 60)[0]
        if offset + 6 > len(raw) or raw[offset:offset+4] != b'PE\0\0' or struct.unpack_from('<H', raw, offset+4)[0] != 0x8664:
            raise ValueError('Windows Setup must target x64')
    elif len(raw) < 512 or raw[-512:-508] != b'koly':
        raise ValueError('Invalid UDIF DMG trailer')
    return raw, hashlib.sha256(raw).hexdigest()


def read_update_package(path, version, platform):
    path = Path(path)
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= MAX_SIZE:
        raise ValueError('Missing, linked or oversized update package')
    raw = path.read_bytes()
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        entries = archive.infolist()
        if not 1 <= len(entries) <= 10000 or sum(e.file_size for e in entries) > 650 * 1024 * 1024:
            raise ValueError('Update extraction limits exceeded')
        seen = set()
        private = re.compile(r'^(?:WTF|SavedVariables|settings\.json|behavior-ai-settings\.json|desktop\.lock|backups?|\.env.*|\.git|__MACOSX)$', re.I)
        for entry in entries:
            name = entry.filename
            parts = PurePosixPath(name).parts
            mode = stat.S_IFMT(entry.external_attr >> 16)
            if (not parts or name.startswith('/') or '\\' in name or ':' in name or
                    '/'.join(parts) != name.rstrip('/') or name.casefold() in seen or
                    any(p in ('.', '..') or private.fullmatch(p) or (p.startswith('.') and name != '_rels/.rels') for p in parts) or
                    mode not in (0, stat.S_IFREG, stat.S_IFDIR) or entry.flag_bits & 1):
                raise ValueError('Unsafe update member: ' + name)
            seen.add(name.casefold())
        spec = ET.fromstring(archive.read(PACKAGE_ID + '.nuspec'))
        metadata = {n.tag.split('}')[-1]: n.text for n in spec.find('{*}metadata')}
        for key, value in {'id': PACKAGE_ID, 'version': version, 'channel': platform, 'rid': platform}.items():
            if metadata.get(key) != value:
                raise ValueError('Update package identity or architecture mismatch')
        prefix = 'lib/app/'
        identity_path = prefix + ('manager-release.json' if platform == 'win-x64' else 'Contents/Resources/manager-release.json')
        if json.loads(archive.read(identity_path)) != {'name': 'MyForeverManager', 'version': version, 'platform': platform}:
            raise ValueError('Update release identity mismatch')
        executable = prefix + ('MyForeverManager.exe' if platform == 'win-x64' else 'Contents/MacOS/MyForeverManager')
        with archive.open(executable) as reader:
            header = reader.read(4096)
        if platform == 'win-x64':
            if len(header) < 64 or header[:2] != b'MZ':
                raise ValueError('Invalid update executable')
            offset = struct.unpack_from('<I', header, 60)[0]
            if offset + 6 > len(header) or header[offset:offset+4] != b'PE\0\0' or struct.unpack_from('<H', header, offset+4)[0] != 0x8664:
                raise ValueError('Update executable must target x64')
        else:
            if len(header) < 8 or header[:4] != b'\xcf\xfa\xed\xfe' or struct.unpack_from('<I', header, 4)[0] != (0x100000c if platform == 'osx-arm64' else 0x1000007):
                raise ValueError('Update executable architecture mismatch')
            info = plistlib.loads(archive.read(prefix + 'Contents/Info.plist'))
            if info.get('CFBundleVersion') != version or info.get('CFBundleIdentifier') != 'xyz.afabiaoge.manager':
                raise ValueError('Update app bundle mismatch')
        if archive.testzip() is not None:
            raise ValueError('Corrupt update package')
    return raw, hashlib.sha256(raw).hexdigest()


def verify_updates(public, release, active):
    config = release.get('self_update')
    if config is None:
        return set()
    if config.get('package_id') != PACKAGE_ID or len(config['feeds']) != 3 or {x['platform'] for x in config['feeds']} != RIDS:
        raise ValueError('Self-update platform configuration mismatch')
    registered = set()
    for item in config['feeds']:
        rid = item['platform']
        folder = 'manager/updates/' + rid + '/'
        feed = folder + 'releases.' + rid + '.json'
        if item['feed_url'] != 'https://afabiaoge.xyz/' + feed:
            raise ValueError('Update feed URL mismatch')
        record = item['package']
        filename = f'{PACKAGE_ID}-{release["version"]}-{rid}-full.nupkg'
        relative = folder + filename
        if record['filename'] != filename or record['url'] != 'https://afabiaoge.xyz/' + relative:
            raise ValueError('Update package URL mismatch')
        raw, digest = read_update_package(Path(public) / relative, release['version'], rid)
        if record['size_bytes'] != len(raw) or record['sha256'] != digest:
            raise ValueError('Update package checksum mismatch')
        if active:
            assets = json.loads((Path(public) / feed).read_text())['Assets']
            if len(assets) != 1 or any(assets[0].get(k) != v for k, v in {
                'PackageId': PACKAGE_ID, 'Version': release['version'], 'Type': 'Full',
                'FileName': filename, 'Size': len(raw), 'SHA256': digest.upper()
            }.items()):
                raise ValueError('Active update feed does not match release package')
        registered.add(relative)
    return registered
