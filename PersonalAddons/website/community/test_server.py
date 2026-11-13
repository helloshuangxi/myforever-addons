#!/usr/bin/env python3
"""HTTP integration tests using isolated SQLite and real loopback sockets."""
import http.client
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
import uuid

from server import BoardServer, Store, BODY_LIMIT


class BoardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='mfc-community-test-')
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.start()
        self.addCleanup(self.stop)

    def start(self, **limits):
        self.store = Store(self.directory, **limits)
        self.server = BoardServer(('127.0.0.1', 0), self.store, 'https://afabiaoge.xyz', ['127.0.0.1'])
        self.worker = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.worker.start()

    def stop(self):
        self.server.shutdown()
        self.server.server_close()
        self.worker.join(timeout=2)

    def call(self, method='GET', path='/api/suggestions', value=None, headers=None, raw=None):
        defaults = {'Host': 'afabiaoge.xyz', 'Origin': 'https://afabiaoge.xyz', 'X-Forwarded-For': '203.0.113.1'}
        if value is not None:
            raw = json.dumps(value).encode()
            defaults['Content-Type'] = 'application/json'
        defaults.update(headers or {})
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=3)
        try:
            connection.request(method, path, raw, defaults)
            response = connection.getresponse()
            data, result_headers, status = response.read(), dict(response.getheaders()), response.status
            return status, json.loads(data), result_headers
        finally:
            connection.close()

    def post(self, body='建议一', **kwargs):
        value = {'nickname': '', 'body': body, 'website': '', 'request_id': str(uuid.uuid4())}
        value.update(kwargs.pop('fields', {}))
        return self.call('POST', value=value, **kwargs)

    def test_persistence_floor_pagination_and_public_fields(self):
        self.stop()
        self.start(interval=0, hourly=100, daily=100)
        for text in ['第一条', '第二条', '第三条']:
            self.assertEqual(self.post(text)[0], 201)
        status, data, headers = self.call(path='/api/suggestions?limit=2')
        self.assertEqual(status, 200)
        self.assertEqual([x['id'] for x in data['items']], [3, 2])
        self.assertTrue(data['has_more'])
        self.assertEqual(data['next_before'], 2)
        self.assertEqual(set(data['items'][0]), {'id', 'nickname', 'body', 'created_at'})
        self.assertNotIn('Access-Control-Allow-Origin', headers)
        self.stop()
        self.start()
        data = self.call(path='/api/suggestions?before=2&limit=2')[1]
        self.assertEqual(data['items'][0]['body'], '第一条')
        self.assertEqual(data['items'][0]['nickname'], '匿名玩家')
        self.assertFalse(data['has_more'])
        self.assertIsNone(data['next_before'])

    def test_idempotency_and_conflicting_request(self):
        value = {'body': '不要重复', 'request_id': str(uuid.uuid4())}
        first = self.call('POST', value=value)
        second = self.call('POST', value=value)
        self.assertEqual((first[0], second[0]), (201, 200))
        self.assertEqual(first[1], second[1])
        value['body'] = '内容改变'
        self.assertEqual(self.call('POST', value=value)[0], 409)
        self.assertEqual(len(self.call()[1]['items']), 1)

    def test_validation_and_same_origin(self):
        for fields in [{'body': ''}, {'body': ' '}, {'body': 'x' * 2001}, {'nickname': 'a' * 25}, {'body': '\x00'}, {'request_id': 'bad'}, {'website': 'spam'}]:
            with self.subTest(fields=fields):
                self.assertEqual(self.post(fields=fields)[0], 400)
        self.assertEqual(self.post(headers={'Origin': 'https://evil.example'})[0], 403)
        self.assertEqual(self.post(headers={'Origin': ''})[0], 403)
        self.assertEqual(self.post(headers={'Host': 'evil.example'})[0], 403)
        self.assertEqual(self.call('POST', raw=b'{}', headers={'Content-Type': 'text/plain'})[0], 415)
        self.assertEqual(self.call('POST', raw=b'x' * (BODY_LIMIT + 1), headers={'Content-Type': 'application/json'})[0], 413)
        self.assertEqual(self.call(path='/api/suggestions?limit=51')[0], 400)
        self.assertEqual(self.call(path='/api/suggestions?before=-1')[0], 400)
        self.assertEqual(self.call(path='/api/suggestions?limit=1&limit=2')[0], 400)
        self.assertEqual(len(self.call()[1]['items']), 0)

    def test_html_is_plain_text_and_ip_is_not_stored(self):
        text = '<img src=x onerror=alert(1)> & <script>hello</script>'
        status, data, headers = self.post(text)
        self.assertEqual(status, 201)
        self.assertEqual(data['item']['body'], text)
        self.assertEqual(headers['Content-Type'], 'application/json; charset=utf-8')
        with sqlite3.connect(self.store.path) as db:
            row = db.execute('SELECT ip_hash FROM abuse').fetchone()
            self.assertEqual(len(row[0]), 64)
            dump = '\n'.join(db.iterdump())
        self.assertNotIn('203.0.113.1', dump)
        self.assertNotIn('ip_hash', json.dumps(self.call()[1]))

    def test_rate_limit_and_trusted_proxy_boundary(self):
        self.assertEqual(self.post()[0], 201)
        status, _, headers = self.post()
        self.assertEqual(status, 429)
        self.assertGreater(int(headers['Retry-After']), 0)
        self.assertEqual(self.post(headers={'X-Forwarded-For': '203.0.113.2'})[0], 201)
        self.assertEqual(self.post(headers={'X-Forwarded-For': '203.0.113.2, 8.8.8.8'})[0], 400)
        self.server.trusted_proxies = set()
        self.assertEqual(self.post(headers={'X-Forwarded-For': '203.0.113.50'})[0], 201)
        self.assertEqual(self.post(headers={'X-Forwarded-For': '203.0.113.51'})[0], 429)

    def test_rate_window_crosses_midnight_and_abuse_expires(self):
        midnight = 1794009600  # 2026-11-07 UTC midnight
        with patch('server.time.time', return_value=midnight - 1):
            self.assertEqual(self.post()[0], 201)
        with patch('server.time.time', return_value=midnight + 1):
            self.assertEqual(self.post()[0], 429)
        with sqlite3.connect(self.store.path) as db:
            db.execute('INSERT INTO abuse VALUES (?,?)', ('expired-test', int(time.time()) - 86401))
        self.store.cleanup()
        with sqlite3.connect(self.store.path) as db:
            self.assertIsNone(db.execute('SELECT 1 FROM abuse WHERE ip_hash=?', ('expired-test',)).fetchone())

    def test_hourly_global_and_total_limits(self):
        self.stop()
        self.start(interval=0, hourly=2, daily=10, global_daily=3, capacity=4)
        self.assertEqual(self.post()[0], 201)
        self.assertEqual(self.post()[0], 201)
        self.assertEqual(self.post()[0], 429)
        self.assertEqual(self.post(headers={'X-Forwarded-For': '203.0.113.2'})[0], 201)
        self.assertEqual(self.post(headers={'X-Forwarded-For': '203.0.113.3'})[1]['error']['code'], 'board_busy')
        self.store.global_daily = 10
        self.assertEqual(self.post(headers={'X-Forwarded-For': '203.0.113.3'})[0], 201)
        self.assertEqual(self.post(headers={'X-Forwarded-For': '203.0.113.4'})[1]['error']['code'], 'board_full')

    def test_local_delete_preserves_floor_and_prevents_replay(self):
        self.stop()
        self.start(interval=0)
        value = {'body': '待删除测试', 'request_id': str(uuid.uuid4())}
        self.assertEqual(self.call('POST', value=value)[0], 201)
        subprocess.run([sys.executable, str(Path(__file__).with_name('admin.py')), '--database', str(self.store.path), 'delete', '1'], check=True, capture_output=True)
        self.assertEqual(self.call()[1]['items'], [])
        self.assertEqual(self.call('POST', value=value)[0], 409)
        self.assertEqual(self.post()[1]['item']['id'], 2)
        with sqlite3.connect(self.store.path) as db:
            self.assertEqual(db.execute('SELECT body FROM suggestions WHERE id=1').fetchone()[0], '')


if __name__ == '__main__':
    unittest.main(verbosity=2)
