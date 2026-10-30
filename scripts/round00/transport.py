"""Runner-only DNS and verified TLS bridge to the unchanged local Laravel API.

The APK retains its real compiled HTTPS hostname. Only this disposable Android
device resolves that name to the runner. TLS verification remains enabled using
a temporary test CA. All app API writes and credentials are rejected here.
"""
from pathlib import Path
import datetime
import http.client
import http.server
import json
import os
import re
import socket
import socketserver
import ssl
import struct
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'round00-out'
HOST = 'real-estate-uat-api-frankfurt.onrender.com'
assert os.environ.get('GITHUB_ACTIONS') == 'true'
assert os.environ.get('AQER_ROUND00_DISPOSABLE') == '20261030'
assert os.environ.get('DB_DATABASE') == 'aqer_round00'
LOCK = threading.Lock()

def record(file, data):
    data['utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    data['monotonic_ns'] = time.monotonic_ns()
    with LOCK, (OUT / file).open('a') as f:
        f.write(json.dumps(data) + '\n')

class DNS(socketserver.BaseRequestHandler):
    def handle(self):
        packet, channel = self.request
        try:
            pos, labels = 12, []
            while packet[pos]:
                length = packet[pos]; pos += 1
                labels.append(packet[pos:pos+length].decode('ascii')); pos += length
            pos += 1
            kind, cls = struct.unpack('!HH', packet[pos:pos+4]); end = pos + 4
            hostname = '.'.join(labels).lower()
            answers = []
            if cls == 1 and kind in (1, 28):
                if hostname == HOST:
                    if kind == 1: answers = ['10.0.2.2']
                else:
                    family = socket.AF_INET if kind == 1 else socket.AF_INET6
                    try:
                        answers = list(dict.fromkeys(x[4][0] for x in socket.getaddrinfo(hostname, None, family, socket.SOCK_STREAM)))[:4]
                    except socket.gaierror:
                        pass
            wire = packet[:2] + struct.pack('!HHHHH', 0x8180, 1, len(answers), 0, 0) + packet[12:end]
            for address in answers:
                value = socket.inet_pton(socket.AF_INET if kind == 1 else socket.AF_INET6, address)
                wire += b'\xc0\x0c' + struct.pack('!HHIH', kind, 1, 30, len(value)) + value
            channel.sendto(wire, self.client_address)
            record('dns.jsonl', {'host':hostname, 'type':kind, 'answers':len(answers), 'api_isolated':hostname == HOST})
        except Exception as error:
            record('transport-errors.jsonl', {'stage':'dns', 'error':type(error).__name__})

class API(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, *args):
        pass
    def do_POST(self):
        if re.fullmatch(r'/api/properties/(?:[1-9]|[12][0-9]|3[0-6])/view',self.path):
            self.forward(False)
        else:
            self.reject()
    def do_PUT(self): self.reject()
    def do_PATCH(self): self.reject()
    def do_DELETE(self): self.reject()
    def reject(self):
        self.send_error(403, 'Round00 is read-only')
        record('http.jsonl', {'method':self.command,'path':self.path,'status':403,'blocked_write':True})
    def do_HEAD(self): self.forward(True)
    def do_GET(self): self.forward(False)
    def forward(self, head):
        started = time.perf_counter()
        if self.headers.get('Host', '').split(':')[0] != HOST or not self.path.startswith('/api/') or self.headers.get('Authorization'):
            self.reject(); return
        response = None
        try:
            connection = http.client.HTTPConnection('127.0.0.1', 8000, timeout=30)
            headers = {k:v for k,v in self.headers.items() if k.lower() in
                {'accept','accept-encoding','content-type','user-agent','if-none-match','range','if-range','x-aqer-diagnostics'}}
            headers['Host'] = HOST
            headers['X-Forwarded-Proto'] = 'https'
            payload = None
            if self.command == 'POST':
                length = int(self.headers.get('Content-Length','0'))
                if length > 4096:
                    self.reject(); return
                payload = self.rfile.read(length)
            connection.request(self.command, self.path, body=payload, headers=headers)
            response = connection.getresponse()
            header_ms = (time.perf_counter() - started)*1000
            body = response.read()
            read_ms = (time.perf_counter() - started)*1000
            self.send_response(response.status)
            for name,value in response.getheaders():
                if name.lower() not in {'connection','transfer-encoding','content-length','date','server'}:
                    self.send_header(name,value)
            self.send_header('Content-Length',str(len(body)))
            self.end_headers()
            if not head: self.wfile.write(body)
            self.wfile.flush()
            record('http.jsonl', {'method':self.command,'path':self.path,'status':response.status,'bytes':len(body),
                'upstream_headers_ms':round(header_ms,2),'upstream_body_complete_ms':round(read_ms,2),
                'total_proxy_ms':round((time.perf_counter()-started)*1000,2),
                'content_type':response.getheader('Content-Type'),'cache_control':response.getheader('Cache-Control'),
                'etag':response.getheader('ETag'),'contract':response.getheader('X-Aqer-Filter-Contract'),
                'server_timing':response.getheader('Server-Timing')})
            connection.close()
        except Exception as error:
            record('transport-errors.jsonl', {'stage':'https','path':self.path,'error':type(error).__name__})
            if response is None:
                self.send_error(502, 'Isolated backend unavailable')

server = http.server.ThreadingHTTPServer(('0.0.0.0',443),API)
tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
tls.load_cert_chain(os.environ['ROUND00_TLS_CERT'],os.environ['ROUND00_TLS_KEY'])
server.socket = tls.wrap_socket(server.socket,server_side=True)
record('environment.jsonl', {'dns':'API hosts override to guest loopback; public map DNS unchanged','tls':'runner:443 via adb reverse','api_host':HOST,'backend':'127.0.0.1:8000',
    'trust':'temporary test CA, no APK verification bypass',
    'writes':'Only view counters for36 synthetic local properties allowed; every other write rejected','database':'aqer_round00'})
server.serve_forever()
