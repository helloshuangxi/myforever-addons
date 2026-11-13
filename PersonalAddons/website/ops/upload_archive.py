#!/usr/bin/env python3
"""Upload large deployment archives in verified parallel chunks over existing SSH.

No shell interpolation of filenames, no service changes, and no public files are
written here. The server only exposes the incoming archive after full verification.
"""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shlex
import subprocess
import tempfile
import time
import uuid

THRESHOLD = 16 * 1024 * 1024
CHUNK_BYTES = 2 * 1024 * 1024
WORKERS = 6
INCOMING = '/var/www/myforeverchat/.incoming'

# Tests execute this same assembly program with an isolated transport root. No
# application source, credentials or archive content is printed by the program.
REMOTE_PROGRAM = r'''
import hashlib,json,os,pathlib,re,shutil,sys
root=pathlib.Path('/var/www/myforeverchat/.incoming')
action,parts_name,target_name=sys.argv[1:4]
if not re.fullmatch(r'upload-[a-f0-9]{32}',parts_name):raise ValueError('Invalid upload identity')
if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*\.tar\.gz',target_name):raise ValueError('Invalid archive name')
if root.is_symlink():raise ValueError('Incoming directory cannot be a symlink')
root.mkdir(parents=True,exist_ok=True)
parts=root/parts_name;target=root/target_name
if parts.is_symlink():raise ValueError('Upload directory cannot be a symlink')
os.umask(0o077)
if action=='init':
 parts.mkdir(mode=0o700)
elif action=='cleanup':
 if parts.exists():shutil.rmtree(parts)
elif action=='assemble':
 manifest=json.loads(sys.argv[4])
 if not parts.is_dir():raise ValueError('Missing upload directory')
 chunks=manifest['chunks']
 if not chunks or len(chunks)>65536:raise ValueError('Invalid chunk count')
 expected={f'part-{i:06d}' for i in range(len(chunks))}
 if {p.name for p in parts.iterdir()}!=expected:raise ValueError('Missing or extra chunk')
 if not re.fullmatch(r'[a-f0-9]{64}',manifest['sha256']):raise ValueError('Invalid final digest')
 size=manifest['size_bytes']
 if not isinstance(size,int) or size<=0:raise ValueError('Invalid final size')
 combined=hashlib.sha256();total=0
 assembled=parts/'assembled.tmp'
 with assembled.open('xb') as output:
  for i,record in enumerate(chunks):
   chunk=parts/f'part-{i:06d}'
   if chunk.is_symlink() or not chunk.is_file():raise ValueError('Unsafe chunk')
   if not isinstance(record['size_bytes'],int) or not 0<record['size_bytes']<=2*1024*1024:raise ValueError('Invalid chunk size')
   if chunk.stat().st_size!=record['size_bytes']:raise ValueError('Chunk size mismatch')
   if not re.fullmatch(r'[a-f0-9]{64}',record['sha256']):raise ValueError('Invalid chunk digest')
   digest=hashlib.sha256();chunk_size=0
   with chunk.open('rb') as source:
    while True:
     block=source.read(1024*1024)
     if not block:break
     chunk_size+=len(block);total+=len(block)
     if chunk_size>record['size_bytes'] or total>size:raise ValueError('Chunk grew during verification')
     digest.update(block);combined.update(block);output.write(block)
   if chunk_size!=record['size_bytes'] or digest.hexdigest()!=record['sha256']:raise ValueError('Chunk digest mismatch')
  if total!=size or combined.hexdigest()!=manifest['sha256']:raise ValueError('Final archive digest mismatch')
  output.flush();os.fsync(output.fileno())
 # Atomic, no overwrite: a prior incoming archive or symlink cannot be replaced.
 os.link(assembled,target)
 assembled.unlink()
 directory_fd=os.open(root,os.O_RDONLY)
 try:os.fsync(directory_fd)
 finally:os.close(directory_fd)
 print(json.dumps({'status':'verified','chunks':len(chunks),'bytes':total,'sha256':combined.hexdigest()}))
else:raise ValueError('Unknown upload action')
'''


class UploadError(RuntimeError):
    pass


def _run(command, *, input=None, timeout=180):
    return subprocess.run(command, input=input, text=True, capture_output=True, timeout=timeout, check=True)


def _remote(ssh, action, parts_name, target_name, manifest=None):
    arguments = [action, parts_name, target_name]
    if manifest is not None:
        arguments.append(json.dumps(manifest, separators=(',', ':')))
    command = 'python3 - ' + ' '.join(shlex.quote(value) for value in arguments)
    return _run([*ssh, command], input=REMOTE_PROGRAM, timeout=180)


def _destination(remote_archive):
    path = PurePosixPath(remote_archive)
    if str(path.parent) != INCOMING or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*\.tar\.gz', path.name):
        raise ValueError('Archive destination must be a named tar.gz in the existing incoming directory')
    return path.name


def upload_archive(local_archive, remote_archive, *, ssh, scp, threshold=THRESHOLD,
                   workers=WORKERS, attempts=3, progress=None):
    """Use one SCP below threshold; above it assemble only verified chunks.

    ``ssh`` includes the existing destination host as its final argument. ``scp``
    contains only the command and its existing authentication/host-check options.
    The optional progress callback receives counts, never filenames or contents.
    """
    local_archive = Path(local_archive).absolute()
    target_name = _destination(remote_archive)
    if local_archive.is_symlink() or not local_archive.is_file():
        raise ValueError('Archive must be a regular local file')
    if not ssh or not scp or not 1 <= workers <= 6 or not 1 <= attempts <= 5:
        raise ValueError('Invalid upload transport or concurrency')
    size = local_archive.stat().st_size
    if size <= 0:
        raise ValueError('Archive is empty')
    host = ssh[-1]
    if size < threshold:
        try:
            _run([*scp, str(local_archive), host + ':' + remote_archive])
        except (subprocess.SubprocessError, OSError):
            raise UploadError('Small archive upload failed; deployment did not start') from None
        if progress:
            progress({'mode': 'scp', 'completed': 1, 'total': 1, 'bytes': size})
        return {'mode': 'scp', 'chunks': 1, 'bytes': size}

    parts_name = 'upload-' + uuid.uuid4().hex
    initialized = False
    with tempfile.TemporaryDirectory(prefix='myforever-upload-') as temporary:
        temporary = Path(temporary)
        chunks = []
        digest = hashlib.sha256()
        total = 0
        with local_archive.open('rb') as source:
            for index in range(65536):
                block = source.read(CHUNK_BYTES)
                if not block:
                    break
                digest.update(block)
                total += len(block)
                (temporary / f'part-{index:06d}').write_bytes(block)
                chunks.append({'size_bytes': len(block), 'sha256': hashlib.sha256(block).hexdigest()})
            else:
                raise ValueError('Archive exceeds chunk count limit')
        if total != size:
            raise UploadError('Local archive changed size during preparation')
        manifest = {'size_bytes': size, 'sha256': digest.hexdigest(), 'chunks': chunks}

        def transfer(index):
            source = temporary / f'part-{index:06d}'
            destination = host + ':' + INCOMING + '/' + parts_name + '/' + source.name
            for attempt in range(attempts):
                try:
                    _run([*scp, str(source), destination])
                    return
                except (subprocess.SubprocessError, OSError):
                    if attempt + 1 == attempts:
                        raise UploadError('Chunk upload failed after bounded retries') from None
                    time.sleep(min(attempt + 1, 3))

        failure = None
        try:
            # Clean up even if SSH disconnects after creating the unique directory.
            initialized = True
            _remote(ssh, 'init', parts_name, target_name)
            completed = 0
            with ThreadPoolExecutor(max_workers=workers) as pool:
                futures = [pool.submit(transfer, index) for index in range(len(chunks))]
                try:
                    for future in as_completed(futures):
                        future.result()
                        completed += 1
                        if progress:
                            progress({'mode': 'chunks', 'completed': completed, 'total': len(chunks), 'bytes': size})
                except BaseException:
                    for future in futures:
                        future.cancel()
                    raise
            result = _remote(ssh, 'assemble', parts_name, target_name, manifest)
            receipt = json.loads(result.stdout)
            if receipt != {'status': 'verified', 'chunks': len(chunks), 'bytes': size, 'sha256': manifest['sha256']}:
                raise UploadError('Server verification receipt did not match the archive')
        except BaseException as error:
            failure = error
            if isinstance(error, (KeyboardInterrupt, SystemExit, UploadError)):
                raise
            raise UploadError('Archive upload or server integrity verification failed; deployment did not start') from None
        finally:
            if initialized:
                try:
                    _remote(ssh, 'cleanup', parts_name, target_name)
                except (subprocess.SubprocessError, OSError):
                    if failure is None:
                        raise UploadError('Archive verified, but temporary chunk cleanup failed; deployment did not start') from None
        return {'mode': 'chunks', 'chunks': len(chunks), 'bytes': size, 'sha256': manifest['sha256']}
