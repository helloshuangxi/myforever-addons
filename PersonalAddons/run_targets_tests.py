"""Run independent MyForeverTargets Lua 5.1 simulations; not game validation."""
from pathlib import Path
import os

from lupa.lua51 import LuaRuntime


root = Path(__file__).resolve().parent.parent
os.chdir(root)
addon = root / "_forever_/Interface/AddOns/MyForeverTargets"
manifest = addon / "MyForeverTargets.toc"
entries = [line.strip() for line in manifest.read_text().splitlines()
           if line.strip() and not line.lstrip().startswith("#")]
declared = [addon / entry.replace("\\", "/") for entry in entries if entry.endswith(".lua")]
sources = sorted(addon.rglob("*.lua"))
assert sources, "No MyForeverTargets sources found"
assert all(path.is_file() for path in declared), "TOC references missing sources"
assert {path for path in declared if path.parent == addon} == set(addon.glob("*.lua")), "Root Lua sources and TOC differ"
lua = LuaRuntime(unpack_returned_tuples=True)
compile_lua = lua.eval("function(s,n) local f,e=loadstring(s,n); assert(f,e) end")
for path in sources:
    compile_lua(path.read_text(), "@" + str(path))
print(f"Lua 5.1 syntax: {len(sources)} files passed", flush=True)
tests = sorted((root / "PersonalAddons/tests").glob("targets_*_test.lua"))
assert tests, "No Targets tests found"
for path in tests:
    runtime = LuaRuntime(unpack_returned_tuples=True)
    runtime.globals().print = lambda *args: print(*args, flush=True)
    runtime.execute(path.read_text())
print("All Targets simulated checks passed. These are not in-game tests.", flush=True)
