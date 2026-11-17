import json, sys, subprocess, urllib.request
from pathlib import Path
root=Path(__file__).resolve().parent
site=root.parent/"navigator-0.7.0-site"
sys.path.insert(0,str(site/"ops"))
from deploy import SSH
from static_reuse import static_tree
code="""
from pathlib import Path
import hashlib,json
base=Path('/var/www/myforeverchat/current').resolve(strict=True)
def digest(path):
    d=hashlib.sha256()
    with path.open('rb') as reader:
        for part in iter(lambda:reader.read(1024*1024),b''):
            d.update(part)
    return d.hexdigest()
print(json.dumps({'release':base.name,'files':{p.relative_to(base).as_posix():digest(p) for p in base.rglob('*') if p.is_file()}}))
"""
remote=json.loads(subprocess.check_output(SSH+["python3 -"],input=code,text=True))
tree=static_tree(site/"public")
assert remote["files"]==tree,sorted(k for k in tree.keys()|remote["files"].keys() if tree.get(k)!=remote["files"].get(k))
before=json.loads((site/"ops/production-before.json").read_text())
assert remote["release"]!=before["release"]
for k,v in before["files"].items():
    assert k in tree
    if k.endswith((".dmg",".zip",".exe",".nupkg")): assert tree[k]==v,k
for path,version in [("navigator/latest.json","0.7.0"),("manager/latest.json","0.6.0")]:
    with urllib.request.urlopen("https://afabiaoge.xyz/"+path,timeout=20) as f:
        assert json.load(f)["version"]==version
(site/"ops/production-after.json").write_text(json.dumps(remote,indent=2)+"\n")
receipt={"release":remote["release"],"matched_files":len(tree),"unchanged_old_immutable":sum(k.endswith((".dmg",".zip",".exe",".nupkg")) for k in before["files"]),"verified_public_releases":{"navigator":"0.7.0","manager":"0.6.0"}}
(root/"production-verified.json").write_text(json.dumps(receipt,indent=2)+"\n")
print(json.dumps(receipt))
