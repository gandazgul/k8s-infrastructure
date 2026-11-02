"""Guard ownership/stop checks with fake cluster and telemetry only."""
import argparse
import contextlib
import datetime
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('runtime_guard', ROOT / 'runtime_guard.py')
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)
OWNER = '11111111-1111-1111-1111-111111111111'
POD = '22222222-2222-2222-2222-222222222222'
RS = '33333333-3333-3333-3333-333333333333'
OTHER = '44444444-4444-4444-4444-444444444444'
WORKLOAD = 'deployment/benchmark-runtime'


class FakeCluster:
    def __init__(self):
        self.current = OWNER
        self.deleted = []
        self.healthy = True
        self.child_failure = False

    def resource_uid(self, workload):
        return self.current

    def owned_pods(self, workload, identifier):
        if self.child_failure:
            raise ValueError('fake telemetry failure')
        return {POD}

    def node_healthy(self):
        return self.healthy

    def delete(self, workload, identifier):
        self.deleted.append((workload, identifier))
        self.current = None

    def rows(self, kind, selector=None):
        return []


def sample(**changes):
    value = {'node_healthy': True, 'report_bytes': 0, 'root_free_bytes': 100 * guard.monitor.GIB,
             'mem_available_bytes': 30 * guard.monitor.GIB, 'gpu_temperature_c': 40,
             'unexpected_gpu_processes': 0, 'xid': False}
    value.update(changes)
    return value


class GuardTests(unittest.TestCase):
    def test_uid_changed_refuses_delete_and_matching_uid_deletes_only_named_workload(self):
        cluster = FakeCluster()
        cluster.current = OTHER
        self.assertEqual(guard.stop_owned(cluster, WORKLOAD, OWNER, {POD}), 'refused_uid_changed')
        self.assertEqual(cluster.deleted, [])
        cluster.current = OWNER
        self.assertEqual(guard.stop_owned(cluster, WORKLOAD, OWNER, {POD}), 'deleted')
        self.assertEqual(cluster.deleted, [(WORKLOAD, OWNER)])

    def test_foreground_delete_is_atomic_uid_precondition_not_name_only(self):
        calls = []
        def runner(command, **kwargs):
            calls.append((command, kwargs))
            return argparse.Namespace(stdout='{}')
        guard.Cluster(runner).delete(WORKLOAD, OWNER)
        command, options = calls[0]
        self.assertEqual(command[0], '/usr/sbin/kubectl')
        self.assertIn('--raw=/apis/apps/v1/namespaces/local-inference-benchmark/deployments/benchmark-runtime', command)
        self.assertEqual(json.loads(options['input']), {
            'apiVersion': 'v1', 'kind': 'DeleteOptions', 'preconditions': {'uid': OWNER},
            'propagationPolicy': 'Foreground'})
        self.assertNotIn('Secret', options['input'])

    def test_deployment_replicaset_pod_chain_and_misownership(self):
        cluster = guard.Cluster()
        rows = {'replicasets': [(RS, [('Deployment', OWNER)])], 'pods': [(POD, [('ReplicaSet', RS)])]}
        cluster.rows = lambda kind, selector: rows[kind]
        self.assertEqual(cluster.owned_pods(WORKLOAD, OWNER), {POD})
        rows['pods'] = [(POD, [('ReplicaSet', OTHER)])]
        with self.assertRaises(ValueError):
            cluster.owned_pods(WORKLOAD, OWNER)
        rows['replicasets'] = [(RS, [('Deployment', OTHER)])]
        with self.assertRaises(ValueError):
            cluster.owned_pods(WORKLOAD, OWNER)

    def test_job_requires_direct_owner_uid(self):
        cluster = guard.Cluster()
        cluster.rows = lambda *_: [(POD, [('Job', OWNER)])]
        self.assertEqual(cluster.owned_pods('job/cuda-sm75-gate', OWNER), {POD})
        cluster.rows = lambda *_: [(POD, [('Job', OTHER)])]
        with self.assertRaises(ValueError):
            cluster.owned_pods('job/cuda-sm75-gate', OWNER)

    def test_exact_cgroup_uid_hyphen_underscore_no_substring_or_foreign_pid(self):
        with tempfile.TemporaryDirectory() as temporary:
            proc = Path(temporary)
            for pid, text in [(12, '0::/kubepods/burstable/pod' + POD + '/crio.scope\n'),
                              (13, '0::/kubepods.slice/kubepods-burstable-pod' + POD.replace('-', '_') + '.slice/crio.scope\n'),
                              (14, '0::/kubepods/pod' + POD + '0/crio.scope\n'),
                              (15, '0::/kubepods/pod' + OTHER + '/crio.scope\n')]:
                (proc / str(pid)).mkdir()
                (proc / str(pid) / 'cgroup').write_text(text)
            self.assertTrue(guard.pid_is_owned(12, {POD}, proc))
            self.assertTrue(guard.pid_is_owned(13, {POD}, proc))
            self.assertFalse(guard.pid_is_owned(14, {POD}, proc))
            self.assertFalse(guard.pid_is_owned(15, {POD}, proc))
            self.assertEqual({12, 13, 14, 15, 999} - guard.OwnedGpuPids({POD}, proc), {14, 15, 999})

    def test_immediate_and_sustained_thresholds_and_common_deadline(self):
        for changes, expected in [({'node_healthy': False}, 'node_unhealthy'),
                                  ({'report_bytes': guard.REPORT_LIMIT}, 'report_budget'),
                                  ({'root_free_bytes': 74 * guard.monitor.GIB}, 'root_floor'),
                                  ({'xid': True}, 'new_xid'),
                                  ({'unexpected_gpu_processes': 1}, 'unexpected_gpu_owner')]:
            self.assertEqual(guard.evaluate_sample(sample(**changes), guard.monitor.Thresholds(), 0, 0, 1), expected)
        thresholds = guard.monitor.Thresholds()
        self.assertIsNone(guard.evaluate_sample(sample(gpu_temperature_c=85), thresholds, 0, 0, 1))
        self.assertEqual(guard.evaluate_sample(sample(gpu_temperature_c=85), thresholds, 30, 0, 31), 'gpu_temperature')
        thresholds = guard.monitor.Thresholds()
        self.assertIsNone(guard.evaluate_sample(sample(mem_available_bytes=23 * guard.monitor.GIB), thresholds, 0, 0, 1))
        self.assertEqual(guard.evaluate_sample(sample(mem_available_bytes=23 * guard.monitor.GIB), thresholds, 30, 0, 31), 'host_memory')
        self.assertEqual(guard.evaluate_sample(sample(), guard.monitor.Thresholds(), 0, 0, 21600), 'gpu_wall_budget')

    def run_guard(self, mode):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            args = argparse.Namespace(workload=WORKLOAD, run_directory=directory, output=directory/'guard.jsonl',
                                      stop_file=directory/'stop.json', finish_file=directory/'finish',
                                      experiment_start=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                                      gpu_uuid='GPU-aaaa-bbbb', interval=0.1)
            cluster, event = FakeCluster(), threading.Event()
            def gpu(*_):
                if mode == 'finish':
                    args.finish_file.touch()
                if mode == 'telemetry':
                    raise ValueError('synthetic telemetry failure')
                return {'gpu_temperature_c': 40, 'unexpected_gpu_processes': 0}
            if mode == 'signal':
                event.set()
            if mode == 'pressure':
                cluster.healthy = False
            if mode == 'child_failure':
                cluster.child_failure = True
            stream = io.StringIO()
            with contextlib.redirect_stdout(stream), contextlib.redirect_stderr(stream), \
                 patch.object(guard.monitor, 'gpu_sample', side_effect=gpu), \
                 patch.object(guard.monitor, 'new_xid', return_value=False), \
                 patch.object(guard.monitor, 'memory_available', return_value=40*guard.monitor.GIB), \
                 patch.object(guard.shutil, 'disk_usage', return_value=argparse.Namespace(free=100*guard.monitor.GIB)):
                result = guard.guard(args, cluster, event)
            self.assertEqual(stream.getvalue(), '')
            self.assertEqual(cluster.deleted, [(WORKLOAD, OWNER)])
            final = json.loads(args.output.read_text().splitlines()[-1])
            self.assertEqual(final['cleanup'], 'deleted')
            self.assertEqual(args.stop_file.exists(), mode != 'finish')
            return result, final

    def test_only_explicit_finish_returns_zero_and_still_cleans_up(self):
        result, final = self.run_guard('finish')
        self.assertEqual((result, final['reason']), (0, 'explicit_finish'))

    def test_signal_pressure_and_telemetry_failure_stop_owned_workload(self):
        for mode, reason in [('signal', 'guard_signal'), ('pressure', 'node_unhealthy'),
                             ('telemetry', 'telemetry_unavailable'), ('child_failure', 'telemetry_unavailable')]:
            with self.subTest(mode=mode):
                result, final = self.run_guard(mode)
                self.assertEqual((result, final['reason']), (1, reason))

    def test_private_paths_reject_symlink_escape_and_shared_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with self.assertRaises(ValueError):
                guard.safe_paths(directory, [directory/'..'/'escape'])
            (directory/'link').symlink_to('/tmp')
            with self.assertRaises(ValueError):
                guard.safe_paths(directory, [directory/'link'/'output'])
            os.chmod(directory, 0o755)
            with self.assertRaises(ValueError):
                guard.safe_paths(directory, [directory/'out'])


if __name__ == '__main__':
    unittest.main()
