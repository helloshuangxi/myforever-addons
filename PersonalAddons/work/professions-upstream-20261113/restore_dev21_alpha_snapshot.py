"""Restore only the two raced dev21 snapshot files; never live addon files.

Default: validate reconstructed hashes. Add --apply to update the snapshot.
"""
from pathlib import Path
import hashlib
import json
import sys

base = Path(__file__).resolve().parent
snapshot = base / "dev21-before-alpha"
manifest = json.loads((base / "dev21-candidate-hashes.json").read_text())
paths = (
    "_forever_/Interface/AddOns/MyForeverProfessions/GatherStandIn.lua",
    "PersonalAddons/tests/professions_standin_test.lua",
)
restored = []
for relative in paths:
    path = snapshot / relative
    content = path.read_text()
    if hashlib.sha256(content.encode()).hexdigest() == manifest[relative]:
        print(f"Already dev21: {relative}")
        continue
    if relative.endswith("GatherStandIn.lua"):
        start = content.index("local function applyOpacity(value)")
        end = content.index("\nfunction stand.Show", start)
        old = '''local function applyOpacity(value)
    local ok=pcall(frame.SetAlpha,frame,value)
    local actual=call(frame.GetAlpha,frame)
    if not ok or not number(actual,0,1) or abs(actual-value)>.00001 then error("opacity-write-failed") end
    return actual
end
'''
        content = content[:start] + old + content[end:]
    else:
        replacements = (
            ('near(f:GetAlpha(),128/255,"half opacity uses byte-representable owned alpha")',
             'near(f:GetAlpha(),.5,"half opacity only on owned frame")'),
            ('if self==f and value==64/255 then error("PRIVATE_OPACITY_WRITE") end',
             'if self==f and value==.25 then error("PRIVATE_OPACITY_WRITE") end'),
            ('if self==f and self.alpha==77/255 then return SECRET end',
             'if self==f and self.alpha==.3 then return SECRET end'),
        )
        for new, old in replacements:
            assert content.count(new) == 1, (relative, new)
            content = content.replace(new, old)
        start = content.index("\n-- Build 70938 rounds native alpha to a byte.")
        end = content.index("for _,value in pairs(stand.Diagnostics()) do", start)
        content = content[:start] + content[end:]
    digest = hashlib.sha256(content.encode()).hexdigest()
    assert digest == manifest[relative], (relative, digest, manifest[relative])
    restored.append((path, content))
    print(f"Validated dev21: {relative} {digest}")

if "--apply" in sys.argv[1:]:
    for path, content in restored:
        path.write_text(content)
    print(f"Restored {len(restored)} snapshot files; live files untouched.")
