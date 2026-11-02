#!/usr/bin/env python3
"""GPU-host safety guard; deletes only its UID-pinned benchmark workload.

No workload spec, environment, prompt, key or kernel log text is recorded.
Run as root on the GPU host. A stop, signal, missing telemetry or explicit
finish always invokes narrowly scoped foreground cleanup. Exit zero means an
explicit finish AND verified cleanup, never merely absence of a stop reason.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import signal
import stat
import subprocess
import sys
import threading
import time

_spec = importlib.util.spec_from_file_location('benchmark_guard_monitor', Path(__file__).with_name('monitor.py'))
monitor = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(monitor)

NAMESPACE = 'local-inference-benchmark'
NODE = 'k8s-control-plane'
WORKLOADS = {
    'job/cuda-sm75-gate': ('Job', 'app.kubernetes.io/name=cuda-sm75-gate',
                         '/apis/batch/v1/namespaces/local-inference-benchmark/jobs/cuda-sm75-gate'),
    'deployment/benchmark-runtime': ('Deployment', 'app.kubernetes.io/name=benchmark-runtime',
                                   '/apis/apps/v1/namespaces/local-inference-benchmark/deployments/benchmark-runtime'),
}
UID_PATTERN = r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
ROWS_PATH = ('{range .items[*]}{.metadata.uid}{"|"}'
             '{range .metadata.ownerReferences[*]}{.kind}{":"}{.uid}{":"}{.controller}{","}{end}'
             '{"\n"}{end}')
REPORT_LIMIT = 2 * monitor.GIB


def uid(value):
    if not re.fullmatch(UID_PATTERN, value):
        raise ValueError('invalid resource UID')
    return value


class Cluster:
    def __init__(self, runner=subprocess.run):
        self.runner = runner

    def command(self, args, body=None, timeout=12):
        result = self.runner(['/usr/sbin/kubectl', '--kubeconfig=/etc/kubernetes/admin.conf',
                              '--request-timeout=8s', *args],
                             input=body, capture_output=True, text=True, check=True,
                             timeout=timeout, env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'})
        if len(result.stdout) > 65536:
            raise ValueError('bounded metadata output exceeded')
        return result.stdout

    def resource_uid(self, workload):
        value = self.command(['-n', NAMESPACE, 'get', workload, '--ignore-not-found=true',
                              '-o=jsonpath={.metadata.uid}']).strip()
        return uid(value) if value else None

    def rows(self, kind, selector=None):
        arguments = ['-n', NAMESPACE, 'get', kind]
        if selector:
            arguments += ['-l', selector]
        raw = self.command([*arguments, '-o=jsonpath=' + ROWS_PATH])
        result = []
        for line in raw.splitlines():
            identifier, references = line.split('|')
            controllers = []
            for reference in references.split(','):
                if reference:
                    owner_kind, owner_uid, controller = reference.split(':')
                    if controller == 'true':
                        controllers.append((owner_kind, uid(owner_uid)))
            result.append((uid(identifier), controllers))
        if len(result) > 64:
            raise ValueError('unexpected benchmark metadata inventory')
        return result

    def owned_pods(self, workload, owner_uid):
        kind, selector, _ = WORKLOADS[workload]
        if kind == 'Deployment':
            owners = set()
            for identifier, references in self.rows('replicasets', selector):
                if references != [('Deployment', owner_uid)]:
                    raise ValueError('unowned ReplicaSet with benchmark label')
                owners.add(identifier)
            parent_kind = 'ReplicaSet'
        else:
            owners, parent_kind = {owner_uid}, 'Job'
        result = set()
        for identifier, references in self.rows('pods', selector):
            if len(references) != 1 or references[0][0] != parent_kind or references[0][1] not in owners:
                raise ValueError('unowned Pod with benchmark label')
            result.add(identifier)
        return result

    def node_healthy(self):
        path = '{range .status.conditions[*]}{.type}{"="}{.status}{"\n"}{end}'
        raw = self.command(['get', 'node', NODE, '-o=jsonpath=' + path])
        conditions = dict(line.split('=', 1) for line in raw.splitlines())
        return (conditions.get('Ready') == 'True' and
                all(conditions.get(name) == 'False' for name in ('DiskPressure', 'MemoryPressure', 'PIDPressure')) and
                conditions.get('NetworkUnavailable', 'False') == 'False')

    def delete(self, workload, owner_uid):
        # UID precondition closes the re-read/delete name replacement race.
        body = json.dumps({'apiVersion': 'v1', 'kind': 'DeleteOptions',
                           'preconditions': {'uid': owner_uid}, 'propagationPolicy': 'Foreground'})
        self.command(['delete', '--raw=' + WORKLOADS[workload][2], '-f', '-'], body=body)


def pid_is_owned(pid, pod_uids, proc=Path('/proc')):
    if type(pid) is not int or pid <= 1:
        return False
    try:
        with (proc / str(pid) / 'cgroup').open() as stream:
            cgroup = stream.read(65537)
        if len(cgroup) > 65536:
            return False
    except (FileNotFoundError, ProcessLookupError):
        return False
    for identifier in pod_uids:
        normalized = uid(identifier).replace('-', '[-_]')
        if re.search(r'(?:^|[/_-])pod' + normalized + r'(?=[/.\n]|$)', cgroup):
            return True
    return False


class OwnedGpuPids:
    """monitor.gpu_sample computes ``observed_pids - allowed_pids``.

    Resolve that difference lazily against precisely the observed GPU PIDs,
    rather than trusting a stale PID allowlist or racing a second GPU query.
    """
    def __init__(self, pod_uids, proc=Path('/proc')):
        self.pod_uids = pod_uids
        self.proc = proc

    def __rsub__(self, observed):
        return {pid for pid in observed if not pid_is_owned(pid, self.pod_uids, self.proc)}


def report_bytes(directory):
    total, entries = 0, 0
    for parent, directories, files in os.walk(directory, followlinks=False):
        for name in directories + files:
            path = Path(parent) / name
            info = path.lstat()
            if stat.S_ISLNK(info.st_mode) or not (stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode)):
                raise ValueError('unsafe report entry')
            total += max(info.st_size, info.st_blocks * 512)
            entries += 1
            if total >= REPORT_LIMIT or entries > 10000:
                return REPORT_LIMIT
    return total


def evaluate_sample(sample, thresholds, now, started, wall):
    if not sample['node_healthy']:
        return 'node_unhealthy'
    if sample['report_bytes'] >= REPORT_LIMIT - 65536:
        return 'report_budget'
    if wall - started >= 6 * 3600:
        return 'gpu_wall_budget'
    return thresholds.evaluate(sample, now)


def stop_owned(cluster, workload, captured_uid, known_pods, clock=time.monotonic, pause=time.sleep):
    deadline = clock() + 60
    current = cluster.resource_uid(workload)
    if current is not None and current != captured_uid:
        return 'refused_uid_changed'
    if current is not None:
        # Failure of child telemetry must not prevent stopping the UID-pinned
        # parent. Kubernetes GC, not a broad label delete, owns its descendants.
        try:
            known_pods.update(cluster.owned_pods(workload, captured_uid))
        except Exception:
            pass
        cluster.delete(workload, captured_uid)
    while True:
        current = cluster.resource_uid(workload)
        if current is not None and current != captured_uid:
            return 'refused_uid_changed'
        if current is None:
            # Only list minimal pod metadata; a replacement's unrelated pods are
            # never deleted. Captured UIDs must actually have disappeared.
            surviving = {identifier for identifier, _ in cluster.rows('pods')}
            if not known_pods.intersection(surviving):
                return 'deleted'
        if clock() >= deadline:
            return 'cleanup_timeout'
        pause(min(0.5, max(0, deadline - clock())))


def safe_paths(directory, paths):
    directory = directory.absolute()
    if not directory.is_dir() or directory.stat().st_mode & 0o077:
        raise ValueError('existing private run directory required')
    for path in [directory, *paths]:
        path = path.absolute()
        if any(part.is_symlink() for part in (path, *path.parents)):
            raise ValueError('symlink path refused')
        path.resolve().relative_to(directory.resolve())
        if path != directory and path.exists() and not path.is_file():
            raise ValueError('nonregular guard path')
    if len({path.resolve() for path in paths}) != len(paths):
        raise ValueError('guard paths must be distinct')


def guard(args, cluster=None, event=None):
    cluster = cluster or Cluster()
    event = event or threading.Event()
    safe_paths(args.run_directory, [args.output, args.stop_file, args.finish_file])
    if args.finish_file.exists():
        raise ValueError('stale finish file refused')
    captured = cluster.resource_uid(args.workload)
    if captured is None:
        raise ValueError('reviewed workload must already exist')
    owned_pods = set()
    output = None
    reason, completed, cleanup = 'guard_unavailable', False, 'not_attempted'
    try:
        fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        output = os.fdopen(fd, 'w')
        def record(value):
            output.write(json.dumps(value, sort_keys=True) + '\n')
            output.flush()
            os.fsync(output.fileno())
        record({'event': 'owned', 'workload': args.workload, 'resource_uid': captured})
        thresholds = monitor.Thresholds()
        started = monitor.timestamp(args.experiment_start)
        if started > time.time() + 5:
            raise ValueError('future experiment start')
        while True:
            if event.is_set():
                reason = 'guard_signal'
                break
            if args.stop_file.exists():
                reason = 'external_stop'
                break
            if cluster.resource_uid(args.workload) != captured:
                reason = 'workload_uid_changed'
                break
            owned_pods.update(cluster.owned_pods(args.workload, captured))
            sample = {'timestamp': time.time(), 'node_healthy': cluster.node_healthy(),
                      'root_free_bytes': shutil.disk_usage('/').free,
                      'mem_available_bytes': monitor.memory_available(),
                      'report_bytes': report_bytes(args.run_directory),
                      'xid': monitor.new_xid(args.experiment_start)}
            sample.update(monitor.gpu_sample(args.gpu_uuid, OwnedGpuPids(owned_pods)))
            reason = evaluate_sample(sample, thresholds, time.monotonic(), started, time.time())
            sample['stop_reason'] = reason
            record(sample)
            if reason:
                break
            if args.finish_file.exists():
                completed, reason = True, 'explicit_finish'
                break
            event.wait(args.interval)
    except Exception as error:
        reason = 'telemetry_unavailable'
        if output is not None:
            try:
                record({'event': 'failure', 'error_class': type(error).__name__})
            except Exception:
                pass
    finally:
        try:
            cleanup = stop_owned(cluster, args.workload, captured, owned_pods)
        except Exception as error:
            cleanup = 'cleanup_failed_' + type(error).__name__
        if not completed:
            try:
                monitor.write_stop(args.stop_file, reason)
            except FileExistsError:
                pass
            except Exception:
                cleanup = 'stop_record_failed_' + cleanup
        if output is not None:
            try:
                record({'event': 'stopped', 'reason': reason, 'cleanup': cleanup})
            except Exception:
                cleanup = 'receipt_failed_' + cleanup
            output.close()
    return 0 if completed and cleanup == 'deleted' else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workload', choices=WORKLOADS, required=True)
    parser.add_argument('--experiment-start', required=True)
    parser.add_argument('--gpu-uuid', required=True)
    parser.add_argument('--run-directory', type=Path, required=True)
    parser.add_argument('--stop-file', type=Path, required=True)
    parser.add_argument('--finish-file', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--interval', type=float, default=1)
    args = parser.parse_args()
    if os.geteuid() != 0 or not 0.1 <= args.interval <= 5 or not re.fullmatch(r'GPU-[0-9A-Fa-f-]+', args.gpu_uuid):
        raise ValueError('root GPU-host guard profile required')
    event = threading.Event()
    for signum in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
        signal.signal(signum, lambda *_: event.set())
    return guard(args, event=event)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception:
        print('{"status":"stopped","stage":"runtime_guard"}', file=sys.stderr)
        sys.exit(1)
