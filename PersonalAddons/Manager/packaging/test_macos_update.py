#!/usr/bin/env python3
"""Exercise the real Mac updater only inside a fresh temporary fixture."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--old", type=Path, required=True, help="Probe installer build directory (0.5.0)")
    parser.add_argument("--new", type=Path, required=True, help="Probe installer build directory (0.5.1)")
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    old, new = args.old.resolve(), args.new.resolve()
    identities = []
    for build in (old, new):
        manifest = json.loads((build / "INSTALLERS.json").read_text())
        assert manifest["artifacts"][0]["update_probe_fixture"], "Only explicit test fixtures allowed"
        identities.append(manifest["package_id"])
    assert identities[0] == identities[1] and identities[0].startswith("MyForeverManagerAppProbe")
    cache = Path.home() / "Library/Caches/velopack" / identities[0]
    assert not cache.exists(), "Choose a fresh --probe-id for A and B, never reuse a cached test version"
    fixture = Path(tempfile.mkdtemp(prefix="myforever-updater-"))
    (fixture / "fixture.json").write_text('{"isolated":true}')
    portable, = (old / "updates/osx-arm64").glob("*-Portable.zip")
    applications = fixture / "Applications"
    applications.mkdir()
    subprocess.run(["ditto", "-x", "-k", str(portable), str(applications)], check=True)
    app, = applications.glob("*.app")
    executable = app / "Contents/MacOS/MyForeverManager"
    shutil.copytree(new / "updates/osx-arm64", fixture / "feed")
    state = fixture / "state"
    state.mkdir()
    game = fixture / "game/_forever_"
    (game / "Interface/AddOns/OtherAddon").mkdir(parents=True)
    (game / "WTF").mkdir()
    sentinels = {
        state / "settings.json": json.dumps({"GameDirectory": str(game), "AutoUpdate": False, "AutoUpdateManager": True}),
        state / "behavior-ai-settings.json": '{"enabled":false,"fixture":"preserve"}',
        state / "behavior-import.json": '{"fixture":"preserve-behavior"}',
        game / "WTF/SavedVariables.lua": "fixture = 'preserve-personal-data'\n",
        game / "Interface/AddOns/OtherAddon/OtherAddon.lua": "-- preserve unrelated addon\n"
    }
    for path, contents in sentinels.items():
        path.write_text(contents)
    before = {str(p.relative_to(fixture)): digest(p) for p in sentinels}
    env = os.environ.copy()
    env["MYFOREVER_MANAGER_STATE_DIR"] = str(state)
    package, = (fixture / "feed").glob("*-full.nupkg")
    good_package = package.read_bytes()
    # Keep the size identical: the SDK must reject content by digest, not size.
    bad = bytearray(good_package)
    bad[len(bad) // 2] ^= 1
    package.write_bytes(bad)
    with (fixture / "corrupt.log").open("w") as log:
        corrupt = subprocess.run([str(executable), "--self-update-probe", str(fixture)], env=env,
                                 stdout=log, stderr=subprocess.STDOUT, timeout=90)
    rejected = json.loads((fixture / "downloaded.json").read_text())
    assert corrupt.returncode == 2 and rejected["phase"] == "Failed" and rejected["target"] is None, rejected
    assert plistlib.loads((app / "Contents/Info.plist").read_bytes())["CFBundleVersion"] == "0.5.0"
    package.write_bytes(good_package)
    with (fixture / "apply.log").open("w") as log:
        subprocess.run([str(executable), "--self-update-probe", str(fixture)], env=env, stdout=log,
                       stderr=subprocess.STDOUT, timeout=90, check=True)
    downloaded = json.loads((fixture / "downloaded.json").read_text())
    assert downloaded == {"IsInstalled": True, "version": "0.5.0", "target": "0.5.1", "phase": "Ready"}, downloaded
    deadline = time.monotonic() + 55
    while not (fixture / "restarted.json").exists() and time.monotonic() < deadline:
        time.sleep(0.5)
    restarted = json.loads((fixture / "restarted.json").read_text())
    assert restarted == {"IsInstalled": True, "version": "0.5.1"}, restarted
    assert plistlib.loads((app / "Contents/Info.plist").read_bytes())["CFBundleVersion"] == "0.5.1"
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    after = {str(p.relative_to(fixture)): digest(p) for p in sentinels}
    assert after == before, "App replacement changed protected data"
    receipt = {"passed": True, "fixture": str(fixture), "corrupt_package_rejected": rejected,
               "downloaded": downloaded, "restarted": restarted, "protected_files": before,
               "signature_verified_after_update": True,
               "scope": "Isolated Apple Silicon macOS; test-only probe builds; no real game or user state"}
    args.receipt.write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
