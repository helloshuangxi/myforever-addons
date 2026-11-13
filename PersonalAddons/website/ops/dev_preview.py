#!/usr/bin/env python3
"""Loopback-only website preview with an isolated, temporary suggestion database."""
from functools import partial
from http.client import HTTPConnection
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse
import json
import sys
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'community'))
from server import BoardServer, Store


class Preview(SimpleHTTPRequestHandler):
    def route_api(self):
        if self.path.split('?', 1)[0] != '/api/suggestions':
            return False
        try:
            length = int(self.headers.get('Content-Length', '0'))
        except ValueError:
            self.send_error(400)
            return True
        if length < 0 or length > 16384:
            self.send_error(413)
            return True
        body = self.rfile.read(length) if length else None
        connection = HTTPConnection('127.0.0.1', self.server.api_port, timeout=10)
        headers = {'Host': self.headers.get('Host', ''), 'X-Forwarded-For': '127.0.0.1'}
        for key in ('Content-Type', 'Origin', 'Sec-Fetch-Site'):
            if key in self.headers:
                headers[key] = self.headers[key]
        try:
            connection.request(self.command, self.path, body=body, headers=headers)
            response = connection.getresponse()
            payload = response.read()
            self.send_response(response.status)
            for name, value in response.getheaders():
                if name.lower() in ('content-type', 'cache-control', 'retry-after', 'x-content-type-options'):
                    self.send_header(name, value)
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        finally:
            connection.close()
        return True

    def do_GET(self):
        if self.server.enable_donation and self.path.split('?', 1)[0] == '/community-config.json':
            config = json.loads((ROOT / 'public/community-config.json').read_text())
            config.setdefault('donation', {})['enabled'] = True
            payload = json.dumps(config, ensure_ascii=False).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        if not self.route_api():
            super().do_GET()

    def do_POST(self):
        if not self.route_api():
            self.send_error(404)

    def log_message(self, *_):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8766)
    parser.add_argument('--enable-donation', action='store_true', help='Preview the draft donation flow without changing public configuration')
    args = parser.parse_args()
    origin = f'http://127.0.0.1:{args.port}'
    with tempfile.TemporaryDirectory(prefix='myforeverchat-preview-') as data:
        api = BoardServer(('127.0.0.1', 0), Store(data), origin, ('127.0.0.1',))
        threading.Thread(target=api.serve_forever, daemon=True).start()
        web = ThreadingHTTPServer(('127.0.0.1', args.port), partial(Preview, directory=str(ROOT / 'public')))
        web.api_port = api.server_port
        web.enable_donation = args.enable_donation
        print(f'{origin} (temporary suggestions; never production data)', flush=True)
        try:
            web.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            web.server_close()
            api.shutdown()
            api.server_close()


if __name__ == '__main__':
    main()
