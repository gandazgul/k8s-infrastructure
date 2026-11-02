"""No Podman/network/build calls: inspect command bounds and resource stops."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import socket
import socketserver
import subprocess
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('build_image', ROOT / 'build_image.py')
build = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build)
LOCK = json.loads((ROOT / 'artifacts.lock.json').read_text())


class BuildTests(unittest.TestCase):
    def baseline(self):
        return {'rx_bytes': 100, 'store_bytes': 100, 'root_free_bytes': 100 * build.GIB,
                'mem_available_bytes': 30 * build.GIB}

    def test_command_enforces_reviewed_limits_and_never_pushes(self):
        command = build.build_command(LOCK, Path('/private-run'))
        for flag in ('--cpu-period=100000', '--cpu-quota=400000', '--jobs=1', '--memory=12g', '--memory-swap=12g', '--platform=linux/amd64',
                     '--layers=false', '--force-rm', '--network=host', '--tls-verify=true', '--http-proxy=true'):
            self.assertIn(flag, command)
        self.assertNotIn('push', command)
        self.assertNotIn('--privileged', command)
        values = dict(item[2:].split('=', 1) for item in command if item.startswith('--') and '=' in item)
        self.assertEqual(int(values['cpu-quota']) / int(values['cpu-period']), 4)
        self.assertFalse(any(item.startswith('--cpus') for item in command))
        self.assertEqual(command[command.index('--authfile') + 1], '/private-run/auth.json')
        self.assertIn('LLAMA_COMMIT=' + LOCK['source']['commit'], command)
        self.assertIn('BUILD_PACKAGES=' + ' '.join(LOCK['build']['build_packages']), command)
        self.assertTrue(command[command.index('--tag') + 1].startswith('localhost/local-inference-benchmark:reviewed-sm75-'))

    def test_immediate_budget_and_host_stops(self):
        baseline = self.baseline()
        for updates, now, log_size, reason in [
            ({'rx_bytes': 100 + build.RX_LIMIT}, 1, 0, 'non_model_transfer_ceiling'),
            ({'rx_bytes': 99}, 1, 0, 'rx_counter_reset'),
            ({'store_bytes': 100 + build.STORE_LIMIT}, 1, 0, 'image_store_growth_ceiling'),
            ({'root_free_bytes': build.ROOT_FLOOR - 1}, 1, 0, 'root_allocated_growth_ceiling'),
            ({'root_free_bytes': build.ROOT_STOP - 1}, 1, 0, 'root_free_floor'),
            ({}, build.BUILD_DEADLINE, 0, 'build_deadline'),
            ({}, 1, build.LOG_LIMIT, 'build_log_ceiling')]:
            with self.subTest(reason=reason):
                self.assertEqual(build.Limits(baseline, 0).reason({**baseline, **updates}, now, log_size), reason)

    def test_low_memory_requires_sustained30seconds_and_recovers(self):
        baseline = self.baseline()
        limits = build.Limits(baseline, 0)
        low = {**baseline, 'mem_available_bytes': build.MEM_FLOOR - 1}
        self.assertIsNone(limits.reason(low, 1))
        self.assertIsNone(limits.reason(low, 30))
        self.assertIsNone(limits.reason(baseline, 31))
        self.assertIsNone(limits.reason(low, 32))
        self.assertEqual(limits.reason(low, 62), 'host_available_memory')

    def test_all_default_interfaces_counted_without_line_rate_requirement(self):
        routes = ('Iface Destination Gateway Flags RefCnt Use Metric Mask MTU Window IRTT\n'
                  'ens6f0 00000000 01010101 0003 0 0 100 00000000 0 0 0\n'
                  'eno1 00000000 01010101 0003 0 0 600 00000000 0 0 0\n')
        with patch.object(Path, 'read_text', new=lambda path: routes if path.name == 'route' else ''), \
                patch.object(Path, 'exists', return_value=True):
            self.assertEqual(build.default_interfaces(), ('eno1', 'ens6f0'))

    def test_root_temp_growth_and_unattributed_ingress_fail_closed(self):
        baseline = self.baseline()
        current = {**baseline, 'root_free_bytes': baseline['root_free_bytes'] - build.STORE_STOP}
        self.assertEqual(build.Limits(baseline, 0).reason(current, 1), 'root_allocated_growth_ceiling')
        current = {**baseline, 'rx_bytes': baseline['rx_bytes'] + build.GIB, 'proxy_download_bytes': 0}
        self.assertEqual(build.Limits(baseline, 0).reason(current, 1), 'unattributed_ingress_or_proxy_bypass')

    def test_proxy_environment_is_explicit_and_has_no_bypass_variables(self):
        environment = build.build_environment('http://127.0.0.1:12345', Path('/private-run'))
        for key in ('http_proxy', 'https_proxy', 'HTTP_PROXY', 'HTTPS_PROXY'):
            self.assertEqual(environment[key], 'http://127.0.0.1:12345')
        self.assertFalse(any(key.lower() in ('all_proxy', 'no_proxy', 'ftp_proxy') for key in environment))
        self.assertEqual(environment['TMPDIR'], '/private-run/tmp')

    def test_previous_ingress_is_carried_into_transfer_limit(self):
        baseline = {**self.baseline(), 'previous_attempt_ingress_bytes': 15283}
        limits = build.Limits(baseline, 0)
        current = {**baseline, 'rx_bytes': baseline['rx_bytes'] + build.RX_LIMIT - 15283}
        self.assertEqual(limits.ingress(current), build.RX_LIMIT)
        self.assertEqual(limits.reason(current, 1), 'non_model_transfer_ceiling')

    def test_only_exact_zero_network_cli_failure_can_be_manually_retried(self):
        actual_stat = Path.stat
        def root_stat(path, *args, **kwargs):
            fields = list(actual_stat(path, *args, **kwargs))
            fields[4] = 0
            return os.stat_result(fields)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original = {'status': 'stopped', 'reason': 'build_nonzero', 'exit_code': 125,
                        'proxy_payload_bytes': 0, 'proxy_connections': 0, 'proxy_failure': None,
                        'default_interface_rx_bytes': 15283}
            (root / 'attempt.json').write_text(json.dumps({'lock_sha256': 'a' * 64,
                    'status': 'attempt_consumed_no_automatic_retry'}))
            (root / 'baseline.json').write_text(json.dumps({'rx_bytes': 50000}))
            (root / 'transfer-reservation.json').write_text(json.dumps({'non_model_reserved_bytes': build.TRANSFER_RESERVATION}))
            (root / 'build.log').write_text("Error: unknown flag: --cpus\nSee 'podman build --help'\n")
            outcome_path = root / 'outcome.json'
            outcome_path.write_text(json.dumps(original))
            with patch.object(Path, 'stat', new=root_stat):
                prior = build.previous_attempt(root)
                self.assertEqual(prior['carried_ingress_bytes'], 15283)
                self.assertEqual(prior['lock_sha256'], 'a' * 64)
                for changed in ({'proxy_payload_bytes': 1}, {'proxy_connections': 1}, {'exit_code': 1},
                                {'proxy_download_bytes': 1}, {'reason': 'other_failure'}):
                    outcome_path.write_text(json.dumps({**original, **changed}))
                    with self.subTest(changed=changed), self.assertRaises(ValueError):
                        build.previous_attempt(root)
                outcome_path.write_text(json.dumps(original))
                (root / 'build.log').write_text('Error: another problem\n')
                with self.assertRaises(ValueError):
                    build.previous_attempt(root)
                (root / 'build.log').write_text("Error: unknown flag: --cpus\nSee 'podman build --help'\n")
                (root / 'compatibility-retry-claim.json').write_text('{}')
                with self.assertRaises(ValueError):
                    build.previous_attempt(root)

    def test_only_owned_group_term_then_kill_on_timeout(self):
        class Process:
            pid = 987654
            waits = 0
            def poll(self):
                return None
            def wait(self, timeout):
                self.waits += 1
                if self.waits == 1:
                    raise subprocess.TimeoutExpired('owned', timeout)
                return -9
        calls = []
        build.stop_owned_group(Process(), killpg=lambda pid, sig: calls.append((pid, sig)))
        self.assertEqual(calls, [(987654, signal.SIGTERM), (987654, signal.SIGKILL)])
        class Exited(Process):
            def poll(self):
                return 0
        build.stop_owned_group(Exited(), killpg=lambda *args: self.fail('exited process must not be signalled'))

    def test_context_excludes_other_files_and_preserves_hashes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'source'
            for relative in build.FILES:
                path = source / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('synthetic\n')
            (source / 'secret.txt').write_text('must not copy')
            hashes = build.copy_context(source, root / 'context')
            self.assertEqual(set(hashes), set(build.FILES))
            self.assertFalse((root / 'context/secret.txt').exists())
            with self.assertRaises(FileExistsError):
                build.copy_context(source, root / 'context')

    def test_exclusive_receipt_and_symlink_refuse_budget_reset(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            build.write_json(root / 'attempt.json', {'consumed': True})
            with self.assertRaises(FileExistsError):
                build.write_json(root / 'attempt.json', {'consumed': False})
            (root / 'link').symlink_to(root / 'attempt.json')
            with self.assertRaises(ValueError):
                build.checked_path(root / 'link')


class _LocalStub(socketserver.BaseRequestHandler):
    def handle(self):
        try:
            self.request.settimeout(3)
            trigger = self.request.recv(32)
            if trigger:
                self.request.sendall(b'x' * 4096)
            while self.request.recv(32):
                pass
        except OSError:
            pass
        finally:
            with self.server.counter_lock:
                self.server.closed_connections += 1


class ProxyTests(unittest.TestCase):
    def setUp(self):
        self.stub = socketserver.ThreadingTCPServer(('127.0.0.1', 0), _LocalStub)
        self.stub.daemon_threads = True
        self.stub.counter_lock = threading.Lock()
        self.stub.closed_connections = 0
        self.stub_thread = threading.Thread(target=self.stub.serve_forever, kwargs={'poll_interval': .05}, daemon=True)
        self.stub_thread.start()
        self.clients, self.proxies = [], []

    def tearDown(self):
        for proxy in self.proxies:
            proxy.close()
        for client in self.clients:
            client.close()
        self.stub.shutdown()
        self.stub.server_close()
        self.stub_thread.join(2)

    def proxy(self, cap=1024):
        connector = lambda host, port: socket.create_connection(self.stub.server_address, timeout=2)
        proxy = build.BudgetProxy(cap=cap, connector=connector)
        self.proxies.append(proxy)
        return proxy

    def connect(self, proxy, host='github.com', successful=True):
        self.assertEqual(proxy.server.server_address[0], '127.0.0.1')
        client = socket.create_connection(proxy.server.server_address, timeout=2)
        client.settimeout(2)
        self.clients.append(client)
        client.sendall(('CONNECT ' + host + ':443 HTTP/1.1\r\nHost: ' + host + ':443\r\n\r\n').encode())
        response = client.recv(4096)
        if successful:
            self.assertTrue(response.startswith(b'HTTP/1.1 200'), response)
        return client

    def test_denied_host_never_reaches_upstream_and_stops_proxy(self):
        proxy = self.proxy()
        self.connect(proxy, 'not-allowed.invalid', successful=False)
        self.assertTrue(proxy.stopped.wait(1))
        self.assertEqual(proxy.stats()['proxy_connections'], 0)
        self.assertEqual(proxy.stats()['proxy_denied_hosts'], ['not-allowed.invalid'])

    def test_real_two_tunnel_aggregate_cap_never_exceeded(self):
        proxy = self.proxy(cap=256)
        left, right = self.connect(proxy), self.connect(proxy)
        left.sendall(b'start')
        try:
            right.sendall(b'start')
        except OSError:
            pass
        self.assertTrue(proxy.stopped.wait(2))
        stats = proxy.stats()
        self.assertEqual(stats['proxy_payload_bytes'], 256)
        self.assertEqual(stats['proxy_payload_bytes'], stats['proxy_download_bytes'] + stats['proxy_upload_bytes'])
        self.assertEqual(stats['proxy_failure'], 'proxy_payload_ceiling')
        self.assertEqual(stats['proxy_connections'], 2)

    def test_close_cleans_real_owned_upstream_and_listener(self):
        proxy = self.proxy()
        client = self.connect(proxy)
        proxy.close()
        self.assertEqual(client.recv(32), b'')
        end = time.monotonic() + 2
        while proxy.stats()['proxy_active_tunnels'] and time.monotonic() < end:
            time.sleep(.01)
        self.assertEqual(proxy.stats()['proxy_active_tunnels'], 0)
        self.assertFalse(proxy.sockets)
        self.assertIsNone(proxy.stats()['proxy_failure'])

    def test_maximum_eight_live_tunnels(self):
        proxy = self.proxy()
        for _ in range(8):
            self.connect(proxy)
        self.connect(proxy, successful=False)
        self.assertTrue(proxy.stopped.wait(1))
        self.assertEqual(proxy.stats()['proxy_connections'], 8)
        self.assertEqual(proxy.stats()['proxy_failure'], 'proxy_tunnel_limit')


if __name__ == '__main__':
    unittest.main()
