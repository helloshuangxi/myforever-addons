"""Run only MyForeverProfessions Lua 5.1 checks, independently of other add-ons."""
from pathlib import Path
import os
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parent.parent
os.chdir(root)
sources = sorted((root / "_forever_/Interface/AddOns/MyForeverProfessions").glob("*.lua"))
lua = LuaRuntime(unpack_returned_tuples=True)
compile_lua = lua.eval("function(text, name) local chunk, err = loadstring(text, name); assert(chunk, err) end")
for source in sources:
    compile_lua(source.read_text(), "@" + str(source))
print(f"MyForeverProfessions Lua 5.1 syntax: {len(sources)} files passed", flush=True)
for test in sorted((root / "PersonalAddons/tests").glob("professions_*_test.lua")):
    runtime = LuaRuntime(unpack_returned_tuples=True)
    runtime.globals().print = lambda *args: print(*args, flush=True)
    runtime.execute(test.read_text())
print("Simulated checks passed. See PROFESSIONS-VALIDATION.md for actual in-game coverage.", flush=True)
