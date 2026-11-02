#!/usr/bin/env python3
"""Content-free host monitor; writes a scoped stop file, never remedies the host.

Run on the GPU host, not the Gateway VM. Thresholds are experiment ceilings,
not general hardware recommendations. Existing workload health must also be
checked by the operator; this script cannot prove cluster/service health.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

GIB = 1024 ** 3


def timestamp(value):
    result = datetime.datetime.fromisoformat(value.replace('Z', '+00:00'))
    if result.tzinfo is None:
        raise ValueError('timezone required')
    return result.timestamp()


def command(args):
    return subprocess.run(args, capture_output=True, text=True, timeout=5,
                          check=True, env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'}).stdout


def memory_available(path=Path('/proc/meminfo')):
    for line in path.read_text().splitlines():
        if line.startswith('MemAvailable:'):
            return int(line.split()[1]) * 1024
    raise ValueError('MemAvailable unavailable')


def gpu_sample(uuid, allowed_pids):
    raw = command(['nvidia-smi', '-i', uuid,
                   '--query-gpu=uuid,temperature.gpu,memory.used,memory.total,utilization.gpu,power.draw',
                   '--format=csv,noheader,nounits'])
    rows = [line.split(',') for line in raw.strip().splitlines()]
    if len(rows) != 1 or rows[0][0].strip() != uuid:
        raise ValueError('GPU identity mismatch')
    _, temperature, used, total, utilization, power = [item.strip() for item in rows[0]]
    processes = command(['nvidia-smi', '--query-compute-apps=pid,gpu_uuid',
                         '--format=csv,noheader,nounits'])
    pids = set()
    for line in processes.strip().splitlines():
        pid, device = [part.strip() for part in line.split(',')]
        if device == uuid:
            pids.add(int(pid))
    return {'gpu_temperature_c': float(temperature), 'gpu_used_mib': float(used),
            'gpu_total_mib': float(total), 'gpu_utilization_percent': float(utilization),
            'gpu_power_w': float(power), 'gpu_processes': len(pids),
            'unexpected_gpu_processes': len(pids - allowed_pids)}


def new_xid(since):
    # Bounded journal query. Fail closed on unavailable access, never log kernel lines.
    raw = command(['journalctl', '-k', '--since', since, '--no-pager', '-n', '2000', '-o', 'cat'])
    lines = raw.splitlines()
    if len(lines) >= 2000:
        raise ValueError('kernel journal window may be truncated')
    return any(re.search(r'\bNVRM:.*\bXid\b', line) for line in lines)


class Thresholds:
    def __init__(self):
        self.since = {}

    def evaluate(self, sample, now):
        if sample['root_free_bytes'] < 75 * GIB:
            return 'root_floor'
        if sample.get('unexpected_gpu_processes', 0):
            return 'unexpected_gpu_owner'
        if sample.get('xid'):
            return 'new_xid'
        for name, active in [('host_memory', sample['mem_available_bytes'] < 24 * GIB),
                             ('gpu_temperature', sample['gpu_temperature_c'] >= 85)]:
            if active:
                self.since.setdefault(name, now)
                if now - self.since[name] >= 30:
                    return name
            else:
                self.since.pop(name, None)
        return None


def write_stop(path, reason):
    # Exclusive creation: do not overwrite the evaluator/operator's first stop reason.
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as stream:
        json.dump({'stop': reason, 'timestamp': time.time()}, stream)
        stream.write('\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gpu-uuid', required=True)
    parser.add_argument('--allowed-gpu-pid', action='append', type=int, default=[])
    parser.add_argument('--experiment-start', required=True, help='same UTC start as evaluator budget')
    parser.add_argument('--journal', action='store_true', help='required for automated Xid coverage')
    parser.add_argument('--stop-file', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--interval', type=float, default=5)
    args = parser.parse_args()
    if not re.fullmatch(r'GPU-[0-9A-Fa-f-]+', args.gpu_uuid) or not 1 <= args.interval <= 10:
        raise ValueError('invalid monitor profile')
    if any(pid <= 1 for pid in args.allowed_gpu_pid):
        raise ValueError('invalid controlled GPU process')
    started = timestamp(args.experiment_start)
    if started > time.time() + 5:
        raise ValueError('experiment start is in the future')
    for path in (args.stop_file, args.output):
        if path.is_symlink() or any(parent.is_symlink() for parent in path.absolute().parents):
            raise ValueError('symlink output refused')
    thresholds = Thresholds()
    fd = os.open(args.output, os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'a') as output:
        while not args.stop_file.exists():
            if os.fstat(output.fileno()).st_size >= 128 * 1024 ** 2:
                write_stop(args.stop_file, 'monitor_output_budget')
                return 1
            now = time.time()
            reason = None
            try:
                sample = {'timestamp': now, 'mem_available_bytes': memory_available(),
                          'root_free_bytes': shutil.disk_usage('/').free,
                          'xid_coverage': 'journal' if args.journal else 'operator_required'}
                sample.update(gpu_sample(args.gpu_uuid, set(args.allowed_gpu_pid)))
                if args.journal:
                    sample['xid'] = new_xid(args.experiment_start)
                reason = thresholds.evaluate(sample, time.monotonic())
                if now - started >= 6 * 3600:
                    reason = 'gpu_wall_budget'
                sample['stop_reason'] = reason
            except Exception as error:
                sample = {'timestamp': now, 'stop_reason': 'monitor_unavailable',
                          'error_class': type(error).__name__}
                reason = 'monitor_unavailable'
            output.write(json.dumps(sample, sort_keys=True) + '\n')
            output.flush()
            os.fsync(output.fileno())
            if reason:
                write_stop(args.stop_file, reason)
                return 1
            time.sleep(args.interval)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (Exception, KeyboardInterrupt) as error:
        print(json.dumps({'status': 'stopped', 'error_class': type(error).__name__}), file=sys.stderr)
        sys.exit(1)
