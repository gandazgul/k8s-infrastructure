#!/usr/bin/env python3
"""One-shot bounded rootful Podman build. Never publishes, prunes or runs an image.

Run on the GPU host after review. --run-directory must already exist, empty,
root-owned and private. Failure consumes this attempt: preserve it for review,
do not reset its receipts or retry under the original transfer allowance.
"""
import argparse
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import select
import shutil
import signal
import socket
import socketserver
import stat
import subprocess
import sys
import threading
import time

GIB = 1024 ** 3
STORE = Path('/var/lib/containers/storage')
RX_LIMIT = 25_000_000_000
TRANSFER_RESERVATION = 25_100_000_000
STORE_LIMIT = 20 * GIB
STORE_STOP = 16 * GIB
ROOT_FLOOR = 75 * GIB
ROOT_STOP = 85 * GIB
MEM_FLOOR = 24 * GIB
BUILD_DEADLINE = 3600
LOG_LIMIT = 256 * 1024 ** 2
FILES = tuple('containers/local-inference/' + name for name in
              ('Containerfile', 'cuda-sm75-check.cu', 'benchmark_proxy.py'))
ENV = {'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'LC_ALL': 'C'}
PROXY_PAYLOAD_LIMIT = 20_000_000_000
PROXY_CHUNK = 64 * 1024
BUILD_HOSTS = frozenset(('registry-1.docker.io', 'auth.docker.io', 'index.docker.io',
                         'production.cloudfront.docker.com', 'production.cloudflare.docker.com',
                         'github.com', 'codeload.github.com', 'snapshot.ubuntu.com'))


def upstream_socket(host, port):
    addresses = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    if not addresses or any(not ipaddress.ip_address(item[4][0]).is_global for item in addresses):
        raise ValueError('nonpublic upstream address')
    for family, kind, protocol, _, address in addresses:
        connection = socket.socket(family, kind, protocol)
        try:
            connection.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, PROXY_CHUNK)
            connection.settimeout(10)
            connection.connect(address)
            return connection
        except OSError:
            connection.close()
    raise ConnectionError('upstream unavailable')


class _ProxyServer(socketserver.ThreadingTCPServer):
    daemon_threads = True
    block_on_close = False
    request_queue_size = 8


class _ConnectHandler(socketserver.BaseRequestHandler):
    def handle(self):
        self.server.owner.handle(self.request)


class BudgetProxy:
    """Opaque CONNECT tunnels; no TLS interception, credentials or body logs.

    Global lock serializes nonblocking reads and charging. Aggregate bytes read
    in BOTH directions can never exceed the cap, even across eight tunnels.
    This caps tunnel payload, not retransmissions/kernel buffers on the wire.
    """
    def __init__(self, *, cap=PROXY_PAYLOAD_LIMIT, connector=upstream_socket):
        self.cap, self.connector = cap, connector
        self.lock = threading.RLock()
        self.slots = threading.BoundedSemaphore(8)
        self.stopped = threading.Event()
        self.sockets = set()
        self.payload_bytes = self.download_bytes = self.upload_bytes = 0
        self.accepted = self.active = self.denied = 0
        self.host_counts, self.denied_hosts = {}, set()
        self.failure = None
        self.closed = False
        self.server = _ProxyServer(('127.0.0.1', 0), _ConnectHandler)
        self.server.owner = self
        self.url = 'http://127.0.0.1:' + str(self.server.server_address[1])
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={'poll_interval': .1}, daemon=True)
        self.thread.start()

    def stats(self):
        with self.lock:
            return {'proxy_payload_bytes': self.payload_bytes, 'proxy_download_bytes': self.download_bytes,
                    'proxy_upload_bytes': self.upload_bytes, 'proxy_connections': self.accepted,
                    'proxy_active_tunnels': self.active, 'proxy_denied': self.denied,
                    'proxy_hosts': dict(self.host_counts), 'proxy_denied_hosts': sorted(self.denied_hosts),
                    'proxy_failure': self.failure}

    def trip(self, reason=None):
        with self.lock:
            if reason and self.failure is None:
                self.failure = reason
            self.stopped.set()
            connections = list(self.sockets)
        for connection in connections:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            connection.close()

    def close(self):
        with self.lock:
            if self.closed:
                return
            self.closed = True
        self.trip()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def register(self, connection):
        with self.lock:
            if self.stopped.is_set():
                connection.close()
                return False
            self.sockets.add(connection)
        return True

    def relay_send(self, destination, data):
        view = memoryview(data)
        while view and not self.stopped.is_set():
            if select.select([], [destination], [], .5)[1]:
                try:
                    sent = destination.send(view)
                except BlockingIOError:
                    continue
                if not sent:
                    return False
                view = view[sent:]
        return not view

    def charged_recv(self, source, download):
        with self.lock:
            if self.stopped.is_set():
                return b''
            available = self.cap - self.payload_bytes
            if available <= 0:
                self.trip('proxy_payload_ceiling')
                return b''
            data = source.recv(min(PROXY_CHUNK, available))
            self.payload_bytes += len(data)
            if download:
                self.download_bytes += len(data)
            else:
                self.upload_bytes += len(data)
            if self.payload_bytes == self.cap:
                self.trip('proxy_payload_ceiling')
            return data

    def handle(self, client):
        if not self.slots.acquire(blocking=False):
            self.trip('proxy_tunnel_limit')
            return
        upstream, registered = None, False
        try:
            if not self.register(client):
                return
            client.settimeout(5)
            header = b''
            while b'\r\n\r\n' not in header and len(header) <= 8192:
                block = client.recv(min(1024, 8193 - len(header)))
                if not block:
                    return
                header += block
            if len(header) > 8192 or not header.endswith(b'\r\n\r\n'):
                raise ValueError('proxy_header_invalid')
            lines = header.decode('ascii').split('\r\n')
            match = re.fullmatch(r'CONNECT ([a-zA-Z0-9.-]+):443 HTTP/1\.[01]', lines[0])
            if not match or any(line.lower().startswith(('authorization:', 'proxy-authorization:')) for line in lines[1:]):
                raise ValueError('proxy_requires_credential_free_https_connect')
            host = match[1].lower()
            if host not in BUILD_HOSTS:
                with self.lock:
                    self.denied_hosts.add(host[:253])
                raise ValueError('proxy_host_denied')
            upstream = self.connector(host, 443)
            if not self.register(upstream):
                return
            with self.lock:
                self.accepted += 1
                self.active += 1
                self.host_counts[host] = self.host_counts.get(host, 0) + 1
                registered = True
            client.sendall(b'HTTP/1.1 200 Connection Established\r\n\r\n')
            client.setblocking(False)
            upstream.setblocking(False)
            while not self.stopped.is_set():
                readable, _, _ = select.select([client, upstream], [], [], .5)
                for source in readable:
                    try:
                        data = self.charged_recv(source, source is upstream)
                    except BlockingIOError:
                        continue
                    if not data or not self.relay_send(client if source is upstream else upstream, data):
                        return
        except (OSError, ValueError) as error:
            if not self.stopped.is_set():
                with self.lock:
                    self.denied += 1
                # Exceptions may contain signed URLs: emit only a fixed reason.
                self.trip('proxy_request_or_upstream_failed')
        finally:
            with self.lock:
                self.sockets.discard(client)
                if upstream is not None:
                    self.sockets.discard(upstream)
                if registered:
                    self.active -= 1
            for connection in (client, upstream):
                if connection is not None:
                    connection.close()
            self.slots.release()


def build_environment(proxy_url, run):
    # Deliberate minimal environment: ALL_PROXY/NO_PROXY variants and caller
    # credentials/config overrides are absent. Official --http-proxy=true passes
    # these four values into RUN; this is not a host network enforcement rule.
    return {**ENV, 'HTTP_PROXY': proxy_url, 'HTTPS_PROXY': proxy_url,
            'http_proxy': proxy_url, 'https_proxy': proxy_url, 'TMPDIR': str(run / 'tmp')}


def checked_path(path):
    path = Path(os.path.abspath(path))
    if path.is_symlink() or any(parent.is_symlink() for parent in path.parents):
        raise ValueError('symlink path refused')
    return path


def exclusive(path):
    return os.fdopen(os.open(checked_path(path), os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600), 'w')


def write_json(path, value):
    with exclusive(path) as stream:
        json.dump(value, stream, sort_keys=True, allow_nan=False)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())


def command(args, timeout=5):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=timeout, env=ENV).stdout


def default_interfaces():
    devices = set()
    for row in Path('/proc/net/route').read_text().splitlines()[1:]:
        fields = row.split()
        if len(fields) >= 8 and fields[1] == '00000000' and int(fields[3], 16) & 1:
            devices.add(fields[0])
    ipv6 = Path('/proc/net/ipv6_route')
    if ipv6.exists():
        for row in ipv6.read_text().splitlines():
            fields = row.split()
            if (len(fields) >= 10 and fields[0] == '0' * 32 and fields[1] == '00'
                    and int(fields[8], 16) & 1 and not int(fields[8], 16) & 0x200):
                devices.add(fields[9])
    if not devices or any(not re.fullmatch(r'[A-Za-z0-9_.:-]+', device) for device in devices):
        raise ValueError('default interfaces unavailable')
    return tuple(sorted(devices))


def rx_bytes(device):
    return int((Path('/sys/class/net') / device / 'statistics/rx_bytes').read_text())


def mem_available():
    for line in Path('/proc/meminfo').read_text().splitlines():
        if line.startswith('MemAvailable:'):
            return int(line.split()[1]) * 1024
    raise ValueError('MemAvailable absent')


def store_size():
    # Count all store growth, not merely the final image. Timeout fails closed.
    # du defaults to allocated bytes and does not traverse symlink targets.
    return int(command(['du', '-sx', '--block-size=1', str(STORE)], timeout=4).split()[0])


def sample(devices):
    if default_interfaces() != devices:
        raise ValueError('default interfaces changed')
    counters = {device: rx_bytes(device) for device in devices}
    return {'timestamp': time.time(), 'rx_bytes': sum(counters.values()), 'rx_by_interface': counters,
            'root_free_bytes': shutil.disk_usage('/').free,
            'mem_available_bytes': mem_available(), 'store_bytes': store_size()}


class Limits:
    def __init__(self, baseline, monotonic_start):
        self.baseline, self.start, self.low_mem_since = baseline, monotonic_start, None

    def reason(self, current, now, log_bytes=0):
        if now - self.start >= BUILD_DEADLINE:
            return 'build_deadline'
        if current['rx_bytes'] < self.baseline['rx_bytes']:
            return 'rx_counter_reset'
        for device, value in self.baseline.get('rx_by_interface', {}).items():
            if current['rx_by_interface'][device] < value:
                return 'rx_counter_reset'
        if self.ingress(current) >= RX_LIMIT:
            return 'non_model_transfer_ceiling'
        if current['store_bytes'] - self.baseline['store_bytes'] >= STORE_STOP:
            return 'image_store_growth_ceiling'
        if self.baseline['root_free_bytes'] - current['root_free_bytes'] >= STORE_STOP:
            return 'root_allocated_growth_ceiling'
        if current['root_free_bytes'] < ROOT_STOP:
            return 'root_free_floor'
        if current.get('proxy_failure'):
            return current['proxy_failure']
        if 'proxy_download_bytes' in current:
            ingress = self.ingress(current)
            accounted = current['proxy_download_bytes']
            if ingress - accounted > max(256 * 1024 ** 2, accounted // 10):
                return 'unattributed_ingress_or_proxy_bypass'
        if log_bytes >= LOG_LIMIT:
            return 'build_log_ceiling'
        if current['mem_available_bytes'] < MEM_FLOOR:
            if self.low_mem_since is None:
                self.low_mem_since = now
            if now - self.low_mem_since >= 30:
                return 'host_available_memory'
        else:
            self.low_mem_since = None
        return None

    def ingress(self, current):
        return (current['rx_bytes'] - self.baseline['rx_bytes']
                + self.baseline.get('previous_attempt_ingress_bytes', 0))


def stop_owned_group(process, *, killpg=os.killpg):
    """Only the Popen child started with start_new_session=True is eligible."""
    if process.poll() is not None:
        return
    if process.pid <= 1 or process.pid == os.getpgrp():
        raise ValueError('invalid owned process group')
    try:
        killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        try:
            killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait(timeout=10)


def copy_context(source, context):
    source = checked_path(source)
    context.mkdir(mode=0o700)
    hashes = {}
    for relative in FILES:
        original = checked_path(source / relative)
        if not original.is_file() or original.stat().st_size > 1024 ** 2:
            raise ValueError('missing or oversized allowlisted source')
        destination = context / relative
        destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        data = original.read_bytes()
        with exclusive(destination) as stream:
            stream.write(data.decode('utf-8'))
        hashes[relative] = hashlib.sha256(data).hexdigest()
    copied = {str(path.relative_to(context)) for path in context.rglob('*') if path.is_file()}
    if copied != set(FILES):
        raise ValueError('unexpected build context')
    return hashes


def validate_lock(lock):
    build = lock['build']
    if (lock.get('schema_version') != 1 or build['platform'] != 'linux/amd64'
            or build['max_cpus'] != 4 or build['max_memory_bytes'] != 12 * GIB
            or build['cuda_architectures'] != ['75']
            or not re.fullmatch(r'[a-f0-9]{40}', lock['source']['commit'])
            or not re.fullmatch(r'\d{8}T\d{6}Z', build['ubuntu_snapshot'])):
        raise ValueError('build lock differs from reviewed resource/architecture scope')
    for group in ('build_packages', 'runtime_packages'):
        if not build[group] or any(not re.fullmatch(r'[a-z0-9.+-]+=[A-Za-z0-9.:+~_-]+', value) for value in build[group]):
            raise ValueError('unversioned package input')
    for field in ('builder_image', 'runtime_image'):
        if not re.fullmatch(r'docker.io/nvidia/cuda@sha256:[a-f0-9]{64}', build[field]):
            raise ValueError('unpinned base image')


def local_tag(lock_sha256):
    if not re.fullmatch(r'[0-9a-f]{64}', lock_sha256):
        raise ValueError('invalid lock identity')
    return 'localhost/local-inference-benchmark:reviewed-sm75-' + lock_sha256[:12]


def build_command(lock, run, lock_sha256=None):
    validate_lock(lock)
    build = lock['build']
    lock_sha256 = lock_sha256 or hashlib.sha256(json.dumps(lock, sort_keys=True).encode()).hexdigest()
    return ['podman', '--root', str(STORE), 'build', '--cpu-period=100000', '--cpu-quota=400000', '--jobs=1',
            '--memory=12g', '--memory-swap=12g',
            '--platform=linux/amd64', '--layers=false', '--force-rm', '--network=host', '--tls-verify=true', '--http-proxy=true',
            '--tag', local_tag(lock_sha256),
            '--authfile', str(run / 'auth.json'), '--iidfile', str(run / 'image.iid'),
            '--build-arg', 'LLAMA_COMMIT=' + lock['source']['commit'],
            '--build-arg', 'UBUNTU_SNAPSHOT=' + build['ubuntu_snapshot'],
            '--build-arg', 'BUILD_PACKAGES=' + ' '.join(build['build_packages']),
            '--build-arg', 'RUNTIME_PACKAGES=' + ' '.join(build['runtime_packages']),
            '--file', str(run / 'context' / FILES[0]), str(run / 'context')]


def validate_containerfile(path, lock):
    text = path.read_text()
    identities = re.findall(r'^FROM --platform=linux/amd64 (\S+)', text, re.M)
    normalized = [re.sub(r':[^/@]+@', '@', identity) for identity in identities]
    if normalized != [lock['build']['builder_image'], lock['build']['runtime_image']]:
        raise ValueError('Containerfile bases differ from lock')
    if lock['source']['commit'] not in text:
        raise ValueError('Containerfile source differs from lock')


def inspect_identity(iid, tag):
    values = json.loads(command(['podman', '--root', str(STORE), 'image', 'inspect', iid], timeout=10))
    if len(values) != 1:
        raise ValueError('ambiguous image identity')
    image = values[0]
    identity = image.get('Id', '')
    if identity.removeprefix('sha256:') != iid.removeprefix('sha256:'):
        raise ValueError('image inspect ID mismatch')
    if image.get('Architecture') != 'amd64' or image.get('Os') != 'linux':
        raise ValueError('built image platform mismatch')
    if tag not in (image.get('RepoTags') or []):
        raise ValueError('expected local repository tag absent')
    return {'image_id': iid, 'architecture': image['Architecture'], 'os': image['Os'],
            'size_bytes': image.get('Size'), 'digest': image.get('Digest'),
            'local_tag': tag,
            'repo_digests': image.get('RepoDigests') or []}


def previous_attempt(path):
    """One explicit operator-selected CLI-compatibility retry, never automatic.

    Only the exact pre-network unknown--cpus/125 attempt qualifies. Preserve
    original receipts and reservation; a changed reviewed lock is recorded, not
    assumed equal (the registry qualification fix legitimately changes its hash).
    """
    path = checked_path(path)
    if not path.is_dir() or stat.S_IMODE(path.stat().st_mode) != 0o700 or path.stat().st_uid != 0:
        raise ValueError('previous attempt must be a private root-owned directory')
    if (path / 'compatibility-retry-claim.json').exists() or (path / 'image.iid').exists():
        raise ValueError('previous attempt already retried or produced an image identity')
    values, hashes = {}, {}
    for name in ('attempt.json', 'baseline.json', 'outcome.json', 'transfer-reservation.json', 'build.log'):
        receipt = checked_path(path / name)
        if not receipt.is_file() or receipt.stat().st_size > 1024 ** 2:
            raise ValueError('missing or oversized previous-attempt receipt')
        raw = receipt.read_bytes()
        hashes[name] = hashlib.sha256(raw).hexdigest()
        values[name] = raw.decode() if name == 'build.log' else json.loads(raw)
    attempt, outcome = values['attempt.json'], values['outcome.json']
    ingress = outcome.get('default_interface_rx_bytes')
    if (attempt.get('previous_attempt') or attempt.get('status') != 'attempt_consumed_no_automatic_retry'
            or not re.fullmatch(r'[0-9a-f]{64}', attempt.get('lock_sha256', ''))
            or outcome.get('status') != 'stopped' or type(outcome.get('exit_code')) is not int
            or outcome['exit_code'] != 125 or outcome.get('reason') != 'build_nonzero'
            or type(outcome.get('proxy_payload_bytes')) is not int or outcome['proxy_payload_bytes'] != 0
            or type(outcome.get('proxy_connections')) is not int or outcome['proxy_connections'] != 0
            or outcome.get('proxy_failure') is not None
            or outcome.get('proxy_download_bytes', 0) != 0 or outcome.get('proxy_upload_bytes', 0) != 0
            or outcome.get('proxy_hosts', {}) or outcome.get('proxy_denied', 0) != 0
            or type(ingress) is not int or not 0 <= ingress < RX_LIMIT
            or values['build.log'].strip().splitlines() != [
                'Error: unknown flag: --cpus', "See 'podman build --help'"]
            or values['transfer-reservation.json'].get('non_model_reserved_bytes') != TRANSFER_RESERVATION
            or type(values['baseline.json'].get('rx_bytes')) is not int):
        raise ValueError('previous attempt is not the approved zero-network CLI-flag failure')
    return {'path': str(path), 'lock_sha256': attempt['lock_sha256'], 'receipt_sha256': hashes,
            'carried_ingress_bytes': ingress,
            'reservation': 'reuse existing25.1GB non-model reservation; do not add or refund'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-directory', type=Path, required=True)
    parser.add_argument('--source-directory', type=Path, required=True)
    parser.add_argument('--lock', type=Path, required=True)
    parser.add_argument('--lock-sha256', required=True, help='SHA-256 of the exact reviewed lock bytes')
    parser.add_argument('--previous-attempt', type=Path,
                        help='manual reviewed compatibility retry of exact zero-proxy unknown--cpus/125 only')
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise ValueError('GPU-host rootful executor required')
    run = checked_path(args.run_directory)
    permissions = run.stat()
    if (not run.is_dir() or permissions.st_uid != 0 or stat.S_IMODE(permissions.st_mode) != 0o700
            or any(run.iterdir())):
        raise ValueError('caller-created empty root-owned0700 run directory required; no budget retry/reset')
    root_device = Path('/').stat().st_dev
    if run.stat().st_dev != root_device or checked_path('/var/tmp').stat().st_dev != root_device:
        raise ValueError('run and var-tmp must use approved root filesystem')
    raw = checked_path(args.lock).read_bytes()
    if hashlib.sha256(raw).hexdigest() != args.lock_sha256:
        raise ValueError('reviewed lock SHA-256 mismatch')
    lock = json.loads(raw)
    validate_lock(lock)
    prior = previous_attempt(args.previous_attempt) if args.previous_attempt else None
    # Exclusive durable one-shot marker exists before any Podman/network action.
    write_json(run / 'attempt.json', {'started_at': time.time(), 'lock_sha256': args.lock_sha256,
                                     'previous_attempt': prior,
                                     'status': 'attempt_consumed_no_automatic_retry'})
    if prior:
        write_json(Path(prior['path']) / 'compatibility-retry-claim.json',
                   {'next_run_directory': str(run), 'new_lock_sha256': args.lock_sha256,
                    'carried_ingress_bytes': prior['carried_ingress_bytes'], 'claimed_at': time.time()})
    process, proxy, outcome = None, None, {'status': 'stopped', 'reason': 'preflight_or_monitor_failed'}
    def interrupted(signum, frame):
        raise InterruptedError('owned_build_interrupted')
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGHUP, interrupted)
    try:
        write_json(run / 'transfer-reservation.json', {'non_model_reserved_bytes': TRANSFER_RESERVATION,
                   'default_interface_rx_ceiling_bytes': RX_LIMIT, 'overall_ceiling_bytes': 60_000_000_000,
                   'connect_proxy_payload_ceiling_bytes': PROXY_PAYLOAD_LIMIT,
                   'previous_attempt': prior,
                   'reservation_action': 'reuse_existing_not_additional' if prior else 'reserve_once',
                   'remaining_model_transfer_ceiling_bytes': 60_000_000_000 - TRANSFER_RESERVATION,
                   'accounting': 'reservation must seed shared staging transferred_bytes; never refund on failure'})
        hashes = copy_context(args.source_directory, run / 'context')
        validate_containerfile(run / 'context' / FILES[0], lock)
        write_json(run / 'context-sha256.json', hashes)
        write_json(run / 'auth.json', {})
        (run / 'tmp').mkdir(mode=0o700)
        info = json.loads(command(['podman', 'info', '--format', 'json']))
        if (info.get('store', {}).get('graphRoot') != str(STORE)
                or info.get('host', {}).get('security', {}).get('rootless') is not False):
            raise ValueError('unexpected Podman rootful graphRoot')
        if checked_path(STORE).stat().st_dev != Path('/').stat().st_dev:
            raise ValueError('image store must use approved root filesystem')
        devices = default_interfaces()
        baseline = sample(devices)
        baseline['previous_attempt_ingress_bytes'] = prior['carried_ingress_bytes'] if prior else 0
        if baseline['root_free_bytes'] < ROOT_STOP or baseline['mem_available_bytes'] < MEM_FLOOR:
            raise ValueError('insufficient prebuild host headroom')
        write_json(run / 'baseline.json', baseline)
        tag = local_tag(args.lock_sha256)
        exists = subprocess.run(['podman', '--root', str(STORE), 'image', 'exists', tag],
                                capture_output=True, timeout=5, env=ENV)
        if exists.returncode != 1:
            raise ValueError('local tag already exists or cannot verify absence; no automatic retag/retry')
        arguments = build_command(lock, run, args.lock_sha256)
        started = time.monotonic()
        limits = Limits(baseline, started)
        with exclusive(run / 'build.log') as log, exclusive(run / 'telemetry.jsonl') as telemetry:
            proxy = BudgetProxy()
            process = subprocess.Popen(arguments, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                                       env=build_environment(proxy.url, run), cwd=run / 'context', start_new_session=True)
            reason = None
            next_progress = started + 30
            while True:
                sampled = {**sample(devices), **proxy.stats()}
                reason = limits.reason(sampled, time.monotonic(), os.fstat(log.fileno()).st_size)
                telemetry.write(json.dumps({**sampled, 'elapsed_seconds': time.monotonic() - started,
                                            'stop_reason': reason}) + '\n')
                telemetry.flush()
                os.fsync(telemetry.fileno())
                if time.monotonic() >= next_progress:
                    print(json.dumps({'phase': 'image_build', 'status': 'running',
                                      'elapsed_seconds': time.monotonic() - started,
                                      'default_interface_rx_bytes': limits.ingress(sampled),
                                      'image_store_growth_bytes': sampled['store_bytes'] - baseline['store_bytes']}), flush=True)
                    next_progress = time.monotonic() + 30
                if reason:
                    proxy.trip(reason)
                    stop_owned_group(process)
                    break
                if process.poll() is not None:
                    break
                time.sleep(max(0, 5 - (time.monotonic() - started) % 5))
            code = process.wait(timeout=10)
            proxy.close()
            outcome = {'status': 'stopped', 'reason': reason or 'build_nonzero', 'exit_code': code,
                       'default_interface_rx_bytes': limits.ingress(sampled),
                       'current_attempt_default_interface_rx_bytes': sampled['rx_bytes'] - baseline['rx_bytes'],
                       'image_store_growth_bytes': sampled['store_bytes'] - baseline['store_bytes'],
                       'root_allocated_growth_bytes': baseline['root_free_bytes'] - sampled['root_free_bytes'],
                       **proxy.stats(),
                       'elapsed_seconds': time.monotonic() - started}
            if not reason and code == 0:
                if not {'github.com', 'snapshot.ubuntu.com'} <= set(proxy.stats()['proxy_hosts']):
                    outcome['reason'] = 'required_build_clients_not_observed_using_proxy'
                    raise ValueError('proxy_respect_not_verified')
                iid_file = checked_path(run / 'image.iid')
                iid = iid_file.read_text().strip()
                if not re.fullmatch(r'sha256:[a-f0-9]{64}', iid):
                    raise ValueError('invalid final image IID')
                outcome.update(inspect_identity(iid, tag))
                outcome.update({'status': 'built_local_only', 'reason': None})
    except BaseException as error:
        if proxy is not None:
            proxy.close()
        if process is not None:
            stop_owned_group(process)
        outcome.update({'status': 'stopped', 'error_class': type(error).__name__})
    finally:
        if proxy is not None:
            proxy.close()
            outcome.update(proxy.stats())
        if process is not None and process.poll() is None:
            stop_owned_group(process)
        outcome['finished_at'] = time.time()
        outcome['previous_attempt'] = prior
        write_json(run / 'outcome.json', outcome)
    print(json.dumps(outcome, sort_keys=True))
    return 0 if outcome['status'] == 'built_local_only' else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (Exception, KeyboardInterrupt) as error:
        print(json.dumps({'status': 'stopped', 'error_class': type(error).__name__}), file=sys.stderr)
        sys.exit(1)
