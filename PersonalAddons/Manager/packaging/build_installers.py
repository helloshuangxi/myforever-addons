#!/usr/bin/env python3
"""Build local DMG/Setup candidates and Velopack feeds; never deploy anything."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
VERSION = ET.parse(ROOT / "Desktop/MyForeverManager.Desktop.csproj").findtext("PropertyGroup/Version")
VPK_VERSION = "1.2.161"
RIDS = ("osx-arm64", "osx-x64", "win-x64")


def run(*args, env=None):
    subprocess.run([str(a) for a in args], cwd=ROOT, env=env, check=True)


def build(args, rid, output, env):
    version = args.fixture_version or VERSION
    package_id = args.probe_id if args.update_probe else "MyForeverManagerApp"
    bundle_id = "xyz.afabiaoge.manager" + (".probe." + package_id.lower() if args.update_probe else "")
    publish = output / "publish" / rid
    command = [args.dotnet, "publish", ROOT / "Desktop/MyForeverManager.Desktop.csproj",
               "-c", "Release", "-r", rid, "--self-contained", "true",
               "-p:PublishSingleFile=true", "-p:IncludeNativeLibrariesForSelfExtract=true",
               "-p:PublishTrimmed=false", "-p:DebugType=None", "-p:DebugSymbols=false",
               f"-p:Version={version}", f"-p:InformationalVersion={version}", "-o", publish]
    if args.update_probe:
        command.append("-p:DefineConstants=SELF_UPDATE_PROBE")
    run(*command)
    # Identity stays compatible with older release tooling; updater metadata is
    # separate (sq.version/releases.*.json), not extra identity schema fields.
    (publish / "manager-release.json").write_text(json.dumps({
        "name": "MyForeverManager", "version": version, "platform": rid
    }, indent=2) + "\n")
    for source, name in [(ROOT / "README.md", "README.txt"),
                         (ROOT.parent / "website/public/LICENSE.txt", "LICENSE.txt"),
                         (ROOT / "packaging/THIRD-PARTY-NOTICES.txt", "THIRD-PARTY-NOTICES.txt")]:
        shutil.copy2(source, publish / name)
    pack_dir = publish
    if rid.startswith("osx-"):
        pack_dir = output / "stage" / rid / "MyForeverManager.app"
        contents = pack_dir / "Contents"
        shutil.copytree(publish, contents / "MacOS")
        (contents / "Resources").mkdir()
        for name in ("README.txt", "LICENSE.txt", "THIRD-PARTY-NOTICES.txt", "manager-release.json"):
            shutil.move(contents / "MacOS" / name, contents / "Resources" / name)
        shutil.copy2(ROOT / "packaging/MyForeverManager.icns", contents / "Resources")
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleExecutable": "MyForeverManager", "CFBundleIdentifier": bundle_id,
            "CFBundleName": "MyForeverManager", "CFBundleDisplayName": "我的无限 · 插件管理器",
            "CFBundleVersion": version, "CFBundleShortVersionString": version,
            "CFBundlePackageType": "APPL", "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleIconFile": "MyForeverManager.icns", "LSMinimumSystemVersion": "14.0",
            "NSHighResolutionCapable": True, "NSPrincipalClass": "NSApplication"
        }))
        # codesign --deep treats managed PE assemblies in MacOS/ as generic
        # code and writes detached signatures into xattrs. Those signatures do
        # not survive nupkg extraction. Sign Mach-O only; vpk signs its injected
        # UpdateMac and the final bundle with --signDisableDeep.
        macho = {b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf"}
        for file in sorted((contents / "MacOS").rglob("*")):
            if file.is_file():
                with file.open("rb") as reader:
                    native = reader.read(4) in macho
                if native and file.name != "MyForeverManager":
                    run("codesign", "--force", "--sign", "-", file)
    feed = output / "updates" / rid
    command = [args.vpk, "[osx]" if rid.startswith("osx-") else "[win]", "pack", "--skip-updates", "--yes",
               "--packId", package_id, "--packTitle", "MyForeverManager",
               "--packAuthors", "Hyder", "--packVersion", version, "--packDir", pack_dir,
               "--runtime", rid, "--channel", rid, "--outputDir", feed,
               "--mainExe", "MyForeverManager" + (".exe" if rid == "win-x64" else ""),
               "--delta", "None"]
    if rid.startswith("osx-"):
        entitlements = pack_dir.parent / "MyForeverManager.entitlements"
        shutil.copy2(ROOT / "packaging/entitlements.plist", entitlements)
        command += ["--bundleId", bundle_id, "--noInst",
                    "--signAppIdentity", "-", "--signEntitlements", entitlements, "--signDisableDeep"]
    else:
        command += ["--icon", ROOT / "packaging/MyForeverManager.ico", "--shortcuts", "StartMenuRoot"]
        if platform.system() != "Windows":
            command.append("--skipVeloAppCheck")
    run(*command, env=env)
    if rid.startswith("osx-"):
        portable, = feed.glob("*-Portable.zip")
        image_stage = output / "dmg-stage" / rid
        image_stage.mkdir(parents=True)
        # ditto preserves executable modes and symlinks in the finalized bundle.
        run("ditto", "-x", "-k", portable, image_stage)
        app, = image_stage.glob("*.app")
        run("codesign", "--verify", "--deep", "--strict", app)
        (image_stage / "Applications").symlink_to("/Applications", target_is_directory=True)
        (image_stage / "安装说明.txt").write_text(
            "将 MyForeverManager 拖到 Applications（应用程序），再从应用程序打开。\n"
            "首次替换旧版前请退出管理器。设置和行为数据保留在用户资料目录。\n"
            "候选版：尚未 Apple Developer ID 签名或公证，公开更新源尚未启用。\n")
        installer = output / f"MyForeverManager-{version}-Trial-{rid}.dmg"
        run("hdiutil", "create", "-volname", "MyForeverManager", "-srcfolder", image_stage,
            "-format", "UDZO", installer)
        run("hdiutil", "verify", installer)
    else:
        setup, = feed.glob("*-Setup.exe")
        installer = output / f"MyForeverManager-{version}-Trial-{rid}-Setup.exe"
        shutil.copy2(setup, installer)
    digest = hashlib.sha256(installer.read_bytes()).hexdigest()
    installer.with_suffix(installer.suffix + ".sha256").write_text(f"{digest}  {installer.name}\n")
    return {"platform": rid, "version": version, "installer": installer.name,
            "sha256": digest, "size_bytes": installer.stat().st_size,
            "feed": f"updates/{rid}", "update_probe_fixture": args.update_probe}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dotnet", default="dotnet")
    parser.add_argument("--vpk", required=True, help=f"Pinned vpk {VPK_VERSION} executable")
    parser.add_argument("--rid", choices=RIDS, action="append")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--update-probe", action="store_true", help="Compile temporary updater probe fixtures, not deliverables")
    parser.add_argument("--fixture-version", help="Only with --update-probe; packaging version for A/B test")
    parser.add_argument("--probe-id", default="MyForeverManagerAppProbe", help="Test-only app/cache identity; use the same unique ID for A and B")
    args = parser.parse_args()
    if args.fixture_version and (not args.update_probe or not re.fullmatch(r"\d+\.\d+\.\d+", args.fixture_version)):
        parser.error("--fixture-version requires --update-probe and a numeric x.y.z version")
    if not re.fullmatch(r"MyForeverManagerAppProbe[A-Za-z0-9]*", args.probe_id):
        parser.error("Probe ID must be separate from the real updater cache")
    if any(r.startswith("osx-") for r in args.rid or RIDS) and platform.system() != "Darwin":
        parser.error("Mac installers must be built on macOS")
    output = (args.output or ROOT / "artifacts/candidates" / datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")).resolve()
    if output.exists() and any(output.iterdir()):
        parser.error("Output must be new or empty; released files may not be overwritten")
    output.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    if Path(args.dotnet).is_absolute():
        env["DOTNET_ROOT"] = str(Path(args.dotnet).resolve().parent)
    version = subprocess.check_output([args.vpk, "-h"], env=env, text=True)
    if not re.search(r"\b" + re.escape(VPK_VERSION) + r"\b", version):
        parser.error(f"Expected vpk {VPK_VERSION}, got {version.strip()}")
    manifest = {"name": "MyForeverManager", "version": args.fixture_version or VERSION,
                "candidate": True, "published": False, "velopack": VPK_VERSION,
                "package_id": args.probe_id if args.update_probe else "MyForeverManagerApp",
                "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                "source_dirty": bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()),
                "artifacts": []}
    for rid in args.rid or RIDS:
        manifest["artifacts"].append(build(args, rid, output, env))
        (output / "INSTALLERS.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2), flush=True)


if __name__ == "__main__":
    main()
