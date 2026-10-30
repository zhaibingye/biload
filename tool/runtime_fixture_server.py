"""Loopback-only deterministic Range server. Serves original, generated samples."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
import struct
import time
from urllib.parse import urlparse

parser = argparse.ArgumentParser()
parser.add_argument('--port', type=int, default=18765)
parser.add_argument('--port-file')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent / 'test/fixtures/media'
files = {path.name: path.read_bytes() for path in root.iterdir() if path.is_file() and path.suffix != '.md'}
padding_size = 4 * 1024 * 1024
files['slow.mp4'] = files['avc.mp4'] + struct.pack('>I4s', padding_size, b'free') + bytes(padding_size - 8)
range_requests = []

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_HEAD(self):
        self.respond(False)

    def do_GET(self):
        self.respond(True)

    def do_POST(self):
        size = int(self.headers.get('Content-Length', '0'))
        body = self.rfile.read(size)
        valid = urlparse(self.path).path == '/login/finish' and body == b'value=fixture'
        self.send_response(200 if valid else 400)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Set-Cookie', 'biload_fixture=fixture; HttpOnly; Path=/')
        self.end_headers()
        self.wfile.write(b'<script>window.localStorage.setItem("biload_fixture", "ready")</script>done')

    def respond(self, body):
        path = urlparse(self.path).path.lstrip('/')
        if path == 'manifest.json':
            data = json.dumps({'files': {name: len(data) for name, data in files.items()},
                               'rangeRequests': range_requests}).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            if body:
                self.wfile.write(data)
            return
        if path == 'login':
            data = b'<form action="/login/finish" method="post"><input name="value" value="fixture"></form><script>document.forms[0].submit()</script>'
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            if body:
                self.wfile.write(data)
            return
        if path not in files:
            self.send_error(404)
            return
        data = files[path]
        start, end = 0, len(data) - 1
        match = re.fullmatch(r'bytes=(\d+)-(\d*)', self.headers.get('Range', ''))
        if match:
            start = int(match[1])
            if match[2]:
                end = min(int(match[2]), end)
            if start > end:
                self.send_response(416)
                self.send_header('Content-Range', f'bytes */{len(data)}')
                self.end_headers()
                return
            range_requests.append({'file': path, 'start': start})
        self.send_response(206 if match else 200)
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Content-Type', 'application/octet-stream')
        self.send_header('Content-Length', str(end - start + 1))
        if match:
            self.send_header('Content-Range', f'bytes {start}-{end}/{len(data)}')
        self.end_headers()
        if not body:
            return
        try:
            for offset in range(start, end + 1, 16384):
                self.wfile.write(data[offset:min(offset + 16384, end + 1)])
                self.wfile.flush()
                if path == 'slow.mp4':
                    time.sleep(0.025)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass

server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
if args.port_file:
    Path(args.port_file).write_text(str(server.server_port), encoding='utf-8')
print(f'Fixture server on loopback port {server.server_port}', flush=True)
server.serve_forever()
