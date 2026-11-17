"""Install the verified arm64 build with an atomic, reversible app swap."""
import ctypes, json, os, plistlib, subprocess
from pathlib import Path
from hashlib import sha256
work=Path(__file__).resolve().parent
source=work/"manager-final/dmg-stage/osx-arm64/MyForeverManager.app"
installed=Path("/Applications/MyForeverManager.app")
backup=work.parents[1]/"backups"/"manager-0.6.0-local-install"/"MyForeverManager-0.5.0.app"
def version(app): return plistlib.loads((app/"Contents/Info.plist").read_bytes())["CFBundleShortVersionString"]
def verify(app): subprocess.run(["codesign","--verify","--deep","--strict",str(app)],check=True)
def settings_digest():
    root=Path.home()/"Library/Application Support/MyForeverManager"
    return {n:sha256((root/n).read_bytes()).digest() for n in ("settings.json","behavior-ai.json","navigator/behavior-ai.json") if (root/n).is_file()}
def assert_closed():
    running=subprocess.check_output(["ps","-axo","comm="],text=True).splitlines()
    assert not any(s.strip().endswith("/MyForeverManager.app/Contents/MacOS/MyForeverManager") for s in running),"manager is running"
assert version(source)=="0.6.0" and version(installed)=="0.5.0" and not backup.exists()
verify(source)
before=settings_digest()
backup.parent.mkdir(parents=True,exist_ok=True)
subprocess.run(["ditto",str(source),str(backup)],check=True)
verify(backup)
assert version(backup)=="0.6.0" and backup.stat().st_dev==installed.stat().st_dev
assert_closed()
swap=ctypes.CDLL(None,use_errno=True).renamex_np
swap.argtypes=[ctypes.c_char_p,ctypes.c_char_p,ctypes.c_uint]
def exchange():
    if swap(os.fsencode(installed),os.fsencode(backup),2)!=0: raise OSError(ctypes.get_errno(),"app swap")
exchange()
try:
    verify(installed)
    assert version(installed)=="0.6.0" and version(backup)=="0.5.0" and before==settings_digest()
except BaseException:
    exchange()
    raise
receipt={"installed":str(installed),"version":version(installed),"signed_bundle_verified":True,"settings_preserved":True,"backup":str(backup)}
(work/"local-manager-install.json").write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+"\n")
print(json.dumps(receipt,ensure_ascii=False))
