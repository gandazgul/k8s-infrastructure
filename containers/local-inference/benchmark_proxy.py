#!/usr/bin/env python3
"""Benchmark-only admission boundary and scoped llama-server supervisor.

No request, response, header, credential, or exception text is logged. Bytes of
successful responses (including SSE reasoning fields) are relayed unchanged.
Transport cancellation is not proof of GPU cancellation: verify the pinned
llama runtime actually releases its slot before accepting benchmark results.
"""
import argparse
from collections import deque
import hmac
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import select
import signal
import socket
import subprocess
import sys
import threading
import time

MAX_BODY = 16 * 1024 * 1024
ROUTES = {
    '/health', '/v1/health', '/metrics', '/props', '/models', '/v1/models',
    '/v1/chat/completions', '/chat/completions', '/completion',
    '/completions', '/v1/completions', '/tokenize', '/detokenize', '/apply-template',
}


class Admission:
    def __init__(self, queue_seconds=30, clock=time.monotonic):
        self.condition = threading.Condition()
        self.waiters = deque()
        self.active = False
        self.queue_seconds = queue_seconds
        self.clock = clock

    def acquire(self, cancelled=lambda: False):
        with self.condition:
            if cancelled():
                return 'client_disconnected'
            if not self.active and not self.waiters:
                self.active = True
                return None
            if len(self.waiters) >= 2:
                return 'queue_full'
            token = object()
            self.waiters.append(token)
            deadline = self.clock() + self.queue_seconds
            while True:
                if cancelled():
                    self.waiters.remove(token)
                    self.condition.notify_all()
                    return 'client_disconnected'
                remaining = deadline - self.clock()
                if remaining <= 0:
                    self.waiters.remove(token)
                    self.condition.notify_all()
                    return 'queue_deadline'
                if not self.active and self.waiters[0] is token:
                    self.waiters.popleft()
                    self.active = True
                    return None
                self.condition.wait(timeout=min(remaining, 0.1))

    def release(self):
        with self.condition:
            self.active = False
            self.condition.notify_all()


class BoundedHeaders:
    def __init__(self, stream):
        self.stream = stream
        self.bytes = 0
        self.lines = 0

    def readline(self, limit=-1):
        line = self.stream.readline(min(limit, 8193) if limit >= 0 else 8193)
        self.bytes += len(line)
        self.lines += 1
        if len(line) > 8192 or self.bytes > 16384 or self.lines > 65:
            raise http.client.HTTPException('bounded header limit')
        return line


class ProxyServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address, key, backend_port=8081, queue_seconds=30, active_seconds=120):
        self.key = key
        self.backend_port = backend_port
        self.active_seconds = active_seconds
        self.admission = Admission(queue_seconds)
        self.handler_slots = threading.BoundedSemaphore(32)
        super().__init__(address, ProxyHandler)

    def process_request(self, request, address):
        if not self.handler_slots.acquire(blocking=False):
            try:
                request.settimeout(1)
                request.sendall(b'HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')
            finally:
                self.shutdown_request(request)
            return
        try:
            super().process_request(request, address)
        except BaseException:
            self.handler_slots.release()
            raise

    def process_request_thread(self, request, address):
        try:
            super().process_request_thread(request, address)
        finally:
            self.handler_slots.release()

    def handle_error(self, request, address):
        # Never let socketserver emit a traceback containing request state.
        pass


class ProxyHandler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    server_version = 'BenchmarkAdmission'
    sys_version = ''
    # No read-ahead: a trailing/pipelined byte must remain visible to the
    # disconnect watcher after the one allowed request body is consumed.
    rbufsize = 0

    def setup(self):
        self.request.settimeout(5)
        super().setup()

    def log_message(self, *args):
        pass

    def parse_request(self):
        if len(self.raw_requestline) > 8192:
            self.send_error(414)
            return False
        original = self.rfile
        self.rfile = BoundedHeaders(original)
        try:
            return super().parse_request()
        finally:
            self.rfile = original

    def handle_expect_100(self):
        # Do not acknowledge a body before authentication/admission.
        self.send_error(417)
        return False

    def _reply(self, status, code):
        body = json.dumps({'error': {'type': 'benchmark_proxy', 'code': code}}).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Connection', 'close')
        self.end_headers()
        self.wfile.write(body)
        self.close_connection = True

    def do_GET(self):
        self._proxy()

    def do_POST(self):
        self._proxy()

    def _proxy(self):
        self.close_connection = True
        path = self.path
        health = self.command == 'GET' and path in ('/health', '/v1/health')
        authorizations = self.headers.get_all('Authorization', [])
        authorized = (len(authorizations) == 1 and
                      hmac.compare_digest(authorizations[0].encode(),
                                          ('Bearer ' + self.server.key).encode()))
        if not health and not authorized:
            self._reply(401, 'authentication_required')
            return
        if path not in ROUTES or (self.command == 'POST' and path in ('/health', '/v1/health', '/metrics', '/models', '/v1/models', '/props')):
            self._reply(404, 'route_not_allowed')
            return
        lengths = self.headers.get_all('Content-Length', [])
        if (self.headers.get_all('Transfer-Encoding') or len(lengths) > 1 or
                (lengths and not lengths[0].isascii()) or
                (lengths and not lengths[0].isdigit())):
            self._reply(400, 'invalid_body_framing')
            return
        size = int(lengths[0]) if lengths else 0
        if size > MAX_BODY:
            self._reply(413, 'body_limit')
            return
        if self.command == 'GET' and size:
            self._reply(400, 'unexpected_body')
            return
        expired = threading.Event()
        def expire_body():
            expired.set()
            try:
                self.connection.shutdown(socket.SHUT_RD)
            except OSError:
                pass
        timer = threading.Timer(5, expire_body)
        timer.daemon = True
        timer.start()
        try:
            body = bytearray()
            while len(body) < size:
                block = self.rfile.read(min(65536, size - len(body)))
                if not block:
                    raise ValueError('incomplete body')
                body.extend(block)
            if expired.is_set():
                raise TimeoutError()
        except Exception:
            self._reply(408 if expired.is_set() else 400, 'body_read_failed')
            return
        finally:
            timer.cancel()

        def client_cancelled():
            try:
                readable, _, _ = select.select([self.connection], [], [], 0)
                # EOF cancels; extra data is forbidden because there is no
                # keepalive/pipelining protocol, and cannot hide a later EOF.
                return bool(readable)
            except OSError:
                return True

        admitted = self.command == 'POST'
        if admitted:
            rejection = self.server.admission.acquire(client_cancelled)
            if rejection:
                if rejection != 'client_disconnected':
                    self._reply(503 if rejection == 'queue_full' else 504, rejection)
                return
        try:
            if not client_cancelled():
                self._relay(path, body, 2 if health else self.server.active_seconds)
        finally:
            if admitted:
                self.server.admission.release()

    def _relay(self, path, body, duration):
        deadline = time.monotonic() + duration
        stopped = threading.Event()
        timed_out = threading.Event()
        disconnected = threading.Event()
        headers_sent = threading.Event()
        connection = http.client.HTTPConnection('127.0.0.1', self.server.backend_port, timeout=duration)
        backend_socket = []

        def abort_backend():
            if backend_socket:
                try:
                    backend_socket[0].shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
            connection.close()

        def watch():
            while not stopped.wait(0.025):
                if time.monotonic() >= deadline:
                    timed_out.set()
                    abort_backend()
                    try:
                        self.connection.shutdown(socket.SHUT_RDWR if headers_sent.is_set() else socket.SHUT_RD)
                    except OSError:
                        pass
                    return
                try:
                    readable, _, _ = select.select([self.connection], [], [], 0)
                    if readable:
                        disconnected.set()
                        abort_backend()
                        return
                except OSError:
                    disconnected.set()
                    abort_backend()
                    return

        watcher = threading.Thread(target=watch, daemon=True)
        watcher.start()
        try:
            self.connection.settimeout(max(0.001, deadline - time.monotonic()))
            if timed_out.is_set() or disconnected.is_set():
                raise TimeoutError()
            connection.timeout = max(0.001, deadline - time.monotonic())
            connection.connect()
            backend_socket.append(connection.sock)
            connection.request(self.command, path, body=body, headers={
                'Authorization': 'Bearer ' + self.server.key,
                'Content-Type': 'application/json', 'Connection': 'close',
            })
            backend_socket[0].settimeout(max(0.001, deadline - time.monotonic()))
            response = connection.getresponse()
            if timed_out.is_set() or disconnected.is_set():
                raise TimeoutError()
            self.send_response(response.status)
            # Never forward hop-by-hop, cookies, redirects or arbitrary headers.
            self.send_header('Content-Type', response.getheader('Content-Type', 'application/json'))
            self.send_header('Connection', 'close')
            self.end_headers()
            headers_sent.set()
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or timed_out.is_set() or disconnected.is_set():
                    raise TimeoutError()
                backend_socket[0].settimeout(remaining)
                chunk = response.read1(4096)
                if not chunk:
                    break
                self.connection.settimeout(max(0.001, deadline - time.monotonic()))
                self.wfile.write(chunk)
                self.wfile.flush()
        except Exception:
            if not headers_sent.is_set() and not disconnected.is_set():
                try:
                    self._reply(504 if timed_out.is_set() or time.monotonic() >= deadline else 502,
                                'active_deadline' if timed_out.is_set() or time.monotonic() >= deadline else 'backend_unavailable')
                except OSError:
                    pass
        finally:
            stopped.set()
            abort_backend()
            watcher.join(timeout=0.1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--api-key-file', type=Path, required=True)
    parser.add_argument('--listen-port', type=int, default=8080)
    parser.add_argument('--backend-port', type=int, default=8081)
    parser.add_argument('--queue-seconds', type=float, default=30)
    parser.add_argument('--active-seconds', type=float, default=120)
    parser.add_argument('backend', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not 0 < args.queue_seconds <= 30 or not 0 < args.active_seconds <= 120:
        raise ValueError('deadline outside benchmark limits')
    key = args.api_key_file.read_text().strip()
    if len(key) < 32 or not key.isascii() or any(character.isspace() for character in key):
        raise ValueError('invalid benchmark credential')
    command = args.backend[1:] if args.backend[:1] == ['--'] else args.backend
    if not command or command[0] != '/opt/local-inference/bin/llama-server':
        raise ValueError('explicit benchmark backend required')
    server = ProxyServer(('0.0.0.0', args.listen_port), key, args.backend_port,
                         args.queue_seconds, args.active_seconds)
    stopped = threading.Event()
    for signum in (signal.SIGTERM, signal.SIGINT):
        signal.signal(signum, lambda *_: stopped.set())
    child = subprocess.Popen(command, start_new_session=True,
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL)
    serving = threading.Thread(target=server.serve_forever, kwargs={'poll_interval': 0.1}, daemon=True)
    serving.start()
    result = 0
    try:
        while not stopped.wait(0.1):
            if child.poll() is not None:
                result = 1
                break
    finally:
        server.shutdown()
        server.server_close()
        if child.poll() is None:
            os.killpg(child.pid, signal.SIGTERM)
            try:
                child.wait(timeout=15)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait(timeout=5)
        serving.join(timeout=1)
    return result


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception:
        print('{"status":"stopped","stage":"benchmark_proxy"}', file=sys.stderr)
        sys.exit(1)
