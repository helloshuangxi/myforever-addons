#!/usr/bin/env python3
"""Publish an audited static directory; no remote change without --execute.

Reuses the existing Caddy image. Preserves existing hosts and rolls back on errors.
"""
from __future__ import annotations
import argparse, datetime, hashlib, io, json, pathlib, re, shlex, subprocess, sys, tarfile, tempfile, zipfile
from upload_archive import upload_archive

ROOT = pathlib.Path(__file__).resolve().parents[1]
SSH = ['ssh', '-i', str(pathlib.Path.home() / '.ssh/integrated_workbench_sgp1'), '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=10', 'root@159.223.40.78']
BLOCK = '''# BEGIN MYFOREVERCHAT WEBSITE
afabiaoge.xyz {
    encode zstd gzip
    header {
        X-Content-Type-Options nosniff
        Referrer-Policy strict-origin-when-cross-origin
        X-Frame-Options DENY
    }
    @downloads path /downloads/*.zip /manager/downloads/*.zip
    header @downloads Cache-Control "public, max-age=31536000, immutable"
    @manifest path /latest.json /releases.json /professions/latest.json /professions/releases.json /navigator/latest.json /navigator/releases.json /targets/latest.json /targets/releases.json /manager/latest.json /manager/releases.json
    header @manifest Cache-Control "no-cache"
    @pages path / /index.html /chat /chat/ /chat/index.html /professions /professions/ /professions/index.html /navigator /navigator/ /navigator/index.html /navigator/style.css /targets /targets/ /targets/index.html /targets/style.css /style.css /theme.css /script.js /portal.css /portal.js /community.css /community.js /professions/style.css /manager /manager/ /manager/index.html /manager/style.css /community-config.json /sitemap.xml
    header @pages Cache-Control "no-cache"
    handle /api/suggestions {
        reverse_proxy MYFOREVERCHAT_COMMUNITY_UPSTREAM:8081 {
            header_up Host afabiaoge.xyz
            header_up X-Forwarded-For {remote_host}
        }
    }
    handle {
        reverse_proxy myforeverchat-site:8080
    }
}
www.afabiaoge.xyz {
    redir https://afabiaoge.xyz{uri} permanent
}
# END MYFOREVERCHAT WEBSITE
'''

REMOTE = r'''
import sys,json,pathlib,subprocess,tarfile,os,time,re,sqlite3,shutil
archive=pathlib.Path(sys.argv[1]); release=sys.argv[2]; community_archive=pathlib.Path(sys.argv[3])
community_base=pathlib.Path('/var/www/myforeverchat-community')
community_target=community_base/'releases'/release
community_name='myforeverchat-community-'+release
community_state=community_base/'current.json'
previous_community=json.loads(community_state.read_text()) if community_state.is_file() else None
base=pathlib.Path('/var/www/myforeverchat'); target=base/'releases'/release
caddy=pathlib.Path('/var/www/linzihan-v3/Caddyfile')
old_config=caddy.read_text(); old_current=os.readlink(base/'current') if (base/'current').is_symlink() else None
block=BLOCK_VALUE.replace('MYFOREVERCHAT_COMMUNITY_UPSTREAM',community_name)
marker='# BEGIN MYFOREVERCHAT WEBSITE'
if marker in old_config:
 new_config=re.sub(r'# BEGIN MYFOREVERCHAT WEBSITE\n.*?# END MYFOREVERCHAT WEBSITE\n?',lambda _:block,old_config,flags=re.S)
else:
 if re.search(r'^\s*(?:www\.)?afabiaoge\.xyz(?:\s|,|\{)',old_config,re.M): raise RuntimeError('Unmanaged apex host already exists; review before publishing')
 new_config=old_config.rstrip()+'\n\n'+block

def run(args, data=None, check=True):
 r=subprocess.run(args,input=data,text=True,capture_output=True)
 if check and r.returncode: raise RuntimeError('Command failed: '+args[0]+' '+args[1]+' (details retained on server)')
 return r

def reload_config(content):
 # Preserve the inode: the main Caddy container mounts this individual file.
 caddy.write_text(content)
 return run(['docker','exec','linzihan-v3-caddy-1','caddy','reload','--config','/etc/caddy/Caddyfile','--adapter','caddyfile'])

def set_current(dest):
 tmp=base/('.current-'+release)
 if tmp.is_symlink():tmp.unlink()
 tmp.symlink_to(dest);os.replace(tmp,base/'current')

def deploy_community():
 if community_target.exists():raise RuntimeError('Community release already exists')
 community_target.mkdir(parents=True)
 with tarfile.open(community_archive) as t:
  if {m.name for m in t.getmembers()}!={'server.py','admin.py'} or any(not m.isfile() for m in t.getmembers()):raise RuntimeError('Unexpected private service archive')
  t.extractall(community_target,filter='data')
 run(['docker','volume','create','myforeverchat-community-data'])
 volume=json.loads(run(['docker','volume','inspect','myforeverchat-community-data']).stdout)[0]
 data=pathlib.Path(volume['Mountpoint']);os.chown(data,10001,10001);os.chmod(data,0o700)
 service_backup=community_base/'backups'/release;service_backup.mkdir(parents=True,mode=0o700)
 if (data/'suggestions.sqlite3').exists():
  with sqlite3.connect(data/'suggestions.sqlite3') as source, sqlite3.connect(service_backup/'suggestions.sqlite3') as destination:source.backup(destination)
  os.chmod(service_backup/'suggestions.sqlite3',0o600)
 if (data/'abuse.key').exists():
  shutil.copyfile(data/'abuse.key',service_backup/'abuse.key');os.chmod(service_backup/'abuse.key',0o600)
 (service_backup/'previous.json').write_text(json.dumps(previous_community));os.chmod(service_backup/'previous.json',0o600)
 proxy=json.loads(run(['docker','inspect','linzihan-v3-caddy-1']).stdout)[0]['NetworkSettings']['Networks']['linzihan-v3_default']['IPAddress']
 image=json.loads(run(['docker','inspect','sg-tcp-subscription']).stdout)[0]['Image']
 run(['docker','run','-d','--name',community_name,'--restart','unless-stopped','--network','linzihan-v3_default','--read-only','--user','10001:10001','--cap-drop','ALL','--security-opt','no-new-privileges:true','--memory','128m','--cpus','0.30','--pids-limit','64','--tmpfs','/tmp:rw,noexec,nosuid,size=8m','-v',str(community_target)+':/app:ro','-v','myforeverchat-community-data:/data','-e','PYTHONDONTWRITEBYTECODE=1','-e','PYTHONUNBUFFERED=1','-e','ALLOWED_ORIGIN=https://afabiaoge.xyz','-e','TRUSTED_PROXY_IPS='+proxy,'--entrypoint','python3',image,'/app/server.py'])
 info=json.loads(run(['docker','inspect',community_name]).stdout)[0]
 ip=info['NetworkSettings']['Networks']['linzihan-v3_default']['IPAddress']
 for _ in range(12):
  result=run(['curl','-fsS','--max-time','3','http://'+ip+':8081/health'],check=False)
  if result.returncode==0 and json.loads(result.stdout).get('ok'):return
  time.sleep(.5)
 raise RuntimeError('Community service failed internal health check')

if target.exists():raise RuntimeError('Release directory already exists')
with tarfile.open(archive) as t:
 for m in t.getmembers():
  p=pathlib.PurePosixPath(m.name)
  if p.is_absolute() or '..' in p.parts or not (m.isfile() or m.isdir()):raise RuntimeError('Unsafe archive member')
 target.mkdir(parents=True)
 t.extractall(target,filter='data')
if not (target/'index.html').is_file():raise RuntimeError('Missing index.html')
backup=base/'backups'/release;backup.mkdir(parents=True,mode=0o700)
(backup/'Caddyfile').write_text(old_config);os.chmod(backup/'Caddyfile',0o600)
(backup/'previous.json').write_text(json.dumps({'current':old_current},indent=2))
# Validate inside the existing container with its current environment.
candidate='/tmp/myforeverchat-'+release+'.Caddyfile'
run(['docker','exec','-i','linzihan-v3-caddy-1','sh','-c','cat > '+candidate],new_config)
valid=run(['docker','exec','linzihan-v3-caddy-1','caddy','validate','--config',candidate,'--adapter','caddyfile'],check=False)
(backup/'validate.log').write_text(valid.stdout+valid.stderr);os.chmod(backup/'validate.log',0o600)
if valid.returncode:raise RuntimeError('Candidate Caddy config failed validation')
created=False;changed=False;community_created=False
try:
 community_created=True
 deploy_community()
 set_current('releases/'+release);changed=True
 exists=run(['docker','container','inspect','myforeverchat-site'],check=False).returncode==0
 if not exists:
  run(['docker','run','-d','--name','myforeverchat-site','--restart','unless-stopped','--network','linzihan-v3_default','--read-only','--cap-drop','ALL','--cap-add','NET_BIND_SERVICE','--security-opt','no-new-privileges:true','--memory','96m','--pids-limit','64','-v',str(base)+':/srv:ro','--entrypoint','caddy','caddy:2.8-alpine','file-server','--root','/srv/current','--listen',':8080'])
  created=True
 info=json.loads(run(['docker','inspect','myforeverchat-site']).stdout)[0]
 ip=info['NetworkSettings']['Networks']['linzihan-v3_default']['IPAddress']
 ready=False
 for _ in range(10):
  test=run(['curl','-fsS','--max-time','3','http://'+ip+':8080/'],check=False)
  if test.returncode==0 and '<html' in test.stdout.lower():ready=True;break
  time.sleep(.5)
 if not ready:raise RuntimeError('Static container failed readiness check')
 reload_config(new_config)
 health=run(['curl','-fsS','--max-time','15','https://chat.afabiaoge.xyz/api/health'],check=False)
 if health.returncode:raise RuntimeError('Existing chat health failed after reload')
 # Wait for automatic ACME certificate issuance. All checks retain TLS verification.
 live=False
 for _ in range(12):
  check=run(['curl','-fsS','--max-time','8','--resolve','afabiaoge.xyz:443:127.0.0.1','https://afabiaoge.xyz/'],check=False)
  if check.returncode==0 and check.stdout==(target/'index.html').read_text():live=True;break
  time.sleep(2)
 if not live:raise RuntimeError('Apex strict TLS/body verification failed')
 redirected=False
 for _ in range(15):
  www=run(['curl','-sS','-o','/dev/null','-w','%{http_code} %{redirect_url}','--max-time','8','--resolve','www.afabiaoge.xyz:443:127.0.0.1','https://www.afabiaoge.xyz/'],check=False)
  if www.returncode==0 and www.stdout.startswith(('301 https://afabiaoge.xyz/','308 https://afabiaoge.xyz/')):
   redirected=True;break
  time.sleep(2)
 if not redirected:raise RuntimeError('www strict TLS/redirect verification failed')
 api=run(['curl','-fsS','--max-time','10','--resolve','afabiaoge.xyz:443:127.0.0.1','https://afabiaoge.xyz/api/suggestions?limit=1'],check=False)
 if api.returncode or not isinstance(json.loads(api.stdout).get('items'),list):raise RuntimeError('Public suggestions GET failed')
 community_state.write_text(json.dumps({'container':community_name,'release':release,'source':str(community_target)},indent=2)+'\n')
 if previous_community and previous_community['container']!=community_name:run(['docker','stop','--time','10',previous_community['container']],check=False)
 print(json.dumps({'status':'deployed','release':release,'path':str(target),'backup':str(backup),'apex':'https://afabiaoge.xyz','www':www.stdout,'existing_chat_health':'passed','community_container':community_name,'community_get':'passed','community_write_test':False},ensure_ascii=False))
except Exception as error:
 print(json.dumps({'status':'failed','reason':str(error),'backup':str(backup)},ensure_ascii=False))
 if changed:
  if old_current:set_current(old_current)
  elif (base/'current').is_symlink():(base/'current').unlink()
 try:reload_config(old_config)
 except Exception:pass
 if community_created:
  logs=run(['docker','logs',community_name],check=False)
  (backup/'community.log').write_text(logs.stdout+logs.stderr);os.chmod(backup/'community.log',0o600)
  run(['docker','rm','-f',community_name],check=False)
 if created:
  logs=run(['docker','logs','myforeverchat-site'],check=False)
  (backup/'static-container.log').write_text(logs.stdout+logs.stderr)
  run(['docker','rm','-f','myforeverchat-site'],check=False)
 raise
finally:
 run(['docker','exec','linzihan-v3-caddy-1','rm','-f',candidate],check=False)
 if archive.exists():archive.unlink()
 if community_archive.exists():community_archive.unlink()
'''

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--public',type=pathlib.Path,default=ROOT/'public')
 p.add_argument('--execute',action='store_true')
 args=p.parse_args();public=args.public.resolve()
 if not (public/'index.html').is_file():p.error('Public directory must contain index.html')
 service_files=[ROOT/'community/server.py',ROOT/'community/admin.py']
 if not all(x.is_file() and not x.is_symlink() for x in service_files):p.error('Private community service source is missing')
 files=sorted(x for x in public.rglob('*') if x.is_file())
 forbidden=re.compile(r'(^|/)(?:\.env[^/]*|WTF|SavedVariables|backups?|\.git|node_modules|ops)(/|$)',re.I)
 for f in files:
  rel=f.relative_to(public).as_posix()
  if f.suffix.lower() in {'.py','.sqlite','.sqlite3','.db','.key','.pem','.sql'} or f.is_symlink() or forbidden.search(rel) or f.name.startswith('.'):p.error('Unsafe public path: '+rel)
  if f.suffix.lower()=='.zip':
   with zipfile.ZipFile(f) as z:
    for n in z.namelist():
     if forbidden.search(n) or '..' in pathlib.PurePosixPath(n).parts or n.startswith('/'):p.error('Unsafe ZIP member: '+n)
 print(json.dumps({'public':str(public),'files':len(files),'bytes':sum(f.stat().st_size for f in files),'execute':args.execute},ensure_ascii=False))
 if not args.execute:return
 subprocess.run([sys.executable,str(ROOT/'ops/verify_site.py'),'--public',str(public)],check=True)
 release=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
 with tempfile.TemporaryDirectory(prefix='myforeverchat-deploy-') as td:
  archive=pathlib.Path(td)/('site-'+release+'.tar.gz')
  with tarfile.open(archive,'w:gz') as t:
   for f in files:t.add(f,arcname=f.relative_to(public).as_posix(),recursive=False)
  service_archive=pathlib.Path(td)/('community-'+release+'.tar.gz')
  with tarfile.open(service_archive,'w:gz') as t:
   for f in service_files:t.add(f,arcname=f.name,recursive=False)
  remote_service_archive='/var/www/myforeverchat/.incoming/'+service_archive.name
  remote_archive='/var/www/myforeverchat/.incoming/'+archive.name
  subprocess.run(SSH+['mkdir -p /var/www/myforeverchat/.incoming'],check=True)
  scp=['scp',*SSH[1:-1]]
  upload_archive(archive,remote_archive,ssh=SSH,scp=scp,progress=lambda event:print(json.dumps({'upload':event}),flush=True))
  upload_archive(service_archive,remote_service_archive,ssh=SSH,scp=scp)
  script=REMOTE.replace('BLOCK_VALUE',repr(BLOCK))
  result=subprocess.run(SSH+['python3 - '+shlex.quote(remote_archive)+' '+shlex.quote(release)+' '+shlex.quote(remote_service_archive)],input=script,text=True,capture_output=True)
  if result.stdout:print(result.stdout.strip())
  if result.returncode:
   # Remote logs/config backups may contain private routes; do not echo them.
   print('Deployment failed and rollback attempted. Inspect server backup logs privately.');raise SystemExit(1)

if __name__=='__main__':main()
