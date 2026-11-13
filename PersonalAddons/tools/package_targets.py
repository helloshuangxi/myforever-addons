"""Build the allowlisted Targets trial package without saved settings or logs."""
from pathlib import Path, PurePosixPath
import hashlib
import json
import re
import zipfile

root = Path(__file__).resolve().parents[2]
docs = root / "PersonalAddons"
addon = root / "_forever_/Interface/AddOns/MyForeverTargets"
toc = addon / "MyForeverTargets.toc"
version = re.search(r"^## Version: ([0-9.]+)$", toc.read_text(), re.M).group(1)
entries = [line.strip().replace("\\", "/") for line in toc.read_text().splitlines()
           if line.strip() and not line.lstrip().startswith("#")]
files = ["MyForeverTargets.toc", *entries, "README.md", "Libs/SOURCES.md", "Libs/LibRangeCheck-3.0/LICENSE"]
payload = {}
for name in files:
    path = PurePosixPath(name)
    source = addon / path
    assert not path.is_absolute() and ".." not in path.parts and name not in payload, name
    assert source.is_file() and not source.is_symlink(), name
    assert source.resolve().is_relative_to(addon.resolve()), name
    payload[name] = source.read_bytes()
payload["VALIDATION.md"] = (docs / "releases" / f"targets-{version}-VALIDATION.md").read_bytes()
assert all(b"\0" not in value for value in payload.values())
assert len(entries) == len(set(entries))
assert {str(p.relative_to(addon)) for p in addon.rglob("*.lua")} == set(entries), "Unlisted Lua source"
assert f'NS.VERSION = "{version}"' in payload["Core.lua"].decode()
dest = docs / "dist" / f"MyForeverTargets-{version}-Trial.zip"
dest.parent.mkdir(parents=True, exist_ok=True)
members = {"MyForeverTargets/" + name: data for name, data in payload.items()}
if dest.exists():
    with zipfile.ZipFile(dest) as archive:
        existing = {name: archive.read(name) for name in archive.namelist()}
    if existing != members:
        raise SystemExit("Versioned package already exists with different content; use a new version.")
else:
    with zipfile.ZipFile(dest, "x", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(members.items()):
            info = zipfile.ZipInfo(name, (2026, 11, 11, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data)
with zipfile.ZipFile(dest) as archive:
    assert archive.testzip() is None
    assert len(archive.namelist()) == len(members)
    assert {name: archive.read(name) for name in archive.namelist()} == members
digest = hashlib.sha256(dest.read_bytes()).hexdigest()
dest.with_suffix(".zip.sha256").write_text(f"{digest}  {dest.name}\n")
manifest = {"version": version, "sha256": digest, "size_bytes": dest.stat().st_size,
            "files": {name: hashlib.sha256(data).hexdigest() for name, data in sorted(payload.items())},
            "validation": "Public validation scope is included as VALIDATION.md; no saved settings or logs."}
dest.with_suffix(".manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
print(json.dumps({"package": str(dest), "files": len(members), "sha256": digest,
                  "size_bytes": dest.stat().st_size}, ensure_ascii=False, indent=2))
