"""Offline loopback-only safety checks; no GPU/image/cluster/network download."""
import contextlib
import http.client
import importlib.util
import io
import json
from pathlib import Path
import select
import socket
import sys
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.dont_write_bytecode = True
SOURCE = Path(__file__).resolve().parents[3] / 'containers/local-inference/benchmark_proxy.py'
SPEC = importlib.util.spec_from_file_location('benchmark_proxy', SOURCE)
proxy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(proxy)
KEY = 'synthetic-unit-test-credential-' + 'x' * 32
EVENT = b'data: {"delta":{"reasoning_content":"abc","content":"visible"}}\n\n'


def eventually(predicate, timeout=1):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.005)
    raise AssertionError('bounded local test condition not reached')


class Stub(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *args):
        pass

    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Length', '2')
        self.end_headers()
        self.wfile.write(b'{}')

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        self.server.seen.append(body.get('name', 'anonymous'))
        self.server.authorizations.append(self.headers.get('Authorization'))
        stream = body.get('stream', False)
        try:
            if stream:
                self.send_response(200)
                self.send_header('Content-Type', 'text/event-stream')
                self.end_headers()
                self.wfile.write(EVENT)
                self.wfile.flush()
            deadline = time.monotonic() + body.get('delay', 0)
            while time.monotonic() < deadline:
                readable, _, _ = select.select([self.connection], [], [], 0.01)
                if readable and self.connection.recv(1, socket.MSG_PEEK) == b'':
                    self.server.cancelled.set()
                    self.close_connection = True
                    return
            if not stream:
                self.send_response(200)
                self.send_header('Content-Length', '2')
                self.end_headers()
                self.wfile.write(b'{}')
            else:
                self.wfile.write(b'data: [DONE]\n\n')
                self.wfile.flush()
                self.close_connection = True
        except OSError:
            self.server.cancelled.set()
            self.close_connection = True


class ProxyTests(unittest.TestCase):
    def setUp(self):
        self.backend = ThreadingHTTPServer(('127.0.0.1', 0), Stub)
        self.backend.daemon_threads = True
        self.backend.seen = []
        self.backend.authorizations = []
        self.backend.cancelled = threading.Event()
        self.backend.handle_error = lambda *_: None
        self.servers = [self.backend]
        self._serve(self.backend)
        self.server = self.new_proxy()

    def _serve(self, server):
        threading.Thread(target=server.serve_forever, kwargs={'poll_interval': 0.01}, daemon=True).start()

    def new_proxy(self, active=2, queue=1):
        server = proxy.ProxyServer(('127.0.0.1', 0), KEY, self.backend.server_port, queue, active)
        self.servers.append(server)
        self._serve(server)
        return server

    def tearDown(self):
        for server in reversed(self.servers):
            server.shutdown()
            server.server_close()

    def request(self, body=None, path='/v1/chat/completions', auth=True, method='POST', server=None):
        server = server or self.server
        connection = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=3)
        headers = {'Authorization': 'Bearer ' + KEY} if auth else {}
        connection.request(method, path, json.dumps(body or {}) if method == 'POST' else None, headers)
        response = connection.getresponse()
        result = (response.status, response.read())
        connection.close()
        return result

    def streaming(self, server=None):
        server = server or self.server
        connection = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=2)
        connection.request('POST', '/v1/chat/completions', json.dumps({'delay': 1, 'stream': True}),
                           {'Authorization': 'Bearer ' + KEY})
        transport = connection.sock  # getresponse() can detach a Connection:close socket.
        response = connection.getresponse()
        return connection, transport, response

    def test_authentication_all_routes_and_public_health(self):
        for path, method in [('/v1/chat/completions', 'POST'), ('/tokenize', 'POST'), ('/metrics', 'GET')]:
            self.assertEqual(self.request(path=path, method=method, auth=False)[0], 401)
        self.assertEqual(self.request(path='/health', method='GET', auth=False)[0], 200)
        self.assertEqual(self.request()[0], 200)
        self.assertEqual(self.backend.authorizations, ['Bearer ' + KEY])

    def test_one_active_two_fifo_and_fourth_busy(self):
        results = {}
        def send(name, delay):
            results[name] = self.request({'name': name, 'delay': delay})[0]
        active = threading.Thread(target=send, args=('active', 0.3))
        active.start()
        eventually(lambda: self.backend.seen == ['active'])
        queued = []
        for name in ('queue1', 'queue2'):
            thread = threading.Thread(target=send, args=(name, 0.01))
            thread.start()
            queued.append(thread)
            eventually(lambda: len(self.server.admission.waiters) == len(queued))
        self.assertEqual(self.request({'name': 'fourth'})[0], 503)
        active.join(2)
        for thread in queued:
            thread.join(2)
        self.assertEqual(results, {'active': 200, 'queue1': 200, 'queue2': 200})
        self.assertEqual(self.backend.seen, ['active', 'queue1', 'queue2'])

    def test_thirty_second_queue_deadline_with_fake_clock(self):
        now = [0.0]
        admission = proxy.Admission(30, clock=lambda: now[0])
        self.assertIsNone(admission.acquire())
        result = []
        thread = threading.Thread(target=lambda: result.append(admission.acquire()))
        thread.start()
        eventually(lambda: len(admission.waiters) == 1)
        with admission.condition:
            now[0] = 30.01
            admission.condition.notify_all()
        thread.join(1)
        self.assertEqual(result, ['queue_deadline'])

    def test_active_deadline_cancels_backend_transport(self):
        server = self.new_proxy(active=0.15)
        started = time.monotonic()
        self.assertEqual(self.request({'delay': 1}, server=server)[0], 504)
        self.assertLess(time.monotonic() - started, 0.5)
        self.assertTrue(self.backend.cancelled.wait(0.5))

    def test_sse_first_chunk_unmodified_and_disconnect_cancel(self):
        connection, transport, response = self.streaming()
        started = time.monotonic()
        self.assertEqual(response.read1(4096), EVENT)
        self.assertLess(time.monotonic() - started, 0.3)
        transport.shutdown(socket.SHUT_RDWR)
        response.close()
        connection.close()
        self.assertTrue(self.backend.cancelled.wait(0.5))

    def test_queued_disconnect_removes_waiter_without_backend_work(self):
        active = threading.Thread(target=lambda: self.request({'name': 'active', 'delay': 0.4}))
        active.start()
        eventually(lambda: self.backend.seen == ['active'])
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=2)
        connection.request('POST', '/tokenize', json.dumps({'name': 'cancelled'}), {'Authorization': 'Bearer ' + KEY})
        eventually(lambda: len(self.server.admission.waiters) == 1)
        connection.sock.shutdown(socket.SHUT_RDWR)
        connection.close()
        eventually(lambda: not self.server.admission.waiters)
        active.join(1)
        self.assertEqual(self.backend.seen, ['active'])

    def test_trailing_bytes_cannot_hide_disconnect(self):
        connection, transport, response = self.streaming()
        self.assertEqual(response.read1(4096), EVENT)
        transport.sendall(b'extra bytes forbidden after request')
        transport.shutdown(socket.SHUT_RDWR)
        response.close()
        connection.close()
        self.assertTrue(self.backend.cancelled.wait(0.5))

    def test_body_limit_and_headers_limit_without_secret_logging(self):
        output = io.StringIO()
        with contextlib.redirect_stderr(output), contextlib.redirect_stdout(output):
            connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=2)
            connection.putrequest('POST', '/tokenize')
            connection.putheader('Authorization', 'Bearer ' + KEY)
            connection.putheader('Content-Length', str(proxy.MAX_BODY + 1))
            connection.endheaders()
            response = connection.getresponse()
            self.assertEqual(response.status, 413)
            response.read()
            connection.close()
            transport = socket.create_connection(('127.0.0.1', self.server.server_port), timeout=2)
            transport.sendall(b'GET /health HTTP/1.1\r\nHost: localhost\r\n' +
                              b'X-Test: data\r\n' * 70 + b'\r\n')
            self.assertIn(b'431', transport.recv(4096).split(b'\r\n')[0])
            transport.close()
            time.sleep(0.05)
        self.assertEqual(output.getvalue(), '')
        self.assertEqual(self.backend.seen, [])


if __name__ == '__main__':
    unittest.main()
