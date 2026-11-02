# Isolated local-inference benchmark

Dormant artifacts only: nothing here is referenced by the production Flux root.
Artifact preparation does not prove CUDA, model compatibility, quality, or
privacy. Building, downloading, applying resources and running these commands
requires the separate concrete experiment approval. No experiment was run while
preparing these files. Do not use the generic container helpers: they publish.

These commands are reviewed lifecycle instructions, **not a run-all script**.
They run on the GPU host through the verified SSH/admin path. Transfer of the
reviewed source to that host, if needed, is a separate explicit operator step.
Use `set -euo pipefail`; never run with shell tracing around credential steps.
Stop at every failed check. Do not install host packages, change runtime/driver
configuration, change production Flux roots, or substitute models/dependencies.

## Inputs and bounds

- Linux/amd64 only; digest-pinned CUDA 12.8.1 builder/runtime; exact llama.cpp
  source and signed Ubuntu snapshot/package roots in `artifacts.lock.json`.
  Snapshot plus base pins fixes transitive resolution; retain the resulting full
  builder/runtime dpkg receipts. CUDA targets SM75; `GGML_NATIVE=OFF` avoids
  compiling incidental builder-host CPU instructions into the image.
- One GPU, one server replica/slot, Recreate, no RuntimeClass override. Use the
  existing native CRI-O CDI/default-crun path. Gate first; no cache directory,
  PV/PVC or model transfer until the gate passes and its pod terminates.
- Server requests 2 CPU/16 GiB, limits 4 CPU/32 GiB. Build limit 4 CPU/12 GiB.
  Do not build while measuring latency. The benchmark-local Python supervisor
  launches llama-server on loopback port 8081 and an authenticated proxy on 8080:
  one active inference/tokenization request, at most two FIFO waiters, 30-second
  queue deadline, 120-second active wall deadline and 16-MiB request-body limit.
  Headers are bounded to 16 KiB/64 headers, connections to 32 handler threads.
  Body upload has an additional five-second absolute read deadline before
  admission. Keepalive, pipelining, chunked requests and Expect/100 are disabled.
  All inference/tokenization/metrics routes require the experiment credential;
  only GET health is public. Fourth concurrent submission returns 503. The
  harness must also enforce output/context limits and stop on failed gates.
- Model/staging budget 60 GiB; net image/build-cache growth 20 GiB; reports and
  temporary evaluation output 2 GiB. Preserve at least 75 GiB root free. Local PV
  capacity is accounting, not a filesystem quota. No YASR, quota reconfiguration,
  broad image pruning, or host recursive ownership changes.
- Total transfer ceiling 60 GB across image/source/package/model transfers;
  model stager accounts only its transfers. Operator must also meter build and
  other transfers and stop before the combined ceiling. Six GPU-hours total;
  preserve the original experiment start/receipts across restarts, never reset
  budgets to continue an incomplete run.
- Monitor host/node/workload health and GPU ownership throughout. Stop for new
  Xid/hardware errors, pressure, competing GPU ownership, root-floor/budget
  breach, temperature at least 85 C for 30 seconds, or host available RAM below
  24 GiB for 30 seconds. `monitor.py` records content-free samples/stop reasons;
  a supervisor/operator must act on its stop file and terminate this experiment.
  It does not stop the Kubernetes server itself. Missing telemetry is a stop.

The two model pairs are `Qwen3.6-27B-Q4_K_M.gguf` with
`mmproj-Qwen3.6-27B-BF16.gguf`, and `Qwen3.5-9B-Q8_0.gguf` with
`mmproj-F16.gguf`. All four exact source revisions, sizes and SHA-256 values
are in the lock. Do not treat the BF16 file as proof of Turing BF16 execution;
test actual projector loading/kernels. Source/model licenses and provenance
must accompany the decision report.

## 1. Preflight and local-only build (after build approval)

Reverify branch/source/root revision, the five-object production inventory,
Ready/pressure/workload baseline, NVMe backing filesystem, available RAM/root
space, no resource-name collision and no GPU/build owner. Record sanitized
evidence. Do not create resources over an existing experiment's resources.

```bash
set -euo pipefail
cd /path/to/reviewed/k8s-infrastructure
BENCHMARK_RUN=$(mktemp -d /var/tmp/local-inference-benchmark.XXXXXXXX)
export BENCHMARK_RUN
chmod 700 "${BENCHMARK_RUN}"
date -u +%Y-%m-%dT%H:%M:%SZ > "${BENCHMARK_RUN}/experiment-start.txt"
kb() { sudo -n kubectl --kubeconfig=/etc/kubernetes/admin.conf --request-timeout=10s "$@"; }
```

Keep `BENCHMARK_RUN` and the experiment start when resuming. Observe root free
bytes, aggregate transfer and image/build-cache net growth during the build;
the CPU/RAM flags alone do not enforce disk/network budgets. Stop the build on
budget breach. Use only this explicit context, containing no `.git`, credentials,
other container projects, or ignored `secrets.env` files:

```bash
python3 - <<'PY'
import json, os, pathlib, shutil, subprocess, tempfile
root = pathlib.Path.cwd()
lock = json.loads((root / 'benchmarks/local-inference/artifacts.lock.json').read_text())
build = lock['build']
run = pathlib.Path(os.environ['BENCHMARK_RUN'])
with tempfile.TemporaryDirectory(prefix='local-inference-build-') as temporary:
    context = pathlib.Path(temporary)
    target = context / 'containers/local-inference'
    target.mkdir(parents=True)
    for name in ('Containerfile', 'cuda-sm75-check.cu', 'benchmark_proxy.py'):
        shutil.copyfile(root / 'containers/local-inference' / name, target / name)
    command = ['sudo', '-n', 'podman', 'build', '--platform=linux/amd64',
               '--cpus=4', '--memory=12g', '--memory-swap=12g',
               '--tag=localhost/local-inference-benchmark:reviewed-sm75',
               '--iidfile=' + str(run / 'image-id.txt'),
               '--build-arg=UBUNTU_SNAPSHOT=' + build['ubuntu_snapshot'],
               '--build-arg=BUILD_PACKAGES=' + ' '.join(build['build_packages']),
               '--build-arg=RUNTIME_PACKAGES=' + ' '.join(build['runtime_packages']),
               '-f', str(target / 'Containerfile'), str(context)]
    subprocess.run(command, check=True)
PY
```

No registry push/login/pull fallback is permitted. A failed build stops the
phase. The build records CMake inputs, source identity/tree digest, full dpkg
closures, license files, and SM75 ELF listings inside
`/opt/local-inference/receipts` and `/opt/local-inference/licenses`.
Capture these and final image inspect/manifest/config identities without running
a GPU workload. Review `llama-server --help` using an explicit
`/opt/local-inference/bin/llama-server` entrypoint before use.
Builder/runtime libc6/libgcc/libstdc++/libgomp versions must match; the image
checks library closure, allowing only the host-injected `libcuda.so.1` to be
absent at build time. Missing additional libraries is a build failure.

**Image gate:** verify CRI-O resolves the exact locally built image and compare
its content identity with the Podman receipt. Image config ID is not the image
manifest digest. Prefer an actually resolvable `local-repository@sha256:...`
pullspec; do not invent a digest or assume Podman and CRI-O share visibility.
Record `sudo -n podman image inspect` and
`sudo -n crictl --runtime-endpoint=unix:///var/run/crio/crio.sock
--image-endpoint=unix:///var/run/crio/crio.sock inspecti EXACT_PULLSPEC` receipts.
If an immutable pullspec is not resolvable, stop for a concrete reviewed local
import/identity-pinning alternative; no implicit publication or mutable-tag
fallback. Both manifests use `imagePullPolicy: Never`.

## 2. Exact offline render

After the image gate, set `BENCHMARK_IMAGE` to that verified immutable pullspec.
The command below renders only the locked model pairs at 4K/8K/16K. The initial
8K candidate is a target, not an acceptance result. Rendering is local-only.

```bash
export BENCHMARK_IMAGE='REPLACE_WITH_VERIFIED_LOCAL_REPOSITORY@sha256:MANIFEST_DIGEST'
python3 - <<'PY'
import os, pathlib, re
root = pathlib.Path('benchmarks/local-inference')
out = pathlib.Path(os.environ['BENCHMARK_RUN']) / 'rendered'
out.mkdir(mode=0o700, exist_ok=True)
image = os.environ['BENCHMARK_IMAGE']
if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9./:_-]*@sha256:[0-9a-f]{64}', image):
    raise SystemExit('verified immutable image pullspec required')
def write(source, name, replacements):
    text = (root / source).read_text()
    for key, value in replacements.items():
        text = text.replace('__' + key + '__', str(value))
    if re.search(r'__[A-Z_]+__', text):
        raise SystemExit('unresolved manifest placeholder')
    (out / name).write_text(text)
write('CudaGate.yaml', 'CudaGate.yaml', {'BENCHMARK_IMAGE': image})
pairs = [
    ('qwen36-27b-q4km', 'Qwen3.6-27B-Q4_K_M.gguf', 'mmproj-Qwen3.6-27B-BF16.gguf'),
    ('qwen35-9b-q80', 'Qwen3.5-9B-Q8_0.gguf', 'mmproj-F16.gguf'),
]
for alias, model, projector in pairs:
    for context in (4096, 8192, 16384):
        write('Server.yaml', f'Server-{alias}-{context}.yaml', {
            'BENCHMARK_IMAGE': image, 'MODEL_FILE': model,
            'PROJECTOR_FILE': projector, 'MODEL_ALIAS': alias,
            'CONTEXT_TOKENS': context,
        })
print(out)
PY
```

Review the rendered diff/resource identities. Do **not** apply this whole
directory: choose one server file only, after the CUDA/storage gates.

## 3. Numerical CUDA gate (before cache creation or staging)

```bash
kb apply -f benchmarks/local-inference/Namespace.yaml
kb apply -f "${BENCHMARK_RUN}/rendered/CudaGate.yaml"
if ! kb -n local-inference-benchmark wait --for=condition=complete job/cuda-sm75-gate --timeout=190s; then
  kb -n local-inference-benchmark logs job/cuda-sm75-gate
  exit 1
fi
kb -n local-inference-benchmark logs job/cuda-sm75-gate > "${BENCHMARK_RUN}/cuda-gate.json"
python3 - <<'PY'
import json, os, pathlib
result = json.loads((pathlib.Path(os.environ['BENCHMARK_RUN']) / 'cuda-gate.json').read_text())
assert result == {'status':'pass', 'device_count':1, 'compute_capability':'7.5',
                  'kernel_arch':750, 'validated_fp32_outputs':1024}
PY
kb -n local-inference-benchmark delete job/cuda-sm75-gate --cascade=foreground --wait=true --timeout=60s
```

The gate validates all 1,024 actual device FP32 matrix outputs against an exact
CPU reference, poisons output first, checks every CUDA call/launch/synchronization,
checks exactly one SM75 device, and checks architecture reported by the executed
kernel. Its nonzero exit, deadline, missing pass JSON or resource-injection error
is a stop, not a reason to test with a different runtime. Verify pod disappearance,
GPU release and host/node health before proceeding. `nvidia-smi` alone is not a
numerical gate. The Job has no retries and a 180-second active deadline.

## 4. Cache and model staging (only after CUDA success)

Create only the new reviewed cache tree. Refuse a preexisting path/symlink until
its ownership/provenance is reviewed; do not reuse or recursively chown it.

```bash
test ! -e /var/lib/local-inference-benchmark
test ! -L /var/lib/local-inference-benchmark
sudo -n install -d -m 0750 -o 10001 -g 10001 /var/lib/local-inference-benchmark
sudo -n install -d -m 0750 -o 10001 -g 10001 /var/lib/local-inference-benchmark/models
kb apply -f benchmarks/local-inference/Storage.yaml
kb -n local-inference-benchmark get pvc/models -o wide
sudo -n python3 benchmarks/local-inference/stage_models.py \
  --lock benchmarks/local-inference/artifacts.lock.json \
  --directory /var/lib/local-inference-benchmark/models \
  --state "${BENCHMARK_RUN}/model-transfer-state.json"
```

Require PVC `models` Bound specifically to PV
`local-inference-benchmark-models`, with the correct node affinity/path and
Retain reclaim policy. The stager accepts only four pinned files, accounts
failed/resume transfers, checks exact byte counts/hashes and atomically renames
verified files. Preserve its state across retries. A failure stops this phase.
Because root staging creates 0600 files, make **only these four verified final
files** readable to the runtime UID; never recurse:

```bash
for model in Qwen3.6-27B-Q4_K_M.gguf mmproj-Qwen3.6-27B-BF16.gguf Qwen3.5-9B-Q8_0.gguf mmproj-F16.gguf; do
  sudo -n chown --no-dereference 10001:10001 "/var/lib/local-inference-benchmark/models/${model}"
  sudo -n chmod 0400 "/var/lib/local-inference-benchmark/models/${model}"
done
```

Serving mounts the PVC read-only and deliberately does not set fsGroup, which
could recursively change ownership of the local volume.

## 5. Secret, one server and authenticated access

Generate a fresh benchmark-only credential without printing it. Do not reuse
production credentials, commit this file, include it in reports, or put the key
in command-line flags/environment variables. Keep the private client file until
evaluation ends, then remove only that named file.

```bash
set +x
python3 - <<'PY'
import os, pathlib, secrets
path = pathlib.Path(os.environ['BENCHMARK_RUN']) / 'api-key'
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as stream:
    stream.write(secrets.token_urlsafe(32) + '\n')
PY
kb -n local-inference-benchmark create secret generic benchmark-api \
  --from-file=api-key="${BENCHMARK_RUN}/api-key"
kb apply -f "${BENCHMARK_RUN}/rendered/Server-qwen35-9b-q80-8192.yaml"
kb -n local-inference-benchmark rollout status deployment/benchmark-runtime --timeout=220s
```

Start one owned localhost-only forwarding process and retain its PID:

```bash
sudo -n kubectl --kubeconfig=/etc/kubernetes/admin.conf -n local-inference-benchmark \
  port-forward --address=127.0.0.1 service/benchmark-runtime 18080:8080 \
  > "${BENCHMARK_RUN}/port-forward.log" 2>&1 &
BENCHMARK_FORWARD_PID=$!
printf '%s\n' "${BENCHMARK_FORWARD_PID}" > "${BENCHMARK_RUN}/port-forward.pid"
```

Wait for the forward to become usable; if it exits or fails, stop. Before
evaluation, verify unauthenticated POST is denied with HTTP 401:

```bash
test "$(curl --silent --show-error --max-time 5 --output /dev/null --write-out '%{http_code}' \
  --header 'Content-Type: application/json' --data '{}' \
  http://127.0.0.1:18080/v1/chat/completions)" = 401
```

Use the harness's API-key **file** option for authenticated requests. Require a
successful authenticated synthetic request too: rejection alone proves no usable
authenticated path. HTTP `/health` is deliberately public for readiness probes;
it is not an authentication test. The manifest disables body/debug logging,
Web UI, slot endpoint/persistence, context shifting, automatic memory fitting,
and prompt reuse; enables metrics; uses F16 K/V, Flash Attention off, all GPU
layers and an explicit matching projector. Model loading may still fail: do not
silently switch quantization/projector, reduce layers, or fall back to CPU.

The proxy relays SSE bytes immediately without buffering the complete response,
including both reasoning and visible-content fields. It closes the backend
socket on the active wall deadline or client disconnect and promptly removes
disconnected FIFO waiters; trailing/pipelined input is rejected rather than
masking a disconnect. Its supervisor sends TERM to only its owned child process
group on shutdown, waits 15 seconds, and escalates only that group if needed.
Neither proxy nor child output logs request bodies, headers or credentials.

**Mandatory actual-runtime cancellation gate:** the pinned server passes
`req.is_connection_closed` to its handlers (`tools/server/server-http.cpp`) and
its response-reader stop path prioritizes cancellation tasks
(`tools/server/server-queue.cpp`). This is static evidence, not proof that this
model/backend stops computing promptly. Before quality work, send a bounded
synthetic streaming request, cancel the client, and verify the actual slot/GPU
work stops and the next admitted request is not queued behind abandoned work.
Repeat at the proxy's active deadline. Record timing and result. Failure is a
stop: remove the named server, preserve evidence, and review cancellation before
continuing. Do not claim socket closure alone proves GPU cancellation.

ClusterIP and localhost forwarding **do not isolate** this API from other pods.
NetworkPolicy enforcement remains unproven. The experiment-only API credential
is mandatory. No Ingress/NodePort/DNS/firewall change or production provider
registration belongs to this benchmark. An optional separately owned SSH tunnel
must bind only 127.0.0.1 and use `ExitOnForwardFailure=yes`; record/stop its PID.

Run the synthetic fixture protocol, screening text/image/tool at each context,
then the full repeated quality/latency/ten-turn/stability protocol. Keep one
selected rendered server at a time. Before changing profiles, stop evaluation,
delete the named Deployment with foreground wait, confirm GPU release, then
apply the next reviewed file; retain the Service/Secret/cache. Do not apply all
six profiles together. Any alternative cache/Flash-Attention/thinking setting
must be separately recorded and compatibility-screened.

## 6. Stop/cleanup and report

On failure, budget exhaustion or completion: stop only this experiment's
evaluation/staging/build/monitor processes by recorded ownership/PIDs; do not
kill unrelated processes. Cancel the owned port-forward (and optional tunnel).
Then remove exactly the named transient resources:

```bash
kb -n local-inference-benchmark delete deployment/benchmark-runtime service/benchmark-runtime job/cuda-sm75-gate \
  --ignore-not-found --cascade=foreground --wait=true --timeout=90s
kb -n local-inference-benchmark delete secret/benchmark-api --ignore-not-found
```

Verify no remaining benchmark pods/GPU owner, no unexpected Xid/pressure and
return to baseline workload health. Remove only the run's `api-key` file after
clients are stopped; retain sanitized results, start/budget state and receipts.
**Preserve namespace/quota/limits, static PV/PVC, model cache and image/build
artifacts by default.** Do not delete the namespace/PV/PVC/cache, run image-store
prunes, or modify NVIDIA/plugin/production resources during cleanup. If cleanup
fails, report it rather than expanding deletion scope.

The decision report must record exact image/source/model/package identities,
all tested flags/context settings, quality by category and repeat, latency
distributions, visible-answer timing, prompt/tool overhead/context fit, actual
peak VRAM/headroom, host impact, transfer/storage/time use, failures and missing
coverage. Incomplete coverage is not acceptance. This direct-runtime benchmark
does not prove OpenClaw routing/attachments or a product Local Model Mode privacy
guarantee; those remain later application/integration approval gates.

## Offline validation

Parse/render all YAML locally; verify reviewed resource identities, no unresolved
placeholders, one GPU/Recreate/read-only mounts, and no production-root changes.
Run the harness's local tests and `git diff --check`. The repository hook checks
staged whitespace/size only and can re-stage files, so do not stage files merely
to invoke it. CUDA compilation and execution are intentionally **not** claimed
by offline checks: they require the separately approved build/GPU gates above.

```bash
python3 -B -m unittest discover -s benchmarks/local-inference/tests -p 'test_*.py' -v
```

`test_proxy.py` uses only ephemeral loopback stub servers to verify API denial,
one-active/two-FIFO admission and fourth-request busy response, fake-clock
30-second queue expiry, scaled active-deadline cancellation, queued disconnect,
byte-preserving early SSE relay, trailing-byte cancellation, body/header limits,
and absence of secret-bearing logs. It is not a real llama/GPU acceptance test.
