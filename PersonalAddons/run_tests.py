"""Run Lua 5.1 syntax and behavior checks; does not launch or control WoW."""
from pathlib import Path
import os
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parent.parent
os.chdir(root)
addons = root / "_forever_/Interface/AddOns"
sources = [source for name in ("MyForeverMacros", "MyForeverFieldKit", "MyForeverChat", "MyForeverProfessions", "MyForeverCoach")
           for source in sorted((addons / name).glob("*.lua"))]
lua = LuaRuntime(unpack_returned_tuples=True)
compile_lua = lua.eval("function(text, name) local chunk, err = loadstring(text, name); assert(chunk, err); return true end")
for source in sources:
    compile_lua(source.read_text(), "@" + str(source))
print(f"Lua 5.1 syntax: {len(sources)} files passed", flush=True)
for test in sorted((root / "PersonalAddons/tests").glob("*_test.lua")):
    runtime = LuaRuntime(unpack_returned_tuples=True)
    runtime.execute(test.read_text())
print("All simulated checks passed. In-game acceptance remains required.", flush=True)
