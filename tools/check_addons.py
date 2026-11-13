#!/usr/bin/env python3
"""Check all seven owned addons; never launch WoW or read player saves."""
from pathlib import Path
import os
import subprocess
import sys

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def main():
    os.chdir(ROOT)
    addon_root = ROOT / "_forever_/Interface/AddOns"
    addons = sorted(addon_root.glob("MyForever*"))
    assert len(addons) == 7, "Expected seven owned addon directories"
    compiler = LuaRuntime().eval(
        "function(s,n) local f,e=loadstring(s,n); assert(f,e) end"
    )
    sources = [p for addon in addons for p in sorted(addon.rglob("*.lua"))]
    for path in sources:
        compiler(path.read_text(encoding="utf-8"), "@" + str(path))
    for addon in addons:
        toc = addon / (addon.name + ".toc")
        for line in toc.read_text(encoding="utf-8").splitlines():
            entry = line.strip()
            if entry and not entry.startswith("#"):
                assert (addon / entry.replace("\\", "/")).is_file(), (toc, entry)
    print(f"Lua 5.1 syntax: {len(sources)} files; seven TOC manifests checked", flush=True)
    failed = []
    # Every addon embeds the same suite style; a drifted copy would split the look again.
    if subprocess.run([sys.executable, "tools/sync_style.py", "--check"], cwd=ROOT).returncode:
        failed.append("tools/sync_style.py --check")
    else:
        print("Shared style: seven embedded copies match the source", flush=True)
    tests = sorted((ROOT / "PersonalAddons/tests").glob("*_test.lua"))
    for path in tests:
        if path.name == "details_truncation_test.lua":
            print("EXCLUDED: legacy Details third-party patch test (not an owned addon)", flush=True)
            continue
        try:
            runtime = LuaRuntime(unpack_returned_tuples=True)
            runtime.globals().print = lambda *args: print(*args, flush=True)
            runtime.execute(path.read_text(encoding="utf-8"))
        except Exception as exc:
            print(f"FAIL {path.name}: {exc}", flush=True)
            failed.append(path.name)
    for script in ("PersonalAddons/run_coach_tests.py", "PersonalAddons/tests/test_coach_combat_log.py"):
        result = subprocess.run([sys.executable, script], cwd=ROOT)
        if result.returncode:
            failed.append(script)
    if failed:
        print("FAILED: " + ", ".join(failed), flush=True)
        return 1
    print("All owned-addon checks passed. Native game acceptance is separate.", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
