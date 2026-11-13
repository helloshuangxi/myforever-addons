#!/usr/bin/env python3
"""Build self-contained desktop candidates without changing released packages."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = ET.parse(ROOT / "Desktop/MyForeverManager.Desktop.csproj").findtext("PropertyGroup/Version")
if not VERSION:
    raise ValueError("Desktop project must declare a release version")
PLATFORMS = ("osx-arm64", "win-x64", "osx-x64")


def run(*args):
    subprocess.run([str(x) for x in args], check=True, cwd=ROOT)


def package(dotnet, rid, output, publish_root=None):
    publish = publish_root / rid if publish_root else output / "publish" / rid
    if publish_root:
        if not publish.is_dir():
            raise ValueError(f"Missing prebuilt publish directory: {publish}")
    else:
        run(dotnet, "publish", ROOT / "Desktop/MyForeverManager.Desktop.csproj",
            "-c", "Release", "-r", rid, "--self-contained", "true",
            "-p:PublishSingleFile=true",
            "-p:IncludeNativeLibrariesForSelfExtract=true", "-p:PublishTrimmed=false",
            "-p:DebugType=None", "-p:DebugSymbols=false", "-o", publish)
    stage = output / "stage" / rid
    stage.mkdir(parents=True)
    if rid == "win-x64":
        for file in publish.iterdir():
            if file.is_file() and file.suffix.lower() != ".pdb":
                shutil.copy2(file, stage / file.name)
    else:
        app = stage / "MyForeverManager.app"
        contents = app / "Contents"
        shutil.copytree(publish, contents / "MacOS")
        (contents / "Resources").mkdir()
        icon = ROOT / "packaging/MyForeverManager.icns"
        if icon.exists():
            shutil.copy2(icon, contents / "Resources" / icon.name)
        plist = {
            "CFBundleExecutable": "MyForeverManager",
            "CFBundleIdentifier": "xyz.afabiaoge.manager",
            "CFBundleName": "我的无限",
            "CFBundleDisplayName": "我的无限 · 插件管理器",
            "CFBundleVersion": VERSION,
            "CFBundleShortVersionString": VERSION,
            "CFBundlePackageType": "APPL",
            "CFBundleInfoDictionaryVersion": "6.0",
            "LSMinimumSystemVersion": "14.0",
            "NSHighResolutionCapable": True,
            "NSPrincipalClass": "NSApplication",
        }
        if icon.exists():
            plist["CFBundleIconFile"] = icon.name
        (contents / "Info.plist").write_bytes(plistlib.dumps(plist))
        executable = contents / "MacOS/MyForeverManager"
        executable.chmod(0o755)
        # Sign each Mach-O explicitly, then the outer bundle. Do not recursively
        # assign executable entitlements to managed assemblies or data files.
        macho = {b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"}
        for file in sorted((contents / "MacOS").rglob("*")):
            if file.is_file() and file != executable:
                with file.open("rb") as reader:
                    native = reader.read(4) in macho
                if native:
                    run("codesign", "--force", "--sign", "-", file)
        run("codesign", "--force", "--sign", "-", "--entitlements",
            ROOT / "packaging/entitlements.plist", app)
        run("codesign", "--verify", "--deep", "--strict", app)
    shutil.copy2(ROOT / "README.md", stage / "README.txt")
    shutil.copy2(ROOT.parent / "website/public/LICENSE.txt", stage / "LICENSE.txt")
    notices = ROOT / "packaging/THIRD-PARTY-NOTICES.txt"
    if notices.exists():
        shutil.copy2(notices, stage / notices.name)
    (stage / "manager-release.json").write_text(json.dumps({
        "name": "MyForeverManager", "version": VERSION, "platform": rid
    }, indent=2) + "\n")
    archive = output / f"MyForeverManager-{VERSION}-Trial-{rid}.zip"
    with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for file in sorted(stage.rglob("*")):
            if file.is_symlink():
                raise ValueError(f"Unexpected symlink: {file}")
            if file.is_file():
                z.write(file, file.relative_to(stage).as_posix())
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix(".zip.sha256").write_text(f"{digest}  {archive.name}\n")
    print(json.dumps({"platform": rid, "package": str(archive), "sha256": digest,
                      "size_bytes": archive.stat().st_size}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dotnet", default="dotnet")
    parser.add_argument("--rid", choices=PLATFORMS, action="append")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--publish-root", type=Path, help="Package already compiled, verified per-RID publish folders")
    args = parser.parse_args()
    output = args.output or ROOT / "artifacts/candidates" / datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output = output.resolve()
    if output.exists() and any(output.iterdir()):
        parser.error("Candidate output directory must be new or empty")
    output.mkdir(parents=True, exist_ok=True)
    print("Candidate directory: " + str(output), flush=True)
    for rid in args.rid or PLATFORMS:
        package(args.dotnet, rid, output, args.publish_root.resolve() if args.publish_root else None)


if __name__ == "__main__":
    main()
