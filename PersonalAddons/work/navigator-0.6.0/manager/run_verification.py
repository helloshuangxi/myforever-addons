import datetime
import hashlib
import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

evidence = Path(__file__).resolve().parent
task = evidence.parent
site = task.with_name('navigator-0.6.0-site') / 'public'
provenance=json.loads((evidence/'provenance.json').read_text())
checkout=Path(provenance['source'])
isolated=Path(provenance['isolated_source'])
sdk='/Users/mashuangxi/.cache/afabiaoge-dotnet/dotnet'
mode=sys.argv[1]
assert mode in {'local', 'live'}
while not (evidence/'frozen.sha256').is_file():
    time.sleep(2)
expected_sha=(evidence/'frozen.sha256').read_text().strip()
release=json.loads((site/'navigator/latest.json').read_text())
assert release['version']=='0.6.0' and release['download']['sha256']==expected_sha
nav=site/'downloads'/release['download']['filename']
assert hashlib.sha256(nav.read_bytes()).hexdigest()==release['download']['sha256']
targets=site/'downloads'/json.loads((site/'targets/latest.json').read_text())['download']['filename']
results=[]
for group,dll,argv in [('directed',isolated/'Directed/bin/Release/net10.0/Directed.dll',[str(site)]),
                         ('official',isolated/'Tests/bin/Release/net10.0/MyForeverManager.Tests.dll',
                          ['--site-root',str(site),'--navigator-zip',str(nav),'--targets-zip',str(targets)])]:
    if mode=='live':argv.append('--live')
    cmd=[sdk,str(dll),*argv]
    proc=subprocess.run(cmd,capture_output=True,cwd=isolated,text=True)
    log=proc.stdout+proc.stderr;(evidence/f'{mode}-{group}.log').write_text(log)
    result=re.search(r'RESULT: (\d+) passed, (\d+) failed',log)
    if not result or proc.returncode or int(result[2]):
        print(log[-2500:]);raise SystemExit(proc.returncode or 1)
    results.append(dict(group=group,passed=int(result[1]),failed=int(result[2]),command=cmd))
    print(mode,group,result[0],flush=True)
src_hashes=provenance['source_files_sha256']
for r,expected in src_hashes.items():
    assert hashlib.sha256((checkout/r).read_bytes()).hexdigest()==expected
    assert hashlib.sha256((isolated/r).read_bytes()).hexdigest()==expected
shutil.copy2(isolated/'Directed/Program.cs',evidence/'DirectedProgram.cs')
result=dict(time=datetime.datetime.now(datetime.timezone.utc).isoformat(),mode=mode,manager_version='0.5.0',manager_source_hashes_matched=len(src_hashes),navigator_version=release['version'],navigator_bytes=nav.stat().st_size,navigator_sha256=release['download']['sha256'],results=results,real_game_modified=False,real_manager_settings_accessed=False,desktop_binary_or_ui_exercised=False)
(evidence/(mode+'-summary.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
