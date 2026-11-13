#!/usr/bin/env python3
"""Anonymous, plain-text suggestion board. Python standard library only."""
from __future__ import annotations
from contextlib import contextmanager
import datetime as dt
import hashlib
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import sqlite3
import threading
import time
from urllib.parse import parse_qs, urlsplit
import uuid

BODY_LIMIT = 16_384
CONTROL = re.compile(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]')


class APIError(Exception):
    def __init__(self, status, code, message, retry_after=None):
        self.status, self.code, self.message, self.retry_after = status, code, message, retry_after


class Store:
    def __init__(self, directory, *, interval=30, hourly=5, daily=20, global_daily=1000, capacity=10000):
        directory = Path(directory)
        directory.mkdir(parents=True, exist_ok=True)
        self.path = directory / 'suggestions.sqlite3'
        secret = directory / 'abuse.key'
        try:
            fd = os.open(secret, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError:
            pass
        else:
            with os.fdopen(fd, 'wb') as stream:
                stream.write(secrets.token_bytes(32))
        self.secret = secret.read_bytes()
        if len(self.secret) != 32:
            raise ValueError('Invalid abuse key')
        self.interval, self.hourly, self.daily = interval, hourly, daily
        self.global_daily, self.capacity = global_daily, capacity
        with self.connect() as db:
            db.executescript('''
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS suggestions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    request_id TEXT NOT NULL UNIQUE,
                    nickname TEXT NOT NULL,
                    body TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    created_epoch INTEGER NOT NULL,
                    deleted INTEGER NOT NULL DEFAULT 0
                );
                CREATE INDEX IF NOT EXISTS suggestions_created ON suggestions(created_epoch);
                CREATE TABLE IF NOT EXISTS abuse (ip_hash TEXT NOT NULL, created_epoch INTEGER NOT NULL);
                CREATE INDEX IF NOT EXISTS abuse_key_time ON abuse(ip_hash, created_epoch);
                CREATE INDEX IF NOT EXISTS abuse_time ON abuse(created_epoch);
            ''')
        os.chmod(self.path, 0o600)
        self.cleanup()

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=5)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA busy_timeout=5000')
        try:
            yield db
            db.commit()
        except Exception:
            db.rollback()
            raise
        finally:
            db.close()

    def cleanup(self):
        with self.connect() as db:
            db.execute('DELETE FROM abuse WHERE created_epoch <= ?', (int(time.time()) - 86400,))

    def token(self, address, now):
        day = dt.datetime.fromtimestamp(now, dt.timezone.utc).date().isoformat()
        return hmac.new(self.secret, (day + '|' + address).encode(), hashlib.sha256).hexdigest()

    @staticmethod
    def public(row):
        return {key: row[key] for key in ('id', 'nickname', 'body', 'created_at')}

    def list(self, before=None, limit=20):
        with self.connect() as db:
            rows = db.execute('SELECT * FROM suggestions WHERE deleted=0 AND id < ? ORDER BY id DESC LIMIT ?', (before or 9223372036854775807, limit + 1)).fetchall()
        has_more = len(rows) > limit
        items = [self.public(row) for row in rows[:limit]]
        return {'items': items, 'has_more': has_more, 'next_before': items[-1]['id'] if has_more else None}

    def create(self, request_id, nickname, body, address):
        now = int(time.time())
        fingerprint = self.token(address, now)
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            prior = db.execute('SELECT * FROM suggestions WHERE request_id=?', (request_id,)).fetchone()
            if prior:
                if prior['deleted'] or prior['nickname'] != nickname or prior['body'] != body:
                    raise APIError(409, 'request_conflict', '这次提交标识已经使用，请重新提交。')
                return self.public(prior), False
            db.execute('DELETE FROM abuse WHERE created_epoch <= ?', (now - 86400,))
            stamps = [row[0] for row in db.execute('SELECT created_epoch FROM abuse WHERE ip_hash IN (?,?) ORDER BY created_epoch', (fingerprint, self.token(address, now - 86400)))]
            if stamps and now - stamps[-1] < self.interval:
                raise APIError(429, 'rate_limited', '提交得有些频繁，请稍后再试。', self.interval - (now - stamps[-1]))
            hourly_stamps = [stamp for stamp in stamps if stamp > now - 3600]
            if len(hourly_stamps) >= self.hourly or len(stamps) >= self.daily:
                wait = hourly_stamps[0] + 3600 - now if len(hourly_stamps) >= self.hourly else stamps[0] + 86400 - now
                raise APIError(429, 'rate_limited', '本时段提交次数已达上限，请稍后再来。', max(1, wait))
            if db.execute('SELECT count(*) FROM suggestions').fetchone()[0] >= self.capacity:
                raise APIError(503, 'board_full', '留言区暂时无法接收新建议，请稍后再来。', 3600)
            if db.execute('SELECT count(*) FROM suggestions WHERE created_epoch > ?', (now - 86400,)).fetchone()[0] >= self.global_daily:
                raise APIError(429, 'board_busy', '今天的建议已较多，请稍后再来。', 3600)
            created_at = dt.datetime.fromtimestamp(now, dt.timezone.utc).isoformat().replace('+00:00', 'Z')
            cursor = db.execute('INSERT INTO suggestions(request_id,nickname,body,created_at,created_epoch) VALUES (?,?,?,?,?)', (request_id, nickname, body, created_at, now))
            db.execute('INSERT INTO abuse VALUES (?,?)', (fingerprint, now))
            row = db.execute('SELECT * FROM suggestions WHERE id=?', (cursor.lastrowid,)).fetchone()
        return self.public(row), True


class BoardServer(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 32

    def __init__(self, address, store, origin, trusted_proxies=()):
        self.store, self.origin = store, origin.rstrip('/')
        self.allowed_host = urlsplit(self.origin).netloc
        self.trusted_proxies = {str(ipaddress.ip_address(x)) for x in trusted_proxies}
        self.slots = threading.BoundedSemaphore(16)
        self.stopping = threading.Event()
        super().__init__(address, Handler)
        self.cleaner = threading.Thread(target=self.clean_loop, daemon=True)
        self.cleaner.start()

    def clean_loop(self):
        while not self.stopping.wait(300):
            try:
                self.store.cleanup()
            except sqlite3.Error:
                pass  # A busy transaction can wait for the next maintenance interval.

    def server_close(self):
        self.stopping.set()
        super().server_close()

    def handle_error(self, request, client_address):
        pass  # Connection failures must not print the client address or request details.

    def process_request(self, request, client_address):
        if not self.slots.acquire(blocking=False):
            try:
                request.sendall(b'HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')
            finally:
                self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self.slots.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.slots.release()


class Handler(BaseHTTPRequestHandler):
    server_version = 'SuggestionBoard'
    sys_version = ''

    def setup(self):
        super().setup()
        self.connection.settimeout(10)

    def log_message(self, *_):
        pass  # Never write IP addresses or posted text into access logs.

    def reply(self, status, value, retry_after=None):
        raw = json.dumps(value, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(raw)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        if retry_after is not None:
            self.send_header('Retry-After', str(retry_after))
        self.end_headers()
        self.wfile.write(raw)

    def address(self):
        address = str(ipaddress.ip_address(self.client_address[0]))
        if address in self.server.trusted_proxies:
            forwarded = self.headers.get('X-Forwarded-For', '')
            if ',' in forwarded:
                raise APIError(400, 'invalid_proxy', '请求来源格式不正确。')
            try:
                return str(ipaddress.ip_address(forwarded))
            except ValueError:
                raise APIError(400, 'invalid_proxy', '请求来源格式不正确。')
        return address

    def dispatch(self, method):
        path = urlsplit(self.path)
        if path.path == '/health' and method == 'GET':
            self.reply(200, {'ok': True})
            return
        if self.headers.get_all('Host') != [self.server.allowed_host]:
            raise APIError(403, 'invalid_host', '请求地址不正确。')
        if path.path != '/api/suggestions':
            raise APIError(404, 'not_found', '页面不存在。')
        if method == 'GET':
            query = parse_qs(path.query, keep_blank_values=True, max_num_fields=4)
            if set(query) - {'before', 'limit'} or any(len(value) != 1 for value in query.values()):
                raise APIError(400, 'invalid_page', '分页参数不正确。')
            def integer(key, default, maximum):
                value = query.get(key, [str(default)])[0]
                if not value.isascii() or not value.isdigit() or not 1 <= int(value) <= maximum:
                    raise APIError(400, 'invalid_page', '分页参数不正确。')
                return int(value)
            limit = integer('limit', 20, 50)
            before = integer('before', 9223372036854775807, 9223372036854775807)
            self.reply(200, self.server.store.list(before, limit))
            return
        if self.headers.get_all('Origin') != [self.server.origin]:
            raise APIError(403, 'invalid_origin', '请从本站页面提交建议。')
        if path.query or self.headers.get('Transfer-Encoding') or len(self.headers.get_all('Content-Length') or []) != 1:
            raise APIError(400, 'invalid_request', '请求格式不正确。')
        if self.headers.get_content_type() != 'application/json':
            raise APIError(415, 'invalid_type', '请使用网页表单提交建议。')
        try:
            length = int(self.headers['Content-Length'])
        except ValueError:
            raise APIError(400, 'invalid_length', '请求长度不正确。')
        if not 1 <= length <= BODY_LIMIT:
            raise APIError(413, 'too_large', '建议内容过长，请缩短后提交。')
        raw = self.rfile.read(length)
        if len(raw) != length:
            raise APIError(400, 'invalid_request', '请求未完整收到，请重试。')
        try:
            value = json.loads(raw)
        except (ValueError, UnicodeDecodeError):
            raise APIError(400, 'invalid_json', '请求格式不正确。')
        if not isinstance(value, dict) or set(value) - {'nickname', 'body', 'website', 'request_id'}:
            raise APIError(400, 'invalid_fields', '请求字段不正确。')
        nickname, body = value.get('nickname', ''), value.get('body')
        if value.get('website', '') != '':
            raise APIError(400, 'invalid_form', '表单未通过校验，请重试。')
        if not isinstance(nickname, str) or not isinstance(body, str) or CONTROL.search(nickname + body):
            raise APIError(400, 'invalid_text', '请填写纯文字建议。')
        nickname, body = ' '.join(nickname.split()), body.strip().replace('\r\n', '\n').replace('\r', '\n')
        if len(nickname) > 24 or not 1 <= len(body) <= 2000:
            raise APIError(400, 'invalid_text', '昵称最多24字，建议内容为1–2000字。')
        nickname = nickname or '匿名玩家'
        try:
            request_id = str(uuid.UUID(value.get('request_id', '')))
        except (ValueError, AttributeError, TypeError):
            raise APIError(400, 'invalid_id', '提交标识不正确，请刷新页面后重试。')
        item, created = self.server.store.create(request_id, nickname, body, self.address())
        self.reply(201 if created else 200, {'item': item})

    def handle_api(self, method):
        try:
            self.dispatch(method)
        except APIError as error:
            self.reply(error.status, {'error': {'code': error.code, 'message': error.message}}, error.retry_after)
        except (ValueError, OverflowError):
            self.reply(400, {'error': {'code': 'invalid_request', 'message': '请求格式不正确。'}})
        except (sqlite3.Error, OSError):
            self.reply(503, {'error': {'code': 'unavailable', 'message': '暂时无法处理，请稍后重试。'}}, 30)

    def do_GET(self):
        self.handle_api('GET')

    def do_POST(self):
        self.handle_api('POST')

    def do_OPTIONS(self):
        self.reply(405, {'error': {'code': 'method_not_allowed', 'message': '不支持跨站提交。'}})


if __name__ == '__main__':
    os.umask(0o077)
    store = Store(os.environ.get('DATA_DIR', '/data'),
                  interval=int(os.environ.get('POST_INTERVAL', '30')),
                  hourly=int(os.environ.get('POST_HOURLY', '5')),
                  daily=int(os.environ.get('POST_DAILY', '20')),
                  global_daily=int(os.environ.get('POST_GLOBAL_DAILY', '1000')),
                  capacity=int(os.environ.get('POST_CAPACITY', '10000')))
    server = BoardServer(('0.0.0.0', int(os.environ.get('PORT', '8081'))), store,
                         os.environ.get('ALLOWED_ORIGIN', 'https://afabiaoge.xyz'),
                         filter(None, os.environ.get('TRUSTED_PROXY_IPS', '').split(',')))
    print('Suggestion board ready', flush=True)
    try:
        server.serve_forever()
    finally:
        server.server_close()
