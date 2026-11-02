#!/usr/bin/env python3
"""Stage only reviewed, pinned public HF artifacts. Never called by the server.

State accounts *all* transferred bytes, including failed downloads. A partial
file is resumed only after hashing its prefix against the same pinned HTTPS
object; the verification transfer is charged too. No credentials are accepted.
"""
import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import sys
import urllib.parse
import urllib.request

GIB = 1024 ** 3
TRANSFER_LIMIT = 60_000_000_000
STORAGE_LIMIT = 60 * GIB
ROOT_FLOOR = 75 * GIB
CHUNK = 1024 * 1024


def atomic_json(path, value):
    temporary = path.with_name(path.name + '.tmp')
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as stream:
        json.dump(value, stream, sort_keys=True)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)


def safe_directory(path):
    path = Path(os.path.abspath(path))
    for component in (path, *path.parents):
        if component.is_symlink():
            raise ValueError('symlink directory refused')
    if not path.is_dir():
        raise ValueError('staging directory must already exist')
    return path


def validate_models(lock):
    models = lock.get('models')
    if not isinstance(models, list) or len(models) != 4:
        raise ValueError('exactly four reviewed model artifacts required')
    names = set()
    for model in models:
        if (not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', model['repo'])
                or any(part in ('.', '..') for part in model['repo'].split('/'))):
            raise ValueError('invalid repository')
        if not re.fullmatch(r'[0-9a-f]{40}', model['revision']):
            raise ValueError('revision must be an exact commit')
        source = PurePosixPath(model['path'])
        if (source.is_absolute() or '..' in source.parts or '\\' in model['path']
                or str(source) != model['path'] or not source.parts):
            raise ValueError('unsafe artifact path')
        name = model.get('local_name', source.name)
        if (not re.fullmatch(r'[A-Za-z0-9_.-]+', name) or name in ('.', '..')
                or name.endswith('.part') or name in names):
            raise ValueError('invalid or duplicate local name')
        names.add(name)
        if type(model['bytes']) is not int or model['bytes'] <= 0:
            raise ValueError('invalid artifact size')
        if not re.fullmatch(r'[0-9a-f]{64}', model['sha256']):
            raise ValueError('invalid SHA-256')
        model['local_name'] = name
    if sum(model['bytes'] for model in models) > STORAGE_LIMIT:
        raise ValueError('model storage budget exceeded')
    return models


class TrustedRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        url = urllib.parse.urlsplit(newurl)
        hostname = url.hostname or ''
        if (url.scheme != 'https' or url.username or url.password or url.port not in (None, 443)
                or not (hostname == 'huggingface.co' or hostname.endswith('.huggingface.co')
                        or hostname.endswith('.hf.co'))):
            raise ValueError('untrusted download redirect')
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(CHUNK), b''):
            result.update(block)
    return result.hexdigest()


class Stager:
    def __init__(self, directory, state_path, state, opener=None):
        self.directory = directory
        self.state_path = state_path
        self.state = state
        self.opener = opener or urllib.request.build_opener(urllib.request.ProxyHandler({}), TrustedRedirect())

    def guard(self, additional=0):
        total = 0
        for path in self.directory.iterdir():
            if path.is_symlink():
                raise ValueError('symlink in staging directory')
            if path.is_file():
                total += path.stat().st_size
            else:
                raise ValueError('unexpected subdirectory in staging directory')
        if total + additional > STORAGE_LIMIT:
            raise ValueError('staging storage ceiling')
        # Models must be on the root filesystem, not YASR or a small VM mount.
        if self.directory.stat().st_dev != Path('/').stat().st_dev:
            raise ValueError('staging must use approved root filesystem')
        if shutil.disk_usage('/').free - additional < ROOT_FLOOR:
            raise ValueError('root free-space floor')

    def charged_read(self, response, amount):
        # Reserve before read: interruption can overcount, never undercount.
        remaining = TRANSFER_LIMIT - self.state['transferred_bytes']
        if remaining < amount:
            raise ValueError('network transfer ceiling')
        self.state['transferred_bytes'] += amount
        atomic_json(self.state_path, self.state)
        block = response.read(amount)
        self.state['transferred_bytes'] -= amount - len(block)
        atomic_json(self.state_path, self.state)
        return block

    def stage(self, model):
        final = self.directory / model['local_name']
        partial = final.with_name(final.name + '.part')
        for path in (final, partial):
            if path.is_symlink():
                raise ValueError('symlink artifact refused')
        if final.exists():
            if final.stat().st_size != model['bytes'] or digest(final) != model['sha256']:
                raise ValueError('existing artifact integrity mismatch; manual review required')
            return 'verified'
        offset = partial.stat().st_size if partial.exists() else 0
        if offset > model['bytes']:
            raise ValueError('oversized partial file')
        self.guard(model['bytes'] - offset)
        url = ('https://huggingface.co/' + model['repo'] + '/resolve/' + model['revision'] + '/'
               + urllib.parse.quote(model['path'], safe='/'))
        # Resume does not trust local .part provenance or mutable sidecar metadata.
        # Read the exact immutable remote prefix and compare before appending.
        with contextlib.closing(self.opener.open(url, timeout=30)) as response:
            if response.status != 200:
                raise ValueError('download status refused')
            length = response.headers.get('Content-Length')
            if length is not None and int(length) != model['bytes']:
                raise ValueError('remote byte size mismatch')
            if offset:
                with partial.open('rb') as old:
                    left = offset
                    while left:
                        size = min(CHUNK, left)
                        block = self.charged_read(response, size)
                        if len(block) != size or old.read(size) != block:
                            raise ValueError('partial prefix mismatch; no append performed')
                        left -= size
            fd = os.open(partial, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600)
            with os.fdopen(fd, 'ab') as output:
                received = offset
                while received < model['bytes']:
                    amount = min(CHUNK, model['bytes'] - received)
                    self.guard(amount)
                    block = self.charged_read(response, amount)
                    if not block:
                        raise ValueError('incomplete download; partial retained')
                    output.write(block)
                    output.flush()
                    received += len(block)
                if self.charged_read(response, 1):
                    raise ValueError('oversized download')
                os.fsync(output.fileno())
        if digest(partial) != model['sha256']:
            raise ValueError('SHA-256 mismatch; partial retained for review')
        os.replace(partial, final)
        return 'staged'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lock', type=Path, required=True)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--state', type=Path, required=True,
                        help='persistent shared accounting file; never reset between retries')
    args = parser.parse_args()
    directory = safe_directory(args.directory)
    state_parent = safe_directory(args.state.parent)
    state_path = state_parent / args.state.name
    if state_path.is_symlink():
        raise ValueError('symlink state refused')
    models = validate_models(json.loads(args.lock.read_text()))
    identity = hashlib.sha256(json.dumps(models, sort_keys=True).encode()).hexdigest()
    fd = os.open(str(state_path) + '.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        state = json.loads(state_path.read_text()) if state_path.exists() else {
            'schema_version': 1, 'artifacts': identity, 'transferred_bytes': 0}
        if (state.get('artifacts') != identity or type(state.get('transferred_bytes')) is not int
                or not 0 <= state['transferred_bytes'] <= TRANSFER_LIMIT):
            raise ValueError('accounting state mismatch')
        atomic_json(state_path, state)
        stager = Stager(directory, state_path, state)
        for index, model in enumerate(models):
            status = stager.stage(model)
            print(json.dumps({'artifact_index': index, 'status': status,
                              'transferred_bytes': state['transferred_bytes']}), flush=True)


if __name__ == '__main__':
    try:
        main()
    except (Exception, KeyboardInterrupt) as error:
        # HTTP redirect URLs may contain signed query credentials: never print exceptions.
        print(json.dumps({'status': 'stopped', 'error_class': type(error).__name__}), file=sys.stderr)
        sys.exit(1)
