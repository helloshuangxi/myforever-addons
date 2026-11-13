"""Build an immutable, allowlisted Navigator trial ZIP; never package user data."""
from pathlib import Path
import hashlib
import json
import re
import zipfile

root = Path(__file__).resolve().parents[2]
docs = root / "PersonalAddons"
addon = root / "_forever_/Interface/AddOns/MyForeverNavigator"
version = re.search(r"^## Version: ([0-9.]+)$", (addon / "MyForeverNavigator.toc").read_text(), re.M).group(1)
dest = docs / "dist" / f"MyForeverNavigator-{version}-Trial.zip"
files = ["MyForeverNavigator.toc", "Core.lua", "Data.lua", "Classification.lua", "Provider.lua", "QuestieCatalog.lua", "Navigation.lua", "QuestData.lua", "QuestNavigation.lua", "UI.lua", "QuestUI.lua", "Main.lua"]
extras = {"README.md": docs / "世界向导使用说明.md", "SOURCES.md": docs / "NAVIGATOR-SOURCES.md",
          "VALIDATION.md": docs / "NAVIGATOR-VALIDATION.md"}
payload = {name: (addon / name).read_bytes() for name in files}
payload.update({name: path.read_bytes() for name, path in extras.items()})
assert f"## Version: {version}" in payload["MyForeverNavigator.toc"].decode()
assert all(b"\0" not in b for b in payload.values())
dest.parent.mkdir(parents=True, exist_ok=True)
if dest.exists():
    with zipfile.ZipFile(dest) as archive:
        existing = {Path(n).name: archive.read(n) for n in archive.namelist()}
    if existing != payload:
        raise SystemExit("Refusing to overwrite a versioned ZIP with different content. Use a new version.")
else:
    with zipfile.ZipFile(dest, "x", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, content in payload.items():
            info = zipfile.ZipInfo(f"MyForeverNavigator/{name}", (2026, 11, 8, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, content)
with zipfile.ZipFile(dest) as archive:
    assert archive.testzip() is None
    assert set(archive.namelist()) == {"MyForeverNavigator/" + name for name in payload}
    for name, content in payload.items():
        assert archive.read("MyForeverNavigator/" + name) == content
digest = hashlib.sha256(dest.read_bytes()).hexdigest()
dest.with_suffix(".zip.sha256").write_text(f"{digest}  {dest.name}\n")
manifest = {"version": version, "status": "trial-local", "sha256": digest,
            "files": {name: hashlib.sha256(content).hexdigest() for name, content in payload.items()},
            "validation": "See included VALIDATION.md for simulation and observed in-game scope"}
dest.with_suffix(".manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
# Ship the same documentation with the installed directory.
for name, content in payload.items():
    if name not in files:
        (addon / name).write_bytes(content)
print(f"Built {dest.name}: {dest.stat().st_size} bytes; {len(payload)} allowlisted files")
print(f"SHA-256 {digest}")
