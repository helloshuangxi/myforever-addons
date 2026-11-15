#!/usr/bin/env python3
"""Inspect local installer identity, content, feed hashes and read-only DMGs."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import struct
import subprocess
import tempfile
import zipfile


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def check(root):
    manifest = json.loads((root / "INSTALLERS.json").read_text())
    assert isinstance(manifest["candidate"], bool) and not manifest["published"]
    assert manifest["package_id"] == "MyForeverManagerApp", "Probe build cannot be delivered"
    results = []
    for item in manifest["artifacts"]:
        rid, version = item["platform"], item["version"]
        assert not item["update_probe_fixture"]
        installer = root / item["installer"]
        assert installer.stat().st_size == item["size_bytes"]
        assert sha256(installer) == item["sha256"].upper()
        feed_dir = root / item["feed"]
        feed = json.loads((feed_dir / f"releases.{rid}.json").read_text())
        asset, = feed["Assets"]
        assert asset["PackageId"] == manifest["package_id"] and asset["Version"] == version and asset["Type"] == "Full"
        package = feed_dir / asset["FileName"]
        assert package.parent == feed_dir and package.stat().st_size == asset["Size"]
        assert sha256(package) == asset["SHA256"]
        with zipfile.ZipFile(package) as archive:
            names = archive.namelist()
            for name in names:
                parts = PurePosixPath(name).parts
                assert ".." not in parts and not name.startswith("/")
                assert not set(parts) & {"WTF", "SavedVariables", "settings.json", "desktop.lock", "behavior-ai-settings.json"}, name
                assert not name.lower().endswith((".key", ".pfx", ".pem")), name
            identity, = [n for n in names if n.endswith("/manager-release.json")]
            assert json.loads(archive.read(identity)) == {"name": "MyForeverManager", "version": version, "platform": rid}
            assembly, = [n for n in names if n.endswith("/MyForeverManager.exe" if rid == "win-x64" else "/MyForeverManager")]
            binary = archive.read(assembly)
            assert "--self-update-probe".encode("utf-16le") not in binary, "Test-only entry point leaked"
            assert b"Velopack" in binary, "Missing updater integration"
            if rid == "win-x64":
                app_exe, = [n for n in names if n.endswith("/MyForeverManager.exe")]
                data = archive.read(app_exe)
                offset, = struct.unpack_from("<I", data, 0x3c)
                assert data[offset:offset+4] == b"PE\0\0" and struct.unpack_from("<H", data, offset+4)[0] == 0x8664
        result = {"platform": rid, "version": version, "installer_sha256": item["sha256"], "feed_verified": True, "personal_data_excluded": True}
        if rid.startswith("osx-"):
            with tempfile.TemporaryDirectory(prefix="myforever-dmg-check-") as temporary:
                mount = Path(temporary) / "volume"
                mount.mkdir()
                subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), str(installer)], check=True, capture_output=True)
                try:
                    assert (mount / "Applications").is_symlink() and (mount / "Applications").readlink() == Path("/Applications")
                    app, = mount.glob("*.app")
                    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
                    assert info["CFBundleIdentifier"] == "xyz.afabiaoge.manager" and info["CFBundleVersion"] == version
                    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
                    file_type = subprocess.check_output(["file", str(app / "Contents/MacOS/MyForeverManager")], text=True)
                    assert ("arm64" if rid.endswith("arm64") else "x86_64") in file_type
                finally:
                    subprocess.run(["hdiutil", "detach", str(mount)], check=True, capture_output=True)
            result["dmg_readonly_mount_and_signature"] = True
        else:
            data = installer.read_bytes()
            offset, = struct.unpack_from("<I", data, 0x3c)
            assert data[:2] == b"MZ" and data[offset:offset+4] == b"PE\0\0"
            result["setup_pe_verified"] = True
            result["native_windows_tested"] = False
        results.append(result)
    return {"passed": True, "source_commit": manifest["source_commit"], "source_dirty": manifest["source_dirty"], "results": results}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    result = check(args.directory.resolve())
    args.receipt.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
