#!/usr/bin/env python3
"""Transport tests execute the real remote verifier inside an isolated directory."""
import hashlib
import json
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

import upload_archive as upload

REAL_RUN = subprocess.run


class Transport:
    def __init__(self, incoming, *, corrupt=False, transient=False, permanent=False, final_hash=False, missing=False):
        self.incoming = incoming
        self.corrupt, self.transient, self.permanent, self.final_hash, self.missing = corrupt, transient, permanent, final_hash, missing
        self.calls, self.counts = [], {}
        self.active = self.maximum = 0
        self.lock = threading.Lock()

    def run(self, command, **options):
        with self.lock:
            self.calls.append(command)
        if command[0] == 'scp':
            source = Path(command[-2])
            remote = command[-1].split(':', 1)[1]
            destination = self.incoming / str(Path(remote).relative_to(upload.INCOMING))
            with self.lock:
                count = self.counts[source.name] = self.counts.get(source.name, 0) + 1
                self.active += 1
                self.maximum = max(self.maximum, self.active)
            try:
                time.sleep(.02)
                if self.permanent or self.transient and source.name == 'part-000000' and count == 1:
                    destination.write_bytes(b'partial failed copy')
                    raise subprocess.CalledProcessError(1, command, stderr='private transport text must not escape')
                if not (self.missing and source.name == 'part-000001'):
                    shutil.copyfile(source, destination)
                if self.corrupt and source.name == 'part-000001':
                    with destination.open('r+b') as stream:
                        byte = stream.read(1)
                        stream.seek(0)
                        stream.write(bytes([byte[0] ^ 1]))
                return subprocess.CompletedProcess(command, 0, stdout='', stderr='')
            finally:
                with self.lock:
                    self.active -= 1
        if command[0] != 'ssh':
            raise AssertionError('Unexpected transport')
        remote_args = shlex.split(command[-1])
        if self.final_hash and remote_args[2] == 'assemble':
            manifest = json.loads(remote_args[-1])
            manifest['sha256'] = '0' * 64
            remote_args[-1] = json.dumps(manifest)
        script = options.pop('input').replace("pathlib.Path('/var/www/myforeverchat/.incoming')", 'pathlib.Path(' + repr(str(self.incoming)) + ')')
        return REAL_RUN([sys.executable, '-', *remote_args[2:]], input=script, **options)


class UploadTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix='mfm-upload-test-')
        self.addCleanup(temp.cleanup)
        self.base = Path(temp.name)
        self.incoming = self.base / 'incoming'
        self.incoming.mkdir()
        (self.incoming / 'unrelated-file').write_text('keep')
        self.source = self.base / 'site-test.tar.gz'
        self.source.write_bytes(bytes(range(251)) * 20000)
        self.remote = upload.INCOMING + '/site-test.tar.gz'

    def perform(self, transport, **kwargs):
        with patch.object(upload.subprocess, 'run', side_effect=transport.run):
            return upload.upload_archive(self.source, self.remote, ssh=['ssh', '-o', 'BatchMode=yes', 'test@host'], scp=['scp', '-o', 'BatchMode=yes'], **kwargs)

    def assert_cleanup(self):
        self.assertFalse(list(self.incoming.glob('upload-*')))
        self.assertEqual((self.incoming / 'unrelated-file').read_text(), 'keep')

    def test_small_archive_preserves_single_scp_path(self):
        transport = Transport(self.incoming)
        result = self.perform(transport)
        self.assertEqual(result['mode'], 'scp')
        self.assertEqual(len(transport.calls), 1)
        self.assertEqual((self.incoming / self.source.name).read_bytes(), self.source.read_bytes())
        self.assert_cleanup()

    def test_parallel_upload_remote_assembly_and_sha256_receipt(self):
        self.source.write_bytes(bytes(range(251)) * 70000)
        transport = Transport(self.incoming)
        progress = []
        result = self.perform(transport, progress=progress.append)
        self.assertEqual(result['mode'], 'chunks')
        self.assertGreater(transport.maximum, 1)
        self.assertLessEqual(transport.maximum, 6)
        self.assertEqual((self.incoming / self.source.name).read_bytes(), self.source.read_bytes())
        self.assertEqual(result['sha256'], hashlib.sha256(self.source.read_bytes()).hexdigest())
        self.assertEqual([x['completed'] for x in progress], list(range(1, result['chunks'] + 1)))
        self.assert_cleanup()

    def test_partial_scp_failure_retries_same_chunk(self):
        transport = Transport(self.incoming, transient=True)
        result = self.perform(transport, threshold=1)
        self.assertEqual(transport.counts['part-000000'], 2)
        self.assertEqual(result['sha256'], hashlib.sha256((self.incoming / self.source.name).read_bytes()).hexdigest())
        self.assert_cleanup()

    def test_corrupted_same_size_chunk_never_exposes_final_archive(self):
        with self.assertRaises(upload.UploadError):
            self.perform(Transport(self.incoming, corrupt=True), threshold=1)
        self.assertFalse((self.incoming / self.source.name).exists())
        self.assert_cleanup()

    def test_final_hash_mismatch_never_exposes_final_archive(self):
        with self.assertRaises(upload.UploadError):
            self.perform(Transport(self.incoming, final_hash=True), threshold=1)
        self.assertFalse((self.incoming / self.source.name).exists())
        self.assert_cleanup()

    def test_missing_chunk_never_exposes_final_archive(self):
        with self.assertRaises(upload.UploadError):
            self.perform(Transport(self.incoming, missing=True), threshold=1)
        self.assertFalse((self.incoming / self.source.name).exists())
        self.assert_cleanup()

    def test_preexisting_final_archive_not_overwritten(self):
        (self.incoming / self.source.name).write_bytes(b'previous archive')
        with self.assertRaises(upload.UploadError):
            self.perform(Transport(self.incoming), threshold=1)
        self.assertEqual((self.incoming / self.source.name).read_bytes(), b'previous archive')
        self.assert_cleanup()

    def test_exhausted_retries_clean_only_owned_directory(self):
        transport = Transport(self.incoming, permanent=True)
        with self.assertRaisesRegex(upload.UploadError, 'bounded retries') as context:
            self.perform(transport, threshold=1, attempts=2)
        self.assertNotIn('private transport', str(context.exception))
        self.assertTrue(all(count <= 2 for count in transport.counts.values()))
        self.assertFalse((self.incoming / self.source.name).exists())
        self.assert_cleanup()

    def test_unsafe_destination_rejected_before_any_transport(self):
        for destination in ('/tmp/site-test.tar.gz', upload.INCOMING + '/../outside.tar.gz', upload.INCOMING + '/bad;whoami.tar.gz'):
            with self.subTest(destination=destination), patch.object(upload.subprocess, 'run') as run, self.assertRaises(ValueError):
                upload.upload_archive(self.source, destination, ssh=['ssh', 'test@host'], scp=['scp'], threshold=1)
            run.assert_not_called()


if __name__ == '__main__':
    unittest.main(verbosity=2)
