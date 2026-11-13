"""Run independent MyForeverNavigator Lua 5.1 simulation checks."""
from pathlib import Path
import os
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parent.parent
os.chdir(root)
addon = root / "_forever_/Interface/AddOns/MyForeverNavigator"
lua = LuaRuntime(unpack_returned_tuples=True)
compile_lua = lua.eval("function(s,n) local f,e=loadstring(s,n); assert(f,e) end")
for path in sorted(addon.glob("*.lua")):
    compile_lua(path.read_text(), "@" + str(path))
print(f"Lua 5.1 syntax: {len(list(addon.glob('*.lua')))} files passed", flush=True)
tests = sorted((root / "PersonalAddons/tests").glob("navigator_*_test.lua"))
assert tests, "No Navigator tests found"
for path in tests:
    runtime = LuaRuntime(unpack_returned_tuples=True)
    runtime.globals().print = lambda *args: print(*args, flush=True)
    runtime.execute(path.read_text())
print("All Navigator simulated checks passed. These are not in-game tests.", flush=True)
