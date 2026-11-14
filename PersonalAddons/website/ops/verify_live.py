#!/usr/bin/env python3
"""Read-only public verification. Retain no chat/studio response bodies."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import hashlib,json,urllib.request,urllib.error,datetime,argparse

root=Path(__file__).resolve().parents[1] if __file__!='<stdin>' else Path.cwd()
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--public',type=Path,default=root/'public')
parser.add_argument('--output',default=str(root/'ops'/'live-verification.json'),help='Report file, or - for stdout only (allows the same checks to run over SSH stdin).')
args=parser.parse_args()
public=args.public
base='https://afabiaoge.xyz/'
latest=json.loads((public/'latest.json').read_text())
paths=['','chat/','style.css','script.js','portal.css','portal.js','latest.json','releases.json','sitemap.xml']+['assets/'+p.name for pattern in ('chat-*.jpg', 'professions-*.jpg') for p in sorted((public/'assets').glob(pattern))]
packages={}
if (public/'theme.css').is_file():
 paths += ['theme.css']
paths += ['assets/'+p.name for p in sorted((public/'assets').glob('ui-20261114-*.png'))]
for folder in [public, *[public/name for name in ('professions','navigator','targets') if (public/name/'latest.json').exists()]]:
 catalog=json.loads((folder/'releases.json').read_text())
 for entry in catalog['releases']:
  if entry.get('download'):
   record=entry['download'];path='downloads/'+record['filename']
   assert path not in packages, 'Duplicate package path'
   packages[path]=record;paths.extend([path,path+'.sha256'])
if (public/'professions/latest.json').exists():
 paths += ['professions/','professions/latest.json','professions/releases.json','professions/style.css']
if (public/'navigator/latest.json').exists():
 paths += ['navigator/','navigator/latest.json','navigator/releases.json','navigator/style.css']
if (public/'targets/latest.json').exists():
 paths += ['targets/','targets/latest.json','targets/releases.json','targets/style.css']

if (public/'manager/latest.json').is_file():
 paths += ['manager/', 'manager/style.css', 'manager/latest.json', 'manager/releases.json']
 catalog=json.loads((public/'manager/releases.json').read_text())
 for entry in catalog['releases']:
  for record in entry['downloads']:
   path='manager/downloads/'+record['filename']
   assert path not in packages, 'Duplicate manager package path'
   packages[path]=record;paths.extend([path,path+'.sha256'])

if (public/'community-config.json').is_file():
 config=json.loads((public/'community-config.json').read_text())
 paths += ['community-config.json','community.js','community.css']
 donation=config.get('donation',{})
 paths += [value for value in [config.get('author',{}).get('avatar_url'),donation.get('qr_url')]+[v.get('qr_url') for v in donation.get('amounts',{}).values()] if value]
 paths=list(dict.fromkeys(paths))

def fetch(path):
 with urllib.request.urlopen(base+path,timeout=120 if path in packages else 30) as r:
  body=r.read();d={'path':'/'+path,'status':r.status,'content_type':r.headers.get('Content-Type'),'bytes':len(body),'sha256':hashlib.sha256(body).hexdigest(),'cache_control':r.headers.get('Cache-Control','')}
  local=public/(path or 'index.html')
  if local.is_dir():local=local/'index.html'
  assert body==local.read_bytes(),f'Body mismatch: {path}'
  if path in ('','chat/','professions/','navigator/','targets/','manager/') or Path(path).suffix.lower() in {'.css','.js','.json','.xml'}:
   assert 'no-cache' in d['cache_control'],f'Mutable page/assets must revalidate: {path}'
  suffix=Path(path).suffix.lower()
  if suffix in {'.jpg','.jpeg'}:assert body.startswith(b'\xff\xd8') and 'image/jpeg' in d['content_type']
  if suffix=='.png':assert body.startswith(b'\x89PNG\r\n\x1a\n') and 'image/png' in d['content_type']
  if suffix=='.webp':assert body.startswith(b'RIFF') and body[8:12]==b'WEBP' and 'image/webp' in d['content_type']
  if path in packages:assert d['bytes']==packages[path]['size_bytes'] and d['sha256']==packages[path]['sha256']
  return d

results=list(ThreadPoolExecutor(max_workers=4).map(fetch,paths))
class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,*args,**kwargs):return None
try:
 urllib.request.build_opener(NoRedirect).open('https://www.afabiaoge.xyz/',timeout=20)
 raise AssertionError('www must redirect')
except urllib.error.HTTPError as e:
 assert e.code in (301,308) and e.headers.get('Location')=='https://afabiaoge.xyz/'
 www={'status':e.code,'location':e.headers.get('Location')}
with urllib.request.urlopen('https://chat.afabiaoge.xyz/api/health',timeout=20) as r:
 assert r.status==200
 chat={'status':r.status}
try:
 with urllib.request.urlopen('https://studio.afabiaoge.xyz/',timeout=20) as r:
  studio={'status':r.status,'final_url':r.url,'login_required':r.url=='https://studio.afabiaoge.xyz/login'}
except urllib.error.HTTPError as e:
 studio={'status':e.code}
assert studio['status']==401 or studio.get('login_required'), 'Protected studio must still require authentication'
community=None
if (public/'community-config.json').is_file():
 with urllib.request.urlopen(base+'api/suggestions?limit=1',timeout=20) as r:
  value=json.load(r)
  assert r.status==200 and isinstance(value['items'],list) and isinstance(value['has_more'],bool)
  assert set(value)=={'items','has_more','next_before'}
  for item in value['items']:
   assert set(item)=={'id','nickname','body','created_at'}
   assert isinstance(item['id'],int) and all(isinstance(item[k],str) for k in ('nickname','body','created_at'))
  community={'status':200,'returned_items':len(value['items']),'has_more':value['has_more'],'write_test_performed':False}
report={'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'passed','files':results,'www':www,'chat_health':chat,'studio_protected':studio,'community':community}
if args.output!='-':
 out=Path(args.output);out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False,indent=2))
