#!/usr/bin/env python3
"""Restore immutable published ZIPs from checked-in release metadata.

Downloads only into website/public. Does not install addons or publish anything.
"""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import os
import tempfile
import urllib.parse
import urllib.request

PUBLIC = Path(__file__).resolve().parents[1] / "PersonalAddons/website/public"
ORIGIN = "https://afabiaoge.xyz"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError("Unexpected release download redirect; review metadata before retrying")


def validated_download(item):
    parsed = urllib.parse.urlsplit(item["url"])
    name = item["filename"]
    relative = PurePosixPath(parsed.path.lstrip("/"))
    if (parsed.scheme != "https" or parsed.netloc != "afabiaoge.xyz"
            or parsed.query or parsed.fragment
            or relative.parent.as_posix() not in ("downloads", "manager/downloads")
            or "/" in name or "\\" in name or not name.endswith(".zip")
            or relative.name != name or ".." in relative.parts):
        raise ValueError("Unsafe release URL or filename")
    size = item["size_bytes"]
    digest = item["sha256"]
    if type(size) is not int or not 0 < size <= 512 * 1024 * 1024:
        raise ValueError("Invalid release size")
    if len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
        raise ValueError("Invalid SHA-256")
    destination = PUBLIC.joinpath(*relative.parts)
    # Refuse symlinked destinations and parent directories.
    if any(p.is_symlink() for p in (PUBLIC, destination.parent, destination.parent.parent, destination)):
        raise ValueError("Release paths must not contain symlinks")
    return destination, size, digest


def matches(path, size, digest):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return path.stat().st_size == size and h.hexdigest() == digest


def restore(item, dry_run=False):
    destination, size, digest = validated_download(item)
    if destination.exists():
        if not matches(destination, size, digest):
            raise ValueError(f"Existing file differs from published metadata: {destination.name}")
        print(f"OK {destination.name}", flush=True)
        return
    print(f"{'WOULD DOWNLOAD' if dry_run else 'DOWNLOADING'} {destination.name} ({size} bytes)", flush=True)
    if dry_run:
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=destination.parent, prefix=".release-", delete=False) as out:
            temporary = Path(out.name)
            request = urllib.request.Request(item["url"], headers={"User-Agent": "MyForever-Source-Checkout/1"})
            with urllib.request.build_opener(NoRedirect).open(request, timeout=60) as response:
                total = 0
                while chunk := response.read(1024 * 1024):
                    total += len(chunk)
                    if total > size:
                        raise ValueError("Download exceeds declared size")
                    out.write(chunk)
        if not matches(temporary, size, digest):
            raise ValueError(f"Release checksum mismatch: {destination.name}")
        # Another process must not silently lose an existing release.
        os.link(temporary, destination)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--all", action="store_true", help="Restore all historical releases")
    parser.add_argument("--include-manager", action="store_true", help="Also restore desktop runtime ZIPs")
    parser.add_argument("--dry-run", action="store_true", help="Verify metadata/existing files without downloading")
    args = parser.parse_args()
    bases = ["", "professions", "navigator", "targets"]
    if args.include_manager:
        bases.append("manager")
    downloads = {}
    for base in bases:
        folder = PUBLIC / base
        if args.all:
            releases = json.loads((folder / "releases.json").read_text(encoding="utf-8"))["releases"]
        else:
            releases = [json.loads((folder / "latest.json").read_text(encoding="utf-8"))]
        for release in releases:
            if args.all and "download" not in release and "downloads" not in release:
                print(f"HISTORY ONLY {base or 'chat'} {release['version']} (no published archive metadata)")
                continue
            for item in release.get("downloads", [release.get("download")]):
                if item is None:
                    raise ValueError("Release metadata has no download")
                previous = downloads.setdefault(item["url"], item)
                if previous != item:
                    raise ValueError("Conflicting metadata for one release URL")
    for item in downloads.values():
        restore(item, args.dry_run)
    print(f"Verified {len(downloads)} published archive entries. No game files or server state changed.")


if __name__ == "__main__":
    main()
